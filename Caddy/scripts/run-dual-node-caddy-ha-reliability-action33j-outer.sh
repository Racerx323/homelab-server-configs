#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

# ssh-local-evidence-contract-v1
readonly prefix=action_33j_outer
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly node_a_alias=pihole0.local.theama.co
readonly node_b_alias=pihole00.local.theama.co
readonly evidence_root=/tmp/caddy-ssh-evidence/action33j
readonly node_evidence_root=/tmp/caddy-action33j
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=65536
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly transaction=$script_directory/transact-caddy-ha-reliability-action33j.sh
readonly manifest=$caddy_root/manifests/caddy-ha-reliability-action33j.yaml
readonly registry=$caddy_root/manifests/accepted-live-artifacts.tsv
readonly regression=$caddy_root/tests/caddy-ha-reliability-action33j-regression.sh
readonly consumed_rolling_evidence=$caddy_root/docs/evidence/action33g-rolling-maintenance.availability
readonly consumed_rolling_evidence_sha256=926e8f7b15132c0da503c3aca51ab77647afc08b712f0a5e2c9ff3df06f80912
readonly maximum_handoff_window_ns=60000000000
readonly maximum_failed_sample_recovery_ns=4000000000
ssh_binary=${CADDY_ACTION33J_SSH_BIN:-/usr/bin/ssh}
readonly ssh_binary
scp_binary=${CADDY_ACTION33J_SCP_BIN:-/usr/bin/scp}
readonly scp_binary
run_id=$(date -u +%Y%m%dT%H%M%SZ)-$$
work_root=
availability_pid=
availability_scenario=
availability_handoffs=
handoff_label=
handoff_start_ns=
current_scenario=baseline
mutated=false
registry_uploaded_a=false
registry_uploaded_b=false

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
safe_stream() {
    local action33j_outer_stream=$1
    [[ "$(wc -c <"$action33j_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action33j_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action33j_outer_stream" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action33j_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' "$action33j_outer_stream"
}
capture_files() {
    local action33j_outer_path
    for action33j_outer_path in "$@"; do
        install -m 0600 /dev/null "$action33j_outer_path"
        chmod 0600 "$action33j_outer_path"
    done
}
emit_stream() {
    local action33j_outer_label=$1
    local action33j_outer_path=$2
    printf '%s_%s_bytes=%s\n' "$prefix" "$action33j_outer_label" "$(wc -c <"$action33j_outer_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action33j_outer_label" "$(line_count "$action33j_outer_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action33j_outer_label" "$(file_hash "$action33j_outer_path")"
    safe_stream "$action33j_outer_path" || return 97
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action33j_outer_label"
    if [[ -s "$action33j_outer_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action33j_outer_label"
        sed "s/^/${prefix}_${action33j_outer_label}_content=/" \
            "$action33j_outer_path"
        printf '%s_%s_end\n' "$prefix" "$action33j_outer_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action33j_outer_label"
    fi
}
gate() {
    local action33j_outer_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action33j_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action33j_outer_label" >&2
    return 1
}
run_remote() {
    local action33j_outer_label=$1 target=$2 alias=$3 role=$4 mode=$5 scenario=$6 argument=${7:-}
    local action33j_outer_stdout=$work_root/$action33j_outer_label.stdout
    local action33j_outer_stderr=$work_root/$action33j_outer_label.stderr
    local action33j_outer_status_file=$work_root/$action33j_outer_label.status
    local action33j_outer_status=0
    capture_files "$action33j_outer_stdout" "$action33j_outer_stderr" "$action33j_outer_status_file"
    "$ssh_binary" -T -o BatchMode=yes -o StrictHostKeyChecking=yes -o "HostKeyAlias=$alias" -o ConnectTimeout=10 -o ConnectionAttempts=1 "$target" \
        "cd / && sudo -n /bin/bash -s -- $mode $role $run_id $scenario $argument" <"$transaction" >"$action33j_outer_stdout" 2>"$action33j_outer_stderr" || action33j_outer_status=$?
    printf '%s\n' "$action33j_outer_status" >"$action33j_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action33j_outer_label" "$action33j_outer_status"
    emit_stream "remote_stdout_$action33j_outer_label" "$action33j_outer_stdout"
    emit_stream "remote_stderr_$action33j_outer_label" "$action33j_outer_stderr"
    [[ "$action33j_outer_status" -eq 0 ]]
}
run_local() {
    local action33j_outer_label=$1
    local action33j_outer_stdout=$work_root/$action33j_outer_label.stdout
    local action33j_outer_stderr=$work_root/$action33j_outer_label.stderr
    local action33j_outer_status_file=$work_root/$action33j_outer_label.status
    local action33j_outer_status=0

    shift
    capture_files "$action33j_outer_stdout" "$action33j_outer_stderr" \
        "$action33j_outer_status_file"
    "$@" >"$action33j_outer_stdout" 2>"$action33j_outer_stderr" ||
        action33j_outer_status=$?
    printf '%s\n' "$action33j_outer_status" >"$action33j_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action33j_outer_label" \
        "$action33j_outer_status"
    emit_stream "local_stdout_$action33j_outer_label" "$action33j_outer_stdout"
    emit_stream "local_stderr_$action33j_outer_label" "$action33j_outer_stderr"
    [[ "$action33j_outer_status" -eq 0 ]]
}
upload_registry() {
    local action33j_outer_label=$1
    local action33j_outer_target=$2
    local action33j_outer_alias=$3
    local action33j_outer_stdout=$work_root/$action33j_outer_label.stdout
    local action33j_outer_stderr=$work_root/$action33j_outer_label.stderr
    local action33j_outer_status_file=$work_root/$action33j_outer_label.status
    local action33j_outer_status=0

    capture_files "$action33j_outer_stdout" "$action33j_outer_stderr" \
        "$action33j_outer_status_file"
    "$scp_binary" -q -p -o BatchMode=yes -o StrictHostKeyChecking=yes \
        -o "HostKeyAlias=$action33j_outer_alias" -o ConnectTimeout=10 \
        -o ConnectionAttempts=1 "$registry" \
        "$action33j_outer_target:/tmp/caddy-action33j-registry-$run_id.tsv" \
        >"$action33j_outer_stdout" 2>"$action33j_outer_stderr" ||
        action33j_outer_status=$?
    printf '%s\n' "$action33j_outer_status" >"$action33j_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action33j_outer_label" \
        "$action33j_outer_status"
    emit_stream "remote_stdout_$action33j_outer_label" "$action33j_outer_stdout"
    emit_stream "remote_stderr_$action33j_outer_label" "$action33j_outer_stderr"
    [[ "$action33j_outer_status" -eq 0 ]]
}
wait_ssh_state() {
    local action33j_outer_label=$1 target=$2 alias=$3 expected=$4 limit=$5 elapsed=0 status
    while ((elapsed < limit)); do
        status=0
        "$ssh_binary" -T -o BatchMode=yes -o StrictHostKeyChecking=yes -o "HostKeyAlias=$alias" -o ConnectTimeout=2 -o ConnectionAttempts=1 "$target" 'cd / && true' >/dev/null 2>&1 || status=$?
        if { [[ "$expected" = up && "$status" -eq 0 ]]; } || { [[ "$expected" = down && "$status" -ne 0 ]]; }; then
            printf '%s_%s_elapsed_seconds=%s\n' "$prefix" "$action33j_outer_label" "$elapsed"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}
start_availability() {
    local action33j_outer_scenario=$1
    local action33j_outer_output=$work_root/$action33j_outer_scenario.availability
    availability_handoffs=$work_root/$action33j_outer_scenario.handoffs
    capture_files "$action33j_outer_output" "$availability_handoffs"
    (
        while :; do
            printf '%s\t' "$(date +%s%N)" >>"$action33j_outer_output"
            dig +time=1 +tries=1 @10.1.0.55 proxy.local.theama.co A +short >>"$action33j_outer_output" 2>&1 &&
                curl --fail --silent --show-error --max-time 2 https://proxy.local.theama.co/ -o /dev/null >>"$action33j_outer_output" 2>&1 &&
                curl --fail --silent --show-error --max-time 2 https://pihole-admin.local.theama.co/admin/login.php -o /dev/null >>"$action33j_outer_output" 2>&1 && printf 'ok\n' >>"$action33j_outer_output" || printf 'failed\n' >>"$action33j_outer_output"
            sleep 1
        done
    ) &
    availability_pid=$!
    availability_scenario=$action33j_outer_scenario
}
begin_handoff() {
    local action33j_outer_label=$1
    [[ -z "$handoff_label" ]] || return 1
    handoff_label=$action33j_outer_label
    handoff_start_ns=$(date +%s%N)
    printf '%s_handoff_%s_begin_ns=%s\n' "$prefix" "$handoff_label" \
        "$handoff_start_ns"
}
end_handoff() {
    local action33j_outer_label=$1
    local action33j_outer_end_ns
    [[ "$handoff_label" = "$action33j_outer_label" ]] || return 1
    action33j_outer_end_ns=$(date +%s%N)
    printf '%s\t%s\t%s\n' "$handoff_label" "$handoff_start_ns" \
        "$action33j_outer_end_ns" >>"$availability_handoffs"
    printf '%s_handoff_%s_end_ns=%s\n' "$prefix" "$handoff_label" \
        "$action33j_outer_end_ns"
    handoff_label=
    handoff_start_ns=
}
build_availability_summary() {
    local action33j_outer_availability=$1
    local action33j_outer_summary=$2

    awk -F '\t' '
        /^[0-9][0-9]*\t/ {
            if (open_sample) exit 2
            if ($1 <= previous_timestamp) exit 3
            timestamp = $1
            previous_timestamp = $1
            open_sample = 1
            next
        }
        $0 == "ok" || $0 == "failed" {
            if (!open_sample) exit 4
            print timestamp "\t" $0
            open_sample = 0
            next
        }
        END {
            if (open_sample) exit 5
        }
    ' "$action33j_outer_availability" >"$action33j_outer_summary"
}
validate_availability_windows() {
    local action33j_outer_windows=$1
    local action33j_outer_summary=$2

    awk -F '\t' -v maximum_window="$maximum_handoff_window_ns" \
        -v windows_file="$action33j_outer_windows" '
        FILENAME == windows_file {
            if (NF != 3 || $1 !~ /^[A-Za-z0-9._-]+$/ ||
                $2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]+$/ ||
                $2 >= $3 || $3 - $2 > maximum_window ||
                (window_count > 0 && $2 < window_end[window_count])) exit 2
            window_count++
            window_start[window_count] = $2
            window_end[window_count] = $3
            next
        }
        $2 == "failed" {
            matched = 0
            for (window_index = 1; window_index <= window_count; window_index++) {
                if ($1 >= window_start[window_index] && $1 <= window_end[window_index]) {
                    matched++
                    failure_count[window_index]++
                }
            }
            if (matched != 1) exit 3
        }
        END {
            for (window_index = 1; window_index <= window_count; window_index++) {
                if (failure_count[window_index] > 1) exit 4
            }
        }
    ' "$action33j_outer_windows" "$action33j_outer_summary"
}
validate_availability_recovery() {
    local action33j_outer_summary=$1

    awk -F '\t' -v maximum_recovery="$maximum_failed_sample_recovery_ns" '
        {
            timestamp[NR] = $1
            state[NR] = $2
        }
        END {
            for (sample_index = 1; sample_index <= NR; sample_index++) {
                if (state[sample_index] != "failed") continue
                if (sample_index == 1 || sample_index == NR) exit 2
                if (state[sample_index - 1] != "ok" || state[sample_index + 1] != "ok") exit 3
                if (timestamp[sample_index + 1] - timestamp[sample_index - 1] > maximum_recovery) exit 4
            }
        }
    ' "$action33j_outer_summary"
}
validate_availability_file() {
    local action33j_outer_label=$1
    local action33j_outer_availability=$2
    local action33j_outer_windows=$3
    local action33j_outer_summary=$action33j_outer_availability.summary
    local action33j_outer_sample_count
    local action33j_outer_failure_count

    # conditional-validator-explicit-failures-begin
    gate "${action33j_outer_label}_availability_regular" test -f \
        "$action33j_outer_availability" || return
    gate "${action33j_outer_label}_availability_not_symlink" test ! -L \
        "$action33j_outer_availability" || return
    gate "${action33j_outer_label}_handoffs_regular" test -f \
        "$action33j_outer_windows" || return
    gate "${action33j_outer_label}_handoffs_not_symlink" test ! -L \
        "$action33j_outer_windows" || return
    capture_files "$action33j_outer_summary"
    gate "${action33j_outer_label}_availability_grammar" \
        build_availability_summary "$action33j_outer_availability" \
        "$action33j_outer_summary" || return
    action33j_outer_sample_count=$(awk 'END { print NR }' \
        "$action33j_outer_summary")
    action33j_outer_failure_count=$(awk -F '\t' '$2 == "failed" { count++ } END { print count + 0 }' \
        "$action33j_outer_summary")
    printf '%s_%s_observed_sample_count=%s\n' "$prefix" \
        "$action33j_outer_label" "$action33j_outer_sample_count"
    printf '%s_%s_observed_failure_count=%s\n' "$prefix" \
        "$action33j_outer_label" "$action33j_outer_failure_count"
    gate "${action33j_outer_label}_availability_nonempty" test \
        "$action33j_outer_sample_count" -gt 0 || return
    gate "${action33j_outer_label}_failures_inside_handoffs" \
        validate_availability_windows "$action33j_outer_windows" \
        "$action33j_outer_summary" || return
    gate "${action33j_outer_label}_failures_isolated_and_bounded" \
        validate_availability_recovery "$action33j_outer_summary" || return
    # conditional-validator-explicit-failures-end
}
consume_action33g_rolling_evidence() {
    local action33j_outer_observed_hash
    local action33j_outer_observed_samples
    local action33j_outer_observed_ok
    local action33j_outer_observed_failed
    local action33j_outer_observed_failure_index
    local action33j_outer_observed_pre_ns
    local action33j_outer_observed_failure_ns
    local action33j_outer_observed_post_ns
    local action33j_outer_observed_window_ns

    # conditional-validator-explicit-failures-begin
    gate consumed_rolling_evidence_regular test -f \
        "$consumed_rolling_evidence" || return
    gate consumed_rolling_evidence_not_symlink test ! -L \
        "$consumed_rolling_evidence" || return
    # conditional-validator-explicit-failures-end
    action33j_outer_observed_hash=$(file_hash "$consumed_rolling_evidence")
    read -r action33j_outer_observed_samples action33j_outer_observed_ok \
        action33j_outer_observed_failed action33j_outer_observed_failure_index \
        action33j_outer_observed_pre_ns action33j_outer_observed_failure_ns \
        action33j_outer_observed_post_ns < <(
            awk -F '\t' '
            /^[0-9][0-9]*\t/ {
                sample++
                timestamp[sample] = $1
                next
            }
            $0 == "ok" { ok++ }
            $0 == "failed" { failed++; failure_index = sample }
            END {
                print sample, ok, failed, failure_index,
                    timestamp[failure_index - 1], timestamp[failure_index],
                    timestamp[failure_index + 1]
            }
        ' "$consumed_rolling_evidence"
        )
    action33j_outer_observed_window_ns=$((action33j_outer_observed_post_ns - action33j_outer_observed_pre_ns))
    printf '%s_consumed_rolling_expected_sha256=%s\n' "$prefix" \
        "$consumed_rolling_evidence_sha256"
    printf '%s_consumed_rolling_observed_sha256=%s\n' "$prefix" \
        "$action33j_outer_observed_hash"
    printf '%s_consumed_rolling_observed_samples=%s\n' "$prefix" \
        "$action33j_outer_observed_samples"
    printf '%s_consumed_rolling_observed_ok=%s\n' "$prefix" \
        "$action33j_outer_observed_ok"
    printf '%s_consumed_rolling_observed_failed=%s\n' "$prefix" \
        "$action33j_outer_observed_failed"
    printf '%s_consumed_rolling_observed_failure_index=%s\n' "$prefix" \
        "$action33j_outer_observed_failure_index"
    printf '%s_consumed_rolling_observed_pre_ns=%s\n' "$prefix" \
        "$action33j_outer_observed_pre_ns"
    printf '%s_consumed_rolling_observed_failure_ns=%s\n' "$prefix" \
        "$action33j_outer_observed_failure_ns"
    printf '%s_consumed_rolling_observed_post_ns=%s\n' "$prefix" \
        "$action33j_outer_observed_post_ns"
    printf '%s_consumed_rolling_observed_window_ns=%s\n' "$prefix" \
        "$action33j_outer_observed_window_ns"
    # conditional-validator-explicit-failures-begin
    gate consumed_rolling_evidence_hash test \
        "$action33j_outer_observed_hash" = \
        "$consumed_rolling_evidence_sha256" || return
    gate consumed_rolling_samples_exact test \
        "$action33j_outer_observed_samples" -eq 51 || return
    gate consumed_rolling_ok_exact test \
        "$action33j_outer_observed_ok" -eq 50 || return
    gate consumed_rolling_failed_exact test \
        "$action33j_outer_observed_failed" -eq 1 || return
    gate consumed_rolling_failure_index_exact test \
        "$action33j_outer_observed_failure_index" -eq 16 || return
    gate consumed_rolling_pre_sample_exact test \
        "$action33j_outer_observed_pre_ns" = 1786575427373856041 || return
    gate consumed_rolling_failed_sample_exact test \
        "$action33j_outer_observed_failure_ns" = 1786575428456195162 || return
    gate consumed_rolling_post_sample_exact test \
        "$action33j_outer_observed_post_ns" = 1786575430480634425 || return
    gate consumed_rolling_recovery_window_bounded test \
        "$action33j_outer_observed_window_ns" -le \
        "$maximum_failed_sample_recovery_ns" || return
    # conditional-validator-explicit-failures-end
    emit_stream consumed_rolling_availability "$consumed_rolling_evidence"
}
stop_availability() {
    local action33j_outer_scenario=$1
    kill "$availability_pid" >/dev/null 2>&1 || true
    wait "$availability_pid" 2>/dev/null || true
    availability_pid=
    availability_scenario=
    emit_stream "${action33j_outer_scenario}_availability" "$work_root/$action33j_outer_scenario.availability"
    emit_stream "${action33j_outer_scenario}_handoffs" \
        "$work_root/$action33j_outer_scenario.handoffs"
    [[ -z "$handoff_label" ]] || return 1
    validate_availability_file "$action33j_outer_scenario" \
        "$work_root/$action33j_outer_scenario.availability" \
        "$work_root/$action33j_outer_scenario.handoffs"
    availability_handoffs=
}
baseline() {
    local action33j_outer_scenario=$1

    run_remote "$action33j_outer_scenario-baseline-a" "$node_a_target" \
        "$node_a_alias" node-a --baseline "$action33j_outer_scenario"
    run_remote "$action33j_outer_scenario-baseline-b" "$node_b_target" \
        "$node_b_alias" node-b --baseline "$action33j_outer_scenario"
    run_remote "$action33j_outer_scenario-master" "$node_a_target" \
        "$node_a_alias" node-a --assert-master "$action33j_outer_scenario"
    run_remote "$action33j_outer_scenario-backup" "$node_b_target" \
        "$node_b_alias" node-b --assert-backup "$action33j_outer_scenario"
    gate "$action33j_outer_scenario-release_identity_equal" test \
        "$(grep -Eo 'observed_current_revision=[A-Za-z0-9._-]+' \
            "$work_root/$action33j_outer_scenario-baseline-a.stdout" | tail -n 1)" = \
        "$(grep -Eo 'observed_current_revision=[A-Za-z0-9._-]+' \
            "$work_root/$action33j_outer_scenario-baseline-b.stdout" | tail -n 1)"
    gate "$action33j_outer_scenario-release_manifest_equal" test \
        "$(grep -Eo 'observed_release_manifest_sha256=[0-9a-f]{64}' \
            "$work_root/$action33j_outer_scenario-baseline-a.stdout" | tail -n 1)" = \
        "$(grep -Eo 'observed_release_manifest_sha256=[0-9a-f]{64}' \
            "$work_root/$action33j_outer_scenario-baseline-b.stdout" | tail -n 1)"
}
restore_baseline() {
    local action33j_outer_scenario=$1
    run_remote "$action33j_outer_scenario-prepare-b" "$node_b_target" \
        "$node_b_alias" node-b --prepare-cleanup "$action33j_outer_scenario"
    run_remote "$action33j_outer_scenario-prepare-a" "$node_a_target" \
        "$node_a_alias" node-a --prepare-cleanup "$action33j_outer_scenario"
    run_remote "$action33j_outer_scenario-freeze-b" "$node_b_target" \
        "$node_b_alias" node-b --freeze "$action33j_outer_scenario"
    run_remote "$action33j_outer_scenario-freeze-a" "$node_a_target" \
        "$node_a_alias" node-a --freeze "$action33j_outer_scenario"
    run_remote "$action33j_outer_scenario-cleanup-b" "$node_b_target" \
        "$node_b_alias" node-b --cleanup "$action33j_outer_scenario"
    run_remote "$action33j_outer_scenario-cleanup-a" "$node_a_target" \
        "$node_a_alias" node-a --cleanup "$action33j_outer_scenario"
    run_remote "$action33j_outer_scenario-restore-b" "$node_b_target" \
        "$node_b_alias" node-b --restore-services "$action33j_outer_scenario"
    run_remote "$action33j_outer_scenario-restore-a" "$node_a_target" \
        "$node_a_alias" node-a --restore-services "$action33j_outer_scenario"
    run_remote "$action33j_outer_scenario-final-a" "$node_a_target" \
        "$node_a_alias" node-a --final "$action33j_outer_scenario"
    run_remote "$action33j_outer_scenario-final-b" "$node_b_target" \
        "$node_b_alias" node-b --final "$action33j_outer_scenario"
    gate "$action33j_outer_scenario-final_release_identity_equal" test \
        "$(grep -Eo 'observed_current_revision=[A-Za-z0-9._-]+' \
            "$work_root/$action33j_outer_scenario-final-a.stdout" | tail -n 1)" = \
        "$(grep -Eo 'observed_current_revision=[A-Za-z0-9._-]+' \
            "$work_root/$action33j_outer_scenario-final-b.stdout" | tail -n 1)"
    gate "$action33j_outer_scenario-final_release_manifest_equal" test \
        "$(grep -Eo 'observed_release_manifest_sha256=[0-9a-f]{64}' \
            "$work_root/$action33j_outer_scenario-final-a.stdout" | tail -n 1)" = \
        "$(grep -Eo 'observed_release_manifest_sha256=[0-9a-f]{64}' \
            "$work_root/$action33j_outer_scenario-final-b.stdout" | tail -n 1)"
}
normalize_emergency_ancestry() {
    local action33j_outer_scenario=$1
    local action33j_outer_revision=action33j-$run_id-$action33j_outer_scenario-normalized

    begin_handoff "$action33j_outer_scenario-b-to-a"
    run_remote "$action33j_outer_scenario-owner-a" "$node_a_target" \
        "$node_a_alias" node-a --restore-services "$action33j_outer_scenario"
    run_remote "$action33j_outer_scenario-master-a" "$node_a_target" \
        "$node_a_alias" node-a --assert-master "$action33j_outer_scenario"
    run_remote "$action33j_outer_scenario-backup-b" "$node_b_target" \
        "$node_b_alias" node-b --assert-backup "$action33j_outer_scenario"
    end_handoff "$action33j_outer_scenario-b-to-a"
    run_remote "$action33j_outer_scenario-normal-publish-a" "$node_a_target" \
        "$node_a_alias" node-a --publish-normal "$action33j_outer_scenario" \
        "$action33j_outer_revision"
    run_remote "$action33j_outer_scenario-normal-promote-a" "$node_a_target" \
        "$node_a_alias" node-a --promote-outgoing "$action33j_outer_scenario" \
        "$action33j_outer_revision"
    run_remote "$action33j_outer_scenario-normal-wait-b" "$node_b_target" \
        "$node_b_alias" node-b --wait-current "$action33j_outer_scenario" \
        "$action33j_outer_revision"
}
recover() {
    local action33j_outer_failed=false
    if [[ -n "$availability_pid" ]]; then
        stop_availability "$availability_scenario" || true
    fi
    if [[ "$mutated" = true ]]; then
        restore_baseline "$current_scenario" || action33j_outer_failed=true
    fi
    if [[ "$registry_uploaded_b" = true ]]; then
        run_remote recovery-remove-registry-b "$node_b_target" \
            "$node_b_alias" node-b --remove-registry recovery ||
            action33j_outer_failed=true
    fi
    if [[ "$registry_uploaded_a" = true ]]; then
        run_remote recovery-remove-registry-a "$node_a_target" \
            "$node_a_alias" node-a --remove-registry recovery ||
            action33j_outer_failed=true
    fi
    [[ "$action33j_outer_failed" = false ]] || exit 125
}
trap recover ERR INT TERM

if [[ "${1:-}" = --self-test ]]; then
    gate transaction_self_test /bin/bash "$transaction" --self-test node-a self-test self-test
    printf '%s_self_test_complete=true\n' "$prefix"
    exit 0
fi
if [[ "${1:-}" = --availability-self-test ]]; then
    [[ $# -eq 2 ]] || exit 64
    validate_availability_file self-test "$2" "$2.handoffs"
    printf '%s_availability_self_test_complete=true\n' "$prefix"
    exit 0
fi
if [[ "${1:-}" = --consumed-evidence-self-test ]]; then
    [[ $# -eq 1 ]] || exit 64
    consume_action33g_rolling_evidence
    printf '%s_consumed_evidence_self_test_complete=true\n' "$prefix"
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
consume_action33g_rolling_evidence
upload_registry registry-a "$node_a_target" "$node_a_alias"
registry_uploaded_a=true
upload_registry registry-b "$node_b_target" "$node_b_alias"
registry_uploaded_b=true
baseline baseline
mutated=true

# Actions 33g and 33h are consumed. Action 33i completed online guarded B-to-A
# emergency replication and normal A-to-B ancestry normalization with every
# availability sample passing, then recovered the exact Action 32g baseline
# after its 15-second orchestration-window assertion rejected a 22.45-second
# handoff. Action 33j begins at the first unexecuted controlled-outage case.
gate action33g_execution_consumed test -f \
    "$caddy_root/manifests/caddy-ha-reliability-action33g.yaml"
gate action33g_same_parent_conflict_consumed true
gate action33g_rolling_maintenance_consumed true
gate action33h_execution_consumed test -f \
    "$caddy_root/manifests/caddy-ha-reliability-action33h.yaml"
gate action33i_execution_consumed test -f \
    "$caddy_root/manifests/caddy-ha-reliability-action33i.yaml"
gate action33i_online_emergency_replication_consumed true
gate action33i_online_availability_all_passed true

for scenario in node-a-controlled node-a-reboot node-b-controlled node-b-reboot; do
    current_scenario=$scenario
    baseline "$scenario"
    start_availability "$scenario"
    case "$scenario" in
        node-a-controlled)
            begin_handoff "$scenario-a-to-b"
            run_remote outage-a "$node_a_target" "$node_a_alias" node-a --controlled-outage "$scenario" || true
            wait_ssh_state a-down "$node_a_target" "$node_a_alias" down 20
            run_remote master-b "$node_b_target" "$node_b_alias" node-b --assert-master "$scenario"
            end_handoff "$scenario-a-to-b"
            run_remote reject-b "$node_b_target" "$node_b_alias" node-b --reject-normal "$scenario"
            run_remote publish-b "$node_b_target" "$node_b_alias" node-b --publish-emergency "$scenario" "action33j-$run_id-$scenario"
            run_remote promote-b "$node_b_target" "$node_b_alias" node-b \
                --promote-outgoing "$scenario" "action33j-$run_id-$scenario"
            run_remote queued-b "$node_b_target" "$node_b_alias" node-b \
                --assert-queued "$scenario" "action33j-$run_id-$scenario"
            sleep 12
            wait_ssh_state a-up "$node_a_target" "$node_a_alias" up 60
            run_remote offline-proof-a "$node_a_target" "$node_a_alias" \
                node-a --assert-controlled-offline "$scenario"
            run_remote health-restore-a "$node_a_target" "$node_a_alias" \
                node-a --restore-health "$scenario"
            run_remote recovered-a "$node_a_target" "$node_a_alias" node-a \
                --assert-recovered "$scenario"
            run_remote wait-a "$node_a_target" "$node_a_alias" node-a \
                --wait-current "$scenario" "action33j-$run_id-$scenario"
            ;;
        node-a-reboot)
            run_remote preboot-a "$node_a_target" "$node_a_alias" node-a \
                --boot-id "$scenario"
            begin_handoff "$scenario-a-to-b"
            run_remote reboot-a "$node_a_target" "$node_a_alias" node-a --prepare-reboot "$scenario"
            wait_ssh_state a-down "$node_a_target" "$node_a_alias" down 30
            run_remote master-b "$node_b_target" "$node_b_alias" node-b --assert-master "$scenario"
            end_handoff "$scenario-a-to-b"
            run_remote reject-b "$node_b_target" "$node_b_alias" node-b --reject-normal "$scenario"
            run_remote publish-b "$node_b_target" "$node_b_alias" node-b --publish-emergency "$scenario" "action33j-$run_id-$scenario"
            run_remote promote-b "$node_b_target" "$node_b_alias" node-b \
                --promote-outgoing "$scenario" "action33j-$run_id-$scenario"
            run_remote queued-b "$node_b_target" "$node_b_alias" node-b \
                --assert-queued "$scenario" "action33j-$run_id-$scenario"
            wait_ssh_state a-up "$node_a_target" "$node_a_alias" up 300
            run_remote postboot-a "$node_a_target" "$node_a_alias" node-a \
                --boot-id "$scenario"
            gate a_boot_id_changed test \
                "$(grep -Eo 'observed_boot_id=[0-9a-f-]+' "$work_root/preboot-a.stdout" | tail -n 1)" != \
                "$(grep -Eo 'observed_boot_id=[0-9a-f-]+' "$work_root/postboot-a.stdout" | tail -n 1)"
            run_remote health-restore-a "$node_a_target" "$node_a_alias" \
                node-a --restore-health "$scenario"
            run_remote recovered-a "$node_a_target" "$node_a_alias" node-a \
                --assert-recovered "$scenario"
            run_remote wait-a "$node_a_target" "$node_a_alias" node-a \
                --wait-current "$scenario" "action33j-$run_id-$scenario"
            ;;
        node-b-controlled)
            run_remote outage-b "$node_b_target" "$node_b_alias" node-b --controlled-outage "$scenario" || true
            wait_ssh_state b-down "$node_b_target" "$node_b_alias" down 20
            run_remote master-a "$node_a_target" "$node_a_alias" node-a --assert-master "$scenario"
            run_remote publish-a "$node_a_target" "$node_a_alias" node-a --publish-normal "$scenario" "action33j-$run_id-$scenario"
            run_remote promote-a "$node_a_target" "$node_a_alias" node-a \
                --promote-outgoing "$scenario" "action33j-$run_id-$scenario"
            run_remote queued-a "$node_a_target" "$node_a_alias" node-a \
                --assert-queued "$scenario" "action33j-$run_id-$scenario"
            sleep 12
            wait_ssh_state b-up "$node_b_target" "$node_b_alias" up 60
            run_remote offline-proof-b "$node_b_target" "$node_b_alias" \
                node-b --assert-controlled-offline "$scenario"
            run_remote health-restore-b "$node_b_target" "$node_b_alias" \
                node-b --restore-health "$scenario"
            run_remote recovered-b "$node_b_target" "$node_b_alias" node-b \
                --assert-recovered "$scenario"
            run_remote wait-b "$node_b_target" "$node_b_alias" node-b \
                --wait-current "$scenario" "action33j-$run_id-$scenario"
            ;;
        node-b-reboot)
            run_remote preboot-b "$node_b_target" "$node_b_alias" node-b \
                --boot-id "$scenario"
            run_remote reboot-b "$node_b_target" "$node_b_alias" node-b --prepare-reboot "$scenario"
            wait_ssh_state b-down "$node_b_target" "$node_b_alias" down 30
            run_remote master-a "$node_a_target" "$node_a_alias" node-a --assert-master "$scenario"
            run_remote publish-a "$node_a_target" "$node_a_alias" node-a --publish-normal "$scenario" "action33j-$run_id-$scenario"
            run_remote promote-a "$node_a_target" "$node_a_alias" node-a \
                --promote-outgoing "$scenario" "action33j-$run_id-$scenario"
            run_remote queued-a "$node_a_target" "$node_a_alias" node-a \
                --assert-queued "$scenario" "action33j-$run_id-$scenario"
            wait_ssh_state b-up "$node_b_target" "$node_b_alias" up 300
            run_remote postboot-b "$node_b_target" "$node_b_alias" node-b \
                --boot-id "$scenario"
            gate b_boot_id_changed test \
                "$(grep -Eo 'observed_boot_id=[0-9a-f-]+' "$work_root/preboot-b.stdout" | tail -n 1)" != \
                "$(grep -Eo 'observed_boot_id=[0-9a-f-]+' "$work_root/postboot-b.stdout" | tail -n 1)"
            run_remote health-restore-b "$node_b_target" "$node_b_alias" \
                node-b --restore-health "$scenario"
            run_remote recovered-b "$node_b_target" "$node_b_alias" node-b \
                --assert-recovered "$scenario"
            run_remote wait-b "$node_b_target" "$node_b_alias" node-b \
                --wait-current "$scenario" "action33j-$run_id-$scenario"
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
