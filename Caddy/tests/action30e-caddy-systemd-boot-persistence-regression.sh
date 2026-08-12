#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_30e_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly transaction=$caddy_root/scripts/apply-caddy-systemd-boot-persistence-action30e.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-systemd-boot-persistence-action30e-outer.sh
readonly health_worker=$caddy_root/scripts/validate-sync-health.sh
readonly lsyncd_unit=$caddy_root/systemd/caddy-lsyncd.service
readonly health_timer=$caddy_root/systemd/caddy-sync-health.timer
fixture_root=

check() {
    local action30e_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action30e_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action30e_regression_label" >&2
    return 1
}
run_outer() {
    local action30e_regression_fail=${1:-}
    local action30e_regression_status=0

    ACTION30E_FAKE_CALLS=$fixture_root/calls \
        ACTION30E_FAKE_PAYLOADS=$fixture_root/payloads \
        ACTION30E_FAKE_FAIL=$action30e_regression_fail \
        CADDY_ACTION30E_SSH_BIN=$fixture_root/fake-ssh \
        CADDY_ACTION30E_EVIDENCE_ROOT=$fixture_root/evidence \
        CADDY_ACTION30E_SKIP_REGRESSION=true \
        CADDY_ACTION30E_SKIP_REPEATED_POLICIES=true \
        /bin/bash "$outer" >"$fixture_root/outer.stdout" \
        2>"$fixture_root/outer.stderr" || action30e_regression_status=$?
    printf '%s\n' "$action30e_regression_status" >"$fixture_root/outer.status"
}
run_regression() {
    local action30e_regression_transaction_sha256
    local action30e_regression_status_file
    local action30e_semantic_stdout

    fixture_root=$(mktemp -d /tmp/action30e-regression.XXXXXX) || return 1
    trap 'rm -rf -- "$fixture_root"' EXIT INT TERM
    action30e_regression_transaction_sha256=$(sha256sum "$transaction" | awk '{ print $1 }') || return 1
    cat >"$fixture_root/fake-ssh" <<'FAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
command_line=${!#}
payload=$(mktemp "$ACTION30E_FAKE_PAYLOADS/payload.XXXXXX")
cat >"$payload"
printf '%s\n' "$command_line" >>"$ACTION30E_FAKE_CALLS"
printf '%s\n' "$(sha256sum "$payload" | awk '{ print $1 }')" >>"$ACTION30E_FAKE_PAYLOADS/hashes"
if [[ -n ${ACTION30E_FAKE_FAIL:-} && $command_line == *"$ACTION30E_FAKE_FAIL"* ]]; then
    exit 1
fi
case "$command_line" in
    *'--apply node-a') printf 'action_30e_remote_node_a_complete=true\n' ;;
    *'--apply node-b') printf 'action_30e_remote_node_b_complete=true\n' ;;
    *'--verify node-a') printf 'action_30e_remote_node_a_verify_complete=true\n' ;;
    *'--verify node-b') printf 'action_30e_remote_node_b_verify_complete=true\n' ;;
    *'--verify-continuity node-a') printf 'action_30e_remote_node_a_verify_continuity_complete=true\n' ;;
    *'--verify-continuity node-b') printf 'action_30e_remote_node_b_verify_continuity_complete=true\n' ;;
    *'--rollback node-a') printf 'action_30e_remote_node_a_rollback_complete=true\n' ;;
    *'--rollback node-b') printf 'action_30e_remote_node_b_rollback_complete=true\n' ;;
    *) exit 64 ;;
esac
FAKE
    chmod 0755 "$fixture_root/fake-ssh" || return 1
    install -d -m 0700 "$fixture_root/payloads" || return 1
    install -m 0600 /dev/null "$fixture_root/calls" || return 1
    install -m 0600 /dev/null "$fixture_root/payloads/hashes" || return 1
    action30e_regression_status_file=$fixture_root/lsyncd.status
    printf 'Lsyncd status report at Tue Aug 11 18:00:00 2026\nSync1 source=/var/lib/caddy-sync/outbound/\nThere are 0 delays\n' \
        >"$action30e_regression_status_file" || return 1

    # conditional-validator-explicit-failures-begin
    check transaction_node_a_self_test /bin/bash "$transaction" --self-test node-a || return 1
    check transaction_node_b_self_test /bin/bash "$transaction" --self-test node-b || return 1
    check transaction_semantic_self_test /bin/bash "$transaction" --semantic-self-test || return 1
    action30e_semantic_stdout=$fixture_root/semantic.stdout
    /bin/bash "$transaction" --semantic-self-test >"$action30e_semantic_stdout" || return 1
    check multiple_node_b_revisions_accepted grep -Fqx \
        'action_30e_remote_role_based_multiple_node_b_revisions_quarantined=true' \
        "$action30e_semantic_stdout" || return 1
    check complete_invalid_inventory_emitted grep -Fqx \
        'action_30e_remote_hidden_symlink_special_complete_inventory_emitted=true' \
        "$action30e_semantic_stdout" || return 1
    check invalid_inventory_rejected grep -Fqx \
        'action_30e_remote_hidden_symlink_special_entries_rejected=true' \
        "$action30e_semantic_stdout" || return 1
    touch -d '2 days ago' "$action30e_regression_status_file" || return 1
    check old_parseable_snapshot_accepted /bin/bash "$health_worker" \
        --validate-status-file "$action30e_regression_status_file" || return 1
    printf 'not an lsyncd status snapshot\n' >"$action30e_regression_status_file" || return 1
    if /bin/bash "$health_worker" --validate-status-file "$action30e_regression_status_file"; then
        return 1
    fi
    printf 'Lsyncd status report at fixture\nSync1 source=/fixture/\001\n' \
        >"$action30e_regression_status_file" || return 1
    if /bin/bash "$health_worker" --validate-status-file "$action30e_regression_status_file"; then
        return 1
    fi
    printf '%s_check_malformed_and_control_snapshots_rejected=true\n' "$prefix"
    check health_worker_source_matches_embedded /bin/bash -c '
        transaction=$1
        worker=$2
        extracted=$3
        compare_worker() {
            awk '\''/^    cat >.*ACTION30E_HEALTH_WORKER/{capture=1; next} /^ACTION30E_HEALTH_WORKER$/{capture=0; exit} capture { print }'\'' \
                "$transaction" >"$extracted" || return 1
            cmp -s "$worker" "$extracted" || return 1
        }
        compare_worker
    ' _ "$transaction" "$health_worker" "$fixture_root/extracted-health-worker" || return 1
    check lsyncd_unit_source_matches_embedded /bin/bash -c '
        transaction=$1
        unit=$2
        extracted=$3
        awk '\''/^    cat >.*ACTION30E_LSYNCD_UNIT/{capture=1; next} /^ACTION30E_LSYNCD_UNIT$/{capture=0; exit} capture { print }'\'' \
            "$transaction" >"$extracted" || return 1
        cmp -s "$unit" "$extracted" || return 1
    ' _ "$transaction" "$lsyncd_unit" "$fixture_root/extracted-lsyncd-unit" || return 1
    check lsyncd_success_exit_status_exact test \
        "$(grep -Fxc 'SuccessExitStatus=143' "$lsyncd_unit")" -eq 1 || return 1
    check lsyncd_success_exit_status_no_broadening test \
        "$(grep -c '^SuccessExitStatus=' "$lsyncd_unit")" -eq 1 || return 1
    check lsyncd_unit_accepted_hash_pinned grep -Fq \
        'accepted_lsyncd_unit_sha256=93cbc36cea03b8b7e1605c44667463592cf64e0293ded9f816d1e34760a69ac8' \
        "$transaction" || return 1
    check lsyncd_unit_corrected_hash_pinned grep -Fq \
        'corrected_lsyncd_unit_sha256=e9139d40f7891485ea423d4a064b9cb162ff1b6234bf27e83d2bb9fbce4c02d2' \
        "$transaction" || return 1
    check corrected_unit_installed_before_lsyncd_transition awk '
        /run_captured install_corrected_lsyncd_unit/ { install = NR }
        /run_captured reload_corrected_lsyncd_unit/ { reload = NR }
        /run_captured stop_lsyncd_for_outbound_quarantine/ { stop = NR }
        /run_captured restart_managed_lsyncd/ { restart = NR }
        END { exit !(install > 0 && reload > install && stop > reload && restart > reload) }
    ' "$transaction" || return 1 # conditional-validator-requires-return
    check reconcile_reset_after_safe_journal awk '
        /check no_new_transport_failure_or_quarantine post_cursor_transport_clean/ { clean = NR }
        /run_captured reset_failed_reconcile_worker/ { reset = NR }
        /check reconcile_worker_nonfailed_after_safe_reset/ { accept = NR }
        END { exit !(clean > 0 && reset > clean && accept > reset) }
    ' "$transaction" || return 1 # conditional-validator-requires-return
    check reconcile_reset_conditional awk '
        /if systemctl is-failed --quiet caddy-sync-reconcile[.]service/ { guard = NR }
        /run_captured reset_failed_reconcile_worker/ { reset = NR }
        END { exit !(guard > 0 && reset > guard) }
    ' "$transaction" || return 1 # conditional-validator-requires-return
    check lsyncd_unit_rollback_restored grep -Fq \
        '"$backup_directory/caddy-lsyncd.service" "$lsyncd_unit"' "$transaction" || return 1
    check lsyncd_unit_acceptance_hash grep -Fq \
        'check lsyncd_unit_hash test "$(file_hash "$lsyncd_unit")" = "$corrected_lsyncd_unit_sha256"' \
        "$transaction" || return 1
    check lsyncd_success_exit_acceptance grep -Fq \
        'check lsyncd_success_exit_status test "$(systemctl show caddy-lsyncd.service -p SuccessExitStatus --value)" = 143' \
        "$transaction" || return 1
    check health_timer_periodic_contract awk '
        $0 == "OnBootSec=2min" { boot++ }
        $0 == "OnUnitActiveSec=1min" { interval++ }
        $0 == "RandomizedDelaySec=10s" { jitter++ }
        END { exit !(boot == 1 && interval == 1 && jitter == 1) }
    ' "$health_timer" || return 1 # conditional-validator-requires-return
    check status_age_contract_absent test -z \
        "$(grep -E 'maximum_lsyncd_status_age|lsyncd_status_(age|fresh)|status.*mtime|wait_for_lsyncd_status_advance' \
            "$transaction" "$health_worker" || true)" || return 1
    check semantic_inventory_precedes_restart awk '
        /run_captured semantic_inventory_before semantic_inventory/ { inventory = NR }
        /run_captured restart_managed_lsyncd systemctl restart/ { restart = NR }
        END { exit !(inventory > 0 && restart > inventory) }
    ' "$transaction" || return 1
    check ineligible_outbound_protected_before_restart awk '
        /run_captured protect_ineligible_outbound protect_ineligible_outbound/ { protect = NR }
        /run_captured restart_managed_lsyncd systemctl restart/ { restart = NR }
        END { exit !(protect > 0 && restart > protect) }
    ' "$transaction" || return 1
    check watcher_stopped_before_quarantine awk '
        /run_captured stop_lsyncd_for_outbound_quarantine/ { stop = NR }
        /run_captured protect_ineligible_outbound protect_ineligible_outbound/ { protect = NR }
        END { exit !(stop > 0 && protect > stop) }
    ' "$transaction" || return 1
    check snapshot_rechecked_after_stop awk '
        /check outbound_snapshot_unchanged_after_stop/ { snapshot = NR }
        /run_captured protect_ineligible_outbound protect_ineligible_outbound/ { protect = NR }
        END { exit !(snapshot > 0 && protect > snapshot) }
    ' "$transaction" || return 1
    check accepted_current_revision_pinned grep -Fq \
        '20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04' \
        "$transaction" || return 1
    check historical_quarantine_revision_pinned grep -Fq \
        '20260811T180716Z-d45a4dc3-64b6-47c5-bebc-02dade4d9ec4' \
        "$transaction" || return 1
    check historical_parent_pinned grep -Fq \
        '20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63' \
        "$transaction" || return 1
    check protected_action30c_older_quarantine_pinned grep -Fq \
        'node_b-outbound-${older_historical_revision}-action30c' "$transaction" || return 1
    check protected_action30c_newer_quarantine_pinned grep -Fq \
        'node_b-outbound-${historical_revision}-action30c' "$transaction" || return 1
    check protected_action30c_quarantines_validated grep -Fq \
        'protected_node_b_quarantines_exact' "$transaction" || return 1
    check role_based_policy grep -Fq \
        'candidate_disposition()' "$transaction" || return 1
    check complete_entry_name_emission grep -Fq \
        'outbound_entry_%s_name_q=%q' "$transaction" || return 1
    check complete_entry_type_emission grep -Fq \
        'outbound_entry_%s_type=%s' "$transaction" || return 1
    check node_b_all_candidates_quarantined grep -Fq \
        '[[ "$action30e_source" = node-b ]]' "$transaction" || return 1
    check node_a_exact_current_identity_compared grep -Fq \
        '"$(file_hash "$action30e_current_candidate/manifest.sha256")"' \
        "$transaction" || return 1
    check role_state_pinned grep -Fq \
        'check coupled_role_state role_state_exact' "$transaction" || return 1
    check journal_cursor_production grep -Fq \
        'journalctl --show-cursor -n 0 --no-pager' "$transaction" || return 1
    check journal_after_cursor_production grep -Fq -- \
        '--after-cursor "$sync_journal_cursor"' "$transaction" || return 1
    check timestamp_boundary_absent test -z \
        "$(grep -F -- '--since' "$transaction" || true)" || return 1
    check post_cursor_transport_rejection grep -Fq \
        'no_new_transport_failure_or_quarantine' "$transaction" || return 1
    check lsyncd_stability_samples grep -Fq \
        'lsyncd_stability_samples=5' "$transaction" || return 1
    check obsolete_source_units_absent test ! -e "$caddy_root/systemd/caddy-validate-reload.path" || return 1
    check obsolete_source_service_absent test ! -e "$caddy_root/systemd/caddy-validate-reload.service" || return 1
    check caddy_enabled_target grep -Fq 'caddy.service' "$transaction" || return 1
    check timers_enabled_target grep -Fq 'caddy-cert-expiry.timer' "$transaction" || return 1
    check health_timer_enabled_target grep -Fq 'caddy-sync-health.timer' "$transaction" || return 1
    check invalid_snapshot_restart_boundary grep -Fq 'restart_managed_lsyncd systemctl restart caddy-lsyncd.service' "$transaction" || return 1
    check corrected_health_worker_staged grep -Fq 'create_health_worker_candidate' "$transaction" || return 1
    check corrected_health_worker_installed grep -Fq \
        'install_corrected_health_worker install -o root -g root -m 0755' "$transaction" || return 1
    check corrected_health_worker_hash_pinned grep -Fq \
        'corrected_health_worker_sha256=91df406d38b3fbceec28a1adb188da0d996b3916521934318948b4e289fb85d4' \
        "$transaction" || return 1
    check health_worker_rollback_restored grep -Fq \
        '"$backup_directory/validate-sync-health.sh" "$health_worker"' "$transaction" || return 1
    check failed_health_reset_boundary grep -Fq 'reset_failed_health_worker systemctl reset-failed caddy-sync-health.service' "$transaction" || return 1
    check cert_worker_invoked grep -Fq 'invoke_cert_worker systemctl start caddy-cert-expiry.service' "$transaction" || return 1
    check health_worker_invoked grep -Fq 'invoke_health_worker systemctl start caddy-sync-health.service' "$transaction" || return 1
    check cert_worker_journal_captured grep -Fq 'cert_worker_journal journalctl -u caddy-cert-expiry.service' "$transaction" || return 1
    check health_worker_journal_captured grep -Fq 'health_worker_journal journalctl -u caddy-sync-health.service' "$transaction" || return 1
    check static_units_not_enabled test -z \
        "$(grep -E 'systemctl enable.*caddy-(cert-expiry|sync-health|sync-reconcile)[.]service' "$transaction" || true)" || return 1
    check distribution_lsyncd_masked grep -Fq 'mask_distribution_lsyncd' "$transaction" || return 1
    check emergency_service_static grep -Fqx '    emergency.service' "$transaction" || return 1
    check emergency_service_not_enabled test -z \
        "$(grep -E 'systemctl enable.*emergency[.]service' "$transaction" || true)" || return 1
    check obsolete_pair_moved grep -Fq 'mv -- "$obsolete_service"' "$transaction" || return 1
    check rollback_restores_pair grep -Fq '"$backup_directory/caddy-validate-reload.service" "$obsolete_service"' "$transaction" || return 1
    check rollback_retains_quarantine grep -Fq \
        'protected_outbound_retained_count=%s' "$transaction" || return 1
    check standby_first_source awk '
        /run_remote node-b-apply/ { standby = NR }
        /run_remote node-a-apply/ { primary = NR }
        END { exit !(standby > 0 && primary > standby) }
    ' "$outer" || return 1
    run_outer || return 1
    check success_status test "$(cat "$fixture_root/outer.status")" -eq 0 || return 1
    check success_complete grep -Fqx 'action_30e_outer_complete=true' "$fixture_root/outer.stdout" || return 1
    check success_order diff -u - "$fixture_root/calls" <<'ORDER' || return 1
cd / && sudo -n /bin/bash -s -- --apply node-b
cd / && sudo -n /bin/bash -s -- --verify-continuity node-a
cd / && sudo -n /bin/bash -s -- --apply node-a
cd / && sudo -n /bin/bash -s -- --verify node-b
cd / && sudo -n /bin/bash -s -- --verify node-a
ORDER
    check exact_generated_payload awk -v expected="$action30e_regression_transaction_sha256" '
        $0 != expected { exit 1 }
        END { exit !(NR == 5) }
    ' "$fixture_root/payloads/hashes" || return 1
    : >"$fixture_root/calls"
    : >"$fixture_root/payloads/hashes"
    run_outer '--verify node-b' || return 1
    check recovery_status test "$(cat "$fixture_root/outer.status")" -eq 1 || return 1
    check recovery_proven grep -Fqx 'action_30e_outer_recovery_proven=true' "$fixture_root/outer.stdout" || return 1
    check reverse_rollback_order awk '
        /--rollback node-a/ { primary = NR }
        /--rollback node-b/ { standby = NR }
        END { exit !(primary > 0 && standby > primary) }
    ' "$fixture_root/calls" || return 1
    # conditional-validator-explicit-failures-end
    printf '%s_actual_generated_remote_program=true\n' "$prefix"
    printf '%s_capture_path_covered=true\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

run_regression
