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
readonly publisher=/usr/local/libexec/publish-release-v2.sh
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly node_a_main_sha256=8fc9dcf8e079b7131f86a58038ae5543804a5158a02d53a4614452de212ce47c
readonly node_b_main_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
readonly node_a_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly node_b_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669

expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root role_valid phase_valid hostname_exact \
        interface_present main_regular main_not_symlink main_metadata main_hash_exact \
        fragment_regular fragment_not_symlink fragment_metadata fragment_hash_exact \
        fragment_unicast_ttl_count fragment_peer_ttl_count health_regular \
        health_not_symlink health_metadata health_hash_exact publisher_regular \
        publisher_not_symlink publisher_metadata publisher_hash_exact current_symlink \
        current_target_directory current_target_not_symlink keepalived_active \
        lighttpd_active caddy_state_expected vrrp_state_file_regular \
        vrrp_state_file_not_symlink vrrp_state_expected ipv4_query_status_zero \
        ipv4_output_safe ipv6_query_status_zero ipv6_output_safe \
        caddy_ipv4_count_expected caddy_ipv6_count_expected dns_ipv4_count_expected \
        dns_ipv6_count_expected health_status_expected vip_https_status_expected \
        lsyncd_inactive caddy_lsyncd_inactive reconcile_path_inactive \
        reconcile_service_inactive
}

node_role=
phase=
while (($#)); do
    case "$1" in
        --node)
            [[ $# -ge 2 ]] || exit 64
            node_role=$2
            shift 2
            ;;
        --phase)
            [[ $# -ge 2 ]] || exit 64
            phase=$2
            shift 2
            ;;
        --expected-checks)
            [[ $# -eq 1 ]] || exit 64
            expected_checks
            exit 0
            ;;
        --self-test)
            [[ $# -eq 1 ]] || exit 64
            labels=$(expected_checks) || exit 1
            [[ "$(printf '%s\n' "$labels" | wc -l)" -eq "$(printf '%s\n' "$labels" | LC_ALL=C sort -u | wc -l)" ]] || exit 1
            printf 'action_28j_inspector_self_test_complete=true\n'
            exit 0
            ;;
        *) exit 64 ;;
    esac
done

case "$node_role:$phase" in
    node-a:baseline)
        readonly prefix=action_28j_node_a_baseline
        readonly expected_hostname=j1-svpihole0
        readonly expected_main_sha256=$node_a_main_sha256
        readonly expected_health_sha256=$node_a_health_sha256
        readonly fragment_sha256=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
        readonly expected_caddy_state=active
        readonly expected_vrrp_state=MASTER
        readonly expected_caddy_count=1
        readonly expected_dns_count=1
        readonly expected_health_status=zero
        readonly expected_https_status=0
        ;;
    node-b:baseline)
        readonly prefix=action_28j_node_b_baseline
        readonly expected_hostname=j1-svpihole00
        readonly expected_main_sha256=$node_b_main_sha256
        readonly expected_health_sha256=$node_b_health_sha256
        readonly fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
        readonly expected_caddy_state=active
        readonly expected_vrrp_state=BACKUP
        readonly expected_caddy_count=0
        readonly expected_dns_count=0
        readonly expected_health_status=zero
        readonly expected_https_status=0
        ;;
    node-a:failed)
        readonly prefix=action_28j_node_a_failed
        readonly expected_hostname=j1-svpihole0
        readonly expected_main_sha256=$node_a_main_sha256
        readonly expected_health_sha256=$node_a_health_sha256
        readonly fragment_sha256=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
        readonly expected_caddy_state=inactive
        readonly expected_vrrp_state=FAULT
        readonly expected_caddy_count=0
        readonly expected_dns_count=1
        readonly expected_health_status=nonzero
        readonly expected_https_status=0
        ;;
    node-b:failed)
        readonly prefix=action_28j_node_b_failed
        readonly expected_hostname=j1-svpihole00
        readonly expected_main_sha256=$node_b_main_sha256
        readonly expected_health_sha256=$node_b_health_sha256
        readonly fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
        readonly expected_caddy_state=active
        readonly expected_vrrp_state=MASTER
        readonly expected_caddy_count=1
        readonly expected_dns_count=0
        readonly expected_health_status=zero
        readonly expected_https_status=0
        ;;
    *) exit 64 ;;
esac

failed_check_count=0
first_failure=none
file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
safe_text() {
    local action28j_text=$1
    [[ ${#action28j_text} -le 131072 ]] || return 1
    ! printf '%s' "$action28j_text" | LC_ALL=C grep -q '[^[:print:][:space:]]' || return 1
}
record_check() {
    local action28j_check_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28j_check_label"
    else
        printf '%s_check_%s=false\n' "$prefix" "$action28j_check_label"
        failed_check_count=$((failed_check_count + 1))
        [[ "$first_failure" != none ]] || first_failure=$action28j_check_label
    fi
    return 0
}
address_count() {
    local action28j_output=$1
    local action28j_cidr=$2
    printf '%s\n' "$action28j_output" | awk -v expected="$action28j_cidr" \
        '$4 == expected { count++ } END { print count + 0 }'
}
status_matches() {
    local action28j_status=$1
    local action28j_expectation=$2

    if [[ "$action28j_expectation" = zero ]]; then
        [[ "$action28j_status" -eq 0 ]]
    else
        [[ "$action28j_status" -ne 0 ]]
    fi
}

ipv4_status=0
ipv4_output=$(ip -o -4 address show dev "$interface" 2>&1) || ipv4_status=$?
ipv6_status=0
ipv6_output=$(ip -o -6 address show dev "$interface" 2>&1) || ipv6_status=$?
health_status=0
timeout 10 "$health_helper" >/dev/null 2>&1 || health_status=$?
https_status=0
curl --silent --show-error --fail --insecure --head --connect-timeout 3 \
    --max-time 10 --resolve proxy.local.theama.co:443:10.1.0.56 \
    https://proxy.local.theama.co/ >/dev/null 2>&1 || https_status=$?

record_check identity_root test "$(id -u)" -eq 0
record_check working_directory_root test "$(pwd -P)" = /
record_check role_valid test "$node_role" = node-a -o "$node_role" = node-b
record_check phase_valid test "$phase" = baseline -o "$phase" = failed
record_check hostname_exact test "$(hostname)" = "$expected_hostname"
record_check interface_present test -d "/sys/class/net/$interface"
record_check main_regular test -f "$main_configuration"
record_check main_not_symlink test ! -L "$main_configuration"
record_check main_metadata test "$(stat -c '%U:%G:%a' "$main_configuration" 2>/dev/null || true)" = root:root:644
record_check main_hash_exact test "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$expected_main_sha256"
record_check fragment_regular test -f "$fragment"
record_check fragment_not_symlink test ! -L "$fragment"
record_check fragment_metadata test "$(stat -c '%U:%G:%a' "$fragment" 2>/dev/null || true)" = root:root:644
record_check fragment_hash_exact test "$(file_hash "$fragment" 2>/dev/null || true)" = "$fragment_sha256"
record_check fragment_unicast_ttl_count test "$(grep -Ec '^[[:space:]]*unicast_ttl[[:space:]]+255[[:space:]]*$' "$fragment" || true)" -eq 2
record_check fragment_peer_ttl_count test "$(grep -Ec 'min_ttl[[:space:]]+255[[:space:]]+max_ttl[[:space:]]+255' "$fragment" || true)" -eq 2
record_check health_regular test -f "$health_helper"
record_check health_not_symlink test ! -L "$health_helper"
record_check health_metadata test "$(stat -c '%U:%G:%a' "$health_helper" 2>/dev/null || true)" = root:root:755
record_check health_hash_exact test "$(file_hash "$health_helper" 2>/dev/null || true)" = "$expected_health_sha256"
record_check publisher_regular test -f "$publisher"
record_check publisher_not_symlink test ! -L "$publisher"
record_check publisher_metadata test "$(stat -c '%U:%G:%a' "$publisher" 2>/dev/null || true)" = root:root:755
record_check publisher_hash_exact test "$(file_hash "$publisher" 2>/dev/null || true)" = "$publisher_sha256"
record_check current_symlink test -L /etc/caddy/current
current_target=$(readlink -e -- /etc/caddy/current 2>/dev/null || true)
record_check current_target_directory test -d "$current_target"
record_check current_target_not_symlink test ! -L "$current_target"
record_check keepalived_active systemctl is-active --quiet keepalived.service
record_check lighttpd_active systemctl is-active --quiet lighttpd.service
record_check caddy_state_expected test "$(systemctl is-active caddy.service 2>/dev/null || true)" = "$expected_caddy_state"
record_check vrrp_state_file_regular test -f /run/caddy-ha/vrrp-state
record_check vrrp_state_file_not_symlink test ! -L /run/caddy-ha/vrrp-state
record_check vrrp_state_expected test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = "$expected_vrrp_state"
record_check ipv4_query_status_zero test "$ipv4_status" -eq 0
record_check ipv4_output_safe safe_text "$ipv4_output"
record_check ipv6_query_status_zero test "$ipv6_status" -eq 0
record_check ipv6_output_safe safe_text "$ipv6_output"
record_check caddy_ipv4_count_expected test "$(address_count "$ipv4_output" "$caddy_ipv4_cidr")" -eq "$expected_caddy_count"
record_check caddy_ipv6_count_expected test "$(address_count "$ipv6_output" "$caddy_ipv6_cidr")" -eq "$expected_caddy_count"
record_check dns_ipv4_count_expected test "$(address_count "$ipv4_output" "$dns_ipv4_cidr")" -eq "$expected_dns_count"
record_check dns_ipv6_count_expected test "$(address_count "$ipv6_output" "$dns_ipv6_cidr")" -eq "$expected_dns_count"
record_check health_status_expected status_matches "$health_status" "$expected_health_status"
record_check vip_https_status_expected test "$https_status" -eq "$expected_https_status"
record_check lsyncd_inactive test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
record_check caddy_lsyncd_inactive test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = inactive
record_check reconcile_path_inactive test "$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)" = inactive
record_check reconcile_service_inactive test "$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)" = inactive

printf '%s_value_node_role=%s\n' "$prefix" "$node_role"
printf '%s_value_phase=%s\n' "$prefix" "$phase"
printf '%s_value_vrrp_state=%s\n' "$prefix" "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || printf unavailable)"
printf '%s_value_caddy_ipv4_count=%s\n' "$prefix" "$(address_count "$ipv4_output" "$caddy_ipv4_cidr")"
printf '%s_value_caddy_ipv6_count=%s\n' "$prefix" "$(address_count "$ipv6_output" "$caddy_ipv6_cidr")"
printf '%s_value_dns_ipv4_count=%s\n' "$prefix" "$(address_count "$ipv4_output" "$dns_ipv4_cidr")"
printf '%s_value_dns_ipv6_count=%s\n' "$prefix" "$(address_count "$ipv6_output" "$dns_ipv6_cidr")"
printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
printf '%s_failed_check_count=%s\n' "$prefix" "$failed_check_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_publisher_invoked=false\n' "$prefix"
if [[ "$failed_check_count" -ne 0 ]]; then
    printf '%s_acceptance=false\n' "$prefix"
    exit 1
fi
printf '%s_acceptance=true\n' "$prefix"
