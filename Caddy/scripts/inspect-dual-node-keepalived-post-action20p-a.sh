#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly interface=eth0
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly health_helper=/usr/local/libexec/check-caddy.sh
readonly health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly dbus_service=org.keepalived.Vrrp1
readonly dbus_interface=org.keepalived.Vrrp1.Instance
readonly dbus_ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/110/IPv4
readonly dbus_ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/111/IPv6
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly maximum_observation_bytes=1048576
readonly maximum_observation_lines=4096

node_role=
case "${1:-}" in
    --node)
        [[ $# -eq 2 ]] || exit 64
        node_role=$2
        ;;
    --expected-checks)
        [[ $# -eq 1 ]] || exit 64
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        ;;
    *) exit 64 ;;
esac

expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root role_valid hostname_exact interface_present \
        main_regular main_not_symlink main_metadata main_hash_exact \
        main_enable_dbus_once main_include_once main_include_terminal \
        fragment_regular fragment_not_symlink fragment_metadata fragment_hash_exact \
        fragment_unicast_ttl_count fragment_unicast_ttl_placement \
        fragment_peer_ttl_constraints_count fragment_hoplimit_absent \
        health_regular health_not_symlink health_metadata health_hash_exact \
        keepalived_active_before caddy_active_before lighttpd_active_before \
        keepalived_pid_numeric_before keepalived_restarts_numeric_before \
        vrrp_state_expected_before ipv4_query_before_status ipv4_output_before_safe \
        ipv6_query_before_status ipv6_output_before_safe caddy_ipv4_count_before \
        caddy_ipv6_count_before dns_ipv4_count_before dns_ipv6_count_before \
        dbus_list_before_status dbus_list_before_safe dbus_service_once_before \
        dbus_tree_before_status dbus_tree_before_safe dbus_ipv4_object_once_before \
        dbus_ipv6_object_once_before dbus_ipv4_state_before_status \
        dbus_ipv4_state_before_safe dbus_ipv4_state_expected_before \
        dbus_ipv6_state_before_status dbus_ipv6_state_before_safe \
        dbus_ipv6_state_expected_before management_https_before vip_https_before \
        journal_cursor_captured observation_wait_complete journal_query_status \
        journal_output_safe journal_ipv4_ttl_hl_quiet journal_ipv6_ttl_hl_quiet \
        journal_no_fatal_errors journal_no_caddy_health_failure journal_no_health_overlap \
        ipv4_query_after_status ipv4_output_after_safe ipv6_query_after_status \
        ipv6_output_after_safe dbus_list_after_status dbus_list_after_safe \
        dbus_tree_after_status dbus_tree_after_safe dbus_ipv4_state_after_status \
        dbus_ipv4_state_after_safe dbus_ipv6_state_after_status \
        dbus_ipv6_state_after_safe keepalived_active_after caddy_active_after \
        lighttpd_active_after keepalived_pid_unchanged keepalived_restarts_unchanged \
        vrrp_state_expected_after caddy_ipv4_count_after caddy_ipv6_count_after \
        dns_ipv4_count_after dns_ipv6_count_after dbus_service_once_after \
        dbus_ipv4_object_once_after dbus_ipv6_object_once_after \
        dbus_ipv4_state_expected_after dbus_ipv6_state_expected_after \
        main_hash_unchanged fragment_hash_unchanged health_hash_unchanged \
        management_https_after vip_https_after state_snapshot_unchanged \
        action20p_residue_absent
}

if [[ "${1:-}" = --expected-checks ]]; then
    expected_checks
    exit 0
fi

if [[ "${1:-}" = --self-test ]]; then
    action20pa_self_labels=$(expected_checks) || exit 1
    readonly action20pa_self_labels
    [[ "$(printf '%s\n' "$action20pa_self_labels" | wc -l)" -gt 90 ]] || exit 1
    [[ "$(printf '%s\n' "$action20pa_self_labels" | wc -l)" -eq "$(printf '%s\n' "$action20pa_self_labels" | LC_ALL=C sort -u | wc -l)" ]] || exit 1
    printf 'action_20p_a_inspector_self_test_complete=true\n'
    exit 0
fi

case "$node_role" in
    node-a)
        readonly prefix=action_20p_a_node_a
        readonly expected_hostname=j1-svpihole0
        readonly main_sha256=8fc9dcf8e079b7131f86a58038ae5543804a5158a02d53a4614452de212ce47c
        readonly fragment_sha256=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
        readonly expected_vrrp_state=MASTER
        readonly expected_dbus_state='(us) 2 "Master"'
        readonly expected_dbus_state_name=Master
        readonly expected_vip_count=1
        readonly management_name=pihole0.local.theama.co
        readonly management_address=10.1.0.53
        ;;
    node-b)
        readonly prefix=action_20p_a_node_b
        readonly expected_hostname=j1-svpihole00
        readonly main_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
        readonly fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
        readonly expected_vrrp_state=BACKUP
        readonly expected_dbus_state='(us) 1 "Backup"'
        readonly expected_dbus_state_name=Backup
        readonly expected_vip_count=0
        readonly management_name=pihole00.local.theama.co
        readonly management_address=10.1.0.54
        ;;
    *) exit 64 ;;
esac

action20pa_failed_check_count=0
action20pa_first_failure=none

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
text_hash() { printf '%s' "$1" | sha256sum | awk '{ print $1 }'; }
line_count_text() { printf '%s' "$1" | awk 'END { print NR }'; }
record_check() {
    local action20pa_check_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20pa_check_label"
    else
        printf '%s_check_%s=false\n' "$prefix" "$action20pa_check_label"
        action20pa_failed_check_count=$((action20pa_failed_check_count + 1))
        if [[ "$action20pa_first_failure" = none ]]; then
            action20pa_first_failure=$action20pa_check_label
        fi
    fi
    return 0
}
safe_text() {
    local action20pa_safe_text=$1

    [[ ${#action20pa_safe_text} -le $maximum_observation_bytes ]] || return 1
    [[ "$(line_count_text "$action20pa_safe_text")" -le "$maximum_observation_lines" ]] || return 1
    ! printf '%s' "$action20pa_safe_text" | LC_ALL=C grep -q '[^[:print:][:space:]]' || return 1
    ! printf '%s' "$action20pa_safe_text" | grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer'
}
emit_observation() {
    local action20pa_observation_label=$1
    local action20pa_observation_text=$2
    local action20pa_observation_status=$3

    printf '%s_observation_%s_status=%s\n' "$prefix" "$action20pa_observation_label" "$action20pa_observation_status"
    printf '%s_observation_%s_bytes=%s\n' "$prefix" "$action20pa_observation_label" "${#action20pa_observation_text}"
    printf '%s_observation_%s_lines=%s\n' "$prefix" "$action20pa_observation_label" "$(line_count_text "$action20pa_observation_text")"
    printf '%s_observation_%s_sha256=%s\n' "$prefix" "$action20pa_observation_label" "$(text_hash "$action20pa_observation_text")"
    if safe_text "$action20pa_observation_text"; then
        printf '%s_observation_%s_classification=bounded_safe\n' "$prefix" "$action20pa_observation_label"
        if [[ -n "$action20pa_observation_text" ]]; then
            printf '%s_observation_%s_begin\n%s\n%s_observation_%s_end\n' \
                "$prefix" "$action20pa_observation_label" "$action20pa_observation_text" \
                "$prefix" "$action20pa_observation_label"
        else
            printf '%s_observation_%s_content=empty\n' "$prefix" "$action20pa_observation_label"
        fi
        return 0
    fi
    printf '%s_observation_%s_classification=unsafe\n' "$prefix" "$action20pa_observation_label"
    return 1
}
capture_observations() {
    action20pa_ip4_status=0
    action20pa_ip4_output=$(ip -o -4 address show dev "$interface" 2>&1) || action20pa_ip4_status=$?
    action20pa_ip6_status=0
    action20pa_ip6_output=$(ip -o -6 address show dev "$interface" 2>&1) || action20pa_ip6_status=$?
    action20pa_dbus_list_status=0
    action20pa_dbus_list_output=$(timeout 5 busctl --system --no-pager --no-legend list 2>&1) || action20pa_dbus_list_status=$?
    action20pa_dbus_tree_status=0
    action20pa_dbus_tree_output=$(timeout 5 busctl --system --no-pager --list tree "$dbus_service" 2>&1) || action20pa_dbus_tree_status=$?
    action20pa_dbus_ipv4_state_status=0
    action20pa_dbus_ipv4_state_output=$(timeout 5 busctl --system --no-pager get-property \
        "$dbus_service" "$dbus_ipv4_object" "$dbus_interface" State 2>&1) || action20pa_dbus_ipv4_state_status=$?
    action20pa_dbus_ipv6_state_status=0
    action20pa_dbus_ipv6_state_output=$(timeout 5 busctl --system --no-pager get-property \
        "$dbus_service" "$dbus_ipv6_object" "$dbus_interface" State 2>&1) || action20pa_dbus_ipv6_state_status=$?
}
address_count() {
    local action20pa_address_status=$1
    local action20pa_address_output=$2
    local action20pa_address_cidr=$3

    [[ "$action20pa_address_status" -eq 0 ]] || return 1
    printf '%s\n' "$action20pa_address_output" | awk -v expected="$action20pa_address_cidr" \
        '$4 == expected { count++ } END { print count + 0 }'
}
exact_first_field_once() {
    local action20pa_field_status=$1
    local action20pa_field_output=$2
    local action20pa_field_expected=$3

    [[ "$action20pa_field_status" -eq 0 ]] || return 1
    [[ "$(printf '%s\n' "$action20pa_field_output" | awk -v expected="$action20pa_field_expected" \
        '$1 == expected { count++ } END { print count + 0 }')" -eq 1 ]]
}
exact_line_once() {
    local action20pa_line_status=$1
    local action20pa_line_output=$2
    local action20pa_line_expected=$3

    [[ "$action20pa_line_status" -eq 0 ]] || return 1
    [[ "$(printf '%s\n' "$action20pa_line_output" | awk -v expected="$action20pa_line_expected" \
        '$0 == expected { count++ } END { print count + 0 }')" -eq 1 ]]
}
https_probe() {
    local action20pa_https_name=$1
    local action20pa_https_address=$2

    curl --silent --show-error --fail --insecure --head --connect-timeout 3 --max-time 10 \
        --resolve "$action20pa_https_name:443:$action20pa_https_address" \
        "https://$action20pa_https_name/" >/dev/null
}
normalized_list_hash() {
    local action20pa_list_text=$1

    printf '%s\n' "$action20pa_list_text" | awk '$3 != "busctl"' | sha256sum | awk '{ print $1 }'
}
state_snapshot() {
    printf 'files=%s|%s|%s\n' \
        "$(file_hash "$main_configuration" 2>/dev/null || printf unavailable)" \
        "$(file_hash "$fragment" 2>/dev/null || printf unavailable)" \
        "$(file_hash "$health_helper" 2>/dev/null || printf unavailable)"
    printf 'services=%s|%s|%s|%s|%s\n' \
        "$(systemctl is-active keepalived.service 2>/dev/null || printf unavailable)" \
        "$(systemctl is-active caddy.service 2>/dev/null || printf unavailable)" \
        "$(systemctl is-active lighttpd.service 2>/dev/null || printf unavailable)" \
        "$(systemctl show keepalived.service -p MainPID --value 2>/dev/null || printf unavailable)" \
        "$(systemctl show keepalived.service -p NRestarts --value 2>/dev/null || printf unavailable)"
    printf 'state=%s|%s|%s|%s|%s|%s|%s\n' \
        "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || printf unavailable)" \
        "$(text_hash "$action20pa_ip4_output")" "$(text_hash "$action20pa_ip6_output")" \
        "$(normalized_list_hash "$action20pa_dbus_list_output")" \
        "$(text_hash "$action20pa_dbus_tree_output")" \
        "$(text_hash "$action20pa_dbus_ipv4_state_output")" \
        "$(text_hash "$action20pa_dbus_ipv6_state_output")"
}

capture_observations
action20pa_pid_before=$(systemctl show keepalived.service -p MainPID --value 2>/dev/null || true)
action20pa_restarts_before=$(systemctl show keepalived.service -p NRestarts --value 2>/dev/null || true)
action20pa_snapshot_before=$(state_snapshot | sha256sum | awk '{ print $1 }')
readonly action20pa_pid_before action20pa_restarts_before action20pa_snapshot_before

record_check identity_root test "$(id -u)" -eq 0
record_check working_directory_root test "$(pwd -P)" = /
record_check role_valid test "$node_role" = node-a -o "$node_role" = node-b
record_check hostname_exact test "$(hostname)" = "$expected_hostname"
record_check interface_present test -d "/sys/class/net/$interface"
record_check main_regular test -f "$main_configuration"
record_check main_not_symlink test ! -L "$main_configuration"
record_check main_metadata test "$(stat -c '%U:%G:%a' "$main_configuration" 2>/dev/null || true)" = root:root:644
record_check main_hash_exact test "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$main_sha256"
record_check main_enable_dbus_once test "$(grep -Ec '^[[:space:]]*enable_dbus[[:space:]]*$' "$main_configuration" || true)" -eq 1
record_check main_include_once test "$(grep -Fxc 'include /etc/keepalived/conf.d/*.conf' "$main_configuration" || true)" -eq 1
record_check main_include_terminal test "$(awk 'NF { line=$0 } END { print line }' "$main_configuration")" = 'include /etc/keepalived/conf.d/*.conf'
record_check fragment_regular test -f "$fragment"
record_check fragment_not_symlink test ! -L "$fragment"
record_check fragment_metadata test "$(stat -c '%U:%G:%a' "$fragment" 2>/dev/null || true)" = root:root:644
record_check fragment_hash_exact test "$(file_hash "$fragment" 2>/dev/null || true)" = "$fragment_sha256"
record_check fragment_unicast_ttl_count test "$(grep -Ec '^[[:space:]]*unicast_ttl[[:space:]]+255[[:space:]]*$' "$fragment" || true)" -eq 2
record_check fragment_unicast_ttl_placement test "$(awk '/unicast_src_ip/{src=NR} /unicast_ttl 255/{if (NR == src + 1) count++} END {print count+0}' "$fragment")" -eq 2
record_check fragment_peer_ttl_constraints_count test "$(grep -Ec 'min_ttl[[:space:]]+255[[:space:]]+max_ttl[[:space:]]+255' "$fragment" || true)" -eq 2
record_check fragment_hoplimit_absent test "$(grep -Ec '^[[:space:]]*hoplimit([[:space:]]|$)' "$fragment" || true)" -eq 0
record_check health_regular test -f "$health_helper"
record_check health_not_symlink test ! -L "$health_helper"
record_check health_metadata test "$(stat -c '%U:%G:%a' "$health_helper" 2>/dev/null || true)" = root:root:755
record_check health_hash_exact test "$(file_hash "$health_helper" 2>/dev/null || true)" = "$health_sha256"
record_check keepalived_active_before systemctl is-active --quiet keepalived.service
record_check caddy_active_before systemctl is-active --quiet caddy.service
record_check lighttpd_active_before systemctl is-active --quiet lighttpd.service
record_check keepalived_pid_numeric_before test "$action20pa_pid_before" -gt 1
record_check keepalived_restarts_numeric_before grep -Eq '^[0-9]+$' <<<"$action20pa_restarts_before"
record_check vrrp_state_expected_before test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = "$expected_vrrp_state"

for action20pa_before_observation in ip4 ip6 dbus_list dbus_tree dbus_ipv4_state dbus_ipv6_state; do
    action20pa_before_output_variable=action20pa_${action20pa_before_observation}_output
    action20pa_before_status_variable=action20pa_${action20pa_before_observation}_status
    emit_observation "${action20pa_before_observation}_before" \
        "${!action20pa_before_output_variable}" "${!action20pa_before_status_variable}" >/dev/null || true
done
record_check ipv4_query_before_status test "$action20pa_ip4_status" -eq 0
record_check ipv4_output_before_safe safe_text "$action20pa_ip4_output"
record_check ipv6_query_before_status test "$action20pa_ip6_status" -eq 0
record_check ipv6_output_before_safe safe_text "$action20pa_ip6_output"
record_check caddy_ipv4_count_before test "$(address_count "$action20pa_ip4_status" "$action20pa_ip4_output" "$caddy_ipv4_cidr" || printf query_failed)" = "$expected_vip_count"
record_check caddy_ipv6_count_before test "$(address_count "$action20pa_ip6_status" "$action20pa_ip6_output" "$caddy_ipv6_cidr" || printf query_failed)" = "$expected_vip_count"
record_check dns_ipv4_count_before test "$(address_count "$action20pa_ip4_status" "$action20pa_ip4_output" "$dns_ipv4_cidr" || printf query_failed)" = "$expected_vip_count"
record_check dns_ipv6_count_before test "$(address_count "$action20pa_ip6_status" "$action20pa_ip6_output" "$dns_ipv6_cidr" || printf query_failed)" = "$expected_vip_count"
record_check dbus_list_before_status test "$action20pa_dbus_list_status" -eq 0
record_check dbus_list_before_safe safe_text "$action20pa_dbus_list_output"
record_check dbus_service_once_before exact_first_field_once "$action20pa_dbus_list_status" "$action20pa_dbus_list_output" "$dbus_service"
record_check dbus_tree_before_status test "$action20pa_dbus_tree_status" -eq 0
record_check dbus_tree_before_safe safe_text "$action20pa_dbus_tree_output"
record_check dbus_ipv4_object_once_before exact_line_once "$action20pa_dbus_tree_status" "$action20pa_dbus_tree_output" "$dbus_ipv4_object"
record_check dbus_ipv6_object_once_before exact_line_once "$action20pa_dbus_tree_status" "$action20pa_dbus_tree_output" "$dbus_ipv6_object"
record_check dbus_ipv4_state_before_status test "$action20pa_dbus_ipv4_state_status" -eq 0
record_check dbus_ipv4_state_before_safe safe_text "$action20pa_dbus_ipv4_state_output"
record_check dbus_ipv4_state_expected_before test "$action20pa_dbus_ipv4_state_output" = "$expected_dbus_state"
record_check dbus_ipv6_state_before_status test "$action20pa_dbus_ipv6_state_status" -eq 0
record_check dbus_ipv6_state_before_safe safe_text "$action20pa_dbus_ipv6_state_output"
record_check dbus_ipv6_state_expected_before test "$action20pa_dbus_ipv6_state_output" = "$expected_dbus_state"
record_check management_https_before https_probe "$management_name" "$management_address"
record_check vip_https_before https_probe pihole-admin.local.theama.co 10.1.0.56

action20pa_journal_cursor=$(journalctl -u keepalived.service -n 0 --show-cursor --no-pager -o cat | sed -n 's/^-- cursor: //p')
readonly action20pa_journal_cursor
record_check journal_cursor_captured test -n "$action20pa_journal_cursor"
sleep 8
record_check observation_wait_complete true
action20pa_journal_status=0
action20pa_journal_output=$(journalctl -u keepalived.service --after-cursor="$action20pa_journal_cursor" \
    --no-pager -o short-iso-precise 2>&1) || action20pa_journal_status=$?
readonly action20pa_journal_status action20pa_journal_output
emit_observation ttl_hl_quiet_window "$action20pa_journal_output" "$action20pa_journal_status" || true
record_check journal_query_status test "$action20pa_journal_status" -eq 0
record_check journal_output_safe safe_text "$action20pa_journal_output"
record_check journal_ipv4_ttl_hl_quiet test "$(printf '%s\n' "$action20pa_journal_output" | grep -Eic '\(CADDY_IPV4\).*TTL/HL .* not in range' || true)" -eq 0
record_check journal_ipv6_ttl_hl_quiet test "$(printf '%s\n' "$action20pa_journal_output" | grep -Eic '\(CADDY_IPV6\).*TTL/HL .* not in range' || true)" -eq 0
record_check journal_no_fatal_errors test "$(printf '%s\n' "$action20pa_journal_output" | grep -Eic 'fatal|configuration.*error|security violation' || true)" -eq 0
# The backticks are literal Keepalived journal text, not shell substitution.
# shellcheck disable=SC2016
record_check journal_no_caddy_health_failure test "$(printf '%s\n' "$action20pa_journal_output" | grep -Ec 'Script `check_caddy` now returning ([1-9]|[1-9][0-9]+)|check_caddy.*(failed|timed out)' || true)" -eq 0
record_check journal_no_health_overlap test "$(printf '%s\n' "$action20pa_journal_output" | grep -Fxc 'Track script check_caddy is already running, expect idle - skipping run' || true)" -eq 0

capture_observations
action20pa_pid_after=$(systemctl show keepalived.service -p MainPID --value 2>/dev/null || true)
action20pa_restarts_after=$(systemctl show keepalived.service -p NRestarts --value 2>/dev/null || true)
action20pa_snapshot_after=$(state_snapshot | sha256sum | awk '{ print $1 }')
readonly action20pa_pid_after action20pa_restarts_after action20pa_snapshot_after
for action20pa_after_observation in ip4 ip6 dbus_list dbus_tree dbus_ipv4_state dbus_ipv6_state; do
    action20pa_after_output_variable=action20pa_${action20pa_after_observation}_output
    action20pa_after_status_variable=action20pa_${action20pa_after_observation}_status
    emit_observation "${action20pa_after_observation}_after" \
        "${!action20pa_after_output_variable}" "${!action20pa_after_status_variable}" >/dev/null || true
done
record_check ipv4_query_after_status test "$action20pa_ip4_status" -eq 0
record_check ipv4_output_after_safe safe_text "$action20pa_ip4_output"
record_check ipv6_query_after_status test "$action20pa_ip6_status" -eq 0
record_check ipv6_output_after_safe safe_text "$action20pa_ip6_output"
record_check dbus_list_after_status test "$action20pa_dbus_list_status" -eq 0
record_check dbus_list_after_safe safe_text "$action20pa_dbus_list_output"
record_check dbus_tree_after_status test "$action20pa_dbus_tree_status" -eq 0
record_check dbus_tree_after_safe safe_text "$action20pa_dbus_tree_output"
record_check dbus_ipv4_state_after_status test "$action20pa_dbus_ipv4_state_status" -eq 0
record_check dbus_ipv4_state_after_safe safe_text "$action20pa_dbus_ipv4_state_output"
record_check dbus_ipv6_state_after_status test "$action20pa_dbus_ipv6_state_status" -eq 0
record_check dbus_ipv6_state_after_safe safe_text "$action20pa_dbus_ipv6_state_output"
record_check keepalived_active_after systemctl is-active --quiet keepalived.service
record_check caddy_active_after systemctl is-active --quiet caddy.service
record_check lighttpd_active_after systemctl is-active --quiet lighttpd.service
record_check keepalived_pid_unchanged test "$action20pa_pid_after" = "$action20pa_pid_before"
record_check keepalived_restarts_unchanged test "$action20pa_restarts_after" = "$action20pa_restarts_before"
record_check vrrp_state_expected_after test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = "$expected_vrrp_state"
record_check caddy_ipv4_count_after test "$(address_count "$action20pa_ip4_status" "$action20pa_ip4_output" "$caddy_ipv4_cidr" || printf query_failed)" = "$expected_vip_count"
record_check caddy_ipv6_count_after test "$(address_count "$action20pa_ip6_status" "$action20pa_ip6_output" "$caddy_ipv6_cidr" || printf query_failed)" = "$expected_vip_count"
record_check dns_ipv4_count_after test "$(address_count "$action20pa_ip4_status" "$action20pa_ip4_output" "$dns_ipv4_cidr" || printf query_failed)" = "$expected_vip_count"
record_check dns_ipv6_count_after test "$(address_count "$action20pa_ip6_status" "$action20pa_ip6_output" "$dns_ipv6_cidr" || printf query_failed)" = "$expected_vip_count"
record_check dbus_service_once_after exact_first_field_once "$action20pa_dbus_list_status" "$action20pa_dbus_list_output" "$dbus_service"
record_check dbus_ipv4_object_once_after exact_line_once "$action20pa_dbus_tree_status" "$action20pa_dbus_tree_output" "$dbus_ipv4_object"
record_check dbus_ipv6_object_once_after exact_line_once "$action20pa_dbus_tree_status" "$action20pa_dbus_tree_output" "$dbus_ipv6_object"
record_check dbus_ipv4_state_expected_after test "$action20pa_dbus_ipv4_state_output" = "$expected_dbus_state"
record_check dbus_ipv6_state_expected_after test "$action20pa_dbus_ipv6_state_output" = "$expected_dbus_state"
record_check main_hash_unchanged test "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$main_sha256"
record_check fragment_hash_unchanged test "$(file_hash "$fragment" 2>/dev/null || true)" = "$fragment_sha256"
record_check health_hash_unchanged test "$(file_hash "$health_helper" 2>/dev/null || true)" = "$health_sha256"
record_check management_https_after https_probe "$management_name" "$management_address"
record_check vip_https_after https_probe pihole-admin.local.theama.co 10.1.0.56
record_check state_snapshot_unchanged test "$action20pa_snapshot_after" = "$action20pa_snapshot_before"
record_check action20p_residue_absent test "$(find /run /tmp -maxdepth 1 -name 'caddy-action20p-*' -printf . 2>/dev/null | wc -c)" -eq 0

printf '%s_value_expected_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
printf '%s_value_main_sha256=%s\n' "$prefix" "$main_sha256"
printf '%s_value_fragment_sha256=%s\n' "$prefix" "$fragment_sha256"
printf '%s_value_health_sha256=%s\n' "$prefix" "$health_sha256"
printf '%s_value_dbus_state=%s\n' "$prefix" "$expected_dbus_state_name"
printf '%s_value_caddy_ipv4_count=%s\n' "$prefix" "$expected_vip_count"
printf '%s_value_caddy_ipv6_count=%s\n' "$prefix" "$expected_vip_count"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$action20pa_snapshot_before"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$action20pa_snapshot_after"
printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
printf '%s_failed_check_count=%s\n' "$prefix" "$action20pa_failed_check_count"
printf '%s_first_failure=%s\n' "$prefix" "$action20pa_first_failure"
printf '%s_read_only=true\n' "$prefix"
printf '%s_keepalived_reload=false\n' "$prefix"
printf '%s_keepalived_restart=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

[[ "$action20pa_failed_check_count" -eq 0 ]]
