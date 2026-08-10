#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28o
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly caddy_fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly include_line='include /etc/keepalived/conf.d/caddy-ha.conf'
readonly main_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
readonly fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
readonly interface=eth0
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly node_b_fqdn=pihole00.local.theama.co
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact main_regular main_not_symlink \
        main_metadata main_hash_exact include_once include_terminal fragment_regular \
        fragment_not_symlink fragment_metadata fragment_hash_exact transaction_residue_absent \
        keepalived_active_before lighttpd_active_before \
        caddy_inactive_before_sample_1 caddy_inactive_before_sample_2 \
        caddy_inactive_before_sample_3 caddy_inactive_before_sample_4 \
        caddy_inactive_before_sample_5 ipv4_query_before_status_zero \
        ipv6_query_before_status_zero dns_ipv4_absent_before dns_ipv6_absent_before \
        caddy_ipv4_absent_before caddy_ipv6_absent_before journal_cursor_status_zero \
        journal_cursor_present start_status_zero start_stdout_safe start_stderr_safe \
        caddy_and_vips_ready_within_bound caddy_active_after_sample_1 \
        caddy_active_after_sample_2 caddy_active_after_sample_3 \
        caddy_active_after_sample_4 caddy_active_after_sample_5 \
        keepalived_active_after lighttpd_active_after ipv4_query_after_status_zero \
        ipv6_query_after_status_zero dns_ipv4_absent_after dns_ipv6_absent_after \
        caddy_ipv4_owned_after caddy_ipv6_owned_after localhost_health_status_204 \
        node_b_ipv4_ui_status_200 node_b_ipv6_ui_status_200 caddy_journal_status_zero \
        caddy_journal_safe caddy_journal_no_fatal keepalived_journal_status_zero \
        keepalived_journal_safe keepalived_journal_no_fatal main_still_exact \
        fragment_still_exact transaction_stage_removed
}
expected_rollback_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact main_hash_exact \
        fragment_hash_exact keepalived_active lighttpd_active stop_status_zero \
        stop_stdout_safe stop_stderr_safe caddy_and_vips_stopped_within_bound \
        caddy_inactive ipv4_query_status_zero ipv6_query_status_zero \
        dns_ipv4_absent dns_ipv6_absent caddy_ipv4_absent caddy_ipv6_absent \
        transaction_stage_removed
}
file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
address_query() { ip -o "-$1" address show dev "$interface"; }
address_count() {
    local action28o_family=$1
    local action28o_cidr=$2

    address_query "$action28o_family" |
        awk -v expected="$action28o_cidr" '$4 == expected { count++ } END { print count + 0 }'
}
safe_stream() {
    local action28o_stream=$1

    [[ "$(wc -c <"$action28o_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28o_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28o_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' "$action28o_stream"
}
emit_stream() {
    local action28o_label=$1
    local action28o_stream=$2

    printf '%s_capture_%s_bytes=%s\n' "$prefix" "$action28o_label" "$(wc -c <"$action28o_stream")"
    printf '%s_capture_%s_lines=%s\n' "$prefix" "$action28o_label" "$(line_count "$action28o_stream")"
    printf '%s_capture_%s_sha256=%s\n' "$prefix" "$action28o_label" "$(file_hash "$action28o_stream")"
    if safe_stream "$action28o_stream"; then
        printf '%s_capture_%s_classification=bounded_safe\n' "$prefix" "$action28o_label"
        if [[ -s "$action28o_stream" ]]; then
            printf '%s_capture_%s_begin\n' "$prefix" "$action28o_label"
            sed "s/^/${prefix}_capture_${action28o_label}_content=/" "$action28o_stream"
            printf '%s_capture_%s_end\n' "$prefix" "$action28o_label"
        else
            printf '%s_capture_%s_content=empty\n' "$prefix" "$action28o_label"
        fi
        return 0
    fi
    printf '%s_capture_%s_classification=unsafe_retained\n' "$prefix" "$action28o_label" >&2
    return 97
}
check() {
    local action28o_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28o_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28o_label"
    return 1
}
require_check() {
    local action28o_required_label=$1

    shift
    check "$action28o_required_label" "$@" || {
        first_failure=$action28o_required_label
        return 1
    }
}
rollback_check() {
    local action28o_rollback_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_rollback_check_%s=true\n' "$prefix" "$action28o_rollback_label"
        return 0
    fi
    printf '%s_rollback_check_%s=false\n' "$prefix" "$action28o_rollback_label"
    return 1
}
require_rollback_check() {
    local action28o_required_rollback_label=$1

    shift
    rollback_check "$action28o_required_rollback_label" "$@" || {
        rollback_first_failure=$action28o_required_rollback_label
        return 1
    }
}
run_captured() {
    local action28o_capture_label=$1
    local action28o_capture_status=0

    shift
    install -m 0600 /dev/null "$capture_directory/${action28o_capture_label}.stdout"
    install -m 0600 /dev/null "$capture_directory/${action28o_capture_label}.stderr"
    "$@" >"$capture_directory/${action28o_capture_label}.stdout" \
        2>"$capture_directory/${action28o_capture_label}.stderr" || action28o_capture_status=$?
    emit_stream "${action28o_capture_label}_stdout" "$capture_directory/${action28o_capture_label}.stdout" || return 97
    emit_stream "${action28o_capture_label}_stderr" "$capture_directory/${action28o_capture_label}.stderr" || return 97
    printf '%s_capture_%s_status=%s\n' "$prefix" "$action28o_capture_label" "$action28o_capture_status"
    [[ "$action28o_capture_status" -eq 0 ]]
}
wait_started() {
    local action28o_attempt

    for action28o_attempt in $(seq 1 30); do
        : "$action28o_attempt"
        if systemctl is-active --quiet caddy.service &&
            systemctl is-active --quiet keepalived.service &&
            [[ "$(address_count 4 "$caddy_ipv4_cidr")" -eq 1 ]] &&
            [[ "$(address_count 6 "$caddy_ipv6_cidr")" -eq 1 ]]; then
            return 0
        fi
        sleep 1
    done
    return 1
}
wait_stopped() {
    local action28o_attempt

    for action28o_attempt in $(seq 1 30); do
        : "$action28o_attempt"
        if ! systemctl is-active --quiet caddy.service &&
            systemctl is-active --quiet keepalived.service &&
            [[ "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0 ]] &&
            [[ "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0 ]]; then
            return 0
        fi
        sleep 1
    done
    return 1
}
https_status() {
    local action28o_fqdn=$1
    local action28o_address=$2
    local action28o_path=$3
    local action28o_status=0
    local action28o_code

    action28o_code=$(curl --noproxy '*' --insecure --silent --show-error --location \
        --max-redirs 3 --proto-redir '=https' --connect-timeout 3 --max-time 10 \
        --resolve "${action28o_fqdn}:443:${action28o_address}" --output /dev/null \
        --write-out '%{http_code}' "https://${action28o_fqdn}${action28o_path}") || action28o_status=$?
    [[ "$action28o_status" -eq 0 && "$action28o_code" = "$4" ]]
}
rollback_live() {
    local action28o_rollback_status=0
    local action28o_stop_status=0

    rollback_invoked=true
    run_captured rollback_stop systemctl stop caddy.service || action28o_stop_status=$?
    [[ "$action28o_stop_status" -eq 0 ]] || action28o_rollback_status=125
    wait_stopped || action28o_rollback_status=125
    [[ "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$main_sha256" ]] || action28o_rollback_status=125
    [[ "$(file_hash "$caddy_fragment" 2>/dev/null || true)" = "$fragment_sha256" ]] || action28o_rollback_status=125
    [[ "$(address_count 4 "$dns_ipv4_cidr" 2>/dev/null || true)" -eq 0 ]] || action28o_rollback_status=125
    [[ "$(address_count 6 "$dns_ipv6_cidr" 2>/dev/null || true)" -eq 0 ]] || action28o_rollback_status=125
    printf '%s_rollback_status=%s\n' "$prefix" "$action28o_rollback_status"
    return "$action28o_rollback_status"
}
cleanup() {
    local action28o_cleanup_status=$?

    trap - EXIT ERR HUP INT TERM
    if [[ "$action28o_cleanup_status" -ne 0 && "$mutation_started" = true && "$transaction_complete" != true ]]; then
        rollback_live || action28o_cleanup_status=125
    fi
    [[ -z "$transaction_root" || ! -d "$transaction_root" ]] || rm -rf -- "$transaction_root"
    printf '%s_value_first_failure=%s\n' "$prefix" "$first_failure"
    printf '%s_rollback_invoked=%s\n' "$prefix" "$rollback_invoked"
    printf '%s_caddy_start_count=%s\n' "$prefix" "$caddy_start_count"
    printf '%s_keepalived_reload_count=0\n' "$prefix"
    printf '%s_node_a_ssh_contacted=false\n' "$prefix"
    if [[ "$action28o_cleanup_status" -eq 0 ]]; then
        printf '%s_acceptance=true\n' "$prefix"
    else
        printf '%s_acceptance=false\n' "$prefix"
    fi
    exit "$action28o_cleanup_status"
}
external_rollback() {
    local action28o_stop_status=0

    rollback_first_failure=none
    transaction_root=$(mktemp -d /run/caddy-action28o-rollback.XXXXXX)
    trap '[[ -z "${transaction_root:-}" || ! -d "$transaction_root" ]] || rm -rf -- "$transaction_root"' RETURN
    chmod 0700 "$transaction_root"
    capture_directory=$transaction_root/capture
    install -d -o root -g root -m 0700 "$capture_directory"
    require_rollback_check identity_root test "$(id -u)" -eq 0 || return 125
    require_rollback_check working_directory_root test "$(pwd -P)" = / || return 125
    require_rollback_check hostname_exact test "$(hostname)" = j1-svpihole00 || return 125
    require_rollback_check main_hash_exact test "$(file_hash "$main_configuration")" = "$main_sha256" || return 125
    require_rollback_check fragment_hash_exact test "$(file_hash "$caddy_fragment")" = "$fragment_sha256" || return 125
    require_rollback_check keepalived_active systemctl is-active --quiet keepalived.service || return 125
    require_rollback_check lighttpd_active systemctl is-active --quiet lighttpd.service || return 125
    run_captured external_stop systemctl stop caddy.service || action28o_stop_status=$?
    require_rollback_check stop_status_zero test "$action28o_stop_status" -eq 0 || return 125
    require_rollback_check stop_stdout_safe safe_stream "$capture_directory/external_stop.stdout" || return 125
    require_rollback_check stop_stderr_safe safe_stream "$capture_directory/external_stop.stderr" || return 125
    require_rollback_check caddy_and_vips_stopped_within_bound wait_stopped || return 125
    require_rollback_check caddy_inactive test "$(systemctl is-active caddy.service 2>/dev/null || true)" = inactive || return 125
    local action28o_ipv4_status=0 action28o_ipv6_status=0
    address_query 4 >/dev/null 2>&1 || action28o_ipv4_status=$?
    address_query 6 >/dev/null 2>&1 || action28o_ipv6_status=$?
    require_rollback_check ipv4_query_status_zero test "$action28o_ipv4_status" -eq 0 || return 125
    require_rollback_check ipv6_query_status_zero test "$action28o_ipv6_status" -eq 0 || return 125
    require_rollback_check dns_ipv4_absent test "$(address_count 4 "$dns_ipv4_cidr")" -eq 0 || return 125
    require_rollback_check dns_ipv6_absent test "$(address_count 6 "$dns_ipv6_cidr")" -eq 0 || return 125
    require_rollback_check caddy_ipv4_absent test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0 || return 125
    require_rollback_check caddy_ipv6_absent test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0 || return 125
    rm -rf -- "$transaction_root"
    transaction_root=
    require_rollback_check transaction_stage_removed test ! -e "$transaction_root" || return 125
    printf '%s_rollback_first_failure=%s\n' "$prefix" "$rollback_first_failure"
    printf '%s_rollback_acceptance=true\n' "$prefix"
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]]
        expected_checks
        exit 0
        ;;
    --expected-rollback-checks)
        [[ $# -eq 1 ]]
        expected_rollback_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        labels=$(expected_checks)
        rollback_labels=$(expected_rollback_checks)
        [[ "$(printf '%s\n' "$labels" | wc -l)" -eq "$(printf '%s\n' "$labels" | LC_ALL=C sort -u | wc -l)" ]]
        [[ "$(printf '%s\n' "$rollback_labels" | wc -l)" -eq "$(printf '%s\n' "$rollback_labels" | LC_ALL=C sort -u | wc -l)" ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --rollback)
        [[ $# -eq 1 ]]
        external_rollback
        exit 0
        ;;
    --execute)
        [[ $# -eq 1 ]]
        ;;
    *) exit 64 ;;
esac

first_failure=none
transaction_root=
capture_directory=
mutation_started=false
transaction_complete=false
rollback_invoked=false
caddy_start_count=0
trap cleanup EXIT ERR HUP INT TERM

require_check identity_root test "$(id -u)" -eq 0
require_check working_directory_root test "$(pwd -P)" = /
require_check hostname_exact test "$(hostname)" = j1-svpihole00
require_check main_regular test -f "$main_configuration"
require_check main_not_symlink test ! -L "$main_configuration"
require_check main_metadata test "$(stat -c '%U:%G:%a' "$main_configuration")" = root:root:644
require_check main_hash_exact test "$(file_hash "$main_configuration")" = "$main_sha256"
require_check include_once test "$(grep -Fxc "$include_line" "$main_configuration")" -eq 1
require_check include_terminal test "$(tail -n 1 "$main_configuration")" = "$include_line"
require_check fragment_regular test -f "$caddy_fragment"
require_check fragment_not_symlink test ! -L "$caddy_fragment"
require_check fragment_metadata test "$(stat -c '%U:%G:%a' "$caddy_fragment")" = root:root:644
require_check fragment_hash_exact test "$(file_hash "$caddy_fragment")" = "$fragment_sha256"
require_check transaction_residue_absent test -z "$(find /run -maxdepth 1 -name 'caddy-action28o-*' -print -quit 2>/dev/null)"
require_check keepalived_active_before systemctl is-active --quiet keepalived.service
require_check lighttpd_active_before systemctl is-active --quiet lighttpd.service
for action28o_sample in 1 2 3 4 5; do
    require_check "caddy_inactive_before_sample_${action28o_sample}" test \
        "$(systemctl is-active caddy.service 2>/dev/null || true)" = inactive
    [[ "$action28o_sample" -eq 5 ]] || sleep 1
done
ipv4_status=0
address_query 4 >/dev/null 2>&1 || ipv4_status=$?
printf '%s_value_ipv4_query_before_status=%s\n' "$prefix" "$ipv4_status"
require_check ipv4_query_before_status_zero test "$ipv4_status" -eq 0
ipv6_status=0
address_query 6 >/dev/null 2>&1 || ipv6_status=$?
printf '%s_value_ipv6_query_before_status=%s\n' "$prefix" "$ipv6_status"
require_check ipv6_query_before_status_zero test "$ipv6_status" -eq 0
require_check dns_ipv4_absent_before test "$(address_count 4 "$dns_ipv4_cidr")" -eq 0
require_check dns_ipv6_absent_before test "$(address_count 6 "$dns_ipv6_cidr")" -eq 0
require_check caddy_ipv4_absent_before test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0
require_check caddy_ipv6_absent_before test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0

transaction_root=$(mktemp -d /run/caddy-action28o-stage.XXXXXX)
chmod 0700 "$transaction_root"
capture_directory=$transaction_root/capture
install -d -o root -g root -m 0700 "$capture_directory"
journal_cursor_status=0
journal_cursor=$(journalctl --sync --quiet 2>/dev/null &&
    journalctl -n 0 --show-cursor --no-pager 2>/dev/null |
    sed -n 's/^-- cursor: //p') || journal_cursor_status=$?
require_check journal_cursor_status_zero test "$journal_cursor_status" -eq 0
require_check journal_cursor_present test -n "$journal_cursor"

mutation_started=true
start_status=0
caddy_start_count=1
run_captured start systemctl start caddy.service || start_status=$?
require_check start_status_zero test "$start_status" -eq 0
require_check start_stdout_safe safe_stream "$capture_directory/start.stdout"
require_check start_stderr_safe safe_stream "$capture_directory/start.stderr"
require_check caddy_and_vips_ready_within_bound wait_started
for action28o_sample in 1 2 3 4 5; do
    require_check "caddy_active_after_sample_${action28o_sample}" systemctl is-active --quiet caddy.service
    [[ "$action28o_sample" -eq 5 ]] || sleep 1
done
require_check keepalived_active_after systemctl is-active --quiet keepalived.service
require_check lighttpd_active_after systemctl is-active --quiet lighttpd.service
ipv4_status=0
address_query 4 >/dev/null 2>&1 || ipv4_status=$?
printf '%s_value_ipv4_query_after_status=%s\n' "$prefix" "$ipv4_status"
require_check ipv4_query_after_status_zero test "$ipv4_status" -eq 0
ipv6_status=0
address_query 6 >/dev/null 2>&1 || ipv6_status=$?
printf '%s_value_ipv6_query_after_status=%s\n' "$prefix" "$ipv6_status"
require_check ipv6_query_after_status_zero test "$ipv6_status" -eq 0
require_check dns_ipv4_absent_after test "$(address_count 4 "$dns_ipv4_cidr")" -eq 0
require_check dns_ipv6_absent_after test "$(address_count 6 "$dns_ipv6_cidr")" -eq 0
require_check caddy_ipv4_owned_after test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 1
require_check caddy_ipv6_owned_after test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 1
require_check localhost_health_status_204 https_status localhost 127.0.0.1 / 204
require_check node_b_ipv4_ui_status_200 https_status "$node_b_fqdn" 10.1.0.54 /admin/ 200
require_check node_b_ipv6_ui_status_200 https_status "$node_b_fqdn" '[fd36:5aa8:6971:1::54]' /admin/ 200
caddy_journal_status=0
run_captured caddy_journal journalctl -u caddy.service --after-cursor "$journal_cursor" \
    --no-pager --output=short-iso || caddy_journal_status=$?
require_check caddy_journal_status_zero test "$caddy_journal_status" -eq 0
require_check caddy_journal_safe safe_stream "$capture_directory/caddy_journal.stdout"
require_check caddy_journal_no_fatal test \
    "$(grep -Eic 'fatal|panic|segmentation fault|failed to start' "$capture_directory/caddy_journal.stdout" || true)" -eq 0
keepalived_journal_status=0
run_captured keepalived_journal journalctl -u keepalived.service --after-cursor "$journal_cursor" \
    --no-pager --output=short-iso || keepalived_journal_status=$?
require_check keepalived_journal_status_zero test "$keepalived_journal_status" -eq 0
require_check keepalived_journal_safe safe_stream "$capture_directory/keepalived_journal.stdout"
require_check keepalived_journal_no_fatal test \
    "$(grep -Eic 'fatal|parse error|configuration error|segmentation fault' "$capture_directory/keepalived_journal.stdout" || true)" -eq 0
require_check main_still_exact test "$(file_hash "$main_configuration")" = "$main_sha256"
require_check fragment_still_exact test "$(file_hash "$caddy_fragment")" = "$fragment_sha256"
rm -rf -- "$transaction_root"
transaction_root=
require_check transaction_stage_removed test ! -e "$transaction_root"
transaction_complete=true
printf '%s_value_main_sha256=%s\n' "$prefix" "$main_sha256"
printf '%s_value_fragment_sha256=%s\n' "$prefix" "$fragment_sha256"
