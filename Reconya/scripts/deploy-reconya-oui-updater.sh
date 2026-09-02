#!/bin/bash

set -Eeuo pipefail
umask 077

readonly expected_hostname='J1-SVMF'
readonly expected_binary_sha256='0f5bdd5c2198f190316595b235f7c2c2fe828632baf320f773bcb5c2f990c4c3'
readonly expected_seed_sha256='e2fa93fcf56ce075e9fc860d47fb7ed1dc35a6e7b2617bea011475d09b804552'
readonly install_dir='/home/pi/reconya'
readonly env_file="$install_dir/.env"
readonly oui_dir="$install_dir/data/oui"
readonly oui_file="$oui_dir/oui.txt"
readonly updater_path='/usr/local/sbin/update-reconya-oui'
readonly service_unit_path='/etc/systemd/system/reconya-oui-update.service'
readonly timer_unit_path='/etc/systemd/system/reconya-oui-update.timer'
readonly backup_dir='/var/backups/reconya-oui-bootstrap-v1'
readonly health_url='http://127.0.0.1:3008/'

bundle_dir=''
mutation_started=0
rollback_running=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    return 1
}

sha256_of() {
    sha256sum -- "$1" | awk '{print $1}'
}

setting_count() {
    local setting_name="$1"

    awk -F= -v name="$setting_name" '$1 == name { count++ } END { print count + 0 }' "$env_file"
}

setting_is_false() {
    local setting_name="$1"

    awk -F= -v name="$setting_name" '
        $1 == name {
            value=$2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            exit !(value == "false")
        }
    ' "$env_file"
}

settings_are_false() {
    awk -F= '
        $1 == "OUI_DOWNLOAD_ENABLED" || $1 == "VENDOR_LOOKUP_ONLINE_ENABLED" {
            value=$2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            count[$1]++
            if (value == "false") valid[$1]++
        }
        END {
            exit !(count["OUI_DOWNLOAD_ENABLED"] == 1 && valid["OUI_DOWNLOAD_ENABLED"] == 1 &&
                count["VENDOR_LOOKUP_ONLINE_ENABLED"] == 1 && valid["VENDOR_LOOKUP_ONLINE_ENABLED"] == 1)
        }
    ' "$env_file"
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

preserve_if_present() {
    local source_path="$1"
    local retained_name="$2"

    if [[ -e $source_path || -L $source_path ]]; then
        mv -- "$source_path" "$backup_dir/$retained_name"
    fi
}

rollback() {
    local original_status=$?

    [[ $rollback_running -eq 0 ]] || exit "$original_status"
    rollback_running=1
    trap - ERR
    [[ $mutation_started -eq 1 ]] || exit "$original_status"
    printf 'ROLLBACK: restoring pre-install ReconYa OUI state\n' >&2

    systemctl disable --now reconya-oui-update.timer >/dev/null 2>&1 || true
    systemctl stop reconya.service || true
    preserve_if_present "$timer_unit_path" failed-reconya-oui-update.timer
    preserve_if_present "$service_unit_path" failed-reconya-oui-update.service
    preserve_if_present "$updater_path" failed-update-reconya-oui
    preserve_if_present "$oui_file" failed-oui.txt
    preserve_if_present "$oui_dir/.oui.txt.bootstrap.new" failed-oui-staging.txt
    cp -a -- "$backup_dir/env.original" "$install_dir/.env.rollback.new"
    mv -- "$install_dir/.env.rollback.new" "$env_file"
    systemctl daemon-reload
    systemctl start reconya.service

    if wait_for_health &&
        [[ ! -e $timer_unit_path && ! -e $service_unit_path && ! -e $updater_path && ! -e $oui_file ]]; then
        printf 'ROLLBACK_OK: original .env restored and OUI updater artifacts retained in %s\n' "$backup_dir" >&2
        exit "$original_status"
    fi
    printf 'MANUAL_INTERVENTION_REQUIRED: OUI updater rollback acceptance failed\n' >&2
    exit 125
}

[[ $# -eq 1 ]] || fail 'usage: deploy-reconya-oui-updater.sh BUNDLE_DIR'
bundle_dir="$1"
[[ $EUID -eq 0 ]] || fail 'must run as root'
[[ $(hostname) == "$expected_hostname" ]] || fail "expected host $expected_hostname"
[[ -d $bundle_dir && ! -L $bundle_dir && $bundle_dir == /* ]] || fail 'bundle directory is unsafe'

for command_name in awk chmod chown cp curl install mv sha256sum sleep systemctl systemd-analyze; do
    command -v "$command_name" >/dev/null || fail "required command not found: $command_name"
done

(
    cd -- "$bundle_dir"
    sha256sum --check --strict BUNDLE-SHA256SUMS
)
[[ $(sha256_of "$bundle_dir/oui.txt") == "$expected_seed_sha256" ]] || fail 'seed checksum mismatch'
/bin/bash "$bundle_dir/update-reconya-oui.sh" validate "$bundle_dir/oui.txt" >/dev/null || fail 'seed validation failed'
[[ $(sha256_of "$install_dir/reconya-linux-arm64") == "$expected_binary_sha256" ]] || fail 'ReconYa binary drifted'
[[ -f $env_file && ! -L $env_file ]] || fail 'live .env is missing or unsafe'
for setting_name in OUI_DOWNLOAD_ENABLED VENDOR_LOOKUP_ONLINE_ENABLED; do
    setting_occurrences="$(setting_count "$setting_name")"
    if [[ $setting_occurrences -ne 0 ]]; then
        if [[ $setting_occurrences -ne 1 ]] || ! setting_is_false "$setting_name"; then
            fail "$setting_name preflight drifted"
        fi
    fi
done
[[ -d $oui_dir && ! -L $oui_dir ]] || fail 'OUI directory is missing or unsafe'
for absent_path in "$oui_file" "$updater_path" "$service_unit_path" "$timer_unit_path" "$backup_dir" \
    "$oui_dir/.oui.txt.bootstrap.new" "$install_dir/.env.oui-bootstrap.new" \
    "$install_dir/.env.rollback.new"; do
    [[ ! -e $absent_path && ! -L $absent_path ]] || fail "reserved path exists: $absent_path"
done
systemctl is-enabled --quiet reconya.service || fail 'ReconYa is not enabled'
health_ok || fail 'ReconYa pre-install health failed'

install -d -m 0700 -- "$backup_dir"
cp -a -- "$env_file" "$backup_dir/env.original"
cp -a -- "$env_file" "$install_dir/.env.oui-bootstrap.new"
{
    if [[ $(setting_count OUI_DOWNLOAD_ENABLED) -eq 0 || $(setting_count VENDOR_LOOKUP_ONLINE_ENABLED) -eq 0 ]]; then
        printf '\n# Repository-managed OUI policy\n'
    fi
    if [[ $(setting_count OUI_DOWNLOAD_ENABLED) -eq 0 ]]; then
        printf 'OUI_DOWNLOAD_ENABLED=false\n'
    fi
    if [[ $(setting_count VENDOR_LOOKUP_ONLINE_ENABLED) -eq 0 ]]; then
        printf 'VENDOR_LOOKUP_ONLINE_ENABLED=false\n'
    fi
} >>"$install_dir/.env.oui-bootstrap.new"
chown --reference="$env_file" "$install_dir/.env.oui-bootstrap.new"
chmod --reference="$env_file" "$install_dir/.env.oui-bootstrap.new"

trap rollback ERR
mv -- "$install_dir/.env.oui-bootstrap.new" "$env_file"
mutation_started=1

install -m 0644 -o root -g root -- "$bundle_dir/oui.txt" "$oui_dir/.oui.txt.bootstrap.new"
mv -- "$oui_dir/.oui.txt.bootstrap.new" "$oui_file"
install -m 0755 -o root -g root -- "$bundle_dir/update-reconya-oui.sh" "$updater_path"
install -m 0644 -o root -g root -- "$bundle_dir/reconya-oui-update.service" "$service_unit_path"
install -m 0644 -o root -g root -- "$bundle_dir/reconya-oui-update.timer" "$timer_unit_path"
systemd-analyze verify "$service_unit_path" "$timer_unit_path"
systemctl daemon-reload
systemctl restart reconya.service
wait_for_health || fail 'ReconYa failed after loading the seed registry'
systemctl enable --now reconya-oui-update.timer

settings_are_false || fail 'live OUI settings failed acceptance'
[[ $(sha256_of "$oui_file") == "$expected_seed_sha256" ]] || fail 'installed seed checksum failed acceptance'
[[ $(sha256_of "$updater_path") == "$(sha256_of "$bundle_dir/update-reconya-oui.sh")" ]] || fail 'updater checksum failed acceptance'
systemctl is-active --quiet reconya-oui-update.timer || fail 'OUI timer is not active'
systemctl is-enabled --quiet reconya-oui-update.timer || fail 'OUI timer is not enabled'
health_ok || fail 'ReconYa final health failed'
[[ -z $(systemctl --failed --no-legend --plain) ]] || fail 'a failed systemd unit remains'

trap - ERR
printf 'ACCEPTED: managed ReconYa OUI seed and monthly updater installed\n'
