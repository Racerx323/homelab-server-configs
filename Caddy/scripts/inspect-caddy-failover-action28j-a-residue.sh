#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28j_a_residue
readonly transaction_parent=/run
readonly transaction_pattern='caddy-action28j-transaction.*'

expected_checks() {
    printf '%s\n' identity_root working_directory_root role_valid hostname_exact \
        transaction_parent_directory transaction_query_status_zero \
        transaction_query_output_safe transaction_residue_absent snapshot_stable
}
safe_text() {
    local action28j_a_residue_text=$1

    [[ ${#action28j_a_residue_text} -le 131072 ]] || return 1
    ! printf '%s' "$action28j_a_residue_text" | LC_ALL=C grep -q '[^[:print:][:space:]]'
}
record_check() {
    local action28j_a_residue_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28j_a_residue_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28j_a_residue_label"
    failed_check_count=$((failed_check_count + 1))
    [[ "$first_failure" != none ]] || first_failure=$action28j_a_residue_label
    return 0
}
query_residue() {
    find "$transaction_parent" -maxdepth 1 -type d -name "$transaction_pattern" -print | LC_ALL=C sort
}
snapshot() {
    {
        printf 'role=%s\n' "$role"
        printf 'hostname=%s\n' "$(hostname)"
        query_residue
    } | sha256sum | awk '{ print $1 }'
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]] || exit 64
        expected_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        labels=$(expected_checks) || exit 1
        readonly labels
        [[ "$(printf '%s\n' "$labels" | wc -l)" -eq "$(printf '%s\n' "$labels" | LC_ALL=C sort -u | wc -l)" ]] || exit 1
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    node-a | node-b)
        [[ $# -eq 1 ]] || exit 64
        readonly role=$1
        ;;
    *) exit 64 ;;
esac

case "$role" in
    node-a) readonly expected_hostname=j1-svpihole0 ;;
    node-b) readonly expected_hostname=j1-svpihole00 ;;
esac

failed_check_count=0
first_failure=none
snapshot_before=$(snapshot)
readonly snapshot_before
transaction_query_status=0
transaction_query_output=$(query_residue 2>&1) || transaction_query_status=$?
readonly transaction_query_status transaction_query_output
transaction_residue_count=$(printf '%s\n' "$transaction_query_output" | awk 'NF { count++ } END { print count + 0 }')
readonly transaction_residue_count

record_check identity_root test "$(id -u)" -eq 0
record_check working_directory_root test "$(pwd -P)" = /
record_check role_valid test "$role" = node-a -o "$role" = node-b
record_check hostname_exact test "$(hostname)" = "$expected_hostname"
record_check transaction_parent_directory test -d "$transaction_parent"
record_check transaction_query_status_zero test "$transaction_query_status" -eq 0
record_check transaction_query_output_safe safe_text "$transaction_query_output"
record_check transaction_residue_absent test "$transaction_residue_count" -eq 0
record_check snapshot_stable test "$(snapshot)" = "$snapshot_before"

printf '%s_value_role=%s\n' "$prefix" "$role"
printf '%s_value_transaction_residue_count=%s\n' "$prefix" "$transaction_residue_count"
printf '%s_value_snapshot_sha256=%s\n' "$prefix" "$snapshot_before"
printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
printf '%s_failed_check_count=%s\n' "$prefix" "$failed_check_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_cleanup_executed=false\n' "$prefix"
if [[ "$failed_check_count" -ne 0 ]]; then
    printf '%s_acceptance=false\n' "$prefix"
    exit 1
fi
printf '%s_acceptance=true\n' "$prefix"
