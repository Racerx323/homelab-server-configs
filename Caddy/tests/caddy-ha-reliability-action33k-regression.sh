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
readonly transaction=$caddy_root/scripts/transact-caddy-ha-reliability-action33k.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-ha-reliability-action33k-outer.sh
readonly manifest=$caddy_root/manifests/caddy-ha-reliability-action33k.yaml
readonly consumed_evidence=$caddy_root/docs/evidence/action33g-rolling-maintenance.availability
fixture_root=

cleanup() {
    if [[ -n "$fixture_root" && -d "$fixture_root" ]]; then
        chmod -R u+w "$fixture_root"
        rm -rf -- "$fixture_root"
    fi
}
trap cleanup EXIT INT TERM
fixture_root=$(mktemp -d /tmp/action33k-regression.XXXXXX)
chmod 0700 "$fixture_root"

require_literal() { grep -Fq -- "$1" "$2"; }
reject_literal() { ! grep -Fq -- "$1" "$2"; }
for file in "$transaction" "$outer" "$manifest" "$consumed_evidence"; do
    [[ -f "$file" && ! -L "$file" ]]
done
/bin/bash -n "$transaction"
/bin/bash -n "$outer"
CADDY_ACTION33K_SSH_BIN=/bin/false /bin/bash "$outer" --self-test \
    >"$fixture_root/self-test.stdout"
grep -Fxq 'action_33k_outer_self_test_complete=true' \
    "$fixture_root/self-test.stdout"
/bin/bash "$transaction" --reject-capture-self-test \
    >"$fixture_root/reject-capture-self-test.stdout"
grep -Fxq \
    'action_33k_remote__check_reject_capture_stdout_regular=true' \
    "$fixture_root/reject-capture-self-test.stdout"
grep -Fxq \
    'action_33k_remote__check_reject_capture_stderr_regular=true' \
    "$fixture_root/reject-capture-self-test.stdout"
grep -Fxq \
    'action_33k_remote__check_reject_capture_status_regular=true' \
    "$fixture_root/reject-capture-self-test.stdout"
grep -Fxq 'action_33k_remote_reject_capture_self_test_complete=true' \
    "$fixture_root/reject-capture-self-test.stdout"

require_literal 'cd / && sudo -n /bin/bash' "$outer"
require_literal '-s -- $mode $role $run_id $scenario $argument' "$outer"
require_literal 'capture_files "$action33k_outer_stdout" "$action33k_outer_stderr" "$action33k_outer_status_file"' "$outer"
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
require_literal 'for scenario in node-a-reboot node-b-controlled node-b-reboot' \
    "$outer"
reject_literal 'for scenario in node-a-controlled' "$outer"
require_literal 'begin_handoff "$action33k_outer_scenario-b-to-a"' "$outer"
require_literal 'begin_handoff "$scenario-a-to-b"' "$outer"
require_literal 'validate_availability_windows' "$outer"
require_literal 'validate_availability_recovery' "$outer"
require_literal '--publish-emergency' "$outer"
require_literal '--reject-normal' "$outer"
require_literal 'prepare_reject_capture_files' "$transaction"
require_literal 'install -m 0600 /dev/null "$evidence_directory/reject.stdout"' \
    "$transaction"
require_literal 'install -m 0600 /dev/null "$evidence_directory/reject.stderr"' \
    "$transaction"
require_literal 'install -m 0600 /dev/null "$evidence_directory/reject.status"' \
    "$transaction"
require_literal 'emit_stream reject_stdout' "$transaction"
require_literal 'emit_stream reject_stderr' "$transaction"
require_literal 'ordinary_node_b_publication_status_nonzero' "$transaction"
reject_literal \
    'install -m 0600 /dev/null "$evidence_directory/reject.stdout" \\' \
    "$transaction"
require_literal 'wait_ssh_state a-down' "$outer"
require_literal 'wait_ssh_state b-down' "$outer"
require_literal 'wait_ssh_state a-up' "$outer"
require_literal 'wait_ssh_state b-up' "$outer"
require_literal 'exit 125' "$outer"
require_literal 'while [[ ! -e "$availability_stop_request" ]]' "$outer"
require_literal 'capture_files "$availability_stop_request"' "$outer"
require_literal 'wait "$availability_pid"' "$outer"
reject_literal 'scenario=same-parent-conflict' "$outer"
reject_literal 'current_scenario=rolling-maintenance' "$outer"
reject_literal 'conflict-one-a' "$outer"
reject_literal 'rolling-b' "$outer"
reject_literal 'rolling-a' "$outer"
reject_literal 'current_scenario=emergency-online' "$outer"
reject_literal 'begin_handoff emergency-online-a-to-b' "$outer"
reject_literal 'run_remote emergency-b' "$outer"
reject_literal 'Caddy/tests/run.sh' "$outer"
require_literal 'first_live_case: node-a-automated-reboot' "$manifest"
require_literal 'stop_request: cooperative' "$manifest"
require_literal 'torn_trailing_sample: prohibited' "$manifest"
require_literal 'maximum_duration_seconds: 60' "$manifest"
require_literal 'maximum_failed_samples_per_window: 1' "$manifest"
require_literal 'failed_samples: prohibited' "$manifest"
require_literal 'production_state_seeding_to_satisfy_assertions: prohibited' "$manifest"

observed_evidence_sha=$(sha256sum -- "$consumed_evidence" | awk '{ print $1 }')
[[ "$observed_evidence_sha" = 926e8f7b15132c0da503c3aca51ab77647afc08b712f0a5e2c9ff3df06f80912 ]]
/bin/bash "$outer" --consumed-evidence-self-test \
    >"$fixture_root/consumed-evidence.stdout"
grep -Fxq 'action_33k_outer_gate_consumed_rolling_failed_exact=true' \
    "$fixture_root/consumed-evidence.stdout"
grep -Fxq 'action_33k_outer_gate_consumed_rolling_recovery_window_bounded=true' \
    "$fixture_root/consumed-evidence.stdout"
grep -Fxq 'action_33k_outer_consumed_evidence_self_test_complete=true' \
    "$fixture_root/consumed-evidence.stdout"
/bin/bash "$outer" --availability-stop-self-test \
    >"$fixture_root/availability-stop.stdout"
grep -Fxq 'action_33k_outer_gate_stop-self-test_availability_grammar=true' \
    "$fixture_root/availability-stop.stdout"
grep -Fxq 'action_33k_outer_gate_stop_self_test_no_open_sample=true' \
    "$fixture_root/availability-stop.stdout"
grep -Fxq 'action_33k_outer_availability_stop_self_test_complete=true' \
    "$fixture_root/availability-stop.stdout"
write_sample() {
    local action33k_test_path=$1
    local action33k_test_timestamp=$2
    local action33k_test_state=$3
    printf '%s\t10.1.0.56\n%s\n' "$action33k_test_timestamp" \
        "$action33k_test_state" >>"$action33k_test_path"
}
run_acceptance() {
    local action33k_test_path=$1
    /bin/bash "$outer" --availability-self-test "$action33k_test_path" \
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
    printf 'Action 33k accepted a failure outside the handoff window\n' >&2
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
    printf 'Action 33k accepted multiple failures in one handoff\n' >&2
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
    printf 'Action 33k accepted consecutive failed samples\n' >&2
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
    printf 'Action 33k accepted an overlong failed-sample recovery\n' >&2
    exit 1
fi

# A handoff marker wider than sixty seconds cannot broaden acceptance.
wide=$fixture_root/wide.availability
cp -- "$accepted" "$wide"
printf 'a-to-b\t1\t60000000002\n' >"$wide.handoffs"
if run_acceptance "$wide"; then
    printf 'Action 33k accepted an overlong handoff window\n' >&2
    exit 1
fi

printf 'caddy_ha_reliability_action33k_regression_complete=true\n'
