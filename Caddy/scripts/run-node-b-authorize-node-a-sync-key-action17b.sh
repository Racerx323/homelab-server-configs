#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly driver_sha256=ebd126884ec1985b4561d5ac7fc16b54f93fb29e7d5de9fddbe4788925c27efe
readonly expected_fingerprint='SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0'
readonly expected_host_alias=pihole00.local.theama.co
readonly expected_target=pi@10.1.0.54

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly driver="$script_dir/authorize-node-a-sync-key-on-node-b-action17b.sh"

verify_driver() {
    [[ -f "$driver" && ! -L "$driver" ]]
    [[ "$(stat -c '%U:%G:%a' "$driver")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$driver" | awk '{ print $1 }')" == "$driver_sha256" ]]
    bash -n "$driver"
}

require_one() {
    local value=$1
    local transcript=$2

    [[ "$(grep -Fxc "$value" "$transcript")" -eq 1 ]]
}

validate_success() {
    local output=$1
    local error_file=$2
    local ssh_status=$3
    local marker

    [[ "$ssh_status" -eq 0 ]]
    [[ ! -s "$error_file" ]]
    for marker in \
        action_17b_preflight_complete=true \
        action_17b_mutation_started=true \
        action_17b_authorization_installed=true \
        restricted_authorization_count=1 \
        "node_a_sync_ed25519_fingerprint=$expected_fingerprint" \
        persistent_mutation_scope=authorized_keys_only \
        peer_connections=false \
        synchronization_commands_executed=false \
        lsyncd_configuration_installed=false \
        service_mutations=false \
        protected_state_unchanged=true \
        action_17b_node_b_authorization_complete=true; do
        require_one "$marker" "$output" || return 1
    done
    if grep -Eq \
        'action_17b_rollback_|manual_intervention_required=true' \
        "$output" "$error_file"; then
        return 1
    fi
}

validate_failure() {
    local output=$1
    local error_file=$2
    local ssh_status=$3

    [[ "$ssh_status" -ne 0 ]]
    if grep -Fq 'manual_intervention_required=true' \
        "$output" "$error_file" ||
        grep -Fq 'action_17b_rollback_complete=false' \
            "$output" "$error_file"; then
        return 97
    fi
    if grep -Fq 'action_17b_mutation_started=true' "$output"; then
        require_one action_17b_rollback_started=true "$error_file" ||
            return 97
        require_one action_17b_rollback_complete=true "$error_file" ||
            return 97
    elif grep -Eq 'action_17b_rollback_' "$output" "$error_file"; then
        return 97
    fi
    return 0
}

validate_secret_free() {
    local output=$1
    local error_file=$2

    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$output" "$error_file"
}

write_success_fixture() {
    local destination=$1

    printf '%s\n' \
        action_17b_preflight_complete=true \
        action_17b_mutation_started=true \
        action_17b_authorization_installed=true \
        restricted_authorization_count=1 \
        "node_a_sync_ed25519_fingerprint=$expected_fingerprint" \
        persistent_mutation_scope=authorized_keys_only \
        peer_connections=false \
        synchronization_commands_executed=false \
        lsyncd_configuration_installed=false \
        service_mutations=false \
        protected_state_unchanged=true \
        action_17b_node_b_authorization_complete=true >"$destination"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$driver_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$expected_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$expected_host_alias" == pihole00.local.theama.co ]]
    [[ "$expected_target" == pi@10.1.0.54 ]]
    verify_driver
    "$driver" --self-test >/dev/null
    printf 'action_17b_authorization_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action17b-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    success=$contract_dir/success
    error_file=$contract_dir/error
    : >"$error_file"
    write_success_fixture "$success"
    validate_secret_free "$success" "$error_file"
    validate_success "$success" "$error_file" 0

    duplicate=$contract_dir/duplicate
    cp -- "$success" "$duplicate"
    printf 'restricted_authorization_count=1\n' >>"$duplicate"
    if validate_success "$duplicate" "$error_file" 0; then
        printf 'Duplicate success marker was accepted.\n' >&2
        exit 1
    fi

    rollback_output=$contract_dir/rollback-output
    rollback_error=$contract_dir/rollback-error
    printf '%s\n' \
        action_17b_preflight_complete=true \
        action_17b_mutation_started=true >"$rollback_output"
    printf '%s\n' \
        action_17b_rollback_started=true \
        action_17b_rollback_complete=true >"$rollback_error"
    validate_failure "$rollback_output" "$rollback_error" 1

    incomplete_error=$contract_dir/incomplete-error
    printf 'action_17b_rollback_started=true\n' >"$incomplete_error"
    set +e
    validate_failure "$rollback_output" "$incomplete_error" 1
    incomplete_status=$?
    set -e
    [[ "$incomplete_status" -eq 97 ]]

    secret=$contract_dir/secret
    cp -- "$success" "$secret"
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$secret"
    if validate_secret_free "$secret" "$error_file"; then
        printf 'Secret-bearing output was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17b_authorization_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_driver
work_dir=$(mktemp -d /tmp/caddy-action17b.XXXXXX)
readonly work_dir
readonly remote_output=$work_dir/remote.out
readonly remote_error=$work_dir/remote.err

cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

finish() {
    local status=$1

    cleanup
    trap - EXIT
    if [[ -e "$work_dir" || -L "$work_dir" ]]; then
        printf 'action_17b_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_17b_local_cleanup_complete=true\n'
    exit "$status"
}

ssh_status=0
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o "HostKeyAlias=$expected_host_alias" \
    -o StrictHostKeyChecking=yes \
    "$expected_target" \
    'sudo -n /bin/bash -s --' \
    <"$driver" >"$remote_output" 2>"$remote_error" || ssh_status=$?

cat "$remote_output"
cat "$remote_error" >&2
printf 'ssh_exit_status=%s\n' "$ssh_status"
if ! validate_secret_free "$remote_output" "$remote_error"; then
    printf 'Unsafe Action 17b output detected.\n' >&2
    finish 97
fi
if [[ "$ssh_status" -eq 0 ]]; then
    if ! validate_success "$remote_output" "$remote_error" "$ssh_status"; then
        printf 'Action 17b success contract failed.\n' >&2
        finish 97
    fi
    printf 'action_17b_authorization_accepted=true\n'
    finish 0
fi

set +e
validate_failure "$remote_output" "$remote_error" "$ssh_status"
failure_validation_status=$?
set -e
if [[ "$failure_validation_status" -eq 97 ]]; then
    printf 'Action 17b rollback evidence is incomplete.\n' >&2
    finish 97
fi
printf 'action_17b_authorization_accepted=false\n'
finish "$ssh_status"
