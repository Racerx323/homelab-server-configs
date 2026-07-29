#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly retained_stage=/var/tmp/caddy-sync-ssh-node-a-action16aj-e
readonly expected_stage_inode=1670964
readonly expected_stage_device=66306
readonly -a expected_files=(
    caddy-sync-rsync-receiver
    node-b-host-ed25519.pub
    node-b-sync-ed25519.pub
    setup-sync-ssh.sh
    validate-sync-ssh.sh
)
readonly -a expected_checksums=(
    '65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134  caddy-sync-rsync-receiver'
    '909ee3ca843757d8d956ac6d442d6079134b0235fa7d37c97d80590eb5870fbd  node-b-host-ed25519.pub'
    'c9a2ecfcc6a44c0cd30d06bbb2841ec50ffd11866ce1da77ff69f2b5ff8320b0  node-b-sync-ed25519.pub'
    'd1d1e4fd0fd3787e43d7801babfbcdec20015b6517282cdba67904aa1b554140  setup-sync-ssh.sh'
    '85df8a934c8dd9561a6f567f42549ebc01ee2605ca630150265004b9ec108072  validate-sync-ssh.sh'
)
readonly -a live_targets=(
    /var/lib/caddy-sync/.ssh/id_ed25519
    /var/lib/caddy-sync/.ssh/id_ed25519.pub
    /var/lib/caddy-sync/.ssh/known_hosts
    /var/lib/caddy-sync/.ssh/authorized_keys
    /usr/local/libexec/caddy-sync-rsync-receiver
    /usr/local/libexec/setup-sync-ssh.sh
    /usr/local/libexec/validate-sync-ssh.sh
    /etc/lsyncd/caddy.lua
)

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "${#expected_files[@]}" -eq 5 ]]
    [[ "${#expected_checksums[@]}" -eq 5 ]]
    [[ "${#live_targets[@]}" -eq 8 ]]
    [[ "$expected_stage_inode" =~ ^[0-9]+$ ]]
    [[ "$expected_stage_device" =~ ^[0-9]+$ ]]
    printf 'action_16ak_c_retained_stage_mode_repair_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

fail_before_write() {
    local label=$1

    printf '%s=false\n' "$label"
    printf 'first_failure=%s\n' "$label"
    printf 'action_16ak_c_preflight_valid=false\n'
    exit 1
}

require_preflight() {
    local label=$1
    shift

    if ! "$@" >/dev/null 2>&1; then
        fail_before_write "$label"
    fi
    printf '%s=true\n' "$label"
}

stage_file_state() {
    (
        cd "$retained_stage"
        find . -mindepth 1 -maxdepth 1 \
            -printf '%P|%y|%U:%G:%m:%s:%Y:%i\n' |
            sort
        find . -mindepth 1 -maxdepth 1 -type f -print0 |
            sort -z |
            xargs -0 -r sha256sum
    )
}

validate_continuity() {
    local expected_mode=$1
    local checksum expected_hash expected_mode_for_file relative_path target
    local -a actual_files=()

    [[ -d "$retained_stage" && ! -L "$retained_stage" ]]
    [[ "$(stat -c '%U:%G:%a:%i:%d' "$retained_stage")" == "root:root:${expected_mode}:${expected_stage_inode}:${expected_stage_device}" ]]
    [[ "$(stat -c '%U:%G:%a' /var/tmp)" == root:root:1777 ]]
    mapfile -t actual_files < <(
        find "$retained_stage" -mindepth 1 -maxdepth 1 -type f \
            -printf '%f\n' |
            sort
    )
    [[ "${actual_files[*]}" == "${expected_files[*]}" ]]
    [[ "$(find "$retained_stage" -type l -print | wc -l)" -eq 0 ]]

    for checksum in "${expected_checksums[@]}"; do
        expected_hash=${checksum%% *}
        relative_path=${checksum#*  }
        [[ "$(sha256sum "$retained_stage/$relative_path" |
            awk '{ print $1 }')" == "$expected_hash" ]]
        [[ "$(stat -c '%U:%G' "$retained_stage/$relative_path")" == root:root ]]
        case "$relative_path" in
            *.sh | caddy-sync-rsync-receiver)
                expected_mode_for_file=750
                ;;
            *)
                expected_mode_for_file=640
                ;;
        esac
        [[ "$(stat -c '%a' "$retained_stage/$relative_path")" == "$expected_mode_for_file" ]]
    done

    for target in "${live_targets[@]}"; do
        [[ ! -e "$target" && ! -L "$target" ]]
    done
    [[ ! -e /usr/local/libexec && ! -L /usr/local/libexec ]]
    [[ "$(systemctl is-active caddy.service 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled caddy.service 2>/dev/null || true)" == masked ]]
    [[ "$(systemctl is-active lsyncd.service 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" == masked ]]
}

printf 'action_16ak_c_remote_reached=true\n'
require_preflight root_effective_uid test "$EUID" -eq 0
require_preflight node_hostname test "$(hostname)" = j1-svpihole0
require_preflight node_ipv4 grep -Fq '10.1.0.53/22' \
    < <(ip -o -4 address show dev eth0)
require_preflight retained_stage_pre_repair validate_continuity 700

stage_file_state_before=$(stage_file_state)
readonly stage_file_state_before
if [[ -z "$stage_file_state_before" ]]; then
    fail_before_write stage_file_state_capture
fi
printf 'stage_file_state_capture=true\n'

exec {stage_fd}<"$retained_stage"
readonly stage_fd
require_preflight stage_fd_identity test \
    "$(stat -Lc '%i:%d' "/proc/self/fd/$stage_fd")" = \
    "${expected_stage_inode}:${expected_stage_device}"
printf 'action_16ak_c_preflight_valid=true\n'

success=false
mutation_started=false
rollback() {
    local original_rc=$?
    local rollback_valid=true

    if [[ "$success" == true ]]; then
        return
    fi

    set +e
    if [[ "$mutation_started" == true ]]; then
        chmod 0700 "/proc/self/fd/$stage_fd" || rollback_valid=false
    fi
    validate_continuity 700 || rollback_valid=false
    [[ "$(stage_file_state)" == "$stage_file_state_before" ]] ||
        rollback_valid=false
    printf 'action_16ak_c_rollback_complete=%s\n' "$rollback_valid" >&2
    if [[ "$rollback_valid" == true ]]; then
        exit "$original_rc"
    fi
    printf 'manual_intervention_required=true\n' >&2
    exit 97
}
trap rollback EXIT

repair_fail() {
    local label=$1

    printf '%s=false\n' "$label"
    printf 'first_failure=%s\n' "$label"
    exit 1
}

mutation_started=true
printf 'action_16ak_c_mutation_started=true\n'
if ! chmod 0750 "/proc/self/fd/$stage_fd"; then
    repair_fail stage_root_mode_repair
fi
printf 'stage_root_mode_repair=true\n'

if ! validate_continuity 750; then
    repair_fail post_repair_continuity
fi
printf 'post_repair_continuity=true\n'
if [[ "$(stage_file_state)" != "$stage_file_state_before" ]]; then
    repair_fail stage_file_state_unchanged
fi
printf 'stage_file_state_unchanged=true\n'

printf 'stage_mode_before=700\n'
printf 'stage_mode_after=%s\n' \
    "$(stat -c '%a' "$retained_stage")"
printf 'stage_owner_after=%s\n' \
    "$(stat -c '%U:%G' "$retained_stage")"
printf 'stage_inode_after=%s\n' \
    "$(stat -c '%i' "$retained_stage")"
printf 'stage_device_after=%s\n' \
    "$(stat -c '%d' "$retained_stage")"
printf 'service_mutations=false\n'
printf 'first_failure=none\n'
printf 'action_16ak_c_rollback_invoked=false\n'
printf 'action_16ak_c_retained_stage_mode_repair_complete=true\n'
success=true
