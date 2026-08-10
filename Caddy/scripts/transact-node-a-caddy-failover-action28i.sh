#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28i_transaction
readonly interface=eth0
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly wait_iterations=20
readonly wait_seconds=2

expected_checks() {
    printf '%s\n' identity_root working_directory_root hostname_exact keepalived_active \
        mode_valid caddy_precondition_expected vrrp_precondition_expected \
        ipv4_query_before_status_zero ipv6_query_before_status_zero \
        caddy_ipv4_precondition_expected caddy_ipv6_precondition_expected \
        service_command_status_zero service_stdout_safe service_stderr_safe \
        readiness_reached caddy_final_state_expected vrrp_final_state_expected \
        ipv4_query_after_status_zero ipv6_query_after_status_zero \
        caddy_ipv4_final_count_expected caddy_ipv6_final_count_expected
}

mode=${1:-}
case "$mode" in
    --failover | --rollback) [[ $# -eq 1 ]] || exit 64 ;;
    --expected-checks)
        [[ $# -eq 1 ]] || exit 64
        expected_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        labels=$(expected_checks) || exit 1
        [[ "$(printf '%s\n' "$labels" | wc -l)" -eq "$(printf '%s\n' "$labels" | LC_ALL=C sort -u | wc -l)" ]] || exit 1
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    *) exit 64 ;;
esac

if [[ "$mode" = --failover ]]; then
    readonly expected_before_caddy=active expected_before_vrrp=MASTER expected_before_count=1
    readonly systemctl_verb=stop expected_after_caddy=inactive expected_after_vrrp=FAULT expected_after_count=0
else
    readonly expected_before_caddy=inactive expected_before_vrrp=FAULT expected_before_count=0
    readonly systemctl_verb=start expected_after_caddy=active expected_after_vrrp=MASTER expected_after_count=1
fi

failed_check_count=0
first_failure=none
mutation_started=false
capture_directory=
file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
record_check() {
    local action28i_tx_check_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28i_tx_check_label"
    else
        printf '%s_check_%s=false\n' "$prefix" "$action28i_tx_check_label"
        failed_check_count=$((failed_check_count + 1))
        [[ "$first_failure" != none ]] || first_failure=$action28i_tx_check_label
    fi
    return 0
}
safe_stream() {
    local action28i_tx_stream=$1
    [[ "$(wc -c <"$action28i_tx_stream")" -le 131072 ]] || return 1
    [[ "$(line_count "$action28i_tx_stream")" -le 1024 ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28i_tx_stream" >/dev/null || return 1
}
emit_stream() {
    local action28i_tx_label=$1
    local action28i_tx_stream=$2
    printf '%s_value_%s_bytes=%s\n' "$prefix" "$action28i_tx_label" "$(wc -c <"$action28i_tx_stream")"
    printf '%s_value_%s_lines=%s\n' "$prefix" "$action28i_tx_label" "$(line_count "$action28i_tx_stream")"
    printf '%s_value_%s_sha256=%s\n' "$prefix" "$action28i_tx_label" "$(file_hash "$action28i_tx_stream")"
    if [[ -s "$action28i_tx_stream" ]]; then
        printf '%s_value_%s_content_begin\n' "$prefix" "$action28i_tx_label"
        sed "s/^/${prefix}_value_${action28i_tx_label}_content=/" "$action28i_tx_stream"
        printf '%s_value_%s_content_end\n' "$prefix" "$action28i_tx_label"
    else
        printf '%s_value_%s_content=empty\n' "$prefix" "$action28i_tx_label"
    fi
}
address_query() { ip -o "-$1" address show dev "$interface"; }
address_count() {
    local action28i_tx_family=$1
    local action28i_tx_cidr=$2
    address_query "$action28i_tx_family" | awk -v expected="$action28i_tx_cidr" '$4 == expected { count++ } END { print count + 0 }'
}
ready() {
    [[ "$(systemctl is-active caddy.service 2>/dev/null || true)" = "$expected_after_caddy" ]] || return 1
    [[ "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = "$expected_after_vrrp" ]] || return 1
    [[ "$(address_count 4 "$caddy_ipv4_cidr")" -eq "$expected_after_count" ]] || return 1
    [[ "$(address_count 6 "$caddy_ipv6_cidr")" -eq "$expected_after_count" ]]
}
cleanup() {
    [[ -z "$capture_directory" ]] || rm -rf -- "$capture_directory"
}
trap cleanup EXIT

record_check identity_root test "$(id -u)" -eq 0
record_check working_directory_root test "$(pwd -P)" = /
record_check hostname_exact test "$(hostname)" = j1-svpihole0
record_check keepalived_active systemctl is-active --quiet keepalived.service
record_check mode_valid test "$mode" = --failover -o "$mode" = --rollback
record_check caddy_precondition_expected test "$(systemctl is-active caddy.service 2>/dev/null || true)" = "$expected_before_caddy"
record_check vrrp_precondition_expected test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = "$expected_before_vrrp"
ipv4_before_status=0
address_query 4 >/dev/null 2>&1 || ipv4_before_status=$?
ipv6_before_status=0
address_query 6 >/dev/null 2>&1 || ipv6_before_status=$?
record_check ipv4_query_before_status_zero test "$ipv4_before_status" -eq 0
record_check ipv6_query_before_status_zero test "$ipv6_before_status" -eq 0
record_check caddy_ipv4_precondition_expected test "$(address_count 4 "$caddy_ipv4_cidr")" -eq "$expected_before_count"
record_check caddy_ipv6_precondition_expected test "$(address_count 6 "$caddy_ipv6_cidr")" -eq "$expected_before_count"
if [[ "$failed_check_count" -ne 0 ]]; then
    printf '%s_failed_check_count=%s\n%s_first_failure=%s\n' "$prefix" "$failed_check_count" "$prefix" "$first_failure"
    exit 1
fi

capture_directory=$(mktemp -d /run/caddy-action28i-transaction.XXXXXX)
chmod 0700 "$capture_directory"
stdout_path=$capture_directory/systemctl.stdout
stderr_path=$capture_directory/systemctl.stderr
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"
mutation_started=true
service_status=0
systemctl "$systemctl_verb" caddy.service >"$stdout_path" 2>"$stderr_path" || service_status=$?
emit_stream service_stdout "$stdout_path"
emit_stream service_stderr "$stderr_path"
record_check service_command_status_zero test "$service_status" -eq 0
record_check service_stdout_safe safe_stream "$stdout_path"
record_check service_stderr_safe safe_stream "$stderr_path"
readiness=false
for ((iteration = 1; iteration <= wait_iterations; iteration++)); do
    if ready; then
        readiness=true
        break
    fi
    sleep "$wait_seconds"
done
record_check readiness_reached test "$readiness" = true
record_check caddy_final_state_expected test "$(systemctl is-active caddy.service 2>/dev/null || true)" = "$expected_after_caddy"
record_check vrrp_final_state_expected test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = "$expected_after_vrrp"
ipv4_after_status=0
address_query 4 >/dev/null 2>&1 || ipv4_after_status=$?
ipv6_after_status=0
address_query 6 >/dev/null 2>&1 || ipv6_after_status=$?
record_check ipv4_query_after_status_zero test "$ipv4_after_status" -eq 0
record_check ipv6_query_after_status_zero test "$ipv6_after_status" -eq 0
record_check caddy_ipv4_final_count_expected test "$(address_count 4 "$caddy_ipv4_cidr")" -eq "$expected_after_count"
record_check caddy_ipv6_final_count_expected test "$(address_count 6 "$caddy_ipv6_cidr")" -eq "$expected_after_count"
printf '%s_value_mode=%s\n' "$prefix" "${mode#--}"
printf '%s_value_service_status=%s\n' "$prefix" "$service_status"
printf '%s_value_mutation_started=%s\n' "$prefix" "$mutation_started"
printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
printf '%s_failed_check_count=%s\n' "$prefix" "$failed_check_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_publisher_invoked=false\n' "$prefix"
if [[ "$failed_check_count" -ne 0 ]]; then
    printf '%s_acceptance=false\n' "$prefix"
    exit 1
fi
printf '%s_acceptance=true\n' "$prefix"
