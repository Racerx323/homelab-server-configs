#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly repair_sha256=1654d9e9e8aff0f77fa851c708352802954231b011ba550644fdb14bb0ce4fa3

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly repair="$script_dir/repair-node-a-retained-stage-mode-action16ak-c.sh"

verify_repair() {
    [[ -f "$repair" && ! -L "$repair" ]]
    [[ "$(stat -c '%U:%G:%a' "$repair")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$repair" | awk '{ print $1 }')" == "$repair_sha256" ]]
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$repair_sha256" =~ ^[0-9a-f]{64}$ ]]
    verify_repair
    bash -n "$repair"
    "$repair" --self-test >/dev/null
    printf 'action_16ak_c_retained_stage_mode_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --local-test && $# -eq 1 ]]; then
    work_dir=$(mktemp -d /tmp/caddy-action16ak-c-local.XXXXXX)
    trap 'rm -rf -- "$work_dir"' EXIT
    install -d -m 0700 "$work_dir/stage"
    exec {stage_fd}<"$work_dir/stage"
    inode_device_before=$(stat -Lc '%i:%d' "/proc/self/fd/$stage_fd")
    chmod 0750 "/proc/self/fd/$stage_fd"
    [[ "$(stat -c '%a' "$work_dir/stage")" == 750 ]]
    [[ "$(stat -c '%i:%d' "$work_dir/stage")" == "$inode_device_before" ]]
    chmod 0700 "/proc/self/fd/$stage_fd"
    [[ "$(stat -c '%a' "$work_dir/stage")" == 700 ]]
    printf 'action_16ak_c_fd_repair_and_rollback_local_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--local-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_repair
work_dir=$(mktemp -d /tmp/caddy-action16ak-c.XXXXXX)
readonly work_dir
readonly remote_output="$work_dir/remote.out"
readonly remote_error="$work_dir/remote.err"
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

finish() {
    local status=$1

    cleanup
    trap - EXIT
    if [[ -e "$work_dir" || -L "$work_dir" ]]; then
        printf 'action_16ak_c_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16ak_c_local_cleanup_complete=true\n'
    exit "$status"
}

ssh_status=0
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias=pihole0.local.theama.co \
    -o StrictHostKeyChecking=yes \
    pi@10.1.0.53 \
    'sudo -n /bin/bash -s --' \
    <"$repair" >"$remote_output" 2>"$remote_error" || ssh_status=$?

if grep -Eq \
    'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|node_a_sync_ed25519_public_key=' \
    "$remote_output" "$remote_error"; then
    printf 'Action 16ak-c suppressed unexpected key material.\n' >&2
    finish 97
fi

cat "$remote_output"
cat "$remote_error" >&2
printf 'ssh_exit_status=%s\n' "$ssh_status"
if [[ "$ssh_status" -ne 0 ]]; then
    if grep -Fq 'manual_intervention_required=true' \
        "$remote_output" "$remote_error"; then
        finish 97
    fi
    if grep -Fq 'action_16ak_c_mutation_started=true' "$remote_output" &&
        ! grep -Fq 'action_16ak_c_rollback_complete=true' \
            "$remote_output" "$remote_error"; then
        printf 'Action 16ak-c lacks required rollback evidence.\n' >&2
        finish 97
    fi
    finish "$ssh_status"
fi

readonly -a required_markers=(
    action_16ak_c_remote_reached=true
    root_effective_uid=true
    node_hostname=true
    node_ipv4=true
    retained_stage_pre_repair=true
    stage_file_state_capture=true
    stage_fd_identity=true
    action_16ak_c_preflight_valid=true
    action_16ak_c_mutation_started=true
    stage_root_mode_repair=true
    post_repair_continuity=true
    stage_file_state_unchanged=true
    stage_mode_before=700
    stage_mode_after=750
    stage_owner_after=root:root
    stage_inode_after=1670964
    stage_device_after=66306
    service_mutations=false
    first_failure=none
    action_16ak_c_rollback_invoked=false
    action_16ak_c_retained_stage_mode_repair_complete=true
)
for marker in "${required_markers[@]}"; do
    grep -Fxq "$marker" "$remote_output"
done
if grep -Eq '=false$|manual_intervention_required=true|action_16ak_c_rollback_complete=' \
    "$remote_output" "$remote_error"; then
    finish 97
fi

finish 0
