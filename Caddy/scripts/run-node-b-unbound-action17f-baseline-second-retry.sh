#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=f380b441aad02b981669d8b251bae67633c49d8769d2e424e20c52b6c8cd3081
readonly tracer_sha256=96437ea43b069b840dcf2abde5c30905f976d07008bfef17d211e9902d698c3b
readonly regression_sha256=7c9bef927c83757f73b42839540fe7acb113d2bc0c93e50b526ac9ea062126ad
readonly collision_checker_sha256=78b46fcdc6c4ca6b4cfe0121c347e0e101c472d723a891aac2dea7f23f085cd8
readonly historical_runner_sha256=5e1ee076526b3d6bc7622dffe23aa4516d4e3f9e14fd55a88ba6a27d5882a815
readonly accepted_live_state_sha256=3a05c0487101f3b44f8e5ba41a4a74713d07cddc369542f04d4a8b1f417cb824
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly inspector_path="$script_dir/diagnose-node-b-unbound-local-zone-prewrite-action17f-a.sh"
readonly tracer_path="$script_dir/trace-node-b-unbound-action17f-baseline-second-retry.sh"
readonly regression_path="$caddy_root/tests/action17f-b-second-retry-production-failure-regression.sh"
readonly collision_checker_path="$caddy_root/tests/check-shell-readonly-local-collisions.sh"
readonly historical_runner_path="$script_dir/run-node-b-unbound-action17f-labeled-baseline-retry.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_file() {
    local source_path=$1
    local expected_hash=$2

    [[ -f "$source_path" && ! -L "$source_path" ]]
    [[ "$(file_hash "$source_path")" == "$expected_hash" ]]
}

verify_sources() {
    verify_file "$inspector_path" "$inspector_sha256"
    verify_file "$tracer_path" "$tracer_sha256"
    verify_file "$regression_path" "$regression_sha256"
    verify_file "$collision_checker_path" "$collision_checker_sha256"
    verify_file "$historical_runner_path" "$historical_runner_sha256"
    bash -n \
        "$inspector_path" "$tracer_path" "$regression_path" \
        "$collision_checker_path" "$historical_runner_path"
}

verify_live_sources() {
    local source_path

    verify_sources
    for source_path in \
        "$inspector_path" "$tracer_path" "$regression_path" \
        "$collision_checker_path" "$historical_runner_path"; do
        [[ "$(stat -c '%U:%G:%a' "$source_path")" == aaron:aaron:755 ]]
    done
}

unique_value() {
    local record_prefix=$1
    local evidence_path=$2
    local record

    [[ "$(grep -Ec "^${record_prefix}=" "$evidence_path")" -eq 1 ]] ||
        return 1
    record=$(grep -E "^${record_prefix}=" "$evidence_path")
    printf '%s\n' "${record#*=}"
}

require_value() {
    local record_prefix=$1
    local expected_value=$2
    local evidence_path=$3

    [[ "$(unique_value "$record_prefix" "$evidence_path")" == "$expected_value" ]]
}

validate_secret_free() {
    if grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=|private-domain:|local-data(-ptr)?:' \
        "$@"; then
        return 1
    fi
}

validate_inspector_evidence() {
    local evidence_path=$1

    require_value action_17f_a_remote_reached true "$evidence_path"
    require_value working_directory_is_root true "$evidence_path"
    require_value prewrite_assertion_count 55 "$evidence_path"
    require_value prewrite_failed_assertion_count 0 "$evidence_path"
    require_value action_17f_a_conclusion \
        all_prewrite_prerequisites_pass "$evidence_path"
    require_value remote_paths_created false "$evidence_path"
    require_value dns_queries_performed false "$evidence_path"
    require_value dns_configuration_mutations false "$evidence_path"
    require_value service_mutations false "$evidence_path"
    require_value persistent_mutations false "$evidence_path"
    require_value action_17f_a_node_b_prewrite_diagnostic_complete \
        true "$evidence_path"
    [[ "$(grep -Ec '^prewrite_[a-zA-Z0-9_-]+=false$' "$evidence_path")" -eq 0 ]]
    validate_secret_free "$evidence_path"
}

validate_trace_evidence() {
    local evidence_path=$1
    local exact_status observed_hash expected_hash
    local failed_label failure_count completion_count

    require_value action_17f_b_second_retry_trace_remote_reached true \
        "$evidence_path"
    require_value remote_paths_created false "$evidence_path"
    require_value dns_queries_performed false "$evidence_path"
    require_value dns_configuration_mutations false "$evidence_path"
    require_value service_mutations false "$evidence_path"
    require_value persistent_mutations false "$evidence_path"
    require_value action_17f_b_second_retry_labeled_trace_complete true \
        "$evidence_path"

    exact_status=$(
        unique_value action_17f_b_second_retry_exact_baseline_status \
            "$evidence_path"
    )
    observed_hash=$(unique_value observed_live_state_sha256 "$evidence_path")
    expected_hash=$(unique_value expected_live_state_sha256 "$evidence_path")
    [[ "$exact_status" =~ ^[0-9]+$ ]]
    [[ "$observed_hash" =~ ^[0-9a-f]{64}$ ]]
    [[ "$expected_hash" == "$accepted_live_state_sha256" ]]

    failure_count=$(
        grep -Ec '^exact_assertion_[a-zA-Z0-9_]+=false$' "$evidence_path" ||
            true
    )
    completion_count=$(
        grep -Ec \
            '^action_17f_b_second_retry_exact_baseline_complete=true$' \
            "$evidence_path" || true
    )
    if [[ "$exact_status" -eq 0 ]]; then
        [[ "$observed_hash" == "$expected_hash" ]]
        [[ "$failure_count" -eq 0 ]]
        [[ "$completion_count" -eq 1 ]]
        require_value exact_assertion_baseline_live_state_hash true \
            "$evidence_path"
        require_value exact_assertion_baseline_live_state_hash_status 0 \
            "$evidence_path"
    else
        [[ "$observed_hash" != "$expected_hash" ]]
        [[ "$failure_count" -eq 1 ]]
        [[ "$completion_count" -eq 0 ]]
        failed_label=$(
            grep -E '^exact_assertion_[a-zA-Z0-9_]+=false$' "$evidence_path"
        )
        failed_label=${failed_label#exact_assertion_}
        failed_label=${failed_label%=false}
        [[ "$failed_label" == baseline_live_state_hash ]]
        [[ "$(grep -Ec "^exact_assertion_${failed_label}_status=[1-9][0-9]*$" \
            "$evidence_path")" -eq 1 ]]
    fi

    awk -F= '
        /^exact_assertion_[a-zA-Z0-9_]+=(true|false)$/ {
            if (++seen[$1] > 1) {
                exit 1
            }
        }
    ' "$evidence_path"
    validate_secret_free "$evidence_path"
}

run_contract_test() {
    local contract_dir inspector_fixture trace_fixture

    contract_dir=$(mktemp -d)
    trap 'rm -rf -- "$contract_dir"' RETURN
    inspector_fixture="$contract_dir/inspector"
    trace_fixture="$contract_dir/trace"

    printf '%s\n' \
        action_17f_a_remote_reached=true \
        working_directory_is_root=true \
        prewrite_assertion_count=55 \
        prewrite_failed_assertion_count=0 \
        action_17f_a_conclusion=all_prewrite_prerequisites_pass \
        remote_paths_created=false \
        dns_queries_performed=false \
        dns_configuration_mutations=false \
        service_mutations=false \
        persistent_mutations=false \
        action_17f_a_node_b_prewrite_diagnostic_complete=true \
        >"$inspector_fixture"
    printf '%s\n' \
        action_17f_b_second_retry_trace_remote_reached=true \
        observed_live_state_sha256=0000000000000000000000000000000000000000000000000000000000000000 \
        expected_live_state_sha256="$accepted_live_state_sha256" \
        exact_assertion_baseline_live_state_hash=false \
        exact_assertion_baseline_live_state_hash_status=1 \
        action_17f_b_second_retry_exact_baseline_status=1 \
        remote_paths_created=false \
        dns_queries_performed=false \
        dns_configuration_mutations=false \
        service_mutations=false \
        persistent_mutations=false \
        action_17f_b_second_retry_labeled_trace_complete=true \
        >"$trace_fixture"

    validate_inspector_evidence "$inspector_fixture"
    validate_trace_evidence "$trace_fixture"
    printf 'action_17f_b_second_retry_runner_contract_test_complete=true\n'
}

case "${1:-}" in
    --self-test)
        (($# == 1))
        verify_sources
        "$inspector_path" --self-test >/dev/null
        "$tracer_path" --self-test >/dev/null
        "$regression_path" >/dev/null
        printf 'action_17f_b_second_retry_runner_self_test_complete=true\n'
        exit 0
        ;;
    --source-test)
        (($# == 1))
        verify_live_sources
        "$collision_checker_path" "$0" >/dev/null
        printf 'action_17f_b_second_retry_runner_source_test_complete=true\n'
        exit 0
        ;;
    --contract-test)
        (($# == 1))
        verify_sources
        run_contract_test
        printf 'action_17f_b_second_retry_runner_contract_complete=true\n'
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 2
        ;;
esac

verify_live_sources
"$collision_checker_path" >/dev/null
"$regression_path" >/dev/null
run_contract_test >/dev/null

runner_work_dir=$(mktemp -d)
readonly runner_work_dir
readonly remote_inspector_evidence="$runner_work_dir/inspector"
readonly remote_trace_evidence="$runner_work_dir/trace"
cleanup() {
    rm -rf -- "$runner_work_dir"
    printf 'action_17f_b_second_retry_local_cleanup_complete=true\n'
}
trap cleanup EXIT

inspector_ssh_status=0
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias="$expected_host_alias" \
    -o StrictHostKeyChecking=yes \
    "$expected_target" \
    "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" \
    <"$inspector_path" >"$remote_inspector_evidence" 2>&1 ||
    inspector_ssh_status=$?

trace_ssh_status=0
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias="$expected_host_alias" \
    -o StrictHostKeyChecking=yes \
    "$expected_target" \
    "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" \
    <"$tracer_path" >"$remote_trace_evidence" 2>&1 ||
    trace_ssh_status=$?

printf '%s\n' action_17f_b_second_retry_inspector_transcript_begin
cat "$remote_inspector_evidence"
printf '%s\n' action_17f_b_second_retry_inspector_transcript_end
printf '%s\n' action_17f_b_second_retry_trace_transcript_begin
cat "$remote_trace_evidence"
printf '%s\n' action_17f_b_second_retry_trace_transcript_end
printf 'inspector_ssh_exit_status=%s\n' "$inspector_ssh_status"
printf 'trace_ssh_exit_status=%s\n' "$trace_ssh_status"

[[ "$inspector_ssh_status" -eq 0 ]]
[[ "$trace_ssh_status" -eq 0 ]]
validate_inspector_evidence "$remote_inspector_evidence"
validate_trace_evidence "$remote_trace_evidence"
printf 'action_17f_b_second_retry_read_only_diagnostic_accepted=true\n'
