#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2034,SC2317

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly transaction=$caddy_root/scripts/transact-caddy-ha-reliability-action33f.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-ha-reliability-action33f-outer.sh
readonly manifest=$caddy_root/manifests/caddy-ha-reliability-action33f.yaml
readonly production_publisher=$caddy_root/scripts/publish-release-v2.sh
readonly production_finalizer=$caddy_root/scripts/finalize-incoming-release-v2-stderr-safe-trigger-action28ac.sh
readonly production_reconciler=$caddy_root/scripts/reconcile-release-v2.sh
fixture_root=

cleanup() {
    if [[ -n "$fixture_root" && -d "$fixture_root" ]]; then
        chmod -R u+w "$fixture_root"
        rm -rf -- "$fixture_root"
    fi
}
trap cleanup EXIT INT TERM

require_literal() { grep -Fq -- "$1" "$2"; }
reject_literal() { ! grep -Fq -- "$1" "$2"; }
for file in "$transaction" "$outer" "$manifest"; do [[ -f "$file" && ! -L "$file" ]]; done
/bin/bash -n "$transaction"
/bin/bash -n "$outer"
/bin/bash "$production_publisher" --help >/dev/null 2>&1
/bin/bash "$production_finalizer" --self-test >/dev/null
/bin/bash "$production_reconciler" --candidate-selection-self-test >/dev/null
CADDY_ACTION33F_SSH_BIN=/bin/false /bin/bash "$outer" --self-test >/tmp/action33f-self-test.stdout
grep -Fxq 'action_33f_outer_self_test_complete=true' /tmp/action33f-self-test.stdout
rm -f -- /tmp/action33f-self-test.stdout

require_literal 'cd / && sudo -n /bin/bash' "$outer"
require_literal '-s -- $mode $role $run_id $scenario $argument' "$outer"
require_literal 'capture_files "$action33f_outer_stdout" "$action33f_outer_stderr" "$action33f_outer_status_file"' "$outer"
require_literal 'wait_ssh_state a-down' "$outer"
require_literal 'wait_ssh_state b-down' "$outer"
require_literal 'wait_ssh_state a-up' "$outer"
require_literal 'wait_ssh_state b-up' "$outer"
require_literal 'cat /proc/sys/kernel/random/boot_id' "$transaction"
require_literal 'systemctl disable --now keepalived.service' "$transaction"
require_literal 'systemd-run --unit "caddy-action33f-reboot-$run_id-$scenario"' "$transaction"
require_literal 'systemd-run --unit "$action33f_remote_unit" --on-active=45s' "$transaction"
require_literal '--publish-emergency' "$outer"
require_literal '--reject-normal' "$outer"
require_literal 'sleep 12' "$outer"
require_literal 'action33f-$run_id-' "$outer"
require_literal 'action33e_invalid_release_consumed' "$outer"
require_literal 'action33e_interrupted_transfer_consumed' "$outer"
reject_literal '--stage-invalid "$scenario"' "$outer"
reject_literal '--stage-active-replay "$scenario"' "$outer"
reject_literal '--assert-replay-incomplete "$scenario"' "$outer"
require_literal '--start-conflict-transport' "$outer"
require_literal '--assert-conflict "$scenario"' "$outer"
require_literal '--freeze-conflict-transport' "$outer"
require_literal '--assert-conflict-retained' "$outer"
require_literal 'inventory_tree "$quarantine_root"' "$transaction"
require_literal 'assert_outbound_role_policy "$role"' "$transaction"
reject_literal 'check outbound_empty' "$transaction"
reject_literal 'check node_a_outbound_present' "$transaction"
require_literal 'check node_a_outbound_entries_admissible test' "$transaction"
require_literal 'assert_replay_destination_absent "$action33f_remote_destination"' "$transaction"
require_literal 'suspend_sync_health_for_lsyncd_outage publish' "$transaction"
require_literal 'accept_and_freeze_invalid_receiver_rejection' "$transaction"
require_literal 'caddy_sync_finalize_v2_check_manifest_file_set_exact=false' "$transaction"
require_literal 'invalid_transport_lsyncd_freeze' "$transaction"
reject_literal 'invalid_transport_lsyncd_failed' "$transaction"
reject_literal 'invalid_transport_lsyncd_exec_status_255' "$transaction"
require_literal 'restore_and_accept_sync_health publish' "$transaction"
require_literal 'suspend_sync_health_for_lsyncd_outage fixture_freeze' "$transaction"
require_literal 'restore_and_accept_sync_health restore_services' "$transaction"
require_literal 'prepare_current_health_baseline' "$transaction"
require_literal 'prepare_cleanup_services' "$transaction"
require_literal 'cleanup_health_timer_enable' "$transaction"
require_literal '--restore-health' "$outer"
require_literal 'health-restore-a' "$outer"
require_literal 'health-restore-b' "$outer"
reject_literal 'systemctl start ssh.service caddy.service caddy-lsyncd.service caddy-sync-reconcile.path caddy-sync-health.timer' "$transaction"
replay_absence_line=$(grep -nF 'assert_replay_destination_absent "$action33f_remote_destination"' "$transaction" | cut -d: -f1)
replay_freeze_line=$(grep -nF 'run_captured replay_transport_freeze systemctl stop caddy-lsyncd.service' "$transaction" | cut -d: -f1)
[[ "$replay_absence_line" -lt "$replay_freeze_line" ]]
require_literal 'release-manifest.sha256' "$transaction"
require_literal 'original_release_path_restored' "$transaction"
require_literal 'original_release_manifest_restored' "$transaction"
require_literal 'publish_owned "$argument" false' "$transaction"
require_literal 'publish_owned "$argument" true' "$transaction"
require_literal 'assert_invalid_rejected "$argument"' "$transaction"
require_literal 'assert_replay_incomplete "$argument"' "$transaction"
require_literal 'assert_conflict "$argument"' "$transaction"
require_literal 'assert_conflict_retained "$argument"' "$transaction"
require_literal 'conflict_caddy_reload_absent' "$transaction"
require_literal 'conflict_caddy_pid_unchanged' "$transaction"
require_literal 'conflict_caddy_restart_count_unchanged' "$transaction"
reject_literal 'transport_start_lsyncd_pid_stable' "$transaction"
require_literal 'active_replay_consumed_once' "$transaction"
require_literal '--rolling-maintenance' "$outer"
require_literal 'rolling-b' "$outer"
require_literal 'rolling-a' "$outer"
require_literal 'exit 125' "$outer"
require_literal 'registry_uploaded_a=false' "$outer"
require_literal 'registry_uploaded_b=false' "$outer"
require_literal 'recovery-remove-registry-a' "$outer"
require_literal 'recovery-remove-registry-b' "$outer"
require_literal '--remove-registry final-acceptance' "$outer"
require_literal 'historical-complete-suite' "$manifest"
reject_literal 'Caddy/tests/run.sh' "$outer"

baseline_case=$(sed -n '/^[[:space:]]*--baseline)/,/^[[:space:]]*--assert-master)/p' \
    "$transaction")
if grep -Fq 'prepare_fixture_source' <<<"$baseline_case"; then exit 1; fi
if grep -Fq 'publish_owned' <<<"$baseline_case"; then exit 1; fi
if grep -Fq 'outgoing_root/' <<<"$baseline_case"; then exit 1; fi
require_literal 'production_state_seeding_to_satisfy_assertions: prohibited' \
    "$manifest"
require_literal 'pid_stability_during_deliberate_transport: not-required' \
    "$manifest"
require_literal 'completed_cases_consumed_without_replay:' "$manifest"

fixture_root=$(mktemp -d /tmp/action33f-regression.XXXXXX)
chmod 0700 "$fixture_root"
sed -e '/^if \[\[ "$mode" = --self-test/,$d' \
    -e "s#^readonly evidence_base=.*#evidence_base=$fixture_root/node-evidence#" \
    -e "s#^readonly releases_root=.*#releases_root=$fixture_root/releases#" \
    -e "s#^readonly incoming_root=.*#incoming_root=$fixture_root/incoming#" \
    -e "s#^readonly outgoing_root=.*#outgoing_root=$fixture_root/outbound#" \
    -e "s#^readonly quarantine_root=.*#quarantine_root=$fixture_root/quarantine#" \
    "$transaction" >"$fixture_root/definitions.sh"
source "$fixture_root/definitions.sh"
run_id=fixture-run
scenario=node-a-controlled
role=node-a
node_token=node_a
evidence_directory=$fixture_root/evidence
install -d -m 0700 "$evidence_directory" "$fixture_root/bin"
cat >"$fixture_root/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >"${ACTION33_SYSTEMCTL_CAPTURE:?}"
SYSTEMCTL
chmod 0700 "$fixture_root/bin/systemctl"
render_controlled_recovery_script "$fixture_root/recovery.sh"
chmod 0700 "$fixture_root/recovery.sh"
/bin/bash -n "$fixture_root/recovery.sh"
env ACTION33_SYSTEMCTL_CAPTURE="$fixture_root/systemctl.capture" \
    PATH="$fixture_root/bin:/usr/bin:/bin" /bin/bash "$fixture_root/recovery.sh"
grep -Fxq true "$evidence_directory/control-recovery-pretransport"
grep -Fxq 'start ssh.service caddy.service caddy-lsyncd.service caddy-sync-reconcile.path' \
    "$fixture_root/systemctl.capture"

# Exercise the actual health-guard functions with a stateful systemctl fake.
health_trace=$fixture_root/health.trace
timer_state=active
timer_enabled=enabled
worker_state=failed
worker_result=success
lsyncd_state=active
systemctl() {
    printf '%s\n' "$*" >>"$health_trace"
    case "$1:$2" in
        is-active:caddy-sync-health.timer)
            printf '%s\n' "$timer_state"
            [[ "$timer_state" = active ]]
            ;;
        is-enabled:caddy-sync-health.timer)
            printf '%s\n' "$timer_enabled"
            [[ "$timer_enabled" = enabled ]]
            ;;
        is-active:caddy-sync-health.service)
            printf 'inactive\n'
            return 3
            ;;
        is-active:caddy-lsyncd.service)
            [[ "$lsyncd_state" = active ]]
            ;;
        is-failed:caddy-sync-health.service)
            printf '%s\n' "$worker_state"
            [[ "$worker_state" = failed ]]
            ;;
        stop:caddy-sync-health.timer)
            timer_state=inactive
            ;;
        stop:caddy-sync-health.service) ;;
        stop:caddy-lsyncd.service)
            lsyncd_state=inactive
            ;;
        start:caddy-lsyncd.service)
            lsyncd_state=active
            ;;
        reset-failed:caddy-sync-health.service)
            worker_state=inactive
            ;;
        start:caddy-sync-health.service)
            worker_state=inactive
            worker_result=success
            ;;
        enable:caddy-sync-health.timer)
            timer_enabled=enabled
            ;;
        start:caddy-sync-health.timer)
            timer_state=active
            ;;
        show:caddy-lsyncd.service)
            case "$*" in
                *'-p MainPID --value'*) printf '4242\n' ;;
                *'-p NRestarts --value'*) printf '0\n' ;;
                *'-p Result --value'*) printf 'success\n' ;;
                *) printf 'ActiveState=active\nSubState=running\nResult=success\nMainPID=4242\nNRestarts=0\n' ;;
            esac
            ;;
        show:caddy-sync-health.service)
            case "$*" in
                *'-p Result --value'*) printf '%s\n' "$worker_result" ;;
            esac
            ;;
        show:caddy-sync-health.timer)
            printf 'ActiveState=%s\nUnitFileState=%s\n' "$timer_state" \
                "$timer_enabled"
            ;;
        *) return 0 ;;
    esac
}
sleep() { :; }
{
    suspend_sync_health_for_lsyncd_outage production_path
    run_captured production_path_lsyncd_stop systemctl stop \
        caddy-lsyncd.service
    restore_and_accept_sync_health production_path
} >"$fixture_root/health.stdout"
timer_stop_line=$(grep -nFx 'stop caddy-sync-health.timer' "$health_trace" | head -n 1 | cut -d: -f1)
lsyncd_stop_line=$(grep -nFx 'stop caddy-lsyncd.service' "$health_trace" | head -n 1 | cut -d: -f1)
lsyncd_start_line=$(grep -nFx 'start caddy-lsyncd.service' "$health_trace" | tail -n 1 | cut -d: -f1)
worker_reset_line=$(grep -nFx 'reset-failed caddy-sync-health.service' "$health_trace" | tail -n 1 | cut -d: -f1)
worker_run_line=$(grep -nFx 'start caddy-sync-health.service' "$health_trace" | tail -n 1 | cut -d: -f1)
timer_start_line=$(grep -nFx 'start caddy-sync-health.timer' "$health_trace" | tail -n 1 | cut -d: -f1)
[[ "$timer_stop_line" -lt "$lsyncd_stop_line" ]]
[[ "$lsyncd_stop_line" -lt "$lsyncd_start_line" ]]
[[ "$lsyncd_start_line" -lt "$worker_reset_line" ]]
[[ "$worker_reset_line" -lt "$worker_run_line" ]]
[[ "$worker_run_line" -lt "$timer_start_line" ]]
grep -Fq 'check_production_path_health_worker_result_success=true' \
    "$fixture_root/health.stdout"
grep -Fq 'check_production_path_health_worker_nonfailed=true' \
    "$fixture_root/health.stdout"
grep -Fq 'check_production_path_health_timer_active_after=true' \
    "$fixture_root/health.stdout"
[[ "$timer_state" = active && "$timer_enabled" = enabled ]]

# Exercise the actual receiver-rejection boundary with lsyncd remaining active
# until the transaction observes the exact journal record and freezes it.
receiver_mode=rejected
transport_state=inactive
systemctl() {
    printf '%s\n' "$*" >>"$health_trace"
    case "$1:$2" in
        is-active:caddy-sync-health.timer)
            printf 'inactive\n'
            return 3
            ;;
        is-enabled:caddy-sync-health.timer) return 0 ;;
        start:caddy-lsyncd.service)
            transport_state=active
            return 0
            ;;
        stop:caddy-lsyncd.service)
            transport_state=inactive
            return 0
            ;;
        is-active:caddy-lsyncd.service)
            printf '%s\n' "$transport_state"
            [[ "$transport_state" = active ]]
            ;;
        show:caddy-lsyncd.service)
            printf 'ActiveState=%s\nSubState=dead\nResult=success\nMainPID=0\nExecMainStatus=0\nNRestarts=0\n' \
                "$transport_state"
            ;;
        *) return 0 ;;
    esac
}
journalctl() {
    case "$*" in
        *'--show-cursor'*) printf '%s\n' '-- cursor: fixture-cursor' ;;
        *'--after-cursor fixture-cursor'*)
            if [[ "$receiver_mode" = rejected ]]; then
                printf '%s\n' 'receiver-rejection-observed' >>"$health_trace"
                printf '%s\n' \
                    'caddy_sync_finalize_v2_check_manifest_file_set_exact=false'
            else
                printf '%s\n' 'lsyncd transport active without rejection'
            fi
            ;;
        *) return 1 ;;
    esac
}
accept_and_freeze_invalid_receiver_rejection \
    >"$fixture_root/invalid-transport.stdout"
grep -Fq 'check_invalid_transport_receiver_rejection_observed=true' \
    "$fixture_root/invalid-transport.stdout"
grep -Fq 'check_invalid_transport_receiver_journal_status_zero=true' \
    "$fixture_root/invalid-transport.stdout"
grep -Fq 'check_invalid_transport_lsyncd_frozen=true' \
    "$fixture_root/invalid-transport.stdout"
grep -Fq 'check_invalid_transport_health_timer_remains_suspended=true' \
    "$fixture_root/invalid-transport.stdout"
receiver_rejection_line=$(grep -nFx 'receiver-rejection-observed' \
    "$health_trace" | tail -n 1 | cut -d: -f1)
invalid_freeze_line=$(grep -nFx 'stop caddy-lsyncd.service' \
    "$health_trace" | tail -n 1 | cut -d: -f1)
[[ "$receiver_rejection_line" -lt "$invalid_freeze_line" ]]
receiver_mode=clean
transport_state=inactive
if accept_and_freeze_invalid_receiver_rejection \
    >"$fixture_root/invalid-transport-wrong.stdout" \
    2>"$fixture_root/invalid-transport-wrong.stderr"; then
    printf 'action33f regression accepted transport without receiver rejection\n' >&2
    exit 1
fi
grep -Fq 'check_invalid_transport_receiver_rejection_observed=false' \
    "$fixture_root/invalid-transport-wrong.stderr"

stage_invalid_case=$(sed -n \
    '/^stage_invalid()/,/^assert_invalid_rejected()/p' "$transaction")
grep -Fq 'accept_and_freeze_invalid_receiver_rejection' <<<"$stage_invalid_case"
if grep -Fq 'restore_and_accept_sync_health invalid_transport' \
    <<<"$stage_invalid_case"; then
    printf 'action33f regression found the consumed PID-stability contract\n' >&2
    exit 1
fi

# Exercise the generated conflict transport boundary with a changing PID. The
# deliberate transport interval requires a successful active start and positive
# PID, but stability is enforced only after guarded restoration.
transport_state=inactive
transport_pid=7000
timer_state=inactive
timer_enabled=enabled
systemctl() {
    printf '%s\n' "$*" >>"$health_trace"
    case "$1:$2" in
        is-active:caddy-sync-health.timer)
            printf '%s\n' "$timer_state"
            return 3
            ;;
        is-enabled:caddy-sync-health.timer)
            [[ "$timer_enabled" = enabled ]]
            ;;
        start:caddy-lsyncd.service)
            transport_state=active
            transport_pid=$((transport_pid + 1))
            ;;
        stop:caddy-lsyncd.service)
            transport_state=inactive
            ;;
        is-active:caddy-lsyncd.service)
            printf '%s\n' "$transport_state"
            [[ "$transport_state" = active ]]
            ;;
        show:caddy-lsyncd.service)
            case "$*" in
                *'-p MainPID --value'*) printf '%s\n' "$transport_pid" ;;
                *)
                    printf 'ActiveState=%s\nSubState=running\nResult=success\nMainPID=%s\nNRestarts=1\n' \
                        "$transport_state" "$transport_pid"
                    ;;
            esac
            ;;
        *) return 0 ;;
    esac
}
start_conflict_transport >"$fixture_root/conflict-transport.stdout"
grep -Fq 'check_conflict_transport_active=true' \
    "$fixture_root/conflict-transport.stdout"
grep -Fq 'check_conflict_transport_pid_positive=true' \
    "$fixture_root/conflict-transport.stdout"
if grep -Fq 'pid_stable' "$fixture_root/conflict-transport.stdout"; then
    printf 'action33f regression found PID stability inside conflict transport\n' >&2
    exit 1
fi
freeze_conflict_transport >"$fixture_root/conflict-freeze.stdout"
grep -Fq 'check_conflict_transport_inactive=true' \
    "$fixture_root/conflict-freeze.stdout"
conflict_start_line=$(grep -nFx 'start caddy-lsyncd.service' "$health_trace" |
    tail -n 1 | cut -d: -f1)
conflict_freeze_line=$(grep -nFx 'stop caddy-lsyncd.service' "$health_trace" |
    tail -n 1 | cut -d: -f1)
[[ "$conflict_start_line" -lt "$conflict_freeze_line" ]]

fixture_releases=$fixture_root/releases
fixture_outbound=$fixture_root/outbound
fixture_empty_outbound=$fixture_root/empty-outbound
fixture_revision=fixture-current
fixture_current=$fixture_releases/$fixture_revision
install -d -m 0700 "$fixture_releases" "$fixture_outbound" \
    "$fixture_empty_outbound" "$fixture_current"
printf '%s\n' '{' \
    '  "revision": "fixture-current",' \
    '  "parent_revision": "fixture-parent",' \
    '  "source_node": "node-a",' \
    '  "created_at": "2026-08-12T00:00:00Z"' \
    '}' >"$fixture_current/release-manifest.json"
printf 'fixture payload\n' >"$fixture_current/Caddyfile"
(
    cd "$fixture_current"
    sha256sum ./Caddyfile ./release-manifest.json >manifest.sha256
)
: >"$fixture_current/.complete"
find "$fixture_current" -type f -exec chmod 0440 {} +
find "$fixture_current" -type d -exec chmod 0550 {} +

# Exercise the production assertion function against the real reconciler's
# canonical same-parent rejection contract, including no reload and retention
# immediately before cleanup.
incoming_root=$fixture_root/incoming
releases_root=$fixture_releases
evidence_base=$fixture_root/node-evidence
role=node-b
node_token=node_b
scenario=same-parent-conflict
conflict_one=fixture-conflict-one
conflict_two=fixture-conflict-two
install -d -m 0700 "$incoming_root/node-a/$conflict_one" \
    "$incoming_root/node-a/$conflict_two" \
    "$evidence_base/$run_id/baseline/$role"
: >"$incoming_root/node-a/$conflict_one/.complete"
: >"$incoming_root/node-a/$conflict_two/.complete"
printf '%s\n' "$fixture_current" \
    >"$evidence_base/$run_id/baseline/$role/current-release"
current_release() { printf '%s\n' "$fixture_current"; }
systemctl() {
    case "$1:$2" in
        show:caddy.service)
            case "$*" in
                *'-p MainPID --value'*) printf '8080\n' ;;
                *'-p NRestarts --value'*) printf '0\n' ;;
                *) return 0 ;;
            esac
            ;;
        start:caddy-sync-reconcile.service) return 1 ;;
        *) return 0 ;;
    esac
}
journalctl() {
    case "$*" in
        *'-u caddy.service --show-cursor'*)
            printf '%s\n' '-- cursor: conflict-caddy-cursor'
            ;;
        *'-u caddy-sync-reconcile.service -n 50'*)
            printf '%s\n' \
                'Multiple finalized candidates claim the active parent.'
            ;;
        *'-u caddy.service --after-cursor conflict-caddy-cursor'*)
            :
            ;;
        *) return 1 ;;
    esac
}
assert_conflict "$conflict_one+$conflict_two" \
    >"$fixture_root/conflict-assert.stdout"
grep -Fq 'check_conflict_worker_failed=true' \
    "$fixture_root/conflict-assert.stdout"
grep -Fq 'check_conflict_message=true' \
    "$fixture_root/conflict-assert.stdout"
grep -Fq 'check_conflict_caddy_reload_absent=true' \
    "$fixture_root/conflict-assert.stdout"
grep -Fq 'check_conflict_first_retained=true' \
    "$fixture_root/conflict-assert.stdout"
grep -Fq 'check_conflict_second_retained=true' \
    "$fixture_root/conflict-assert.stdout"
assert_conflict_retained "$conflict_one+$conflict_two" \
    >"$fixture_root/conflict-precleanup.stdout"
grep -Fq 'check_conflict_selection_unchanged=true' \
    "$fixture_root/conflict-precleanup.stdout"
install -d -m 0550 "$releases_root/$conflict_one"
if assert_conflict_retained "$conflict_one+$conflict_two" \
    >"$fixture_root/conflict-destination.stdout" \
    2>"$fixture_root/conflict-destination.stderr"; then
    printf 'action33f regression accepted a conflict destination release\n' >&2
    exit 1
fi
grep -Fq 'check_conflict_first_destination_absent=false' \
    "$fixture_root/conflict-destination.stderr"
chmod -R u+w "$releases_root/$conflict_one"
rm -rf -- "$releases_root/${conflict_one:?}" \
    "$incoming_root/node-a/${conflict_one:?}" \
    "$incoming_root/node-a/${conflict_two:?}"

cp -a -- "$fixture_current" "$fixture_outbound/$fixture_revision"
chmod 0750 "$fixture_outbound/$fixture_revision"
rm -f -- "$fixture_outbound/$fixture_revision/.complete"
: >"$fixture_outbound/$fixture_revision/.finalize-request"
chmod 0440 "$fixture_outbound/$fixture_revision/.finalize-request"
chmod 0550 "$fixture_outbound/$fixture_revision"

role=node-a
node_token=node_a
assert_outbound_role_policy node-a "$fixture_empty_outbound" \
    "$fixture_releases" "$fixture_current" >"$fixture_root/node-a-empty.stdout"
grep -Fq 'outbound_entry_count=0' "$fixture_root/node-a-empty.stdout"
grep -Fq 'check_node_a_outbound_entries_admissible=true' \
    "$fixture_root/node-a-empty.stdout"
grep -Fq 'outbound_role_policy=accepted' "$fixture_root/node-a-empty.stdout"

assert_outbound_role_policy node-a "$fixture_outbound" "$fixture_releases" \
    "$fixture_current" >"$fixture_root/node-a-safe.stdout"
grep -Fq 'disposition=retain_exact_active_replay' \
    "$fixture_root/node-a-safe.stdout"
role=node-b
node_token=node_b
assert_outbound_role_policy node-b "$fixture_empty_outbound" \
    "$fixture_releases" "$fixture_current" >"$fixture_root/node-b-empty.stdout"
grep -Fq 'outbound_role_policy=accepted' "$fixture_root/node-b-empty.stdout"

replay_destination=$fixture_outbound/transaction-owned-replay
assert_replay_destination_absent "$replay_destination" \
    >"$fixture_root/replay-absent.stdout"
grep -Fq 'check_replay_outgoing_absent=true' \
    "$fixture_root/replay-absent.stdout"
install -d -m 0750 "$replay_destination"
printf 'current production collision sentinel\n' \
    >"$replay_destination/sentinel"
chmod 0440 "$replay_destination/sentinel"
chmod 0550 "$replay_destination"
replay_before=$(sha256sum "$replay_destination/sentinel" | awk '{ print $1 }')
if assert_replay_destination_absent "$replay_destination" \
    >"$fixture_root/replay-present.stdout" 2>"$fixture_root/replay-present.stderr"; then
    printf 'action33f regression accepted an existing replay destination\n' >&2
    exit 1
fi
grep -Fq 'check_replay_outgoing_absent=false' \
    "$fixture_root/replay-present.stderr"
replay_after=$(sha256sum "$replay_destination/sentinel" | awk '{ print $1 }')
[[ "$replay_before" = "$replay_after" ]]
chmod -R u+w "$replay_destination"
rm -rf -- "$replay_destination"

role=node-a
node_token=node_a
chmod 0640 "$fixture_outbound/$fixture_revision/Caddyfile"
printf 'unsafe drift\n' >>"$fixture_outbound/$fixture_revision/Caddyfile"
chmod 0440 "$fixture_outbound/$fixture_revision/Caddyfile"
if assert_outbound_role_policy node-a "$fixture_outbound" \
    "$fixture_releases" "$fixture_current" >/dev/null 2>&1; then
    printf 'action33f regression accepted payload drift\n' >&2
    exit 1
fi
chmod -R u+w "$fixture_outbound/${fixture_revision:?}"
rm -rf -- "$fixture_outbound/${fixture_revision:?}"
ln -s "$fixture_current" "$fixture_outbound/$fixture_revision"
if assert_outbound_role_policy node-a "$fixture_outbound" \
    "$fixture_releases" "$fixture_current" >/dev/null 2>&1; then
    printf 'action33f regression accepted an outbound symlink\n' >&2
    exit 1
fi

for required in invalid-a-to-b-payload-hash interrupted-a-to-b-finalize-request same-parent-conflict-retained node-a-controlled node-a-reboot node-b-controlled node-b-reboot; do
    require_literal "$required" "$manifest"
done
printf 'caddy_ha_reliability_action33f_regression_complete=true\n'
