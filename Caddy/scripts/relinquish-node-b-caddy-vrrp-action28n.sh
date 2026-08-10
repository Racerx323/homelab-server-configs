#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28n
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly caddy_fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly include_line='include /etc/keepalived/conf.d/caddy-ha.conf'
readonly baseline_main_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
readonly retired_main_sha256=9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148
readonly fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
readonly backup_directory=/var/backups/caddy-ha/action28n-node-b-caddy-vrrp-relinquish
readonly interface=eth0
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly node_b_fqdn=pihole00.local.theama.co
readonly caddy_ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/110/IPv4
readonly caddy_ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/111/IPv6
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact main_regular main_not_symlink \
        main_metadata main_hash_baseline include_once include_terminal fragment_regular \
        fragment_not_symlink fragment_metadata fragment_hash_exact backup_absent \
        transaction_residue_absent keepalived_active_before \
        caddy_active_before_sample_1 caddy_active_before_sample_2 \
        caddy_active_before_sample_3 caddy_active_before_sample_4 \
        caddy_active_before_sample_5 \
        lighttpd_active_before ipv4_query_before_status_zero ipv6_query_before_status_zero \
        dns_ipv4_absent_before dns_ipv6_absent_before caddy_ipv4_owned_before \
        caddy_ipv6_owned_before node_b_ipv4_ui_before node_b_ipv6_ui_before \
        candidate_hash_exact candidate_include_absent candidate_byte_boundary_exact \
        candidate_dns_instances_retained candidate_not_coupled backup_created \
        backup_main_hash_exact backup_fragment_hash_exact backup_manifest_lines \
        backup_manifest_action backup_manifest_baseline backup_manifest_fragment \
        backup_manifest_retired \
        main_installed main_hash_retired main_include_absent journal_cursor_status_zero \
        journal_cursor_present reload_status_zero \
        reload_stdout_safe reload_stderr_safe caddy_vips_relinquished_within_bound \
        reload_journal_status_zero \
        reload_journal_safe reload_journal_no_fatal keepalived_active_after \
        caddy_active_after_sample_1 caddy_active_after_sample_2 \
        caddy_active_after_sample_3 caddy_active_after_sample_4 \
        caddy_active_after_sample_5 lighttpd_active_after ipv4_query_after_status_zero \
        ipv6_query_after_status_zero dns_ipv4_absent_after dns_ipv6_absent_after \
        caddy_ipv4_absent_after caddy_ipv6_absent_after dbus_tree_status_zero \
        dbus_tree_safe caddy_ipv4_object_absent caddy_ipv6_object_absent \
        node_b_ipv4_ui_after node_b_ipv6_ui_after fragment_still_exact \
        transaction_stage_removed
}
expected_rollback_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact backup_directory_exact \
        backup_main_exact backup_fragment_exact main_hash_retired fragment_hash_exact \
        main_restored reload_status_zero reload_stdout_safe reload_stderr_safe \
        caddy_vips_restored_within_bound \
        keepalived_active caddy_active lighttpd_active ipv4_query_status_zero \
        ipv6_query_status_zero dns_ipv4_absent dns_ipv6_absent caddy_ipv4_owned \
        caddy_ipv6_owned node_b_ipv4_ui node_b_ipv6_ui transaction_stage_removed
}
file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
address_query() { ip -o "-$1" address show dev "$interface"; }
address_count() {
    local action28n_family=$1
    local action28n_cidr=$2

    address_query "$action28n_family" |
        awk -v expected="$action28n_cidr" '$4 == expected { count++ } END { print count + 0 }'
}
safe_stream() {
    local action28n_stream=$1

    [[ "$(wc -c <"$action28n_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28n_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28n_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' "$action28n_stream"
}
emit_stream() {
    local action28n_label=$1
    local action28n_stream=$2

    printf '%s_capture_%s_bytes=%s\n' "$prefix" "$action28n_label" "$(wc -c <"$action28n_stream")"
    printf '%s_capture_%s_lines=%s\n' "$prefix" "$action28n_label" "$(line_count "$action28n_stream")"
    printf '%s_capture_%s_sha256=%s\n' "$prefix" "$action28n_label" "$(file_hash "$action28n_stream")"
    if safe_stream "$action28n_stream"; then
        printf '%s_capture_%s_classification=bounded_safe\n' "$prefix" "$action28n_label"
        if [[ -s "$action28n_stream" ]]; then
            printf '%s_capture_%s_begin\n' "$prefix" "$action28n_label"
            sed "s/^/${prefix}_capture_${action28n_label}_content=/" "$action28n_stream"
            printf '%s_capture_%s_end\n' "$prefix" "$action28n_label"
        else
            printf '%s_capture_%s_content=empty\n' "$prefix" "$action28n_label"
        fi
        return 0
    fi
    printf '%s_capture_%s_classification=unsafe_retained\n' "$prefix" "$action28n_label" >&2
    return 97
}
check() {
    local action28n_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28n_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28n_label"
    return 1
}
require_check() {
    local action28n_required_label=$1

    shift
    check "$action28n_required_label" "$@" || {
        first_failure=$action28n_required_label
        return 1
    }
}
rollback_check() {
    local action28n_rollback_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_rollback_check_%s=true\n' "$prefix" "$action28n_rollback_label"
        return 0
    fi
    printf '%s_rollback_check_%s=false\n' "$prefix" "$action28n_rollback_label"
    return 1
}
require_rollback_check() {
    local action28n_rollback_required_label=$1

    shift
    rollback_check "$action28n_rollback_required_label" "$@" || {
        rollback_first_failure=$action28n_rollback_required_label
        return 1
    }
}
candidate_contract() {
    local action28n_candidate_file=$1

    [[ "$(file_hash "$action28n_candidate_file")" = "$retired_main_sha256" ]] || return 1
    [[ "$(grep -Fxc "$include_line" "$action28n_candidate_file" || true)" -eq 0 ]] || return 1
    [[ "$(grep -Fxc 'vrrp_instance PIHOLE_IPV4 {' "$action28n_candidate_file" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'vrrp_instance PIHOLE_IPV6 {' "$action28n_candidate_file" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc '        10.1.0.55/22 dev eth0' "$action28n_candidate_file" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc '        fd36:5aa8:6971:1::55/128 dev eth0 preferred_lft forever' "$action28n_candidate_file" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc '        10.1.0.56/22 dev eth0' "$action28n_candidate_file" || true)" -eq 0 ]] || return 1
    [[ "$(grep -Fxc '        fd36:5aa8:6971:1::56/128 dev eth0 preferred_lft forever' "$action28n_candidate_file" || true)" -eq 0 ]]
}
candidate_byte_boundary() {
    local action28n_source_file=$1
    local action28n_candidate_file=$2
    local action28n_rebuilt

    action28n_rebuilt=$(mktemp /tmp/caddy-action28n-boundary.XXXXXX) || return 1
    sed '$d' "$action28n_source_file" | sed '$d' >"$action28n_rebuilt" || {
        rm -f -- "$action28n_rebuilt"
        return 1
    }
    cmp -s "$action28n_rebuilt" "$action28n_candidate_file"
    local action28n_boundary_status=$?
    rm -f -- "$action28n_rebuilt"
    return "$action28n_boundary_status"
}
https_status() {
    local action28n_address=$1
    local action28n_status=0
    local action28n_code

    action28n_code=$(curl --noproxy '*' --insecure --silent --show-error --location \
        --max-redirs 3 --proto-redir '=https' --connect-timeout 3 --max-time 10 \
        --resolve "${node_b_fqdn}:443:${action28n_address}" --output /dev/null \
        --write-out '%{http_code}' "https://${node_b_fqdn}/admin/") || action28n_status=$?
    [[ "$action28n_status" -eq 0 && "$action28n_code" = 200 ]]
}
run_captured() {
    local action28n_capture_label=$1
    local action28n_capture_status=0

    shift
    install -m 0600 /dev/null "$capture_directory/${action28n_capture_label}.stdout"
    install -m 0600 /dev/null "$capture_directory/${action28n_capture_label}.stderr"
    "$@" >"$capture_directory/${action28n_capture_label}.stdout" \
        2>"$capture_directory/${action28n_capture_label}.stderr" || action28n_capture_status=$?
    emit_stream "${action28n_capture_label}_stdout" "$capture_directory/${action28n_capture_label}.stdout" || return 97
    emit_stream "${action28n_capture_label}_stderr" "$capture_directory/${action28n_capture_label}.stderr" || return 97
    printf '%s_capture_%s_status=%s\n' "$prefix" "$action28n_capture_label" "$action28n_capture_status"
    [[ "$action28n_capture_status" -eq 0 ]]
}
wait_relinquished() {
    for _ in $(seq 1 30); do
        if systemctl is-active --quiet keepalived.service &&
            [[ "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0 ]] &&
            [[ "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0 ]]; then
            return 0
        fi
        sleep 1
    done
    return 1
}
wait_restored() {
    for _ in $(seq 1 40); do
        if systemctl is-active --quiet keepalived.service &&
            [[ "$(address_count 4 "$caddy_ipv4_cidr")" -eq 1 ]] &&
            [[ "$(address_count 6 "$caddy_ipv6_cidr")" -eq 1 ]]; then
            return 0
        fi
        sleep 1
    done
    return 1
}
recovery_check() {
    local action28n_recovery_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_recovery_check_%s=true\n' "$prefix" "$action28n_recovery_label"
        return 0
    fi
    printf '%s_recovery_check_%s=false\n' "$prefix" "$action28n_recovery_label"
    return 1
}
rollback_live() {
    local action28n_rollback_status=0

    rollback_invoked=true
    if [[ -f "$backup_directory/keepalived.conf" ]]; then
        install -o root -g root -m 0644 "$backup_directory/keepalived.conf" \
            "$main_configuration" || action28n_rollback_status=125
        if [[ "$action28n_rollback_status" -eq 0 ]]; then
            action28n_recovery_reload_status=0
            run_captured rollback_reload systemctl reload keepalived.service ||
                action28n_recovery_reload_status=$?
            recovery_check reload_status_zero test "$action28n_recovery_reload_status" -eq 0 ||
                action28n_rollback_status=125
            reload_count=$((reload_count + 1))
        fi
        if [[ "$action28n_rollback_status" -eq 0 ]]; then
            recovery_check caddy_vips_restored_within_bound wait_restored || action28n_rollback_status=125
        fi
    else
        action28n_rollback_status=125
    fi
    recovery_check main_restored test "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$baseline_main_sha256" || action28n_rollback_status=125
    recovery_check keepalived_active systemctl is-active --quiet keepalived.service || action28n_rollback_status=125
    recovery_check caddy_active systemctl is-active --quiet caddy.service || action28n_rollback_status=125
    recovery_check dns_ipv4_absent test "$(address_count 4 "$dns_ipv4_cidr" 2>/dev/null || true)" -eq 0 || action28n_rollback_status=125
    recovery_check dns_ipv6_absent test "$(address_count 6 "$dns_ipv6_cidr" 2>/dev/null || true)" -eq 0 || action28n_rollback_status=125
    recovery_check caddy_ipv4_owned test "$(address_count 4 "$caddy_ipv4_cidr" 2>/dev/null || true)" -eq 1 || action28n_rollback_status=125
    recovery_check caddy_ipv6_owned test "$(address_count 6 "$caddy_ipv6_cidr" 2>/dev/null || true)" -eq 1 || action28n_rollback_status=125
    printf '%s_rollback_status=%s\n' "$prefix" "$action28n_rollback_status"
    return "$action28n_rollback_status"
}
cleanup() {
    local action28n_cleanup_status=$?

    trap - EXIT ERR HUP INT TERM
    if [[ "$action28n_cleanup_status" -ne 0 && "$mutation_started" = true && "$transaction_complete" != true ]]; then
        rollback_live || action28n_cleanup_status=125
    fi
    [[ -z "$transaction_root" || ! -d "$transaction_root" ]] || rm -rf -- "$transaction_root"
    printf '%s_value_first_failure=%s\n' "$prefix" "$first_failure"
    printf '%s_rollback_invoked=%s\n' "$prefix" "$rollback_invoked"
    printf '%s_keepalived_reload_count=%s\n' "$prefix" "$reload_count"
    printf '%s_node_a_ssh_contacted=false\n' "$prefix"
    if [[ "$action28n_cleanup_status" -eq 0 ]]; then
        printf '%s_acceptance=true\n' "$prefix"
    else
        printf '%s_acceptance=false\n' "$prefix"
    fi
    exit "$action28n_cleanup_status"
}
external_rollback() {
    first_failure=none
    rollback_first_failure=none
    transaction_root=$(mktemp -d /run/caddy-action28n-rollback.XXXXXX)
    chmod 0700 "$transaction_root"
    capture_directory=$transaction_root/capture
    install -d -o root -g root -m 0700 "$capture_directory"
    require_rollback_check identity_root test "$(id -u)" -eq 0 || return 125
    require_rollback_check working_directory_root test "$(pwd -P)" = / || return 125
    require_rollback_check hostname_exact test "$(hostname)" = j1-svpihole00 || return 125
    require_rollback_check backup_directory_exact test "$(stat -c '%U:%G:%a' "$backup_directory")" = root:root:700 || return 125
    require_rollback_check backup_main_exact test "$(file_hash "$backup_directory/keepalived.conf")" = "$baseline_main_sha256" || return 125
    require_rollback_check backup_fragment_exact test "$(file_hash "$backup_directory/caddy-ha.conf")" = "$fragment_sha256" || return 125
    require_rollback_check main_hash_retired test "$(file_hash "$main_configuration")" = "$retired_main_sha256" || return 125
    require_rollback_check fragment_hash_exact test "$(file_hash "$caddy_fragment")" = "$fragment_sha256" || return 125
    install -o root -g root -m 0644 "$backup_directory/keepalived.conf" "$main_configuration"
    require_rollback_check main_restored test "$(file_hash "$main_configuration")" = "$baseline_main_sha256" || return 125
    local action28n_external_reload_status=0
    run_captured external_rollback_reload systemctl reload keepalived.service ||
        action28n_external_reload_status=$?
    require_rollback_check reload_status_zero test "$action28n_external_reload_status" -eq 0 || return 125
    require_rollback_check reload_stdout_safe safe_stream "$capture_directory/external_rollback_reload.stdout" || return 125
    require_rollback_check reload_stderr_safe safe_stream "$capture_directory/external_rollback_reload.stderr" || return 125
    require_rollback_check caddy_vips_restored_within_bound wait_restored || return 125
    require_rollback_check keepalived_active systemctl is-active --quiet keepalived.service || return 125
    require_rollback_check caddy_active systemctl is-active --quiet caddy.service || return 125
    require_rollback_check lighttpd_active systemctl is-active --quiet lighttpd.service || return 125
    local action28n_ipv4_status=0 action28n_ipv6_status=0
    address_query 4 >/dev/null 2>&1 || action28n_ipv4_status=$?
    address_query 6 >/dev/null 2>&1 || action28n_ipv6_status=$?
    require_rollback_check ipv4_query_status_zero test "$action28n_ipv4_status" -eq 0 || return 125
    require_rollback_check ipv6_query_status_zero test "$action28n_ipv6_status" -eq 0 || return 125
    require_rollback_check dns_ipv4_absent test "$(address_count 4 "$dns_ipv4_cidr")" -eq 0 || return 125
    require_rollback_check dns_ipv6_absent test "$(address_count 6 "$dns_ipv6_cidr")" -eq 0 || return 125
    require_rollback_check caddy_ipv4_owned test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 1 || return 125
    require_rollback_check caddy_ipv6_owned test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 1 || return 125
    require_rollback_check node_b_ipv4_ui https_status 10.1.0.54 || return 125
    require_rollback_check node_b_ipv6_ui https_status '[fd36:5aa8:6971:1::54]' || return 125
    rm -rf -- "$transaction_root"
    transaction_root=
    require_rollback_check transaction_stage_removed test ! -e "$transaction_root" || return 125
    printf '%s_rollback_first_failure=%s\n' "$prefix" "$rollback_first_failure"
    printf '%s_rollback_acceptance=true\n' "$prefix"
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]]
        expected_checks
        exit 0
        ;;
    --expected-rollback-checks)
        [[ $# -eq 1 ]]
        expected_rollback_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        labels=$(expected_checks)
        rollback_labels=$(expected_rollback_checks)
        [[ "$(printf '%s\n' "$labels" | wc -l)" -eq "$(printf '%s\n' "$labels" | LC_ALL=C sort -u | wc -l)" ]]
        [[ "$(printf '%s\n' "$rollback_labels" | wc -l)" -eq "$(printf '%s\n' "$rollback_labels" | LC_ALL=C sort -u | wc -l)" ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --candidate-test)
        [[ $# -eq 3 ]]
        candidate_contract "$3"
        candidate_byte_boundary "$2" "$3"
        printf '%s_candidate_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --rollback)
        [[ $# -eq 1 ]]
        external_rollback
        exit 0
        ;;
    --execute)
        [[ $# -eq 1 ]]
        ;;
    *) exit 64 ;;
esac

first_failure=none
transaction_root=
capture_directory=
mutation_started=false
transaction_complete=false
rollback_invoked=false
reload_count=0
trap cleanup EXIT ERR HUP INT TERM

require_check identity_root test "$(id -u)" -eq 0
require_check working_directory_root test "$(pwd -P)" = /
require_check hostname_exact test "$(hostname)" = j1-svpihole00
require_check main_regular test -f "$main_configuration"
require_check main_not_symlink test ! -L "$main_configuration"
require_check main_metadata test "$(stat -c '%U:%G:%a' "$main_configuration")" = root:root:644
require_check main_hash_baseline test "$(file_hash "$main_configuration")" = "$baseline_main_sha256"
require_check include_once test "$(grep -Fxc "$include_line" "$main_configuration")" -eq 1
require_check include_terminal test "$(tail -n 1 "$main_configuration")" = "$include_line"
require_check fragment_regular test -f "$caddy_fragment"
require_check fragment_not_symlink test ! -L "$caddy_fragment"
require_check fragment_metadata test "$(stat -c '%U:%G:%a' "$caddy_fragment")" = root:root:644
require_check fragment_hash_exact test "$(file_hash "$caddy_fragment")" = "$fragment_sha256"
require_check backup_absent test ! -e "$backup_directory"
require_check transaction_residue_absent test -z "$(find /run -maxdepth 1 -name 'caddy-action28n-*' -print -quit 2>/dev/null)"
require_check keepalived_active_before systemctl is-active --quiet keepalived.service
for caddy_sample in 1 2 3 4 5; do
    require_check "caddy_active_before_sample_${caddy_sample}" systemctl is-active --quiet caddy.service
    [[ "$caddy_sample" -eq 5 ]] || sleep 1
done
require_check lighttpd_active_before systemctl is-active --quiet lighttpd.service
ipv4_status=0
address_query 4 >/dev/null 2>&1 || ipv4_status=$?
require_check ipv4_query_before_status_zero test "$ipv4_status" -eq 0
ipv6_status=0
address_query 6 >/dev/null 2>&1 || ipv6_status=$?
require_check ipv6_query_before_status_zero test "$ipv6_status" -eq 0
require_check dns_ipv4_absent_before test "$(address_count 4 "$dns_ipv4_cidr")" -eq 0
require_check dns_ipv6_absent_before test "$(address_count 6 "$dns_ipv6_cidr")" -eq 0
require_check caddy_ipv4_owned_before test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 1
require_check caddy_ipv6_owned_before test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 1
require_check node_b_ipv4_ui_before https_status 10.1.0.54
require_check node_b_ipv6_ui_before https_status '[fd36:5aa8:6971:1::54]'

transaction_root=$(mktemp -d /run/caddy-action28n-stage.XXXXXX)
chmod 0700 "$transaction_root"
capture_directory=$transaction_root/capture
install -d -o root -g root -m 0700 "$capture_directory"
candidate=$transaction_root/keepalived.conf
sed '$d' "$main_configuration" | sed '$d' >"$candidate"
chmod 0600 "$candidate"
require_check candidate_hash_exact test "$(file_hash "$candidate")" = "$retired_main_sha256"
require_check candidate_include_absent test "$(grep -Fxc "$include_line" "$candidate" || true)" -eq 0
require_check candidate_byte_boundary_exact candidate_byte_boundary "$main_configuration" "$candidate"
require_check candidate_dns_instances_retained candidate_contract "$candidate"
require_check candidate_not_coupled test "$(grep -Fxc '        10.1.0.56/22 dev eth0' "$candidate" || true)" -eq 0

install -d -o root -g root -m 0700 "$backup_directory"
install -o root -g root -m 0600 "$main_configuration" "$backup_directory/keepalived.conf"
install -o root -g root -m 0600 "$caddy_fragment" "$backup_directory/caddy-ha.conf"
printf 'action=28n\nbaseline_main_sha256=%s\nfragment_sha256=%s\nretired_main_sha256=%s\n' \
    "$baseline_main_sha256" "$fragment_sha256" "$retired_main_sha256" >"$backup_directory/manifest"
chmod 0600 "$backup_directory/manifest"
require_check backup_created test "$(stat -c '%U:%G:%a' "$backup_directory")" = root:root:700
require_check backup_main_hash_exact test "$(file_hash "$backup_directory/keepalived.conf")" = "$baseline_main_sha256"
require_check backup_fragment_hash_exact test "$(file_hash "$backup_directory/caddy-ha.conf")" = "$fragment_sha256"
require_check backup_manifest_lines test "$(line_count "$backup_directory/manifest")" -eq 4
require_check backup_manifest_action grep -Fqx 'action=28n' "$backup_directory/manifest"
require_check backup_manifest_baseline grep -Fqx "baseline_main_sha256=$baseline_main_sha256" "$backup_directory/manifest"
require_check backup_manifest_fragment grep -Fqx "fragment_sha256=$fragment_sha256" "$backup_directory/manifest"
require_check backup_manifest_retired grep -Fqx "retired_main_sha256=$retired_main_sha256" "$backup_directory/manifest"

mutation_started=true
install -o root -g root -m 0644 "$candidate" "$main_configuration"
require_check main_installed test -f "$main_configuration"
require_check main_hash_retired test "$(file_hash "$main_configuration")" = "$retired_main_sha256"
require_check main_include_absent test "$(grep -Fxc "$include_line" "$main_configuration" || true)" -eq 0

journal_cursor_status=0
journal_cursor=$(journalctl --sync --quiet 2>/dev/null &&
    journalctl -u keepalived.service -n 0 --show-cursor --no-pager 2>/dev/null |
    sed -n 's/^-- cursor: //p') || journal_cursor_status=$?
require_check journal_cursor_status_zero test "$journal_cursor_status" -eq 0
require_check journal_cursor_present test -n "$journal_cursor"
reload_status=0
run_captured reload systemctl reload keepalived.service || reload_status=$?
reload_count=1
require_check reload_status_zero test "$reload_status" -eq 0
require_check reload_stdout_safe safe_stream "$capture_directory/reload.stdout"
require_check reload_stderr_safe safe_stream "$capture_directory/reload.stderr"
require_check caddy_vips_relinquished_within_bound wait_relinquished
reload_journal_status=0
run_captured reload_journal journalctl -u keepalived.service --after-cursor "$journal_cursor" --no-pager --output=short-iso ||
    reload_journal_status=$?
require_check reload_journal_status_zero test "$reload_journal_status" -eq 0
require_check reload_journal_safe safe_stream "$capture_directory/reload_journal.stdout"
require_check reload_journal_no_fatal test "$(grep -Eic 'fatal|parse error|configuration error|segmentation fault' "$capture_directory/reload_journal.stdout" || true)" -eq 0
require_check keepalived_active_after systemctl is-active --quiet keepalived.service
for caddy_sample in 1 2 3 4 5; do
    require_check "caddy_active_after_sample_${caddy_sample}" systemctl is-active --quiet caddy.service
    [[ "$caddy_sample" -eq 5 ]] || sleep 1
done
require_check lighttpd_active_after systemctl is-active --quiet lighttpd.service
ipv4_status=0
address_query 4 >/dev/null 2>&1 || ipv4_status=$?
require_check ipv4_query_after_status_zero test "$ipv4_status" -eq 0
ipv6_status=0
address_query 6 >/dev/null 2>&1 || ipv6_status=$?
require_check ipv6_query_after_status_zero test "$ipv6_status" -eq 0
require_check dns_ipv4_absent_after test "$(address_count 4 "$dns_ipv4_cidr")" -eq 0
require_check dns_ipv6_absent_after test "$(address_count 6 "$dns_ipv6_cidr")" -eq 0
require_check caddy_ipv4_absent_after test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0
require_check caddy_ipv6_absent_after test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0
dbus_tree_status=0
run_captured dbus_tree timeout 5 busctl --system --no-pager --list tree org.keepalived.Vrrp1 ||
    dbus_tree_status=$?
require_check dbus_tree_status_zero test "$dbus_tree_status" -eq 0
require_check dbus_tree_safe safe_stream "$capture_directory/dbus_tree.stdout"
require_check caddy_ipv4_object_absent test "$(grep -Fxc "$caddy_ipv4_object" "$capture_directory/dbus_tree.stdout" || true)" -eq 0
require_check caddy_ipv6_object_absent test "$(grep -Fxc "$caddy_ipv6_object" "$capture_directory/dbus_tree.stdout" || true)" -eq 0
require_check node_b_ipv4_ui_after https_status 10.1.0.54
require_check node_b_ipv6_ui_after https_status '[fd36:5aa8:6971:1::54]'
require_check fragment_still_exact test "$(file_hash "$caddy_fragment")" = "$fragment_sha256"
rm -rf -- "$transaction_root"
transaction_root=
require_check transaction_stage_removed test ! -e "$transaction_root"
transaction_complete=true
printf '%s_value_baseline_main_sha256=%s\n' "$prefix" "$baseline_main_sha256"
printf '%s_value_retired_main_sha256=%s\n' "$prefix" "$retired_main_sha256"
printf '%s_value_fragment_sha256=%s\n' "$prefix" "$fragment_sha256"
