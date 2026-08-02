#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=67c6c1eca8d3af1820607e3c0a9d548c439d1bdce97a68676ca793d24492d90f
readonly inspector_name=inspect-node-a-post-cutover-action16aq.sh
readonly -a fixed_markers=(
    action_16aq_remote_reached=true
    peer_connections=false
    installed_helper_execution=false
    systemd_daemon_reload_performed=false
    service_mutations=false
    filesystem_mutations=false
    action_16aq_inspection_complete=true
)
readonly -a evidence_prefixes=(
    backend_http_code
    localhost_https_code
    management_ipv4_http1_code
    management_ipv4_http2_code
    management_ipv6_http1_code
    management_ipv6_http2_code
    unknown_host_code
    served_leaf_sha256
    certificate_not_after
    live_lighttpd_tree_sha256
    original_lighttpd_tree_sha256
    candidate_lighttpd_tree_sha256
    caddy_tree_sha256
    keepalived_tree_sha256
    journal_record_count
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

record_count() {
    local prefix=$1
    local output_file=$2

    grep -c "^${prefix}=" "$output_file" || true
}

evaluate_contract() {
    local output_file=$1
    local error_file=$2
    local ssh_status=$3
    local assertion_count mismatch_count valid expected_status
    local check_count false_check_count malformed_check_count
    local journal_count marker prefix hash_prefix

    for marker in "${fixed_markers[@]}"; do
        [[ "$(grep -Fxc "$marker" "$output_file")" -eq 1 ]] || return 97
    done
    for prefix in \
        postcutover_assertion_count postcutover_mismatch_count first_failure \
        action_16aq_post_cutover_valid "${evidence_prefixes[@]}"; do
        [[ "$(record_count "$prefix" "$output_file")" -eq 1 ]] || return 97
    done
    if grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=' \
        "$output_file" "$error_file"; then
        return 97
    fi
    if LC_ALL=C grep -n '[^[:print:][:space:]]' \
        "$output_file" "$error_file" >/dev/null; then
        return 97
    fi

    assertion_count=$(
        sed -n 's/^postcutover_assertion_count=//p' "$output_file"
    )
    mismatch_count=$(
        sed -n 's/^postcutover_mismatch_count=//p' "$output_file"
    )
    valid=$(sed -n 's/^action_16aq_post_cutover_valid=//p' "$output_file")
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

    for prefix in \
        backend_http_code management_ipv4_http1_code \
        management_ipv4_http2_code management_ipv6_http1_code \
        management_ipv6_http2_code; do
        grep -Eq "^${prefix}=[23][0-9][0-9]$" "$output_file" || return 97
    done
    grep -Fxq 'localhost_https_code=204' "$output_file" || return 97
    grep -Fxq 'unknown_host_code=421' "$output_file" || return 97
    grep -Eq '^served_leaf_sha256=[0-9a-f]{64}$' "$output_file" || return 97
    grep -Fxq \
        'certificate_not_after=Jan 19 23:59:59 2027 GMT' \
        "$output_file" || return 97

    for hash_prefix in \
        live_lighttpd_tree_sha256 original_lighttpd_tree_sha256 \
        candidate_lighttpd_tree_sha256 caddy_tree_sha256 \
        keepalived_tree_sha256; do
        grep -Eq "^${hash_prefix}=[0-9a-f]{64}$" "$output_file" || return 97
    done
    grep -Fxq \
        'live_lighttpd_tree_sha256=95a8752f86f1f475d7b8fd12090379c4ae46b9f4140212c7405586c222383372' \
        "$output_file" || return 97
    grep -Fxq \
        'original_lighttpd_tree_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92' \
        "$output_file" || return 97
    grep -Fxq \
        'candidate_lighttpd_tree_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13' \
        "$output_file" || return 97
    grep -Fxq \
        'caddy_tree_sha256=6ae99faf2cb216466879f15139cdd6614234cf46d796f535387d51ecc9602161' \
        "$output_file" || return 97
    grep -Fxq \
        'keepalived_tree_sha256=dad64e4ac7fdbaab2db3454ccf79158b6f41e4973086f9937a7c6b737f0a2f66' \
        "$output_file" || return 97
    journal_count=$(sed -n 's/^journal_record_count=//p' "$output_file")
    [[ "$journal_count" =~ ^[0-9]+$ ]] || return 97
    [[ "$journal_count" -le 160 ]] || return 97

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
    [[ "${#fixed_markers[@]}" -eq 7 ]]
    [[ "${#evidence_prefixes[@]}" -eq 15 ]]
    verify_inspector
    printf 'action_16aq_post_cutover_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action16aq-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    success="$contract_dir/success.out"
    error_file="$contract_dir/error"
    {
        printf '%s\n' "${fixed_markers[@]}"
        printf 'check_example=true\n'
        printf 'backend_http_code=302\n'
        printf 'localhost_https_code=204\n'
        printf 'management_ipv4_http1_code=302\n'
        printf 'management_ipv4_http2_code=302\n'
        printf 'management_ipv6_http1_code=302\n'
        printf 'management_ipv6_http2_code=302\n'
        printf 'unknown_host_code=421\n'
        printf 'served_leaf_sha256=%064d\n' 1
        printf 'certificate_not_after=Jan 19 23:59:59 2027 GMT\n'
        printf 'live_lighttpd_tree_sha256=95a8752f86f1f475d7b8fd12090379c4ae46b9f4140212c7405586c222383372\n'
        printf 'original_lighttpd_tree_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92\n'
        printf 'candidate_lighttpd_tree_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13\n'
        printf 'caddy_tree_sha256=6ae99faf2cb216466879f15139cdd6614234cf46d796f535387d51ecc9602161\n'
        printf 'keepalived_tree_sha256=dad64e4ac7fdbaab2db3454ccf79158b6f41e4973086f9937a7c6b737f0a2f66\n'
        printf 'journal_record_count=10\n'
        printf 'postcutover_assertion_count=1\n'
        printf 'postcutover_mismatch_count=0\n'
        printf 'first_failure=none\n'
        printf 'action_16aq_post_cutover_valid=true\n'
    } >"$success"
    : >"$error_file"
    evaluate_contract "$success" "$error_file" 0

    mismatch="$contract_dir/mismatch.out"
    sed \
        -e 's/check_example=true/check_example=false/' \
        -e 's/postcutover_mismatch_count=0/postcutover_mismatch_count=1/' \
        -e 's/first_failure=none/first_failure=example/' \
        -e 's/action_16aq_post_cutover_valid=true/action_16aq_post_cutover_valid=false/' \
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
        printf 'Duplicate Action 16aq evidence was accepted.\n' >&2
        exit 1
    fi
    malformed="$contract_dir/malformed.out"
    sed 's/check_example=true/check_Example=true/' "$success" >"$malformed"
    if evaluate_contract "$malformed" "$error_file" 0; then
        printf 'Malformed Action 16aq evidence was accepted.\n' >&2
        exit 1
    fi
    secret="$contract_dir/secret.out"
    cp -- "$success" "$secret"
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$secret"
    if evaluate_contract "$secret" "$error_file" 0; then
        printf 'Secret-bearing Action 16aq evidence was accepted.\n' >&2
        exit 1
    fi
    if evaluate_contract "$success" "$error_file" 255; then
        printf 'Nonzero-SSH Action 16aq evidence was accepted.\n' >&2
        exit 1
    fi
    printf 'action_16aq_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_inspector
work_dir=$(mktemp -d /tmp/caddy-action16aq.XXXXXX)
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
        printf 'action_16aq_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16aq_local_cleanup_complete=true\n'
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
