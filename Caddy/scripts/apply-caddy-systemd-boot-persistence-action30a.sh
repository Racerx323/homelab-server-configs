#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_30a_remote
readonly backup_directory=/var/backups/caddy-ha/action30a-systemd-boot-persistence
readonly evidence_root=/tmp/caddy-action30a
readonly obsolete_path=/etc/systemd/system/caddy-validate-reload.path
readonly obsolete_service=/etc/systemd/system/caddy-validate-reload.service
readonly obsolete_path_sha256=f7fde941ae045e5697aa9e966e4f9a40d55a1f08f413f02cf9f8775046331bb7
readonly obsolete_service_sha256=51be7495194143210bf805fdaa78072162eed028e8da3b3507f73f416cde8322
readonly cert_timer=/etc/systemd/system/caddy-cert-expiry.timer
readonly cert_timer_sha256=409a4494eff683c602ceced8d076eed1e9681e5d351665b54a3e614afb7f05f7
readonly health_timer=/etc/systemd/system/caddy-sync-health.timer
readonly health_timer_sha256=65bd3ff8f969301f17d6fdf457a8b6b1676489f5e536612cab57d61e0c6bdf8e
readonly reconcile_path=/etc/systemd/system/caddy-sync-reconcile.path
readonly reconcile_path_sha256=c8c11582580326300035c1b6e8dc97cb6b90052683b57836cc3afdcdd436f295
readonly -a persistent_units=(
    caddy.service
    caddy-lsyncd.service
    caddy-sync-reconcile.path
    caddy-cert-expiry.timer
    caddy-sync-health.timer
)
readonly -a static_units=(
    emergency.service
    caddy-cert-expiry.service
    caddy-sync-failure@.service
    caddy-sync-health.service
    caddy-sync-reconcile.service
)
readonly distribution_lsyncd_unit=lsyncd.service
readonly lsyncd_status_file=${CADDY_ACTION30A_STATUS_FILE:-/run/caddy-lsyncd/status}
readonly maximum_lsyncd_status_age=120
readonly lsyncd_status_wait_seconds=45

role=
node_token=
expected_hostname=
capture_directory=
mutation_started=false
transaction_complete=false

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
safe_stream() {
    local action30a_stream=$1

    [[ "$(wc -c <"$action30a_stream")" -le 1048576 ]] || return 1
    [[ "$(line_count "$action30a_stream")" -le 8192 ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action30a_stream" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action30a_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' "$action30a_stream"
}
emit_stream() {
    local action30a_label=$1
    local action30a_stream=$2

    printf '%s_%s_%s_bytes=%s\n' "$prefix" "$node_token" "$action30a_label" "$(wc -c <"$action30a_stream")"
    printf '%s_%s_%s_lines=%s\n' "$prefix" "$node_token" "$action30a_label" "$(line_count "$action30a_stream")"
    printf '%s_%s_%s_sha256=%s\n' "$prefix" "$node_token" "$action30a_label" "$(file_hash "$action30a_stream")"
    safe_stream "$action30a_stream" || return 97
    printf '%s_%s_%s_classification=bounded_safe\n' "$prefix" "$node_token" "$action30a_label"
    if [[ -s "$action30a_stream" ]]; then
        printf '%s_%s_%s_begin\n' "$prefix" "$node_token" "$action30a_label"
        cat "$action30a_stream"
        printf '%s_%s_%s_end\n' "$prefix" "$node_token" "$action30a_label"
    else
        printf '%s_%s_%s_content=empty\n' "$prefix" "$node_token" "$action30a_label"
    fi
}
check() {
    local action30a_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_%s_check_%s=true\n' "$prefix" "$node_token" "$action30a_label"
        return 0
    fi
    printf '%s_%s_check_%s=false\n' "$prefix" "$node_token" "$action30a_label" >&2
    return 1
}
run_captured() {
    local action30a_label=$1
    local action30a_stdout=$capture_directory/$action30a_label.stdout
    local action30a_stderr=$capture_directory/$action30a_label.stderr
    local action30a_status_file=$capture_directory/$action30a_label.status
    local action30a_status=0

    shift
    install -m 0600 /dev/null "$action30a_stdout" || return 1
    install -m 0600 /dev/null "$action30a_stderr" || return 1
    install -m 0600 /dev/null "$action30a_status_file" || return 1
    "$@" >"$action30a_stdout" 2>"$action30a_stderr" || action30a_status=$?
    printf '%s\n' "$action30a_status" >"$action30a_status_file"
    printf '%s_%s_%s_status=%s\n' "$prefix" "$node_token" "$action30a_label" "$action30a_status"
    emit_stream "${action30a_label}_stdout" "$action30a_stdout" || return $?
    emit_stream "${action30a_label}_stderr" "$action30a_stderr" || return $?
    [[ "$action30a_status" -eq 0 ]]
}
enabled_exact() {
    [[ "$(systemctl is-enabled "$1" 2>/dev/null || true)" = "$2" ]]
}
active_exact() {
    [[ "$(systemctl is-active "$1" 2>/dev/null || true)" = "$2" ]]
}
unit_not_failed() {
    [[ "$(systemctl is-failed "$1" 2>/dev/null || true)" != failed ]]
}
static_enablement_contract() {
    local action30a_unit

    for action30a_unit in "${static_units[@]}"; do
        enabled_exact "$action30a_unit" static || return 1
    done
}
lsyncd_status_age() {
    local action30a_now
    local action30a_modified

    [[ -f "$lsyncd_status_file" && ! -L "$lsyncd_status_file" && -s "$lsyncd_status_file" ]] || return 1
    action30a_now=$(date +%s) || return 1
    action30a_modified=$(stat -c %Y "$lsyncd_status_file") || return 1
    [[ "$action30a_modified" -le "$action30a_now" ]] || return 1
    printf '%s\n' "$((action30a_now - action30a_modified))"
}
lsyncd_status_fresh() {
    local action30a_age

    action30a_age=$(lsyncd_status_age) || return 1
    [[ "$action30a_age" -le "$maximum_lsyncd_status_age" ]]
}
wait_for_fresh_lsyncd_status() {
    local action30a_waited=0

    while [[ "$action30a_waited" -lt "$lsyncd_status_wait_seconds" ]]; do
        if lsyncd_status_fresh; then
            printf '%s_%s_lsyncd_status_wait_seconds=%s\n' "$prefix" "$node_token" "$action30a_waited"
            return 0
        fi
        sleep 1
        action30a_waited=$((action30a_waited + 1))
    done
    return 1
}
wait_for_lsyncd_status_advance() {
    local action30a_initial_mtime
    local action30a_current_mtime
    local action30a_waited=0

    action30a_initial_mtime=$(stat -c %Y "$lsyncd_status_file") || return 1
    printf '%s_%s_lsyncd_status_mtime_initial=%s\n' "$prefix" "$node_token" "$action30a_initial_mtime"
    while [[ "$action30a_waited" -lt "$lsyncd_status_wait_seconds" ]]; do
        sleep 1
        action30a_waited=$((action30a_waited + 1))
        action30a_current_mtime=$(stat -c %Y "$lsyncd_status_file" 2>/dev/null || true)
        if [[ "$action30a_current_mtime" =~ ^[0-9]+$ &&
            "$action30a_current_mtime" -gt "$action30a_initial_mtime" ]]; then
            printf '%s_%s_lsyncd_status_mtime_advanced=%s\n' "$prefix" "$node_token" "$action30a_current_mtime"
            printf '%s_%s_lsyncd_status_advance_wait_seconds=%s\n' "$prefix" "$node_token" "$action30a_waited"
            return 0
        fi
    done
    return 1
}
emit_unit_properties() {
    local action30a_label=$1
    local action30a_unit=$2

    run_captured "$action30a_label" systemctl show "$action30a_unit" \
        -p LoadState -p UnitFileState -p ActiveState -p SubState -p Result -p ExecMainStatus
}
successful_static_worker() {
    local action30a_unit=$1

    enabled_exact "$action30a_unit" static || return 1
    unit_not_failed "$action30a_unit" || return 1
    [[ "$(systemctl show "$action30a_unit" -p Result --value 2>/dev/null || true)" = success ]] || return 1
    [[ "$(systemctl show "$action30a_unit" -p ExecMainStatus --value 2>/dev/null || true)" = 0 ]]
}
continuity() {
    check uid_root test "$(id -u)" -eq 0 || return 1
    check working_directory_root test "$PWD" = / || return 1
    check hostname_exact test "$(hostname)" = "$expected_hostname" || return 1
    check caddy_active active_exact caddy.service active || return 1
    check lsyncd_active active_exact caddy-lsyncd.service active || return 1
    check reconcile_path_active active_exact caddy-sync-reconcile.path active || return 1
    check keepalived_active active_exact keepalived.service active || return 1
    check lighttpd_active active_exact lighttpd.service active || return 1
}
target_contract() {
    local action30a_unit

    continuity || return 1
    for action30a_unit in "${persistent_units[@]}"; do
        check "${action30a_unit//[^a-zA-Z0-9]/_}_enabled" enabled_exact "$action30a_unit" enabled || return 1
        check "${action30a_unit//[^a-zA-Z0-9]/_}_active" active_exact "$action30a_unit" active || return 1
    done
    check caddy_api_masked enabled_exact caddy-api.service masked || return 1
    check caddy_api_inactive active_exact caddy-api.service inactive || return 1
    check distribution_lsyncd_masked enabled_exact "$distribution_lsyncd_unit" masked || return 1
    check distribution_lsyncd_inactive active_exact "$distribution_lsyncd_unit" inactive || return 1
    check emergency_service_static enabled_exact emergency.service static || return 1
    check emergency_service_nonfailed unit_not_failed emergency.service || return 1
    check cert_worker_static enabled_exact caddy-cert-expiry.service static || return 1
    check cert_worker_success successful_static_worker caddy-cert-expiry.service || return 1
    check health_worker_static enabled_exact caddy-sync-health.service static || return 1
    check health_worker_success successful_static_worker caddy-sync-health.service || return 1
    check failure_worker_static enabled_exact caddy-sync-failure@.service static || return 1
    check failure_worker_nonfailed unit_not_failed caddy-sync-failure@.service || return 1
    check reconcile_worker_static enabled_exact caddy-sync-reconcile.service static || return 1
    check reconcile_worker_nonfailed unit_not_failed caddy-sync-reconcile.service || return 1
    check lsyncd_status_fresh lsyncd_status_fresh || return 1
    check cert_timer_hash test "$(file_hash "$cert_timer")" = "$cert_timer_sha256" || return 1
    check health_timer_hash test "$(file_hash "$health_timer")" = "$health_timer_sha256" || return 1
    check reconcile_path_hash test "$(file_hash "$reconcile_path")" = "$reconcile_path_sha256" || return 1
    check obsolete_path_absent test ! -e "$obsolete_path" || return 1
    check obsolete_service_absent test ! -e "$obsolete_service" || return 1
    check validate_path_not_loaded test "$(systemctl show caddy-validate-reload.path -p LoadState --value 2>/dev/null || true)" = not-found || return 1
    check validate_service_not_loaded test "$(systemctl show caddy-validate-reload.service -p LoadState --value 2>/dev/null || true)" = not-found || return 1
}
manifest_value() {
    local action30a_key=$1

    awk -F= -v key="$action30a_key" '$1 == key { print $2; found++ } END { if (found != 1) exit 1 }' \
        "$backup_directory/manifest"
}
record_backup() {
    local action30a_unit
    local action30a_backup_staging=${backup_directory}.staging.$$

    if ! install -d -o root -g root -m 0700 "$action30a_backup_staging"; then
        return 1
    fi
    if ! install -o root -g root -m 0600 "$obsolete_path" \
        "$action30a_backup_staging/caddy-validate-reload.path" ||
        ! install -o root -g root -m 0600 "$obsolete_service" \
            "$action30a_backup_staging/caddy-validate-reload.service"; then
        rm -rf -- "$action30a_backup_staging"
        return 1
    fi
    {
        printf 'action=30a\nrole=%s\n' "$role"
        for action30a_unit in "${persistent_units[@]}" caddy-api.service "$distribution_lsyncd_unit" caddy-validate-reload.path; do
            printf 'enabled_%s=%s\n' "${action30a_unit//[^a-zA-Z0-9]/_}" \
                "$(systemctl is-enabled "$action30a_unit" 2>/dev/null || true)"
            printf 'active_%s=%s\n' "${action30a_unit//[^a-zA-Z0-9]/_}" \
                "$(systemctl is-active "$action30a_unit" 2>/dev/null || true)"
        done
    } >"$action30a_backup_staging/manifest" || {
        rm -rf -- "$action30a_backup_staging"
        return 1
    }
    if ! chmod 0600 "$action30a_backup_staging/manifest" ||
        ! mv -- "$action30a_backup_staging" "$backup_directory"; then
        rm -rf -- "$action30a_backup_staging"
        return 1
    fi
}
restore_enablement() {
    local action30a_unit=$1
    local action30a_token=${action30a_unit//[^a-zA-Z0-9]/_}
    local action30a_state
    local action30a_active

    action30a_state=$(manifest_value "enabled_$action30a_token") || return 1
    action30a_active=$(manifest_value "active_$action30a_token") || return 1
    case "$action30a_state" in
        enabled) systemctl enable "$action30a_unit" >/dev/null 2>&1 || return 1 ;;
        disabled) systemctl disable "$action30a_unit" >/dev/null 2>&1 || return 1 ;;
        masked) systemctl mask "$action30a_unit" >/dev/null 2>&1 || return 1 ;;
        static | indirect | generated | transient | '') ;;
        *) return 1 ;;
    esac
    case "$action30a_active" in
        active) systemctl start "$action30a_unit" >/dev/null 2>&1 || return 1 ;;
        inactive) systemctl stop "$action30a_unit" >/dev/null 2>&1 || return 1 ;;
        failed) return 1 ;;
        *) ;;
    esac
}
rollback() {
    local action30a_unit

    check backup_manifest_regular test -f "$backup_directory/manifest" || return 1
    install -o root -g root -m 0644 "$backup_directory/caddy-validate-reload.path" "$obsolete_path" || return 1
    install -o root -g root -m 0644 "$backup_directory/caddy-validate-reload.service" "$obsolete_service" || return 1
    systemctl daemon-reload || return 1
    for action30a_unit in "${persistent_units[@]}" caddy-api.service "$distribution_lsyncd_unit" caddy-validate-reload.path; do
        restore_enablement "$action30a_unit" || return 1
    done
    continuity || return 1
    printf '%s_%s_rollback_complete=true\n' "$prefix" "$node_token"
}
apply() {
    local action30a_cert_journal_since
    local action30a_health_journal_since
    local action30a_status_age

    continuity || return 1
    check backup_absent test ! -e "$backup_directory" || return 1
    check obsolete_path_regular test -f "$obsolete_path" || return 1
    check obsolete_path_not_symlink test ! -L "$obsolete_path" || return 1
    check obsolete_path_hash test "$(file_hash "$obsolete_path")" = "$obsolete_path_sha256" || return 1
    check obsolete_service_regular test -f "$obsolete_service" || return 1
    check obsolete_service_not_symlink test ! -L "$obsolete_service" || return 1
    check obsolete_service_hash test "$(file_hash "$obsolete_service")" = "$obsolete_service_sha256" || return 1
    check obsolete_path_inactive active_exact caddy-validate-reload.path inactive || return 1
    check caddy_api_masked_before enabled_exact caddy-api.service masked || return 1
    check caddy_api_inactive_before active_exact caddy-api.service inactive || return 1
    check distribution_lsyncd_masked_before enabled_exact "$distribution_lsyncd_unit" masked || return 1
    check distribution_lsyncd_inactive_before active_exact "$distribution_lsyncd_unit" inactive || return 1
    check static_enablement_before static_enablement_contract || return 1
    record_backup || return 1
    mutation_started=true
    if action30a_status_age=$(lsyncd_status_age 2>/dev/null); then
        printf '%s_%s_lsyncd_status_age_before=%s\n' "$prefix" "$node_token" "$action30a_status_age"
    else
        printf '%s_%s_lsyncd_status_age_before=unavailable\n' "$prefix" "$node_token"
    fi
    if ! lsyncd_status_fresh; then
        run_captured restart_managed_lsyncd systemctl restart caddy-lsyncd.service || return 1
    else
        printf '%s_%s_restart_managed_lsyncd=not_required\n' "$prefix" "$node_token"
    fi
    check lsyncd_status_fresh_after_wait wait_for_fresh_lsyncd_status || return 1
    printf '%s_%s_lsyncd_status_age_after=%s\n' "$prefix" "$node_token" "$(lsyncd_status_age)"
    check lsyncd_status_writer_advances wait_for_lsyncd_status_advance || return 1
    check lsyncd_status_fresh_after_advance lsyncd_status_fresh || return 1
    if systemctl is-failed --quiet caddy-sync-health.service; then
        run_captured reset_failed_health_worker systemctl reset-failed caddy-sync-health.service || return 1
    else
        printf '%s_%s_reset_failed_health_worker=not_required\n' "$prefix" "$node_token"
    fi
    check health_worker_nonfailed_after_reset unit_not_failed caddy-sync-health.service || return 1
    run_captured disable_obsolete_path systemctl disable --now caddy-validate-reload.path || return 1
    mv -- "$obsolete_path" "$backup_directory/caddy-validate-reload.path.live" || return 1
    mv -- "$obsolete_service" "$backup_directory/caddy-validate-reload.service.live" || return 1
    run_captured daemon_reload systemctl daemon-reload || return 1
    run_captured enable_caddy systemctl enable caddy.service || return 1
    run_captured enable_cert_timer systemctl enable caddy-cert-expiry.timer || return 1
    action30a_cert_journal_since=$(date --iso-8601=seconds) || return 1
    run_captured invoke_cert_worker systemctl start caddy-cert-expiry.service || return 1
    emit_unit_properties cert_worker_properties caddy-cert-expiry.service || return 1
    run_captured cert_worker_journal journalctl -u caddy-cert-expiry.service \
        --since "$action30a_cert_journal_since" --no-pager --no-hostname -o short-iso || return 1
    check cert_worker_acceptance successful_static_worker caddy-cert-expiry.service || return 1
    run_captured start_cert_timer systemctl start caddy-cert-expiry.timer || return 1
    check cert_timer_active active_exact caddy-cert-expiry.timer active || return 1
    run_captured enable_health_timer systemctl enable caddy-sync-health.timer || return 1
    action30a_health_journal_since=$(date --iso-8601=seconds) || return 1
    run_captured invoke_health_worker systemctl start caddy-sync-health.service || return 1
    emit_unit_properties health_worker_properties caddy-sync-health.service || return 1
    run_captured health_worker_journal journalctl -u caddy-sync-health.service \
        --since "$action30a_health_journal_since" --no-pager --no-hostname -o short-iso || return 1
    check health_worker_acceptance successful_static_worker caddy-sync-health.service || return 1
    run_captured start_health_timer systemctl start caddy-sync-health.timer || return 1
    check health_timer_active active_exact caddy-sync-health.timer active || return 1
    run_captured enable_lsyncd systemctl enable caddy-lsyncd.service || return 1
    run_captured enable_reconcile_path systemctl enable caddy-sync-reconcile.path || return 1
    run_captured mask_caddy_api systemctl mask caddy-api.service || return 1
    run_captured mask_distribution_lsyncd systemctl mask "$distribution_lsyncd_unit" || return 1
    target_contract || return 1
    printf '%s\n' committed >"$backup_directory/transaction.complete"
    chmod 0600 "$backup_directory/transaction.complete" || return 1
    transaction_complete=true
    printf '%s_%s_complete=true\n' "$prefix" "$node_token"
}
rollback_on_error() {
    local action30a_status=$?

    trap - EXIT INT TERM
    if [[ "$transaction_complete" = true || "$mutation_started" = false ]]; then
        exit "$action30a_status"
    fi
    printf '%s_%s_rollback_started=true\n' "$prefix" "$node_token" >&2
    if rollback; then
        exit "$action30a_status"
    fi
    printf '%s_%s_manual_intervention_required=true\n' "$prefix" "$node_token" >&2
    exit 125
}
configure_role() {
    role=$1
    node_token=${role//-/_}
    case "$role" in
        node-a) expected_hostname=j1-svpihole0 ;;
        node-b) expected_hostname=j1-svpihole00 ;;
        *) return 64 ;;
    esac
    capture_directory=$evidence_root/$node_token
}
self_test() {
    configure_role "$1" || return 1
    printf '%s_%s_node_contact=false\n' "$prefix" "$node_token"
    printf '%s_%s_self_test_complete=true\n' "$prefix" "$node_token"
}
main() {
    local action30a_mode=${1:-}
    local action30a_role=${2:-}

    configure_role "$action30a_role" || return $?
    install -d -o root -g root -m 0700 "$capture_directory" || return 1
    case "$action30a_mode" in
        --apply)
            trap rollback_on_error EXIT INT TERM
            apply
            trap - EXIT INT TERM
            ;;
        --verify)
            target_contract
            printf '%s_%s_verify_complete=true\n' "$prefix" "$node_token"
            ;;
        --verify-continuity)
            continuity
            printf '%s_%s_verify_continuity_complete=true\n' "$prefix" "$node_token"
            ;;
        --rollback) rollback ;;
        *) return 64 ;;
    esac
}

case "${1:-}" in
    --self-test) [[ $# -eq 2 ]] && self_test "$2" ;;
    --apply | --verify | --verify-continuity | --rollback) [[ $# -eq 2 ]] && main "$@" ;;
    *) exit 64 ;;
esac
