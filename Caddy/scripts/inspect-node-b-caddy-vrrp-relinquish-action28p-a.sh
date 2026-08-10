#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28p_a_node_b
readonly production_main_sha256=9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148
readonly production_fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
readonly production_baseline_main_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
readonly include_line='include /etc/keepalived/conf.d/caddy-ha.conf'
readonly interface=eth0
readonly caddy_ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/110/IPv4
readonly caddy_ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/111/IPv6
readonly maximum_stream_bytes=131072
readonly maximum_stream_lines=1024
fixture_root=

expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact main_regular main_not_symlink \
        main_metadata main_hash_exact include_absent fragment_regular fragment_not_symlink \
        fragment_metadata fragment_hash_exact backup_directory_metadata backup_main_regular \
        backup_main_metadata backup_main_hash_exact backup_fragment_regular \
        backup_fragment_metadata backup_fragment_hash_exact backup_manifest_regular \
        backup_manifest_metadata backup_manifest_line_count backup_manifest_action \
        backup_manifest_baseline backup_manifest_fragment backup_manifest_retired \
        backup_entry_count transaction_residue_absent \
        keepalived_active_before lighttpd_active_before caddy_active_before_sample_1 \
        caddy_active_before_sample_2 caddy_active_before_sample_3 \
        caddy_active_before_sample_4 caddy_active_before_sample_5 \
        ipv4_query_before_status_zero ipv6_query_before_status_zero \
        dns_ipv4_absent_before dns_ipv6_absent_before caddy_ipv4_absent_before \
        caddy_ipv6_absent_before localhost_health_status_zero localhost_health_status_204 \
        node_b_ipv4_https_status_zero node_b_ipv4_ui_status_200 \
        node_b_ipv6_https_status_zero node_b_ipv6_ui_status_200 \
        keepalived_active_after lighttpd_active_after caddy_active_after_sample_1 \
        caddy_active_after_sample_2 caddy_active_after_sample_3 \
        caddy_active_after_sample_4 caddy_active_after_sample_5 \
        ipv4_query_after_status_zero ipv6_query_after_status_zero \
        dns_ipv4_absent_after dns_ipv6_absent_after caddy_ipv4_absent_after \
        caddy_ipv6_absent_after dbus_tree_status_zero dbus_tree_safe dbus_tree_stderr_safe \
        caddy_ipv4_object_absent caddy_ipv6_object_absent main_still_exact \
        fragment_still_exact backup_still_exact state_unchanged
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
    if [[ -n "$fixture_root" ]]; then printf '0\n'; else id -u; fi
}
observed_hostname() {
    if [[ -n "$fixture_root" ]]; then printf 'j1-svpihole00\n'; else hostname; fi
}
file_metadata() {
    local action28pa_metadata_path=$1
    local action28pa_metadata_mode

    if [[ -n "$fixture_root" ]]; then
        action28pa_metadata_mode=$(stat -c '%a' "$action28pa_metadata_path") || return 1
        printf 'root:root:%s\n' "$action28pa_metadata_mode"
    else
        stat -c '%U:%G:%a' "$action28pa_metadata_path"
    fi
}
directory_metadata() {
    local action28pa_directory_path=$1
    local action28pa_directory_mode

    if [[ -n "$fixture_root" ]]; then
        action28pa_directory_mode=$(stat -c '%a' "$action28pa_directory_path") || return 1
        printf 'root:root:%s\n' "$action28pa_directory_mode"
    else
        stat -c '%U:%G:%a' "$action28pa_directory_path"
    fi
}
service_active() {
    local action28pa_service=$1

    if [[ -n "$fixture_root" ]]; then
        grep -Fqx "$action28pa_service=active" "$fixture_root/state/services"
    else
        systemctl is-active --quiet "$action28pa_service"
    fi
}
address_query() {
    local action28pa_family=$1

    if [[ -n "$fixture_root" ]]; then
        cat "$fixture_root/state/ipv${action28pa_family}"
    else
        ip -o "-${action28pa_family}" address show dev "$interface"
    fi
}
address_count() {
    local action28pa_family=$1
    local action28pa_cidr=$2

    address_query "$action28pa_family" |
        awk -v expected="$action28pa_cidr" '$4 == expected { count++ } END { print count + 0 }'
}
https_probe() {
    local action28pa_fqdn=$1
    local action28pa_address=$2
    local action28pa_path=$3
    local action28pa_code
    local action28pa_status=0

    if [[ -n "$fixture_root" ]]; then
        awk -F '|' -v fqdn="$action28pa_fqdn" -v address="$action28pa_address" \
            -v path="$action28pa_path" \
            '$1 == fqdn && $2 == address && $3 == path { print $4 "|" $5; found = 1 }
             END { if (!found) exit 44 }' "$fixture_root/state/https"
        return
    fi
    action28pa_code=$(curl --noproxy '*' --insecure --silent --show-error --location \
        --max-redirs 3 --proto-redir '=https' --connect-timeout 3 --max-time 10 \
        --resolve "${action28pa_fqdn}:443:${action28pa_address}" \
        --output /dev/null --write-out '%{http_code}' \
        "https://${action28pa_fqdn}${action28pa_path}") || action28pa_status=$?
    printf '%s|%s\n' "$action28pa_status" "$action28pa_code"
}
snapshot() {
    local action28pa_main=$1
    local action28pa_fragment=$2
    local action28pa_backup_main=$3
    local action28pa_backup_fragment=$4
    local action28pa_backup_manifest=$5

    printf 'main=%s\n' "$(file_hash "$action28pa_main")" || return 1
    printf 'fragment=%s\n' "$(file_hash "$action28pa_fragment")" || return 1
    printf 'backup=%s|%s|%s\n' \
        "$(file_hash "$action28pa_backup_main")" \
        "$(file_hash "$action28pa_backup_fragment")" \
        "$(file_hash "$action28pa_backup_manifest")" || return 1
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
safe_stream() {
    local action28pa_stream=$1

    [[ "$(wc -c <"$action28pa_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(awk 'END { print NR }' "$action28pa_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28pa_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:|WEBPASSWORD' \
        "$action28pa_stream" || return 1
}
emit_stream() {
    local action28pa_stream_label=$1
    local action28pa_stream=$2

    printf '%s_value_%s_bytes=%s\n' "$prefix" "$action28pa_stream_label" "$(wc -c <"$action28pa_stream")"
    printf '%s_value_%s_lines=%s\n' "$prefix" "$action28pa_stream_label" "$(awk 'END { print NR }' "$action28pa_stream")"
    printf '%s_value_%s_sha256=%s\n' "$prefix" "$action28pa_stream_label" "$(file_hash "$action28pa_stream")"
    if [[ -s "$action28pa_stream" ]]; then
        printf '%s_value_%s_begin\n' "$prefix" "$action28pa_stream_label"
        cat "$action28pa_stream"
        printf '%s_value_%s_end\n' "$prefix" "$action28pa_stream_label"
    else
        printf '%s_value_%s_content=empty\n' "$prefix" "$action28pa_stream_label"
    fi
}
check() {
    local action28pa_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28pa_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28pa_label"
    return 1
}
require() {
    local action28pa_required_label=$1

    shift
    check "$action28pa_required_label" "$@" || {
        printf '%s_first_failure=%s\n' "$prefix" "$action28pa_required_label"
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
        [[ "${CADDY_ACTION28PA_TEST_MODE:-}" = 1 && $# -eq 2 && -d "$2" ]]
        fixture_root=$2
        ;;
    "") ;;
    *) exit 64 ;;
esac

main_configuration=$(rooted /etc/keepalived/keepalived.conf)
caddy_fragment=$(rooted /etc/keepalived/conf.d/caddy-ha.conf)
backup_directory=$(rooted /var/backups/caddy-ha/action28p-node-b-caddy-vrrp-relinquish)
backup_main=$backup_directory/keepalived.conf
backup_fragment=$backup_directory/caddy-ha.conf
backup_manifest=$backup_directory/manifest
run_root=$(rooted /run)
readonly main_configuration caddy_fragment backup_directory backup_main backup_fragment \
    backup_manifest run_root
if [[ -n "$fixture_root" ]]; then
    main_sha256=${CADDY_ACTION28PA_MAIN_SHA256:?}
    fragment_sha256=${CADDY_ACTION28PA_FRAGMENT_SHA256:?}
else
    main_sha256=$production_main_sha256
    fragment_sha256=$production_fragment_sha256
fi
readonly main_sha256 fragment_sha256

printf '%s_value_expected_main_sha256=%s\n' "$prefix" "$main_sha256"
printf '%s_value_observed_main_sha256=%s\n' "$prefix" "$(file_hash "$main_configuration")"
printf '%s_value_expected_fragment_sha256=%s\n' "$prefix" "$fragment_sha256"
printf '%s_value_observed_fragment_sha256=%s\n' "$prefix" "$(file_hash "$caddy_fragment")"
printf '%s_value_expected_backup_main_sha256=%s\n' "$prefix" "$production_baseline_main_sha256"
printf '%s_value_observed_backup_main_sha256=%s\n' "$prefix" "$(file_hash "$backup_main")"

require identity_root test "$(observed_uid)" -eq 0
require working_directory_root test "$(pwd -P)" = /
require hostname_exact test "$(observed_hostname)" = j1-svpihole00
require main_regular test -f "$main_configuration"
require main_not_symlink test ! -L "$main_configuration"
require main_metadata test "$(file_metadata "$main_configuration")" = root:root:644
require main_hash_exact test "$(file_hash "$main_configuration")" = "$main_sha256"
require include_absent test "$(grep -Fxc "$include_line" "$main_configuration" || true)" -eq 0
require fragment_regular test -f "$caddy_fragment"
require fragment_not_symlink test ! -L "$caddy_fragment"
require fragment_metadata test "$(file_metadata "$caddy_fragment")" = root:root:644
require fragment_hash_exact test "$(file_hash "$caddy_fragment")" = "$fragment_sha256"
require backup_directory_metadata test "$(directory_metadata "$backup_directory")" = root:root:700
require backup_main_regular test -f "$backup_main"
require backup_main_metadata test "$(file_metadata "$backup_main")" = root:root:600
require backup_main_hash_exact test "$(file_hash "$backup_main")" = "$production_baseline_main_sha256"
require backup_fragment_regular test -f "$backup_fragment"
require backup_fragment_metadata test "$(file_metadata "$backup_fragment")" = root:root:600
require backup_fragment_hash_exact test "$(file_hash "$backup_fragment")" = "$fragment_sha256"
require backup_manifest_regular test -f "$backup_manifest"
require backup_manifest_metadata test "$(file_metadata "$backup_manifest")" = root:root:600
require backup_manifest_line_count test "$(awk 'END { print NR }' "$backup_manifest")" -eq 4
require backup_manifest_action grep -Fqx 'action=28p' "$backup_manifest"
require backup_manifest_baseline grep -Fqx \
    "baseline_main_sha256=$production_baseline_main_sha256" "$backup_manifest"
require backup_manifest_fragment grep -Fqx "fragment_sha256=$fragment_sha256" "$backup_manifest"
require backup_manifest_retired grep -Fqx "retired_main_sha256=$main_sha256" "$backup_manifest"
require backup_entry_count test "$(find "$backup_directory" -mindepth 1 -maxdepth 1 -printf '.' | wc -c)" -eq 3
require transaction_residue_absent test -z \
    "$(find "$run_root" -maxdepth 1 -name 'caddy-action28p-*' -print -quit 2>/dev/null)"

before_state=$(snapshot "$main_configuration" "$caddy_fragment" "$backup_main" \
    "$backup_fragment" "$backup_manifest")
before_hash=$(printf '%s\n' "$before_state" | sha256sum | awk '{ print $1 }')
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$before_hash"
require keepalived_active_before service_active keepalived.service
require lighttpd_active_before service_active lighttpd.service
for action28pa_sample in 1 2 3 4 5; do
    require "caddy_active_before_sample_${action28pa_sample}" service_active caddy.service
    [[ -n "$fixture_root" || "$action28pa_sample" -eq 5 ]] || sleep 1
done
ipv4_status=0
address_query 4 >/dev/null 2>&1 || ipv4_status=$?
printf '%s_value_ipv4_query_before_status=%s\n' "$prefix" "$ipv4_status"
require ipv4_query_before_status_zero test "$ipv4_status" -eq 0
ipv6_status=0
address_query 6 >/dev/null 2>&1 || ipv6_status=$?
printf '%s_value_ipv6_query_before_status=%s\n' "$prefix" "$ipv6_status"
require ipv6_query_before_status_zero test "$ipv6_status" -eq 0
require dns_ipv4_absent_before test "$(address_count 4 10.1.0.55/22)" -eq 0
require dns_ipv6_absent_before test "$(address_count 6 fd36:5aa8:6971:1::55/128)" -eq 0
require caddy_ipv4_absent_before test "$(address_count 4 10.1.0.56/22)" -eq 0
require caddy_ipv6_absent_before test "$(address_count 6 fd36:5aa8:6971:1::56/128)" -eq 0

localhost_result=$(https_probe localhost 127.0.0.1 /)
localhost_status=${localhost_result%%|*}
localhost_code=${localhost_result#*|}
printf '%s_value_localhost_https_status=%s\n' "$prefix" "$localhost_status"
printf '%s_value_localhost_http_code=%s\n' "$prefix" "$localhost_code"
require localhost_health_status_zero test "$localhost_status" -eq 0
require localhost_health_status_204 test "$localhost_code" = 204
node_b_ipv4_result=$(https_probe pihole00.local.theama.co 10.1.0.54 /admin/)
node_b_ipv4_status=${node_b_ipv4_result%%|*}
node_b_ipv4_code=${node_b_ipv4_result#*|}
printf '%s_value_node_b_ipv4_https_status=%s\n' "$prefix" "$node_b_ipv4_status"
printf '%s_value_node_b_ipv4_http_code=%s\n' "$prefix" "$node_b_ipv4_code"
require node_b_ipv4_https_status_zero test "$node_b_ipv4_status" -eq 0
require node_b_ipv4_ui_status_200 test "$node_b_ipv4_code" = 200
node_b_ipv6_result=$(https_probe pihole00.local.theama.co '[fd36:5aa8:6971:1::54]' /admin/)
node_b_ipv6_status=${node_b_ipv6_result%%|*}
node_b_ipv6_code=${node_b_ipv6_result#*|}
printf '%s_value_node_b_ipv6_https_status=%s\n' "$prefix" "$node_b_ipv6_status"
printf '%s_value_node_b_ipv6_http_code=%s\n' "$prefix" "$node_b_ipv6_code"
require node_b_ipv6_https_status_zero test "$node_b_ipv6_status" -eq 0
require node_b_ipv6_ui_status_200 test "$node_b_ipv6_code" = 200

require keepalived_active_after service_active keepalived.service
require lighttpd_active_after service_active lighttpd.service
for action28pa_sample in 1 2 3 4 5; do
    require "caddy_active_after_sample_${action28pa_sample}" service_active caddy.service
done
ipv4_status=0
address_query 4 >/dev/null 2>&1 || ipv4_status=$?
printf '%s_value_ipv4_query_after_status=%s\n' "$prefix" "$ipv4_status"
require ipv4_query_after_status_zero test "$ipv4_status" -eq 0
ipv6_status=0
address_query 6 >/dev/null 2>&1 || ipv6_status=$?
printf '%s_value_ipv6_query_after_status=%s\n' "$prefix" "$ipv6_status"
require ipv6_query_after_status_zero test "$ipv6_status" -eq 0
require dns_ipv4_absent_after test "$(address_count 4 10.1.0.55/22)" -eq 0
require dns_ipv6_absent_after test "$(address_count 6 fd36:5aa8:6971:1::55/128)" -eq 0
require caddy_ipv4_absent_after test "$(address_count 4 10.1.0.56/22)" -eq 0
require caddy_ipv6_absent_after test "$(address_count 6 fd36:5aa8:6971:1::56/128)" -eq 0
dbus_stdout=$(mktemp /tmp/caddy-action28p-a-dbus.stdout.XXXXXX)
dbus_stderr=$(mktemp /tmp/caddy-action28p-a-dbus.stderr.XXXXXX)
readonly dbus_stdout dbus_stderr
trap 'rm -f -- "$dbus_stdout" "$dbus_stderr"' EXIT
dbus_status=0
if [[ -n "$fixture_root" ]]; then
    cat "$fixture_root/state/dbus-tree" >"$dbus_stdout" 2>"$dbus_stderr" || dbus_status=$?
else
    timeout 5 busctl --system --no-pager --list tree org.keepalived.Vrrp1 \
        >"$dbus_stdout" 2>"$dbus_stderr" || dbus_status=$?
fi
printf '%s_value_dbus_tree_status=%s\n' "$prefix" "$dbus_status"
require dbus_tree_status_zero test "$dbus_status" -eq 0
require dbus_tree_safe safe_stream "$dbus_stdout"
require dbus_tree_stderr_safe safe_stream "$dbus_stderr"
emit_stream dbus_tree_stdout "$dbus_stdout"
emit_stream dbus_tree_stderr "$dbus_stderr"
require caddy_ipv4_object_absent test \
    "$(grep -Fxc "$caddy_ipv4_object" "$dbus_stdout" || true)" -eq 0
require caddy_ipv6_object_absent test \
    "$(grep -Fxc "$caddy_ipv6_object" "$dbus_stdout" || true)" -eq 0
require main_still_exact test "$(file_hash "$main_configuration")" = "$main_sha256"
require fragment_still_exact test "$(file_hash "$caddy_fragment")" = "$fragment_sha256"
require backup_still_exact test \
    "$(file_hash "$backup_main")|$(file_hash "$backup_fragment")" = \
    "$production_baseline_main_sha256|$fragment_sha256"
after_state=$(snapshot "$main_configuration" "$caddy_fragment" "$backup_main" \
    "$backup_fragment" "$backup_manifest")
after_hash=$(printf '%s\n' "$after_state" | sha256sum | awk '{ print $1 }')
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$after_hash"
require state_unchanged test "$before_hash" = "$after_hash"
printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
printf '%s_first_failure=none\n' "$prefix"
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_mutation=false\n' "$prefix"
printf '%s_action_28p_rerun=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
