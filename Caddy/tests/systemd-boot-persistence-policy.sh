#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=systemd_boot_persistence_policy
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly agents_file=$caddy_root/../AGENTS.md
readonly transaction=$caddy_root/scripts/apply-caddy-systemd-boot-persistence-action30e.sh
readonly health_worker=$caddy_root/scripts/validate-sync-health.sh
readonly lsyncd_unit=$caddy_root/systemd/caddy-lsyncd.service

check() {
    local systemd_policy_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$systemd_policy_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$systemd_policy_label" >&2
    return 1
}
run_checks() {
    local systemd_policy_unit

    # conditional-validator-explicit-failures-begin
    check obsolete_path_source_absent test ! -e "$caddy_root/systemd/caddy-validate-reload.path" || return 1
    check obsolete_service_source_absent test ! -e "$caddy_root/systemd/caddy-validate-reload.service" || return 1
    check transaction_regular test -f "$transaction" || return 1
    check transaction_not_symlink test ! -L "$transaction" || return 1
    check persistent_enabled_gate grep -Fq \
        'check "${action30e_unit//[^a-zA-Z0-9]/_}_enabled" enabled_exact "$action30e_unit" enabled' \
        "$transaction" || return 1
    check persistent_active_gate grep -Fq \
        'check "${action30e_unit//[^a-zA-Z0-9]/_}_active" active_exact "$action30e_unit" active' \
        "$transaction" || return 1
    for systemd_policy_unit in \
        caddy.service caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-cert-expiry.timer caddy-sync-health.timer; do
        check "${systemd_policy_unit//[^a-zA-Z0-9]/_}_persistent_member" grep -Fqx \
            "    $systemd_policy_unit" "$transaction" || return 1
    done
    check caddy_api_masked_gate grep -Fq 'check caddy_api_masked enabled_exact caddy-api.service masked' "$transaction" || return 1
    check caddy_api_inactive_gate grep -Fq 'check caddy_api_inactive active_exact caddy-api.service inactive' "$transaction" || return 1
    check distribution_lsyncd_masked_gate grep -Fq 'check distribution_lsyncd_masked enabled_exact "$distribution_lsyncd_unit" masked' "$transaction" || return 1
    check distribution_lsyncd_inactive_gate grep -Fq 'check distribution_lsyncd_inactive active_exact "$distribution_lsyncd_unit" inactive' "$transaction" || return 1
    check emergency_static_member grep -Fqx '    emergency.service' "$transaction" || return 1
    check emergency_static_gate grep -Fq 'check emergency_service_static enabled_exact emergency.service static' "$transaction" || return 1
    check certificate_worker_gate grep -Fq 'check cert_worker_success successful_static_worker caddy-cert-expiry.service' "$transaction" || return 1
    check health_worker_gate grep -Fq 'check health_worker_success successful_static_worker caddy-sync-health.service' "$transaction" || return 1
    check lsyncd_status_snapshot_gate grep -Fq \
        'check lsyncd_status_snapshot_valid lsyncd_status_snapshot_valid' "$transaction" || return 1
    check status_age_contract_absent test -z \
        "$(grep -E 'maximum_lsyncd_status_age|lsyncd_status_(age|fresh)|status.*mtime|wait_for_lsyncd_status_advance' \
            "$transaction" "$health_worker" || true)" || return 1
    check health_worker_service_state grep -Fq \
        '[[ "$(service_property SubState)" = running ]]' "$health_worker" || return 1
    check health_worker_main_pid grep -Fq \
        '[[ "$sync_health_main_pid" =~ ^[1-9][0-9]*$ ]]' "$health_worker" || return 1
    check health_worker_restart_count grep -Fq \
        '[[ "$sync_health_restarts" =~ ^[0-9]+$ ]]' "$health_worker" || return 1
    check health_worker_parseable_snapshot grep -Fq \
        "grep -Eq '^Lsyncd status report at .+\$'" "$health_worker" || return 1
    check semantic_inventory_gate grep -Fq 'run_captured semantic_inventory_before semantic_inventory' "$transaction" || return 1
    check outbound_protection_gate grep -Fq 'run_captured protect_ineligible_outbound protect_ineligible_outbound' "$transaction" || return 1
    check journal_cursor_gate grep -Fq 'capture_cursor sync_journal_cursor' "$transaction" || return 1
    check post_cursor_transport_gate grep -Fq 'check no_new_transport_failure_or_quarantine post_cursor_transport_clean' "$transaction" || return 1
    check lsyncd_stability_gate grep -Fq 'run_captured lsyncd_stability lsyncd_stable' "$transaction" || return 1
    check lsyncd_success_exit_exact test "$(grep -Fxc 'SuccessExitStatus=143' "$lsyncd_unit")" -eq 1 || return 1
    check lsyncd_unit_install_gate grep -Fq 'run_captured install_corrected_lsyncd_unit' "$transaction" || return 1
    check reconcile_reset_gate grep -Fq 'run_captured reset_failed_reconcile_worker' "$transaction" || return 1
    check reconcile_reset_after_transport_clean awk '
        /check no_new_transport_failure_or_quarantine post_cursor_transport_clean/ { clean = NR }
        /run_captured reset_failed_reconcile_worker/ { reset = NR }
        END { exit !(clean > 0 && reset > clean) }
    ' "$transaction" || return 1 # conditional-validator-requires-return
    check obsolete_path_absence_gate grep -Fq 'check obsolete_path_absent test ! -e "$obsolete_path"' "$transaction" || return 1
    check obsolete_service_absence_gate grep -Fq 'check obsolete_service_absent test ! -e "$obsolete_service"' "$transaction" || return 1
    check repository_rule grep -Fq 'Production service acceptance must validate boot persistence' "$agents_file" || return 1
    # conditional-validator-explicit-failures-end
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --check) run_checks ;;
    *) exit 64 ;;
esac
