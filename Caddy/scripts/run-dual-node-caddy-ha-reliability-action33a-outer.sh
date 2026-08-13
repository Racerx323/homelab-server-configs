#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

# ssh-local-evidence-contract-v1
readonly prefix=action_33a_outer
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly node_a_alias=pihole0.local.theama.co
readonly node_b_alias=pihole00.local.theama.co
readonly evidence_root=/tmp/caddy-ssh-evidence/action33a
readonly node_evidence_root=/tmp/caddy-action33a
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=65536
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly transaction=$script_directory/transact-caddy-ha-reliability-action33a.sh
readonly manifest=$caddy_root/manifests/caddy-ha-reliability-action33a.yaml
readonly registry=$caddy_root/manifests/accepted-live-artifacts.tsv
readonly regression=$caddy_root/tests/caddy-ha-reliability-action33a-regression.sh
ssh_binary=${CADDY_ACTION33A_SSH_BIN:-/usr/bin/ssh}
readonly ssh_binary
scp_binary=${CADDY_ACTION33A_SCP_BIN:-/usr/bin/scp}
readonly scp_binary
run_id=$(date -u +%Y%m%dT%H%M%SZ)-$$
work_root=
availability_pid=
availability_scenario=
current_scenario=baseline
mutated=false
registry_uploaded_a=false
registry_uploaded_b=false

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
safe_stream() {
    local action33a_outer_stream=$1
    [[ "$(wc -c <"$action33a_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action33a_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action33a_outer_stream" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action33a_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' "$action33a_outer_stream"
}
capture_files() {
    local action33a_outer_path
    for action33a_outer_path in "$@"; do
        install -m 0600 /dev/null "$action33a_outer_path"
        chmod 0600 "$action33a_outer_path"
    done
}
emit_stream() {
    local action33a_outer_label=$1
    local action33a_outer_path=$2
    printf '%s_%s_bytes=%s\n' "$prefix" "$action33a_outer_label" "$(wc -c <"$action33a_outer_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action33a_outer_label" "$(line_count "$action33a_outer_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action33a_outer_label" "$(file_hash "$action33a_outer_path")"
    safe_stream "$action33a_outer_path" || return 97
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action33a_outer_label"
    if [[ -s "$action33a_outer_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action33a_outer_label"
        sed "s/^/${prefix}_${action33a_outer_label}_content=/" \
            "$action33a_outer_path"
        printf '%s_%s_end\n' "$prefix" "$action33a_outer_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action33a_outer_label"
    fi
}
gate() {
    local action33a_outer_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action33a_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action33a_outer_label" >&2
    return 1
}
run_remote() {
    local action33a_outer_label=$1 target=$2 alias=$3 role=$4 mode=$5 scenario=$6 argument=${7:-}
    local action33a_outer_stdout=$work_root/$action33a_outer_label.stdout
    local action33a_outer_stderr=$work_root/$action33a_outer_label.stderr
    local action33a_outer_status_file=$work_root/$action33a_outer_label.status
    local action33a_outer_status=0
    capture_files "$action33a_outer_stdout" "$action33a_outer_stderr" "$action33a_outer_status_file"
    "$ssh_binary" -T -o BatchMode=yes -o StrictHostKeyChecking=yes -o "HostKeyAlias=$alias" -o ConnectTimeout=10 -o ConnectionAttempts=1 "$target" \
        "cd / && sudo -n /bin/bash -s -- $mode $role $run_id $scenario $argument" <"$transaction" >"$action33a_outer_stdout" 2>"$action33a_outer_stderr" || action33a_outer_status=$?
    printf '%s\n' "$action33a_outer_status" >"$action33a_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action33a_outer_label" "$action33a_outer_status"
    emit_stream "remote_stdout_$action33a_outer_label" "$action33a_outer_stdout"
    emit_stream "remote_stderr_$action33a_outer_label" "$action33a_outer_stderr"
    [[ "$action33a_outer_status" -eq 0 ]]
}
run_local() {
    local action33a_outer_label=$1
    local action33a_outer_stdout=$work_root/$action33a_outer_label.stdout
    local action33a_outer_stderr=$work_root/$action33a_outer_label.stderr
    local action33a_outer_status_file=$work_root/$action33a_outer_label.status
    local action33a_outer_status=0

    shift
    capture_files "$action33a_outer_stdout" "$action33a_outer_stderr" \
        "$action33a_outer_status_file"
    "$@" >"$action33a_outer_stdout" 2>"$action33a_outer_stderr" ||
        action33a_outer_status=$?
    printf '%s\n' "$action33a_outer_status" >"$action33a_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action33a_outer_label" \
        "$action33a_outer_status"
    emit_stream "local_stdout_$action33a_outer_label" "$action33a_outer_stdout"
    emit_stream "local_stderr_$action33a_outer_label" "$action33a_outer_stderr"
    [[ "$action33a_outer_status" -eq 0 ]]
}
upload_registry() {
    local action33a_outer_label=$1
    local action33a_outer_target=$2
    local action33a_outer_alias=$3
    local action33a_outer_stdout=$work_root/$action33a_outer_label.stdout
    local action33a_outer_stderr=$work_root/$action33a_outer_label.stderr
    local action33a_outer_status_file=$work_root/$action33a_outer_label.status
    local action33a_outer_status=0

    capture_files "$action33a_outer_stdout" "$action33a_outer_stderr" \
        "$action33a_outer_status_file"
    "$scp_binary" -q -p -o BatchMode=yes -o StrictHostKeyChecking=yes \
        -o "HostKeyAlias=$action33a_outer_alias" -o ConnectTimeout=10 \
        -o ConnectionAttempts=1 "$registry" \
        "$action33a_outer_target:/tmp/caddy-action33a-registry-$run_id.tsv" \
        >"$action33a_outer_stdout" 2>"$action33a_outer_stderr" ||
        action33a_outer_status=$?
    printf '%s\n' "$action33a_outer_status" >"$action33a_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action33a_outer_label" \
        "$action33a_outer_status"
    emit_stream "remote_stdout_$action33a_outer_label" "$action33a_outer_stdout"
    emit_stream "remote_stderr_$action33a_outer_label" "$action33a_outer_stderr"
    [[ "$action33a_outer_status" -eq 0 ]]
}
wait_ssh_state() {
    local action33a_outer_label=$1 target=$2 alias=$3 expected=$4 limit=$5 elapsed=0 status
    while ((elapsed < limit)); do
        status=0
        "$ssh_binary" -T -o BatchMode=yes -o StrictHostKeyChecking=yes -o "HostKeyAlias=$alias" -o ConnectTimeout=2 -o ConnectionAttempts=1 "$target" 'cd / && true' >/dev/null 2>&1 || status=$?
        if { [[ "$expected" = up && "$status" -eq 0 ]]; } || { [[ "$expected" = down && "$status" -ne 0 ]]; }; then
            printf '%s_%s_elapsed_seconds=%s\n' "$prefix" "$action33a_outer_label" "$elapsed"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}
start_availability() {
    local action33a_outer_scenario=$1
    local action33a_outer_output=$work_root/$action33a_outer_scenario.availability
    capture_files "$action33a_outer_output"
    (
        while :; do
            printf '%s\t' "$(date +%s%N)" >>"$action33a_outer_output"
            dig +time=1 +tries=1 @10.1.0.55 proxy.local.theama.co A +short >>"$action33a_outer_output" 2>&1 &&
                curl --fail --silent --show-error --max-time 2 https://proxy.local.theama.co/ -o /dev/null >>"$action33a_outer_output" 2>&1 &&
                curl --fail --silent --show-error --max-time 2 https://pihole-admin.local.theama.co/admin/login.php -o /dev/null >>"$action33a_outer_output" 2>&1 && printf 'ok\n' >>"$action33a_outer_output" || printf 'failed\n' >>"$action33a_outer_output"
            sleep 1
        done
    ) &
    availability_pid=$!
    availability_scenario=$action33a_outer_scenario
}
stop_availability() {
    local action33a_outer_scenario=$1
    kill "$availability_pid" >/dev/null 2>&1 || true
    wait "$availability_pid" 2>/dev/null || true
    availability_pid=
    availability_scenario=
    gate "${action33a_outer_scenario}_availability_no_failure" test -z "$(grep -F 'failed' "$work_root/$action33a_outer_scenario.availability" || true)"
    emit_stream "${action33a_outer_scenario}_availability" "$work_root/$action33a_outer_scenario.availability"
}
baseline() {
    local action33a_outer_scenario=$1

    run_remote "$action33a_outer_scenario-baseline-a" "$node_a_target" \
        "$node_a_alias" node-a --baseline "$action33a_outer_scenario"
    run_remote "$action33a_outer_scenario-baseline-b" "$node_b_target" \
        "$node_b_alias" node-b --baseline "$action33a_outer_scenario"
    run_remote "$action33a_outer_scenario-master" "$node_a_target" \
        "$node_a_alias" node-a --assert-master "$action33a_outer_scenario"
    run_remote "$action33a_outer_scenario-backup" "$node_b_target" \
        "$node_b_alias" node-b --assert-backup "$action33a_outer_scenario"
    gate "$action33a_outer_scenario-release_identity_equal" test \
        "$(grep -Eo 'observed_current_revision=[A-Za-z0-9._-]+' \
            "$work_root/$action33a_outer_scenario-baseline-a.stdout" | tail -n 1)" = \
        "$(grep -Eo 'observed_current_revision=[A-Za-z0-9._-]+' \
            "$work_root/$action33a_outer_scenario-baseline-b.stdout" | tail -n 1)"
    gate "$action33a_outer_scenario-release_manifest_equal" test \
        "$(grep -Eo 'observed_release_manifest_sha256=[0-9a-f]{64}' \
            "$work_root/$action33a_outer_scenario-baseline-a.stdout" | tail -n 1)" = \
        "$(grep -Eo 'observed_release_manifest_sha256=[0-9a-f]{64}' \
            "$work_root/$action33a_outer_scenario-baseline-b.stdout" | tail -n 1)"
}
restore_baseline() {
    local action33a_outer_scenario=$1
    run_remote "$action33a_outer_scenario-prepare-b" "$node_b_target" \
        "$node_b_alias" node-b --prepare-cleanup "$action33a_outer_scenario"
    run_remote "$action33a_outer_scenario-prepare-a" "$node_a_target" \
        "$node_a_alias" node-a --prepare-cleanup "$action33a_outer_scenario"
    run_remote "$action33a_outer_scenario-freeze-b" "$node_b_target" \
        "$node_b_alias" node-b --freeze "$action33a_outer_scenario"
    run_remote "$action33a_outer_scenario-freeze-a" "$node_a_target" \
        "$node_a_alias" node-a --freeze "$action33a_outer_scenario"
    run_remote "$action33a_outer_scenario-cleanup-b" "$node_b_target" \
        "$node_b_alias" node-b --cleanup "$action33a_outer_scenario"
    run_remote "$action33a_outer_scenario-cleanup-a" "$node_a_target" \
        "$node_a_alias" node-a --cleanup "$action33a_outer_scenario"
    run_remote "$action33a_outer_scenario-restore-b" "$node_b_target" \
        "$node_b_alias" node-b --restore-services "$action33a_outer_scenario"
    run_remote "$action33a_outer_scenario-restore-a" "$node_a_target" \
        "$node_a_alias" node-a --restore-services "$action33a_outer_scenario"
    run_remote "$action33a_outer_scenario-final-a" "$node_a_target" \
        "$node_a_alias" node-a --final "$action33a_outer_scenario"
    run_remote "$action33a_outer_scenario-final-b" "$node_b_target" \
        "$node_b_alias" node-b --final "$action33a_outer_scenario"
    gate "$action33a_outer_scenario-final_release_identity_equal" test \
        "$(grep -Eo 'observed_current_revision=[A-Za-z0-9._-]+' \
            "$work_root/$action33a_outer_scenario-final-a.stdout" | tail -n 1)" = \
        "$(grep -Eo 'observed_current_revision=[A-Za-z0-9._-]+' \
            "$work_root/$action33a_outer_scenario-final-b.stdout" | tail -n 1)"
    gate "$action33a_outer_scenario-final_release_manifest_equal" test \
        "$(grep -Eo 'observed_release_manifest_sha256=[0-9a-f]{64}' \
            "$work_root/$action33a_outer_scenario-final-a.stdout" | tail -n 1)" = \
        "$(grep -Eo 'observed_release_manifest_sha256=[0-9a-f]{64}' \
            "$work_root/$action33a_outer_scenario-final-b.stdout" | tail -n 1)"
}
normalize_emergency_ancestry() {
    local action33a_outer_scenario=$1
    local action33a_outer_revision=action33a-$run_id-$action33a_outer_scenario-normalized

    run_remote "$action33a_outer_scenario-owner-a" "$node_a_target" \
        "$node_a_alias" node-a --restore-services "$action33a_outer_scenario"
    run_remote "$action33a_outer_scenario-master-a" "$node_a_target" \
        "$node_a_alias" node-a --assert-master "$action33a_outer_scenario"
    run_remote "$action33a_outer_scenario-backup-b" "$node_b_target" \
        "$node_b_alias" node-b --assert-backup "$action33a_outer_scenario"
    run_remote "$action33a_outer_scenario-normal-publish-a" "$node_a_target" \
        "$node_a_alias" node-a --publish-normal "$action33a_outer_scenario" \
        "$action33a_outer_revision"
    run_remote "$action33a_outer_scenario-normal-promote-a" "$node_a_target" \
        "$node_a_alias" node-a --promote-outgoing "$action33a_outer_scenario" \
        "$action33a_outer_revision"
    run_remote "$action33a_outer_scenario-normal-wait-b" "$node_b_target" \
        "$node_b_alias" node-b --wait-current "$action33a_outer_scenario" \
        "$action33a_outer_revision"
}
recover() {
    local action33a_outer_failed=false
    if [[ -n "$availability_pid" ]]; then
        stop_availability "$availability_scenario" || true
    fi
    if [[ "$mutated" = true ]]; then
        restore_baseline "$current_scenario" || action33a_outer_failed=true
    fi
    if [[ "$registry_uploaded_b" = true ]]; then
        run_remote recovery-remove-registry-b "$node_b_target" \
            "$node_b_alias" node-b --remove-registry recovery ||
            action33a_outer_failed=true
    fi
    if [[ "$registry_uploaded_a" = true ]]; then
        run_remote recovery-remove-registry-a "$node_a_target" \
            "$node_a_alias" node-a --remove-registry recovery ||
            action33a_outer_failed=true
    fi
    [[ "$action33a_outer_failed" = false ]] || exit 125
}
trap recover ERR INT TERM

if [[ "${1:-}" = --self-test ]]; then
    gate transaction_self_test /bin/bash "$transaction" --self-test node-a self-test self-test
    printf '%s_self_test_complete=true\n' "$prefix"
    exit 0
fi
[[ $# -eq 0 ]] || exit 64
[[ "$PWD" = /home/aaron/code/homelab-server-configs || "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || exit 1
install -d -m 0700 "$evidence_root"
work_root=$(mktemp -d "$evidence_root/run.XXXXXX")
chmod 0700 "$work_root"
gate accepted_live_policy /bin/bash "$caddy_root/tests/accepted-live-hash-policy.sh" --check
gate regression /bin/bash "$regression"
gate manifest_regular test -f "$manifest"
gate registry_regular test -f "$registry"
upload_registry registry-a "$node_a_target" "$node_a_alias"
registry_uploaded_a=true
upload_registry registry-b "$node_b_target" "$node_b_alias"
registry_uploaded_b=true
baseline baseline
mutated=true

# Invalid payload: the real publisher produces the candidate, then the
# transaction invalidates one payload byte after manifest creation.
scenario=invalid-release
current_scenario=$scenario
baseline "$scenario"
run_remote invalid-stage-a "$node_a_target" "$node_a_alias" node-a \
    --stage-invalid "$scenario" "action33a-$run_id-$scenario"
sleep 8
run_remote invalid-accept-b "$node_b_target" "$node_b_alias" node-b \
    --assert-invalid "$scenario" "action33a-$run_id-$scenario"
restore_baseline "$scenario"

# Interrupted transfer: expose an exact active replay without the request,
# prove it is inert, then add the request atomically and consume it once.
scenario=interrupted-transfer
current_scenario=$scenario
baseline "$scenario"
run_remote replay-stage-a "$node_a_target" "$node_a_alias" node-a \
    --stage-active-replay "$scenario"
replay_revision=$(grep -Eo 'active_replay_revision=[A-Za-z0-9._-]+' \
    "$work_root/replay-stage-a.stdout" | tail -n 1 | cut -d= -f2)
[[ -n "$replay_revision" ]]
sleep 8
run_remote replay-inert-b "$node_b_target" "$node_b_alias" node-b \
    --assert-replay-incomplete "$scenario" "$replay_revision"
run_remote replay-request-a "$node_a_target" "$node_a_alias" node-a \
    --request-active-replay "$scenario" "$replay_revision"
run_remote replay-consumed-b "$node_b_target" "$node_b_alias" node-b \
    --wait-replay-consumed "$scenario" "$replay_revision"
restore_baseline "$scenario"

# Same-parent conflict: finalize both while the path is stopped, then invoke
# the real reconciler and require its current fail-closed retention behavior.
scenario=same-parent-conflict
current_scenario=$scenario
conflict_one=action33a-$run_id-conflict-one
conflict_two=action33a-$run_id-conflict-two
baseline "$scenario"
run_remote conflict-stop-b "$node_b_target" "$node_b_alias" node-b \
    --stop-reconcile "$scenario"
run_remote conflict-one-a "$node_a_target" "$node_a_alias" node-a \
    --stage-conflict "$scenario" "$conflict_one"
run_remote conflict-two-a "$node_a_target" "$node_a_alias" node-a \
    --stage-conflict "$scenario" "$conflict_two"
run_remote conflict-transport-a "$node_a_target" "$node_a_alias" node-a \
    --start-transport "$scenario"
run_remote conflict-accept-b "$node_b_target" "$node_b_alias" node-b \
    --assert-conflict "$scenario" "$conflict_one+$conflict_two"
restore_baseline "$scenario"

# Standby-first rolling maintenance with the current installed binaries.
current_scenario=rolling-maintenance
baseline rolling-maintenance
start_availability rolling-maintenance
run_remote rolling-b "$node_b_target" "$node_b_alias" node-b \
    --rolling-maintenance rolling-maintenance
run_remote rolling-backup-b "$node_b_target" "$node_b_alias" node-b \
    --assert-backup rolling-maintenance
run_remote rolling-relinquish-a "$node_a_target" "$node_a_alias" node-a \
    --relinquish rolling-maintenance
run_remote rolling-master-b "$node_b_target" "$node_b_alias" node-b \
    --assert-master rolling-maintenance
run_remote rolling-a "$node_a_target" "$node_a_alias" node-a \
    --rolling-maintenance rolling-maintenance
run_remote rolling-restore-a "$node_a_target" "$node_a_alias" node-a \
    --restore-services rolling-maintenance
run_remote rolling-master-a "$node_a_target" "$node_a_alias" node-a \
    --assert-master rolling-maintenance
run_remote rolling-backup-b-final "$node_b_target" "$node_b_alias" node-b \
    --assert-backup rolling-maintenance
stop_availability rolling-maintenance
restore_baseline rolling-maintenance

# Online emergency B to A baseline.
current_scenario=emergency-online
baseline emergency-online
start_availability emergency-online
run_remote relinquish-a "$node_a_target" "$node_a_alias" node-a --relinquish emergency-online
run_remote master-b "$node_b_target" "$node_b_alias" node-b --assert-master emergency-online
run_remote zero-a "$node_a_target" "$node_a_alias" node-a --assert-zero emergency-online
run_remote reject-b "$node_b_target" "$node_b_alias" node-b --reject-normal emergency-online
run_remote emergency-b "$node_b_target" "$node_b_alias" node-b --publish-emergency emergency-online "action33a-$run_id-emergency-online"
run_remote emergency-promote-b "$node_b_target" "$node_b_alias" node-b \
    --promote-outgoing emergency-online "action33a-$run_id-emergency-online"
run_remote reconcile-a "$node_a_target" "$node_a_alias" node-a --reconcile emergency-online
run_remote emergency-wait-a "$node_a_target" "$node_a_alias" node-a \
    --wait-current emergency-online "action33a-$run_id-emergency-online"
normalize_emergency_ancestry emergency-online
stop_availability emergency-online
restore_baseline emergency-online

for scenario in node-a-controlled node-a-reboot node-b-controlled node-b-reboot; do
    current_scenario=$scenario
    baseline "$scenario"
    start_availability "$scenario"
    case "$scenario" in
        node-a-controlled)
            run_remote outage-a "$node_a_target" "$node_a_alias" node-a --controlled-outage "$scenario" || true
            wait_ssh_state a-down "$node_a_target" "$node_a_alias" down 20
            run_remote master-b "$node_b_target" "$node_b_alias" node-b --assert-master "$scenario"
            run_remote reject-b "$node_b_target" "$node_b_alias" node-b --reject-normal "$scenario"
            run_remote publish-b "$node_b_target" "$node_b_alias" node-b --publish-emergency "$scenario" "action33a-$run_id-$scenario"
            run_remote promote-b "$node_b_target" "$node_b_alias" node-b \
                --promote-outgoing "$scenario" "action33a-$run_id-$scenario"
            run_remote queued-b "$node_b_target" "$node_b_alias" node-b \
                --assert-queued "$scenario" "action33a-$run_id-$scenario"
            sleep 12
            wait_ssh_state a-up "$node_a_target" "$node_a_alias" up 60
            run_remote offline-proof-a "$node_a_target" "$node_a_alias" \
                node-a --assert-controlled-offline "$scenario"
            run_remote recovered-a "$node_a_target" "$node_a_alias" node-a \
                --assert-recovered "$scenario"
            run_remote wait-a "$node_a_target" "$node_a_alias" node-a \
                --wait-current "$scenario" "action33a-$run_id-$scenario"
            ;;
        node-a-reboot)
            run_remote preboot-a "$node_a_target" "$node_a_alias" node-a \
                --boot-id "$scenario"
            run_remote reboot-a "$node_a_target" "$node_a_alias" node-a --prepare-reboot "$scenario"
            wait_ssh_state a-down "$node_a_target" "$node_a_alias" down 30
            run_remote master-b "$node_b_target" "$node_b_alias" node-b --assert-master "$scenario"
            run_remote reject-b "$node_b_target" "$node_b_alias" node-b --reject-normal "$scenario"
            run_remote publish-b "$node_b_target" "$node_b_alias" node-b --publish-emergency "$scenario" "action33a-$run_id-$scenario"
            run_remote promote-b "$node_b_target" "$node_b_alias" node-b \
                --promote-outgoing "$scenario" "action33a-$run_id-$scenario"
            run_remote queued-b "$node_b_target" "$node_b_alias" node-b \
                --assert-queued "$scenario" "action33a-$run_id-$scenario"
            wait_ssh_state a-up "$node_a_target" "$node_a_alias" up 300
            run_remote postboot-a "$node_a_target" "$node_a_alias" node-a \
                --boot-id "$scenario"
            gate a_boot_id_changed test \
                "$(grep -Eo 'observed_boot_id=[0-9a-f-]+' "$work_root/preboot-a.stdout" | tail -n 1)" != \
                "$(grep -Eo 'observed_boot_id=[0-9a-f-]+' "$work_root/postboot-a.stdout" | tail -n 1)"
            run_remote recovered-a "$node_a_target" "$node_a_alias" node-a \
                --assert-recovered "$scenario"
            run_remote wait-a "$node_a_target" "$node_a_alias" node-a \
                --wait-current "$scenario" "action33a-$run_id-$scenario"
            ;;
        node-b-controlled)
            run_remote outage-b "$node_b_target" "$node_b_alias" node-b --controlled-outage "$scenario" || true
            wait_ssh_state b-down "$node_b_target" "$node_b_alias" down 20
            run_remote master-a "$node_a_target" "$node_a_alias" node-a --assert-master "$scenario"
            run_remote publish-a "$node_a_target" "$node_a_alias" node-a --publish-normal "$scenario" "action33a-$run_id-$scenario"
            run_remote promote-a "$node_a_target" "$node_a_alias" node-a \
                --promote-outgoing "$scenario" "action33a-$run_id-$scenario"
            run_remote queued-a "$node_a_target" "$node_a_alias" node-a \
                --assert-queued "$scenario" "action33a-$run_id-$scenario"
            sleep 12
            wait_ssh_state b-up "$node_b_target" "$node_b_alias" up 60
            run_remote offline-proof-b "$node_b_target" "$node_b_alias" \
                node-b --assert-controlled-offline "$scenario"
            run_remote recovered-b "$node_b_target" "$node_b_alias" node-b \
                --assert-recovered "$scenario"
            run_remote wait-b "$node_b_target" "$node_b_alias" node-b \
                --wait-current "$scenario" "action33a-$run_id-$scenario"
            ;;
        node-b-reboot)
            run_remote preboot-b "$node_b_target" "$node_b_alias" node-b \
                --boot-id "$scenario"
            run_remote reboot-b "$node_b_target" "$node_b_alias" node-b --prepare-reboot "$scenario"
            wait_ssh_state b-down "$node_b_target" "$node_b_alias" down 30
            run_remote master-a "$node_a_target" "$node_a_alias" node-a --assert-master "$scenario"
            run_remote publish-a "$node_a_target" "$node_a_alias" node-a --publish-normal "$scenario" "action33a-$run_id-$scenario"
            run_remote promote-a "$node_a_target" "$node_a_alias" node-a \
                --promote-outgoing "$scenario" "action33a-$run_id-$scenario"
            run_remote queued-a "$node_a_target" "$node_a_alias" node-a \
                --assert-queued "$scenario" "action33a-$run_id-$scenario"
            wait_ssh_state b-up "$node_b_target" "$node_b_alias" up 300
            run_remote postboot-b "$node_b_target" "$node_b_alias" node-b \
                --boot-id "$scenario"
            gate b_boot_id_changed test \
                "$(grep -Eo 'observed_boot_id=[0-9a-f-]+' "$work_root/preboot-b.stdout" | tail -n 1)" != \
                "$(grep -Eo 'observed_boot_id=[0-9a-f-]+' "$work_root/postboot-b.stdout" | tail -n 1)"
            run_remote recovered-b "$node_b_target" "$node_b_alias" node-b \
                --assert-recovered "$scenario"
            run_remote wait-b "$node_b_target" "$node_b_alias" node-b \
                --wait-current "$scenario" "action33a-$run_id-$scenario"
            ;;
    esac
    case "$scenario" in
        node-a-controlled | node-a-reboot)
            normalize_emergency_ancestry "$scenario"
            ;;
    esac
    stop_availability "$scenario"
    restore_baseline "$scenario"
done

start_availability final-acceptance
sleep 5
stop_availability final-acceptance
run_local final-node-a-dns dig +time=2 +tries=1 @10.1.0.53 \
    proxy.local.theama.co A +short
run_local final-node-b-dns dig +time=2 +tries=1 @10.1.0.54 \
    proxy.local.theama.co AAAA +short
run_local final-node-a-ui curl --fail --silent --show-error --max-time 5 \
    https://pihole0.local.theama.co/admin/login.php -o /dev/null
run_local final-node-b-ui curl --fail --silent --show-error --max-time 5 \
    https://pihole00.local.theama.co/admin/login.php -o /dev/null
mutated=false
run_remote final-remove-registry-b "$node_b_target" "$node_b_alias" node-b \
    --remove-registry final-acceptance
registry_uploaded_b=false
run_remote final-remove-registry-a "$node_a_target" "$node_a_alias" node-a \
    --remove-registry final-acceptance
registry_uploaded_a=false

trap - ERR INT TERM
printf '%s_node_evidence_root=%s/%s\n' "$prefix" "$node_evidence_root" "$run_id"
printf '%s_workstation_evidence_root=%s\n' "$prefix" "$work_root"
printf '%s_evidence_directory=%s\n' "$prefix" "$work_root"
printf '%s_complete=true\n' "$prefix"
