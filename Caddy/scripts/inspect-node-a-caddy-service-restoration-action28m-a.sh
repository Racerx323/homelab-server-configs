#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28m_a
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly caddy_fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly backup_directory=/var/backups/caddy-ha/action28m-node-a-caddy-service-restoration
readonly retired_main_sha256=6162cfb9d83f7e524db1df6a3b041ced90a7639fceaf28eacf713270c2a66a65
readonly baseline_main_sha256=8fc9dcf8e079b7131f86a58038ae5543804a5158a02d53a4614452de212ce47c
readonly fragment_sha256=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
readonly include_line='include /etc/keepalived/conf.d/caddy-ha.conf'
readonly interface=eth0

expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact main_regular main_not_symlink \
        main_metadata main_hash_retired main_include_absent fragment_regular \
        fragment_not_symlink fragment_metadata fragment_hash_exact backup_directory_exact \
        backup_main_hash_exact backup_fragment_hash_exact backup_manifest_exact \
        transaction_residue_absent keepalived_active_before lighttpd_active_before \
        caddy_active_before ipv4_query_before_status_zero ipv6_query_before_status_zero \
        dns_ipv4_owned_before dns_ipv6_owned_before caddy_ipv4_absent_before \
        caddy_ipv6_absent_before localhost_health_status_204 node_a_ipv4_ui_status_200 \
        node_a_ipv6_ui_status_200 keepalived_active_after lighttpd_active_after \
        caddy_active_after ipv4_query_after_status_zero ipv6_query_after_status_zero \
        dns_ipv4_owned_after dns_ipv6_owned_after caddy_ipv4_absent_after \
        caddy_ipv6_absent_after state_unchanged
}

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
address_query() { ip -o "-$1" address show dev "$interface"; }
address_count() {
    local action28ma_family=$1
    local action28ma_cidr=$2

    address_query "$action28ma_family" |
        awk -v expected="$action28ma_cidr" '$4 == expected { count++ } END { print count + 0 }'
}
check() {
    local action28ma_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28ma_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28ma_label"
    return 1
}
https_status() {
    local action28ma_fqdn=$1
    local action28ma_address=$2
    local action28ma_path=$3

    curl --noproxy '*' --insecure --silent --show-error --location --max-redirs 3 \
        --proto-redir '=https' --connect-timeout 3 --max-time 10 \
        --resolve "${action28ma_fqdn}:443:${action28ma_address}" \
        --output /dev/null --write-out '%{http_code}' \
        "https://${action28ma_fqdn}${action28ma_path}"
}
snapshot() {
    printf 'main=%s\n' "$(file_hash "$main_configuration")"
    printf 'fragment=%s\n' "$(file_hash "$caddy_fragment")"
    printf 'services=%s|%s|%s\n' "$(systemctl is-active keepalived.service)" \
        "$(systemctl is-active lighttpd.service)" "$(systemctl is-active caddy.service)"
    printf 'addresses=%s|%s|%s|%s\n' \
        "$(address_count 4 10.1.0.55/22)" \
        "$(address_count 6 fd36:5aa8:6971:1::55/128)" \
        "$(address_count 4 10.1.0.56/22)" \
        "$(address_count 6 fd36:5aa8:6971:1::56/128)"
}
require() {
    local action28ma_required_label=$1

    shift
    check "$action28ma_required_label" "$@" || {
        printf '%s_first_failure=%s\n' "$prefix" "$action28ma_required_label"
        exit 1
    }
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]]
        expected_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        labels=$(expected_checks)
        [[ "$(printf '%s\n' "$labels" | wc -l)" -eq "$(printf '%s\n' "$labels" | LC_ALL=C sort -u | wc -l)" ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") ;;
    *) exit 64 ;;
esac

require identity_root test "$(id -u)" -eq 0
require working_directory_root test "$(pwd -P)" = /
require hostname_exact test "$(hostname)" = j1-svpihole0
require main_regular test -f "$main_configuration"
require main_not_symlink test ! -L "$main_configuration"
require main_metadata test "$(stat -c '%U:%G:%a' "$main_configuration")" = root:root:644
require main_hash_retired test "$(file_hash "$main_configuration")" = "$retired_main_sha256"
require main_include_absent test "$(grep -Fxc "$include_line" "$main_configuration" || true)" -eq 0
require fragment_regular test -f "$caddy_fragment"
require fragment_not_symlink test ! -L "$caddy_fragment"
require fragment_metadata test "$(stat -c '%U:%G:%a' "$caddy_fragment")" = root:root:644
require fragment_hash_exact test "$(file_hash "$caddy_fragment")" = "$fragment_sha256"
require backup_directory_exact test "$(stat -c '%U:%G:%a' "$backup_directory")" = root:root:700
require backup_main_hash_exact test "$(file_hash "$backup_directory/keepalived.conf")" = "$baseline_main_sha256"
require backup_fragment_hash_exact test "$(file_hash "$backup_directory/caddy-ha.conf")" = "$fragment_sha256"
require backup_manifest_exact grep -Fqx "retired_main_sha256=$retired_main_sha256" "$backup_directory/manifest"
require transaction_residue_absent test -z "$(find /run -maxdepth 1 -name 'caddy-action28m-*' -print -quit 2>/dev/null)"
before_state=$(snapshot)
before_hash=$(printf '%s\n' "$before_state" | sha256sum | awk '{ print $1 }')
require keepalived_active_before systemctl is-active --quiet keepalived.service
require lighttpd_active_before systemctl is-active --quiet lighttpd.service
require caddy_active_before systemctl is-active --quiet caddy.service
ipv4_status=0
address_query 4 >/dev/null 2>&1 || ipv4_status=$?
require ipv4_query_before_status_zero test "$ipv4_status" -eq 0
ipv6_status=0
address_query 6 >/dev/null 2>&1 || ipv6_status=$?
require ipv6_query_before_status_zero test "$ipv6_status" -eq 0
require dns_ipv4_owned_before test "$(address_count 4 10.1.0.55/22)" -eq 1
require dns_ipv6_owned_before test "$(address_count 6 fd36:5aa8:6971:1::55/128)" -eq 1
require caddy_ipv4_absent_before test "$(address_count 4 10.1.0.56/22)" -eq 0
require caddy_ipv6_absent_before test "$(address_count 6 fd36:5aa8:6971:1::56/128)" -eq 0
require localhost_health_status_204 test "$(https_status localhost 127.0.0.1 /)" = 204
require node_a_ipv4_ui_status_200 test "$(https_status pihole0.local.theama.co 10.1.0.53 /admin/)" = 200
require node_a_ipv6_ui_status_200 test \
    "$(https_status pihole0.local.theama.co '[fd36:5aa8:6971:1::53]' /admin/)" = 200
require keepalived_active_after systemctl is-active --quiet keepalived.service
require lighttpd_active_after systemctl is-active --quiet lighttpd.service
require caddy_active_after systemctl is-active --quiet caddy.service
ipv4_status=0
address_query 4 >/dev/null 2>&1 || ipv4_status=$?
require ipv4_query_after_status_zero test "$ipv4_status" -eq 0
ipv6_status=0
address_query 6 >/dev/null 2>&1 || ipv6_status=$?
require ipv6_query_after_status_zero test "$ipv6_status" -eq 0
require dns_ipv4_owned_after test "$(address_count 4 10.1.0.55/22)" -eq 1
require dns_ipv6_owned_after test "$(address_count 6 fd36:5aa8:6971:1::55/128)" -eq 1
require caddy_ipv4_absent_after test "$(address_count 4 10.1.0.56/22)" -eq 0
require caddy_ipv6_absent_after test "$(address_count 6 fd36:5aa8:6971:1::56/128)" -eq 0
after_state=$(snapshot)
after_hash=$(printf '%s\n' "$after_state" | sha256sum | awk '{ print $1 }')
require state_unchanged test "$before_hash" = "$after_hash"
printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
printf '%s_first_failure=none\n' "$prefix"
printf '%s_value_state_sha256=%s\n' "$prefix" "$after_hash"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_mutation=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
