#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_25_retry
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
readonly maximum_probe_bytes=1048576

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
valid_sha256() {
    local action25_hash_value=$1

    [[ ${#action25_hash_value} -eq 64 ]] || return 1
    [[ "$action25_hash_value" != *[!0-9a-f]* ]]
}
safe_text() {
    local action25_text_value=$1

    [[ ${#action25_text_value} -le "$maximum_probe_bytes" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' <<<"$action25_text_value" >/dev/null
}
check() {
    local action25_check_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_%s_check_%s=true\n' "$prefix" "$node_token" "$action25_check_label"
        return 0
    fi
    printf '%s_%s_check_%s=false\n' "$prefix" "$node_token" "$action25_check_label" >&2
    return 1
}
address_count() {
    local action25_address_family=$1
    local action25_address_cidr=$2

    ip -o "$action25_address_family" addr show |
        awk -v expected="$action25_address_cidr" '$4 == expected { count++ } END { print count + 0 }'
}
endpoint_specs() {
    printf '%s\n' \
        'shared_ipv4|pihole-admin.local.theama.co|10.1.0.56|10.1.0.56' \
        'shared_ipv6|pihole-admin.local.theama.co|[fd36:5aa8:6971:1::56]|fd36:5aa8:6971:1::56' \
        'node_a_ipv4|pihole0.local.theama.co|10.1.0.53|10.1.0.53' \
        'node_a_ipv6|pihole0.local.theama.co|[fd36:5aa8:6971:1::53]|fd36:5aa8:6971:1::53' \
        'node_b_ipv4|pihole00.local.theama.co|10.1.0.54|10.1.0.54' \
        'node_b_ipv6|pihole00.local.theama.co|[fd36:5aa8:6971:1::54]|fd36:5aa8:6971:1::54'
}
expected_checks() {
    printf '%s\n' \
        uid_root working_directory_root hostname_exact local_zone_regular local_zone_not_symlink \
        local_zone_hash pihole_ftl_regular pihole_ftl_not_symlink pihole_ftl_hash \
        pihole_domain_regular pihole_domain_not_symlink pihole_domain_hash \
        pihole_domain_exact caddy_active_before lighttpd_active_before keepalived_active_before \
        vrrp_state_regular vrrp_state_not_symlink vrrp_state_exact \
        physical_ipv4_owned_before physical_ipv6_owned_before caddy_ipv4_count_before \
        caddy_ipv6_count_before dns_ipv4_count_before dns_ipv6_count_before before_state_hash_valid
    while IFS='|' read -r action25_endpoint_label _ _ _; do
        printf '%s\n' \
            "${action25_endpoint_label}_command_status" \
            "${action25_endpoint_label}_output_safe" \
            "${action25_endpoint_label}_metadata_present" \
            "${action25_endpoint_label}_http_200" \
            "${action25_endpoint_label}_effective_url_exact" \
            "${action25_endpoint_label}_remote_ip_exact" \
            "${action25_endpoint_label}_body_nonempty" \
            "${action25_endpoint_label}_body_bounded" \
            "${action25_endpoint_label}_body_pihole_marker"
    done < <(endpoint_specs)
    printf '%s\n' \
        caddy_active_after lighttpd_active_after keepalived_active_after vrrp_state_exact_after \
        physical_ipv4_owned_after physical_ipv6_owned_after caddy_ipv4_count_after \
        caddy_ipv6_count_after dns_ipv4_count_after dns_ipv6_count_after local_zone_hash_after \
        pihole_ftl_hash_after pihole_domain_hash_after after_state_hash_valid state_unchanged
}
state_snapshot() {
    printf 'files=%s|%s|%s\n' \
        "$(file_hash "$local_zone")" "$(file_hash "$pihole_ftl")" "$(file_hash "$pihole_domain")"
    printf 'services=%s|%s|%s\n' \
        "$(systemctl is-active caddy.service)" \
        "$(systemctl is-active lighttpd.service)" \
        "$(systemctl is-active keepalived.service)"
    printf 'vrrp=%s\n' "$(sed -n '1p' "$vrrp_state")"
    printf 'addresses=%s|%s|%s|%s|%s|%s\n' \
        "$(address_count -4 "$physical_ipv4_cidr")" \
        "$(address_count -6 "$physical_ipv6_cidr")" \
        "$(address_count -4 "$caddy_ipv4_cidr")" \
        "$(address_count -6 "$caddy_ipv6_cidr")" \
        "$(address_count -4 "$dns_ipv4_cidr")" \
        "$(address_count -6 "$dns_ipv6_cidr")"
}
configure_node() {
    local action25_node_role=$1

    case "$action25_node_role" in
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
probe_endpoint() {
    local action25_endpoint_label=$1
    local action25_endpoint_fqdn=$2
    local action25_resolve_address=$3
    local action25_expected_remote_ip=$4
    local action25_curl_status=0
    local action25_curl_output
    local action25_output_classification
    local action25_metadata
    local action25_body
    local action25_body_sha256
    local action25_body_marker
    local action25_http_code
    local action25_effective_url
    local action25_remote_ip
    local action25_expected_url="https://${action25_endpoint_fqdn}/admin/"

    action25_curl_output=$("${CADDY_ACTION25_RETRY_CURL_BIN:-/usr/bin/curl}" \
        --noproxy '*' --insecure --silent --show-error --http1.1 \
        --connect-timeout 3 --max-time 10 \
        --resolve "${action25_endpoint_fqdn}:443:${action25_resolve_address}" \
        --write-out $'\naction25-metadata|%{http_code}|%{url_effective}|%{remote_ip}' \
        "$action25_expected_url") || action25_curl_status=$?

    printf '%s_%s_observed_%s_command_status=%s\n' "$prefix" "$node_token" \
        "$action25_endpoint_label" "$action25_curl_status"
    if safe_text "$action25_curl_output" &&
        ! grep -Eqi \
            'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
            <<<"$action25_curl_output"; then
        action25_output_classification=bounded_safe
        printf '%s_%s_observed_%s_output_classification=%s\n' "$prefix" "$node_token" \
            "$action25_endpoint_label" "$action25_output_classification"
        printf '%s_%s_observed_%s_output_begin\n' "$prefix" "$node_token" "$action25_endpoint_label"
        printf '%s\n' "$action25_curl_output"
        printf '%s_%s_observed_%s_output_end\n' "$prefix" "$node_token" "$action25_endpoint_label"
    else
        action25_output_classification=unsafe_suppressed
        printf '%s_%s_observed_%s_output_classification=%s\n' "$prefix" "$node_token" \
            "$action25_endpoint_label" "$action25_output_classification"
    fi

    check "${action25_endpoint_label}_command_status" test "$action25_curl_status" -eq 0 || return 1
    check "${action25_endpoint_label}_output_safe" \
        test "$action25_output_classification" = bounded_safe || return 1
    action25_metadata=$(printf '%s\n' "$action25_curl_output" | tail -n 1) || return 1
    action25_body=$(printf '%s\n' "$action25_curl_output" | sed '$d') || return 1
    check "${action25_endpoint_label}_metadata_present" \
        test "${action25_metadata%%|*}" = action25-metadata || return 1
    IFS='|' read -r _ action25_http_code action25_effective_url action25_remote_ip <<<"$action25_metadata"
    action25_body_sha256=$(printf '%s' "$action25_body" | sha256sum | awk '{ print $1 }') || return 1
    if grep -Fqi 'Pi-hole' <<<"$action25_body"; then
        action25_body_marker=true
    else
        action25_body_marker=false
    fi

    printf '%s_%s_observed_%s_http_code=%s\n' "$prefix" "$node_token" \
        "$action25_endpoint_label" "$action25_http_code"
    printf '%s_%s_observed_%s_effective_url=%s\n' "$prefix" "$node_token" \
        "$action25_endpoint_label" "$action25_effective_url"
    printf '%s_%s_observed_%s_remote_ip=%s\n' "$prefix" "$node_token" \
        "$action25_endpoint_label" "$action25_remote_ip"
    printf '%s_%s_observed_%s_body_bytes=%s\n' "$prefix" "$node_token" \
        "$action25_endpoint_label" "${#action25_body}"
    printf '%s_%s_observed_%s_body_sha256=%s\n' "$prefix" "$node_token" \
        "$action25_endpoint_label" "$action25_body_sha256"
    printf '%s_%s_observed_%s_body_classification=%s\n' "$prefix" "$node_token" \
        "$action25_endpoint_label" "$action25_output_classification"
    printf '%s_%s_observed_%s_body_pihole_marker=%s\n' "$prefix" "$node_token" \
        "$action25_endpoint_label" "$action25_body_marker"

    check "${action25_endpoint_label}_http_200" test "$action25_http_code" = 200 || return 1
    check "${action25_endpoint_label}_effective_url_exact" \
        test "$action25_effective_url" = "$action25_expected_url" || return 1
    check "${action25_endpoint_label}_remote_ip_exact" \
        test "$action25_remote_ip" = "$action25_expected_remote_ip" || return 1
    check "${action25_endpoint_label}_body_nonempty" test -n "$action25_body" || return 1
    check "${action25_endpoint_label}_body_bounded" \
        test "${#action25_body}" -le "$maximum_probe_bytes" || return 1
    check "${action25_endpoint_label}_body_pihole_marker" \
        test "$action25_body_marker" = true || return 1
    printf '%s_%s_value_%s_http_code=%s\n' "$prefix" "$node_token" \
        "$action25_endpoint_label" "$action25_http_code"
    printf '%s_%s_value_%s_effective_url=%s\n' "$prefix" "$node_token" \
        "$action25_endpoint_label" "$action25_effective_url"
    printf '%s_%s_value_%s_remote_ip=%s\n' "$prefix" "$node_token" \
        "$action25_endpoint_label" "$action25_remote_ip"
    printf '%s_%s_value_%s_body_bytes=%s\n' "$prefix" "$node_token" \
        "$action25_endpoint_label" "${#action25_body}"
    printf '%s_%s_value_%s_body_sha256=%s\n' "$prefix" "$node_token" \
        "$action25_endpoint_label" "$action25_body_sha256"
}
run_inspection() {
    local action25_before_state
    local action25_after_state

    # conditional-validator-explicit-failures-begin
    check uid_root test "$(id -u)" -eq 0 || return 1
    check working_directory_root test "$PWD" = / || return 1
    check hostname_exact test "$(hostname)" = "$expected_hostname" || return 1
    check local_zone_regular test -f "$local_zone" || return 1
    check local_zone_not_symlink test ! -L "$local_zone" || return 1
    check local_zone_hash test "$(file_hash "$local_zone")" = "$accepted_local_zone_sha256" || return 1
    check pihole_ftl_regular test -f "$pihole_ftl" || return 1
    check pihole_ftl_not_symlink test ! -L "$pihole_ftl" || return 1
    check pihole_ftl_hash test "$(file_hash "$pihole_ftl")" = "$accepted_pihole_ftl_sha256" || return 1
    check pihole_domain_regular test -f "$pihole_domain" || return 1
    check pihole_domain_not_symlink test ! -L "$pihole_domain" || return 1
    check pihole_domain_hash test "$(file_hash "$pihole_domain")" = "$accepted_pihole_domain_sha256" || return 1
    check pihole_domain_exact grep -Fqx 'domain=local.theama.co' "$pihole_domain" || return 1
    check caddy_active_before systemctl is-active --quiet caddy.service || return 1
    check lighttpd_active_before systemctl is-active --quiet lighttpd.service || return 1
    check keepalived_active_before systemctl is-active --quiet keepalived.service || return 1
    check vrrp_state_regular test -f "$vrrp_state" || return 1
    check vrrp_state_not_symlink test ! -L "$vrrp_state" || return 1
    check vrrp_state_exact test "$(sed -n '1p' "$vrrp_state")" = "$expected_vrrp" || return 1
    check physical_ipv4_owned_before test "$(address_count -4 "$physical_ipv4_cidr")" -eq 1 || return 1
    check physical_ipv6_owned_before test "$(address_count -6 "$physical_ipv6_cidr")" -eq 1 || return 1
    check caddy_ipv4_count_before test "$(address_count -4 "$caddy_ipv4_cidr")" -eq "$expected_vip_count" || return 1
    check caddy_ipv6_count_before test "$(address_count -6 "$caddy_ipv6_cidr")" -eq "$expected_vip_count" || return 1
    check dns_ipv4_count_before test "$(address_count -4 "$dns_ipv4_cidr")" -eq "$expected_vip_count" || return 1
    check dns_ipv6_count_before test "$(address_count -6 "$dns_ipv6_cidr")" -eq "$expected_vip_count" || return 1
    action25_before_state=$(state_snapshot | sha256sum | awk '{ print $1 }') || return 1
    check before_state_hash_valid valid_sha256 "$action25_before_state" || return 1

    while IFS='|' read -r action25_probe_label action25_probe_fqdn action25_probe_resolve action25_probe_remote; do
        probe_endpoint "$action25_probe_label" "$action25_probe_fqdn" \
            "$action25_probe_resolve" "$action25_probe_remote" || return 1
    done < <(endpoint_specs)

    check caddy_active_after systemctl is-active --quiet caddy.service || return 1
    check lighttpd_active_after systemctl is-active --quiet lighttpd.service || return 1
    check keepalived_active_after systemctl is-active --quiet keepalived.service || return 1
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
    action25_after_state=$(state_snapshot | sha256sum | awk '{ print $1 }') || return 1
    check after_state_hash_valid valid_sha256 "$action25_after_state" || return 1
    check state_unchanged test "$action25_before_state" = "$action25_after_state" || return 1
    # conditional-validator-explicit-failures-end

    printf '%s_%s_value_before_state_sha256=%s\n' "$prefix" "$node_token" "$action25_before_state"
    printf '%s_%s_value_after_state_sha256=%s\n' "$prefix" "$node_token" "$action25_after_state"
    printf '%s_%s_value_local_zone_sha256=%s\n' "$prefix" "$node_token" "$accepted_local_zone_sha256"
    printf '%s_%s_value_vrrp_state=%s\n' "$prefix" "$node_token" "$expected_vrrp"
    printf '%s_%s_check_count=%s\n' "$prefix" "$node_token" "$(expected_checks | wc -l)"
    printf '%s_%s_endpoint_count=6\n' "$prefix" "$node_token"
    printf '%s_%s_filesystem_mutation=false\n' "$prefix" "$node_token"
    printf '%s_%s_service_mutation=false\n' "$prefix" "$node_token"
    printf '%s_%s_dns_mutation=false\n' "$prefix" "$node_token"
    printf '%s_%s_peer_ssh=false\n' "$prefix" "$node_token"
    printf '%s_%s_remote_complete=true\n' "$prefix" "$node_token"
}
self_test() {
    local action25_self_state=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

    while IFS= read -r action25_self_label; do
        printf '%s_%s_check_%s=true\n' "$prefix" "$node_token" "$action25_self_label"
    done < <(expected_checks)
    while IFS='|' read -r action25_self_endpoint action25_self_fqdn _ action25_self_remote; do
        printf '%s_%s_observed_%s_command_status=0\n' "$prefix" "$node_token" "$action25_self_endpoint"
        printf '%s_%s_observed_%s_output_classification=bounded_safe\n' "$prefix" "$node_token" "$action25_self_endpoint"
        printf '%s_%s_observed_%s_output_begin\n' "$prefix" "$node_token" "$action25_self_endpoint"
        printf '<html><title>Pi-hole</title></html>\n'
        printf 'action25-metadata|200|https://%s/admin/|%s\n' "$action25_self_fqdn" "$action25_self_remote"
        printf '%s_%s_observed_%s_output_end\n' "$prefix" "$node_token" "$action25_self_endpoint"
        printf '%s_%s_observed_%s_http_code=200\n' "$prefix" "$node_token" "$action25_self_endpoint"
        printf '%s_%s_observed_%s_effective_url=https://%s/admin/\n' "$prefix" "$node_token" "$action25_self_endpoint" "$action25_self_fqdn"
        printf '%s_%s_observed_%s_remote_ip=%s\n' "$prefix" "$node_token" "$action25_self_endpoint" "$action25_self_remote"
        printf '%s_%s_observed_%s_body_bytes=128\n' "$prefix" "$node_token" "$action25_self_endpoint"
        printf '%s_%s_observed_%s_body_sha256=%s\n' "$prefix" "$node_token" "$action25_self_endpoint" "$action25_self_state"
        printf '%s_%s_observed_%s_body_classification=bounded_safe\n' "$prefix" "$node_token" "$action25_self_endpoint"
        printf '%s_%s_observed_%s_body_pihole_marker=true\n' "$prefix" "$node_token" "$action25_self_endpoint"
        printf '%s_%s_value_%s_http_code=200\n' "$prefix" "$node_token" "$action25_self_endpoint"
        printf '%s_%s_value_%s_effective_url=https://%s/admin/\n' "$prefix" "$node_token" "$action25_self_endpoint" "$action25_self_fqdn"
        printf '%s_%s_value_%s_remote_ip=%s\n' "$prefix" "$node_token" "$action25_self_endpoint" "$action25_self_remote"
        printf '%s_%s_value_%s_body_bytes=128\n' "$prefix" "$node_token" "$action25_self_endpoint"
        printf '%s_%s_value_%s_body_sha256=%s\n' "$prefix" "$node_token" "$action25_self_endpoint" "$action25_self_state"
    done < <(endpoint_specs)
    printf '%s_%s_value_before_state_sha256=%s\n' "$prefix" "$node_token" "$action25_self_state"
    printf '%s_%s_value_after_state_sha256=%s\n' "$prefix" "$node_token" "$action25_self_state"
    printf '%s_%s_value_local_zone_sha256=%s\n' "$prefix" "$node_token" "$accepted_local_zone_sha256"
    printf '%s_%s_value_vrrp_state=%s\n' "$prefix" "$node_token" "$expected_vrrp"
    printf '%s_%s_check_count=%s\n' "$prefix" "$node_token" "$(expected_checks | wc -l)"
    printf '%s_%s_endpoint_count=6\n' "$prefix" "$node_token"
    printf '%s_%s_filesystem_mutation=false\n' "$prefix" "$node_token"
    printf '%s_%s_service_mutation=false\n' "$prefix" "$node_token"
    printf '%s_%s_dns_mutation=false\n' "$prefix" "$node_token"
    printf '%s_%s_peer_ssh=false\n' "$prefix" "$node_token"
    printf '%s_%s_remote_complete=true\n' "$prefix" "$node_token"
}

case "${1:-}" in
    --expected-checks)
        configure_node "${2:-}" || exit $?
        expected_checks
        ;;
    --self-test-node)
        configure_node "${2:-}" || exit $?
        self_test
        ;;
    --probe-test)
        configure_node "${2:-}" || exit $?
        while IFS='|' read -r action25_test_label action25_test_fqdn action25_test_resolve action25_test_remote; do
            if [[ "$action25_test_label" == "${3:-}" ]]; then
                probe_endpoint "$action25_test_label" "$action25_test_fqdn" \
                    "$action25_test_resolve" "$action25_test_remote"
                exit $?
            fi
        done < <(endpoint_specs)
        exit 64
        ;;
    --node)
        configure_node "${2:-}" || exit $?
        run_inspection
        ;;
    *) exit 64 ;;
esac
