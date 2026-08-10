#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28r_a
readonly retained_cursor='s=b120595ff27149a9b51cc363decde165;i=74d5a5;b=8a45746a5c624b1aa42b11e901a02bfc;m=bf67ad835;t=658b706074b90;x=8deffc60c97e9236'
readonly interface=eth0
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/100/IPv4
readonly ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/101/IPv6
readonly accepted_node_a_main_sha256=6162cfb9d83f7e524db1df6a3b041ced90a7639fceaf28eacf713270c2a66a65
readonly accepted_node_a_fragment_sha256=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
readonly accepted_node_b_main_sha256=9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148
readonly accepted_node_b_fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096
fixture_root=${CADDY_ACTION28RA_FIXTURE_ROOT:-}
[[ -z "$fixture_root" || "${CADDY_ACTION28RA_TEST_MODE:-}" = 1 ]] || exit 64
readonly fixture_root

line_count() { awk 'END { print NR }' "$1"; }
file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
safe_stream() {
    local action28ra_stream=$1

    # conditional-validator-explicit-failures-begin
    [[ "$(wc -c <"$action28ra_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28ra_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28ra_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:|WEBPASSWORD' "$action28ra_stream" || return 1
    # conditional-validator-explicit-failures-end
}
emit_stream() {
    local action28ra_label=$1
    local action28ra_stream=$2

    printf '%s_capture_%s_bytes=%s\n' "$prefix" "$action28ra_label" "$(wc -c <"$action28ra_stream")"
    printf '%s_capture_%s_lines=%s\n' "$prefix" "$action28ra_label" "$(line_count "$action28ra_stream")"
    printf '%s_capture_%s_sha256=%s\n' "$prefix" "$action28ra_label" "$(file_hash "$action28ra_stream")"
    if ! safe_stream "$action28ra_stream"; then
        printf '%s_capture_%s_classification=unsafe_retained\n' "$prefix" "$action28ra_label"
        return 97
    fi
    printf '%s_capture_%s_classification=bounded_safe\n' "$prefix" "$action28ra_label"
    if [[ -s "$action28ra_stream" ]]; then
        printf '%s_capture_%s_begin\n' "$prefix" "$action28ra_label"
        sed "s/^/${prefix}_capture_${action28ra_label}_content=/" "$action28ra_stream"
        printf '%s_capture_%s_end\n' "$prefix" "$action28ra_label"
    else
        printf '%s_capture_%s_content=empty\n' "$prefix" "$action28ra_label"
    fi
}
expected_checks() {
    printf '%s\n' identity_root working_directory_root hostname_exact cursor_exact \
        main_regular main_not_symlink main_hash_exact main_caddy_include_absent fragment_regular \
        fragment_not_symlink fragment_hash_exact keepalived_active caddy_active \
        lighttpd_active ipv4_query_status_zero ipv6_query_status_zero \
        ipv4_state_query_status_zero ipv6_state_query_status_zero ipv4_state_exact \
        ipv6_state_exact dns_ipv4_count_exact dns_ipv6_count_exact \
        caddy_ipv4_count_exact caddy_ipv6_count_exact keepalived_journal_status_zero \
        keepalived_journal_stdout_safe keepalived_journal_stderr_safe \
        keepalived_journal_nonempty notifier_journal_status_zero \
        notifier_journal_stdout_safe notifier_journal_stderr_safe
}
record_check() {
    local action28ra_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28ra_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28ra_label"
    if [[ "$first_failure" = none ]]; then first_failure=$action28ra_label; fi
    failure_count=$((failure_count + 1))
    return 0
}
observed_uid() { if [[ -n "$fixture_root" ]]; then printf '0\n'; else id -u; fi; }
observed_hostname() {
    if [[ -n "$fixture_root" ]]; then
        if [[ "$role" = node_a ]]; then printf 'j1-svpihole0\n'; else printf 'j1-svpihole00\n'; fi
    else
        hostname
    fi
}
# Invoked indirectly through record_check's command boundary.
# shellcheck disable=SC2317
service_active() {
    if [[ -n "$fixture_root" ]]; then
        grep -Fqx "$1=active" "$fixture_root/services"
    else
        systemctl is-active --quiet "$1"
    fi
}
address_query() {
    if [[ -n "$fixture_root" ]]; then
        cat "$fixture_root/ipv$1"
    else
        ip -o "-$1" address show dev "$interface"
    fi
}
address_count() {
    local action28ra_file=$1
    local action28ra_cidr=$2

    awk -v expected="$action28ra_cidr" '$4 == expected { count++ } END { print count + 0 }' "$action28ra_file"
}
state_query() {
    local action28ra_family=$1
    local action28ra_object=$2

    if [[ -n "$fixture_root" ]]; then
        cat "$fixture_root/${action28ra_family}-state"
    else
        busctl --system --no-pager get-property org.keepalived.Vrrp1 "$action28ra_object" org.keepalived.Vrrp1.Instance State
    fi
}
journal_query() {
    local action28ra_kind=$1

    if [[ -n "$fixture_root" ]]; then
        cat "$fixture_root/${action28ra_kind}-journal"
    elif [[ "$action28ra_kind" = keepalived ]]; then
        journalctl -u keepalived.service --after-cursor "$retained_cursor" --no-pager --output=short-iso
    else
        journalctl -t keepalived-notify --after-cursor "$retained_cursor" --no-pager --output=short-iso
    fi
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]]
        expected_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$(expected_checks | wc -l)" -eq "$(expected_checks | LC_ALL=C sort -u | wc -l)" ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --node-a | --node-b)
        [[ $# -eq 1 ]]
        role=${1#--node-}
        role=node_$role
        ;;
    *) exit 64 ;;
esac
readonly role

if [[ "$role" = node_a ]]; then
    expected_hostname=j1-svpihole0
    expected_main_sha256=${CADDY_ACTION28RA_NODE_A_MAIN_SHA256:-$accepted_node_a_main_sha256}
    expected_fragment_sha256=${CADDY_ACTION28RA_NODE_A_FRAGMENT_SHA256:-$accepted_node_a_fragment_sha256}
    expected_ipv4_state='(us) 2 "Master"'
    expected_ipv6_state='(us) 2 "Master"'
    expected_dns_ipv4_count=1
    expected_dns_ipv6_count=1
else
    expected_hostname=j1-svpihole00
    expected_main_sha256=${CADDY_ACTION28RA_NODE_B_MAIN_SHA256:-$accepted_node_b_main_sha256}
    expected_fragment_sha256=${CADDY_ACTION28RA_NODE_B_FRAGMENT_SHA256:-$accepted_node_b_fragment_sha256}
    expected_ipv4_state='(us) 1 "Backup"'
    expected_ipv6_state='(us) 1 "Backup"'
    expected_dns_ipv4_count=0
    expected_dns_ipv6_count=0
fi
readonly expected_hostname expected_main_sha256 expected_fragment_sha256
readonly expected_ipv4_state expected_ipv6_state expected_dns_ipv4_count expected_dns_ipv6_count

main_configuration=$fixture_root/etc/keepalived/keepalived.conf
caddy_fragment=$fixture_root/etc/keepalived/conf.d/caddy-ha.conf
[[ -n "$fixture_root" ]] || {
    main_configuration=/etc/keepalived/keepalived.conf
    caddy_fragment=/etc/keepalived/conf.d/caddy-ha.conf
}
readonly main_configuration caddy_fragment
capture_directory=$(mktemp -d /tmp/caddy-action28r-a.XXXXXX)
readonly capture_directory
trap 'rm -rf -- "$capture_directory"' EXIT
chmod 0700 "$capture_directory"
first_failure=none
failure_count=0

record_check identity_root test "$(observed_uid)" -eq 0
record_check working_directory_root test "$(pwd -P)" = /
record_check hostname_exact test "$(observed_hostname)" = "$expected_hostname"
record_check cursor_exact test "$retained_cursor" = 's=b120595ff27149a9b51cc363decde165;i=74d5a5;b=8a45746a5c624b1aa42b11e901a02bfc;m=bf67ad835;t=658b706074b90;x=8deffc60c97e9236'
record_check main_regular test -f "$main_configuration"
record_check main_not_symlink test ! -L "$main_configuration"
observed_main_sha256=$(file_hash "$main_configuration" 2>/dev/null || true)
printf '%s_value_expected_main_sha256=%s\n' "$prefix" "$expected_main_sha256"
printf '%s_value_observed_main_sha256=%s\n' "$prefix" "$observed_main_sha256"
record_check main_hash_exact test "$observed_main_sha256" = "$expected_main_sha256"
record_check main_caddy_include_absent test "$(grep -Fxc 'include /etc/keepalived/conf.d/caddy-ha.conf' "$main_configuration" || true)" -eq 0
record_check fragment_regular test -f "$caddy_fragment"
record_check fragment_not_symlink test ! -L "$caddy_fragment"
observed_fragment_sha256=$(file_hash "$caddy_fragment" 2>/dev/null || true)
printf '%s_value_expected_fragment_sha256=%s\n' "$prefix" "$expected_fragment_sha256"
printf '%s_value_observed_fragment_sha256=%s\n' "$prefix" "$observed_fragment_sha256"
printf '%s_value_caddy_fragment_activation=retained_inactive\n' "$prefix"
record_check fragment_hash_exact test "$observed_fragment_sha256" = "$expected_fragment_sha256"
record_check keepalived_active service_active keepalived.service
record_check caddy_active service_active caddy.service
record_check lighttpd_active service_active lighttpd.service

ipv4_status=0
ipv6_status=0
state_ipv4_status=0
state_ipv6_status=0
address_query 4 >"$capture_directory/ipv4" 2>"$capture_directory/ipv4.stderr" || ipv4_status=$?
address_query 6 >"$capture_directory/ipv6" 2>"$capture_directory/ipv6.stderr" || ipv6_status=$?
state_query ipv4 "$ipv4_object" >"$capture_directory/ipv4-state" 2>"$capture_directory/ipv4-state.stderr" || state_ipv4_status=$?
state_query ipv6 "$ipv6_object" >"$capture_directory/ipv6-state" 2>"$capture_directory/ipv6-state.stderr" || state_ipv6_status=$?
printf '%s_value_ipv4_query_status=%s\n' "$prefix" "$ipv4_status"
printf '%s_value_ipv6_query_status=%s\n' "$prefix" "$ipv6_status"
printf '%s_value_ipv4_state_query_status=%s\n' "$prefix" "$state_ipv4_status"
printf '%s_value_ipv6_state_query_status=%s\n' "$prefix" "$state_ipv6_status"
record_check ipv4_query_status_zero test "$ipv4_status" -eq 0
record_check ipv6_query_status_zero test "$ipv6_status" -eq 0
record_check ipv4_state_query_status_zero test "$state_ipv4_status" -eq 0
record_check ipv6_state_query_status_zero test "$state_ipv6_status" -eq 0
observed_ipv4_state=$(<"$capture_directory/ipv4-state")
observed_ipv6_state=$(<"$capture_directory/ipv6-state")
printf '%s_value_observed_ipv4_state=%s\n' "$prefix" "$observed_ipv4_state"
printf '%s_value_observed_ipv6_state=%s\n' "$prefix" "$observed_ipv6_state"
record_check ipv4_state_exact test "$observed_ipv4_state" = "$expected_ipv4_state"
record_check ipv6_state_exact test "$observed_ipv6_state" = "$expected_ipv6_state"
dns_ipv4_count=$(address_count "$capture_directory/ipv4" "$dns_ipv4_cidr")
dns_ipv6_count=$(address_count "$capture_directory/ipv6" "$dns_ipv6_cidr")
caddy_ipv4_count=$(address_count "$capture_directory/ipv4" "$caddy_ipv4_cidr")
caddy_ipv6_count=$(address_count "$capture_directory/ipv6" "$caddy_ipv6_cidr")
printf '%s_value_dns_ipv4_count=%s\n' "$prefix" "$dns_ipv4_count"
printf '%s_value_dns_ipv6_count=%s\n' "$prefix" "$dns_ipv6_count"
printf '%s_value_caddy_ipv4_count=%s\n' "$prefix" "$caddy_ipv4_count"
printf '%s_value_caddy_ipv6_count=%s\n' "$prefix" "$caddy_ipv6_count"
record_check dns_ipv4_count_exact test "$dns_ipv4_count" -eq "$expected_dns_ipv4_count"
record_check dns_ipv6_count_exact test "$dns_ipv6_count" -eq "$expected_dns_ipv6_count"
record_check caddy_ipv4_count_exact test "$caddy_ipv4_count" -eq 0
record_check caddy_ipv6_count_exact test "$caddy_ipv6_count" -eq 0

keepalived_status=0
notifier_status=0
journal_query keepalived >"$capture_directory/keepalived.stdout" 2>"$capture_directory/keepalived.stderr" || keepalived_status=$?
journal_query notifier >"$capture_directory/notifier.stdout" 2>"$capture_directory/notifier.stderr" || notifier_status=$?
printf '%s_value_keepalived_journal_status=%s\n' "$prefix" "$keepalived_status"
record_check keepalived_journal_status_zero test "$keepalived_status" -eq 0
record_check keepalived_journal_stdout_safe safe_stream "$capture_directory/keepalived.stdout"
record_check keepalived_journal_stderr_safe safe_stream "$capture_directory/keepalived.stderr"
record_check keepalived_journal_nonempty test -s "$capture_directory/keepalived.stdout"
emit_stream keepalived_journal_stdout "$capture_directory/keepalived.stdout" || failure_count=$((failure_count + 1))
emit_stream keepalived_journal_stderr "$capture_directory/keepalived.stderr" || failure_count=$((failure_count + 1))
printf '%s_value_notifier_journal_status=%s\n' "$prefix" "$notifier_status"
record_check notifier_journal_status_zero test "$notifier_status" -eq 0
record_check notifier_journal_stdout_safe safe_stream "$capture_directory/notifier.stdout"
record_check notifier_journal_stderr_safe safe_stream "$capture_directory/notifier.stderr"
emit_stream notifier_journal_stdout "$capture_directory/notifier.stdout" || failure_count=$((failure_count + 1))
emit_stream notifier_journal_stderr "$capture_directory/notifier.stderr" || failure_count=$((failure_count + 1))
printf '%s_value_keepalived_master_line_count=%s\n' "$prefix" "$(grep -Eic 'master' "$capture_directory/keepalived.stdout" || true)"
printf '%s_value_keepalived_backup_line_count=%s\n' "$prefix" "$(grep -Eic 'backup' "$capture_directory/keepalived.stdout" || true)"
printf '%s_value_notifier_master_line_count=%s\n' "$prefix" "$(grep -Eic 'state MASTER|state: MASTER' "$capture_directory/notifier.stdout" || true)"
printf '%s_value_notifier_backup_line_count=%s\n' "$prefix" "$(grep -Eic 'state BACKUP|state: BACKUP' "$capture_directory/notifier.stdout" || true)"
printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_role=%s\n' "$prefix" "$role"
printf '%s_cursor=%s\n' "$prefix" "$retained_cursor"
printf '%s_mutation=false\n' "$prefix"
if [[ "$failure_count" -eq 0 ]]; then
    printf '%s_acceptance=true\n' "$prefix"
    exit 0
fi
printf '%s_acceptance=false\n' "$prefix"
exit 1
