#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
if [[ "${CADDY_ACTION28R_TEST_MODE:-}" = 1 ]]; then
    PATH=${CADDY_ACTION28R_TEST_PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}
else
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
fi
export PATH
readonly PATH

readonly prefix=action_28r_convergence
readonly interface=eth0
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly accepted_node_b_main_sha256=9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148
if [[ "${CADDY_ACTION28R_TEST_MODE:-}" = 1 ]]; then
    node_a_main_sha256=${CADDY_ACTION28R_NODE_A_MAIN_SHA256:-9e3dbf9760733f0ddb46ba51996cfdd9ad9af723d561ee2376de8c7c7d6ee3aa}
    node_a_fragment_sha256=${CADDY_ACTION28R_NODE_A_FRAGMENT_SHA256:-8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be}
    node_b_main_sha256=${CADDY_ACTION28R_NODE_B_MAIN_SHA256:-$accepted_node_b_main_sha256}
    node_b_fragment_sha256=${CADDY_ACTION28R_NODE_B_FRAGMENT_SHA256:-0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518}
else
    node_a_main_sha256=9e3dbf9760733f0ddb46ba51996cfdd9ad9af723d561ee2376de8c7c7d6ee3aa
    node_a_fragment_sha256=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
    node_b_main_sha256=$accepted_node_b_main_sha256
    node_b_fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
fi
readonly node_a_main_sha256 node_a_fragment_sha256 node_b_main_sha256 node_b_fragment_sha256
readonly dns_ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/100/IPv4
readonly dns_ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/101/IPv6
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096
fixture_root=${CADDY_ACTION28R_FIXTURE_ROOT:-}
[[ -z "$fixture_root" || "${CADDY_ACTION28R_TEST_MODE:-}" = 1 ]] || exit 64
readonly fixture_root
readonly main_configuration=$fixture_root/etc/keepalived/keepalived.conf
readonly caddy_fragment=$fixture_root/etc/keepalived/conf.d/caddy-ha.conf

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
address_query() { ip -o "-$1" address show dev "$interface"; }
address_count() {
    local action28r_convergence_family=$1
    local action28r_convergence_cidr=$2

    address_query "$action28r_convergence_family" |
        awk -v expected="$action28r_convergence_cidr" '$4 == expected { count++ } END { print count + 0 }'
}
state_query() {
    busctl --system --no-pager get-property org.keepalived.Vrrp1 "$1" \
        org.keepalived.Vrrp1.Instance State
}
cursor_safe() {
    LC_ALL=C grep -Eq '^[A-Za-z0-9:;=._-]+$' <<<"$1"
}
safe_stream() {
    local action28r_convergence_stream=$1

    [[ "$(wc -c <"$action28r_convergence_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28r_convergence_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28r_convergence_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' \
        "$action28r_convergence_stream"
}
emit_stream() {
    local action28r_convergence_label=$1
    local action28r_convergence_stream=$2

    printf '%s_capture_%s_bytes=%s\n' "$prefix" "$action28r_convergence_label" \
        "$(wc -c <"$action28r_convergence_stream")"
    printf '%s_capture_%s_lines=%s\n' "$prefix" "$action28r_convergence_label" \
        "$(line_count "$action28r_convergence_stream")"
    printf '%s_capture_%s_sha256=%s\n' "$prefix" "$action28r_convergence_label" \
        "$(file_hash "$action28r_convergence_stream")"
    if safe_stream "$action28r_convergence_stream"; then
        printf '%s_capture_%s_classification=bounded_safe\n' "$prefix" \
            "$action28r_convergence_label"
        if [[ -s "$action28r_convergence_stream" ]]; then
            printf '%s_capture_%s_begin\n' "$prefix" "$action28r_convergence_label"
            sed "s/^/${prefix}_capture_${action28r_convergence_label}_content=/" \
                "$action28r_convergence_stream"
            printf '%s_capture_%s_end\n' "$prefix" "$action28r_convergence_label"
        else
            printf '%s_capture_%s_content=empty\n' "$prefix" "$action28r_convergence_label"
        fi
        return 0
    fi
    printf '%s_capture_%s_classification=unsafe_retained\n' "$prefix" \
        "$action28r_convergence_label" >&2
    return 97
}
check() {
    local action28r_convergence_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28r_convergence_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28r_convergence_label"
    return 1
}
require_check() {
    local action28r_convergence_required_label=$1

    shift
    check "$action28r_convergence_required_label" "$@" || {
        first_failure=$action28r_convergence_required_label
        return 1
    }
}
expected_node_b_checks() {
    printf '%s\n' identity_root working_directory_root hostname_exact main_hash_exact \
        fragment_hash_exact keepalived_active caddy_active lighttpd_active
    local action28r_convergence_sample
    for action28r_convergence_sample in $(seq 1 15); do
        printf '%s\n' \
            "sample_${action28r_convergence_sample}_ipv4_query_status_zero" \
            "sample_${action28r_convergence_sample}_ipv6_query_status_zero" \
            "sample_${action28r_convergence_sample}_ipv4_state_query_status_zero" \
            "sample_${action28r_convergence_sample}_ipv6_state_query_status_zero"
        if [[ "$action28r_convergence_sample" -ge 11 ]]; then
            printf '%s\n' \
                "sample_${action28r_convergence_sample}_ipv4_state_backup" \
                "sample_${action28r_convergence_sample}_ipv6_state_backup" \
                "sample_${action28r_convergence_sample}_dns_ipv4_absent" \
                "sample_${action28r_convergence_sample}_dns_ipv6_absent" \
                "sample_${action28r_convergence_sample}_caddy_ipv4_absent" \
                "sample_${action28r_convergence_sample}_caddy_ipv6_absent"
        fi
    done
    printf '%s\n' keepalived_journal_status_zero keepalived_journal_safe \
        keepalived_journal_stderr_safe keepalived_journal_no_fatal \
        notifier_journal_status_zero notifier_journal_safe notifier_journal_stderr_safe \
        final_ipv4_state_backup final_ipv6_state_backup final_dns_ipv4_absent \
        final_dns_ipv6_absent final_caddy_ipv4_absent final_caddy_ipv6_absent
}
expected_node_a_checks() {
    printf '%s\n' identity_root working_directory_root hostname_exact main_hash_exact \
        fragment_hash_exact keepalived_active caddy_active lighttpd_active
    local action28r_convergence_sample
    for action28r_convergence_sample in $(seq 1 5); do
        printf '%s\n' \
            "sample_${action28r_convergence_sample}_ipv4_query_status_zero" \
            "sample_${action28r_convergence_sample}_ipv6_query_status_zero" \
            "sample_${action28r_convergence_sample}_dns_ipv4_owned" \
            "sample_${action28r_convergence_sample}_dns_ipv6_owned" \
            "sample_${action28r_convergence_sample}_caddy_ipv4_owned" \
            "sample_${action28r_convergence_sample}_caddy_ipv6_owned"
    done
    printf '%s\n' shared_admin_status_zero shared_admin_status_200 \
        shared_admin_body_safe shared_admin_title_node_a shared_admin_title_node_b_absent
}
run_captured() {
    local action28r_convergence_label=$1
    local action28r_convergence_status=0

    shift
    install -m 0600 /dev/null "$capture_directory/${action28r_convergence_label}.stdout"
    install -m 0600 /dev/null "$capture_directory/${action28r_convergence_label}.stderr"
    "$@" >"$capture_directory/${action28r_convergence_label}.stdout" \
        2>"$capture_directory/${action28r_convergence_label}.stderr" ||
        action28r_convergence_status=$?
    emit_stream "${action28r_convergence_label}_stdout" \
        "$capture_directory/${action28r_convergence_label}.stdout" || return 97
    emit_stream "${action28r_convergence_label}_stderr" \
        "$capture_directory/${action28r_convergence_label}.stderr" || return 97
    printf '%s_value_%s_status=%s\n' "$prefix" "$action28r_convergence_label" \
        "$action28r_convergence_status"
    [[ "$action28r_convergence_status" -eq 0 ]]
}
sample_node_b() {
    local action28r_convergence_sample=$1
    local action28r_convergence_ipv4_status=0
    local action28r_convergence_ipv6_status=0
    local action28r_convergence_ipv4_state_status=0
    local action28r_convergence_ipv6_state_status=0
    local action28r_convergence_ipv4_state
    local action28r_convergence_ipv6_state

    printf '%s_value_sample_%s_epoch_ms=%s\n' "$prefix" "$action28r_convergence_sample" \
        "$(date +%s%3N)"
    address_query 4 >"$capture_directory/sample-${action28r_convergence_sample}-ipv4" 2>/dev/null ||
        action28r_convergence_ipv4_status=$?
    address_query 6 >"$capture_directory/sample-${action28r_convergence_sample}-ipv6" 2>/dev/null ||
        action28r_convergence_ipv6_status=$?
    action28r_convergence_ipv4_state=$(state_query "$dns_ipv4_object" 2>/dev/null) ||
        action28r_convergence_ipv4_state_status=$?
    action28r_convergence_ipv6_state=$(state_query "$dns_ipv6_object" 2>/dev/null) ||
        action28r_convergence_ipv6_state_status=$?
    printf '%s_value_sample_%s_ipv4_state=%s\n' "$prefix" "$action28r_convergence_sample" \
        "$action28r_convergence_ipv4_state"
    printf '%s_value_sample_%s_ipv6_state=%s\n' "$prefix" "$action28r_convergence_sample" \
        "$action28r_convergence_ipv6_state"
    printf '%s_value_sample_%s_dns_ipv4_count=%s\n' "$prefix" "$action28r_convergence_sample" \
        "$(awk -v expected="$dns_ipv4_cidr" '$4 == expected { count++ } END { print count + 0 }' \
            "$capture_directory/sample-${action28r_convergence_sample}-ipv4")"
    printf '%s_value_sample_%s_dns_ipv6_count=%s\n' "$prefix" "$action28r_convergence_sample" \
        "$(awk -v expected="$dns_ipv6_cidr" '$4 == expected { count++ } END { print count + 0 }' \
            "$capture_directory/sample-${action28r_convergence_sample}-ipv6")"
    printf '%s_value_sample_%s_caddy_ipv4_count=%s\n' "$prefix" "$action28r_convergence_sample" \
        "$(awk -v expected="$caddy_ipv4_cidr" '$4 == expected { count++ } END { print count + 0 }' \
            "$capture_directory/sample-${action28r_convergence_sample}-ipv4")"
    printf '%s_value_sample_%s_caddy_ipv6_count=%s\n' "$prefix" "$action28r_convergence_sample" \
        "$(awk -v expected="$caddy_ipv6_cidr" '$4 == expected { count++ } END { print count + 0 }' \
            "$capture_directory/sample-${action28r_convergence_sample}-ipv6")"
    require_check "sample_${action28r_convergence_sample}_ipv4_query_status_zero" \
        test "$action28r_convergence_ipv4_status" -eq 0
    require_check "sample_${action28r_convergence_sample}_ipv6_query_status_zero" \
        test "$action28r_convergence_ipv6_status" -eq 0
    require_check "sample_${action28r_convergence_sample}_ipv4_state_query_status_zero" \
        test "$action28r_convergence_ipv4_state_status" -eq 0
    require_check "sample_${action28r_convergence_sample}_ipv6_state_query_status_zero" \
        test "$action28r_convergence_ipv6_state_status" -eq 0
    if [[ "$action28r_convergence_sample" -ge 11 ]]; then
        require_check "sample_${action28r_convergence_sample}_ipv4_state_backup" \
            test "$action28r_convergence_ipv4_state" = '(us) 1 "Backup"'
        require_check "sample_${action28r_convergence_sample}_ipv6_state_backup" \
            test "$action28r_convergence_ipv6_state" = '(us) 1 "Backup"'
        require_check "sample_${action28r_convergence_sample}_dns_ipv4_absent" \
            test "$(address_count 4 "$dns_ipv4_cidr")" -eq 0
        require_check "sample_${action28r_convergence_sample}_dns_ipv6_absent" \
            test "$(address_count 6 "$dns_ipv6_cidr")" -eq 0
        require_check "sample_${action28r_convergence_sample}_caddy_ipv4_absent" \
            test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0
        require_check "sample_${action28r_convergence_sample}_caddy_ipv6_absent" \
            test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0
    fi
}
sample_node_a() {
    local action28r_convergence_sample=$1
    local action28r_convergence_ipv4_status=0
    local action28r_convergence_ipv6_status=0

    printf '%s_value_sample_%s_epoch_ms=%s\n' "$prefix" "$action28r_convergence_sample" \
        "$(date +%s%3N)"
    address_query 4 >/dev/null 2>&1 || action28r_convergence_ipv4_status=$?
    address_query 6 >/dev/null 2>&1 || action28r_convergence_ipv6_status=$?
    require_check "sample_${action28r_convergence_sample}_ipv4_query_status_zero" \
        test "$action28r_convergence_ipv4_status" -eq 0
    require_check "sample_${action28r_convergence_sample}_ipv6_query_status_zero" \
        test "$action28r_convergence_ipv6_status" -eq 0
    require_check "sample_${action28r_convergence_sample}_dns_ipv4_owned" \
        test "$(address_count 4 "$dns_ipv4_cidr")" -eq 1
    require_check "sample_${action28r_convergence_sample}_dns_ipv6_owned" \
        test "$(address_count 6 "$dns_ipv6_cidr")" -eq 1
    require_check "sample_${action28r_convergence_sample}_caddy_ipv4_owned" \
        test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 1
    require_check "sample_${action28r_convergence_sample}_caddy_ipv6_owned" \
        test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 1
}
inspect_node_b() {
    local action28r_convergence_cursor=$1
    local action28r_convergence_sample
    local action28r_convergence_keepalived_status=0
    local action28r_convergence_notifier_status=0

    for action28r_convergence_sample in $(seq 1 15); do
        sample_node_b "$action28r_convergence_sample"
        [[ "$action28r_convergence_sample" -eq 15 ]] || sleep 1
    done
    run_captured keepalived_journal journalctl -u keepalived.service \
        --after-cursor "$action28r_convergence_cursor" --no-pager --output=short-iso ||
        action28r_convergence_keepalived_status=$?
    require_check keepalived_journal_status_zero test \
        "$action28r_convergence_keepalived_status" -eq 0
    require_check keepalived_journal_safe safe_stream \
        "$capture_directory/keepalived_journal.stdout"
    require_check keepalived_journal_stderr_safe safe_stream \
        "$capture_directory/keepalived_journal.stderr"
    require_check keepalived_journal_no_fatal test \
        "$(grep -Eic 'fatal|parse error|configuration error|segmentation fault' \
            "$capture_directory/keepalived_journal.stdout" || true)" -eq 0
    run_captured notifier_journal journalctl -t keepalived-notify \
        --after-cursor "$action28r_convergence_cursor" --no-pager --output=short-iso ||
        action28r_convergence_notifier_status=$?
    require_check notifier_journal_status_zero test "$action28r_convergence_notifier_status" -eq 0
    require_check notifier_journal_safe safe_stream "$capture_directory/notifier_journal.stdout"
    require_check notifier_journal_stderr_safe safe_stream "$capture_directory/notifier_journal.stderr"
    printf '%s_value_notifier_delivery_failure_count=%s\n' "$prefix" \
        "$(grep -Fc 'notification failed' "$capture_directory/notifier_journal.stdout" || true)"
    require_check final_ipv4_state_backup test \
        "$(state_query "$dns_ipv4_object")" = '(us) 1 "Backup"'
    require_check final_ipv6_state_backup test \
        "$(state_query "$dns_ipv6_object")" = '(us) 1 "Backup"'
    require_check final_dns_ipv4_absent test "$(address_count 4 "$dns_ipv4_cidr")" -eq 0
    require_check final_dns_ipv6_absent test "$(address_count 6 "$dns_ipv6_cidr")" -eq 0
    require_check final_caddy_ipv4_absent test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0
    require_check final_caddy_ipv6_absent test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0
}
inspect_node_a() {
    local action28r_convergence_sample
    local action28r_convergence_status=0
    local action28r_convergence_code

    for action28r_convergence_sample in $(seq 1 5); do
        sample_node_a "$action28r_convergence_sample"
        [[ "$action28r_convergence_sample" -eq 5 ]] || sleep 1
    done
    run_captured shared_admin curl --noproxy '*' --insecure --silent --show-error --location \
        --max-redirs 3 --proto-redir '=https' --connect-timeout 3 --max-time 10 \
        --resolve 'pihole-admin.local.theama.co:443:10.1.0.56' \
        --output "$capture_directory/shared-admin.body" --write-out '%{http_code}' \
        'https://pihole-admin.local.theama.co/admin/login.php' ||
        action28r_convergence_status=$?
    action28r_convergence_code=$(<"$capture_directory/shared_admin.stdout")
    require_check shared_admin_status_zero test "$action28r_convergence_status" -eq 0
    require_check shared_admin_status_200 test "$action28r_convergence_code" = 200
    require_check shared_admin_body_safe safe_stream "$capture_directory/shared-admin.body"
    require_check shared_admin_title_node_a grep -Fq 'j1-svpihole0' \
        "$capture_directory/shared-admin.body"
    require_check shared_admin_title_node_b_absent test \
        "$(grep -Fc 'j1-svpihole00' "$capture_directory/shared-admin.body" || true)" -eq 0
}

case "${1:-}" in
    --expected-node-b-checks)
        [[ $# -eq 1 ]]
        expected_node_b_checks
        exit 0
        ;;
    --expected-node-a-checks)
        [[ $# -eq 1 ]]
        expected_node_a_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$(expected_node_b_checks | wc -l)" -eq "$(expected_node_b_checks | LC_ALL=C sort -u | wc -l)" ]]
        [[ "$(expected_node_a_checks | wc -l)" -eq "$(expected_node_a_checks | LC_ALL=C sort -u | wc -l)" ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --node-b)
        [[ $# -eq 2 ]]
        cursor_safe "$2"
        readonly role=node_b
        readonly journal_cursor=$2
        ;;
    --node-a)
        [[ $# -eq 1 ]]
        readonly role=node_a
        ;;
    *) exit 64 ;;
esac

first_failure=none
capture_directory=$(mktemp -d /tmp/caddy-action28r-convergence.XXXXXX)
trap 'rm -rf -- "$capture_directory"' EXIT
chmod 0700 "$capture_directory"
require_check identity_root test "$(id -u)" -eq 0
require_check working_directory_root test "$(pwd -P)" = /
if [[ "$role" = node_b ]]; then
    require_check hostname_exact test "$(hostname)" = j1-svpihole00
    require_check main_hash_exact test "$(file_hash "$main_configuration")" = "$node_b_main_sha256"
    require_check fragment_hash_exact test "$(file_hash "$caddy_fragment")" = "$node_b_fragment_sha256"
else
    require_check hostname_exact test "$(hostname)" = j1-svpihole0
    require_check main_hash_exact test "$(file_hash "$main_configuration")" = "$node_a_main_sha256"
    require_check fragment_hash_exact test "$(file_hash "$caddy_fragment")" = "$node_a_fragment_sha256"
fi
require_check keepalived_active systemctl is-active --quiet keepalived.service
require_check caddy_active systemctl is-active --quiet caddy.service
require_check lighttpd_active systemctl is-active --quiet lighttpd.service
if [[ "$role" = node_b ]]; then
    inspect_node_b "$journal_cursor"
else
    inspect_node_a
fi
printf '%s_check_count=%s\n' "$prefix" \
    "$(if [[ "$role" = node_b ]]; then expected_node_b_checks; else expected_node_a_checks; fi | wc -l)"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_role=%s\n' "$prefix" "$role"
printf '%s_notifier_delivery_is_gate=false\n' "$prefix"
printf '%s_mutation=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
