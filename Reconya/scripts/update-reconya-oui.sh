#!/bin/bash

set -Eeuo pipefail
umask 077

readonly oui_url='https://standards-oui.ieee.org/oui/oui.txt'
readonly oui_dir='/home/pi/reconya/data/oui'
readonly oui_file="$oui_dir/oui.txt"
readonly previous_file="$oui_dir/oui.txt.previous"
readonly service_name='reconya.service'
readonly health_url='http://127.0.0.1:3008/'
readonly minimum_bytes=5000000
readonly maximum_bytes=10000000
readonly minimum_records=30000
readonly maximum_known_duplicates=3

candidate_file=''
replacement_installed=0
had_current=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    return 1
}

sha256_of() {
    sha256sum -- "$1" | awk '{print $1}'
}

validate_oui() {
    local checked_file="$1"
    local file_bytes

    [[ -f $checked_file && ! -L $checked_file ]] || return 1
    file_bytes="$(stat -c '%s' -- "$checked_file")"
    ((file_bytes >= minimum_bytes && file_bytes <= maximum_bytes)) || return 1

    LC_ALL=C awk -v minimum="$minimum_records" -v maximum_duplicates="$maximum_known_duplicates" '
        index($0, "(hex)") {
            prefix = $1
            if (prefix !~ /^[0-9A-F][0-9A-F]-[0-9A-F][0-9A-F]-[0-9A-F][0-9A-F]$/) {
                malformed++
                next
            }
            gsub(/-/, "", prefix)
            if (seen[prefix]++) {
                duplicate++
                if (prefix != "080030" && prefix != "0001C8") {
                    unexpected_duplicate++
                }
            }
            records++
        }
        END {
            if (records < minimum || malformed || unexpected_duplicate || duplicate > maximum_duplicates) {
                exit 1
            }
            print records
        }
    ' "$checked_file"
}

health_ok() {
    local status_code

    systemctl is-active --quiet "$service_name" || return 1
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

rollback() {
    local original_status=$?
    local failed_file

    trap - ERR
    [[ $replacement_installed -eq 1 ]] || exit "$original_status"

    failed_file="$oui_dir/oui.txt.failed.$(date -u +%Y%m%dT%H%M%SZ)"
    printf 'ROLLBACK: preserving rejected active database at %s\n' "$failed_file" >&2
    systemctl stop "$service_name" || true
    [[ ! -e $failed_file ]] || {
        printf 'MANUAL_INTERVENTION_REQUIRED: rollback residue path exists: %s\n' "$failed_file" >&2
        exit 125
    }
    mv -- "$oui_file" "$failed_file"
    if [[ $had_current -eq 1 ]]; then
        cp -a -- "$previous_file" "$oui_file"
    fi
    systemctl start "$service_name"
    if wait_for_health; then
        printf 'ROLLBACK_OK: prior OUI state restored; failed database retained at %s\n' "$failed_file" >&2
        exit "$original_status"
    fi
    printf 'MANUAL_INTERVENTION_REQUIRED: ReconYa did not recover after OUI rollback\n' >&2
    exit 125
}

if [[ ${1:-} == validate && $# -eq 2 ]]; then
    validate_oui "$2"
    exit
fi
[[ $# -eq 0 ]] || fail 'usage: update-reconya-oui.sh [validate FILE]'
[[ $EUID -eq 0 ]] || fail 'must run as root'
[[ -d $oui_dir && ! -L $oui_dir ]] || fail "OUI directory is missing or unsafe: $oui_dir"

for command_name in awk chmod chown cmp cp curl date flock mktemp mv rm sha256sum stat systemctl; do
    command -v "$command_name" >/dev/null || fail "required command not found: $command_name"
done

exec 9>/run/lock/reconya-oui-update.lock
flock --nonblock 9 || fail 'another OUI update is running'

candidate_file="$(mktemp "$oui_dir/.oui.txt.candidate.XXXXXX")"
readonly candidate_file
cleanup() {
    [[ -n $candidate_file && -e $candidate_file ]] && rm -f -- "$candidate_file"
}
trap cleanup EXIT

curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --connect-timeout 15 --max-time 120 --retry 3 \
    --user-agent 'reconya-oui-updater/1.0' \
    --output "$candidate_file" "$oui_url"

candidate_records="$(validate_oui "$candidate_file")" || fail 'candidate failed OUI structure and size validation'
readonly candidate_records
candidate_sha256="$(sha256_of "$candidate_file")"
readonly candidate_sha256

if [[ -e $oui_file ]]; then
    [[ -f $oui_file && ! -L $oui_file ]] || fail "current OUI database is unsafe: $oui_file"
    current_records="$(validate_oui "$oui_file")" || fail 'current OUI database failed validation'
    readonly current_records
    ((candidate_records * 100 >= current_records * 95)) || fail 'candidate record count dropped by more than five percent'
    if cmp --silent -- "$candidate_file" "$oui_file"; then
        printf 'UNCHANGED: records=%s sha256=%s\n' "$candidate_records" "$candidate_sha256"
        exit
    fi
    previous_staging="$oui_dir/.oui.txt.previous.new"
    readonly previous_staging
    [[ ! -e $previous_staging ]] || fail "previous-file staging path exists: $previous_staging"
    cp -a -- "$oui_file" "$previous_staging"
    mv -f -- "$previous_staging" "$previous_file"
    had_current=1
fi

chmod 0644 -- "$candidate_file"
chown root:root -- "$candidate_file"
trap rollback ERR
mv -- "$candidate_file" "$oui_file"
replacement_installed=1

systemctl restart "$service_name"
wait_for_health || fail 'ReconYa health check failed after OUI update'

trap - ERR
printf 'UPDATED: records=%s sha256=%s\n' "$candidate_records" "$candidate_sha256"
