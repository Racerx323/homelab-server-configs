#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20l
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly health_helper=/usr/local/libexec/check-caddy.sh
readonly health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly maximum_capture_bytes=1048576
readonly maximum_capture_lines=4096
readonly expected_check_count=49

action20l_failed_check_count=0
action20l_first_failure=none

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
address_count() {
    local action20l_address_family=$1
    local action20l_expected_cidr=$2

    ip -o "-$action20l_address_family" address show dev eth0 2>/dev/null |
        awk -v expected="$action20l_expected_cidr" '$4 == expected { count++ }
            END { print count + 0 }'
}
expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact architecture_arm64 \
        main_regular main_not_symlink main_metadata_exact main_hash_exact \
        main_enable_dbus_absent main_dbus_service_name_absent \
        fragment_regular fragment_not_symlink fragment_metadata_exact \
        fragment_hash_exact health_regular health_not_symlink \
        health_metadata_exact health_hash_exact keepalived_active_before \
        caddy_active_before lighttpd_active_before keepalived_pid_numeric_before \
        keepalived_restarts_numeric_before vrrp_state_exact_before \
        caddy_ipv4_count_exact_before caddy_ipv6_count_exact_before \
        dns_ipv4_count_exact_before dns_ipv6_count_exact_before \
        keepalived_binary_executable busctl_binary_executable \
        system_bus_socket_present keepalived_version_status_zero \
        keepalived_version_stdout_safe keepalived_version_stderr_safe \
        keepalived_version_output_present keepalived_product_line_present \
        keepalived_config_options_line_present keepalived_dbus_build_feature_present \
        system_bus_query_status_zero system_bus_query_stdout_safe \
        system_bus_query_stderr_safe system_bus_query_output_present \
        system_bus_daemon_name_present keepalived_active_after \
        keepalived_pid_unchanged keepalived_restarts_unchanged \
        vrrp_state_exact_after vip_ownership_exact_after state_snapshot_unchanged
}
record_check() {
    local action20l_check_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20l_check_label"
    else
        printf '%s_check_%s=false\n' "$prefix" "$action20l_check_label"
        action20l_failed_check_count=$((action20l_failed_check_count + 1))
        if [[ "$action20l_first_failure" = none ]]; then
            action20l_first_failure=$action20l_check_label
        fi
    fi
    return 0
}
safe_capture() {
    local action20l_capture_path=$1

    [[ "$(wc -c <"$action20l_capture_path")" -le "$maximum_capture_bytes" ]] || return 1
    [[ "$(line_count "$action20l_capture_path")" -le "$maximum_capture_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20l_capture_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20l_capture_path"
}
emit_encoded_capture() {
    local action20l_capture_label=$1
    local action20l_capture_path=$2

    printf '%s_capture_%s_bytes=%s\n' "$prefix" "$action20l_capture_label" \
        "$(wc -c <"$action20l_capture_path")"
    printf '%s_capture_%s_lines=%s\n' "$prefix" "$action20l_capture_label" \
        "$(line_count "$action20l_capture_path")"
    printf '%s_capture_%s_sha256=%s\n' "$prefix" "$action20l_capture_label" \
        "$(file_hash "$action20l_capture_path")"
    printf '%s_capture_%s_classification=bounded_safe\n' "$prefix" "$action20l_capture_label"
    printf '%s_capture_%s_base64=%s\n' "$prefix" "$action20l_capture_label" \
        "$(base64 -w 0 "$action20l_capture_path")"
}
version_has_dbus() {
    local action20l_version_combined=$1

    awk '
        $1 == "Config" && $2 == "options:" {
            for (field = 3; field <= NF; field++) {
                if ($field == "DBUS") found = 1
            }
        }
        END { exit(found == 1 ? 0 : 1) }
    ' "$action20l_version_combined"
}
state_snapshot() {
    printf 'main=%s|%s\n' \
        "$(stat -c '%U:%G:%a' "$main_configuration" 2>/dev/null || printf unavailable)" \
        "$(file_hash "$main_configuration" 2>/dev/null || printf unavailable)"
    printf 'fragment=%s|%s\n' \
        "$(stat -c '%U:%G:%a' "$fragment" 2>/dev/null || printf unavailable)" \
        "$(file_hash "$fragment" 2>/dev/null || printf unavailable)"
    printf 'health=%s|%s\n' \
        "$(stat -c '%U:%G:%a' "$health_helper" 2>/dev/null || printf unavailable)" \
        "$(file_hash "$health_helper" 2>/dev/null || printf unavailable)"
    printf 'keepalived=%s|%s|%s\n' \
        "$(systemctl is-active keepalived.service 2>/dev/null || printf unavailable)" \
        "$(systemctl show keepalived.service --property MainPID --value 2>/dev/null || printf unavailable)" \
        "$(systemctl show keepalived.service --property NRestarts --value 2>/dev/null || printf unavailable)"
    printf 'caddy=%s\n' "$(systemctl is-active caddy.service 2>/dev/null || printf unavailable)"
    printf 'lighttpd=%s\n' "$(systemctl is-active lighttpd.service 2>/dev/null || printf unavailable)"
    printf 'vrrp=%s\n' "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || printf unavailable)"
    printf 'vips=%s|%s|%s|%s\n' \
        "$(address_count 4 "$caddy_ipv4_cidr")" \
        "$(address_count 6 "$caddy_ipv6_cidr")" \
        "$(address_count 4 "$dns_ipv4_cidr")" \
        "$(address_count 6 "$dns_ipv6_cidr")"
}
self_test() {
    local action20l_self_test_root
    local action20l_self_test_version

    [[ "$(expected_checks | wc -l)" -eq "$expected_check_count" ]] || return 1
    [[ "$(expected_checks | LC_ALL=C sort -u | wc -l)" -eq "$expected_check_count" ]] || return 1
    [[ "$(expected_checks | grep -Evc '^[a-z0-9_]+$')" -eq 0 ]] || return 1
    action20l_self_test_root=$(mktemp -d /tmp/caddy-action20l-self-test.XXXXXX) || return 1
    trap 'rm -rf -- "$action20l_self_test_root"' RETURN
    action20l_self_test_version=$action20l_self_test_root/version
    printf '%s\n' 'Keepalived v2.2.7' 'Config options: VRRP DBUS' >"$action20l_self_test_version" || return 1
    version_has_dbus "$action20l_self_test_version" || return 1
    printf '%s\n' 'Keepalived v2.2.7' 'Config options: VRRP' >"$action20l_self_test_version" || return 1
    ! version_has_dbus "$action20l_self_test_version" || return 1
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
    --node)
        [[ $# -eq 2 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s --node node-a|node-b | --expected-checks | --self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac

readonly node_role=$2
case "$node_role" in
    node-a)
        readonly expected_hostname=j1-svpihole0
        readonly expected_main_sha256=357eb09c628fa3b78efcaacf53278ab09a6574b991820632ee3ec2614265d8e2
        readonly expected_fragment_sha256=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
        readonly expected_vrrp_state=MASTER
        readonly expected_caddy_vip_count=1
        readonly expected_dns_vip_count=1
        ;;
    node-b)
        readonly expected_hostname=j1-svpihole00
        readonly expected_main_sha256=8b260315628888c937c6f7eaf21f63e73eb52cfd9cd6e9c0d9d90fa9cf9fbd3f
        readonly expected_fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
        readonly expected_vrrp_state=BACKUP
        readonly expected_caddy_vip_count=0
        readonly expected_dns_vip_count=0
        ;;
    *) exit 64 ;;
esac

action20l_work_root=$(mktemp -d /tmp/caddy-action20l.XXXXXX) || exit 1
readonly action20l_work_root
trap 'rm -rf -- "$action20l_work_root"' EXIT
readonly version_stdout=$action20l_work_root/version.stdout
readonly version_stderr=$action20l_work_root/version.stderr
readonly version_combined=$action20l_work_root/version.combined
readonly bus_stdout=$action20l_work_root/bus.stdout
readonly bus_stderr=$action20l_work_root/bus.stderr
readonly before_snapshot=$action20l_work_root/state.before
readonly after_snapshot=$action20l_work_root/state.after
install -m 0600 /dev/null "$version_stdout" || exit 1
install -m 0600 /dev/null "$version_stderr" || exit 1
install -m 0600 /dev/null "$version_combined" || exit 1
install -m 0600 /dev/null "$bus_stdout" || exit 1
install -m 0600 /dev/null "$bus_stderr" || exit 1
install -m 0600 /dev/null "$before_snapshot" || exit 1
install -m 0600 /dev/null "$after_snapshot" || exit 1

state_snapshot >"$before_snapshot"
action20l_keepalived_pid_before=$(systemctl show keepalived.service --property MainPID --value 2>/dev/null || true)
readonly action20l_keepalived_pid_before
action20l_keepalived_restarts_before=$(systemctl show keepalived.service --property NRestarts --value 2>/dev/null || true)
readonly action20l_keepalived_restarts_before

action20l_version_status=0
/usr/sbin/keepalived --version >"$version_stdout" 2>"$version_stderr" || action20l_version_status=$?
readonly action20l_version_status
cat "$version_stdout" "$version_stderr" >"$version_combined"
action20l_bus_status=0
/usr/bin/timeout 5 /usr/bin/busctl --system --no-pager --no-legend list \
    >"$bus_stdout" 2>"$bus_stderr" || action20l_bus_status=$?
readonly action20l_bus_status

record_check identity_root test "$(id -u)" -eq 0
record_check working_directory_root test "$(pwd -P)" = /
record_check hostname_exact test "$(hostname)" = "$expected_hostname"
record_check architecture_arm64 test "$(dpkg --print-architecture)" = arm64
record_check main_regular test -f "$main_configuration"
record_check main_not_symlink test ! -L "$main_configuration"
record_check main_metadata_exact test "$(stat -c '%U:%G:%a' "$main_configuration" 2>/dev/null || true)" = root:root:644
record_check main_hash_exact test "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$expected_main_sha256"
record_check main_enable_dbus_absent test "$(grep -Ec '^[[:space:]]*enable_dbus([[:space:]]|$)' "$main_configuration" 2>/dev/null || true)" -eq 0
record_check main_dbus_service_name_absent test "$(grep -Ec '^[[:space:]]*dbus_service_name([[:space:]]|$)' "$main_configuration" 2>/dev/null || true)" -eq 0
record_check fragment_regular test -f "$fragment"
record_check fragment_not_symlink test ! -L "$fragment"
record_check fragment_metadata_exact test "$(stat -c '%U:%G:%a' "$fragment" 2>/dev/null || true)" = root:root:644
record_check fragment_hash_exact test "$(file_hash "$fragment" 2>/dev/null || true)" = "$expected_fragment_sha256"
record_check health_regular test -f "$health_helper"
record_check health_not_symlink test ! -L "$health_helper"
record_check health_metadata_exact test "$(stat -c '%U:%G:%a' "$health_helper" 2>/dev/null || true)" = root:caddy-tls:750
record_check health_hash_exact test "$(file_hash "$health_helper" 2>/dev/null || true)" = "$health_sha256"
record_check keepalived_active_before systemctl is-active --quiet keepalived.service
record_check caddy_active_before systemctl is-active --quiet caddy.service
record_check lighttpd_active_before systemctl is-active --quiet lighttpd.service
record_check keepalived_pid_numeric_before test "$action20l_keepalived_pid_before" -gt 0
record_check keepalived_restarts_numeric_before test "$action20l_keepalived_restarts_before" -ge 0
record_check vrrp_state_exact_before test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = "$expected_vrrp_state"
record_check caddy_ipv4_count_exact_before test "$(address_count 4 "$caddy_ipv4_cidr")" -eq "$expected_caddy_vip_count"
record_check caddy_ipv6_count_exact_before test "$(address_count 6 "$caddy_ipv6_cidr")" -eq "$expected_caddy_vip_count"
record_check dns_ipv4_count_exact_before test "$(address_count 4 "$dns_ipv4_cidr")" -eq "$expected_dns_vip_count"
record_check dns_ipv6_count_exact_before test "$(address_count 6 "$dns_ipv6_cidr")" -eq "$expected_dns_vip_count"
record_check keepalived_binary_executable test -x /usr/sbin/keepalived
record_check busctl_binary_executable test -x /usr/bin/busctl
record_check system_bus_socket_present test -S /run/dbus/system_bus_socket
record_check keepalived_version_status_zero test "$action20l_version_status" -eq 0
record_check keepalived_version_stdout_safe safe_capture "$version_stdout"
record_check keepalived_version_stderr_safe safe_capture "$version_stderr"
record_check keepalived_version_output_present test -s "$version_combined"
record_check keepalived_product_line_present grep -Eq '^Keepalived v[^[:space:]]+' "$version_combined"
record_check keepalived_config_options_line_present grep -Eq '^Config options:' "$version_combined"
record_check keepalived_dbus_build_feature_present version_has_dbus "$version_combined"
record_check system_bus_query_status_zero test "$action20l_bus_status" -eq 0
record_check system_bus_query_stdout_safe safe_capture "$bus_stdout"
record_check system_bus_query_stderr_safe safe_capture "$bus_stderr"
record_check system_bus_query_output_present test -s "$bus_stdout"
record_check system_bus_daemon_name_present grep -Eq '^org\.freedesktop\.DBus[[:space:]]' "$bus_stdout"
record_check keepalived_active_after systemctl is-active --quiet keepalived.service
record_check keepalived_pid_unchanged test "$(systemctl show keepalived.service --property MainPID --value 2>/dev/null || true)" = "$action20l_keepalived_pid_before"
record_check keepalived_restarts_unchanged test "$(systemctl show keepalived.service --property NRestarts --value 2>/dev/null || true)" = "$action20l_keepalived_restarts_before"
record_check vrrp_state_exact_after test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = "$expected_vrrp_state"
# The child Bash expands its positional parameters.
# shellcheck disable=SC2016
record_check vip_ownership_exact_after bash -c \
    '[[ "$1" -eq "$5" && "$2" -eq "$5" && "$3" -eq "$6" && "$4" -eq "$6" ]]' _ \
    "$(address_count 4 "$caddy_ipv4_cidr")" "$(address_count 6 "$caddy_ipv6_cidr")" \
    "$(address_count 4 "$dns_ipv4_cidr")" "$(address_count 6 "$dns_ipv6_cidr")" \
    "$expected_caddy_vip_count" "$expected_dns_vip_count"
state_snapshot >"$after_snapshot"
record_check state_snapshot_unchanged cmp -s "$before_snapshot" "$after_snapshot"

emit_encoded_capture version_stdout "$version_stdout"
emit_encoded_capture version_stderr "$version_stderr"
emit_encoded_capture bus_stdout "$bus_stdout"
emit_encoded_capture bus_stderr "$bus_stderr"
printf '%s_value_node=%s\n' "$prefix" "$node_role"
printf '%s_value_expected_check_count=%s\n' "$prefix" "$expected_check_count"
printf '%s_value_main_sha256=%s\n' "$prefix" "$expected_main_sha256"
printf '%s_value_fragment_sha256=%s\n' "$prefix" "$expected_fragment_sha256"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$(file_hash "$before_snapshot")"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$(file_hash "$after_snapshot")"
printf '%s_check_count=%s\n' "$prefix" "$expected_check_count"
printf '%s_failed_check_count=%s\n' "$prefix" "$action20l_failed_check_count"
printf '%s_first_failure=%s\n' "$prefix" "$action20l_first_failure"
printf '%s_keepalived_dbus_registration_checked=false\n' "$prefix"
printf '%s_config_installation=false\n' "$prefix"
printf '%s_keepalived_reload=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

[[ "$action20l_failed_check_count" -eq 0 ]]
