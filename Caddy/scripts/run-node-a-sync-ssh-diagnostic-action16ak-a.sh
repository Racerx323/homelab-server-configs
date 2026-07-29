#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=3fc6ff00132c6900b1a1b3d01d6ed65cf974de3466ab5f8b5ad829755b029d5f

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly inspector="$script_dir/diagnose-node-a-sync-ssh-action16ak-a.sh"

verify_inspector() {
    [[ -f "$inspector" && ! -L "$inspector" ]]
    [[ "$(stat -c '%U:%G:%a' "$inspector")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$inspector" | awk '{ print $1 }')" == "$inspector_sha256" ]]
}

if [[ "${1:-}" == --self-test ]]; then
    [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    verify_inspector
    bash -n "$inspector"
    "$inspector" --self-test >/dev/null
    printf 'action_16ak_a_sync_ssh_diagnostic_runner_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_inspector
work_dir=$(mktemp -d /tmp/caddy-action16ak-a.XXXXXX)
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
        printf 'action_16ak_a_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16ak_a_local_cleanup_complete=true\n'
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
    'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|node_a_sync_ed25519_public_key=' \
    "$remote_output" "$remote_error"; then
    printf 'Action 16ak-a suppressed unexpected key material.\n' >&2
    finish 97
fi

cat "$remote_output"
cat "$remote_error" >&2
printf 'ssh_exit_status=%s\n' "$ssh_status"

if ! grep -Fxq 'action_16ak_a_remote_reached=true' "$remote_output"; then
    finish "$ssh_status"
fi

diagnostic_contract_valid=true
grep -Fxq \
    'action_16ak_a_read_only_inspection_complete=true' \
    "$remote_output" || diagnostic_contract_valid=false
[[ "$(grep -c '^diagnostic_mismatch_count=' "$remote_output")" -eq 1 ]] ||
    diagnostic_contract_valid=false
[[ "$(grep -c '^first_failure=' "$remote_output")" -eq 1 ]] ||
    diagnostic_contract_valid=false
[[ "$(grep -c '^action_16ak_preflight_would_pass=' "$remote_output")" -eq 1 ]] ||
    diagnostic_contract_valid=false
[[ "$(grep -c '^installed_shape_valid=' "$remote_output")" -eq 1 ]] ||
    diagnostic_contract_valid=false
[[ "$(grep -c '^node_a_public_fingerprint=' "$remote_output")" -eq 1 ]] ||
    diagnostic_contract_valid=false
[[ "$(grep -c '^live_target_.*_state=' "$remote_output")" -eq 8 ]] ||
    diagnostic_contract_valid=false
[[ "$(grep -c '^live_target_.*_owner_mode=' "$remote_output")" -eq 8 ]] ||
    diagnostic_contract_valid=false
grep -Eq '^diagnostic_mismatch_count=[0-9]+$' "$remote_output" ||
    diagnostic_contract_valid=false
grep -Eq '^first_failure=(none|[a-z0-9_]+)$' "$remote_output" ||
    diagnostic_contract_valid=false
grep -Eq '^action_16ak_preflight_would_pass=(true|false)$' \
    "$remote_output" || diagnostic_contract_valid=false
grep -Eq '^installed_shape_valid=(true|false)$' "$remote_output" ||
    diagnostic_contract_valid=false
grep -Eq \
    '^node_a_public_fingerprint=(unavailable|SHA256:[A-Za-z0-9+/]{43})$' \
    "$remote_output" || diagnostic_contract_valid=false

if [[ "$diagnostic_contract_valid" != true ]]; then
    printf 'Action 16ak-a diagnostic output contract failed.\n' >&2
    finish 97
fi

diagnostic_mismatch_count=$(
    sed -n 's/^diagnostic_mismatch_count=//p' "$remote_output"
)
first_failure=$(
    sed -n 's/^first_failure=//p' "$remote_output"
)
preflight_would_pass=$(
    sed -n 's/^action_16ak_preflight_would_pass=//p' "$remote_output"
)

if [[ "$diagnostic_mismatch_count" -eq 0 ]]; then
    if [[ "$first_failure" != none ||
        "$preflight_would_pass" != true ||
        "$ssh_status" -ne 0 ]]; then
        printf 'Action 16ak-a valid-state result is inconsistent.\n' >&2
        finish 97
    fi
    finish 0
fi

if [[ "$first_failure" == none ||
    "$preflight_would_pass" != false ||
    "$ssh_status" -ne 1 ]]; then
    printf 'Action 16ak-a mismatch result is inconsistent.\n' >&2
    finish 97
fi
finish 1
