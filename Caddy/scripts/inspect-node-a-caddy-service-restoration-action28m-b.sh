#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28m_b
readonly production_retired_main_sha256=6162cfb9d83f7e524db1df6a3b041ced90a7639fceaf28eacf713270c2a66a65
readonly production_baseline_main_sha256=8fc9dcf8e079b7131f86a58038ae5543804a5158a02d53a4614452de212ce47c
readonly production_fragment_sha256=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
readonly include_line='include /etc/keepalived/conf.d/caddy-ha.conf'
readonly interface=eth0
fixture_root=

expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact main_regular main_not_symlink \
        main_metadata main_hash_retired main_include_absent fragment_regular \
        fragment_not_symlink fragment_metadata fragment_hash_exact backup_directory_metadata \
        backup_main_hash_exact backup_fragment_hash_exact backup_manifest_metadata \
        backup_manifest_action_exact backup_manifest_baseline_exact \
        backup_manifest_fragment_exact backup_manifest_retired_exact \
        backup_entries_exact transaction_residue_absent keepalived_active_before \
        lighttpd_active_before caddy_active_before ipv4_query_before_status_zero \
        ipv6_query_before_status_zero dns_ipv4_owned_before dns_ipv6_owned_before \
        caddy_ipv4_absent_before caddy_ipv6_absent_before localhost_https_status_zero \
        localhost_health_status_204 node_a_ipv4_https_status_zero \
        node_a_ipv4_ui_status_200 node_a_ipv6_https_status_zero \
        node_a_ipv6_ui_status_200 keepalived_active_after lighttpd_active_after \
        caddy_active_after ipv4_query_after_status_zero ipv6_query_after_status_zero \
        dns_ipv4_owned_after dns_ipv6_owned_after caddy_ipv4_absent_after \
        caddy_ipv6_absent_after state_unchanged
}

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
rooted() {
    if [[ -n "$fixture_root" ]]; then
        printf '%s%s\n' "$fixture_root" "$1"
    else
        printf '%s\n' "$1"
    fi
}
observed_uid() {
    if [[ -n "$fixture_root" ]]; then
        printf '0\n'
    else
        id -u
    fi
}
observed_hostname() {
    if [[ -n "$fixture_root" ]]; then
        printf 'j1-svpihole0\n'
    else
        hostname
    fi
}
file_metadata() {
    local action28mb_metadata_path=$1
    local action28mb_metadata_mode

    if [[ -n "$fixture_root" ]]; then
        action28mb_metadata_mode=$(stat -c '%a' "$action28mb_metadata_path") || return 1
        printf 'root:root:%s\n' "$action28mb_metadata_mode"
    else
        stat -c '%U:%G:%a' "$action28mb_metadata_path"
    fi
}
service_active() {
    local action28mb_service=$1

    if [[ -n "$fixture_root" ]]; then
        grep -Fqx "$action28mb_service=active" "$fixture_root/state/services"
    else
        systemctl is-active --quiet "$action28mb_service"
    fi
}
address_query() {
    local action28mb_family=$1

    if [[ -n "$fixture_root" ]]; then
        cat "$fixture_root/state/ipv${action28mb_family}"
    else
        ip -o "-${action28mb_family}" address show dev "$interface"
    fi
}
address_count() {
    local action28mb_family=$1
    local action28mb_cidr=$2

    address_query "$action28mb_family" |
        awk -v expected="$action28mb_cidr" '$4 == expected { count++ } END { print count + 0 }'
}
https_probe() {
    local action28mb_fqdn=$1
    local action28mb_address=$2
    local action28mb_path=$3
    local action28mb_code
    local action28mb_status=0

    if [[ -n "$fixture_root" ]]; then
        awk -F '|' -v fqdn="$action28mb_fqdn" -v address="$action28mb_address" \
            -v path="$action28mb_path" \
            '$1 == fqdn && $2 == address && $3 == path { print $4 "|" $5; found = 1 }
             END { if (!found) exit 44 }' "$fixture_root/state/https"
        return
    fi
    action28mb_code=$(curl --noproxy '*' --insecure --silent --show-error --location \
        --max-redirs 3 --proto-redir '=https' --connect-timeout 3 --max-time 10 \
        --resolve "${action28mb_fqdn}:443:${action28mb_address}" \
        --output /dev/null --write-out '%{http_code}' \
        "https://${action28mb_fqdn}${action28mb_path}") || action28mb_status=$?
    printf '%s|%s\n' "$action28mb_status" "$action28mb_code"
}
snapshot() {
    local action28mb_main=$1
    local action28mb_fragment=$2

    printf 'main=%s\n' "$(file_hash "$action28mb_main")" || return 1
    printf 'fragment=%s\n' "$(file_hash "$action28mb_fragment")" || return 1
    printf 'services=%s|%s|%s\n' \
        "$(service_active keepalived.service && printf active || printf inactive)" \
        "$(service_active lighttpd.service && printf active || printf inactive)" \
        "$(service_active caddy.service && printf active || printf inactive)" || return 1
    printf 'addresses=%s|%s|%s|%s\n' \
        "$(address_count 4 10.1.0.55/22)" \
        "$(address_count 6 fd36:5aa8:6971:1::55/128)" \
        "$(address_count 4 10.1.0.56/22)" \
        "$(address_count 6 fd36:5aa8:6971:1::56/128)" || return 1
}
check() {
    local action28mb_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28mb_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28mb_label"
    return 1
}
require() {
    local action28mb_required_label=$1

    shift
    check "$action28mb_required_label" "$@" || {
        printf '%s_first_failure=%s\n' "$prefix" "$action28mb_required_label"
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
    --fixture-root)
        [[ "${CADDY_ACTION28MB_TEST_MODE:-}" = 1 && $# -eq 2 && -d "$2" ]]
        fixture_root=$2
        ;;
    "") ;;
    *) exit 64 ;;
esac

main_configuration=$(rooted /etc/keepalived/keepalived.conf)
caddy_fragment=$(rooted /etc/keepalived/conf.d/caddy-ha.conf)
backup_directory=$(rooted /var/backups/caddy-ha/action28m-node-a-caddy-service-restoration)
run_root=$(rooted /run)
readonly main_configuration caddy_fragment backup_directory run_root
if [[ -n "$fixture_root" ]]; then
    retired_main_sha256=${CADDY_ACTION28MB_RETIRED_MAIN_SHA256:?}
    baseline_main_sha256=${CADDY_ACTION28MB_BASELINE_MAIN_SHA256:?}
    fragment_sha256=${CADDY_ACTION28MB_FRAGMENT_SHA256:?}
else
    retired_main_sha256=$production_retired_main_sha256
    baseline_main_sha256=$production_baseline_main_sha256
    fragment_sha256=$production_fragment_sha256
fi
readonly retired_main_sha256 baseline_main_sha256 fragment_sha256

printf '%s_value_expected_main_sha256=%s\n' "$prefix" "$retired_main_sha256"
printf '%s_value_observed_main_sha256=%s\n' "$prefix" "$(file_hash "$main_configuration")"
printf '%s_value_expected_fragment_sha256=%s\n' "$prefix" "$fragment_sha256"
printf '%s_value_observed_fragment_sha256=%s\n' "$prefix" "$(file_hash "$caddy_fragment")"
printf '%s_value_expected_backup_main_sha256=%s\n' "$prefix" "$baseline_main_sha256"
printf '%s_value_observed_backup_main_sha256=%s\n' "$prefix" \
    "$(file_hash "$backup_directory/keepalived.conf")"
printf '%s_value_observed_backup_fragment_sha256=%s\n' "$prefix" \
    "$(file_hash "$backup_directory/caddy-ha.conf")"

require identity_root test "$(observed_uid)" -eq 0
require working_directory_root test "$(pwd -P)" = /
require hostname_exact test "$(observed_hostname)" = j1-svpihole0
require main_regular test -f "$main_configuration"
require main_not_symlink test ! -L "$main_configuration"
require main_metadata test "$(file_metadata "$main_configuration")" = root:root:644
require main_hash_retired test "$(file_hash "$main_configuration")" = "$retired_main_sha256"
require main_include_absent test "$(grep -Fxc "$include_line" "$main_configuration" || true)" -eq 0
require fragment_regular test -f "$caddy_fragment"
require fragment_not_symlink test ! -L "$caddy_fragment"
require fragment_metadata test "$(file_metadata "$caddy_fragment")" = root:root:644
require fragment_hash_exact test "$(file_hash "$caddy_fragment")" = "$fragment_sha256"
require backup_directory_metadata test "$(file_metadata "$backup_directory")" = root:root:700
require backup_main_hash_exact test "$(file_hash "$backup_directory/keepalived.conf")" = "$baseline_main_sha256"
require backup_fragment_hash_exact test "$(file_hash "$backup_directory/caddy-ha.conf")" = "$fragment_sha256"
require backup_manifest_metadata test "$(file_metadata "$backup_directory/manifest")" = root:root:600
require backup_manifest_action_exact grep -Fqx 'action=28m' "$backup_directory/manifest"
require backup_manifest_baseline_exact grep -Fqx \
    "baseline_main_sha256=$baseline_main_sha256" "$backup_directory/manifest"
require backup_manifest_fragment_exact grep -Fqx \
    "fragment_sha256=$fragment_sha256" "$backup_directory/manifest"
require backup_manifest_retired_exact grep -Fqx \
    "retired_main_sha256=$retired_main_sha256" "$backup_directory/manifest"
require backup_entries_exact test \
    "$(find "$backup_directory" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)" = \
    $'caddy-ha.conf\nkeepalived.conf\nmanifest'
require transaction_residue_absent test -z \
    "$(find "$run_root" -maxdepth 1 -name 'caddy-action28m-*' -print -quit 2>/dev/null)"

before_state=$(snapshot "$main_configuration" "$caddy_fragment")
before_hash=$(printf '%s\n' "$before_state" | sha256sum | awk '{ print $1 }')
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$before_hash"
require keepalived_active_before service_active keepalived.service
require lighttpd_active_before service_active lighttpd.service
require caddy_active_before service_active caddy.service
ipv4_status=0
address_query 4 >/dev/null 2>&1 || ipv4_status=$?
printf '%s_value_ipv4_query_before_status=%s\n' "$prefix" "$ipv4_status"
require ipv4_query_before_status_zero test "$ipv4_status" -eq 0
ipv6_status=0
address_query 6 >/dev/null 2>&1 || ipv6_status=$?
printf '%s_value_ipv6_query_before_status=%s\n' "$prefix" "$ipv6_status"
require ipv6_query_before_status_zero test "$ipv6_status" -eq 0
require dns_ipv4_owned_before test "$(address_count 4 10.1.0.55/22)" -eq 1
require dns_ipv6_owned_before test "$(address_count 6 fd36:5aa8:6971:1::55/128)" -eq 1
require caddy_ipv4_absent_before test "$(address_count 4 10.1.0.56/22)" -eq 0
require caddy_ipv6_absent_before test "$(address_count 6 fd36:5aa8:6971:1::56/128)" -eq 0

localhost_result=$(https_probe localhost 127.0.0.1 /)
localhost_status=${localhost_result%%|*}
localhost_code=${localhost_result#*|}
printf '%s_value_localhost_https_status=%s\n' "$prefix" "$localhost_status"
printf '%s_value_localhost_http_code=%s\n' "$prefix" "$localhost_code"
require localhost_https_status_zero test "$localhost_status" -eq 0
require localhost_health_status_204 test "$localhost_code" = 204
node_a_ipv4_result=$(https_probe pihole0.local.theama.co 10.1.0.53 /admin/)
node_a_ipv4_status=${node_a_ipv4_result%%|*}
node_a_ipv4_code=${node_a_ipv4_result#*|}
printf '%s_value_node_a_ipv4_https_status=%s\n' "$prefix" "$node_a_ipv4_status"
printf '%s_value_node_a_ipv4_http_code=%s\n' "$prefix" "$node_a_ipv4_code"
require node_a_ipv4_https_status_zero test "$node_a_ipv4_status" -eq 0
require node_a_ipv4_ui_status_200 test "$node_a_ipv4_code" = 200
node_a_ipv6_result=$(https_probe pihole0.local.theama.co '[fd36:5aa8:6971:1::53]' /admin/)
node_a_ipv6_status=${node_a_ipv6_result%%|*}
node_a_ipv6_code=${node_a_ipv6_result#*|}
printf '%s_value_node_a_ipv6_https_status=%s\n' "$prefix" "$node_a_ipv6_status"
printf '%s_value_node_a_ipv6_http_code=%s\n' "$prefix" "$node_a_ipv6_code"
require node_a_ipv6_https_status_zero test "$node_a_ipv6_status" -eq 0
require node_a_ipv6_ui_status_200 test "$node_a_ipv6_code" = 200

require keepalived_active_after service_active keepalived.service
require lighttpd_active_after service_active lighttpd.service
require caddy_active_after service_active caddy.service
ipv4_status=0
address_query 4 >/dev/null 2>&1 || ipv4_status=$?
printf '%s_value_ipv4_query_after_status=%s\n' "$prefix" "$ipv4_status"
require ipv4_query_after_status_zero test "$ipv4_status" -eq 0
ipv6_status=0
address_query 6 >/dev/null 2>&1 || ipv6_status=$?
printf '%s_value_ipv6_query_after_status=%s\n' "$prefix" "$ipv6_status"
require ipv6_query_after_status_zero test "$ipv6_status" -eq 0
require dns_ipv4_owned_after test "$(address_count 4 10.1.0.55/22)" -eq 1
require dns_ipv6_owned_after test "$(address_count 6 fd36:5aa8:6971:1::55/128)" -eq 1
require caddy_ipv4_absent_after test "$(address_count 4 10.1.0.56/22)" -eq 0
require caddy_ipv6_absent_after test "$(address_count 6 fd36:5aa8:6971:1::56/128)" -eq 0
after_state=$(snapshot "$main_configuration" "$caddy_fragment")
after_hash=$(printf '%s\n' "$after_state" | sha256sum | awk '{ print $1 }')
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$after_hash"
require state_unchanged test "$before_hash" = "$after_hash"
printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
printf '%s_first_failure=none\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_mutation=false\n' "$prefix"
printf '%s_action_28m_rerun=false\n' "$prefix"
printf '%s_action_28m_a_rerun=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
