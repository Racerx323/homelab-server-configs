#!/bin/bash

set -Eeuo pipefail
umask 077

readonly expected_hostname='J1-SVMF'
readonly service_name='reconya.service'
readonly install_dir='/home/pi/reconya'
readonly binary_name='reconya-linux-arm64'
readonly archive_name='reconya-linux-arm64.tar.gz'
readonly old_binary_sha256='75101e776500539b5827ba0300fb3435cc4991cd75fcaa9123cf6206fc68f9d3'
readonly new_archive_sha256='31e6ee19536e90c24d676446a950feee3d5e8e53fb6ef429e50568eb916be812'
readonly new_binary_sha256='0f5bdd5c2198f190316595b235f7c2c2fe828632baf320f773bcb5c2f990c4c3'
readonly backup_dir='/var/backups/reconya/v0.24.1-to-v0.26.0'
readonly health_url='http://127.0.0.1:3008/'
readonly binary_path="$install_dir/$binary_name"
readonly data_path="$install_dir/data"

bundle_dir=''
work_dir=''
service_stopped=0
snapshot_ready=0
binary_replaced=0
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

    status_code="$(curl --silent --show-error --output /dev/null \
        --write-out '%{http_code}' --max-time 5 "$health_url")" || return 1
    [[ $status_code == 200 || $status_code == 302 || $status_code == 303 ]]
}

service_ok() {
    systemctl is-active --quiet "$service_name" &&
        systemctl is-enabled --quiet "$service_name" &&
        ss -H -ltn 'sport = :3008' | grep -q . &&
        health_ok
}

rollback() {
    local original_status=$?

    [[ $rollback_running -eq 0 ]] || exit "$original_status"
    rollback_running=1
    trap - ERR
    printf 'ROLLBACK: restoring v0.24.1 binary and stopped-state data snapshot\n' >&2

    if [[ $service_stopped -eq 1 && $snapshot_ready -eq 0 ]]; then
        systemctl start "$service_name"
        if [[ $(sha256_of "$binary_path") == "$old_binary_sha256" ]] && service_ok; then
            printf 'ROLLBACK_OK: original service restarted before binary or data mutation\n' >&2
            exit "$original_status"
        fi
        printf 'MANUAL_INTERVENTION_REQUIRED: original service did not recover; backup path is %s\n' "$backup_dir" >&2
        exit 125
    fi

    systemctl stop "$service_name" || true

    if [[ $binary_replaced -eq 1 && -e $binary_path ]]; then
        mv -- "$binary_path" "$backup_dir/failed-v0.26.0-binary"
    fi
    install -m 0755 -- "$backup_dir/$binary_name" "$binary_path"
    chown --reference="$backup_dir/$binary_name" "$binary_path"

    if [[ -d $data_path && ! -L $data_path ]]; then
        mv -- "$data_path" "$backup_dir/failed-v0.26.0-data"
    fi
    cp -a -- "$backup_dir/data.snapshot" "$data_path"

    systemctl start "$service_name"
    if [[ $(sha256_of "$binary_path") == "$old_binary_sha256" ]] && service_ok; then
        printf 'ROLLBACK_OK: v0.24.1 restored; failed candidate artifacts preserved in %s\n' "$backup_dir" >&2
        exit "$original_status"
    fi

    printf 'MANUAL_INTERVENTION_REQUIRED: rollback acceptance failed; artifacts preserved in %s\n' "$backup_dir" >&2
    exit 125
}

[[ $# -eq 1 ]] || fail 'usage: deploy-reconya-update.sh BUNDLE_DIR'
bundle_dir="$1"
[[ $EUID -eq 0 ]] || fail 'must run as root'
[[ $(hostname) == "$expected_hostname" ]] || fail "expected host $expected_hostname"
[[ -d $bundle_dir && ! -L $bundle_dir ]] || fail 'bundle directory must be a real directory'
[[ $bundle_dir == /* ]] || fail 'bundle directory must be absolute'

for command_name in curl file sha256sum ss systemctl tar mktemp install; do
    command -v "$command_name" >/dev/null || fail "required command not found: $command_name"
done

[[ -f $binary_path && ! -L $binary_path ]] || fail 'installed binary must be a regular non-symlink'
[[ -d $data_path && ! -L $data_path ]] || fail 'data path must be a real non-symlink directory'
[[ $(sha256_of "$binary_path") == "$old_binary_sha256" ]] || fail 'installed binary is not the authorized v0.24.1 input'
file "$binary_path" | grep -Fq 'ELF 64-bit LSB executable, ARM aarch64' || fail 'installed binary is not ARM64 ELF'
systemctl is-active --quiet "$service_name" || fail 'service is not active before update'
systemctl is-enabled --quiet "$service_name" || fail 'service is not enabled before update'
health_ok || fail 'pre-update HTTP health check failed'
[[ ! -e $backup_dir ]] || fail "backup path already exists: $backup_dir"

readonly candidate_archive="$bundle_dir/$archive_name"
[[ -f $candidate_archive && ! -L $candidate_archive ]] || fail 'candidate archive missing or unsafe'
[[ $(sha256_of "$candidate_archive") == "$new_archive_sha256" ]] || fail 'candidate archive checksum mismatch'

work_dir="$(mktemp -d)"
readonly work_dir
trap 'rm -rf -- "$work_dir"' EXIT

mapfile -t archive_members < <(tar -tzf "$candidate_archive" | LC_ALL=C sort)
readonly archive_members
[[ ${#archive_members[@]} -eq 2 ]] || fail 'candidate archive must contain exactly two members'
[[ ${archive_members[0]} == '.env.example' ]] || fail 'candidate archive member set rejected'
[[ ${archive_members[1]} == "$binary_name" ]] || fail 'candidate archive member set rejected'
[[ -z $(tar -tvzf "$candidate_archive" | awk '$1 !~ /^-/ { print }') ]] || fail 'candidate archive has non-regular members'
tar -xzf "$candidate_archive" -C "$work_dir" --no-same-owner --no-same-permissions
readonly candidate_binary="$work_dir/$binary_name"
[[ $(sha256_of "$candidate_binary") == "$new_binary_sha256" ]] || fail 'candidate binary checksum mismatch'
file "$candidate_binary" | grep -Fq 'ELF 64-bit LSB executable, ARM aarch64' || fail 'candidate binary is not ARM64 ELF'

install -d -m 0700 -- "$(dirname -- "$backup_dir")"
install -d -m 0700 -- "$backup_dir"

trap rollback ERR
systemctl stop "$service_name"
service_stopped=1
systemctl is-active --quiet "$service_name" && fail 'service remained active after stop'

cp -a -- "$binary_path" "$backup_dir/$binary_name"
cp -a -- "$data_path" "$backup_dir/data.snapshot"
printf '%s  %s\n' "$old_binary_sha256" "$binary_name" >"$backup_dir/SHA256SUMS"
[[ $(sha256_of "$backup_dir/$binary_name") == "$old_binary_sha256" ]] || fail 'backup binary checksum mismatch'
[[ -d $backup_dir/data.snapshot && ! -L $backup_dir/data.snapshot ]] || fail 'data snapshot is unsafe'
snapshot_ready=1

readonly replacement_path="$install_dir/.${binary_name}.v0.26.0.new"
[[ ! -e $replacement_path ]] || fail "replacement staging path exists: $replacement_path"
install -m 0755 -- "$candidate_binary" "$replacement_path"
chown --reference="$binary_path" "$replacement_path"
[[ $(sha256_of "$replacement_path") == "$new_binary_sha256" ]] || fail 'staged binary checksum mismatch'
mv -- "$replacement_path" "$binary_path"
binary_replaced=1

systemctl start "$service_name"
for _attempt in $(seq 1 30); do
    if service_ok; then
        break
    fi
    sleep 1
done

[[ $(sha256_of "$binary_path") == "$new_binary_sha256" ]] || fail 'installed candidate checksum mismatch'
service_ok || fail 'post-update acceptance failed'

trap - ERR
printf 'ACCEPTED: ReconYa v0.26.0 binary is active; backup retained at %s\n' "$backup_dir"
