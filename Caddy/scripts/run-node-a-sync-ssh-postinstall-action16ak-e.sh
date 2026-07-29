#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=706ff3c6debbe6eda70e459625d72ab110d3240e7d371a0dbc61ce080ad2fc43
readonly expected_node_a_fingerprint='SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0'
readonly expected_node_a_public_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG3MEgLhf8tsImyjkCZpQU4H7X8Xdac+iOUCxRTMM0tA caddy-ha-sync'

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly inspector="$script_dir/inspect-node-a-sync-ssh-postinstall-action16ak-e.sh"

verify_inspector() {
    [[ -f "$inspector" && ! -L "$inspector" ]]
    [[ "$(stat -c '%U:%G:%a' "$inspector")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$inspector" | awk '{ print $1 }')" == "$inspector_sha256" ]]
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$expected_node_a_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$expected_node_a_public_key" =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+\ caddy-ha-sync$ ]]
    verify_inspector
    bash -n "$inspector"
    "$inspector" --self-test >/dev/null
    printf 'action_16ak_e_sync_ssh_postinstall_runner_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_inspector
work_dir=$(mktemp -d /tmp/caddy-action16ak-e.XXXXXX)
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
        printf 'action_16ak_e_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16ak_e_local_cleanup_complete=true\n'
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
    <"$inspector" >"$remote_output" 2>"$remote_error" || ssh_status=$?

if grep -Eq \
    'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=' \
    "$remote_output" "$remote_error"; then
    printf 'Action 16ak-e suppressed unexpected private material.\n' >&2
    finish 97
fi

cat "$remote_output"
cat "$remote_error" >&2
printf 'ssh_exit_status=%s\n' "$ssh_status"
if ! grep -Fxq 'action_16ak_e_remote_reached=true' "$remote_output"; then
    finish "$ssh_status"
fi

contract_valid=true
grep -Fxq 'action_16ak_e_read_only_inspection_complete=true' \
    "$remote_output" || contract_valid=false
[[ "$(grep -c '^acceptance_mismatch_count=' "$remote_output")" -eq 1 ]] ||
    contract_valid=false
[[ "$(grep -c '^first_failure=' "$remote_output")" -eq 1 ]] ||
    contract_valid=false
[[ "$(grep -c '^action_16ak_e_postinstall_valid=' "$remote_output")" -eq 1 ]] ||
    contract_valid=false
[[ "$(grep -c '^node_a_sync_ed25519_fingerprint=' "$remote_output")" -eq 1 ]] ||
    contract_valid=false
[[ "$(grep -c '^node_a_sync_ed25519_public_key=' "$remote_output")" -eq 1 ]] ||
    contract_valid=false
grep -Eq '^acceptance_mismatch_count=[0-9]+$' "$remote_output" ||
    contract_valid=false
grep -Eq '^first_failure=(none|[a-z0-9_]+)$' "$remote_output" ||
    contract_valid=false
grep -Eq '^action_16ak_e_postinstall_valid=(true|false)$' \
    "$remote_output" || contract_valid=false
grep -Fxq \
    "node_a_sync_ed25519_fingerprint=$expected_node_a_fingerprint" \
    "$remote_output" || contract_valid=false
grep -Fxq \
    "node_a_sync_ed25519_public_key=$expected_node_a_public_key" \
    "$remote_output" || contract_valid=false
grep -Fxq 'peer_connections=false' "$remote_output" ||
    contract_valid=false
grep -Fxq 'installed_helper_execution=false' "$remote_output" ||
    contract_valid=false
grep -Fxq 'service_mutations=false' "$remote_output" ||
    contract_valid=false

if [[ "$contract_valid" != true ]]; then
    printf 'Action 16ak-e output contract failed.\n' >&2
    finish 97
fi

mismatch_count=$(
    sed -n 's/^acceptance_mismatch_count=//p' "$remote_output"
)
first_failure=$(
    sed -n 's/^first_failure=//p' "$remote_output"
)
postinstall_valid=$(
    sed -n 's/^action_16ak_e_postinstall_valid=//p' "$remote_output"
)
if [[ "$mismatch_count" -eq 0 ]]; then
    if [[ "$first_failure" != none ||
        "$postinstall_valid" != true ||
        "$ssh_status" -ne 0 ]]; then
        printf 'Action 16ak-e valid-state result is inconsistent.\n' >&2
        finish 97
    fi
    finish 0
fi
if [[ "$first_failure" == none ||
    "$postinstall_valid" != false ||
    "$ssh_status" -ne 1 ]]; then
    printf 'Action 16ak-e mismatch result is inconsistent.\n' >&2
    finish 97
fi
finish 1
