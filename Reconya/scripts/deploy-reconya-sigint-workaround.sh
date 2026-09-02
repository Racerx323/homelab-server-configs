#!/bin/bash

set -Eeuo pipefail
umask 077

readonly expected_hostname='J1-SVMF'
readonly expected_binary_sha256='0f5bdd5c2198f190316595b235f7c2c2fe828632baf320f773bcb5c2f990c4c3'
readonly old_unit_sha256='6f600cd2bacc70f9d27342299607126d37b72b9ef0ef81fe8dce66e19c42ca31'
readonly new_unit_sha256='16b99c17b21b0553e1eaeee74720a6429466588ae7d031967ff8b4d344bb8a6e'
readonly unit_path='/etc/systemd/system/reconya.service'
readonly staging_path='/etc/systemd/system/.reconya.service.sigint.new'
readonly rollback_staging_path='/etc/systemd/system/.reconya.service.rollback.new'
readonly backup_dir='/var/backups/reconya-sigint-workaround-v1'
readonly binary_path='/home/pi/reconya/reconya-linux-arm64'
readonly health_url='http://127.0.0.1:3008/'

candidate_unit=''
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
    for cleanup_path in "$staging_path" "$rollback_staging_path"; do
        if [[ -e $cleanup_path || -L $cleanup_path ]]; then
            rm -f -- "$cleanup_path"
        fi
    done
}

rollback() {
    local original_status=$?

    [[ $rollback_running -eq 0 ]] || exit "$original_status"
    rollback_running=1
    trap - ERR
    [[ $mutation_started -eq 1 ]] || exit "$original_status"
    printf 'ROLLBACK: restoring the prior ReconYa systemd unit\n' >&2

    cp -a -- "$unit_path" "$backup_dir/failed-sigint-unit"
    install -m 0644 -o root -g root -- "$backup_dir/reconya.service.original" "$rollback_staging_path"
    mv -- "$rollback_staging_path" "$unit_path"
    systemctl daemon-reload
    systemctl restart reconya.service

    if [[ $(sha256_of "$unit_path") == "$old_unit_sha256" ]] && wait_for_health; then
        printf 'ROLLBACK_OK: prior unit restored from %s\n' "$backup_dir" >&2
        exit "$original_status"
    fi
    printf 'MANUAL_INTERVENTION_REQUIRED: unit rollback acceptance failed\n' >&2
    exit 125
}

[[ $# -eq 1 ]] || fail 'usage: deploy-reconya-sigint-workaround.sh CANDIDATE_UNIT'
candidate_unit="$1"
[[ $EUID -eq 0 ]] || fail 'must run as root'
[[ $(hostname) == "$expected_hostname" ]] || fail "expected host $expected_hostname"
[[ -f $candidate_unit && ! -L $candidate_unit && $candidate_unit == /* ]] || fail 'candidate unit is unsafe'

for command_name in awk cp curl date grep install journalctl mv rm sha256sum sleep systemctl systemd-analyze; do
    command -v "$command_name" >/dev/null || fail "required command not found: $command_name"
done

[[ $(sha256_of "$candidate_unit") == "$new_unit_sha256" ]] || fail 'candidate unit checksum mismatch'
[[ $(sha256_of "$unit_path") == "$old_unit_sha256" ]] || fail 'live unit preflight drifted'
[[ $(sha256_of "$binary_path") == "$expected_binary_sha256" ]] || fail 'ReconYa binary drifted'
[[ ! -e $staging_path && ! -L $staging_path ]] || fail 'unit staging path exists'
[[ ! -e $rollback_staging_path && ! -L $rollback_staging_path ]] || fail 'rollback staging path exists'
[[ ! -e $backup_dir && ! -L $backup_dir ]] || fail 'backup path exists'
systemctl is-enabled --quiet reconya.service || fail 'ReconYa is not enabled'
systemctl is-active --quiet reconya-oui-update.timer || fail 'OUI timer is not active'
systemctl is-enabled --quiet reconya-oui-update.timer || fail 'OUI timer is not enabled'
health_ok || fail 'ReconYa pre-change health failed'
systemd-analyze verify "$candidate_unit"

trap cleanup EXIT
install -m 0644 -o root -g root -- "$candidate_unit" "$staging_path"
[[ $(sha256_of "$staging_path") == "$new_unit_sha256" ]] || fail 'staged unit checksum mismatch'
install -d -m 0700 -- "$backup_dir"
cp -a -- "$unit_path" "$backup_dir/reconya.service.original"

trap rollback ERR
mv -- "$staging_path" "$unit_path"
mutation_started=1
systemctl daemon-reload
restart_marker="$(date '+%Y-%m-%d %H:%M:%S')"
restart_started=$SECONDS
systemctl restart reconya.service
restart_duration=$((SECONDS - restart_started))
wait_for_health || fail 'ReconYa failed after SIGINT workaround restart'

restart_log="$(journalctl -u reconya.service --since "$restart_marker" --no-pager)"
grep -Fq 'Received shutdown signal: interrupt' <<<"$restart_log" || fail 'SIGINT receipt was not logged'
grep -Fq '[SUCCESS] Services stopped' <<<"$restart_log" || fail 'graceful shutdown success was not logged'
if grep -Eq "stop-sig(term|int).*timed out|State 'stop-.*' timed out|Killing( process)?\." <<<"$restart_log"; then
    fail 'restart required a forced stop'
fi
[[ $restart_duration -le 10 ]] || fail "graceful restart took too long: ${restart_duration}s"
[[ $(sha256_of "$unit_path") == "$new_unit_sha256" ]] || fail 'live unit checksum failed acceptance'
[[ $(sha256_of "$binary_path") == "$expected_binary_sha256" ]] || fail 'binary changed during workaround deployment'
systemctl is-enabled --quiet reconya.service || fail 'ReconYa is no longer enabled'
systemctl is-active --quiet reconya-oui-update.timer || fail 'OUI timer is no longer active'
systemctl is-enabled --quiet reconya-oui-update.timer || fail 'OUI timer is no longer enabled'
[[ -z $(systemctl --failed --no-legend --plain) ]] || fail 'a failed systemd unit remains'
health_ok || fail 'ReconYa final health failed'

trap - ERR
printf 'ACCEPTED: ReconYa SIGINT workaround installed; restart_duration_seconds=%s\n' "$restart_duration"
