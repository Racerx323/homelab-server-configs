#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20o
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly health_helper=/usr/local/libexec/check-caddy.sh
readonly rollback_directory=/var/backups/caddy-ha/action20m-node-b-dbus-main.wHwzci
readonly rollback_main=$rollback_directory/keepalived.conf.before
readonly rollback_manifest=$rollback_directory/manifest
readonly expected_hostname=j1-svpihole00
readonly expected_main_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
readonly expected_rollback_main_sha256=8b260315628888c937c6f7eaf21f63e73eb52cfd9cd6e9c0d9d90fa9cf9fbd3f
readonly expected_source_sha256=9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148
readonly expected_fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
readonly expected_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly dbus_service=org.keepalived.Vrrp1
readonly dbus_interface=org.keepalived.Vrrp1.Instance
readonly dbus_ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/110/IPv4
readonly dbus_ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/111/IPv6
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly node_a_fqdn=pihole0.local.theama.co
readonly caddy_vip_fqdn=pihole-admin.local.theama.co
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

transaction_complete=false
mutation_started=false
transaction_root=
before_main_pid=
before_restarts=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
address_count() {
    local action20o_address_family=$1
    local action20o_address_cidr=$2

    ip -o "$action20o_address_family" address show dev eth0 |
        awk -v address="$action20o_address_cidr" '$4 == address { count++ } END { print count + 0 }'
}
expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact \
        main_regular main_not_symlink main_metadata main_hash_exact \
        main_enable_dbus_once main_dbus_service_name_absent main_include_once \
        fragment_regular fragment_not_symlink fragment_metadata fragment_hash_exact \
        health_regular health_not_symlink health_metadata health_hash_exact \
        rollback_directory_present rollback_directory_not_symlink rollback_directory_metadata \
        rollback_main_regular rollback_main_not_symlink rollback_main_metadata \
        rollback_main_hash_exact rollback_manifest_regular rollback_manifest_not_symlink \
        rollback_manifest_metadata rollback_manifest_lines rollback_manifest_action \
        rollback_manifest_node rollback_manifest_source rollback_manifest_before \
        rollback_manifest_candidate keepalived_active_before caddy_active_before \
        lighttpd_active_before keepalived_pid_numeric_before \
        keepalived_restarts_numeric_before vrrp_state_backup_before \
        caddy_ipv4_absent_before caddy_ipv6_absent_before dns_ipv4_absent_before \
        dns_ipv6_absent_before dbus_service_absent_before node_a_https_before \
        caddy_vip_https_before journal_cursor_captured reload_status \
        reload_journal_status dbus_list_status dbus_tree_status \
        dbus_ipv4_state_status dbus_ipv6_state_status reload_journal_no_fatal_errors \
        dbus_service_present_after dbus_tree_ipv4_object dbus_tree_ipv6_object \
        dbus_ipv4_state_backup dbus_ipv6_state_backup keepalived_active_after \
        caddy_active_after lighttpd_active_after keepalived_pid_unchanged \
        keepalived_restarts_unchanged vrrp_state_backup_after caddy_ipv4_absent_after \
        caddy_ipv6_absent_after dns_ipv4_absent_after dns_ipv6_absent_after \
        main_hash_unchanged fragment_hash_unchanged health_hash_unchanged \
        health_root_context health_keepalived_context node_a_https_after \
        caddy_vip_https_after
}
record_check() {
    local action20o_check_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20o_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20o_check_label" >&2
    return 1
}
safe_stream() {
    local action20o_stream_path=$1

    [[ "$(wc -c <"$action20o_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20o_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20o_stream_path" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' "$action20o_stream_path"
}
emit_stream() {
    local action20o_stream_label=$1
    local action20o_stream_path=$2

    printf '%s_capture_%s_bytes=%s\n' "$prefix" "$action20o_stream_label" "$(wc -c <"$action20o_stream_path")"
    printf '%s_capture_%s_lines=%s\n' "$prefix" "$action20o_stream_label" "$(line_count "$action20o_stream_path")"
    printf '%s_capture_%s_sha256=%s\n' "$prefix" "$action20o_stream_label" "$(file_hash "$action20o_stream_path")"
    if ! safe_stream "$action20o_stream_path"; then
        printf '%s_capture_%s_classification=unsafe_retained\n' "$prefix" "$action20o_stream_label" >&2
        return 97
    fi
    printf '%s_capture_%s_classification=bounded_safe\n' "$prefix" "$action20o_stream_label"
    if [[ -s "$action20o_stream_path" ]]; then
        printf '%s_capture_%s_begin\n' "$prefix" "$action20o_stream_label"
        sed "s/^/${prefix}_capture_${action20o_stream_label}_content=/" "$action20o_stream_path"
        printf '%s_capture_%s_end\n' "$prefix" "$action20o_stream_label"
    else
        printf '%s_capture_%s_content_secured=empty\n' "$prefix" "$action20o_stream_label"
    fi
}
run_captured() {
    local action20o_capture_label=$1
    local action20o_capture_status=0

    shift
    install -m 0600 /dev/null "$transaction_root/$action20o_capture_label.stdout"
    install -m 0600 /dev/null "$transaction_root/$action20o_capture_label.stderr"
    "$@" >"$transaction_root/$action20o_capture_label.stdout" \
        2>"$transaction_root/$action20o_capture_label.stderr" || action20o_capture_status=$?
    emit_stream "${action20o_capture_label}_stdout" "$transaction_root/$action20o_capture_label.stdout" || return 97
    emit_stream "${action20o_capture_label}_stderr" "$transaction_root/$action20o_capture_label.stderr" || return 97
    printf '%s_capture_%s_status=%s\n' "$prefix" "$action20o_capture_label" "$action20o_capture_status"
    [[ "$action20o_capture_status" -eq 0 ]]
}
wait_for_runtime() {
    for _ in $(seq 1 20); do
        if systemctl is-active --quiet keepalived.service &&
            [[ "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = BACKUP ]] &&
            [[ "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0 ]] &&
            [[ "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0 ]] &&
            timeout 3 busctl --system --no-pager --no-legend list 2>/dev/null |
            awk '$1 == "org.keepalived.Vrrp1" { found=1 } END { exit(found ? 0 : 1) }'; then
            return 0
        fi
        sleep 1
    done
    return 1
}
https_probe() {
    local action20o_probe_name=$1
    local action20o_probe_address=$2

    curl --silent --show-error --fail --insecure --head \
        --connect-timeout 2 --max-time 5 \
        --resolve "$action20o_probe_name:443:$action20o_probe_address" \
        "https://$action20o_probe_name/" >/dev/null
}
dbus_name_present() {
    local action20o_bus_list=$1

    awk '$1 == "org.keepalived.Vrrp1" { found++ } END { exit(found == 1 ? 0 : 1) }' "$action20o_bus_list"
}
dbus_name_absent_live() {
    ! timeout 3 busctl --system --no-pager --no-legend list 2>/dev/null |
        awk '$1 == "org.keepalived.Vrrp1" { found=1 } END { exit(found ? 0 : 1) }'
}
rollback_transaction() {
    local action20o_rollback_ok=true

    printf '%s_rollback_started=true\n' "$prefix" >&2
    install -o root -g root -m 0644 "$rollback_main" "$main_configuration" || action20o_rollback_ok=false
    if [[ "$action20o_rollback_ok" = true ]]; then
        if systemctl is-active --quiet keepalived.service; then
            run_captured rollback_reload systemctl reload keepalived.service ||
                run_captured rollback_restart systemctl restart keepalived.service || action20o_rollback_ok=false
        else
            run_captured rollback_restart systemctl restart keepalived.service || action20o_rollback_ok=false
        fi
    fi
    for _ in $(seq 1 20); do
        if systemctl is-active --quiet keepalived.service &&
            [[ "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = BACKUP ]] &&
            [[ "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0 ]] &&
            [[ "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0 ]]; then
            break
        fi
        sleep 1
    done
    [[ "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$expected_rollback_main_sha256" ]] || action20o_rollback_ok=false
    systemctl is-active --quiet keepalived.service || action20o_rollback_ok=false
    [[ "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = BACKUP ]] || action20o_rollback_ok=false
    [[ "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0 ]] || action20o_rollback_ok=false
    [[ "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0 ]] || action20o_rollback_ok=false
    https_probe "$node_a_fqdn" 10.1.0.53 || action20o_rollback_ok=false
    https_probe "$caddy_vip_fqdn" 10.1.0.56 || action20o_rollback_ok=false
    if timeout 3 busctl --system --no-pager --no-legend list 2>/dev/null |
        awk '$1 == "org.keepalived.Vrrp1" { found=1 } END { exit(found ? 0 : 1) }'; then
        action20o_rollback_ok=false
    fi
    if [[ "$action20o_rollback_ok" = true ]]; then
        printf '%s_rollback_complete=true\n' "$prefix" >&2
        return 0
    fi
    printf '%s_rollback_complete=false\n' "$prefix" >&2
    return 125
}
cleanup() {
    local action20o_cleanup_status=$?

    trap - EXIT INT TERM
    if [[ "$mutation_started" = true && "$transaction_complete" != true ]]; then
        rollback_transaction || action20o_cleanup_status=125
    fi
    if [[ -n "$transaction_root" && -d "$transaction_root" ]]; then
        rm -rf -- "$transaction_root"
    fi
    exit "$action20o_cleanup_status"
}
self_test() {
    [[ "$(expected_checks | wc -l)" -eq 77 ]] || return 1
    [[ "$(expected_checks | LC_ALL=C sort -u | wc -l)" -eq 77 ]] || return 1
    [[ "$(expected_checks | grep -Evc '^[a-z0-9_]+$')" -eq 0 ]] || return 1
    [[ "$dbus_service" = org.keepalived.Vrrp1 ]] || return 1
    [[ "$dbus_ipv4_object" = /org/keepalived/Vrrp1/Instance/eth0/110/IPv4 ]] || return 1
    [[ "$dbus_ipv6_object" = /org/keepalived/Vrrp1/Instance/eth0/111/IPv6 ]] || return 1
}

case "${1:-}" in
    --expected-checks)
        expected_checks
        exit 0
        ;;
    --self-test)
        self_test
        exit $?
        ;;
    '') ;;
    *) exit 64 ;;
esac

transaction_root=$(mktemp -d /run/caddy-action20o.XXXXXX)
readonly transaction_root
chmod 0700 "$transaction_root"
trap cleanup EXIT INT TERM

record_check identity_root test "$(id -u)" -eq 0 || exit 1
record_check working_directory_root test "$(pwd -P)" = / || exit 1
record_check hostname_exact test "$(hostname)" = "$expected_hostname" || exit 1
record_check main_regular test -f "$main_configuration" || exit 1
record_check main_not_symlink test ! -L "$main_configuration" || exit 1
record_check main_metadata test "$(stat -c '%U:%G:%a' "$main_configuration" 2>/dev/null || true)" = root:root:644 || exit 1
record_check main_hash_exact test "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$expected_main_sha256" || exit 1
record_check main_enable_dbus_once test "$(grep -Ec '^[[:space:]]*enable_dbus([[:space:]]|$)' "$main_configuration" 2>/dev/null || true)" -eq 1 || exit 1
record_check main_dbus_service_name_absent test "$(grep -Ec '^[[:space:]]*dbus_service_name([[:space:]]|$)' "$main_configuration" 2>/dev/null || true)" -eq 0 || exit 1
record_check main_include_once test "$(grep -Fxc 'include /etc/keepalived/conf.d/caddy-ha.conf' "$main_configuration" 2>/dev/null || true)" -eq 1 || exit 1
record_check fragment_regular test -f "$fragment" || exit 1
record_check fragment_not_symlink test ! -L "$fragment" || exit 1
record_check fragment_metadata test "$(stat -c '%U:%G:%a' "$fragment" 2>/dev/null || true)" = root:root:644 || exit 1
record_check fragment_hash_exact test "$(file_hash "$fragment" 2>/dev/null || true)" = "$expected_fragment_sha256" || exit 1
record_check health_regular test -f "$health_helper" || exit 1
record_check health_not_symlink test ! -L "$health_helper" || exit 1
record_check health_metadata test "$(stat -c '%U:%G:%a' "$health_helper" 2>/dev/null || true)" = root:root:755 || exit 1
record_check health_hash_exact test "$(file_hash "$health_helper" 2>/dev/null || true)" = "$expected_health_sha256" || exit 1
record_check rollback_directory_present test -d "$rollback_directory" || exit 1
record_check rollback_directory_not_symlink test ! -L "$rollback_directory" || exit 1
record_check rollback_directory_metadata test "$(stat -c '%U:%G:%a' "$rollback_directory" 2>/dev/null || true)" = root:root:700 || exit 1
record_check rollback_main_regular test -f "$rollback_main" || exit 1
record_check rollback_main_not_symlink test ! -L "$rollback_main" || exit 1
record_check rollback_main_metadata test "$(stat -c '%U:%G:%a' "$rollback_main" 2>/dev/null || true)" = root:root:600 || exit 1
record_check rollback_main_hash_exact test "$(file_hash "$rollback_main" 2>/dev/null || true)" = "$expected_rollback_main_sha256" || exit 1
record_check rollback_manifest_regular test -f "$rollback_manifest" || exit 1
record_check rollback_manifest_not_symlink test ! -L "$rollback_manifest" || exit 1
record_check rollback_manifest_metadata test "$(stat -c '%U:%G:%a' "$rollback_manifest" 2>/dev/null || true)" = root:root:600 || exit 1
record_check rollback_manifest_lines test "$(line_count "$rollback_manifest")" -eq 5 || exit 1
record_check rollback_manifest_action grep -Fqx action=20m "$rollback_manifest" || exit 1
record_check rollback_manifest_node grep -Fqx node=node-b "$rollback_manifest" || exit 1
record_check rollback_manifest_source grep -Fqx "source_sha256=$expected_source_sha256" "$rollback_manifest" || exit 1
record_check rollback_manifest_before grep -Fqx "before_sha256=$expected_rollback_main_sha256" "$rollback_manifest" || exit 1
record_check rollback_manifest_candidate grep -Fqx "candidate_sha256=$expected_main_sha256" "$rollback_manifest" || exit 1
record_check keepalived_active_before systemctl is-active --quiet keepalived.service || exit 1
record_check caddy_active_before systemctl is-active --quiet caddy.service || exit 1
record_check lighttpd_active_before systemctl is-active --quiet lighttpd.service || exit 1
before_main_pid=$(systemctl show keepalived.service --property MainPID --value)
before_restarts=$(systemctl show keepalived.service --property NRestarts --value)
readonly before_main_pid before_restarts
record_check keepalived_pid_numeric_before test "$before_main_pid" -gt 0 || exit 1
record_check keepalived_restarts_numeric_before test "$before_restarts" -ge 0 || exit 1
record_check vrrp_state_backup_before test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = BACKUP || exit 1
record_check caddy_ipv4_absent_before test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0 || exit 1
record_check caddy_ipv6_absent_before test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0 || exit 1
record_check dns_ipv4_absent_before test "$(address_count 4 "$dns_ipv4_cidr")" -eq 0 || exit 1
record_check dns_ipv6_absent_before test "$(address_count 6 "$dns_ipv6_cidr")" -eq 0 || exit 1
record_check dbus_service_absent_before dbus_name_absent_live || exit 1
record_check node_a_https_before https_probe "$node_a_fqdn" 10.1.0.53 || exit 1
record_check caddy_vip_https_before https_probe "$caddy_vip_fqdn" 10.1.0.56 || exit 1

journal_cursor=$(journalctl --unit keepalived.service --lines=0 --show-cursor --no-pager --output=cat | sed -n 's/^-- cursor: //p')
readonly journal_cursor
record_check journal_cursor_captured test -n "$journal_cursor" || exit 1
mutation_started=true
printf '%s_mutation_started=true\n' "$prefix"
record_check reload_status run_captured reload systemctl reload keepalived.service || exit 1
wait_for_runtime || exit 1
record_check reload_journal_status run_captured reload_journal journalctl --unit keepalived.service --after-cursor="$journal_cursor" --no-pager --output=short-iso-precise || exit 1
record_check dbus_list_status run_captured dbus_list timeout 5 busctl --system --no-pager --no-legend list || exit 1
record_check dbus_tree_status run_captured dbus_tree timeout 5 busctl --system --no-pager tree "$dbus_service" || exit 1
record_check dbus_ipv4_state_status run_captured dbus_ipv4_state timeout 5 busctl --system --no-pager get-property "$dbus_service" "$dbus_ipv4_object" "$dbus_interface" State || exit 1
record_check dbus_ipv6_state_status run_captured dbus_ipv6_state timeout 5 busctl --system --no-pager get-property "$dbus_service" "$dbus_ipv6_object" "$dbus_interface" State || exit 1
record_check reload_journal_no_fatal_errors test "$(grep -Eic 'configuration error|unknown keyword|syntax error|security violation|segmentation fault|fatal|unable to open dbus|disabling dbus|lost the name' "$transaction_root/reload_journal.stdout" || true)" -eq 0 || exit 1
record_check dbus_service_present_after dbus_name_present "$transaction_root/dbus_list.stdout" || exit 1
record_check dbus_tree_ipv4_object grep -Fq "$dbus_ipv4_object" "$transaction_root/dbus_tree.stdout" || exit 1
record_check dbus_tree_ipv6_object grep -Fq "$dbus_ipv6_object" "$transaction_root/dbus_tree.stdout" || exit 1
record_check dbus_ipv4_state_backup grep -Fq '"Backup"' "$transaction_root/dbus_ipv4_state.stdout" || exit 1
record_check dbus_ipv6_state_backup grep -Fq '"Backup"' "$transaction_root/dbus_ipv6_state.stdout" || exit 1
record_check keepalived_active_after systemctl is-active --quiet keepalived.service || exit 1
record_check caddy_active_after systemctl is-active --quiet caddy.service || exit 1
record_check lighttpd_active_after systemctl is-active --quiet lighttpd.service || exit 1
record_check keepalived_pid_unchanged test "$(systemctl show keepalived.service --property MainPID --value)" = "$before_main_pid" || exit 1
record_check keepalived_restarts_unchanged test "$(systemctl show keepalived.service --property NRestarts --value)" = "$before_restarts" || exit 1
record_check vrrp_state_backup_after test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = BACKUP || exit 1
record_check caddy_ipv4_absent_after test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0 || exit 1
record_check caddy_ipv6_absent_after test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0 || exit 1
record_check dns_ipv4_absent_after test "$(address_count 4 "$dns_ipv4_cidr")" -eq 0 || exit 1
record_check dns_ipv6_absent_after test "$(address_count 6 "$dns_ipv6_cidr")" -eq 0 || exit 1
record_check main_hash_unchanged test "$(file_hash "$main_configuration")" = "$expected_main_sha256" || exit 1
record_check fragment_hash_unchanged test "$(file_hash "$fragment")" = "$expected_fragment_sha256" || exit 1
record_check health_hash_unchanged test "$(file_hash "$health_helper")" = "$expected_health_sha256" || exit 1
record_check health_root_context "$health_helper" || exit 1
record_check health_keepalived_context runuser -u keepalived_script -- "$health_helper" || exit 1
record_check node_a_https_after https_probe "$node_a_fqdn" 10.1.0.53 || exit 1
record_check caddy_vip_https_after https_probe "$caddy_vip_fqdn" 10.1.0.56 || exit 1

printf '%s_value_expected_check_count=77\n' "$prefix"
printf '%s_value_main_sha256=%s\n' "$prefix" "$expected_main_sha256"
printf '%s_value_rollback_main_sha256=%s\n' "$prefix" "$expected_rollback_main_sha256"
printf '%s_value_dbus_service=%s\n' "$prefix" "$dbus_service"
printf '%s_value_before_main_pid=%s\n' "$prefix" "$before_main_pid"
printf '%s_value_after_main_pid=%s\n' "$prefix" "$(systemctl show keepalived.service --property MainPID --value)"
printf '%s_check_count=77\n' "$prefix"
printf '%s_failed_check_count=0\n' "$prefix"
printf '%s_first_failure=none\n' "$prefix"
printf '%s_keepalived_reload=true\n' "$prefix"
printf '%s_keepalived_restart=false\n' "$prefix"
printf '%s_dbus_runtime_active=true\n' "$prefix"
printf '%s_filesystem_mutation=false\n' "$prefix"
printf '%s_vrrp_transition=false\n' "$prefix"
printf '%s_vip_mutation=false\n' "$prefix"
printf '%s_node_a_ssh_contacted=false\n' "$prefix"
printf '%s_node_a_continuity_verified=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
transaction_complete=true
