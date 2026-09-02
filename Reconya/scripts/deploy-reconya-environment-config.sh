#!/bin/bash

set -Eeuo pipefail
umask 077

readonly expected_hostname='J1-SVMF'
readonly expected_binary_sha256='0f5bdd5c2198f190316595b235f7c2c2fe828632baf320f773bcb5c2f990c4c3'
readonly expected_template_sha256='ed9fe8121990169539a47bfd9e55f764d94995c272a26eb2a61913a7ac3b364f'
readonly install_dir='/home/pi/reconya'
readonly env_file="$install_dir/.env"
readonly staging_file="$install_dir/.env.reconcile.new"
readonly backup_dir='/var/backups/reconya-env-v0.26.0-desired-state-v1'
readonly health_url='http://127.0.0.1:3008/'

template_file=''
mutation_started=0
rollback_running=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    return 1
}

sha256_of() {
    sha256sum -- "$1" | awk '{print $1}'
}

health_ok() {
    local status_code

    systemctl is-active --quiet reconya.service || return 1
    status_code="$(curl --silent --show-error --output /dev/null \
        --write-out '%{http_code}' --max-time 5 "$health_url")" || return 1
    [[ $status_code == 200 || $status_code == 302 || $status_code == 303 ]]
}

wait_for_health() {
    local attempt

    for ((attempt = 1; attempt <= 30; attempt++)); do
        health_ok && return 0
        sleep 1
    done
    return 1
}

cleanup() {
    if [[ -e $staging_file || -L $staging_file ]]; then
        rm -f -- "$staging_file"
    fi
}

validate_pre_reconciliation_env() {
    local checked_file="$1"

    awk -F= '
        /^[A-Z][A-Z0-9_]*=/ { count[$1]++ }
        END {
            split("DATABASE_TYPE DATABASE_NAME SQLITE_PATH PORT LOGIN_USERNAME LOGIN_PASSWORD JWT_SECRET_KEY IPV6_MONITORING_ENABLED IPV6_MONITOR_INTERFACES IPV6_MONITOR_INTERVAL IPV6_LINK_LOCAL_MONITORING IPV6_MULTICAST_MONITORING OUI_DOWNLOAD_ENABLED VENDOR_LOOKUP_ONLINE_ENABLED", names, " ")
            for (array_index in names) expected[names[array_index]]=1
            for (name in count) if (!(name in expected) || count[name] != 1) exit 1
            for (name in expected) if (count[name] != 1) exit 1
        }
    ' "$checked_file" || return 1

    grep -Fxq 'DATABASE_TYPE=sqlite' "$checked_file" &&
        grep -Fxq 'SQLITE_PATH=data/reconya.db' "$checked_file" &&
        grep -Fxq 'DATABASE_NAME="reconya-dev"' "$checked_file" &&
        grep -Fxq 'PORT=3008' "$checked_file" &&
        grep -Fxq 'IPV6_MONITORING_ENABLED=true' "$checked_file" &&
        grep -Fxq 'IPV6_MONITOR_INTERFACES=' "$checked_file" &&
        grep -Fxq 'IPV6_MONITOR_INTERVAL=30' "$checked_file" &&
        grep -Fxq 'IPV6_LINK_LOCAL_MONITORING=true' "$checked_file" &&
        grep -Fxq 'IPV6_MULTICAST_MONITORING=false' "$checked_file" &&
        grep -Fxq 'OUI_DOWNLOAD_ENABLED=false' "$checked_file" &&
        grep -Fxq 'VENDOR_LOOKUP_ONLINE_ENABLED=false' "$checked_file" &&
        awk -F= '
            $1 == "LOGIN_USERNAME" || $1 == "LOGIN_PASSWORD" || $1 == "JWT_SECRET_KEY" {
                if (length(substr($0, index($0, "=") + 1)) == 0) exit 1
                found[$1]++
            }
            END { exit !(found["LOGIN_USERNAME"] == 1 && found["LOGIN_PASSWORD"] == 1 && found["JWT_SECRET_KEY"] == 1) }
        ' "$checked_file"
}

validate_desired_env() {
    local checked_file="$1"

    awk -F= '
        /^[A-Z][A-Z0-9_]*=/ { count[$1]++ }
        END {
            split("DATABASE_NAME SQLITE_PATH PORT LOGIN_USERNAME LOGIN_PASSWORD PUBLIC_IP_LOOKUP_ENABLED GEOLOCATION_ENABLED VENDOR_LOOKUP_ONLINE_ENABLED OUI_DOWNLOAD_ENABLED ALERT_OFFLINE_THRESHOLD_HOURS", names, " ")
            for (array_index in names) expected[names[array_index]]=1
            for (name in count) if (!(name in expected) || count[name] != 1) exit 1
            for (name in expected) if (count[name] != 1) exit 1
        }
    ' "$checked_file" || return 1

    grep -Fxq 'DATABASE_NAME="reconya-dev"' "$checked_file" &&
        grep -Fxq 'SQLITE_PATH=data/reconya.db' "$checked_file" &&
        grep -Fxq 'PORT=3008' "$checked_file" &&
        grep -Fxq 'PUBLIC_IP_LOOKUP_ENABLED=false' "$checked_file" &&
        grep -Fxq 'GEOLOCATION_ENABLED=false' "$checked_file" &&
        grep -Fxq 'VENDOR_LOOKUP_ONLINE_ENABLED=false' "$checked_file" &&
        grep -Fxq 'OUI_DOWNLOAD_ENABLED=false' "$checked_file" &&
        grep -Fxq 'ALERT_OFFLINE_THRESHOLD_HOURS=6' "$checked_file" &&
        awk -F= '
            $1 == "LOGIN_USERNAME" || $1 == "LOGIN_PASSWORD" {
                value=substr($0, index($0, "=") + 1)
                if (length(value) == 0 || value ~ /^REPLACE_WITH_/) exit 1
                found[$1]++
            }
            END { exit !(found["LOGIN_USERNAME"] == 1 && found["LOGIN_PASSWORD"] == 1) }
        ' "$checked_file"
}

credential_lines_match() {
    local first_file="$1"
    local second_file="$2"

    cmp --silent \
        <(awk -F= '$1 == "LOGIN_USERNAME" || $1 == "LOGIN_PASSWORD" { print }' "$first_file") \
        <(awk -F= '$1 == "LOGIN_USERNAME" || $1 == "LOGIN_PASSWORD" { print }' "$second_file")
}

rollback() {
    local original_status=$?

    [[ $rollback_running -eq 0 ]] || exit "$original_status"
    rollback_running=1
    trap - ERR
    [[ $mutation_started -eq 1 ]] || exit "$original_status"
    printf 'ROLLBACK: restoring the pre-reconciliation ReconYa environment\n' >&2

    systemctl stop reconya.service || true
    if [[ -e $env_file || -L $env_file ]]; then
        mv -- "$env_file" "$backup_dir/failed-desired-state.env"
    fi
    cp -a -- "$backup_dir/env.original" "$staging_file"
    mv -- "$staging_file" "$env_file"
    systemctl start reconya.service

    if wait_for_health && validate_pre_reconciliation_env "$env_file"; then
        printf 'ROLLBACK_OK: original environment restored from %s\n' "$backup_dir" >&2
        exit "$original_status"
    fi
    printf 'MANUAL_INTERVENTION_REQUIRED: environment rollback acceptance failed\n' >&2
    exit 125
}

if [[ $# -eq 2 && $1 == validate-pre-reconciliation ]]; then
    validate_pre_reconciliation_env "$2"
    exit
fi
if [[ $# -eq 2 && $1 == validate-desired ]]; then
    validate_desired_env "$2"
    exit
fi

[[ $# -eq 1 ]] || fail 'usage: deploy-reconya-environment-config.sh TEMPLATE_FILE'
template_file="$1"
[[ $EUID -eq 0 ]] || fail 'must run as root'
[[ $(hostname) == "$expected_hostname" ]] || fail "expected host $expected_hostname"
[[ -f $template_file && ! -L $template_file && $template_file == /* ]] || fail 'template file is unsafe'

for command_name in awk chown chmod cmp cp curl grep install mv rm sha256sum sleep stat systemctl; do
    command -v "$command_name" >/dev/null || fail "required command not found: $command_name"
done

[[ $(sha256_of "$template_file") == "$expected_template_sha256" ]] || fail 'template checksum mismatch'
[[ $(sha256_of "$install_dir/reconya-linux-arm64") == "$expected_binary_sha256" ]] || fail 'ReconYa binary drifted'
[[ -f $env_file && ! -L $env_file ]] || fail 'live .env is missing or unsafe'
[[ $(stat -c '%a %U:%G' "$env_file") == '600 pi:pi' ]] || fail 'live .env ownership or mode drifted'
[[ ! -e $staging_file && ! -L $staging_file ]] || fail 'environment staging path exists'
[[ ! -e $backup_dir && ! -L $backup_dir ]] || fail 'environment backup path exists'
validate_pre_reconciliation_env "$env_file" || fail 'live .env preflight drifted'
systemctl is-enabled --quiet reconya.service || fail 'ReconYa is not enabled'
health_ok || fail 'ReconYa pre-reconciliation health failed'

trap cleanup EXIT
awk '
    NR == FNR {
        if ($0 ~ /^LOGIN_USERNAME=/) username=$0
        if ($0 ~ /^LOGIN_PASSWORD=/) password=$0
        next
    }
    $0 == "LOGIN_USERNAME=REPLACE_WITH_LOGIN_USERNAME" { print username; next }
    $0 == "LOGIN_PASSWORD=REPLACE_WITH_STRONG_PASSWORD" { print password; next }
    { print }
    END { if (username == "" || password == "") exit 1 }
' "$env_file" "$template_file" >"$staging_file"
chown --reference="$env_file" "$staging_file"
chmod --reference="$env_file" "$staging_file"
validate_desired_env "$staging_file" || fail 'candidate .env failed desired-state validation'
credential_lines_match "$env_file" "$staging_file" || fail 'candidate changed a credential line'

install -d -m 0700 -- "$backup_dir"
cp -a -- "$env_file" "$backup_dir/env.original"
install -m 0600 -o root -g root -- "$template_file" "$backup_dir/desired-template"
trap rollback ERR
mv -- "$staging_file" "$env_file"
mutation_started=1
systemctl restart reconya.service
wait_for_health || fail 'ReconYa failed after environment reconciliation'

validate_desired_env "$env_file" || fail 'live .env failed desired-state acceptance'
credential_lines_match "$backup_dir/env.original" "$env_file" || fail 'live credential lines changed'
[[ $(sha256_of "$install_dir/reconya-linux-arm64") == "$expected_binary_sha256" ]] || fail 'binary changed during reconciliation'
systemctl is-enabled --quiet reconya.service || fail 'ReconYa is no longer enabled'
[[ -z $(systemctl --failed --no-legend --plain) ]] || fail 'a failed systemd unit remains'
health_ok || fail 'ReconYa final health failed'

trap - ERR
printf 'ACCEPTED: ReconYa environment reconciled to the repository desired state\n'
