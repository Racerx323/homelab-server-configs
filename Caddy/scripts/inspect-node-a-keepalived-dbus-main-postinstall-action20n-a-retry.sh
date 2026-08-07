#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20n_a
readonly expected_hostname=j1-svpihole0
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly main_sha256=8fc9dcf8e079b7131f86a58038ae5543804a5158a02d53a4614452de212ce47c
readonly source_sha256=6162cfb9d83f7e524db1df6a3b041ced90a7639fceaf28eacf713270c2a66a65
readonly prior_main_sha256=357eb09c628fa3b78efcaacf53278ab09a6574b991820632ee3ec2614265d8e2
readonly include_record='include /etc/keepalived/conf.d/caddy-ha.conf'
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly fragment_sha256=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
readonly health_helper=/usr/local/libexec/check-caddy.sh
readonly health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly backup_directory=/var/backups/caddy-ha/action20n-node-a-dbus-main.s8Qkep
readonly backup_main=$backup_directory/keepalived.conf.before
readonly backup_manifest=$backup_directory/manifest
readonly vip_ipv4_cidr=10.1.0.56/22
readonly vip_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly expected_check_count=68

action20na_failed_check_count=0
action20na_first_failure=none

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
address_count() {
    local action20na_address_family=$1
    local action20na_expected_cidr=$2

    ip -o "-$action20na_address_family" address show dev eth0 2>/dev/null |
        awk -v expected="$action20na_expected_cidr" '$4 == expected { count++ }
            END { print count + 0 }'
}
matching_path_count() {
    local action20na_parent=$1
    local action20na_pattern=$2

    find "$action20na_parent" -mindepth 1 -maxdepth 1 -name "$action20na_pattern" \
        -print 2>/dev/null | awk 'END { print NR }'
}
expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact main_regular \
        main_not_symlink main_metadata main_hash_exact main_global_defs_once \
        main_enable_dbus_once main_enable_dbus_in_global_defs \
        main_dbus_service_name_absent main_include_once main_include_terminal \
        fragment_regular fragment_not_symlink fragment_metadata \
        fragment_hash_exact health_regular health_not_symlink health_metadata \
        health_hash_exact backup_directory_present backup_directory_not_symlink \
        backup_directory_metadata backup_main_regular backup_main_not_symlink \
        backup_main_metadata backup_main_hash_exact backup_manifest_regular \
        backup_manifest_not_symlink backup_manifest_metadata \
        backup_manifest_lines backup_manifest_action backup_manifest_node \
        backup_manifest_source backup_manifest_before backup_manifest_candidate \
        backup_count_exact runtime_stage_residue_absent_pre \
        install_stage_residue_absent_pre keepalived_active_before \
        caddy_active_before lighttpd_active_before keepalived_pid_numeric_before \
        keepalived_restarts_numeric_before vrrp_state_master_before \
        caddy_ipv4_count_before caddy_ipv6_count_before dns_ipv4_count_before \
        dns_ipv6_count_before keepalived_active_after caddy_active_after \
        lighttpd_active_after keepalived_pid_unchanged \
        keepalived_restarts_unchanged vrrp_state_master_after \
        caddy_ipv4_count_after caddy_ipv6_count_after dns_ipv4_count_after \
        dns_ipv6_count_after main_hash_unchanged fragment_hash_unchanged \
        health_hash_unchanged backup_main_hash_unchanged \
        backup_manifest_hash_unchanged runtime_stage_residue_absent_post \
        install_stage_residue_absent_post state_snapshot_unchanged
}
record_check() {
    local action20na_check_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20na_check_label"
    else
        printf '%s_check_%s=false\n' "$prefix" "$action20na_check_label"
        action20na_failed_check_count=$((action20na_failed_check_count + 1))
        if [[ "$action20na_first_failure" = none ]]; then
            action20na_first_failure=$action20na_check_label
        fi
    fi
    return 0
}
global_defs_contains_enable_dbus() {
    local action20na_configuration_path=$1

    awk '
        /^[[:space:]]*global_defs[[:space:]]*\{/ { in_global=1; blocks++; next }
        in_global && /^[[:space:]]*enable_dbus([[:space:]]|$)/ { found++ }
        in_global && /^[[:space:]]*\}[[:space:]]*$/ { in_global=0 }
        END { exit(blocks == 1 && found == 1 ? 0 : 1) }
    ' "$action20na_configuration_path"
}
runtime_residue_count() {
    matching_path_count /run 'caddy-action20n*'
}
install_residue_count() {
    matching_path_count /etc/keepalived '.keepalived.conf.action20n*'
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
    printf 'backup_directory=%s\n' \
        "$(stat -c '%U:%G:%a' "$backup_directory" 2>/dev/null || printf unavailable)"
    printf 'backup_main=%s|%s\n' \
        "$(stat -c '%U:%G:%a' "$backup_main" 2>/dev/null || printf unavailable)" \
        "$(file_hash "$backup_main" 2>/dev/null || printf unavailable)"
    printf 'backup_manifest=%s|%s\n' \
        "$(stat -c '%U:%G:%a' "$backup_manifest" 2>/dev/null || printf unavailable)" \
        "$(file_hash "$backup_manifest" 2>/dev/null || printf unavailable)"
    printf 'keepalived=%s|%s|%s\n' \
        "$(systemctl is-active keepalived.service 2>/dev/null || printf unavailable)" \
        "$(systemctl show keepalived.service --property MainPID --value 2>/dev/null || printf unavailable)" \
        "$(systemctl show keepalived.service --property NRestarts --value 2>/dev/null || printf unavailable)"
    printf 'caddy=%s\n' "$(systemctl is-active caddy.service 2>/dev/null || printf unavailable)"
    printf 'lighttpd=%s\n' "$(systemctl is-active lighttpd.service 2>/dev/null || printf unavailable)"
    printf 'vrrp=%s\n' "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || printf unavailable)"
    printf 'vips=%s|%s|%s|%s\n' \
        "$(address_count 4 "$vip_ipv4_cidr")" "$(address_count 6 "$vip_ipv6_cidr")" \
        "$(address_count 4 "$dns_ipv4_cidr")" "$(address_count 6 "$dns_ipv6_cidr")"
    printf 'residue=%s|%s\n' "$(runtime_residue_count)" "$(install_residue_count)"
}
self_test() {
    local action20na_fixture_root
    local action20na_fixture_main

    [[ "$(expected_checks | wc -l)" -eq "$expected_check_count" ]] || return 1
    [[ "$(expected_checks | LC_ALL=C sort -u | wc -l)" -eq "$expected_check_count" ]] || return 1
    [[ "$(expected_checks | grep -Evc '^[a-z0-9_]+$')" -eq 0 ]] || return 1
    action20na_fixture_root=$(mktemp -d /tmp/caddy-action20n-a-self.XXXXXX) || return 1
    trap 'rm -rf -- "$action20na_fixture_root"' RETURN
    action20na_fixture_main=$action20na_fixture_root/keepalived.conf
    printf '%s\n' 'global_defs {' '    enable_dbus' '}' '' "$include_record" >"$action20na_fixture_main"
    global_defs_contains_enable_dbus "$action20na_fixture_main" || return 1
    [[ "$(tail -n 1 "$action20na_fixture_main")" = "$include_record" ]] || return 1
    sed '/enable_dbus/d' "$action20na_fixture_main" >"$action20na_fixture_root/missing"
    if global_defs_contains_enable_dbus "$action20na_fixture_root/missing"; then
        return 1
    fi
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
    "")
        [[ $# -eq 0 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s [--expected-checks|--self-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

action20na_keepalived_pid_before=$(systemctl show keepalived.service --property MainPID --value 2>/dev/null || true)
readonly action20na_keepalived_pid_before
action20na_keepalived_restarts_before=$(systemctl show keepalived.service --property NRestarts --value 2>/dev/null || true)
readonly action20na_keepalived_restarts_before
action20na_backup_manifest_sha256=$(file_hash "$backup_manifest" 2>/dev/null || true)
readonly action20na_backup_manifest_sha256
action20na_state_before=$(state_snapshot | sha256sum | awk '{ print $1 }')
readonly action20na_state_before

record_check identity_root test "$(id -u)" -eq 0
record_check working_directory_root test "$(pwd -P)" = /
record_check hostname_exact test "$(hostname)" = "$expected_hostname"
record_check main_regular test -f "$main_configuration"
record_check main_not_symlink test ! -L "$main_configuration"
record_check main_metadata test "$(stat -c '%U:%G:%a' "$main_configuration" 2>/dev/null || true)" = root:root:644
record_check main_hash_exact test "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$main_sha256"
record_check main_global_defs_once test "$(grep -Ec '^[[:space:]]*global_defs[[:space:]]*\{' "$main_configuration" 2>/dev/null || true)" -eq 1
record_check main_enable_dbus_once test "$(grep -Ec '^[[:space:]]*enable_dbus([[:space:]]|$)' "$main_configuration" 2>/dev/null || true)" -eq 1
record_check main_enable_dbus_in_global_defs global_defs_contains_enable_dbus "$main_configuration"
record_check main_dbus_service_name_absent test "$(grep -Ec '^[[:space:]]*dbus_service_name([[:space:]]|$)' "$main_configuration" 2>/dev/null || true)" -eq 0
record_check main_include_once test "$(grep -Fxc "$include_record" "$main_configuration" 2>/dev/null || true)" -eq 1
record_check main_include_terminal test "$(tail -n 1 "$main_configuration" 2>/dev/null || true)" = "$include_record"
record_check fragment_regular test -f "$fragment"
record_check fragment_not_symlink test ! -L "$fragment"
record_check fragment_metadata test "$(stat -c '%U:%G:%a' "$fragment" 2>/dev/null || true)" = root:root:644
record_check fragment_hash_exact test "$(file_hash "$fragment" 2>/dev/null || true)" = "$fragment_sha256"
record_check health_regular test -f "$health_helper"
record_check health_not_symlink test ! -L "$health_helper"
record_check health_metadata test "$(stat -c '%U:%G:%a' "$health_helper" 2>/dev/null || true)" = root:root:755
record_check health_hash_exact test "$(file_hash "$health_helper" 2>/dev/null || true)" = "$health_sha256"
record_check backup_directory_present test -d "$backup_directory"
record_check backup_directory_not_symlink test ! -L "$backup_directory"
record_check backup_directory_metadata test "$(stat -c '%U:%G:%a' "$backup_directory" 2>/dev/null || true)" = root:root:700
record_check backup_main_regular test -f "$backup_main"
record_check backup_main_not_symlink test ! -L "$backup_main"
record_check backup_main_metadata test "$(stat -c '%U:%G:%a' "$backup_main" 2>/dev/null || true)" = root:root:600
record_check backup_main_hash_exact test "$(file_hash "$backup_main" 2>/dev/null || true)" = "$prior_main_sha256"
record_check backup_manifest_regular test -f "$backup_manifest"
record_check backup_manifest_not_symlink test ! -L "$backup_manifest"
record_check backup_manifest_metadata test "$(stat -c '%U:%G:%a' "$backup_manifest" 2>/dev/null || true)" = root:root:600
record_check backup_manifest_lines test "$(awk 'END { print NR }' "$backup_manifest" 2>/dev/null || true)" -eq 5
record_check backup_manifest_action grep -Fqx action=20n "$backup_manifest"
record_check backup_manifest_node grep -Fqx node=node-a "$backup_manifest"
record_check backup_manifest_source grep -Fqx "source_sha256=$source_sha256" "$backup_manifest"
record_check backup_manifest_before grep -Fqx "before_sha256=$prior_main_sha256" "$backup_manifest"
record_check backup_manifest_candidate grep -Fqx "candidate_sha256=$main_sha256" "$backup_manifest"
record_check backup_count_exact test "$(matching_path_count /var/backups/caddy-ha 'action20n-node-a-dbus-main.*')" -eq 1
record_check runtime_stage_residue_absent_pre test "$(runtime_residue_count)" -eq 0
record_check install_stage_residue_absent_pre test "$(install_residue_count)" -eq 0
record_check keepalived_active_before systemctl is-active --quiet keepalived.service
record_check caddy_active_before systemctl is-active --quiet caddy.service
record_check lighttpd_active_before systemctl is-active --quiet lighttpd.service
record_check keepalived_pid_numeric_before test "$action20na_keepalived_pid_before" -gt 0
record_check keepalived_restarts_numeric_before test "$action20na_keepalived_restarts_before" -ge 0
record_check vrrp_state_master_before test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = MASTER
record_check caddy_ipv4_count_before test "$(address_count 4 "$vip_ipv4_cidr")" -eq 1
record_check caddy_ipv6_count_before test "$(address_count 6 "$vip_ipv6_cidr")" -eq 1
record_check dns_ipv4_count_before test "$(address_count 4 "$dns_ipv4_cidr")" -eq 1
record_check dns_ipv6_count_before test "$(address_count 6 "$dns_ipv6_cidr")" -eq 1
record_check keepalived_active_after systemctl is-active --quiet keepalived.service
record_check caddy_active_after systemctl is-active --quiet caddy.service
record_check lighttpd_active_after systemctl is-active --quiet lighttpd.service
record_check keepalived_pid_unchanged test "$(systemctl show keepalived.service --property MainPID --value 2>/dev/null || true)" = "$action20na_keepalived_pid_before"
record_check keepalived_restarts_unchanged test "$(systemctl show keepalived.service --property NRestarts --value 2>/dev/null || true)" = "$action20na_keepalived_restarts_before"
record_check vrrp_state_master_after test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = MASTER
record_check caddy_ipv4_count_after test "$(address_count 4 "$vip_ipv4_cidr")" -eq 1
record_check caddy_ipv6_count_after test "$(address_count 6 "$vip_ipv6_cidr")" -eq 1
record_check dns_ipv4_count_after test "$(address_count 4 "$dns_ipv4_cidr")" -eq 1
record_check dns_ipv6_count_after test "$(address_count 6 "$dns_ipv6_cidr")" -eq 1
record_check main_hash_unchanged test "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$main_sha256"
record_check fragment_hash_unchanged test "$(file_hash "$fragment" 2>/dev/null || true)" = "$fragment_sha256"
record_check health_hash_unchanged test "$(file_hash "$health_helper" 2>/dev/null || true)" = "$health_sha256"
record_check backup_main_hash_unchanged test "$(file_hash "$backup_main" 2>/dev/null || true)" = "$prior_main_sha256"
record_check backup_manifest_hash_unchanged test "$(file_hash "$backup_manifest" 2>/dev/null || true)" = "$action20na_backup_manifest_sha256"
record_check runtime_stage_residue_absent_post test "$(runtime_residue_count)" -eq 0
record_check install_stage_residue_absent_post test "$(install_residue_count)" -eq 0

action20na_state_after=$(state_snapshot | sha256sum | awk '{ print $1 }')
readonly action20na_state_after
record_check state_snapshot_unchanged test "$action20na_state_after" = "$action20na_state_before"

printf '%s_value_expected_check_count=%s\n' "$prefix" "$expected_check_count"
printf '%s_value_backup_path=%s\n' "$prefix" "$backup_directory"
printf '%s_value_main_sha256=%s\n' "$prefix" "$main_sha256"
printf '%s_value_backup_main_sha256=%s\n' "$prefix" "$prior_main_sha256"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$action20na_state_before"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$action20na_state_after"
printf '%s_check_count=%s\n' "$prefix" "$expected_check_count"
printf '%s_failed_check_count=%s\n' "$prefix" "$action20na_failed_check_count"
printf '%s_first_failure=%s\n' "$prefix" "$action20na_first_failure"
printf '%s_helper_execution=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

[[ "$action20na_failed_check_count" -eq 0 ]]
