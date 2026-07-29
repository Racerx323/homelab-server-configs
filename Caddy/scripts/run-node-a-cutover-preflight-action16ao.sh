#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=370e40f3ce2293aaf354080f346c847b4134f37d92d83d6d7b61803a99eb1eb0
readonly inspector_name=inspect-node-a-cutover-preflight-action16ao.sh
readonly -a fixed_markers=(
    action_16ao_remote_reached=true
    peer_connections=false
    installed_helper_execution=false
    systemd_daemon_reload_performed=false
    service_mutations=false
    action_16ao_inspection_complete=true
)

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly inspector="$script_dir/$inspector_name"

verify_inspector() {
    [[ -f "$inspector" && ! -L "$inspector" ]]
    [[ "$(stat -c '%U:%G:%a' "$inspector")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$inspector" | awk '{ print $1 }')" == "$inspector_sha256" ]]
    bash -n "$inspector"
    "$inspector" --self-test >/dev/null
}

evaluate_contract() {
    local output_file=$1
    local error_file=$2
    local ssh_status=$3
    local assertion_count mismatch_count valid expected_status
    local check_count false_check_count malformed_check_count marker

    for marker in "${fixed_markers[@]}"; do
        [[ "$(grep -Fxc "$marker" "$output_file")" -eq 1 ]] || return 97
    done
    for prefix in \
        preflight_assertion_count preflight_mismatch_count first_failure \
        action_16ao_cutover_preflight_valid; do
        [[ "$(grep -c "^${prefix}=" "$output_file")" -eq 1 ]] || return 97
    done
    if grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=' \
        "$output_file" "$error_file"; then
        return 97
    fi

    assertion_count=$(sed -n 's/^preflight_assertion_count=//p' "$output_file")
    mismatch_count=$(sed -n 's/^preflight_mismatch_count=//p' "$output_file")
    valid=$(sed -n 's/^action_16ao_cutover_preflight_valid=//p' "$output_file")
    [[ "$assertion_count" =~ ^[1-9][0-9]*$ ]] || return 97
    [[ "$mismatch_count" =~ ^[0-9]+$ ]] || return 97
    ((mismatch_count <= assertion_count)) || return 97

    check_count=$(grep -c '^check_' "$output_file")
    false_check_count=$(grep -c '^check_.*=false$' "$output_file" || true)
    malformed_check_count=$(
        grep '^check_' "$output_file" |
            grep -Evc '^check_[a-z0-9_]+=(true|false)$' || true
    )
    [[ "$check_count" -eq "$assertion_count" ]] || return 97
    [[ "$false_check_count" -eq "$mismatch_count" ]] || return 97
    [[ "$malformed_check_count" -eq 0 ]] || return 97

    if [[ "$mismatch_count" -eq 0 ]]; then
        [[ "$valid" == true ]] || return 97
        grep -Fxq 'first_failure=none' "$output_file" || return 97
        expected_status=0
    else
        [[ "$valid" == false ]] || return 97
        ! grep -Fxq 'first_failure=none' "$output_file" || return 97
        expected_status=1
    fi
    [[ "$ssh_status" -eq "$expected_status" ]] || return 97
    return "$expected_status"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "${#fixed_markers[@]}" -eq 6 ]]
    verify_inspector
    printf 'action_16ao_cutover_preflight_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action16ao-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    success="$contract_dir/success.out"
    error_file="$contract_dir/error"
    {
        printf '%s\n' "${fixed_markers[@]}"
        printf 'check_example=true\n'
        printf 'preflight_assertion_count=1\n'
        printf 'preflight_mismatch_count=0\n'
        printf 'first_failure=none\n'
        printf 'action_16ao_cutover_preflight_valid=true\n'
    } >"$success"
    : >"$error_file"
    evaluate_contract "$success" "$error_file" 0

    mismatch="$contract_dir/mismatch.out"
    sed \
        -e 's/check_example=true/check_example=false/' \
        -e 's/preflight_mismatch_count=0/preflight_mismatch_count=1/' \
        -e 's/first_failure=none/first_failure=example/' \
        -e 's/action_16ao_cutover_preflight_valid=true/action_16ao_cutover_preflight_valid=false/' \
        "$success" >"$mismatch"
    set +e
    evaluate_contract "$mismatch" "$error_file" 1
    mismatch_status=$?
    set -e
    [[ "$mismatch_status" -eq 1 ]]

    duplicate="$contract_dir/duplicate.out"
    cp -- "$success" "$duplicate"
    printf '%s\n' "${fixed_markers[0]}" >>"$duplicate"
    if evaluate_contract "$duplicate" "$error_file" 0; then
        printf 'Duplicate Action 16ao evidence was accepted.\n' >&2
        exit 1
    fi
    malformed="$contract_dir/malformed.out"
    sed 's/check_example=true/check_Example=true/' "$success" >"$malformed"
    if evaluate_contract "$malformed" "$error_file" 0; then
        printf 'Malformed Action 16ao evidence was accepted.\n' >&2
        exit 1
    fi
    secret="$contract_dir/secret.out"
    cp -- "$success" "$secret"
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$secret"
    if evaluate_contract "$secret" "$error_file" 0; then
        printf 'Secret-bearing Action 16ao evidence was accepted.\n' >&2
        exit 1
    fi
    printf 'action_16ao_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_inspector
work_dir=$(mktemp -d /tmp/caddy-action16ao.XXXXXX)
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
        printf 'action_16ao_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16ao_local_cleanup_complete=true\n'
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
    <"$inspector" >"$remote_output" 2>"$remote_error"
ssh_status=$?
set -e

cat "$remote_output"
cat "$remote_error" >&2
printf 'ssh_exit_status=%s\n' "$ssh_status"
set +e
evaluate_contract "$remote_output" "$remote_error" "$ssh_status"
contract_status=$?
set -e
finish "$contract_status"
