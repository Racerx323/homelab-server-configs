#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20o_b
readonly expected_hostname=j1-svpihole00
readonly interface=eth0
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly main_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
readonly health_helper=/usr/local/libexec/check-caddy.sh
readonly health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly dbus_service=org.keepalived.Vrrp1
readonly dbus_interface=org.keepalived.Vrrp1.Instance
readonly dbus_ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/110/IPv4
readonly dbus_ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/111/IPv6
readonly expected_dbus_state='(us) 1 "Backup"'
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly maximum_observation_bytes=65536
readonly maximum_observation_lines=1024

action20ob_failed_check_count=0
action20ob_first_failure=none

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
text_hash() { printf '%s' "$1" | sha256sum | awk '{ print $1 }'; }
line_count_text() { printf '%s' "$1" | awk 'END { print NR }'; }
expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact interface_present \
        main_regular main_not_symlink main_metadata main_hash_exact \
        main_enable_dbus_once main_include_once main_include_terminal \
        fragment_regular fragment_not_symlink fragment_metadata fragment_hash_exact \
        health_regular health_not_symlink health_metadata health_hash_exact \
        runtime_residue_absent_before bundle_residue_absent_before install_residue_absent_before \
        keepalived_active_before caddy_active_before lighttpd_active_before \
        keepalived_pid_numeric_before keepalived_restarts_numeric_before \
        vrrp_state_backup_before ipv4_query_before_status ipv4_output_before_safe \
        ipv6_query_before_status ipv6_output_before_safe caddy_ipv4_absent_before \
        caddy_ipv6_absent_before dns_ipv4_absent_before dns_ipv6_absent_before \
        dbus_list_before_status dbus_list_before_safe dbus_service_once_before \
        dbus_tree_before_status dbus_tree_before_safe dbus_ipv4_object_once_before \
        dbus_ipv6_object_once_before dbus_ipv4_state_before_status \
        dbus_ipv4_state_before_safe dbus_ipv4_state_backup_before \
        dbus_ipv6_state_before_status dbus_ipv6_state_before_safe \
        dbus_ipv6_state_backup_before node_a_https_continuity caddy_vip_https_continuity \
        ipv4_query_after_status ipv4_output_after_safe ipv6_query_after_status \
        ipv6_output_after_safe dbus_list_after_status dbus_list_after_safe \
        dbus_tree_after_status dbus_tree_after_safe dbus_ipv4_state_after_status \
        dbus_ipv4_state_after_safe dbus_ipv6_state_after_status dbus_ipv6_state_after_safe \
        keepalived_active_after caddy_active_after lighttpd_active_after \
        keepalived_pid_unchanged keepalived_restarts_unchanged vrrp_state_backup_after \
        caddy_ipv4_absent_after caddy_ipv6_absent_after dns_ipv4_absent_after \
        dns_ipv6_absent_after dbus_service_once_after dbus_ipv4_object_once_after \
        dbus_ipv6_object_once_after dbus_ipv4_state_backup_after dbus_ipv6_state_backup_after \
        main_hash_unchanged fragment_hash_unchanged health_hash_unchanged \
        runtime_residue_absent_after bundle_residue_absent_after install_residue_absent_after \
        state_snapshot_unchanged
}
record_check() {
    local action20ob_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20ob_label"
    else
        printf '%s_check_%s=false\n' "$prefix" "$action20ob_label"
        action20ob_failed_check_count=$((action20ob_failed_check_count + 1))
        if [[ "$action20ob_first_failure" = none ]]; then
            action20ob_first_failure=$action20ob_label
        fi
    fi
    return 0
}
safe_text() {
    local action20ob_text=$1

    [[ ${#action20ob_text} -le $maximum_observation_bytes ]] || return 1
    [[ "$(line_count_text "$action20ob_text")" -le $maximum_observation_lines ]] || return 1
    ! printf '%s' "$action20ob_text" | LC_ALL=C grep -q '[^[:print:][:space:]]' || return 1
    ! printf '%s' "$action20ob_text" | grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer'
}
emit_observation() {
    local action20ob_label=$1
    local action20ob_text=$2
    local action20ob_status=$3

    printf '%s_observation_%s_status=%s\n' "$prefix" "$action20ob_label" "$action20ob_status"
    printf '%s_observation_%s_bytes=%s\n' "$prefix" "$action20ob_label" "${#action20ob_text}"
    printf '%s_observation_%s_lines=%s\n' "$prefix" "$action20ob_label" "$(line_count_text "$action20ob_text")"
    printf '%s_observation_%s_sha256=%s\n' "$prefix" "$action20ob_label" "$(text_hash "$action20ob_text")"
    if safe_text "$action20ob_text"; then
        printf '%s_observation_%s_classification=bounded_safe\n' "$prefix" "$action20ob_label"
        if [[ -n "$action20ob_text" ]]; then
            printf '%s_observation_%s_begin\n%s\n%s_observation_%s_end\n' \
                "$prefix" "$action20ob_label" "$action20ob_text" "$prefix" "$action20ob_label"
        else
            printf '%s_observation_%s_content=empty\n' "$prefix" "$action20ob_label"
        fi
        return 0
    fi
    printf '%s_observation_%s_classification=unsafe\n' "$prefix" "$action20ob_label"
    return 1
}
address_absent() {
    local action20ob_status=$1
    local action20ob_output=$2
    local action20ob_cidr=$3

    [[ "$action20ob_status" -eq 0 ]] || return 1
    [[ "$(printf '%s\n' "$action20ob_output" | awk -v expected="$action20ob_cidr" \
        '$4 == expected { count++ } END { print count + 0 }')" -eq 0 ]]
}
exact_first_field_once() {
    local action20ob_status=$1
    local action20ob_output=$2
    local action20ob_expected=$3

    [[ "$action20ob_status" -eq 0 ]] || return 1
    [[ "$(printf '%s\n' "$action20ob_output" | awk -v expected="$action20ob_expected" \
        '$1 == expected { count++ } END { print count + 0 }')" -eq 1 ]]
}
exact_line_once() {
    local action20ob_status=$1
    local action20ob_output=$2
    local action20ob_expected=$3

    [[ "$action20ob_status" -eq 0 ]] || return 1
    [[ "$(printf '%s\n' "$action20ob_output" | awk -v expected="$action20ob_expected" \
        '$0 == expected { count++ } END { print count + 0 }')" -eq 1 ]]
}
residue_absent() {
    local action20ob_pattern=$1

    ! compgen -G "$action20ob_pattern" >/dev/null
}
https_probe() {
    local action20ob_name=$1
    local action20ob_address=$2

    curl --silent --show-error --fail --insecure --head --max-time 10 --connect-timeout 3 \
        --resolve "$action20ob_name:443:$action20ob_address" "https://$action20ob_name/" >/dev/null
}
normalize_dbus_list() {
    local action20ob_text=$1

    printf '%s\n' "$action20ob_text" | awk '$3 != "busctl"'
}
state_snapshot() {
    printf 'main=%s\nfragment=%s\nhealth=%s\n' \
        "$(file_hash "$main_configuration" 2>/dev/null || printf unavailable)" \
        "$(file_hash "$fragment" 2>/dev/null || printf unavailable)" \
        "$(file_hash "$health_helper" 2>/dev/null || printf unavailable)"
    printf 'services=%s|%s|%s|%s|%s\n' \
        "$(systemctl is-active keepalived.service 2>/dev/null || printf unavailable)" \
        "$(systemctl is-active caddy.service 2>/dev/null || printf unavailable)" \
        "$(systemctl is-active lighttpd.service 2>/dev/null || printf unavailable)" \
        "$(systemctl show keepalived.service -p MainPID --value 2>/dev/null || printf unavailable)" \
        "$(systemctl show keepalived.service -p NRestarts --value 2>/dev/null || printf unavailable)"
    printf 'vrrp=%s\nip4=%s\nip6=%s\ndbus_list=%s\ndbus_tree=%s\nstate4=%s\nstate6=%s\n' \
        "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || printf unavailable)" \
        "$(text_hash "$action20ob_ip4_output")" "$(text_hash "$action20ob_ip6_output")" \
        "$(normalize_dbus_list "$action20ob_dbus_list_output" | sha256sum | awk '{ print $1 }')" \
        "$(text_hash "$action20ob_dbus_tree_output")" \
        "$(text_hash "$action20ob_dbus_ipv4_state_output")" \
        "$(text_hash "$action20ob_dbus_ipv6_state_output")"
    printf 'residue=%s|%s|%s\n' \
        "$(residue_absent '/run/caddy-action20o-retry2.*' && printf absent || printf present)" \
        "$(residue_absent '/run/caddy-action20o-retry2-bundle.*' && printf absent || printf present)" \
        "$(residue_absent '/etc/keepalived/.keepalived.conf.action20o-retry2.*' && printf absent || printf present)"
}
capture_observations() {
    action20ob_ip4_status=0
    action20ob_ip4_output=$(ip -o -4 address show dev "$interface" 2>&1) || action20ob_ip4_status=$?
    action20ob_ip6_status=0
    action20ob_ip6_output=$(ip -o -6 address show dev "$interface" 2>&1) || action20ob_ip6_status=$?
    action20ob_dbus_list_status=0
    action20ob_dbus_list_output=$(timeout 5 busctl --system --no-pager --no-legend list 2>&1) || action20ob_dbus_list_status=$?
    action20ob_dbus_tree_status=0
    action20ob_dbus_tree_output=$(timeout 5 busctl --system --no-pager --list tree "$dbus_service" 2>&1) || action20ob_dbus_tree_status=$?
    action20ob_dbus_ipv4_state_status=0
    action20ob_dbus_ipv4_state_output=$(timeout 5 busctl --system --no-pager get-property \
        "$dbus_service" "$dbus_ipv4_object" "$dbus_interface" State 2>&1) || action20ob_dbus_ipv4_state_status=$?
    action20ob_dbus_ipv6_state_status=0
    action20ob_dbus_ipv6_state_output=$(timeout 5 busctl --system --no-pager get-property \
        "$dbus_service" "$dbus_ipv6_object" "$dbus_interface" State 2>&1) || action20ob_dbus_ipv6_state_status=$?
}
self_test() {
    local action20ob_labels
    local action20ob_list_a=':1.1 100 busctl root :1.1 session.scope - -'
    local action20ob_list_b=':1.2 101 busctl root :1.2 session.scope - -'
    local action20ob_keepalived='org.keepalived.Vrrp1 200 keepalived root :1.3 keepalived.service - -'

    action20ob_labels=$(expected_checks) || return 1
    [[ "$(printf '%s\n' "$action20ob_labels" | wc -l)" -gt 70 ]] || return 1
    [[ "$(printf '%s\n' "$action20ob_labels" | wc -l)" -eq "$(printf '%s\n' "$action20ob_labels" | LC_ALL=C sort -u | wc -l)" ]] || return 1
    [[ "$(normalize_dbus_list "$action20ob_list_a")" = '' ]] || return 1
    [[ "$(normalize_dbus_list "$action20ob_list_b")" = '' ]] || return 1
    [[ "$(normalize_dbus_list "$action20ob_keepalived")" = "$action20ob_keepalived" ]] || return 1
    exact_first_field_once 0 "$action20ob_keepalived" "$dbus_service" || return 1
    if exact_first_field_once 1 "$action20ob_keepalived" "$dbus_service"; then return 1; fi
    exact_line_once 0 "$dbus_ipv4_object" "$dbus_ipv4_object" || return 1
    if exact_line_once 0 "├─$dbus_ipv4_object" "$dbus_ipv4_object"; then return 1; fi
    address_absent 0 '2: eth0 inet 10.1.0.54/22 scope global eth0' "$caddy_ipv4_cidr" || return 1
    if address_absent 1 '' "$caddy_ipv4_cidr"; then return 1; fi
    printf '%s_self_test_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]] || exit 64
        expected_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--expected-checks|--self-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

capture_observations
action20ob_pid_before=$(systemctl show keepalived.service -p MainPID --value 2>/dev/null || true)
action20ob_restarts_before=$(systemctl show keepalived.service -p NRestarts --value 2>/dev/null || true)
action20ob_state_before=$(state_snapshot | sha256sum | awk '{ print $1 }')
action20ob_ip4_safe=0
action20ob_ip6_safe=0
action20ob_dbus_list_safe=0
action20ob_dbus_tree_safe=0
action20ob_dbus_ipv4_state_safe=0
action20ob_dbus_ipv6_state_safe=0

for action20ob_observation in ip4 ip6 dbus_list dbus_tree dbus_ipv4_state dbus_ipv6_state; do
    action20ob_safe_variable=action20ob_${action20ob_observation}_safe
    printf -v "$action20ob_safe_variable" '%s' 0
    action20ob_output_variable=action20ob_${action20ob_observation}_output
    action20ob_status_variable=action20ob_${action20ob_observation}_status
    emit_observation "${action20ob_observation}_before" "${!action20ob_output_variable}" \
        "${!action20ob_status_variable}" || printf -v "$action20ob_safe_variable" '%s' "$?"
done

record_check identity_root test "$(id -u)" -eq 0
record_check working_directory_root test "$(pwd -P)" = /
record_check hostname_exact test "$(hostname)" = "$expected_hostname"
record_check interface_present test -d "/sys/class/net/$interface"
record_check main_regular test -f "$main_configuration"
record_check main_not_symlink test ! -L "$main_configuration"
record_check main_metadata test "$(stat -c '%U:%G:%a' "$main_configuration" 2>/dev/null || true)" = root:root:644
record_check main_hash_exact test "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$main_sha256"
record_check main_enable_dbus_once test "$(grep -Ec '^[[:space:]]*enable_dbus([[:space:]]|$)' "$main_configuration" 2>/dev/null || true)" -eq 1
record_check main_include_once test "$(grep -Fxc 'include /etc/keepalived/conf.d/caddy-ha.conf' "$main_configuration" 2>/dev/null || true)" -eq 1
record_check main_include_terminal test "$(tail -n 1 "$main_configuration" 2>/dev/null || true)" = 'include /etc/keepalived/conf.d/caddy-ha.conf'
record_check fragment_regular test -f "$fragment"
record_check fragment_not_symlink test ! -L "$fragment"
record_check fragment_metadata test "$(stat -c '%U:%G:%a' "$fragment" 2>/dev/null || true)" = root:root:644
record_check fragment_hash_exact test "$(file_hash "$fragment" 2>/dev/null || true)" = "$fragment_sha256"
record_check health_regular test -f "$health_helper"
record_check health_not_symlink test ! -L "$health_helper"
record_check health_metadata test "$(stat -c '%U:%G:%a' "$health_helper" 2>/dev/null || true)" = root:root:755
record_check health_hash_exact test "$(file_hash "$health_helper" 2>/dev/null || true)" = "$health_sha256"
record_check runtime_residue_absent_before residue_absent '/run/caddy-action20o-retry2.*'
record_check bundle_residue_absent_before residue_absent '/run/caddy-action20o-retry2-bundle.*'
record_check install_residue_absent_before residue_absent '/etc/keepalived/.keepalived.conf.action20o-retry2.*'
record_check keepalived_active_before systemctl is-active --quiet keepalived.service
record_check caddy_active_before systemctl is-active --quiet caddy.service
record_check lighttpd_active_before systemctl is-active --quiet lighttpd.service
record_check keepalived_pid_numeric_before test "$action20ob_pid_before" -gt 0
record_check keepalived_restarts_numeric_before test "$action20ob_restarts_before" -ge 0
record_check vrrp_state_backup_before test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = BACKUP
record_check ipv4_query_before_status test "$action20ob_ip4_status" -eq 0
record_check ipv4_output_before_safe test "$action20ob_ip4_safe" -eq 0
record_check ipv6_query_before_status test "$action20ob_ip6_status" -eq 0
record_check ipv6_output_before_safe test "$action20ob_ip6_safe" -eq 0
record_check caddy_ipv4_absent_before address_absent "$action20ob_ip4_status" "$action20ob_ip4_output" "$caddy_ipv4_cidr"
record_check caddy_ipv6_absent_before address_absent "$action20ob_ip6_status" "$action20ob_ip6_output" "$caddy_ipv6_cidr"
record_check dns_ipv4_absent_before address_absent "$action20ob_ip4_status" "$action20ob_ip4_output" "$dns_ipv4_cidr"
record_check dns_ipv6_absent_before address_absent "$action20ob_ip6_status" "$action20ob_ip6_output" "$dns_ipv6_cidr"
record_check dbus_list_before_status test "$action20ob_dbus_list_status" -eq 0
record_check dbus_list_before_safe test "$action20ob_dbus_list_safe" -eq 0
record_check dbus_service_once_before exact_first_field_once "$action20ob_dbus_list_status" "$action20ob_dbus_list_output" "$dbus_service"
record_check dbus_tree_before_status test "$action20ob_dbus_tree_status" -eq 0
record_check dbus_tree_before_safe test "$action20ob_dbus_tree_safe" -eq 0
record_check dbus_ipv4_object_once_before exact_line_once "$action20ob_dbus_tree_status" "$action20ob_dbus_tree_output" "$dbus_ipv4_object"
record_check dbus_ipv6_object_once_before exact_line_once "$action20ob_dbus_tree_status" "$action20ob_dbus_tree_output" "$dbus_ipv6_object"
record_check dbus_ipv4_state_before_status test "$action20ob_dbus_ipv4_state_status" -eq 0
record_check dbus_ipv4_state_before_safe test "$action20ob_dbus_ipv4_state_safe" -eq 0
record_check dbus_ipv4_state_backup_before exact_line_once "$action20ob_dbus_ipv4_state_status" "$action20ob_dbus_ipv4_state_output" "$expected_dbus_state"
record_check dbus_ipv6_state_before_status test "$action20ob_dbus_ipv6_state_status" -eq 0
record_check dbus_ipv6_state_before_safe test "$action20ob_dbus_ipv6_state_safe" -eq 0
record_check dbus_ipv6_state_backup_before exact_line_once "$action20ob_dbus_ipv6_state_status" "$action20ob_dbus_ipv6_state_output" "$expected_dbus_state"
record_check node_a_https_continuity https_probe pihole0.local.theama.co 10.1.0.53
record_check caddy_vip_https_continuity https_probe proxy.local.theama.co 10.1.0.56

capture_observations
for action20ob_observation in ip4 ip6 dbus_list dbus_tree dbus_ipv4_state dbus_ipv6_state; do
    action20ob_safe_variable=action20ob_${action20ob_observation}_safe
    printf -v "$action20ob_safe_variable" '%s' 0
    action20ob_output_variable=action20ob_${action20ob_observation}_output
    action20ob_status_variable=action20ob_${action20ob_observation}_status
    emit_observation "${action20ob_observation}_after" "${!action20ob_output_variable}" \
        "${!action20ob_status_variable}" || printf -v "$action20ob_safe_variable" '%s' "$?"
done

record_check ipv4_query_after_status test "$action20ob_ip4_status" -eq 0
record_check ipv4_output_after_safe test "$action20ob_ip4_safe" -eq 0
record_check ipv6_query_after_status test "$action20ob_ip6_status" -eq 0
record_check ipv6_output_after_safe test "$action20ob_ip6_safe" -eq 0
record_check dbus_list_after_status test "$action20ob_dbus_list_status" -eq 0
record_check dbus_list_after_safe test "$action20ob_dbus_list_safe" -eq 0
record_check dbus_tree_after_status test "$action20ob_dbus_tree_status" -eq 0
record_check dbus_tree_after_safe test "$action20ob_dbus_tree_safe" -eq 0
record_check dbus_ipv4_state_after_status test "$action20ob_dbus_ipv4_state_status" -eq 0
record_check dbus_ipv4_state_after_safe test "$action20ob_dbus_ipv4_state_safe" -eq 0
record_check dbus_ipv6_state_after_status test "$action20ob_dbus_ipv6_state_status" -eq 0
record_check dbus_ipv6_state_after_safe test "$action20ob_dbus_ipv6_state_safe" -eq 0
record_check keepalived_active_after systemctl is-active --quiet keepalived.service
record_check caddy_active_after systemctl is-active --quiet caddy.service
record_check lighttpd_active_after systemctl is-active --quiet lighttpd.service
record_check keepalived_pid_unchanged test "$(systemctl show keepalived.service -p MainPID --value 2>/dev/null || true)" = "$action20ob_pid_before"
record_check keepalived_restarts_unchanged test "$(systemctl show keepalived.service -p NRestarts --value 2>/dev/null || true)" = "$action20ob_restarts_before"
record_check vrrp_state_backup_after test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = BACKUP
record_check caddy_ipv4_absent_after address_absent "$action20ob_ip4_status" "$action20ob_ip4_output" "$caddy_ipv4_cidr"
record_check caddy_ipv6_absent_after address_absent "$action20ob_ip6_status" "$action20ob_ip6_output" "$caddy_ipv6_cidr"
record_check dns_ipv4_absent_after address_absent "$action20ob_ip4_status" "$action20ob_ip4_output" "$dns_ipv4_cidr"
record_check dns_ipv6_absent_after address_absent "$action20ob_ip6_status" "$action20ob_ip6_output" "$dns_ipv6_cidr"
record_check dbus_service_once_after exact_first_field_once "$action20ob_dbus_list_status" "$action20ob_dbus_list_output" "$dbus_service"
record_check dbus_ipv4_object_once_after exact_line_once "$action20ob_dbus_tree_status" "$action20ob_dbus_tree_output" "$dbus_ipv4_object"
record_check dbus_ipv6_object_once_after exact_line_once "$action20ob_dbus_tree_status" "$action20ob_dbus_tree_output" "$dbus_ipv6_object"
record_check dbus_ipv4_state_backup_after exact_line_once "$action20ob_dbus_ipv4_state_status" "$action20ob_dbus_ipv4_state_output" "$expected_dbus_state"
record_check dbus_ipv6_state_backup_after exact_line_once "$action20ob_dbus_ipv6_state_status" "$action20ob_dbus_ipv6_state_output" "$expected_dbus_state"
record_check main_hash_unchanged test "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$main_sha256"
record_check fragment_hash_unchanged test "$(file_hash "$fragment" 2>/dev/null || true)" = "$fragment_sha256"
record_check health_hash_unchanged test "$(file_hash "$health_helper" 2>/dev/null || true)" = "$health_sha256"
record_check runtime_residue_absent_after residue_absent '/run/caddy-action20o-retry2.*'
record_check bundle_residue_absent_after residue_absent '/run/caddy-action20o-retry2-bundle.*'
record_check install_residue_absent_after residue_absent '/etc/keepalived/.keepalived.conf.action20o-retry2.*'
action20ob_state_after=$(state_snapshot | sha256sum | awk '{ print $1 }')
record_check state_snapshot_unchanged test "$action20ob_state_after" = "$action20ob_state_before"

action20ob_expected_check_count=$(expected_checks | wc -l)
printf '%s_value_expected_check_count=%s\n' "$prefix" "$action20ob_expected_check_count"
printf '%s_value_main_sha256=%s\n' "$prefix" "$main_sha256"
printf '%s_value_fragment_sha256=%s\n' "$prefix" "$fragment_sha256"
printf '%s_value_health_sha256=%s\n' "$prefix" "$health_sha256"
printf '%s_value_dbus_service=%s\n' "$prefix" "$dbus_service"
printf '%s_value_dbus_ipv4_object=%s\n' "$prefix" "$dbus_ipv4_object"
printf '%s_value_dbus_ipv6_object=%s\n' "$prefix" "$dbus_ipv6_object"
printf '%s_value_dbus_state=Backup\n' "$prefix"
printf '%s_value_dbus_snapshot_normalization=process_column_busctl_only\n' "$prefix"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$action20ob_state_before"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$action20ob_state_after"
printf '%s_check_count=%s\n' "$prefix" "$action20ob_expected_check_count"
printf '%s_failed_check_count=%s\n' "$prefix" "$action20ob_failed_check_count"
printf '%s_first_failure=%s\n' "$prefix" "$action20ob_first_failure"
printf '%s_read_only=true\n' "$prefix"
printf '%s_health_helpers_invoked=false\n' "$prefix"
printf '%s_keepalived_reload=false\n' "$prefix"
printf '%s_keepalived_restart=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"
[[ "$action20ob_failed_check_count" -eq 0 ]]
