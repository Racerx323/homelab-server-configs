#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly driver_sha256=b46ff5cd437887b19fbec25025f03451bcbcf9b6a10bae1b8350dade40346292

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly driver="$script_dir/install-node-a-sync-ssh-action16ak.sh"

verify_driver() {
    [[ -f "$driver" && ! -L "$driver" ]]
    [[ "$(stat -c '%U:%G:%a' "$driver")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$driver" | awk '{ print $1 }')" == "$driver_sha256" ]]
}

if [[ "${1:-}" == --self-test ]]; then
    [[ "$driver_sha256" =~ ^[0-9a-f]{64}$ ]]
    verify_driver
    bash -n "$driver"
    "$driver" --self-test >/dev/null
    printf 'action_16ak_sync_ssh_install_runner_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_driver
work_dir=$(mktemp -d /tmp/caddy-action16ak.XXXXXX)
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
        printf 'action_16ak_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16ak_local_cleanup_complete=true\n'
    exit "$status"
}

set +e
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias=pihole0.local.theama.co \
    -o StrictHostKeyChecking=yes \
    pi@10.1.0.53 \
    'sudo -n /bin/bash -s --' \
    <"$driver" >"$remote_output" 2>"$remote_error"
ssh_status=$?
set -e

cat "$remote_output"
cat "$remote_error" >&2
printf 'ssh_exit_status=%s\n' "$ssh_status"
if grep -Eq \
    'PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM' \
    "$remote_output" "$remote_error"; then
    printf 'Unsafe Action 16ak output detected.\n' >&2
    finish 97
fi
if [[ "$ssh_status" -ne 0 ]]; then
    if grep -Eq \
        'manual_intervention_required=true|action_16ak_rollback_complete=false' \
        "$remote_output" "$remote_error"; then
        printf 'Failed Action 16ak rollback detected.\n' >&2
        finish 97
    fi
    if grep -Fq 'action_16ak_mutation_started=true' "$remote_output" &&
        ! grep -Fq 'action_16ak_rollback_complete=true' \
            "$remote_output" "$remote_error"; then
        printf 'Action 16ak lacks required rollback evidence.\n' >&2
        finish 97
    fi
    finish "$ssh_status"
fi

readonly -a required_markers=(
    action_16ak_preflight_complete=true
    action_16ak_mutation_started=true
    action_16ak_helpers_installed=true
    action_16ak_known_hosts_installed=true
    action_16ak_identity_and_authorization_installed=true
    action_16ak_initial_validation_complete=true
    action_16ak_repeat_validation_complete=true
    node_b_host_ed25519_fingerprint=SHA256:eDdqL/bS/EuVysKQ7yxJ6lpjJWf2PcymtfPwMlzacbo
    node_b_sync_ed25519_fingerprint=SHA256:ykJmrl499fd2qRm9bYjgyrgeiTCA1rzTelBBKX0gy5g
    restricted_authorization_count=1
    non_connecting_validation=true
    idempotency_validation=true
    retained_stage_preserved=true
    lsyncd_configuration_installed=false
    service_mutations=false
    action_16ak_sync_ssh_install_complete=true
)
for marker in "${required_markers[@]}"; do
    grep -Fxq "$marker" "$remote_output"
done
grep -Eq \
    '^node_a_sync_ed25519_fingerprint=SHA256:[A-Za-z0-9+/]{43}$' \
    "$remote_output"
grep -Eq \
    '^node_a_sync_ed25519_public_key=ssh-ed25519 [A-Za-z0-9+/=]+ caddy-ha-sync$' \
    "$remote_output"
if grep -Eq \
    'manual_intervention_required=true|action_16ak_rollback_complete=' \
    "$remote_output" "$remote_error"; then
    printf 'Unexpected Action 16ak rollback output detected.\n' >&2
    finish 97
fi

finish 0
