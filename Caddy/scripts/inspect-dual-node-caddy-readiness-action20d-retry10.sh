#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_readiness_probe
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly notification_script=/usr/local/libexec/lsyncd-ha-failover-notify.sh
readonly notification_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8
readonly state_directory=/run/caddy-ha
readonly dedupe_directory=/run/caddy-ha-notify
readonly execution_user=pi
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
address_count() {
    local address_family=$1
    local expected_cidr=$2

    ip -o "-$address_family" address show dev eth0 2>/dev/null |
        awk -v expected="$expected_cidr" '$4 == expected { count++ }
            END { print count + 0 }'
}
directory_metadata() {
    local directory_path=$1

    if [[ -d "$directory_path" && ! -L "$directory_path" ]]; then
        stat -c '%U:%G:%a' "$directory_path"
    else
        printf 'absent-or-invalid\n'
    fi
}
snapshot_state() {
    local unit_name

    printf 'main=%s\n' "$(file_hash "$main_configuration" 2>/dev/null || true)"
    printf 'fragment=%s\n' "$(file_hash "$fragment" 2>/dev/null || true)"
    printf 'helper=%s\n' "$(file_hash "$notification_script" 2>/dev/null || true)"
    printf 'state_directory=%s\n' "$(directory_metadata "$state_directory")"
    printf 'dedupe_directory=%s\n' "$(directory_metadata "$dedupe_directory")"
    printf 'addresses=%s:%s:%s:%s\n' \
        "$(address_count 4 "$caddy_ipv4_cidr")" \
        "$(address_count 6 "$caddy_ipv6_cidr")" \
        "$(address_count 4 "$dns_ipv4_cidr")" \
        "$(address_count 6 "$dns_ipv6_cidr")"
    for unit_name in keepalived.service caddy.service lighttpd.service; do
        printf 'unit=%s:%s:%s:%s\n' "$unit_name" \
            "$(systemctl is-active "$unit_name" 2>/dev/null || true)" \
            "$(systemctl show -p MainPID --value "$unit_name" 2>/dev/null || true)" \
            "$(systemctl show -p NRestarts --value "$unit_name" 2>/dev/null || true)"
    done
}
expected_assertions() {
    printf '%s\n' \
        identity_root working_directory_root node_role_exact hostname_exact \
        main_regular main_not_symlink main_metadata_exact main_hash_exact \
        inherited_script_user_exact fragment_regular fragment_not_symlink \
        fragment_metadata_exact fragment_hash_exact notify_directive_exact \
        notify_directive_has_no_inline_user execution_user_exists \
        execution_user_identity_exact helper_regular helper_not_symlink \
        helper_metadata_exact helper_hash_exact helper_executable_as_pi \
        helper_state_path_exact helper_dedupe_path_exact \
        state_directory_exists state_directory_not_symlink \
        state_directory_readable_as_pi state_directory_writable_as_pi \
        state_directory_searchable_as_pi dedupe_directory_exists \
        dedupe_directory_not_symlink dedupe_directory_readable_as_pi \
        dedupe_directory_writable_as_pi dedupe_directory_searchable_as_pi \
        keepalived_active caddy_active lighttpd_active \
        caddy_ipv4_vip_absent caddy_ipv6_vip_absent \
        dns_ipv4_vip_role_exact dns_ipv6_vip_role_exact \
        before_snapshot_complete after_snapshot_complete state_unchanged
}
record_assertion() {
    local assertion_label=$1

    shift
    if "$@"; then
        printf '%s_assertion_%s=true\n' "$prefix" "$assertion_label"
        return 0
    fi
    printf '%s_assertion_%s=false\n' "$prefix" "$assertion_label"
    return 1
}
self_test_assertion() {
    local self_test_label=$1

    shift
    if "$@"; then
        printf '%s_self_test_assertion_%s=true\n' "$prefix" "$self_test_label"
        return 0
    fi
    printf '%s_self_test_assertion_%s=false\n' "$prefix" "$self_test_label" >&2
    return 1
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]] || exit 64
        expected_assertions
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test_count=$(expected_assertions | wc -l)
        readonly self_test_count
        self_test_assertion inventory_count test "$self_test_count" -eq 44
        self_test_assertion inventory_unique test \
            "$(expected_assertions | LC_ALL=C sort -u | wc -l)" -eq 44
        self_test_assertion labels_valid test \
            "$(expected_assertions | grep -Evc '^[a-z0-9_]+$')" -eq 0
        # The grep pattern intentionally matches literal variable references.
        # shellcheck disable=SC2016
        self_test_assertion notifier_not_invoked test \
            "$(grep -Fxc 'runuser -u "$execution_user" -- "$notification_script"' "$0")" -eq 0
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --node)
        [[ $# -eq 2 ]] || exit 64
        node_role=$2
        ;;
    *)
        printf 'Usage: %s --expected-assertions|--self-test|--node node-a|node-b\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

case "$node_role" in
    node-a)
        expected_hostname=j1-svpihole0
        expected_main_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
        expected_fragment_sha256=6f5a58ca8fd39a1218de6fc964f54aef69f374351c0727bbb0fabf899a80ef39
        expected_dns_vip_count=1
        ;;
    node-b)
        expected_hostname=j1-svpihole00
        expected_main_sha256=e8473427d9fe167777ca910d740035d5a73b27f9f909999a8d32c5a0a60722b6
        expected_fragment_sha256=294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d
        expected_dns_vip_count=0
        ;;
    *)
        printf 'Unknown node role: %s\n' "$node_role" >&2
        exit 64
        ;;
esac
readonly node_role expected_hostname expected_main_sha256
readonly expected_fragment_sha256 expected_dns_vip_count

before_snapshot=$(snapshot_state)
before_snapshot_status=$?
readonly before_snapshot before_snapshot_status
before_snapshot_sha256=$(printf '%s\n' "$before_snapshot" | sha256sum | awk '{ print $1 }')
readonly before_snapshot_sha256

failed_assertion_count=0
first_failure=none
run_assertion() {
    local run_label=$1

    shift
    if ! record_assertion "$run_label" "$@"; then
        failed_assertion_count=$((failed_assertion_count + 1))
        if [[ "$first_failure" = none ]]; then
            first_failure=$run_label
        fi
    fi
}

run_assertion identity_root test "$(id -u)" -eq 0
run_assertion working_directory_root test "$(pwd -P)" = /
run_assertion node_role_exact test "$node_role" = "$2"
run_assertion hostname_exact test "$(hostname)" = "$expected_hostname"
run_assertion main_regular test -f "$main_configuration"
run_assertion main_not_symlink test ! -L "$main_configuration"
run_assertion main_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$main_configuration" 2>/dev/null || true)" = root:root:644
run_assertion main_hash_exact test \
    "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$expected_main_sha256"
run_assertion inherited_script_user_exact test \
    "$(grep -Fxc '    script_user pi' "$main_configuration" 2>/dev/null || true)" -eq 1
run_assertion fragment_regular test -f "$fragment"
run_assertion fragment_not_symlink test ! -L "$fragment"
run_assertion fragment_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$fragment" 2>/dev/null || true)" = root:root:644
run_assertion fragment_hash_exact test \
    "$(file_hash "$fragment" 2>/dev/null || true)" = "$expected_fragment_sha256"
run_assertion notify_directive_exact test \
    "$(grep -Fxc '    notify "/usr/local/libexec/lsyncd-ha-failover-notify.sh"' "$fragment" 2>/dev/null || true)" -eq 1
run_assertion notify_directive_has_no_inline_user test \
    "$(grep -Ec '^[[:space:]]*notify[[:space:]]+"/usr/local/libexec/lsyncd-ha-failover-notify.sh"[[:space:]]+[[:alnum:]_-]+' "$fragment" 2>/dev/null || true)" -eq 0
run_assertion execution_user_exists test -n \
    "$(getent passwd "$execution_user" 2>/dev/null || true)"
run_assertion execution_user_identity_exact test \
    "$(getent passwd "$execution_user" 2>/dev/null | cut -d: -f1)" = "$execution_user"
run_assertion helper_regular test -f "$notification_script"
run_assertion helper_not_symlink test ! -L "$notification_script"
run_assertion helper_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$notification_script" 2>/dev/null || true)" = root:root:755
run_assertion helper_hash_exact test \
    "$(file_hash "$notification_script" 2>/dev/null || true)" = "$notification_sha256"
run_assertion helper_executable_as_pi runuser -u "$execution_user" -- test -x "$notification_script"
run_assertion helper_state_path_exact test \
    "$(grep -Fxc "readonly state_dir='$state_directory'" "$notification_script" 2>/dev/null || true)" -eq 1
run_assertion helper_dedupe_path_exact test \
    "$(grep -Fxc "readonly dedupe_dir='$dedupe_directory'" "$notification_script" 2>/dev/null || true)" -eq 1
run_assertion state_directory_exists test -d "$state_directory"
run_assertion state_directory_not_symlink test ! -L "$state_directory"
run_assertion state_directory_readable_as_pi runuser -u "$execution_user" -- test -r "$state_directory"
run_assertion state_directory_writable_as_pi runuser -u "$execution_user" -- test -w "$state_directory"
run_assertion state_directory_searchable_as_pi runuser -u "$execution_user" -- test -x "$state_directory"
run_assertion dedupe_directory_exists test -d "$dedupe_directory"
run_assertion dedupe_directory_not_symlink test ! -L "$dedupe_directory"
run_assertion dedupe_directory_readable_as_pi runuser -u "$execution_user" -- test -r "$dedupe_directory"
run_assertion dedupe_directory_writable_as_pi runuser -u "$execution_user" -- test -w "$dedupe_directory"
run_assertion dedupe_directory_searchable_as_pi runuser -u "$execution_user" -- test -x "$dedupe_directory"
run_assertion keepalived_active test "$(systemctl is-active keepalived.service)" = active
run_assertion caddy_active test "$(systemctl is-active caddy.service)" = active
run_assertion lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
caddy_ipv4_count=$(address_count 4 "$caddy_ipv4_cidr")
caddy_ipv6_count=$(address_count 6 "$caddy_ipv6_cidr")
dns_ipv4_count=$(address_count 4 "$dns_ipv4_cidr")
dns_ipv6_count=$(address_count 6 "$dns_ipv6_cidr")
readonly caddy_ipv4_count caddy_ipv6_count dns_ipv4_count dns_ipv6_count
run_assertion caddy_ipv4_vip_absent test "$caddy_ipv4_count" -eq 0
run_assertion caddy_ipv6_vip_absent test "$caddy_ipv6_count" -eq 0
run_assertion dns_ipv4_vip_role_exact test "$dns_ipv4_count" -eq "$expected_dns_vip_count"
run_assertion dns_ipv6_vip_role_exact test "$dns_ipv6_count" -eq "$expected_dns_vip_count"
run_assertion before_snapshot_complete test "$before_snapshot_status" -eq 0
after_snapshot=$(snapshot_state)
after_snapshot_status=$?
readonly after_snapshot after_snapshot_status
after_snapshot_sha256=$(printf '%s\n' "$after_snapshot" | sha256sum | awk '{ print $1 }')
readonly after_snapshot_sha256
run_assertion after_snapshot_complete test "$after_snapshot_status" -eq 0
run_assertion state_unchanged test "$before_snapshot_sha256" = "$after_snapshot_sha256"

printf '%s_value_node_role=%s\n' "$prefix" "$node_role"
printf '%s_value_inherited_execution_user=%s\n' "$prefix" "$execution_user"
printf '%s_value_state_directory_metadata=%s\n' "$prefix" "$(directory_metadata "$state_directory")"
printf '%s_value_dedupe_directory_metadata=%s\n' "$prefix" "$(directory_metadata "$dedupe_directory")"
printf '%s_value_caddy_ipv4_vip_count=%s\n' "$prefix" "$caddy_ipv4_count"
printf '%s_value_caddy_ipv6_vip_count=%s\n' "$prefix" "$caddy_ipv6_count"
printf '%s_value_dns_ipv4_vip_count=%s\n' "$prefix" "$dns_ipv4_count"
printf '%s_value_dns_ipv6_vip_count=%s\n' "$prefix" "$dns_ipv6_count"
printf '%s_value_before_snapshot_sha256=%s\n' "$prefix" "$before_snapshot_sha256"
printf '%s_value_after_snapshot_sha256=%s\n' "$prefix" "$after_snapshot_sha256"
printf '%s_assertion_count=%s\n' "$prefix" "$(expected_assertions | wc -l)"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_assertion_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_notification_helper_invoked=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_keepalived_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_network_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

[[ "$failed_assertion_count" -eq 0 ]]
