#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_a_probe
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly health_helper=/usr/local/libexec/check-caddy.sh
readonly notification_helper=/usr/local/libexec/lsyncd-ha-failover-notify.sh
readonly environment_file=/etc/default/caddy-ha
readonly backup_root=/var/backups/caddy-ha
readonly node_a_backup=/var/backups/caddy-ha/action20d-retry10-node-a-caddy-vrrp.dTSW20
readonly include_record='include /etc/keepalived/conf.d/caddy-ha.conf'
readonly health_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly notification_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8
readonly environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
address_count() {
    local address_family=$1
    local expected_cidr=$2

    ip -o "-$address_family" address show dev eth0 2>/dev/null |
        awk -v expected="$expected_cidr" '$4 == expected { count++ }
            END { print count + 0 }'
}
tree_hash() {
    local tree_root=$1

    if [[ ! -d "$tree_root" ]]; then
        printf 'absent\n'
        return 0
    fi
    (
        cd "$tree_root"
        find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}
unit_state() {
    local unit_name=$1

    printf '%s:%s:%s:%s' \
        "$(systemctl is-active "$unit_name" 2>/dev/null || true)" \
        "$(systemctl is-enabled "$unit_name" 2>/dev/null || true)" \
        "$(systemctl show -p MainPID --value "$unit_name" 2>/dev/null || true)" \
        "$(systemctl show -p NRestarts --value "$unit_name" 2>/dev/null || true)"
}
snapshot_state() {
    printf 'main=%s\n' "$(file_hash "$main_configuration" 2>/dev/null || true)"
    printf 'fragment=%s\n' "$(file_hash "$fragment" 2>/dev/null || true)"
    printf 'health=%s\n' "$(file_hash "$health_helper" 2>/dev/null || true)"
    printf 'notification=%s\n' "$(file_hash "$notification_helper" 2>/dev/null || true)"
    printf 'environment=%s\n' "$(file_hash "$environment_file" 2>/dev/null || true)"
    printf 'backup=%s\n' "$(tree_hash "$node_a_backup")"
    printf 'addresses=%s:%s:%s:%s\n' \
        "$(address_count 4 "$caddy_ipv4_cidr")" \
        "$(address_count 6 "$caddy_ipv6_cidr")" \
        "$(address_count 4 "$dns_ipv4_cidr")" \
        "$(address_count 6 "$dns_ipv6_cidr")"
    printf 'vrrp_state=%s\n' "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)"
    printf 'keepalived=%s\n' "$(unit_state keepalived.service)"
    printf 'caddy=%s\n' "$(unit_state caddy.service)"
    printf 'lighttpd=%s\n' "$(unit_state lighttpd.service)"
    printf 'lsyncd=%s\n' "$(unit_state lsyncd.service)"
}
expected_assertions() {
    printf '%s\n' \
        identity_root working_directory_root node_role_exact hostname_exact \
        main_regular main_not_symlink main_metadata_exact main_hash_exact \
        main_include_count_exact fragment_regular fragment_not_symlink \
        fragment_metadata_exact fragment_hash_exact fragment_health_user_exact \
        fragment_notify_exact health_regular health_not_symlink \
        health_metadata_exact health_hash_exact environment_regular \
        environment_not_symlink environment_metadata_exact environment_hash_exact \
        notification_regular notification_not_symlink notification_metadata_exact \
        notification_hash_exact keepalived_active caddy_active lighttpd_active \
        lsyncd_inactive caddy_ipv4_count_exact caddy_ipv6_count_exact \
        dns_ipv4_count_exact dns_ipv6_count_exact vrrp_contract_exact \
        retry10_backup_count_exact retry10_backup_contract_exact \
        retry10_run_residue_absent retry10_tmp_residue_absent \
        before_snapshot_complete health_status_zero health_stdout_safe \
        health_stderr_safe health_transient_residue_absent \
        after_snapshot_complete state_unchanged
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
safe_stream() {
    local inspected_stream=$1

    [[ "$(wc -c <"$inspected_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$inspected_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$inspected_stream"
}
emit_stream() {
    local stream_label=$1
    local stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_label" "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_label" "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_label" "$(file_hash "$stream_path")"
    if safe_stream "$stream_path"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$stream_label"
        if [[ -s "$stream_path" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$stream_label"
            cat "$stream_path"
            printf '%s_%s_end\n' "$prefix" "$stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$stream_label" >&2
    return 97
}
validate_node_a_backup() {
    [[ -d "$node_a_backup" && ! -L "$node_a_backup" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$node_a_backup")" = root:root:700 ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$node_a_backup/keepalived.conf.before")" = root:root:600 ]] || return 1
    [[ "$(file_hash "$node_a_backup/keepalived.conf.before")" = cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2 ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$node_a_backup/manifest")" = root:root:600 ]] || return 1
    [[ "$(wc -l <"$node_a_backup/manifest")" -eq 7 ]] || return 1
    grep -Fqx 'action=20d-retry10' "$node_a_backup/manifest" || return 1
    grep -Fqx 'node=node-a' "$node_a_backup/manifest" || return 1
    grep -Fqx 'main_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2' "$node_a_backup/manifest" || return 1
    grep -Fqx 'main_owner=root' "$node_a_backup/manifest" || return 1
    grep -Fqx 'main_group=root' "$node_a_backup/manifest" || return 1
    grep -Fqx 'main_mode=0644' "$node_a_backup/manifest" || return 1
    grep -Fqx "include_record=$include_record" "$node_a_backup/manifest"
}
validate_backup_contract() {
    if [[ "$node_role" = node-a ]]; then
        validate_node_a_backup
        return
    fi
    [[ ! -e "$node_a_backup" && ! -L "$node_a_backup" ]]
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]] || exit 64
        expected_assertions
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$(expected_assertions | wc -l)" -eq 47 ]]
        [[ "$(expected_assertions | LC_ALL=C sort -u | wc -l)" -eq 47 ]]
        [[ "$(expected_assertions | grep -Evc '^[a-z0-9_]+$')" -eq 0 ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --node)
        [[ $# -eq 2 ]] || exit 64
        node_role=$2
        ;;
    *)
        printf 'Usage: %s --expected-assertions|--self-test|--node node-a|node-b\n' "${0##*/}" >&2
        exit 64
        ;;
esac

case "$node_role" in
    node-a)
        expected_hostname=j1-svpihole0
        expected_main_sha256=357eb09c628fa3b78efcaacf53278ab09a6574b991820632ee3ec2614265d8e2
        expected_fragment_sha256=6f5a58ca8fd39a1218de6fc964f54aef69f374351c0727bbb0fabf899a80ef39
        expected_health_user='    user keepalived_script caddy-tls'
        expected_include_count=1
        expected_caddy_count=1
        expected_dns_count=1
        expected_vrrp_state=MASTER
        expected_backup_count=1
        ;;
    node-b)
        expected_hostname=j1-svpihole00
        expected_main_sha256=e8473427d9fe167777ca910d740035d5a73b27f9f909999a8d32c5a0a60722b6
        expected_fragment_sha256=294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d
        expected_health_user='    user keepalived_script'
        expected_include_count=0
        expected_caddy_count=0
        expected_dns_count=0
        expected_vrrp_state=inactive_fragment
        expected_backup_count=0
        ;;
    *) exit 64 ;;
esac
readonly node_role expected_hostname expected_main_sha256 expected_fragment_sha256
readonly expected_health_user expected_include_count expected_caddy_count
readonly expected_dns_count expected_vrrp_state expected_backup_count

work_root=$(mktemp -d /run/caddy-action20d-retry10-a-inspect.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT
readonly health_stdout=$work_root/health.stdout
readonly health_stderr=$work_root/health.stderr
: >"$health_stdout"
: >"$health_stderr"
chmod 0600 "$health_stdout" "$health_stderr"

before_snapshot=$(snapshot_state)
before_snapshot_status=$?
before_snapshot_sha256=$(printf '%s\n' "$before_snapshot" | sha256sum | awk '{ print $1 }')
readonly before_snapshot before_snapshot_status before_snapshot_sha256

health_status=0
"$health_helper" >"$health_stdout" 2>"$health_stderr" || health_status=$?
readonly health_status
emit_stream health_stdout "$health_stdout"
emit_stream health_stderr "$health_stderr"

failed_assertion_count=0
first_failure=none
run_assertion() {
    local run_label=$1

    shift
    if ! record_assertion "$run_label" "$@"; then
        failed_assertion_count=$((failed_assertion_count + 1))
        if [[ "$first_failure" = none ]]; then first_failure=$run_label; fi
    fi
}

run_assertion identity_root test "$(id -u)" -eq 0
run_assertion working_directory_root test "$(pwd -P)" = /
run_assertion node_role_exact test "$node_role" = "$2"
run_assertion hostname_exact test "$(hostname -s)" = "$expected_hostname"
run_assertion main_regular test -f "$main_configuration"
run_assertion main_not_symlink test ! -L "$main_configuration"
run_assertion main_metadata_exact test "$(stat -c '%U:%G:%a' "$main_configuration" 2>/dev/null || true)" = root:root:644
run_assertion main_hash_exact test "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$expected_main_sha256"
run_assertion main_include_count_exact test "$(grep -Fxc "$include_record" "$main_configuration" 2>/dev/null || true)" -eq "$expected_include_count"
run_assertion fragment_regular test -f "$fragment"
run_assertion fragment_not_symlink test ! -L "$fragment"
run_assertion fragment_metadata_exact test "$(stat -c '%U:%G:%a' "$fragment" 2>/dev/null || true)" = root:root:644
run_assertion fragment_hash_exact test "$(file_hash "$fragment" 2>/dev/null || true)" = "$expected_fragment_sha256"
run_assertion fragment_health_user_exact test "$(grep -Fxc "$expected_health_user" "$fragment" 2>/dev/null || true)" -eq 1
run_assertion fragment_notify_exact test "$(grep -Fxc '    notify "/usr/local/libexec/lsyncd-ha-failover-notify.sh"' "$fragment" 2>/dev/null || true)" -eq 1
run_assertion health_regular test -f "$health_helper"
run_assertion health_not_symlink test ! -L "$health_helper"
run_assertion health_metadata_exact test "$(stat -c '%U:%G:%a' "$health_helper" 2>/dev/null || true)" = root:root:755
run_assertion health_hash_exact test "$(file_hash "$health_helper" 2>/dev/null || true)" = "$health_sha256"
run_assertion environment_regular test -f "$environment_file"
run_assertion environment_not_symlink test ! -L "$environment_file"
run_assertion environment_metadata_exact test "$(stat -c '%U:%G:%a' "$environment_file" 2>/dev/null || true)" = root:caddy-tls:640
run_assertion environment_hash_exact test "$(file_hash "$environment_file" 2>/dev/null || true)" = "$environment_sha256"
run_assertion notification_regular test -f "$notification_helper"
run_assertion notification_not_symlink test ! -L "$notification_helper"
run_assertion notification_metadata_exact test "$(stat -c '%U:%G:%a' "$notification_helper" 2>/dev/null || true)" = root:root:755
run_assertion notification_hash_exact test "$(file_hash "$notification_helper" 2>/dev/null || true)" = "$notification_sha256"
run_assertion keepalived_active test "$(systemctl is-active keepalived.service)" = active
run_assertion caddy_active test "$(systemctl is-active caddy.service)" = active
run_assertion lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
run_assertion lsyncd_inactive test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
run_assertion caddy_ipv4_count_exact test "$(address_count 4 "$caddy_ipv4_cidr")" -eq "$expected_caddy_count"
run_assertion caddy_ipv6_count_exact test "$(address_count 6 "$caddy_ipv6_cidr")" -eq "$expected_caddy_count"
run_assertion dns_ipv4_count_exact test "$(address_count 4 "$dns_ipv4_cidr")" -eq "$expected_dns_count"
run_assertion dns_ipv6_count_exact test "$(address_count 6 "$dns_ipv6_cidr")" -eq "$expected_dns_count"
if [[ "$node_role" = node-a ]]; then
    run_assertion vrrp_contract_exact test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = MASTER
else
    run_assertion vrrp_contract_exact test "$expected_include_count" -eq 0
fi
run_assertion retry10_backup_count_exact test \
    "$(find "$backup_root" -mindepth 1 -maxdepth 1 -type d -name 'action20d-retry10-node-a-caddy-vrrp.*' -printf . 2>/dev/null | wc -c)" -eq "$expected_backup_count"
run_assertion retry10_backup_contract_exact validate_backup_contract
run_assertion retry10_run_residue_absent test \
    "$(find /run -maxdepth 1 -name 'caddy-action20d-retry10-*' ! -path "$work_root" -printf . 2>/dev/null | wc -c)" -eq 0
run_assertion retry10_tmp_residue_absent test \
    "$(find /tmp -maxdepth 1 -name 'caddy-action20d-retry10-*' -printf . 2>/dev/null | wc -c)" -eq 0
run_assertion before_snapshot_complete test "$before_snapshot_status" -eq 0
run_assertion health_status_zero test "$health_status" -eq 0
run_assertion health_stdout_safe safe_stream "$health_stdout"
run_assertion health_stderr_safe safe_stream "$health_stderr"
run_assertion health_transient_residue_absent test \
    "$(find /tmp -maxdepth 1 -name 'caddy-health.*' -printf . 2>/dev/null | wc -c)" -eq 0

after_snapshot=$(snapshot_state)
after_snapshot_status=$?
after_snapshot_sha256=$(printf '%s\n' "$after_snapshot" | sha256sum | awk '{ print $1 }')
readonly after_snapshot after_snapshot_status after_snapshot_sha256
run_assertion after_snapshot_complete test "$after_snapshot_status" -eq 0
run_assertion state_unchanged test "$before_snapshot_sha256" = "$after_snapshot_sha256"

printf '%s_value_node_role=%s\n' "$prefix" "$node_role"
printf '%s_value_expected_vrrp_state=%s\n' "$prefix" "$expected_vrrp_state"
printf '%s_value_caddy_ipv4_count=%s\n' "$prefix" "$(address_count 4 "$caddy_ipv4_cidr")"
printf '%s_value_caddy_ipv6_count=%s\n' "$prefix" "$(address_count 6 "$caddy_ipv6_cidr")"
printf '%s_value_dns_ipv4_count=%s\n' "$prefix" "$(address_count 4 "$dns_ipv4_cidr")"
printf '%s_value_dns_ipv6_count=%s\n' "$prefix" "$(address_count 6 "$dns_ipv6_cidr")"
printf '%s_value_before_snapshot_sha256=%s\n' "$prefix" "$before_snapshot_sha256"
printf '%s_value_after_snapshot_sha256=%s\n' "$prefix" "$after_snapshot_sha256"
printf '%s_assertion_count=%s\n' "$prefix" "$(expected_assertions | wc -l)"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_assertion_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_health_helper_invoked=true\n' "$prefix"
printf '%s_notification_helper_invoked=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_keepalived_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_network_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_remote_cleanup_complete=true\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

rm -rf -- "$work_root"
trap - EXIT
[[ "$failed_assertion_count" -eq 0 ]]
