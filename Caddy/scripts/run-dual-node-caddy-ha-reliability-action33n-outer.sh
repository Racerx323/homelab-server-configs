#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

# ssh-local-evidence-contract-v1
readonly prefix=action_33n_outer
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly node_a_alias=pihole0.local.theama.co
readonly node_b_alias=pihole00.local.theama.co
readonly evidence_root=/tmp/caddy-ssh-evidence/action33n
readonly node_evidence_root=/tmp/caddy-action33n
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=65536
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly transaction=$script_directory/transact-caddy-ha-reliability-action33n.sh
readonly manifest=$caddy_root/manifests/caddy-ha-reliability-action33n.yaml
readonly registry=$caddy_root/manifests/accepted-live-artifacts.tsv
readonly regression=$caddy_root/tests/caddy-ha-reliability-action33n-regression.sh
readonly consumed_rolling_evidence=$caddy_root/docs/evidence/action33g-rolling-maintenance.availability
readonly consumed_rolling_evidence_sha256=926e8f7b15132c0da503c3aca51ab77647afc08b712f0a5e2c9ff3df06f80912
readonly consumed_action33m_evidence=/tmp/caddy-ssh-evidence/action33m/run.E9TEiy
readonly consumed_action33m_evidence_sha256=b517fc714d7c7442dc8cd68e3af04fc8e81892a7241393be01727f2952da4a7e
readonly maximum_handoff_window_ns=60000000000
readonly maximum_failed_sample_recovery_ns=4000000000
ssh_binary=${CADDY_ACTION33N_SSH_BIN:-/usr/bin/ssh}
readonly ssh_binary
scp_binary=${CADDY_ACTION33N_SCP_BIN:-/usr/bin/scp}
readonly scp_binary
run_id=$(date -u +%Y%m%dT%H%M%SZ)-$$
work_root=
availability_pid=
availability_scenario=
availability_handoffs=
availability_stop_request=
handoff_label=
handoff_start_ns=
current_scenario=baseline
mutated=false
registry_uploaded_a=false
registry_uploaded_b=false
failed_action33k_recovery_started=false
baseline_captured=false
node_b_reboot_started=false
node_b_state_rehydrated=true
baseline_bundle_a=
baseline_bundle_b=
baseline_bundle_a_sha256=
baseline_bundle_b_sha256=
node_b_reboot_scenario_bundle=
node_b_reboot_scenario_bundle_sha256=

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
directory_aggregate_hash() {
    local action33n_outer_directory=$1

    (
        cd "$action33n_outer_directory"
        find . -type f -print0 | LC_ALL=C sort -z |
            xargs -0 sha256sum | sha256sum | awk '{ print $1 }'
    )
}
line_count() { awk 'END { print NR }' "$1"; }
safe_stream() {
    local action33n_outer_stream=$1
    [[ "$(wc -c <"$action33n_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action33n_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action33n_outer_stream" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action33n_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' "$action33n_outer_stream"
}
capture_files() {
    local action33n_outer_path
    for action33n_outer_path in "$@"; do
        install -m 0600 /dev/null "$action33n_outer_path"
        chmod 0600 "$action33n_outer_path"
    done
}
emit_stream() {
    local action33n_outer_label=$1
    local action33n_outer_path=$2
    printf '%s_%s_bytes=%s\n' "$prefix" "$action33n_outer_label" "$(wc -c <"$action33n_outer_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action33n_outer_label" "$(line_count "$action33n_outer_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action33n_outer_label" "$(file_hash "$action33n_outer_path")"
    safe_stream "$action33n_outer_path" || return 97
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action33n_outer_label"
    if [[ -s "$action33n_outer_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action33n_outer_label"
        sed "s/^/${prefix}_${action33n_outer_label}_content=/" \
            "$action33n_outer_path"
        printf '%s_%s_end\n' "$prefix" "$action33n_outer_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action33n_outer_label"
    fi
}
gate() {
    local action33n_outer_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action33n_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action33n_outer_label" >&2
    return 1
}
run_remote() {
    local action33n_outer_label=$1 target=$2 alias=$3 role=$4 mode=$5 scenario=$6 argument=${7:-}
    local action33n_outer_stdout=$work_root/$action33n_outer_label.stdout
    local action33n_outer_stderr=$work_root/$action33n_outer_label.stderr
    local action33n_outer_status_file=$work_root/$action33n_outer_label.status
    local action33n_outer_status=0
    capture_files "$action33n_outer_stdout" "$action33n_outer_stderr" "$action33n_outer_status_file"
    "$ssh_binary" -T -o BatchMode=yes -o StrictHostKeyChecking=yes -o "HostKeyAlias=$alias" -o ConnectTimeout=10 -o ConnectionAttempts=1 "$target" \
        "cd / && sudo -n /bin/bash -s -- $mode $role $run_id $scenario $argument" <"$transaction" >"$action33n_outer_stdout" 2>"$action33n_outer_stderr" || action33n_outer_status=$?
    printf '%s\n' "$action33n_outer_status" >"$action33n_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action33n_outer_label" "$action33n_outer_status"
    emit_stream "remote_stdout_$action33n_outer_label" "$action33n_outer_stdout"
    emit_stream "remote_stderr_$action33n_outer_label" "$action33n_outer_stderr"
    [[ "$action33n_outer_status" -eq 0 ]]
}
run_local() {
    local action33n_outer_label=$1
    local action33n_outer_stdout=$work_root/$action33n_outer_label.stdout
    local action33n_outer_stderr=$work_root/$action33n_outer_label.stderr
    local action33n_outer_status_file=$work_root/$action33n_outer_label.status
    local action33n_outer_status=0

    shift
    capture_files "$action33n_outer_stdout" "$action33n_outer_stderr" \
        "$action33n_outer_status_file"
    "$@" >"$action33n_outer_stdout" 2>"$action33n_outer_stderr" ||
        action33n_outer_status=$?
    printf '%s\n' "$action33n_outer_status" >"$action33n_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action33n_outer_label" \
        "$action33n_outer_status"
    emit_stream "local_stdout_$action33n_outer_label" "$action33n_outer_stdout"
    emit_stream "local_stderr_$action33n_outer_label" "$action33n_outer_stderr"
    [[ "$action33n_outer_status" -eq 0 ]]
}
upload_registry() {
    local action33n_outer_label=$1
    local action33n_outer_target=$2
    local action33n_outer_alias=$3
    local action33n_outer_stdout=$work_root/$action33n_outer_label.stdout
    local action33n_outer_stderr=$work_root/$action33n_outer_label.stderr
    local action33n_outer_status_file=$work_root/$action33n_outer_label.status
    local action33n_outer_status=0

    capture_files "$action33n_outer_stdout" "$action33n_outer_stderr" \
        "$action33n_outer_status_file"
    "$scp_binary" -q -p -o BatchMode=yes -o StrictHostKeyChecking=yes \
        -o "HostKeyAlias=$action33n_outer_alias" -o ConnectTimeout=10 \
        -o ConnectionAttempts=1 "$registry" \
        "$action33n_outer_target:/tmp/caddy-action33n-registry-$run_id.tsv" \
        >"$action33n_outer_stdout" 2>"$action33n_outer_stderr" ||
        action33n_outer_status=$?
    printf '%s\n' "$action33n_outer_status" >"$action33n_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action33n_outer_label" \
        "$action33n_outer_status"
    emit_stream "remote_stdout_$action33n_outer_label" "$action33n_outer_stdout"
    emit_stream "remote_stderr_$action33n_outer_label" "$action33n_outer_stderr"
    [[ "$action33n_outer_status" -eq 0 ]]
}
download_baseline_bundle() {
    local action33n_outer_label=$1
    local action33n_outer_target=$2
    local action33n_outer_alias=$3
    local action33n_outer_role=$4
    local action33n_outer_snapshot=$5
    local action33n_outer_destination=$6
    local action33n_outer_stdout=$work_root/$action33n_outer_label.stdout
    local action33n_outer_stderr=$work_root/$action33n_outer_label.stderr
    local action33n_outer_status_file=$work_root/$action33n_outer_label.status
    local action33n_outer_status=0

    capture_files "$action33n_outer_stdout" "$action33n_outer_stderr" \
        "$action33n_outer_status_file" "$action33n_outer_destination"
    "$scp_binary" -q -p -o BatchMode=yes -o StrictHostKeyChecking=yes \
        -o "HostKeyAlias=$action33n_outer_alias" -o ConnectTimeout=10 \
        -o ConnectionAttempts=1 \
        "$action33n_outer_target:/run/caddy-action33n-baseline-$run_id-$action33n_outer_snapshot-$action33n_outer_role/baseline.tar" \
        "$action33n_outer_destination" >"$action33n_outer_stdout" \
        2>"$action33n_outer_stderr" || action33n_outer_status=$?
    chmod 0600 "$action33n_outer_destination"
    printf '%s\n' "$action33n_outer_status" >"$action33n_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action33n_outer_label" \
        "$action33n_outer_status"
    emit_stream "remote_stdout_$action33n_outer_label" "$action33n_outer_stdout"
    emit_stream "remote_stderr_$action33n_outer_label" "$action33n_outer_stderr"
    [[ "$action33n_outer_status" -eq 0 ]]
    gate "${action33n_outer_label}_bundle_regular" test -f \
        "$action33n_outer_destination"
    gate "${action33n_outer_label}_bundle_nonempty" test -s \
        "$action33n_outer_destination"
    printf '%s_%s_bundle_path=%s\n' "$prefix" "$action33n_outer_label" \
        "$action33n_outer_destination"
    printf '%s_%s_bundle_sha256=%s\n' "$prefix" "$action33n_outer_label" \
        "$(file_hash "$action33n_outer_destination")"
}
upload_baseline_bundle() {
    local action33n_outer_label=$1
    local action33n_outer_source=$2
    local action33n_outer_target=$3
    local action33n_outer_alias=$4
    local action33n_outer_role=$5
    local action33n_outer_snapshot=$6
    local action33n_outer_stdout=$work_root/$action33n_outer_label.stdout
    local action33n_outer_stderr=$work_root/$action33n_outer_label.stderr
    local action33n_outer_status_file=$work_root/$action33n_outer_label.status
    local action33n_outer_status=0

    gate "${action33n_outer_label}_source_regular" test -f \
        "$action33n_outer_source"
    gate "${action33n_outer_label}_source_nonempty" test -s \
        "$action33n_outer_source"
    capture_files "$action33n_outer_stdout" "$action33n_outer_stderr" \
        "$action33n_outer_status_file"
    "$scp_binary" -q -p -o BatchMode=yes -o StrictHostKeyChecking=yes \
        -o "HostKeyAlias=$action33n_outer_alias" -o ConnectTimeout=10 \
        -o ConnectionAttempts=1 "$action33n_outer_source" \
        "$action33n_outer_target:/tmp/caddy-action33n-baseline-$run_id-$action33n_outer_snapshot-$action33n_outer_role.tar" \
        >"$action33n_outer_stdout" 2>"$action33n_outer_stderr" ||
        action33n_outer_status=$?
    printf '%s\n' "$action33n_outer_status" >"$action33n_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action33n_outer_label" \
        "$action33n_outer_status"
    emit_stream "remote_stdout_$action33n_outer_label" "$action33n_outer_stdout"
    emit_stream "remote_stderr_$action33n_outer_label" "$action33n_outer_stderr"
    [[ "$action33n_outer_status" -eq 0 ]]
}
persist_baseline_on_workstation() {
    local action33n_outer_role=$1
    local action33n_outer_target=$2
    local action33n_outer_alias=$3
    local action33n_outer_snapshot=${4:-baseline}
    local action33n_outer_stage_stdout
    local action33n_outer_expected_sha
    local action33n_outer_bundle=$work_root/reboot-baseline-$action33n_outer_snapshot-$action33n_outer_role.tar

    run_remote "baseline-stage-$action33n_outer_snapshot-$action33n_outer_role" "$action33n_outer_target" \
        "$action33n_outer_alias" "$action33n_outer_role" \
        --stage-baseline-bundle "$action33n_outer_snapshot"
    action33n_outer_stage_stdout=$work_root/baseline-stage-$action33n_outer_snapshot-$action33n_outer_role.stdout
    action33n_outer_expected_sha=$(grep -Eo \
        'baseline_bundle_sha256=[0-9a-f]{64}' \
        "$action33n_outer_stage_stdout" | tail -n 1 | cut -d= -f2)
    gate "baseline_stage_${action33n_outer_role}_sha_format" test \
        "${#action33n_outer_expected_sha}" -eq 64
    download_baseline_bundle "baseline-download-$action33n_outer_snapshot-$action33n_outer_role" \
        "$action33n_outer_target" "$action33n_outer_alias" \
        "$action33n_outer_role" "$action33n_outer_snapshot" \
        "$action33n_outer_bundle"
    gate "baseline_download_${action33n_outer_snapshot}_${action33n_outer_role}_sha_exact" test \
        "$(file_hash "$action33n_outer_bundle")" = \
        "$action33n_outer_expected_sha"
    run_remote "baseline-stage-remove-$action33n_outer_snapshot-$action33n_outer_role" \
        "$action33n_outer_target" "$action33n_outer_alias" \
        "$action33n_outer_role" --remove-baseline-stage \
        "$action33n_outer_snapshot"
    if [[ "$action33n_outer_snapshot" = baseline &&
        "$action33n_outer_role" = node-a ]]; then
        baseline_bundle_a=$action33n_outer_bundle
        baseline_bundle_a_sha256=$action33n_outer_expected_sha
    elif [[ "$action33n_outer_snapshot" = baseline ]]; then
        baseline_bundle_b=$action33n_outer_bundle
        baseline_bundle_b_sha256=$action33n_outer_expected_sha
    else
        node_b_reboot_scenario_bundle=$action33n_outer_bundle
        node_b_reboot_scenario_bundle_sha256=$action33n_outer_expected_sha
    fi
}
rehydrate_node_b_state() {
    upload_registry reboot-registry-b "$node_b_target" "$node_b_alias"
    registry_uploaded_b=true
    upload_baseline_bundle reboot-baseline-upload-b "$baseline_bundle_b" \
        "$node_b_target" "$node_b_alias" node-b baseline
    run_remote reboot-baseline-import-b "$node_b_target" "$node_b_alias" \
        node-b --import-baseline baseline "$baseline_bundle_b_sha256"
    upload_baseline_bundle reboot-scenario-upload-b \
        "$node_b_reboot_scenario_bundle" "$node_b_target" "$node_b_alias" \
        node-b node-b-reboot
    run_remote reboot-scenario-import-b "$node_b_target" "$node_b_alias" \
        node-b --import-baseline node-b-reboot \
        "$node_b_reboot_scenario_bundle_sha256"
    node_b_state_rehydrated=true
}
wait_ssh_state() {
    local action33n_outer_label=$1 target=$2 alias=$3 expected=$4 limit=$5 elapsed=0 status
    while ((elapsed < limit)); do
        status=0
        "$ssh_binary" -T -o BatchMode=yes -o StrictHostKeyChecking=yes -o "HostKeyAlias=$alias" -o ConnectTimeout=2 -o ConnectionAttempts=1 "$target" 'cd / && true' >/dev/null 2>&1 || status=$?
        if { [[ "$expected" = up && "$status" -eq 0 ]]; } || { [[ "$expected" = down && "$status" -ne 0 ]]; }; then
            printf '%s_%s_elapsed_seconds=%s\n' "$prefix" "$action33n_outer_label" "$elapsed"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}
availability_probe() {
    dig +time=1 +tries=1 @10.1.0.55 proxy.local.theama.co A +short &&
        curl --fail --silent --show-error --max-time 2 \
            https://proxy.local.theama.co/ -o /dev/null &&
        curl --fail --silent --show-error --max-time 2 \
            https://pihole-admin.local.theama.co/admin/login.php -o /dev/null
}
start_availability() {
    local action33n_outer_scenario=$1
    local action33n_outer_output=$work_root/$action33n_outer_scenario.availability
    availability_handoffs=$work_root/$action33n_outer_scenario.handoffs
    availability_stop_request=$work_root/$action33n_outer_scenario.stop-request
    capture_files "$action33n_outer_output" "$availability_handoffs"
    [[ ! -e "$availability_stop_request" ]]
    (
        while [[ ! -e "$availability_stop_request" ]]; do
            printf '%s\t' "$(date +%s%N)" >>"$action33n_outer_output"
            if availability_probe >>"$action33n_outer_output" 2>&1; then
                printf 'ok\n' >>"$action33n_outer_output"
            else
                printf 'failed\n' >>"$action33n_outer_output"
            fi
            sleep 1
        done
    ) &
    availability_pid=$!
    availability_scenario=$action33n_outer_scenario
}
begin_handoff() {
    local action33n_outer_label=$1
    [[ -z "$handoff_label" ]] || return 1
    handoff_label=$action33n_outer_label
    handoff_start_ns=$(date +%s%N)
    printf '%s_handoff_%s_begin_ns=%s\n' "$prefix" "$handoff_label" \
        "$handoff_start_ns"
}
end_handoff() {
    local action33n_outer_label=$1
    local action33n_outer_end_ns
    [[ "$handoff_label" = "$action33n_outer_label" ]] || return 1
    action33n_outer_end_ns=$(date +%s%N)
    printf '%s\t%s\t%s\n' "$handoff_label" "$handoff_start_ns" \
        "$action33n_outer_end_ns" >>"$availability_handoffs"
    printf '%s_handoff_%s_end_ns=%s\n' "$prefix" "$handoff_label" \
        "$action33n_outer_end_ns"
    handoff_label=
    handoff_start_ns=
}
build_availability_summary() {
    local action33n_outer_availability=$1
    local action33n_outer_summary=$2

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
    ' "$action33n_outer_availability" >"$action33n_outer_summary"
}
validate_availability_windows() {
    local action33n_outer_windows=$1
    local action33n_outer_summary=$2

    awk -F '\t' -v maximum_window="$maximum_handoff_window_ns" \
        -v windows_file="$action33n_outer_windows" '
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
    ' "$action33n_outer_windows" "$action33n_outer_summary"
}
validate_availability_recovery() {
    local action33n_outer_summary=$1

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
    ' "$action33n_outer_summary"
}
validate_availability_file() {
    local action33n_outer_label=$1
    local action33n_outer_availability=$2
    local action33n_outer_windows=$3
    local action33n_outer_summary=$action33n_outer_availability.summary
    local action33n_outer_sample_count
    local action33n_outer_failure_count

    # conditional-validator-explicit-failures-begin
    gate "${action33n_outer_label}_availability_regular" test -f \
        "$action33n_outer_availability" || return
    gate "${action33n_outer_label}_availability_not_symlink" test ! -L \
        "$action33n_outer_availability" || return
    gate "${action33n_outer_label}_handoffs_regular" test -f \
        "$action33n_outer_windows" || return
    gate "${action33n_outer_label}_handoffs_not_symlink" test ! -L \
        "$action33n_outer_windows" || return
    capture_files "$action33n_outer_summary"
    gate "${action33n_outer_label}_availability_grammar" \
        build_availability_summary "$action33n_outer_availability" \
        "$action33n_outer_summary" || return
    action33n_outer_sample_count=$(awk 'END { print NR }' \
        "$action33n_outer_summary")
    action33n_outer_failure_count=$(awk -F '\t' '$2 == "failed" { count++ } END { print count + 0 }' \
        "$action33n_outer_summary")
    printf '%s_%s_observed_sample_count=%s\n' "$prefix" \
        "$action33n_outer_label" "$action33n_outer_sample_count"
    printf '%s_%s_observed_failure_count=%s\n' "$prefix" \
        "$action33n_outer_label" "$action33n_outer_failure_count"
    gate "${action33n_outer_label}_availability_nonempty" test \
        "$action33n_outer_sample_count" -gt 0 || return
    gate "${action33n_outer_label}_failures_inside_handoffs" \
        validate_availability_windows "$action33n_outer_windows" \
        "$action33n_outer_summary" || return
    gate "${action33n_outer_label}_failures_isolated_and_bounded" \
        validate_availability_recovery "$action33n_outer_summary" || return
    # conditional-validator-explicit-failures-end
}
consume_action33g_rolling_evidence() {
    local action33n_outer_observed_hash
    local action33n_outer_observed_samples
    local action33n_outer_observed_ok
    local action33n_outer_observed_failed
    local action33n_outer_observed_failure_index
    local action33n_outer_observed_pre_ns
    local action33n_outer_observed_failure_ns
    local action33n_outer_observed_post_ns
    local action33n_outer_observed_window_ns

    # conditional-validator-explicit-failures-begin
    gate consumed_rolling_evidence_regular test -f \
        "$consumed_rolling_evidence" || return
    gate consumed_rolling_evidence_not_symlink test ! -L \
        "$consumed_rolling_evidence" || return
    # conditional-validator-explicit-failures-end
    action33n_outer_observed_hash=$(file_hash "$consumed_rolling_evidence")
    read -r action33n_outer_observed_samples action33n_outer_observed_ok \
        action33n_outer_observed_failed action33n_outer_observed_failure_index \
        action33n_outer_observed_pre_ns action33n_outer_observed_failure_ns \
        action33n_outer_observed_post_ns < <(
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
    action33n_outer_observed_window_ns=$((action33n_outer_observed_post_ns - action33n_outer_observed_pre_ns))
    printf '%s_consumed_rolling_expected_sha256=%s\n' "$prefix" \
        "$consumed_rolling_evidence_sha256"
    printf '%s_consumed_rolling_observed_sha256=%s\n' "$prefix" \
        "$action33n_outer_observed_hash"
    printf '%s_consumed_rolling_observed_samples=%s\n' "$prefix" \
        "$action33n_outer_observed_samples"
    printf '%s_consumed_rolling_observed_ok=%s\n' "$prefix" \
        "$action33n_outer_observed_ok"
    printf '%s_consumed_rolling_observed_failed=%s\n' "$prefix" \
        "$action33n_outer_observed_failed"
    printf '%s_consumed_rolling_observed_failure_index=%s\n' "$prefix" \
        "$action33n_outer_observed_failure_index"
    printf '%s_consumed_rolling_observed_pre_ns=%s\n' "$prefix" \
        "$action33n_outer_observed_pre_ns"
    printf '%s_consumed_rolling_observed_failure_ns=%s\n' "$prefix" \
        "$action33n_outer_observed_failure_ns"
    printf '%s_consumed_rolling_observed_post_ns=%s\n' "$prefix" \
        "$action33n_outer_observed_post_ns"
    printf '%s_consumed_rolling_observed_window_ns=%s\n' "$prefix" \
        "$action33n_outer_observed_window_ns"
    # conditional-validator-explicit-failures-begin
    gate consumed_rolling_evidence_hash test \
        "$action33n_outer_observed_hash" = \
        "$consumed_rolling_evidence_sha256" || return
    gate consumed_rolling_samples_exact test \
        "$action33n_outer_observed_samples" -eq 51 || return
    gate consumed_rolling_ok_exact test \
        "$action33n_outer_observed_ok" -eq 50 || return
    gate consumed_rolling_failed_exact test \
        "$action33n_outer_observed_failed" -eq 1 || return
    gate consumed_rolling_failure_index_exact test \
        "$action33n_outer_observed_failure_index" -eq 16 || return
    gate consumed_rolling_pre_sample_exact test \
        "$action33n_outer_observed_pre_ns" = 1786575427373856041 || return
    gate consumed_rolling_failed_sample_exact test \
        "$action33n_outer_observed_failure_ns" = 1786575428456195162 || return
    gate consumed_rolling_post_sample_exact test \
        "$action33n_outer_observed_post_ns" = 1786575430480634425 || return
    gate consumed_rolling_recovery_window_bounded test \
        "$action33n_outer_observed_window_ns" -le \
        "$maximum_failed_sample_recovery_ns" || return
    # conditional-validator-explicit-failures-end
    emit_stream consumed_rolling_availability "$consumed_rolling_evidence"
}
stop_availability() {
    local action33n_outer_scenario=$1
    local action33n_outer_wait_samples=0

    capture_files "$availability_stop_request"
    while kill -0 "$availability_pid" >/dev/null 2>&1 &&
        ((action33n_outer_wait_samples < 12)); do
        sleep 1
        action33n_outer_wait_samples=$((action33n_outer_wait_samples + 1))
    done
    if kill -0 "$availability_pid" >/dev/null 2>&1; then
        kill "$availability_pid" >/dev/null 2>&1 || true
        wait "$availability_pid" 2>/dev/null || true
        return 1
    fi
    wait "$availability_pid"
    rm -f -- "$availability_stop_request"
    availability_pid=
    availability_scenario=
    emit_stream "${action33n_outer_scenario}_availability" "$work_root/$action33n_outer_scenario.availability"
    emit_stream "${action33n_outer_scenario}_handoffs" \
        "$work_root/$action33n_outer_scenario.handoffs"
    [[ -z "$handoff_label" ]] || return 1
    validate_availability_file "$action33n_outer_scenario" \
        "$work_root/$action33n_outer_scenario.availability" \
        "$work_root/$action33n_outer_scenario.handoffs"
    availability_handoffs=
    availability_stop_request=
}
baseline() {
    local action33n_outer_scenario=$1

    run_remote "$action33n_outer_scenario-baseline-a" "$node_a_target" \
        "$node_a_alias" node-a --baseline "$action33n_outer_scenario"
    run_remote "$action33n_outer_scenario-baseline-b" "$node_b_target" \
        "$node_b_alias" node-b --baseline "$action33n_outer_scenario"
    run_remote "$action33n_outer_scenario-master" "$node_a_target" \
        "$node_a_alias" node-a --assert-master "$action33n_outer_scenario"
    run_remote "$action33n_outer_scenario-backup" "$node_b_target" \
        "$node_b_alias" node-b --assert-backup "$action33n_outer_scenario"
    gate "$action33n_outer_scenario-release_identity_equal" test \
        "$(grep -Eo 'observed_current_revision=[A-Za-z0-9._-]+' \
            "$work_root/$action33n_outer_scenario-baseline-a.stdout" | tail -n 1)" = \
        "$(grep -Eo 'observed_current_revision=[A-Za-z0-9._-]+' \
            "$work_root/$action33n_outer_scenario-baseline-b.stdout" | tail -n 1)"
    gate "$action33n_outer_scenario-release_manifest_equal" test \
        "$(grep -Eo 'observed_release_manifest_sha256=[0-9a-f]{64}' \
            "$work_root/$action33n_outer_scenario-baseline-a.stdout" | tail -n 1)" = \
        "$(grep -Eo 'observed_release_manifest_sha256=[0-9a-f]{64}' \
            "$work_root/$action33n_outer_scenario-baseline-b.stdout" | tail -n 1)"
}
restore_baseline() {
    local action33n_outer_scenario=$1
    run_remote "$action33n_outer_scenario-prepare-b" "$node_b_target" \
        "$node_b_alias" node-b --prepare-cleanup "$action33n_outer_scenario"
    run_remote "$action33n_outer_scenario-prepare-a" "$node_a_target" \
        "$node_a_alias" node-a --prepare-cleanup "$action33n_outer_scenario"
    run_remote "$action33n_outer_scenario-freeze-b" "$node_b_target" \
        "$node_b_alias" node-b --freeze "$action33n_outer_scenario"
    run_remote "$action33n_outer_scenario-freeze-a" "$node_a_target" \
        "$node_a_alias" node-a --freeze "$action33n_outer_scenario"
    run_remote "$action33n_outer_scenario-cleanup-b" "$node_b_target" \
        "$node_b_alias" node-b --cleanup "$action33n_outer_scenario"
    run_remote "$action33n_outer_scenario-cleanup-a" "$node_a_target" \
        "$node_a_alias" node-a --cleanup "$action33n_outer_scenario"
    run_remote "$action33n_outer_scenario-restore-b" "$node_b_target" \
        "$node_b_alias" node-b --restore-services "$action33n_outer_scenario"
    run_remote "$action33n_outer_scenario-restore-a" "$node_a_target" \
        "$node_a_alias" node-a --restore-services "$action33n_outer_scenario"
    run_remote "$action33n_outer_scenario-final-a" "$node_a_target" \
        "$node_a_alias" node-a --final "$action33n_outer_scenario"
    run_remote "$action33n_outer_scenario-final-b" "$node_b_target" \
        "$node_b_alias" node-b --final "$action33n_outer_scenario"
    gate "$action33n_outer_scenario-final_release_identity_equal" test \
        "$(grep -Eo 'observed_current_revision=[A-Za-z0-9._-]+' \
            "$work_root/$action33n_outer_scenario-final-a.stdout" | tail -n 1)" = \
        "$(grep -Eo 'observed_current_revision=[A-Za-z0-9._-]+' \
            "$work_root/$action33n_outer_scenario-final-b.stdout" | tail -n 1)"
    gate "$action33n_outer_scenario-final_release_manifest_equal" test \
        "$(grep -Eo 'observed_release_manifest_sha256=[0-9a-f]{64}' \
            "$work_root/$action33n_outer_scenario-final-a.stdout" | tail -n 1)" = \
        "$(grep -Eo 'observed_release_manifest_sha256=[0-9a-f]{64}' \
            "$work_root/$action33n_outer_scenario-final-b.stdout" | tail -n 1)"
}
recover_failed_action33k() {
    local action33n_outer_failed=false

    run_remote action33k-recovery-freeze-b "$node_b_target" "$node_b_alias" \
        node-b --recover-action33k-freeze recovery || action33n_outer_failed=true
    run_remote action33k-recovery-freeze-a "$node_a_target" "$node_a_alias" \
        node-a --recover-action33k-freeze recovery || action33n_outer_failed=true
    run_remote action33k-recovery-apply-b "$node_b_target" "$node_b_alias" \
        node-b --recover-action33k-apply recovery || action33n_outer_failed=true
    run_remote action33k-recovery-apply-a "$node_a_target" "$node_a_alias" \
        node-a --recover-action33k-apply recovery || action33n_outer_failed=true
    run_remote action33k-recovery-restore-a "$node_a_target" "$node_a_alias" \
        node-a --recover-action33k-restore recovery || action33n_outer_failed=true
    run_remote action33k-recovery-restore-b "$node_b_target" "$node_b_alias" \
        node-b --recover-action33k-restore recovery || action33n_outer_failed=true
    [[ "$action33n_outer_failed" = false ]]
}
recover() {
    local action33n_outer_failed=false
    if [[ -n "$availability_pid" ]]; then
        stop_availability "$availability_scenario" || true
    fi
    if [[ "$node_b_reboot_started" = true &&
        "$node_b_state_rehydrated" = false ]]; then
        wait_ssh_state recovery-b-up "$node_b_target" "$node_b_alias" up \
            300 || action33n_outer_failed=true
        if [[ "$action33n_outer_failed" = false ]]; then
            rehydrate_node_b_state || action33n_outer_failed=true
        fi
    fi
    if [[ "$failed_action33k_recovery_started" = true &&
        "$baseline_captured" = false ]]; then
        recover_failed_action33k || action33n_outer_failed=true
    elif [[ "$mutated" = true ]]; then
        restore_baseline "$current_scenario" || action33n_outer_failed=true
    fi
    if [[ "$registry_uploaded_b" = true ]]; then
        run_remote recovery-remove-registry-b "$node_b_target" \
            "$node_b_alias" node-b --remove-registry recovery ||
            action33n_outer_failed=true
    fi
    if [[ "$registry_uploaded_a" = true ]]; then
        run_remote recovery-remove-registry-a "$node_a_target" \
            "$node_a_alias" node-a --remove-registry recovery ||
            action33n_outer_failed=true
    fi
    [[ "$action33n_outer_failed" = false ]] || exit 125
}
trap recover ERR INT TERM

if [[ "${1:-}" = --self-test ]]; then
    gate transaction_self_test /bin/bash "$transaction" --self-test node-a self-test self-test
    gate baseline_bundle_self_test /bin/bash "$transaction" \
        --baseline-bundle-self-test
    gate action33k_family_self_test /bin/bash "$transaction" \
        --action33k-family-self-test
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
if [[ "${1:-}" = --availability-stop-self-test ]]; then
    [[ $# -eq 1 ]] || exit 64
    work_root=$(mktemp -d /tmp/action33n-stop-self-test.XXXXXX)
    chmod 0700 "$work_root"
    availability_probe() {
        printf '10.1.0.56\n'
        sleep 0.1
    }
    start_availability stop-self-test
    sleep 0.2
    stop_availability stop-self-test
    gate stop_self_test_no_open_sample test \
        "$(awk -F '\t' 'END { print NF }' \
            "$work_root/stop-self-test.availability.summary")" -eq 2
    printf '%s_availability_stop_self_test_evidence=%s\n' "$prefix" \
        "$work_root"
    printf '%s_availability_stop_self_test_complete=true\n' "$prefix"
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
gate action33m_execution_consumed test -f \
    "$caddy_root/manifests/caddy-ha-reliability-action33m.yaml"
gate action33m_evidence_directory test -d "$consumed_action33m_evidence"
gate action33m_evidence_aggregate_hash test \
    "$(directory_aggregate_hash "$consumed_action33m_evidence")" = \
    "$consumed_action33m_evidence_sha256"
gate action33m_failed_before_mutation_status grep -Fxq 1 \
    "$consumed_action33m_evidence/action33k-recovery-preflight-a.status"
gate action33m_exact_preflight_rejection grep -Fxq \
    'action_33m_remote_node_a_check_failed_action33k_candidate_valid=false' \
    "$consumed_action33m_evidence/action33k-recovery-preflight-a.stderr"
gate action33m_no_recovery_mutation_evidence test ! -e \
    "$consumed_action33m_evidence/action33k-recovery-freeze-a.status"
upload_registry registry-a "$node_a_target" "$node_a_alias"
registry_uploaded_a=true
upload_registry registry-b "$node_b_target" "$node_b_alias"
registry_uploaded_b=true
run_remote action33k-recovery-preflight-a "$node_a_target" "$node_a_alias" \
    node-a --recover-action33k-preflight recovery
run_remote action33k-recovery-preflight-b "$node_b_target" "$node_b_alias" \
    node-b --recover-action33k-preflight recovery
failed_action33k_recovery_started=true
recover_failed_action33k
baseline baseline
baseline_captured=true
failed_action33k_recovery_started=false
mutated=true
persist_baseline_on_workstation node-a "$node_a_target" "$node_a_alias"
persist_baseline_on_workstation node-b "$node_b_target" "$node_b_alias"

# Actions 33g and 33h are consumed. Action 33i completed online guarded B-to-A
# emergency replication and normal A-to-B ancestry normalization with every
# availability sample passing, then recovered the exact Action 32g baseline
# after its 15-second orchestration-window assertion rejected a 22.45-second
# handoff. Action 33j then completed and recovered the controlled Node A
# outage but rejected a torn final availability sample created by killing the
# producer between its timestamp and terminal state. Action 33k then completed
# the Node A reboot and availability checks but lost its node-local baseline
# across reboot. Action 33m then failed before mutation because it required an
# inferred emergency release-manifest hash that production evidence did not
# establish. Action 33n consumes that fail-closed evidence, validates both
# exact Action 33k families without that unsupported prerequisite, restores
# Action 32g, and begins at the first unexecuted Node B outage case.
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
gate action33j_execution_consumed test -f \
    "$caddy_root/manifests/caddy-ha-reliability-action33j.yaml"
gate action33j_node_a_controlled_outage_consumed true
gate action33j_controlled_outage_availability_all_passed true
gate action33k_execution_consumed test -f \
    "$caddy_root/manifests/caddy-ha-reliability-action33k.yaml"
gate action33k_node_a_reboot_consumed true
gate action33k_node_a_reboot_availability_all_passed true

for scenario in node-b-controlled node-b-reboot; do
    current_scenario=$scenario
    baseline "$scenario"
    if [[ "$scenario" = node-b-reboot ]]; then
        persist_baseline_on_workstation node-b "$node_b_target" \
            "$node_b_alias" "$scenario"
    fi
    start_availability "$scenario"
    case "$scenario" in
        node-b-controlled)
            run_remote outage-b "$node_b_target" "$node_b_alias" node-b --controlled-outage "$scenario" || true
            wait_ssh_state b-down "$node_b_target" "$node_b_alias" down 20
            run_remote master-a "$node_a_target" "$node_a_alias" node-a --assert-master "$scenario"
            run_remote publish-a "$node_a_target" "$node_a_alias" node-a --publish-normal "$scenario" "action33n-$run_id-$scenario"
            run_remote promote-a "$node_a_target" "$node_a_alias" node-a \
                --promote-outgoing "$scenario" "action33n-$run_id-$scenario"
            run_remote queued-a "$node_a_target" "$node_a_alias" node-a \
                --assert-queued "$scenario" "action33n-$run_id-$scenario"
            sleep 12
            wait_ssh_state b-up "$node_b_target" "$node_b_alias" up 60
            run_remote offline-proof-b "$node_b_target" "$node_b_alias" \
                node-b --assert-controlled-offline "$scenario"
            run_remote health-restore-b "$node_b_target" "$node_b_alias" \
                node-b --restore-health "$scenario"
            run_remote recovered-b "$node_b_target" "$node_b_alias" node-b \
                --assert-recovered "$scenario"
            run_remote wait-b "$node_b_target" "$node_b_alias" node-b \
                --wait-current "$scenario" "action33n-$run_id-$scenario"
            ;;
        node-b-reboot)
            node_b_reboot_started=true
            node_b_state_rehydrated=false
            run_remote preboot-b "$node_b_target" "$node_b_alias" node-b \
                --boot-id "$scenario"
            run_remote reboot-b "$node_b_target" "$node_b_alias" node-b --prepare-reboot "$scenario"
            wait_ssh_state b-down "$node_b_target" "$node_b_alias" down 30
            run_remote master-a "$node_a_target" "$node_a_alias" node-a --assert-master "$scenario"
            run_remote publish-a "$node_a_target" "$node_a_alias" node-a --publish-normal "$scenario" "action33n-$run_id-$scenario"
            run_remote promote-a "$node_a_target" "$node_a_alias" node-a \
                --promote-outgoing "$scenario" "action33n-$run_id-$scenario"
            run_remote queued-a "$node_a_target" "$node_a_alias" node-a \
                --assert-queued "$scenario" "action33n-$run_id-$scenario"
            wait_ssh_state b-up "$node_b_target" "$node_b_alias" up 300
            rehydrate_node_b_state
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
                --wait-current "$scenario" "action33n-$run_id-$scenario"
            ;;
    esac
    stop_availability "$scenario"
    restore_baseline "$scenario"
    node_b_reboot_started=false
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
gate final_baseline_bundle_a_retained test -f "$baseline_bundle_a"
gate final_baseline_bundle_a_hash_unchanged test \
    "$(file_hash "$baseline_bundle_a")" = "$baseline_bundle_a_sha256"
gate final_baseline_bundle_b_retained test -f "$baseline_bundle_b"
gate final_baseline_bundle_b_hash_unchanged test \
    "$(file_hash "$baseline_bundle_b")" = "$baseline_bundle_b_sha256"
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
