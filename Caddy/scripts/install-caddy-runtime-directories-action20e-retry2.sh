#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20e_retry2_node
readonly installed_config=/etc/tmpfiles.d/caddy-ha.conf
readonly state_directory=/run/caddy-ha
readonly notify_directory=/run/caddy-ha-notify
readonly backup_root=/var/backups/caddy-ha
readonly notifier=/usr/local/libexec/lsyncd-ha-failover-notify.sh
readonly expected_notifier_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8
readonly expected_config_sha256=9d36d8b3e6a872bed9a435f569b543db8517e6ee79c2aa089583b8ca3dac6bc2
readonly caddy_ipv4=10.1.0.56/22
readonly caddy_ipv6=fd36:5aa8:6971:1::56/128
readonly dns_ipv4=10.1.0.55/22
readonly dns_ipv6=fd36:5aa8:6971:1::55/128
readonly maximum_stream_bytes=65536
readonly maximum_stream_lines=512

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
render_config() {
    printf '%s\n' \
        '# Caddy HA runtime state. Recreated by systemd-tmpfiles during boot.' \
        'd /run/caddy-ha 0750 pi caddy-sync -' \
        'd /run/caddy-ha-notify 0700 pi pi -'
}
render_shadow_config() {
    local pi_gid
    local pi_uid
    local sync_gid

    pi_uid=$(id -u pi) || return 1
    pi_gid=$(getent group pi | awk -F: '{ print $3 }') || return 1
    sync_gid=$(getent group caddy-sync | awk -F: '{ print $3 }') || return 1
    [[ -n "$pi_uid" && -n "$pi_gid" && -n "$sync_gid" ]] || return 1
    render_shadow_config_values "$pi_uid" "$pi_gid" "$sync_gid"
}
render_shadow_config_values() {
    local rendered_pi_gid=$2
    local rendered_pi_uid=$1
    local rendered_sync_gid=$3

    [[ "$rendered_pi_uid" =~ ^[0-9]+$ ]] || return 1
    [[ "$rendered_pi_gid" =~ ^[0-9]+$ ]] || return 1
    [[ "$rendered_sync_gid" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' \
        '# Caddy HA runtime state. Recreated by systemd-tmpfiles during boot.' \
        "d /run/caddy-ha 0750 $rendered_pi_uid $rendered_sync_gid -" \
        "d /run/caddy-ha-notify 0700 $rendered_pi_uid $rendered_pi_gid -"
}
create_secure_directory() {
    local created_group=$2
    local created_owner=$1
    local created_path=$3

    install -d -o "$created_owner" -g "$created_group" -m 0700 "$created_path"
}
address_count() {
    local address_family=$1
    local expected_address=$2

    ip -o "-$address_family" address show dev eth0 2>/dev/null |
        awk -v expected="$expected_address" '$4 == expected { count++ }
            END { print count + 0 }'
}
safe_stream() {
    local inspected_path=$1

    [[ "$(wc -c <"$inspected_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$inspected_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$inspected_path"
}
emit_stream() {
    local emitted_label=$1
    local emitted_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$emitted_label" "$(wc -c <"$emitted_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$emitted_label" "$(line_count "$emitted_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$emitted_label" "$(file_hash "$emitted_path")"
    if ! safe_stream "$emitted_path"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$emitted_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$emitted_label"
    if [[ -s "$emitted_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$emitted_label"
        cat "$emitted_path"
        printf '%s_%s_end\n' "$prefix" "$emitted_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$emitted_label"
    fi
}
snapshot_state() {
    local unit_name

    printf 'keepalived=%s\n' "$(file_hash /etc/keepalived/keepalived.conf)"
    printf 'fragment=%s\n' "$(file_hash /etc/keepalived/conf.d/caddy-ha.conf)"
    printf 'notifier=%s\n' "$(file_hash "$notifier")"
    printf 'addresses=%s:%s:%s:%s\n' \
        "$(address_count 4 "$caddy_ipv4")" "$(address_count 6 "$caddy_ipv6")" \
        "$(address_count 4 "$dns_ipv4")" "$(address_count 6 "$dns_ipv6")"
    for unit_name in keepalived.service caddy.service lighttpd.service; do
        printf 'unit=%s:%s:%s:%s\n' "$unit_name" \
            "$(systemctl is-active "$unit_name")" \
            "$(systemctl show -p MainPID --value "$unit_name")" \
            "$(systemctl show -p NRestarts --value "$unit_name")"
    done
}
path_empty_or_absent() {
    local inspected_directory=$1

    [[ ! -e "$inspected_directory" ]] && return 0
    [[ -d "$inspected_directory" && ! -L "$inspected_directory" ]] || return 1
    [[ -z "$(find "$inspected_directory" -mindepth 1 -maxdepth 1 -print -quit)" ]]
}
path_not_writable_by() {
    local inspected_user=$1
    local inspected_path=$2

    ! runuser -u "$inspected_user" -- test -w "$inspected_path"
}
expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root node_role_exact hostname_exact architecture_arm64 \
        tmpfiles_parent_regular tmpfiles_parent_not_symlink tmpfiles_parent_owner_exact pi_user_exists pi_group_exists \
        pi_primary_group_exact caddy_sync_user_exists caddy_sync_group_exists \
        config_prestate_absent state_prestate_absent notify_prestate_absent \
        notifier_regular notifier_not_symlink notifier_metadata_exact notifier_hash_exact \
        notifier_inherits_pi keepalived_active caddy_active lighttpd_active \
        caddy_ipv4_absent caddy_ipv6_absent dns_ipv4_role_exact dns_ipv6_role_exact \
        candidate_regular candidate_not_symlink candidate_metadata_exact candidate_hash_exact \
        candidate_content_exact shadow_root_regular shadow_root_not_symlink \
        shadow_root_metadata_exact shadow_etc_regular shadow_etc_not_symlink \
        shadow_etc_metadata_exact shadow_tmpfiles_regular shadow_tmpfiles_not_symlink \
        shadow_tmpfiles_metadata_exact shadow_config_regular shadow_config_not_symlink \
        shadow_config_metadata_exact shadow_config_content_exact parser_status_zero \
        parser_stdout_safe parser_stderr_safe shadow_state_regular shadow_state_not_symlink \
        shadow_state_metadata_exact shadow_notify_regular shadow_notify_not_symlink \
        shadow_notify_metadata_exact shadow_sentinel_regular reapply_status_zero \
        reapply_stdout_safe reapply_stderr_safe shadow_state_metadata_reapplied \
        shadow_sentinel_retained backup_directory_regular backup_directory_not_symlink backup_directory_metadata_exact \
        backup_manifest_regular backup_manifest_not_symlink backup_manifest_metadata_exact \
        backup_manifest_exact installed_config_regular installed_config_not_symlink \
        installed_config_metadata_exact installed_config_hash_exact create_status_zero \
        create_stdout_safe create_stderr_safe state_directory_regular state_directory_not_symlink \
        state_directory_metadata_exact state_readable_by_pi state_writable_by_pi \
        state_searchable_by_pi state_readable_by_caddy_sync state_searchable_by_caddy_sync \
        state_not_writable_by_caddy_sync notify_directory_regular notify_directory_not_symlink \
        notify_directory_metadata_exact notify_readable_by_pi notify_writable_by_pi \
        notify_searchable_by_pi notifier_not_invoked before_snapshot_complete \
        after_snapshot_complete state_unchanged keepalived_still_active caddy_still_active \
        lighttpd_still_active caddy_ipv4_still_absent caddy_ipv6_still_absent \
        dns_ipv4_role_still_exact dns_ipv6_role_still_exact
}
expected_rollback_checks() {
    printf '%s\n' \
        rollback_identity_root rollback_working_directory_root rollback_hostname_exact \
        rollback_backup_regular rollback_backup_not_symlink rollback_backup_metadata_exact \
        rollback_manifest_regular rollback_manifest_not_symlink rollback_manifest_metadata_exact \
        rollback_manifest_exact rollback_config_hash_supported rollback_state_empty \
        rollback_notify_empty rollback_config_removed rollback_state_removed rollback_notify_removed \
        rollback_keepalived_active rollback_caddy_active rollback_lighttpd_active \
        rollback_caddy_ipv4_absent rollback_caddy_ipv6_absent
}
record_check() {
    local assertion_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$assertion_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$assertion_label" >&2
    return 1
}
config_hash_supported() {
    local observed_hash

    [[ ! -e "$installed_config" ]] && return 0
    [[ -f "$installed_config" && ! -L "$installed_config" ]] || return 1
    observed_hash=$(file_hash "$installed_config") || return 1
    [[ "$observed_hash" = "$expected_config_sha256" ]]
}

node_role=
rollback_directory=
case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]] || exit 64
        expected_checks
        exit 0
        ;;
    --expected-rollback-checks)
        [[ $# -eq 1 ]] || exit 64
        expected_rollback_checks
        exit 0
        ;;
    --render-config)
        [[ $# -eq 1 ]] || exit 64
        render_config
        exit 0
        ;;
    --render-shadow-config)
        [[ $# -eq 4 ]] || exit 64
        render_shadow_config_values "$2" "$3" "$4"
        exit 0
        ;;
    --shadow-layout-test)
        [[ $# -eq 2 ]] || exit 64
        layout_test_root=$2
        case "$layout_test_root" in
            /tmp/caddy-action20e-retry2-layout.*) ;;
            *) exit 64 ;;
        esac
        [[ -d "$layout_test_root" && ! -L "$layout_test_root" ]] || exit 64
        [[ -z "$(find "$layout_test_root" -mindepth 1 -print -quit)" ]] || exit 64
        layout_test_owner=$(id -un)
        readonly layout_test_owner
        layout_test_group=$(id -gn)
        readonly layout_test_group
        create_secure_directory "$layout_test_owner" "$layout_test_group" \
            "$layout_test_root/shadow-root"
        printf '%s_layout_test_root=%s\n' "$prefix" \
            "$(stat -c '%U:%G:%a' "$layout_test_root/shadow-root")"
        create_secure_directory "$layout_test_owner" "$layout_test_group" \
            "$layout_test_root/shadow-root/etc"
        printf '%s_layout_test_etc=%s\n' "$prefix" \
            "$(stat -c '%U:%G:%a' "$layout_test_root/shadow-root/etc")"
        create_secure_directory "$layout_test_owner" "$layout_test_group" \
            "$layout_test_root/shadow-root/etc/tmpfiles.d"
        printf '%s_layout_test_tmpfiles=%s\n' "$prefix" \
            "$(stat -c '%U:%G:%a' "$layout_test_root/shadow-root/etc/tmpfiles.d")"
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$(expected_checks | wc -l)" -eq "$(expected_checks | LC_ALL=C sort -u | wc -l)" ]]
        [[ "$(expected_rollback_checks | wc -l)" -eq "$(expected_rollback_checks | LC_ALL=C sort -u | wc -l)" ]]
        [[ "$(render_config | sha256sum | awk '{ print $1 }')" = "$expected_config_sha256" ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --node)
        [[ $# -eq 2 ]] || exit 64
        node_role=$2
        ;;
    --rollback)
        [[ $# -eq 4 && ${2:-} = --node ]] || exit 64
        node_role=$3
        rollback_directory=$4
        ;;
    *)
        printf 'Usage: %s --node node-a|node-b | --rollback --node node-a|node-b BACKUP | --expected-checks | --expected-rollback-checks | --render-config | --render-shadow-config UID PI_GID SYNC_GID | --shadow-layout-test ROOT | --self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac

case "$node_role" in
    node-a)
        expected_hostname=j1-svpihole0
        expected_dns_count=1
        ;;
    node-b)
        expected_hostname=j1-svpihole00
        expected_dns_count=0
        ;;
    *) exit 64 ;;
esac
readonly node_role expected_hostname expected_dns_count

rollback_failures=0
rollback_first_failure=none
run_rollback_check() {
    local rollback_label=$1

    shift
    if ! record_check "$rollback_label" "$@"; then
        rollback_failures=$((rollback_failures + 1))
        if [[ "$rollback_first_failure" = none ]]; then
            rollback_first_failure=$rollback_label
        fi
    fi
}
perform_rollback() {
    local expected_manifest

    expected_manifest=$(printf 'action=20e\nnode=%s\ntmpfiles_config=absent\nstate_directory=absent\nnotify_directory=absent\n' "$node_role")
    run_rollback_check rollback_identity_root test "$(id -u)" -eq 0
    run_rollback_check rollback_working_directory_root test "$(pwd -P)" = /
    run_rollback_check rollback_hostname_exact test "$(hostname)" = "$expected_hostname"
    run_rollback_check rollback_backup_regular test -d "$rollback_directory"
    run_rollback_check rollback_backup_not_symlink test ! -L "$rollback_directory"
    run_rollback_check rollback_backup_metadata_exact test "$(stat -c '%U:%G:%a' "$rollback_directory" 2>/dev/null || true)" = root:root:700
    run_rollback_check rollback_manifest_regular test -f "$rollback_directory/manifest"
    run_rollback_check rollback_manifest_not_symlink test ! -L "$rollback_directory/manifest"
    run_rollback_check rollback_manifest_metadata_exact test "$(stat -c '%U:%G:%a' "$rollback_directory/manifest" 2>/dev/null || true)" = root:root:600
    run_rollback_check rollback_manifest_exact test "$(cat "$rollback_directory/manifest" 2>/dev/null || true)" = "$expected_manifest"
    run_rollback_check rollback_config_hash_supported config_hash_supported
    run_rollback_check rollback_state_empty path_empty_or_absent "$state_directory"
    run_rollback_check rollback_notify_empty path_empty_or_absent "$notify_directory"
    if [[ "$rollback_failures" -ne 0 ]]; then
        printf '%s_rollback_failed_check_count=%s\n' "$prefix" "$rollback_failures"
        printf '%s_rollback_first_failure=%s\n' "$prefix" "$rollback_first_failure"
        printf '%s_manual_intervention_required=true\n' "$prefix"
        return 125
    fi
    rm -f -- "$installed_config"
    rmdir -- "$notify_directory"
    rmdir -- "$state_directory"
    run_rollback_check rollback_config_removed test ! -e "$installed_config"
    run_rollback_check rollback_state_removed test ! -e "$state_directory"
    run_rollback_check rollback_notify_removed test ! -e "$notify_directory"
    run_rollback_check rollback_keepalived_active test "$(systemctl is-active keepalived.service)" = active
    run_rollback_check rollback_caddy_active test "$(systemctl is-active caddy.service)" = active
    run_rollback_check rollback_lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
    run_rollback_check rollback_caddy_ipv4_absent test "$(address_count 4 "$caddy_ipv4")" -eq 0
    run_rollback_check rollback_caddy_ipv6_absent test "$(address_count 6 "$caddy_ipv6")" -eq 0
    printf '%s_rollback_check_count=%s\n' "$prefix" "$(expected_rollback_checks | wc -l)"
    printf '%s_rollback_failed_check_count=%s\n' "$prefix" "$rollback_failures"
    printf '%s_rollback_first_failure=%s\n' "$prefix" "$rollback_first_failure"
    printf '%s_rollback_complete=true\n' "$prefix"
    [[ "$rollback_failures" -eq 0 ]]
}

if [[ ${1:-} = --rollback ]]; then
    readonly rollback_directory
    perform_rollback
    exit
fi

transaction_root=$(mktemp -d /run/caddy-action20e-retry2-node.XXXXXX)
readonly transaction_root
retain_evidence=false
cleanup() {
    # shellcheck disable=SC2317
    if [[ "$retain_evidence" = true ]]; then
        printf '%s_protected_evidence=%s\n' "$prefix" "$transaction_root" >&2
    else
        rm -rf -- "$transaction_root"
    fi
}
trap cleanup EXIT
readonly candidate=$transaction_root/caddy-ha.conf
readonly parser_stdout=$transaction_root/parser.stdout
readonly parser_stderr=$transaction_root/parser.stderr
readonly reapply_stdout=$transaction_root/reapply.stdout
readonly reapply_stderr=$transaction_root/reapply.stderr
readonly create_stdout=$transaction_root/create.stdout
readonly create_stderr=$transaction_root/create.stderr
readonly shadow_root=$transaction_root/shadow-root
readonly shadow_config=$shadow_root/etc/tmpfiles.d/caddy-ha.conf
readonly shadow_state=$shadow_root/run/caddy-ha
readonly shadow_notify=$shadow_root/run/caddy-ha-notify
readonly shadow_sentinel=$shadow_state/sentinel
render_config >"$candidate"
: >"$parser_stdout"
: >"$parser_stderr"
: >"$reapply_stdout"
: >"$reapply_stderr"
: >"$create_stdout"
: >"$create_stderr"
chmod 0600 "$candidate" "$parser_stdout" "$parser_stderr" "$reapply_stdout" \
    "$reapply_stderr" "$create_stdout" "$create_stderr"

failed_checks=0
first_failure=none
run_check() {
    local check_label=$1

    shift
    if ! record_check "$check_label" "$@"; then
        failed_checks=$((failed_checks + 1))
        if [[ "$first_failure" = none ]]; then first_failure=$check_label; fi
    fi
}

before_snapshot_status=0
before_snapshot=$(snapshot_state) || before_snapshot_status=$?
readonly before_snapshot before_snapshot_status
before_snapshot_sha256=$(printf '%s\n' "$before_snapshot" | sha256sum | awk '{ print $1 }')
readonly before_snapshot_sha256

run_check identity_root test "$(id -u)" -eq 0
run_check working_directory_root test "$(pwd -P)" = /
run_check node_role_exact test -n "$node_role"
run_check hostname_exact test "$(hostname)" = "$expected_hostname"
run_check architecture_arm64 test "$(dpkg --print-architecture)" = arm64
run_check tmpfiles_parent_regular test -d /etc/tmpfiles.d
run_check tmpfiles_parent_not_symlink test ! -L /etc/tmpfiles.d
run_check tmpfiles_parent_owner_exact test "$(stat -c '%U:%G' /etc/tmpfiles.d 2>/dev/null || true)" = root:root
printf '%s_live_tmpfiles_parent_metadata=%s\n' "$prefix" "$(stat -c '%U:%G:%a' /etc/tmpfiles.d 2>/dev/null || printf unavailable)"
run_check pi_user_exists getent passwd pi
run_check pi_group_exists getent group pi
run_check pi_primary_group_exact test "$(id -gn pi 2>/dev/null || true)" = pi
run_check caddy_sync_user_exists getent passwd caddy-sync
run_check caddy_sync_group_exists getent group caddy-sync
run_check config_prestate_absent test ! -e "$installed_config"
run_check state_prestate_absent test ! -e "$state_directory"
run_check notify_prestate_absent test ! -e "$notify_directory"
run_check notifier_regular test -f "$notifier"
run_check notifier_not_symlink test ! -L "$notifier"
run_check notifier_metadata_exact test "$(stat -c '%U:%G:%a' "$notifier" 2>/dev/null || true)" = root:root:755
run_check notifier_hash_exact test "$(file_hash "$notifier" 2>/dev/null || true)" = "$expected_notifier_sha256"
run_check notifier_inherits_pi test "$(grep -Fxc '    script_user pi' /etc/keepalived/keepalived.conf 2>/dev/null || true)" -eq 1
run_check keepalived_active test "$(systemctl is-active keepalived.service)" = active
run_check caddy_active test "$(systemctl is-active caddy.service)" = active
run_check lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
run_check caddy_ipv4_absent test "$(address_count 4 "$caddy_ipv4")" -eq 0
run_check caddy_ipv6_absent test "$(address_count 6 "$caddy_ipv6")" -eq 0
run_check dns_ipv4_role_exact test "$(address_count 4 "$dns_ipv4")" -eq "$expected_dns_count"
run_check dns_ipv6_role_exact test "$(address_count 6 "$dns_ipv6")" -eq "$expected_dns_count"
run_check candidate_regular test -f "$candidate"
run_check candidate_not_symlink test ! -L "$candidate"
run_check candidate_metadata_exact test "$(stat -c '%U:%G:%a' "$candidate")" = root:root:600
run_check candidate_hash_exact test "$(file_hash "$candidate")" = "$expected_config_sha256"
run_check candidate_content_exact test "$(cat "$candidate")" = "$(render_config)"
create_secure_directory root root "$shadow_root"
run_check shadow_root_regular test -d "$shadow_root"
run_check shadow_root_not_symlink test ! -L "$shadow_root"
run_check shadow_root_metadata_exact test "$(stat -c '%U:%G:%a' "$shadow_root")" = root:root:700
create_secure_directory root root "$shadow_root/etc"
run_check shadow_etc_regular test -d "$shadow_root/etc"
run_check shadow_etc_not_symlink test ! -L "$shadow_root/etc"
run_check shadow_etc_metadata_exact test "$(stat -c '%U:%G:%a' "$shadow_root/etc")" = root:root:700
create_secure_directory root root "$shadow_root/etc/tmpfiles.d"
run_check shadow_tmpfiles_regular test -d "$shadow_root/etc/tmpfiles.d"
run_check shadow_tmpfiles_not_symlink test ! -L "$shadow_root/etc/tmpfiles.d"
run_check shadow_tmpfiles_metadata_exact test "$(stat -c '%U:%G:%a' "$shadow_root/etc/tmpfiles.d")" = root:root:700
render_shadow_config >"$shadow_config"
chmod 0600 "$shadow_config"
run_check shadow_config_regular test -f "$shadow_config"
run_check shadow_config_not_symlink test ! -L "$shadow_config"
run_check shadow_config_metadata_exact test "$(stat -c '%U:%G:%a' "$shadow_config")" = root:root:600
run_check shadow_config_content_exact test "$(cat "$shadow_config")" = "$(render_shadow_config)"
parser_status=0
systemd-tmpfiles --root="$shadow_root" --create caddy-ha.conf >"$parser_stdout" 2>"$parser_stderr" || parser_status=$?
readonly parser_status
run_check parser_status_zero test "$parser_status" -eq 0
run_check parser_stdout_safe safe_stream "$parser_stdout"
run_check parser_stderr_safe safe_stream "$parser_stderr"
run_check shadow_state_regular test -d "$shadow_state"
run_check shadow_state_not_symlink test ! -L "$shadow_state"
run_check shadow_state_metadata_exact test \
    "$(stat -c '%u:%g:%a' "$shadow_state" 2>/dev/null || true)" = \
    "$(id -u pi):$(getent group caddy-sync | awk -F: '{ print $3 }'):750"
run_check shadow_notify_regular test -d "$shadow_notify"
run_check shadow_notify_not_symlink test ! -L "$shadow_notify"
run_check shadow_notify_metadata_exact test \
    "$(stat -c '%u:%g:%a' "$shadow_notify" 2>/dev/null || true)" = \
    "$(id -u pi):$(getent group pi | awk -F: '{ print $3 }'):700"
printf 'retained\n' >"$shadow_sentinel"
chmod 0600 "$shadow_sentinel"
run_check shadow_sentinel_regular test -f "$shadow_sentinel"
chmod 0777 "$shadow_state"
reapply_status=0
systemd-tmpfiles --root="$shadow_root" --create caddy-ha.conf >"$reapply_stdout" 2>"$reapply_stderr" || reapply_status=$?
readonly reapply_status
run_check reapply_status_zero test "$reapply_status" -eq 0
run_check reapply_stdout_safe safe_stream "$reapply_stdout"
run_check reapply_stderr_safe safe_stream "$reapply_stderr"
run_check shadow_state_metadata_reapplied test \
    "$(stat -c '%u:%g:%a' "$shadow_state" 2>/dev/null || true)" = \
    "$(id -u pi):$(getent group caddy-sync | awk -F: '{ print $3 }'):750"
run_check shadow_sentinel_retained grep -Fxq retained "$shadow_sentinel"
run_check before_snapshot_complete test "$before_snapshot_status" -eq 0
if [[ "$failed_checks" -ne 0 ]]; then
    emit_stream parser_stdout "$parser_stdout" || retain_evidence=true
    emit_stream parser_stderr "$parser_stderr" || retain_evidence=true
    emit_stream reapply_stdout "$reapply_stdout" || retain_evidence=true
    emit_stream reapply_stderr "$reapply_stderr" || retain_evidence=true
    printf '%s_failed_check_count=%s\n' "$prefix" "$failed_checks"
    printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
    printf '%s_mutation_started=false\n' "$prefix"
    exit 1
fi

install -d -o root -g root -m 0700 "$backup_root"
backup_directory=$(mktemp -d "$backup_root/action20e-${node_role}-runtime-directories.XXXXXX")
readonly backup_directory
printf 'action=20e\nnode=%s\ntmpfiles_config=absent\nstate_directory=absent\nnotify_directory=absent\n' "$node_role" >"$backup_directory/manifest"
chmod 0600 "$backup_directory/manifest"
rendered_backup_manifest=$(printf 'action=20e\nnode=%s\ntmpfiles_config=absent\nstate_directory=absent\nnotify_directory=absent\n' "$node_role")
readonly rendered_backup_manifest
run_check backup_directory_regular test -d "$backup_directory"
run_check backup_directory_not_symlink test ! -L "$backup_directory"
run_check backup_directory_metadata_exact test "$(stat -c '%U:%G:%a' "$backup_directory")" = root:root:700
run_check backup_manifest_regular test -f "$backup_directory/manifest"
run_check backup_manifest_not_symlink test ! -L "$backup_directory/manifest"
run_check backup_manifest_metadata_exact test "$(stat -c '%U:%G:%a' "$backup_directory/manifest")" = root:root:600
run_check backup_manifest_exact test "$(cat "$backup_directory/manifest")" = "$rendered_backup_manifest"
if [[ "$failed_checks" -ne 0 ]]; then
    printf '%s_failed_check_count=%s\n' "$prefix" "$failed_checks"
    printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
    printf '%s_mutation_started=false\n' "$prefix"
    exit 1
fi

printf '%s_mutation_started=true\n' "$prefix"
install -o root -g root -m 0644 "$candidate" "$installed_config"
create_status=0
systemd-tmpfiles --create "$installed_config" >"$create_stdout" 2>"$create_stderr" || create_status=$?
readonly create_status
run_check installed_config_regular test -f "$installed_config"
run_check installed_config_not_symlink test ! -L "$installed_config"
run_check installed_config_metadata_exact test "$(stat -c '%U:%G:%a' "$installed_config" 2>/dev/null || true)" = root:root:644
run_check installed_config_hash_exact test "$(file_hash "$installed_config" 2>/dev/null || true)" = "$expected_config_sha256"
run_check create_status_zero test "$create_status" -eq 0
run_check create_stdout_safe safe_stream "$create_stdout"
run_check create_stderr_safe safe_stream "$create_stderr"
run_check state_directory_regular test -d "$state_directory"
run_check state_directory_not_symlink test ! -L "$state_directory"
run_check state_directory_metadata_exact test "$(stat -c '%U:%G:%a' "$state_directory" 2>/dev/null || true)" = pi:caddy-sync:750
run_check state_readable_by_pi runuser -u pi -- test -r "$state_directory"
run_check state_writable_by_pi runuser -u pi -- test -w "$state_directory"
run_check state_searchable_by_pi runuser -u pi -- test -x "$state_directory"
run_check state_readable_by_caddy_sync runuser -u caddy-sync -- test -r "$state_directory"
run_check state_searchable_by_caddy_sync runuser -u caddy-sync -- test -x "$state_directory"
run_check state_not_writable_by_caddy_sync path_not_writable_by caddy-sync "$state_directory"
run_check notify_directory_regular test -d "$notify_directory"
run_check notify_directory_not_symlink test ! -L "$notify_directory"
run_check notify_directory_metadata_exact test "$(stat -c '%U:%G:%a' "$notify_directory" 2>/dev/null || true)" = pi:pi:700
run_check notify_readable_by_pi runuser -u pi -- test -r "$notify_directory"
run_check notify_writable_by_pi runuser -u pi -- test -w "$notify_directory"
run_check notify_searchable_by_pi runuser -u pi -- test -x "$notify_directory"
run_check notifier_not_invoked test ! -e "$state_directory/vrrp-state"
after_snapshot_status=0
after_snapshot=$(snapshot_state) || after_snapshot_status=$?
readonly after_snapshot after_snapshot_status
after_snapshot_sha256=$(printf '%s\n' "$after_snapshot" | sha256sum | awk '{ print $1 }')
readonly after_snapshot_sha256
run_check after_snapshot_complete test "$after_snapshot_status" -eq 0
run_check state_unchanged test "$after_snapshot" = "$before_snapshot"
run_check keepalived_still_active test "$(systemctl is-active keepalived.service)" = active
run_check caddy_still_active test "$(systemctl is-active caddy.service)" = active
run_check lighttpd_still_active test "$(systemctl is-active lighttpd.service)" = active
run_check caddy_ipv4_still_absent test "$(address_count 4 "$caddy_ipv4")" -eq 0
run_check caddy_ipv6_still_absent test "$(address_count 6 "$caddy_ipv6")" -eq 0
run_check dns_ipv4_role_still_exact test "$(address_count 4 "$dns_ipv4")" -eq "$expected_dns_count"
run_check dns_ipv6_role_still_exact test "$(address_count 6 "$dns_ipv6")" -eq "$expected_dns_count"

emit_status=0
emit_stream parser_stdout "$parser_stdout" || emit_status=$?
emit_stream parser_stderr "$parser_stderr" || emit_status=$?
emit_stream reapply_stdout "$reapply_stdout" || emit_status=$?
emit_stream reapply_stderr "$reapply_stderr" || emit_status=$?
emit_stream create_stdout "$create_stdout" || emit_status=$?
emit_stream create_stderr "$create_stderr" || emit_status=$?
if [[ "$emit_status" -ne 0 ]]; then
    retain_evidence=true
    failed_checks=$((failed_checks + 1))
    if [[ "$first_failure" = none ]]; then first_failure=output_evidence_unsafe; fi
fi
if [[ "$failed_checks" -ne 0 ]]; then
    printf '%s_rollback_started=true\n' "$prefix" >&2
    rollback_directory=$backup_directory
    if perform_rollback; then
        printf '%s_automatic_rollback_complete=true\n' "$prefix" >&2
    else
        retain_evidence=true
        printf '%s_automatic_rollback_complete=false\n' "$prefix" >&2
        exit 125
    fi
    printf '%s_failed_check_count=%s\n' "$prefix" "$failed_checks"
    printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
    exit 1
fi

printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
printf '%s_failed_check_count=0\n' "$prefix"
printf '%s_first_failure=none\n' "$prefix"
printf '%s_before_state_sha256=%s\n' "$prefix" "$before_snapshot_sha256"
printf '%s_after_state_sha256=%s\n' "$prefix" "$after_snapshot_sha256"
printf '%s_backup_path=%s\n' "$prefix" "$backup_directory"
printf '%s_keepalived_mutated=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutated=false\n' "$prefix"
printf '%s_vip_mutated=false\n' "$prefix"
printf '%s_notifier_invoked=false\n' "$prefix"
printf '%s_persistent_mutation_scope=tmpfiles_config,runtime_directories,rollback_backup\n' "$prefix"
printf '%s_install_complete=true\n' "$prefix"
