#!/usr/bin/env bash
# shellcheck disable=SC1003,SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly transaction=$caddy_root/scripts/transact-caddy-ha-reliability-action33o.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-ha-reliability-action33o-outer.sh
readonly manifest=$caddy_root/manifests/caddy-ha-reliability-action33o.yaml
readonly action33k_producer=$caddy_root/scripts/transact-caddy-ha-reliability-action33k.sh
readonly consumed_evidence=$caddy_root/docs/evidence/action33g-rolling-maintenance.availability
fixture_root=

cleanup() {
    if [[ -n "$fixture_root" && -d "$fixture_root" ]]; then
        chmod -R u+w "$fixture_root"
        rm -rf -- "$fixture_root"
    fi
}
trap cleanup EXIT INT TERM
fixture_root=$(mktemp -d /tmp/action33o-regression.XXXXXX)
chmod 0700 "$fixture_root"

require_literal() { grep -Fq -- "$1" "$2"; }
reject_literal() { ! grep -Fq -- "$1" "$2"; }
for file in "$transaction" "$outer" "$manifest" "$action33k_producer" \
    "$consumed_evidence"; do
    [[ -f "$file" && ! -L "$file" ]]
done
/bin/bash -n "$transaction"
/bin/bash -n "$outer"
CADDY_ACTION33O_SSH_BIN=/bin/false /bin/bash "$outer" --self-test \
    >"$fixture_root/self-test.stdout"
grep -Fxq 'action_33o_outer_self_test_complete=true' \
    "$fixture_root/self-test.stdout"
grep -Fxq 'action_33o_outer_gate_baseline_bundle_self_test=true' \
    "$fixture_root/self-test.stdout"
/bin/bash "$transaction" --reject-capture-self-test \
    >"$fixture_root/reject-capture-self-test.stdout"
grep -Fxq \
    'action_33o_remote__check_reject_capture_stdout_regular=true' \
    "$fixture_root/reject-capture-self-test.stdout"
grep -Fxq \
    'action_33o_remote__check_reject_capture_stderr_regular=true' \
    "$fixture_root/reject-capture-self-test.stdout"
grep -Fxq \
    'action_33o_remote__check_reject_capture_status_regular=true' \
    "$fixture_root/reject-capture-self-test.stdout"
grep -Fxq 'action_33o_remote_reject_capture_self_test_complete=true' \
    "$fixture_root/reject-capture-self-test.stdout"

require_literal 'cd / && sudo -n /bin/bash' "$outer"
require_literal '-s -- $mode $role $run_id $scenario $argument' "$outer"
require_literal 'capture_files "$action33o_outer_stdout" "$action33o_outer_stderr" "$action33o_outer_status_file"' "$outer"
require_literal 'consume_action33g_rolling_evidence' "$outer"
require_literal '926e8f7b15132c0da503c3aca51ab77647afc08b712f0a5e2c9ff3df06f80912' "$outer"
require_literal 'action33g_same_parent_conflict_consumed' "$outer"
require_literal 'action33g_rolling_maintenance_consumed' "$outer"
require_literal 'action33h_execution_consumed' "$outer"
require_literal 'action33i_execution_consumed' "$outer"
require_literal 'action33i_online_emergency_replication_consumed' "$outer"
require_literal 'action33i_online_availability_all_passed' "$outer"
require_literal 'action33j_execution_consumed' "$outer"
require_literal 'action33j_node_a_controlled_outage_consumed' "$outer"
require_literal 'action33j_controlled_outage_availability_all_passed' "$outer"
require_literal 'action33k_node_a_reboot_consumed' "$outer"
require_literal 'action33k_node_a_reboot_availability_all_passed' "$outer"
require_literal 'for scenario in node-b-controlled node-b-reboot' \
    "$outer"
reject_literal 'for scenario in node-a-reboot' "$outer"
reject_literal '        node-a-reboot)' "$outer"
reject_literal '        node-a-controlled)' "$outer"
require_literal 'validate_availability_windows' "$outer"
require_literal 'validate_availability_recovery' "$outer"
require_literal 'wait_ssh_state b-down' "$outer"
require_literal 'wait_ssh_state b-up' "$outer"
require_literal 'exit 125' "$outer"
require_literal 'while [[ ! -e "$availability_stop_request" ]]' "$outer"
require_literal 'capture_files "$availability_stop_request"' "$outer"
require_literal 'wait "$availability_pid"' "$outer"
require_literal 'recover_failed_action33k' "$outer"
require_literal '--recover-action33k-preflight' "$outer"
require_literal '--recover-action33k-freeze' "$outer"
require_literal '--recover-action33k-apply' "$outer"
require_literal '--recover-action33k-restore' "$outer"
require_literal 'persist_baseline_on_workstation node-a' "$outer"
require_literal 'persist_baseline_on_workstation node-b' "$outer"
require_literal 'rehydrate_node_b_state' "$outer"
require_literal 'upload_registry reboot-registry-b' "$outer"
require_literal '--import-baseline baseline "$baseline_bundle_b_sha256"' "$outer"
require_literal '--import-baseline node-b-reboot' "$outer"
require_literal 'persist_baseline_on_workstation node-b "$node_b_target"' \
    "$outer"
require_literal 'node_b_state_rehydrated=false' "$outer"
require_literal 'create_baseline_archive' "$transaction"
require_literal 'import_baseline_archive' "$transaction"
require_literal '/run/caddy-action33o-baseline-$run_id-$scenario-$role' "$transaction"
require_literal '/tmp/caddy-action33o-baseline-$run_id-$scenario-$role.tar' "$transaction"
require_literal 'baseline_stage_owner_group_mode' "$transaction"
require_literal 'baseline_archive_owner_group_mode' "$transaction"
require_literal 'baseline_stage_exact_inventory' "$transaction"
require_literal 'baseline_import_upload_owner' "$transaction"
require_literal 'baseline_import_upload_mode' "$transaction"
require_literal 'accepted_release_revision=20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04' \
    "$transaction"
require_literal 'failed_action33k_run_id=20260813T000701Z-2499021' \
    "$transaction"
require_literal 'failed_action33k_emergency_revision=action33k-$failed_action33k_run_id-node-a-reboot' \
    "$transaction"
require_literal 'failed_action33k_normalized_revision=$failed_action33k_emergency_revision-normalized' \
    "$transaction"
reject_literal 'failed_action33k_emergency_manifest_sha256=' "$transaction"
reject_literal 'action33o_remote_emergency_hash' "$transaction"
require_literal 'failed_action33k_normalized_manifest_sha256=bf711fa44181d89654ea08530d5fd44a9dade7dc1a4cd5ea42858b1309d8f807' \
    "$transaction"
require_literal 'payload_manifest_matches_action33k_transform' "$transaction"
require_literal "printf '\\n# Action 33k reliability fixture %s\\n'" \
    "$action33k_producer"
require_literal 'unchanged_file_inventory_and_hashes_match_action32g: true' \
    "$manifest"
require_literal 'function: prepare_fixture_source' "$manifest"
require_literal 'test "$action33o_remote_source" = node-b' "$transaction"
require_literal 'test "$action33o_remote_source" = node-a' "$transaction"
require_literal '"$failed_action33k_emergency_revision" || return' "$transaction"
require_literal 'failed_action33k_emergency_family_count' "$transaction"
require_literal 'failed_action33k_normalized_family_count' "$transaction"
require_literal 'action33k_residue_absent_after_restore' "$transaction"
require_literal 'if [[ "$role" = node-b &&' "$transaction"
reject_literal 'scenario=same-parent-conflict' "$outer"
reject_literal 'current_scenario=rolling-maintenance' "$outer"
reject_literal 'conflict-one-a' "$outer"
reject_literal 'rolling-b' "$outer"
reject_literal 'rolling-a' "$outer"
reject_literal 'current_scenario=emergency-online' "$outer"
reject_literal 'begin_handoff emergency-online-a-to-b' "$outer"
reject_literal 'run_remote emergency-b' "$outer"
reject_literal 'normalize_emergency_ancestry' "$outer"
reject_literal 'Caddy/tests/run.sh' "$outer"
require_literal 'first_live_case: node-b-controlled-outage' "$manifest"
require_literal 'workstation_persistent_baseline: required' "$manifest"
require_literal 'node_tmp_is_reboot_persistent: false' "$manifest"
require_literal 'stop_request: cooperative' "$manifest"
require_literal 'torn_trailing_sample: prohibited' "$manifest"
require_literal 'maximum_duration_seconds: 60' "$manifest"
require_literal 'maximum_failed_samples_per_window: 1' "$manifest"
require_literal 'failed_samples: prohibited' "$manifest"
require_literal 'production_state_seeding_to_satisfy_assertions: prohibited' "$manifest"
require_literal 'action: 33o' "$manifest"
require_literal 'failed_predecessor: 33n' "$manifest"
require_literal 'predecessor_failed_before_mutation: true' "$manifest"
require_literal 'exact_revision_families_required: 2' "$manifest"
require_literal 'inferred_release_manifest_sha256_required: false' "$manifest"
require_literal 'validate_every_matching_path_before_cleanup: true' "$manifest"
require_literal 'consumed_action33n_evidence=/tmp/caddy-ssh-evidence/action33n/run.EVWPHw' "$outer"
require_literal 'consumed_action33n_evidence_sha256=54ea29edf6c317c3cbd20aeab677e04ff9d944f5e8477a29e21edd34bf5764b5' "$outer"
require_literal 'action33n_failed_before_mutation_status' "$outer"
require_literal 'action33n_no_recovery_mutation_evidence' "$outer"
reject_literal 'run-dual-node-caddy-ha-reliability-action33n-outer.sh' "$outer"

# Execute Action 33k's real producer function. Only its privileged /run stage
# root is redirected into this regression's private /tmp tree; the copy and
# exact suffix operations are the immutable production function body.
producer_function_raw=$fixture_root/action33k-prepare-fixture-source.raw.sh
producer_function=$fixture_root/action33k-prepare-fixture-source.sh
awk '
    /^prepare_fixture_source\(\) \{/ { capture = 1 }
    capture { print }
    capture && /^}$/ { exit }
' "$action33k_producer" >"$producer_function_raw"
grep -Fxq 'prepare_fixture_source() {' "$producer_function_raw"
sed -e "s#/run/caddy-action33k-stage-#$fixture_root/producer-stage-#" \
    -e 's/install -d -o root -g root -m 0700/install -d -m 0700/' \
    "$producer_function_raw" >"$producer_function"
# shellcheck disable=SC1090
source "$producer_function"
check() {
    local action33o_test_label=$1
    : "$action33o_test_label"
    shift
    "$@"
}
producer_current=$fixture_root/producer-accepted
current_release() { printf '%s\n' "$producer_current"; }
run_id=producer-contract
scenario=node-a-reboot
install -d -m 0700 "$producer_current/conf.d"
printf 'fixture payload\n' >"$producer_current/Caddyfile"
printf 'unchanged payload\n' >"$producer_current/conf.d/unchanged.caddy"
producer_emergency_revision=action33k-$run_id-$scenario
producer_normalized_revision=$producer_emergency_revision-normalized
producer_emergency=$(prepare_fixture_source "$producer_emergency_revision")
{
    cat "$producer_current/Caddyfile"
    printf '\n# Action 33k reliability fixture %s\n' \
        "$producer_emergency_revision"
} >"$fixture_root/producer-emergency.expected"
cmp -s "$fixture_root/producer-emergency.expected" \
    "$producer_emergency/Caddyfile"
cmp -s "$producer_current/conf.d/unchanged.caddy" \
    "$producer_emergency/conf.d/unchanged.caddy"
producer_current=$producer_emergency
producer_normalized=$(prepare_fixture_source "$producer_normalized_revision")
{
    cat "$producer_emergency/Caddyfile"
    printf '\n# Action 33k reliability fixture %s\n' \
        "$producer_normalized_revision"
} >"$fixture_root/producer-normalized.expected"
cmp -s "$fixture_root/producer-normalized.expected" \
    "$producer_normalized/Caddyfile"
cmp -s "$producer_emergency/conf.d/unchanged.caddy" \
    "$producer_normalized/conf.d/unchanged.caddy"

/bin/bash "$transaction" --action33k-family-self-test \
    >"$fixture_root/action33k-family-self-test.stdout"
for expected in \
    action_33o_remote__check_action33k_emergency_family_accepted=true \
    action_33o_remote__check_action33k_normalized_family_accepted=true \
    action_33o_remote_action33k_wrong_source_rejected=true \
    action_33o_remote_action33k_wrong_payload_rejected=true \
    action_33o_remote_action33k_wrong_unchanged_payload_rejected=true \
    action_33o_remote_action33k_wrong_normalized_transform_rejected=true \
    action_33o_remote_action33k_wrong_parent_rejected=true \
    action_33o_remote_action33k_wrong_normalized_hash_rejected=true \
    action_33o_remote_action33k_family_self_test_complete=true; do
    grep -Fxq "$expected" "$fixture_root/action33k-family-self-test.stdout"
done

observed_evidence_sha=$(sha256sum -- "$consumed_evidence" | awk '{ print $1 }')
[[ "$observed_evidence_sha" = 926e8f7b15132c0da503c3aca51ab77647afc08b712f0a5e2c9ff3df06f80912 ]]
/bin/bash "$outer" --consumed-evidence-self-test \
    >"$fixture_root/consumed-evidence.stdout"
grep -Fxq 'action_33o_outer_gate_consumed_rolling_failed_exact=true' \
    "$fixture_root/consumed-evidence.stdout"
grep -Fxq 'action_33o_outer_gate_consumed_rolling_recovery_window_bounded=true' \
    "$fixture_root/consumed-evidence.stdout"
grep -Fxq 'action_33o_outer_consumed_evidence_self_test_complete=true' \
    "$fixture_root/consumed-evidence.stdout"
/bin/bash "$outer" --availability-stop-self-test \
    >"$fixture_root/availability-stop.stdout"
grep -Fxq 'action_33o_outer_gate_stop-self-test_availability_grammar=true' \
    "$fixture_root/availability-stop.stdout"
grep -Fxq 'action_33o_outer_gate_stop_self_test_no_open_sample=true' \
    "$fixture_root/availability-stop.stdout"
grep -Fxq 'action_33o_outer_availability_stop_self_test_complete=true' \
    "$fixture_root/availability-stop.stdout"
write_sample() {
    local action33o_test_path=$1
    local action33o_test_timestamp=$2
    local action33o_test_state=$3
    printf '%s\t10.1.0.56\n%s\n' "$action33o_test_timestamp" \
        "$action33o_test_state" >>"$action33o_test_path"
}
run_acceptance() {
    local action33o_test_path=$1
    /bin/bash "$outer" --availability-self-test "$action33o_test_path" \
        >/dev/null
}

# One isolated failure inside one explicit narrow handoff is accepted.
accepted=$fixture_root/accepted.availability
: >"$accepted"
write_sample "$accepted" 1000000000 ok
write_sample "$accepted" 2000000000 failed
write_sample "$accepted" 4000000000 ok
printf 'a-to-b\t1500000000\t3000000000\n' >"$accepted.handoffs"
run_acceptance "$accepted"

# Steady state with no handoff and no failures remains accepted.
steady=$fixture_root/steady.availability
: >"$steady"
write_sample "$steady" 1000000000 ok
write_sample "$steady" 2000000000 ok
: >"$steady.handoffs"
run_acceptance "$steady"

# A failure outside every handoff window is rejected.
outside=$fixture_root/outside.availability
cp -- "$accepted" "$outside"
printf 'a-to-b\t2500000000\t3000000000\n' >"$outside.handoffs"
if run_acceptance "$outside"; then
    printf 'Action 33o accepted a failure outside the handoff window\n' >&2
    exit 1
fi

# More than one failure in one handoff window is rejected.
multiple=$fixture_root/multiple.availability
: >"$multiple"
write_sample "$multiple" 1000000000 ok
write_sample "$multiple" 2000000000 failed
write_sample "$multiple" 3000000000 ok
write_sample "$multiple" 4000000000 failed
write_sample "$multiple" 5000000000 ok
printf 'a-to-b\t1500000000\t4500000000\n' >"$multiple.handoffs"
if run_acceptance "$multiple"; then
    printf 'Action 33o accepted multiple failures in one handoff\n' >&2
    exit 1
fi

# Consecutive failures remain rejected even when separately windowed.
consecutive=$fixture_root/consecutive.availability
: >"$consecutive"
write_sample "$consecutive" 1000000000 ok
write_sample "$consecutive" 2000000000 failed
write_sample "$consecutive" 3000000000 failed
write_sample "$consecutive" 4000000000 ok
printf 'first\t1500000000\t2500000000\nsecond\t2500000001\t3500000000\n' \
    >"$consecutive.handoffs"
if run_acceptance "$consecutive"; then
    printf 'Action 33o accepted consecutive failed samples\n' >&2
    exit 1
fi

# Recovery taking longer than four seconds between adjacent passes is rejected.
slow=$fixture_root/slow.availability
: >"$slow"
write_sample "$slow" 1000000000 ok
write_sample "$slow" 2000000000 failed
write_sample "$slow" 6000000000 ok
printf 'a-to-b\t1500000000\t3000000000\n' >"$slow.handoffs"
if run_acceptance "$slow"; then
    printf 'Action 33o accepted an overlong failed-sample recovery\n' >&2
    exit 1
fi

# A handoff marker wider than sixty seconds cannot broaden acceptance.
wide=$fixture_root/wide.availability
cp -- "$accepted" "$wide"
printf 'a-to-b\t1\t60000000002\n' >"$wide.handoffs"
if run_acceptance "$wide"; then
    printf 'Action 33o accepted an overlong handoff window\n' >&2
    exit 1
fi

printf 'caddy_ha_reliability_action33o_regression_complete=true\n'
