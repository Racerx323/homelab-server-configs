#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_node
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly health_helper=/usr/local/libexec/check-caddy.sh
readonly notification_helper=/usr/local/libexec/lsyncd-ha-failover-notify.sh
readonly include_record='include /etc/keepalived/conf.d/caddy-ha.conf'
readonly backup_root=/var/backups/caddy-ha
readonly caddy_ipv4=10.1.0.56/22
readonly caddy_ipv6=fd36:5aa8:6971:1::56/128
readonly dns_ipv4=10.1.0.55/22
readonly dns_ipv6=fd36:5aa8:6971:1::55/128
readonly health_helper_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly notification_helper_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

transaction_complete=false
mutation_started=false
backup_directory=
node_role=
expected_hostname=
expected_main_sha256=
expected_fragment_sha256=
expected_vrrp_state=
expected_caddy_count=
expected_dns_count=
before_main_pid=
before_restarts=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
address_count() {
    local address_family=$1
    local address_cidr=$2

    ip -o "$address_family" address show dev eth0 |
        awk -v address="$address_cidr" '$4 == address { count++ } END { print count + 0 }'
}
expected_checks() {
    printf '%s\n' \
        root_user node_role hostname main_regular main_not_symlink \
        main_owner main_mode main_hash fragment_regular fragment_not_symlink \
        fragment_owner fragment_mode fragment_hash health_helper_regular \
        health_helper_not_symlink health_helper_metadata health_helper_hash \
        notification_helper_regular notification_helper_not_symlink \
        notification_helper_metadata notification_helper_hash \
        include_absent keepalived_active caddy_active lighttpd_active can_reload \
        health_pre caddy_ipv4_absent_pre caddy_ipv6_absent_pre \
        dns_ipv4_role_pre dns_ipv6_role_pre candidate_regular \
        candidate_include_once candidate_config_valid backup_created \
        backup_file_exact backup_manifest_exact main_installed reload_status \
        readiness_state_reached keepalived_active_post main_pid_unchanged \
        restart_count_unchanged main_include_once_post health_post expected_ipv4_state \
        expected_ipv6_state expected_vrrp_state dns_ipv4_unchanged \
        dns_ipv6_unchanged
}
expected_inspection_checks() {
    printf '%s\n' \
        root_user node_role hostname main_regular main_not_symlink \
        main_owner main_mode main_include_once fragment_hash \
        health_helper_regular health_helper_not_symlink \
        health_helper_metadata health_helper_hash notification_helper_regular \
        notification_helper_not_symlink notification_helper_metadata \
        notification_helper_hash keepalived_active \
        caddy_active lighttpd_active health expected_ipv4_state \
        expected_ipv6_state expected_vrrp_state dns_ipv4_unchanged \
        dns_ipv6_unchanged
}
record_check() {
    local check_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$check_label" >&2
    return 1
}
safe_stream() {
    local inspected_path=$1

    [[ "$(wc -c <"$inspected_path")" -le "$maximum_stream_bytes" ]] ||
        return 1
    [[ "$(line_count "$inspected_path")" -le "$maximum_stream_lines" ]] ||
        return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_path" >/dev/null ||
        return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$inspected_path"
}
emit_stream() {
    local stream_label=$1
    local stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_label" \
        "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_label" \
        "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_label" \
        "$(file_hash "$stream_path")"
    if ! safe_stream "$stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' \
            "$prefix" "$stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$stream_label"
    if [[ -s "$stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$stream_label"
        sed "s/^/${prefix}_${stream_label}_content=/" "$stream_path"
        printf '%s_%s_end\n' "$prefix" "$stream_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$stream_label"
    fi
}
run_captured() {
    local capture_label=$1
    local capture_root=$2
    local capture_status=0

    shift 2
    : >"$capture_root/$capture_label.stdout"
    : >"$capture_root/$capture_label.stderr"
    chmod 0600 "$capture_root/$capture_label.stdout" \
        "$capture_root/$capture_label.stderr"
    "$@" >"$capture_root/$capture_label.stdout" \
        2>"$capture_root/$capture_label.stderr" || capture_status=$?
    emit_stream "${capture_label}_stdout" \
        "$capture_root/$capture_label.stdout" || return 97
    emit_stream "${capture_label}_stderr" \
        "$capture_root/$capture_label.stderr" || return 97
    printf '%s_%s_status=%s\n' "$prefix" "$capture_label" "$capture_status"
    [[ "$capture_status" -eq 0 ]]
}
record_captured_check() {
    local captured_check_label=$1
    local captured_stream_label=$2
    local captured_root=$3

    shift 3
    if run_captured "$captured_stream_label" "$captured_root" "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$captured_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$captured_check_label" >&2
    return 1
}
configure_role() {
    case "$node_role" in
        node-a)
            expected_hostname=j1-svpihole0
            expected_main_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
            expected_fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5
            expected_vrrp_state=MASTER
            expected_caddy_count=1
            expected_dns_count=1
            ;;
        node-b)
            expected_hostname=j1-svpihole00
            expected_main_sha256=e8473427d9fe167777ca910d740035d5a73b27f9f909999a8d32c5a0a60722b6
            expected_fragment_sha256=294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d
            expected_vrrp_state=BACKUP
            expected_caddy_count=0
            expected_dns_count=0
            ;;
        *) return 64 ;;
    esac
    readonly expected_hostname expected_main_sha256 expected_fragment_sha256
    readonly expected_vrrp_state expected_caddy_count expected_dns_count
}
wait_for_role_state() {
    local wait_iteration

    for wait_iteration in $(seq 1 30); do
        if [[ "$(address_count -4 "$caddy_ipv4")" -eq "$expected_caddy_count" ]] &&
            [[ "$(address_count -6 "$caddy_ipv6")" -eq "$expected_caddy_count" ]] &&
            [[ -r /run/caddy-ha/vrrp-state ]] &&
            [[ "$(</run/caddy-ha/vrrp-state)" = "$expected_vrrp_state" ]]; then
            printf '%s_value_readiness_iteration=%s\n' "$prefix" "$wait_iteration"
            return 0
        fi
        sleep 1
    done
    return 1
}
rollback_local() {
    local rollback_capture_root=$1
    local rollback_ok=true

    printf '%s_rollback_started=true\n' "$prefix" >&2
    if [[ -n "$backup_directory" &&
        -f "$backup_directory/keepalived.conf.before" ]]; then
        install -o root -g root -m 0644 \
            "$backup_directory/keepalived.conf.before" "$main_configuration" ||
            rollback_ok=false
        run_captured rollback_reload "$rollback_capture_root" \
            systemctl reload keepalived.service || rollback_ok=false
        for _ in $(seq 1 15); do
            if [[ "$(address_count -4 "$caddy_ipv4")" -eq 0 &&
            "$(address_count -6 "$caddy_ipv6")" -eq 0 ]]; then
                break
            fi
            sleep 1
        done
        [[ "$(file_hash "$main_configuration")" = "$expected_main_sha256" ]] ||
            rollback_ok=false
        [[ "$(address_count -4 "$caddy_ipv4")" -eq 0 ]] || rollback_ok=false
        [[ "$(address_count -6 "$caddy_ipv6")" -eq 0 ]] || rollback_ok=false
    else
        rollback_ok=false
    fi
    if [[ "$rollback_ok" = true ]]; then
        printf '%s_rollback_complete=true\n' "$prefix" >&2
        return 0
    fi
    printf '%s_rollback_complete=false\n' "$prefix" >&2
    printf '%s_manual_intervention_required=true\n' "$prefix" >&2
    return 125
}
on_exit() {
    local exit_status=$?

    if [[ "$transaction_complete" != true && "$mutation_started" = true ]]; then
        rollback_local "${transaction_root:-/run}" || exit 125
    fi
    if [[ -n "${transaction_root:-}" && -d "$transaction_root" ]]; then
        rm -rf -- "$transaction_root"
    fi
    exit "$exit_status"
}
trap on_exit EXIT

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]] || exit 64
        expected_checks
        exit 0
        ;;
    --expected-inspection-checks)
        [[ $# -eq 1 ]] || exit 64
        expected_inspection_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$(expected_checks | wc -l)" -eq 50 ]]
        [[ "$(expected_checks | LC_ALL=C sort -u | wc -l)" -eq 50 ]]
        [[ "$(expected_inspection_checks | wc -l)" -eq 26 ]]
        [[ "$(expected_inspection_checks | LC_ALL=C sort -u | wc -l)" -eq 26 ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --activate)
        [[ $# -eq 2 ]] || exit 64
        node_role=$2
        readonly node_role
        configure_role
        ;;
    --inspect)
        [[ $# -eq 2 ]] || exit 64
        node_role=$2
        readonly node_role
        configure_role
        transaction_root=$(mktemp -d /run/caddy-action20d-inspect.XXXXXX)
        readonly transaction_root
        record_check root_user test "$(id -u)" -eq 0
        record_check node_role test "$node_role" = "${2:-}"
        record_check hostname test "$(hostname -s)" = "$expected_hostname"
        record_check main_regular test -f "$main_configuration"
        record_check main_not_symlink test ! -L "$main_configuration"
        record_check main_owner test "$(stat -c '%U:%G' "$main_configuration")" = root:root
        record_check main_mode test "$(stat -c '%a' "$main_configuration")" = 644
        record_check main_include_once test "$(grep -Fxc "$include_record" "$main_configuration")" -eq 1
        record_check fragment_hash test "$(file_hash "$fragment")" = "$expected_fragment_sha256"
        record_check health_helper_regular test -f "$health_helper"
        record_check health_helper_not_symlink test ! -L "$health_helper"
        record_check health_helper_metadata test "$(stat -c '%U:%G:%a' "$health_helper")" = root:root:755
        record_check health_helper_hash test "$(file_hash "$health_helper")" = "$health_helper_sha256"
        record_check notification_helper_regular test -f "$notification_helper"
        record_check notification_helper_not_symlink test ! -L "$notification_helper"
        record_check notification_helper_metadata test "$(stat -c '%U:%G:%a' "$notification_helper")" = root:root:755
        record_check notification_helper_hash test "$(file_hash "$notification_helper")" = "$notification_helper_sha256"
        record_check keepalived_active test "$(systemctl is-active keepalived.service)" = active
        record_check caddy_active test "$(systemctl is-active caddy.service)" = active
        record_check lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
        record_captured_check health inspect_health "$transaction_root" "$health_helper"
        record_check expected_ipv4_state test "$(address_count -4 "$caddy_ipv4")" -eq "$expected_caddy_count"
        record_check expected_ipv6_state test "$(address_count -6 "$caddy_ipv6")" -eq "$expected_caddy_count"
        record_check expected_vrrp_state test "$(</run/caddy-ha/vrrp-state)" = "$expected_vrrp_state"
        record_check dns_ipv4_unchanged test "$(address_count -4 "$dns_ipv4")" -eq "$expected_dns_count"
        record_check dns_ipv6_unchanged test "$(address_count -6 "$dns_ipv6")" -eq "$expected_dns_count"
        printf '%s_value_node_role=%s\n' "$prefix" "$node_role"
        printf '%s_value_vrrp_state=%s\n' "$prefix" "$expected_vrrp_state"
        printf '%s_value_caddy_ipv4_count=%s\n' "$prefix" "$expected_caddy_count"
        printf '%s_value_caddy_ipv6_count=%s\n' "$prefix" "$expected_caddy_count"
        printf '%s_value_dns_ipv4_count=%s\n' "$prefix" "$expected_dns_count"
        printf '%s_value_dns_ipv6_count=%s\n' "$prefix" "$expected_dns_count"
        printf '%s_filesystem_mutations=false\n' "$prefix"
        printf '%s_service_mutations=false\n' "$prefix"
        printf '%s_vrrp_mutations=false\n' "$prefix"
        printf '%s_vip_mutations=false\n' "$prefix"
        printf '%s_inspection_complete=true\n' "$prefix"
        transaction_complete=true
        rm -rf -- "$transaction_root"
        trap - EXIT
        exit 0
        ;;
    --rollback)
        [[ $# -eq 3 ]] || exit 64
        node_role=$2
        backup_directory=$3
        readonly node_role backup_directory
        configure_role
        transaction_root=$(mktemp -d /run/caddy-action20d-rollback.XXXXXX)
        readonly transaction_root
        rollback_local "$transaction_root"
        transaction_complete=true
        printf '%s_explicit_rollback_complete=true\n' "$prefix"
        rm -rf -- "$transaction_root"
        exit 0
        ;;
    *)
        printf 'Usage: %s --activate node-a|node-b | --inspect node-a|node-b | --rollback node-a|node-b BACKUP | --expected-checks | --expected-inspection-checks | --self-test\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

transaction_root=$(mktemp -d /run/caddy-action20d-node.XXXXXX)
readonly transaction_root
candidate_configuration=$transaction_root/keepalived.conf.candidate
readonly candidate_configuration

record_check root_user test "$(id -u)" -eq 0
record_check node_role test "$node_role" = "${2:-}"
record_check hostname test "$(hostname -s)" = "$expected_hostname"
record_check main_regular test -f "$main_configuration"
record_check main_not_symlink test ! -L "$main_configuration"
record_check main_owner test "$(stat -c '%U:%G' "$main_configuration")" = root:root
record_check main_mode test "$(stat -c '%a' "$main_configuration")" = 644
record_check main_hash test "$(file_hash "$main_configuration")" = "$expected_main_sha256"
record_check fragment_regular test -f "$fragment"
record_check fragment_not_symlink test ! -L "$fragment"
record_check fragment_owner test "$(stat -c '%U:%G' "$fragment")" = root:root
record_check fragment_mode test "$(stat -c '%a' "$fragment")" = 644
record_check fragment_hash test "$(file_hash "$fragment")" = "$expected_fragment_sha256"
record_check health_helper_regular test -f "$health_helper"
record_check health_helper_not_symlink test ! -L "$health_helper"
record_check health_helper_metadata test "$(stat -c '%U:%G:%a' "$health_helper")" = root:root:755
record_check health_helper_hash test "$(file_hash "$health_helper")" = "$health_helper_sha256"
record_check notification_helper_regular test -f "$notification_helper"
record_check notification_helper_not_symlink test ! -L "$notification_helper"
record_check notification_helper_metadata test "$(stat -c '%U:%G:%a' "$notification_helper")" = root:root:755
record_check notification_helper_hash test "$(file_hash "$notification_helper")" = "$notification_helper_sha256"
record_check include_absent test "$(grep -Fxc "$include_record" "$main_configuration" || true)" -eq 0
record_check keepalived_active test "$(systemctl is-active keepalived.service)" = active
record_check caddy_active test "$(systemctl is-active caddy.service)" = active
record_check lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
record_check can_reload test "$(systemctl show -p CanReload --value keepalived.service)" = yes
record_captured_check health_pre health_pre "$transaction_root" "$health_helper"
record_check caddy_ipv4_absent_pre test "$(address_count -4 "$caddy_ipv4")" -eq 0
record_check caddy_ipv6_absent_pre test "$(address_count -6 "$caddy_ipv6")" -eq 0
record_check dns_ipv4_role_pre test "$(address_count -4 "$dns_ipv4")" -eq "$expected_dns_count"
record_check dns_ipv6_role_pre test "$(address_count -6 "$dns_ipv6")" -eq "$expected_dns_count"

cp --preserve=mode,ownership,timestamps "$main_configuration" "$candidate_configuration"
printf '\n%s\n' "$include_record" >>"$candidate_configuration"
record_check candidate_regular test -f "$candidate_configuration"
record_check candidate_include_once test "$(grep -Fxc "$include_record" "$candidate_configuration")" -eq 1
record_captured_check candidate_config_valid candidate_config \
    "$transaction_root" \
    keepalived --dont-fork --config-test="$transaction_root/keepalived.log" \
    -f "$candidate_configuration"

install -d -o root -g root -m 0700 "$backup_root"
backup_directory=$(mktemp -d "$backup_root/action20d-${node_role}-caddy-vrrp.XXXXXX")
readonly backup_directory
install -o root -g root -m 0600 "$main_configuration" \
    "$backup_directory/keepalived.conf.before"
printf '%s\n' \
    'action=20d' \
    "node=$node_role" \
    "main_sha256=$expected_main_sha256" \
    'main_owner=root' \
    'main_group=root' \
    'main_mode=0644' \
    "include_record=$include_record" >"$backup_directory/manifest"
chmod 0600 "$backup_directory/manifest"
record_check backup_created test -d "$backup_directory"
record_check backup_file_exact cmp -s "$main_configuration" \
    "$backup_directory/keepalived.conf.before"
record_check backup_manifest_exact test "$(grep -Ec '^(action|node|main_sha256|main_owner|main_group|main_mode|include_record)=' "$backup_directory/manifest")" -eq 7

before_main_pid=$(systemctl show -p MainPID --value keepalived.service)
before_restarts=$(systemctl show -p NRestarts --value keepalived.service)
readonly before_main_pid before_restarts
mutation_started=true
printf '%s_mutation_started=true\n' "$prefix"
install -o root -g root -m 0644 "$candidate_configuration" "$main_configuration"
record_check main_installed test "$(grep -Fxc "$include_record" "$main_configuration")" -eq 1
record_captured_check reload_status reload "$transaction_root" \
    systemctl reload keepalived.service
record_check readiness_state_reached wait_for_role_state
record_check keepalived_active_post test "$(systemctl is-active keepalived.service)" = active
record_check main_pid_unchanged test "$(systemctl show -p MainPID --value keepalived.service)" = "$before_main_pid"
record_check restart_count_unchanged test "$(systemctl show -p NRestarts --value keepalived.service)" = "$before_restarts"
record_check main_include_once_post test "$(grep -Fxc "$include_record" "$main_configuration")" -eq 1
record_captured_check health_post health_post "$transaction_root" "$health_helper"
record_check expected_ipv4_state test "$(address_count -4 "$caddy_ipv4")" -eq "$expected_caddy_count"
record_check expected_ipv6_state test "$(address_count -6 "$caddy_ipv6")" -eq "$expected_caddy_count"
record_check expected_vrrp_state test "$(</run/caddy-ha/vrrp-state)" = "$expected_vrrp_state"
record_check dns_ipv4_unchanged test "$(address_count -4 "$dns_ipv4")" -eq "$expected_dns_count"
record_check dns_ipv6_unchanged test "$(address_count -6 "$dns_ipv6")" -eq "$expected_dns_count"

printf '%s_value_node_role=%s\n' "$prefix" "$node_role"
printf '%s_value_vrrp_state=%s\n' "$prefix" "$expected_vrrp_state"
printf '%s_value_caddy_ipv4_count=%s\n' "$prefix" "$expected_caddy_count"
printf '%s_value_caddy_ipv6_count=%s\n' "$prefix" "$expected_caddy_count"
printf '%s_value_dns_ipv4_count=%s\n' "$prefix" "$expected_dns_count"
printf '%s_value_dns_ipv6_count=%s\n' "$prefix" "$expected_dns_count"
printf '%s_backup_path=%s\n' "$prefix" "$backup_directory"
printf '%s_notification_helper_transition_invocation_expected=true\n' "$prefix"
printf '%s_persistent_mutation_scope=main_include,rollback_backup\n' "$prefix"
printf '%s_activation_complete=true\n' "$prefix"
transaction_complete=true
rm -rf -- "$transaction_root"
trap - EXIT
