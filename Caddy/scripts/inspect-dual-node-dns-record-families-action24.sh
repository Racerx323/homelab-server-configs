#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_24
readonly accepted_local_zone_sha256=fa9f4850386ab1328f323c7c88bd9fa9ad0d5a84994b3066b6874deb5beb569c
readonly accepted_pihole_ftl_sha256=c77de6654c575e12fa1661f8ec901de67d9a623c3e9b965d4e32b550c132a7aa
readonly accepted_pihole_domain_sha256=a8305acbc27a9133d6e68e8b1a0fe9a462a975919233d71866d54b2e98810f96
readonly local_zone=/etc/unbound/unbound.conf.d/pihole-local-zone.conf
readonly pihole_ftl=/etc/pihole/pihole-FTL.conf
readonly pihole_domain=/etc/dnsmasq.d/local.theama.co.conf
readonly vrrp_state=/run/caddy-ha/vrrp-state
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
valid_sha256() {
    local action24_hash_value=$1

    [[ ${#action24_hash_value} -eq 64 ]] || return 1
    [[ "$action24_hash_value" != *[!0-9a-f]* ]]
}
safe_text() {
    local action24_text=$1

    [[ ${#action24_text} -le 4096 ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' <<<"$action24_text" >/dev/null
}
check() {
    local action24_check_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_%s_check_%s=true\n' "$prefix" "$node_token" "$action24_check_label"
        return 0
    fi
    printf '%s_%s_check_%s=false\n' "$prefix" "$node_token" "$action24_check_label" >&2
    return 1
}
address_count() {
    local action24_family=$1
    local action24_cidr=$2

    ip -o "$action24_family" addr show | awk -v expected="$action24_cidr" '$4 == expected { count++ } END { print count + 0 }'
}
service_unit() {
    case "$1" in
        unbound) printf '%s\n' unbound.service ;;
        pihole_ftl) printf '%s\n' pihole-FTL.service ;;
        keepalived) printf '%s\n' keepalived.service ;;
        caddy) printf '%s\n' caddy.service ;;
        lighttpd) printf '%s\n' lighttpd.service ;;
        *) return 64 ;;
    esac
}
state_snapshot() {
    printf 'files=%s|%s|%s\n' \
        "$(file_hash "$local_zone")" "$(file_hash "$pihole_ftl")" "$(file_hash "$pihole_domain")"
    printf 'services=%s|%s|%s|%s|%s\n' \
        "$(systemctl is-active unbound.service)" \
        "$(systemctl is-active pihole-FTL.service)" \
        "$(systemctl is-active keepalived.service)" \
        "$(systemctl is-active caddy.service)" \
        "$(systemctl is-active lighttpd.service)"
    printf 'vrrp=%s\n' "$(sed -n '1p' "$vrrp_state")"
    printf 'addresses=%s|%s|%s|%s|%s|%s\n' \
        "$(address_count -4 "$physical_ipv4_cidr")" \
        "$(address_count -6 "$physical_ipv6_cidr")" \
        "$(address_count -4 "$caddy_ipv4_cidr")" \
        "$(address_count -6 "$caddy_ipv6_cidr")" \
        "$(address_count -4 "$dns_ipv4_cidr")" \
        "$(address_count -6 "$dns_ipv6_cidr")"
}
expected_query_specs() {
    printf '%s\n' \
        'admin_a|pihole-admin.local.theama.co|A|10.1.0.56' \
        'proxy_a|proxy.local.theama.co|A|10.1.0.56' \
        'admin_aaaa|pihole-admin.local.theama.co|AAAA|fd36:5aa8:6971:1::56' \
        'proxy_aaaa|proxy.local.theama.co|AAAA|fd36:5aa8:6971:1::56' \
        'caddy_ptr4|10.1.0.56|PTR|proxy.local.theama.co.' \
        'caddy_ptr6|fd36:5aa8:6971:1::56|PTR|proxy.local.theama.co.' \
        'https_srv|_https._tcp.proxy.local.theama.co|SRV|0_0_443_proxy.local.theama.co.' \
        'smtp_srv|_smtp._tcp.local.theama.co|SRV|0_10_8025_mailrise.local.theama.co.' \
        'pihole_a|pihole.local.theama.co|A|10.1.0.55' \
        'pihole_aaaa|pihole.local.theama.co|AAAA|fd36:5aa8:6971:1::55' \
        'pihole_ptr4|10.1.0.55|PTR|pihole.local.theama.co.' \
        'pihole_ptr6|fd36:5aa8:6971:1::55|PTR|pihole.local.theama.co.'
}
expected_checks() {
    printf '%s\n' \
        uid_root working_directory_root hostname_exact local_zone_regular local_zone_not_symlink \
        local_zone_hash pihole_ftl_regular pihole_ftl_not_symlink pihole_ftl_hash \
        pihole_ptr_policy_exact pihole_domain_regular pihole_domain_not_symlink \
        pihole_domain_hash pihole_domain_exact unbound_active_before pihole_ftl_active_before \
        keepalived_active_before caddy_active_before lighttpd_active_before vrrp_state_regular \
        vrrp_state_not_symlink vrrp_state_exact physical_ipv4_owned_before \
        physical_ipv6_owned_before caddy_ipv4_count_before caddy_ipv6_count_before \
        dns_ipv4_count_before dns_ipv6_count_before before_state_hash_valid
    while IFS='|' read -r action24_query_label _ _ _; do
        for action24_path in direct local; do
            printf '%s\n' \
                "${action24_path}_${action24_query_label}_command_status" \
                "${action24_path}_${action24_query_label}_answer_safe" \
                "${action24_path}_${action24_query_label}_answer_exact"
        done
    done < <(expected_query_specs)
    printf '%s\n' \
        unbound_active_after pihole_ftl_active_after keepalived_active_after caddy_active_after \
        lighttpd_active_after vrrp_state_exact_after physical_ipv4_owned_after \
        physical_ipv6_owned_after caddy_ipv4_count_after caddy_ipv6_count_after \
        dns_ipv4_count_after dns_ipv6_count_after local_zone_hash_after \
        pihole_ftl_hash_after pihole_domain_hash_after after_state_hash_valid state_unchanged
}
normalize_answer() {
    local action24_record_type=$1

    if [[ "$action24_record_type" == SRV ]]; then
        awk '{$1=$1; gsub(/ /, "_"); print}'
    else
        sed '/^$/d'
    fi
}
query_and_check() {
    local action24_path_label=$1
    local action24_server=$2
    local action24_port=$3
    local action24_query_label=$4
    local action24_query_name=$5
    local action24_query_type=$6
    local action24_expected_answer=$7
    local action24_query_status=0
    local action24_query_output

    action24_query_output=$(dig +time=2 +tries=1 +short \
        "@$action24_server" -p "$action24_port" "$action24_query_name" "$action24_query_type" 2>&1) ||
        action24_query_status=$?
    check "${action24_path_label}_${action24_query_label}_command_status" \
        test "$action24_query_status" -eq 0 || return 1
    check "${action24_path_label}_${action24_query_label}_answer_safe" \
        safe_text "$action24_query_output" || return 1
    action24_query_output=$(printf '%s\n' "$action24_query_output" | normalize_answer "$action24_query_type") || return 1
    check "${action24_path_label}_${action24_query_label}_answer_exact" \
        test "$action24_query_output" = "$action24_expected_answer" || return 1
    printf '%s_%s_value_%s_%s=%s\n' "$prefix" "$node_token" \
        "$action24_path_label" "$action24_query_label" "$action24_query_output"
}
configure_node() {
    local action24_role=$1

    case "$action24_role" in
        node-a)
            node_token=node_a
            expected_hostname=j1-svpihole0
            physical_ipv4_cidr=10.1.0.53/22
            physical_ipv6_cidr=fd36:5aa8:6971:1::53/64
            expected_vrrp=MASTER
            expected_vip_count=1
            ;;
        node-b)
            node_token=node_b
            expected_hostname=j1-svpihole00
            physical_ipv4_cidr=10.1.0.54/22
            physical_ipv6_cidr=fd36:5aa8:6971:1::54/64
            expected_vrrp=BACKUP
            expected_vip_count=0
            ;;
        *) return 64 ;;
    esac
    readonly node_token expected_hostname physical_ipv4_cidr physical_ipv6_cidr expected_vrrp expected_vip_count
}
run_inspection() {
    local action24_before_state
    local action24_after_state

    check uid_root test "$(id -u)" -eq 0 || return 1
    check working_directory_root test "$PWD" = / || return 1
    check hostname_exact test "$(hostname)" = "$expected_hostname" || return 1
    check local_zone_regular test -f "$local_zone" || return 1
    check local_zone_not_symlink test ! -L "$local_zone" || return 1
    check local_zone_hash test "$(file_hash "$local_zone")" = "$accepted_local_zone_sha256" || return 1
    check pihole_ftl_regular test -f "$pihole_ftl" || return 1
    check pihole_ftl_not_symlink test ! -L "$pihole_ftl" || return 1
    check pihole_ftl_hash test "$(file_hash "$pihole_ftl")" = "$accepted_pihole_ftl_sha256" || return 1
    check pihole_ptr_policy_exact grep -Fqx 'PIHOLE_PTR=NONE' "$pihole_ftl" || return 1
    check pihole_domain_regular test -f "$pihole_domain" || return 1
    check pihole_domain_not_symlink test ! -L "$pihole_domain" || return 1
    check pihole_domain_hash test "$(file_hash "$pihole_domain")" = "$accepted_pihole_domain_sha256" || return 1
    check pihole_domain_exact grep -Fqx 'domain=local.theama.co' "$pihole_domain" || return 1
    for action24_service in unbound pihole_ftl keepalived caddy lighttpd; do
        check "${action24_service}_active_before" systemctl is-active --quiet \
            "$(service_unit "$action24_service")" || return 1
    done
    check vrrp_state_regular test -f "$vrrp_state" || return 1
    check vrrp_state_not_symlink test ! -L "$vrrp_state" || return 1
    check vrrp_state_exact test "$(sed -n '1p' "$vrrp_state")" = "$expected_vrrp" || return 1
    check physical_ipv4_owned_before test "$(address_count -4 "$physical_ipv4_cidr")" -eq 1 || return 1
    check physical_ipv6_owned_before test "$(address_count -6 "$physical_ipv6_cidr")" -eq 1 || return 1
    check caddy_ipv4_count_before test "$(address_count -4 "$caddy_ipv4_cidr")" -eq "$expected_vip_count" || return 1
    check caddy_ipv6_count_before test "$(address_count -6 "$caddy_ipv6_cidr")" -eq "$expected_vip_count" || return 1
    check dns_ipv4_count_before test "$(address_count -4 "$dns_ipv4_cidr")" -eq "$expected_vip_count" || return 1
    check dns_ipv6_count_before test "$(address_count -6 "$dns_ipv6_cidr")" -eq "$expected_vip_count" || return 1
    action24_before_state=$(state_snapshot | sha256sum | awk '{ print $1 }') || return 1
    check before_state_hash_valid valid_sha256 "$action24_before_state" || return 1

    while IFS='|' read -r action24_query_label action24_query_name action24_query_type action24_expected_answer; do
        query_and_check direct 127.0.0.1 5335 "$action24_query_label" \
            "$action24_query_name" "$action24_query_type" "$action24_expected_answer" || return 1
        query_and_check local 127.0.0.1 53 "$action24_query_label" \
            "$action24_query_name" "$action24_query_type" "$action24_expected_answer" || return 1
    done < <(expected_query_specs)

    for action24_service in unbound pihole_ftl keepalived caddy lighttpd; do
        check "${action24_service}_active_after" systemctl is-active --quiet \
            "$(service_unit "$action24_service")" || return 1
    done
    check vrrp_state_exact_after test "$(sed -n '1p' "$vrrp_state")" = "$expected_vrrp" || return 1
    check physical_ipv4_owned_after test "$(address_count -4 "$physical_ipv4_cidr")" -eq 1 || return 1
    check physical_ipv6_owned_after test "$(address_count -6 "$physical_ipv6_cidr")" -eq 1 || return 1
    check caddy_ipv4_count_after test "$(address_count -4 "$caddy_ipv4_cidr")" -eq "$expected_vip_count" || return 1
    check caddy_ipv6_count_after test "$(address_count -6 "$caddy_ipv6_cidr")" -eq "$expected_vip_count" || return 1
    check dns_ipv4_count_after test "$(address_count -4 "$dns_ipv4_cidr")" -eq "$expected_vip_count" || return 1
    check dns_ipv6_count_after test "$(address_count -6 "$dns_ipv6_cidr")" -eq "$expected_vip_count" || return 1
    check local_zone_hash_after test "$(file_hash "$local_zone")" = "$accepted_local_zone_sha256" || return 1
    check pihole_ftl_hash_after test "$(file_hash "$pihole_ftl")" = "$accepted_pihole_ftl_sha256" || return 1
    check pihole_domain_hash_after test "$(file_hash "$pihole_domain")" = "$accepted_pihole_domain_sha256" || return 1
    action24_after_state=$(state_snapshot | sha256sum | awk '{ print $1 }') || return 1
    check after_state_hash_valid valid_sha256 "$action24_after_state" || return 1
    check state_unchanged test "$action24_before_state" = "$action24_after_state" || return 1

    printf '%s_%s_value_before_state_sha256=%s\n' "$prefix" "$node_token" "$action24_before_state"
    printf '%s_%s_value_after_state_sha256=%s\n' "$prefix" "$node_token" "$action24_after_state"
    printf '%s_%s_value_local_zone_sha256=%s\n' "$prefix" "$node_token" "$accepted_local_zone_sha256"
    printf '%s_%s_value_vrrp_state=%s\n' "$prefix" "$node_token" "$expected_vrrp"
    printf '%s_%s_check_count=%s\n' "$prefix" "$node_token" "$(expected_checks | wc -l)"
    printf '%s_%s_filesystem_mutation=false\n' "$prefix" "$node_token"
    printf '%s_%s_service_mutation=false\n' "$prefix" "$node_token"
    printf '%s_%s_dns_mutation=false\n' "$prefix" "$node_token"
    printf '%s_%s_peer_ssh=false\n' "$prefix" "$node_token"
    printf '%s_%s_remote_complete=true\n' "$prefix" "$node_token"
}
self_test() {
    local action24_self_test_state=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

    while IFS= read -r action24_self_test_label; do
        printf '%s_%s_check_%s=true\n' "$prefix" "$node_token" "$action24_self_test_label"
    done < <(expected_checks)
    while IFS='|' read -r action24_query_label _ _ action24_expected_answer; do
        for action24_path in direct local; do
            printf '%s_%s_value_%s_%s=%s\n' "$prefix" "$node_token" \
                "$action24_path" "$action24_query_label" "$action24_expected_answer"
        done
    done < <(expected_query_specs)
    printf '%s_%s_value_before_state_sha256=%s\n' "$prefix" "$node_token" "$action24_self_test_state"
    printf '%s_%s_value_after_state_sha256=%s\n' "$prefix" "$node_token" "$action24_self_test_state"
    printf '%s_%s_value_local_zone_sha256=%s\n' "$prefix" "$node_token" "$accepted_local_zone_sha256"
    printf '%s_%s_value_vrrp_state=%s\n' "$prefix" "$node_token" "$expected_vrrp"
    printf '%s_%s_check_count=%s\n' "$prefix" "$node_token" "$(expected_checks | wc -l)"
    printf '%s_%s_filesystem_mutation=false\n' "$prefix" "$node_token"
    printf '%s_%s_service_mutation=false\n' "$prefix" "$node_token"
    printf '%s_%s_dns_mutation=false\n' "$prefix" "$node_token"
    printf '%s_%s_peer_ssh=false\n' "$prefix" "$node_token"
    printf '%s_%s_remote_complete=true\n' "$prefix" "$node_token"
}

mode=${1:-}
case "$mode" in
    --expected-checks)
        configure_node "${2:-}" || exit $?
        expected_checks
        ;;
    --self-test-node)
        configure_node "${2:-}" || exit $?
        self_test
        ;;
    --node)
        configure_node "${2:-}" || exit $?
        run_inspection
        ;;
    *) exit 64 ;;
esac
