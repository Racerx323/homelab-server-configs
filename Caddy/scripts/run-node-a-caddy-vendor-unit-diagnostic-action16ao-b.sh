#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=6a67da4d77c680e29b98ea13ddbd1b9ab4e9194c17115af4785ca268902c5911
readonly inspector_name=diagnose-node-a-caddy-vendor-unit-action16ao-b.sh
readonly -a singleton_prefixes=(
    hostname_status
    node_hostname
    architecture_status
    node_architecture
    mask_lstat_status
    mask_path
    mask_lstat
    mask_readlink_status
    mask_link_target
    mask_canonical_status
    mask_canonical_target
    mask_canonical_stat_status
    mask_canonical_stat
    package_query_status
    package_record
    package_file_list_status
    vendor_inspection_status
    vendor_unit_record_count
    vendor_type_record_count
)
readonly -a status_prefixes=(
    hostname_status
    architecture_status
    mask_lstat_status
    mask_readlink_status
    mask_canonical_status
    mask_canonical_stat_status
    package_query_status
    package_file_list_status
    vendor_inspection_status
)
readonly -a fixed_markers=(
    action_16ao_b_remote_reached=true
    peer_connections=false
    installed_helper_execution=false
    systemd_daemon_reload_performed=false
    service_mutations=false
    action_16ao_b_diagnostic_complete=true
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
    local prefix marker unit_count type_count

    for marker in "${fixed_markers[@]}"; do
        [[ "$(grep -Fxc "$marker" "$output_file")" -eq 1 ]] || return 97
    done
    for prefix in "${singleton_prefixes[@]}"; do
        [[ "$(grep -c "^${prefix}=" "$output_file")" -eq 1 ]] || return 97
    done
    if grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=' \
        "$output_file" "$error_file"; then
        return 97
    fi
    if LC_ALL=C grep -n '[^[:print:][:space:]]' "$output_file" "$error_file" \
        >/dev/null; then
        return 97
    fi

    for prefix in "${status_prefixes[@]}"; do
        grep -Eq "^${prefix}=[0-9]+$" "$output_file" || return 97
    done
    unit_count=$(sed -n 's/^vendor_unit_record_count=//p' "$output_file")
    type_count=$(sed -n 's/^vendor_type_record_count=//p' "$output_file")
    [[ "$unit_count" =~ ^[0-9]+$ ]] || return 97
    [[ "$type_count" =~ ^[0-9]+$ ]] || return 97
    [[ "$(grep -c '^vendor_unit_record=' "$output_file" || true)" -eq "$unit_count" ]] ||
        return 97
    [[ "$(grep -c '^vendor_type_record=' "$output_file" || true)" -eq "$type_count" ]] ||
        return 97
    [[ "$ssh_status" -eq 0 ]] || return 97
    grep -Eq '^node_hostname=[A-Za-z0-9._-]+$' "$output_file" || return 97
    grep -Eq '^node_architecture=[A-Za-z0-9._-]+$' "$output_file" || return 97
    grep -Fxq 'mask_path=/etc/systemd/system/caddy.service' "$output_file" ||
        return 97
    return 0
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "${#singleton_prefixes[@]}" -eq 19 ]]
    [[ "${#status_prefixes[@]}" -eq 9 ]]
    [[ "${#fixed_markers[@]}" -eq 6 ]]
    verify_inspector
    printf 'action_16ao_b_diagnostic_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action16ao-b-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    success="$contract_dir/success.out"
    error_file="$contract_dir/error"
    {
        printf '%s\n' "${fixed_markers[@]}"
        printf 'hostname_status=0\n'
        printf 'node_hostname=j1-svpihole0\n'
        printf 'architecture_status=0\n'
        printf 'node_architecture=arm64\n'
        printf 'mask_lstat_status=0\n'
        printf 'mask_path=/etc/systemd/system/caddy.service\n'
        printf 'mask_lstat=symbolic link|root:root|777|9\n'
        printf 'mask_readlink_status=0\n'
        printf 'mask_link_target=/dev/null\n'
        printf 'mask_canonical_status=0\n'
        printf 'mask_canonical_target=/dev/null\n'
        printf 'mask_canonical_stat_status=0\n'
        printf 'mask_canonical_stat=character special file|root:root|666|0\n'
        printf 'package_query_status=0\n'
        printf 'package_record=ii |caddy|2.11.4|arm64\n'
        printf 'package_file_list_status=0\n'
        printf 'vendor_inspection_status=0\n'
        printf 'vendor_unit_record_count=1\n'
        printf 'vendor_unit_record=path=/lib/systemd/system/caddy.service|lstat_status=0|lstat=regular file|root:root|644|1200|canonical_status=0|canonical=/usr/lib/systemd/system/caddy.service|sha256_status=0|sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|owner_status=0|owner=caddy: /lib/systemd/system/caddy.service\n'
        printf 'vendor_type_record_count=1\n'
        printf 'vendor_type_record=/lib/systemd/system/caddy.service:25:Type=notify\n'
    } >"$success"
    : >"$error_file"
    evaluate_contract "$success" "$error_file" 0

    duplicate="$contract_dir/duplicate.out"
    cp -- "$success" "$duplicate"
    printf 'mask_link_target=/dev/null\n' >>"$duplicate"
    if evaluate_contract "$duplicate" "$error_file" 0; then
        printf 'Duplicate Action 16ao-b evidence was accepted.\n' >&2
        exit 1
    fi
    inconsistent="$contract_dir/inconsistent.out"
    sed 's/vendor_type_record_count=1/vendor_type_record_count=2/' \
        "$success" >"$inconsistent"
    if evaluate_contract "$inconsistent" "$error_file" 0; then
        printf 'Inconsistent Action 16ao-b evidence was accepted.\n' >&2
        exit 1
    fi
    secret="$contract_dir/secret.out"
    cp -- "$success" "$secret"
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$secret"
    if evaluate_contract "$secret" "$error_file" 0; then
        printf 'Secret-bearing Action 16ao-b evidence was accepted.\n' >&2
        exit 1
    fi
    if evaluate_contract "$success" "$error_file" 255; then
        printf 'Nonzero-SSH Action 16ao-b evidence was accepted.\n' >&2
        exit 1
    fi
    printf 'action_16ao_b_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_inspector
work_dir=$(mktemp -d /tmp/caddy-action16ao-b.XXXXXX)
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
        printf 'action_16ao_b_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16ao_b_local_cleanup_complete=true\n'
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
