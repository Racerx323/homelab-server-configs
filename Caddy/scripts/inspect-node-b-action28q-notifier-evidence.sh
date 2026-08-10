#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28q_a_notifier
readonly journal_since='2026-08-10 13:53:30'
readonly journal_until='2026-08-10 13:56:30'
readonly ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/100/IPv4
readonly ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/101/IPv6
readonly maximum_stream_bytes=131072
readonly maximum_stream_lines=1024
fixture_root=

expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact journal_query_status_zero \
        journal_stdout_safe journal_stderr_safe master_callback_exact \
        master_delivery_exact backup_callback_exact backup_delivery_failure_exact \
        backup_curl_exit_28_exact backup_timeout_5001ms_exact event_order_exact \
        ipv4_state_query_status_zero ipv4_state_stdout_safe ipv4_state_stderr_safe \
        ipv4_state_backup_exact ipv6_state_query_status_zero ipv6_state_stdout_safe \
        ipv6_state_stderr_safe ipv6_state_backup_exact
}

line_count() { awk 'END { print NR }' "$1"; }
file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
observed_uid() {
    if [[ -n "$fixture_root" ]]; then printf '0\n'; else id -u; fi
}
observed_hostname() {
    if [[ -n "$fixture_root" ]]; then printf 'j1-svpihole00\n'; else hostname; fi
}
safe_stream() {
    local action28qa_notifier_stream=$1

    # conditional-validator-explicit-failures-begin
    [[ "$(wc -c <"$action28qa_notifier_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28qa_notifier_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28qa_notifier_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:|WEBPASSWORD' \
        "$action28qa_notifier_stream" || return 1
    # conditional-validator-explicit-failures-end
}
emit_stream() {
    local action28qa_notifier_label=$1
    local action28qa_notifier_stream=$2

    printf '%s_capture_%s_bytes=%s\n' "$prefix" "$action28qa_notifier_label" \
        "$(wc -c <"$action28qa_notifier_stream")"
    printf '%s_capture_%s_lines=%s\n' "$prefix" "$action28qa_notifier_label" \
        "$(line_count "$action28qa_notifier_stream")"
    printf '%s_capture_%s_sha256=%s\n' "$prefix" "$action28qa_notifier_label" \
        "$(file_hash "$action28qa_notifier_stream")"
    if ! safe_stream "$action28qa_notifier_stream"; then
        printf '%s_capture_%s_classification=unsafe_retained\n' "$prefix" "$action28qa_notifier_label"
        return 97
    fi
    printf '%s_capture_%s_classification=bounded_safe\n' "$prefix" "$action28qa_notifier_label"
    if [[ -s "$action28qa_notifier_stream" ]]; then
        printf '%s_capture_%s_begin\n' "$prefix" "$action28qa_notifier_label"
        sed "s/^/${prefix}_capture_${action28qa_notifier_label}_content=/" \
            "$action28qa_notifier_stream"
        printf '%s_capture_%s_end\n' "$prefix" "$action28qa_notifier_label"
    else
        printf '%s_capture_%s_content=empty\n' "$prefix" "$action28qa_notifier_label"
    fi
}
check() {
    local action28qa_notifier_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28qa_notifier_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28qa_notifier_label"
    return 1
}
require() {
    local action28qa_notifier_required_label=$1

    shift
    check "$action28qa_notifier_required_label" "$@" || {
        printf '%s_first_failure=%s\n' "$prefix" "$action28qa_notifier_required_label"
        exit 1
    }
}
event_order_exact() {
    local action28qa_notifier_journal=$1
    local action28qa_notifier_master_callback
    local action28qa_notifier_master_delivery
    local action28qa_notifier_backup_callback
    local action28qa_notifier_backup_failure

    # conditional-validator-explicit-failures-begin
    action28qa_notifier_master_callback=$(grep -nF \
        'Instance PIHOLE_DUALSTACK (GROUP) changed to state: MASTER' \
        "$action28qa_notifier_journal" | cut -d: -f1) || return 1
    action28qa_notifier_master_delivery=$(grep -nF \
        'Apprise notification delivered for PIHOLE_DUALSTACK (GROUP) state MASTER' \
        "$action28qa_notifier_journal" | cut -d: -f1) || return 1
    action28qa_notifier_backup_callback=$(grep -nF \
        'Instance PIHOLE_DUALSTACK (GROUP) changed to state: BACKUP' \
        "$action28qa_notifier_journal" | cut -d: -f1) || return 1
    action28qa_notifier_backup_failure=$(grep -nF \
        'Apprise notification failed for PIHOLE_DUALSTACK (GROUP) state BACKUP:' \
        "$action28qa_notifier_journal" | cut -d: -f1) || return 1
    [[ "$action28qa_notifier_master_callback" -lt "$action28qa_notifier_master_delivery" ]] || return 1
    [[ "$action28qa_notifier_master_delivery" -lt "$action28qa_notifier_backup_callback" ]] || return 1
    [[ "$action28qa_notifier_backup_callback" -lt "$action28qa_notifier_backup_failure" ]] || return 1
    # conditional-validator-explicit-failures-end
}
run_journal_query() {
    local action28qa_notifier_stdout=$1
    local action28qa_notifier_stderr=$2

    if [[ -n "$fixture_root" ]]; then
        cat "$fixture_root/journal" >"$action28qa_notifier_stdout"
        : >"$action28qa_notifier_stderr"
        return 0
    fi
    journalctl -t keepalived-notify --since "$journal_since" --until "$journal_until" \
        --no-pager >"$action28qa_notifier_stdout" 2>"$action28qa_notifier_stderr"
}
run_state_query() {
    local action28qa_notifier_family=$1
    local action28qa_notifier_stdout=$2
    local action28qa_notifier_stderr=$3
    local action28qa_notifier_object

    if [[ "$action28qa_notifier_family" = ipv4 ]]; then
        action28qa_notifier_object=$ipv4_object
    else
        action28qa_notifier_object=$ipv6_object
    fi
    if [[ -n "$fixture_root" ]]; then
        cat "$fixture_root/${action28qa_notifier_family}-state" >"$action28qa_notifier_stdout"
        : >"$action28qa_notifier_stderr"
        return 0
    fi
    busctl get-property org.keepalived.Vrrp1 "$action28qa_notifier_object" \
        org.keepalived.Vrrp1.Instance State >"$action28qa_notifier_stdout" \
        2>"$action28qa_notifier_stderr"
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
    --fixture-root)
        [[ "${CADDY_ACTION28QA_TEST_MODE:-}" = 1 && $# -eq 2 && -d "$2" ]]
        fixture_root=$2
        ;;
    "") ;;
    *) exit 64 ;;
esac

capture_directory=$(mktemp -d /tmp/caddy-action28q-a-notifier.XXXXXX)
readonly capture_directory
cleanup() { rm -rf -- "$capture_directory"; }
trap cleanup EXIT
readonly journal_stdout=$capture_directory/journal.stdout
readonly journal_stderr=$capture_directory/journal.stderr
readonly ipv4_stdout=$capture_directory/ipv4.stdout
readonly ipv4_stderr=$capture_directory/ipv4.stderr
readonly ipv6_stdout=$capture_directory/ipv6.stdout
readonly ipv6_stderr=$capture_directory/ipv6.stderr

require identity_root test "$(observed_uid)" -eq 0
require working_directory_root test "$(pwd -P)" = /
require hostname_exact test "$(observed_hostname)" = j1-svpihole00
journal_status=0
run_journal_query "$journal_stdout" "$journal_stderr" || journal_status=$?
printf '%s_value_journal_query_status=%s\n' "$prefix" "$journal_status"
require journal_query_status_zero test "$journal_status" -eq 0
require journal_stdout_safe safe_stream "$journal_stdout"
require journal_stderr_safe safe_stream "$journal_stderr"
emit_stream journal_stdout "$journal_stdout"
emit_stream journal_stderr "$journal_stderr"
require master_callback_exact test \
    "$(grep -Fc 'Instance PIHOLE_DUALSTACK (GROUP) changed to state: MASTER' "$journal_stdout" || true)" -eq 1
require master_delivery_exact test \
    "$(grep -Fc 'Apprise notification delivered for PIHOLE_DUALSTACK (GROUP) state MASTER' "$journal_stdout" || true)" -eq 1
require backup_callback_exact test \
    "$(grep -Fc 'Instance PIHOLE_DUALSTACK (GROUP) changed to state: BACKUP' "$journal_stdout" || true)" -eq 1
require backup_delivery_failure_exact test \
    "$(grep -Fc 'Apprise notification failed for PIHOLE_DUALSTACK (GROUP) state BACKUP:' "$journal_stdout" || true)" -eq 1
require backup_curl_exit_28_exact test \
    "$(grep -Fc 'state BACKUP: curl exit 28:' "$journal_stdout" || true)" -eq 1
require backup_timeout_5001ms_exact test \
    "$(grep -Fc 'Operation timed out after 5001 milliseconds with 0 bytes received' "$journal_stdout" || true)" -eq 1
require event_order_exact event_order_exact "$journal_stdout"

ipv4_status=0
run_state_query ipv4 "$ipv4_stdout" "$ipv4_stderr" || ipv4_status=$?
printf '%s_value_ipv4_state_query_status=%s\n' "$prefix" "$ipv4_status"
require ipv4_state_query_status_zero test "$ipv4_status" -eq 0
require ipv4_state_stdout_safe safe_stream "$ipv4_stdout"
require ipv4_state_stderr_safe safe_stream "$ipv4_stderr"
emit_stream ipv4_state_stdout "$ipv4_stdout"
emit_stream ipv4_state_stderr "$ipv4_stderr"
require ipv4_state_backup_exact grep -Fqx '(us) 1 "Backup"' "$ipv4_stdout"

ipv6_status=0
run_state_query ipv6 "$ipv6_stdout" "$ipv6_stderr" || ipv6_status=$?
printf '%s_value_ipv6_state_query_status=%s\n' "$prefix" "$ipv6_status"
require ipv6_state_query_status_zero test "$ipv6_status" -eq 0
require ipv6_state_stdout_safe safe_stream "$ipv6_stdout"
require ipv6_state_stderr_safe safe_stream "$ipv6_stderr"
emit_stream ipv6_state_stdout "$ipv6_stdout"
emit_stream ipv6_state_stderr "$ipv6_stderr"
require ipv6_state_backup_exact grep -Fqx '(us) 1 "Backup"' "$ipv6_stdout"

printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
printf '%s_first_failure=none\n' "$prefix"
printf '%s_master_transition_observed=true\n' "$prefix"
printf '%s_backup_transition_observed=true\n' "$prefix"
printf '%s_backup_notification_delivery_failed=true\n' "$prefix"
printf '%s_mutation=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
