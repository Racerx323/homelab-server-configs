#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly driver_sha256=de3bea3d3478959ec16c34af4460d804063f3ebf81a7c69b51214867a117159a
readonly driver_name=cutover-node-a-lighttpd-caddy-action16ap.sh
readonly -a success_markers=(
    action_16ap_remote_reached=true
    action_16ap_preflight_complete=true
    action_16ap_mutation_started=true
    lighttpd_backend_ready=true
    caddy_ready=true
    peer_connections=false
    lsyncd_configuration_changes=false
    keepalived_configuration_changes=false
    action_16ap_cutover_complete=true
)
readonly -a success_prefixes=(
    services_before
    listeners_before_sha256
    source_candidate_tree_sha256
    transformed_candidate_tree_sha256
    promoted_lighttpd_tree_sha256
    original_lighttpd_tree_sha256
    caddy_tree_sha256
    keepalived_tree_sha256
    caddy_timeout_stop
)

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly driver="$script_dir/$driver_name"

verify_driver() {
    [[ -f "$driver" && ! -L "$driver" ]]
    [[ "$(stat -c '%U:%G:%a' "$driver")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$driver" | awk '{ print $1 }')" == "$driver_sha256" ]]
    bash -n "$driver"
    "$driver" --self-test >/dev/null
}

evaluate_success() {
    local output_file=$1
    local error_file=$2
    local ssh_status=$3
    local marker prefix hash_prefix

    [[ "$ssh_status" -eq 0 ]] || return 97
    for marker in "${success_markers[@]}"; do
        [[ "$(grep -Fxc "$marker" "$output_file")" -eq 1 ]] || return 97
    done
    for prefix in "${success_prefixes[@]}"; do
        [[ "$(grep -c "^${prefix}=" "$output_file")" -eq 1 ]] || return 97
    done
    for hash_prefix in \
        listeners_before_sha256 source_candidate_tree_sha256 \
        transformed_candidate_tree_sha256 promoted_lighttpd_tree_sha256 \
        original_lighttpd_tree_sha256 caddy_tree_sha256 \
        keepalived_tree_sha256; do
        grep -Eq "^${hash_prefix}=[0-9a-f]{64}$" "$output_file" || return 97
    done
    grep -Fxq \
        'source_candidate_tree_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13' \
        "$output_file" || return 97
    grep -Fxq \
        'original_lighttpd_tree_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92' \
        "$output_file" || return 97
    grep -Fxq 'caddy_timeout_stop=30s' "$output_file" || return 97
    if grep -Eq \
        'action_16ap_rollback_(complete|incomplete|not_required)=true|manual_intervention_required=true' \
        "$output_file" "$error_file"; then
        return 97
    fi
    return 0
}

evaluate_contract() {
    local output_file=$1
    local error_file=$2
    local ssh_status=$3

    if grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=' \
        "$output_file" "$error_file"; then
        return 97
    fi
    if LC_ALL=C grep -n '[^[:print:][:space:]]' "$output_file" "$error_file" \
        >/dev/null; then
        return 97
    fi
    if [[ "$(grep -Fxc 'action_16ap_cutover_complete=true' \
        "$output_file")" -eq 1 ]]; then
        evaluate_success "$output_file" "$error_file" "$ssh_status"
        return
    fi
    [[ "$ssh_status" -ne 0 ]] || return 97
    if grep -Fxq 'action_16ap_rollback_incomplete=true' "$error_file" ||
        grep -Fxq 'manual_intervention_required=true' "$error_file"; then
        return 97
    fi
    if [[ "$(grep -Fxc 'action_16ap_rollback_complete=true' \
        "$error_file")" -eq 1 ]]; then
        return 1
    fi
    if [[ "$(grep -Fxc 'action_16ap_rollback_not_required=true' \
        "$error_file")" -eq 1 ]]; then
        return 1
    fi
    return 97
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$driver_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "${#success_markers[@]}" -eq 9 ]]
    [[ "${#success_prefixes[@]}" -eq 9 ]]
    verify_driver
    printf 'action_16ap_cutover_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action16ap-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    success="$contract_dir/success.out"
    error_file="$contract_dir/error"
    {
        printf '%s\n' "${success_markers[@]}"
        printf 'services_before=lighttpd=active/enabled\n'
        printf 'listeners_before_sha256=%064d\n' 0
        printf 'source_candidate_tree_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13\n'
        printf 'transformed_candidate_tree_sha256=%064d\n' 1
        printf 'promoted_lighttpd_tree_sha256=%064d\n' 2
        printf 'original_lighttpd_tree_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92\n'
        printf 'caddy_tree_sha256=%064d\n' 3
        printf 'keepalived_tree_sha256=%064d\n' 4
        printf 'caddy_timeout_stop=30s\n'
    } >"$success"
    : >"$error_file"
    evaluate_contract "$success" "$error_file" 0

    duplicate="$contract_dir/duplicate.out"
    cp -- "$success" "$duplicate"
    printf 'caddy_ready=true\n' >>"$duplicate"
    if evaluate_contract "$duplicate" "$error_file" 0; then
        printf 'Duplicate Action 16ap success evidence was accepted.\n' >&2
        exit 1
    fi
    rollback_error="$contract_dir/rollback.error"
    printf 'action_16ap_rollback_complete=true\n' >"$rollback_error"
    set +e
    evaluate_contract /dev/null "$rollback_error" 1
    rollback_status=$?
    set -e
    [[ "$rollback_status" -eq 1 ]]
    no_mutation_error="$contract_dir/no-mutation.error"
    printf 'action_16ap_rollback_not_required=true\n' >"$no_mutation_error"
    set +e
    evaluate_contract /dev/null "$no_mutation_error" 1
    no_mutation_status=$?
    set -e
    [[ "$no_mutation_status" -eq 1 ]]
    incomplete_error="$contract_dir/incomplete.error"
    {
        printf 'action_16ap_rollback_incomplete=true\n'
        printf 'manual_intervention_required=true\n'
    } >"$incomplete_error"
    set +e
    evaluate_contract /dev/null "$incomplete_error" 125
    incomplete_status=$?
    set -e
    [[ "$incomplete_status" -eq 97 ]]
    secret="$contract_dir/secret.out"
    cp -- "$success" "$secret"
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$secret"
    if evaluate_contract "$secret" "$error_file" 0; then
        printf 'Secret-bearing Action 16ap evidence was accepted.\n' >&2
        exit 1
    fi
    printf 'action_16ap_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_driver
work_dir=$(mktemp -d /tmp/caddy-action16ap.XXXXXX)
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
        printf 'action_16ap_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16ap_local_cleanup_complete=true\n'
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
set +e
evaluate_contract "$remote_output" "$remote_error" "$ssh_status"
contract_status=$?
set -e
finish "$contract_status"
