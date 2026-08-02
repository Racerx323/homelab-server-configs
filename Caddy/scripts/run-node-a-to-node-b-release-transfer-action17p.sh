#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly node_a_host_alias=pihole0.local.theama.co
readonly node_a_target=pi@10.1.0.53
readonly node_b_host_alias=pihole00.local.theama.co
readonly node_b_target=pi@10.1.0.54
readonly revision=action17p-node-a-to-node-b-bootstrap
readonly parent_revision=action15-health-follow-redirects
readonly node_a_driver_sha256=10ac5148a7ae890dbd710faddc736f85be7ec9e10000f90e821cff0d2a99bed2
readonly node_b_inspector_sha256=de785ff8d66a30a5079a22880db9ecb07af87da11b9fd940feef683cd5edb234

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly node_a_driver="$script_dir/transfer-node-a-release-to-node-b-action17p.sh"
readonly node_b_inspector="$script_dir/inspect-node-b-incoming-release-action17p.sh"

checks_total=0
checks_passed=0
checks_failed=0
first_failure=none

record_result() {
    local result_label=$1
    local result_value=$2

    checks_total=$((checks_total + 1))
    if [[ "$result_value" == true ]]; then
        printf 'action_17p_check_%s=true\n' "$result_label"
        checks_passed=$((checks_passed + 1))
    else
        printf 'action_17p_check_%s=false\n' "$result_label" >&2
        checks_failed=$((checks_failed + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$result_label
        fi
    fi
}

record_command() {
    local command_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        record_result "$command_label" true
    else
        record_result "$command_label" false
    fi
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_content() {
    local content_path=$1
    local content_hash=$2

    [[ -f "$content_path" ]]
    [[ ! -L "$content_path" ]]
    [[ "$(file_hash "$content_path")" == "$content_hash" ]]
    bash -n "$content_path"
}

verify_contents() {
    verify_content "$node_a_driver" "$node_a_driver_sha256"
    verify_content "$node_b_inspector" "$node_b_inspector_sha256"
}

value_for() {
    local value_prefix=$1
    local value_transcript=$2
    local value_record

    [[ "$(grep -Ec "^${value_prefix}=" "$value_transcript")" -eq 1 ]] ||
        return 1
    value_record=$(grep -E "^${value_prefix}=" "$value_transcript")
    printf '%s\n' "${value_record#*=}"
}

require_one() {
    local required_record=$1
    local required_transcript=$2

    [[ "$(grep -Fxc "$required_record" "$required_transcript")" -eq 1 ]]
}

is_sha256() {
    [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

transcript_grammar_valid() {
    local grammar_prefix=$1
    local grammar_transcript=$2

    awk -v prefix="$grammar_prefix" '
        index($0, prefix "_") != 1 { invalid++ }
        $0 !~ /^[a-z0-9_]+=[A-Za-z0-9_.:-]+$/ { invalid++ }
        END { exit invalid ? 1 : 0 }
    ' "$grammar_transcript"
}

validate_phase() {
    local phase_label=$1
    local transcript_path=$2
    local transcript_prefix=$3
    local expected_phase=$4
    local check_count
    local unique_count
    local total_count
    local passed_count
    local failed_count
    local manifest_hash

    check_count=$(
        grep -Ec "^${transcript_prefix}_check_[a-z0-9_]+=true$" \
            "$transcript_path" || true
    )
    unique_count=$(
        sed -n \
            "s/^\\(${transcript_prefix}_check_[a-z0-9_]*\\)=true$/\\1/p" \
            "$transcript_path" |
            LC_ALL=C sort -u |
            wc -l
    )
    total_count=$(value_for "${transcript_prefix}_checks_total" \
        "$transcript_path") || total_count=invalid
    passed_count=$(value_for "${transcript_prefix}_checks_passed" \
        "$transcript_path") || passed_count=invalid
    failed_count=$(value_for "${transcript_prefix}_checks_failed" \
        "$transcript_path") || failed_count=invalid

    record_command "${phase_label}_check_count_positive" \
        test "$check_count" -gt 0
    record_command "${phase_label}_check_labels_unique" \
        test "$check_count" -eq "$unique_count"
    record_command "${phase_label}_total_numeric" \
        test "$total_count" -eq "$total_count"
    record_command "${phase_label}_passed_numeric" \
        test "$passed_count" -eq "$passed_count"
    record_command "${phase_label}_failed_numeric" \
        test "$failed_count" -eq "$failed_count"
    record_command "${phase_label}_count_matches_total" \
        test "$check_count" -eq "$total_count"
    record_command "${phase_label}_passed_matches_total" \
        test "$passed_count" -eq "$total_count"
    record_command "${phase_label}_failed_zero" \
        test "$failed_count" -eq 0
    record_command "${phase_label}_false_checks_absent" \
        test "$(grep -Ec \
            "^${transcript_prefix}_check_[a-z0-9_]+=false$" \
            "$transcript_path" || true)" -eq 0
    record_command "${phase_label}_transcript_grammar" \
        transcript_grammar_valid "$transcript_prefix" "$transcript_path"
    record_command "${phase_label}_first_failure_none" \
        require_one "${transcript_prefix}_first_failure=none" "$transcript_path"
    record_command "${phase_label}_phase_exact" \
        require_one "${transcript_prefix}_value_phase=$expected_phase" \
        "$transcript_path"
    record_command "${phase_label}_revision_exact" \
        require_one "${transcript_prefix}_value_revision=$revision" \
        "$transcript_path"
    record_command "${phase_label}_parent_exact" \
        require_one \
        "${transcript_prefix}_value_parent_revision=$parent_revision" \
        "$transcript_path"
    record_command "${phase_label}_service_mutations_false" \
        require_one "${transcript_prefix}_service_mutations=false" \
        "$transcript_path"
    record_command "${phase_label}_reconciliation_false" \
        require_one "${transcript_prefix}_reconciliation_executed=false" \
        "$transcript_path"
    record_command "${phase_label}_selection_changed_false" \
        require_one "${transcript_prefix}_caddy_selection_changed=false" \
        "$transcript_path"
    record_command "${phase_label}_acceptance_true" \
        require_one "${transcript_prefix}_acceptance=true" "$transcript_path"
    manifest_hash=$(value_for "${transcript_prefix}_value_manifest_sha256" \
        "$transcript_path") || manifest_hash=invalid
    if [[ "$expected_phase" == preflight ]]; then
        record_command "${phase_label}_manifest_unavailable" \
            test "$manifest_hash" = unavailable
    else
        record_command "${phase_label}_manifest_hash_format" \
            is_sha256 "$manifest_hash"
    fi
}

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$@"
}

run_remote() {
    local remote_host_alias=$1
    local remote_target=$2
    local remote_argument=$3
    local remote_payload=$4
    local remote_output=$5
    local remote_error=$6
    local remote_status_name=$7
    local remote_status=0

    ssh -T \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o "HostKeyAlias=$remote_host_alias" \
        -o StrictHostKeyChecking=yes \
        "$remote_target" \
        "cd / && sudo -n bash -s -- $remote_argument" \
        <"$remote_payload" >"$remote_output" 2>"$remote_error" ||
        remote_status=$?
    printf -v "$remote_status_name" '%s' "$remote_status"
}

write_phase_fixture() {
    local fixture_path=$1
    local fixture_prefix=$2
    local fixture_phase=$3
    local fixture_manifest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    printf '%s\n' \
        "${fixture_prefix}_check_fixture=true" \
        "${fixture_prefix}_value_phase=$fixture_phase" \
        "${fixture_prefix}_value_revision=$revision" \
        "${fixture_prefix}_value_parent_revision=$parent_revision" \
        "${fixture_prefix}_value_manifest_sha256=$fixture_manifest" \
        "${fixture_prefix}_checks_total=1" \
        "${fixture_prefix}_checks_passed=1" \
        "${fixture_prefix}_checks_failed=0" \
        "${fixture_prefix}_first_failure=none" \
        "${fixture_prefix}_service_mutations=false" \
        "${fixture_prefix}_reconciliation_executed=false" \
        "${fixture_prefix}_caddy_selection_changed=false" \
        "${fixture_prefix}_acceptance=true" >"$fixture_path"
}

reset_checks() {
    checks_total=0
    checks_passed=0
    checks_failed=0
    first_failure=none
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_contents
    "$node_a_driver" --self-test >/dev/null
    "$node_b_inspector" --self-test >/dev/null
    [[ "$revision" == action17p-node-a-to-node-b-bootstrap ]]
    [[ "$parent_revision" == action15-health-follow-redirects ]]
    printf 'action_17p_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action17p-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT

    write_phase_fixture \
        "$contract_dir/valid" action_17p_node_b preflight
    reset_checks
    validate_phase fixture "$contract_dir/valid" \
        action_17p_node_b preflight >/dev/null 2>&1
    [[ "$checks_failed" -eq 0 ]]

    cp -- "$contract_dir/valid" "$contract_dir/false-check"
    sed -i 's/_check_fixture=true/_check_fixture=false/' \
        "$contract_dir/false-check"
    reset_checks
    validate_phase fixture "$contract_dir/false-check" \
        action_17p_node_b preflight >/dev/null 2>&1
    [[ "$checks_failed" -gt 0 ]]

    cp -- "$contract_dir/valid" "$contract_dir/duplicate"
    printf 'action_17p_node_b_check_fixture=true\n' \
        >>"$contract_dir/duplicate"
    reset_checks
    validate_phase fixture "$contract_dir/duplicate" \
        action_17p_node_b preflight >/dev/null 2>&1
    [[ "$checks_failed" -gt 0 ]]

    cp -- "$contract_dir/valid" "$contract_dir/wrong-phase"
    sed -i 's/value_phase=preflight/value_phase=complete/' \
        "$contract_dir/wrong-phase"
    reset_checks
    validate_phase fixture "$contract_dir/wrong-phase" \
        action_17p_node_b preflight >/dev/null 2>&1
    [[ "$checks_failed" -gt 0 ]]

    cp -- "$contract_dir/valid" "$contract_dir/missing-acceptance"
    sed -i '/_acceptance=true/d' "$contract_dir/missing-acceptance"
    reset_checks
    validate_phase fixture "$contract_dir/missing-acceptance" \
        action_17p_node_b preflight >/dev/null 2>&1
    [[ "$checks_failed" -gt 0 ]]

    cp -- "$contract_dir/valid" "$contract_dir/raw-output"
    printf 'created directory node-a\n' >>"$contract_dir/raw-output"
    reset_checks
    validate_phase fixture "$contract_dir/raw-output" \
        action_17p_node_b preflight >/dev/null 2>&1
    [[ "$checks_failed" -gt 0 ]]

    printf 'action_17p_false_negative_valid_fixture_accepted=true\n'
    printf 'action_17p_false_positive_false_check_rejected=true\n'
    printf 'action_17p_false_positive_duplicate_check_rejected=true\n'
    printf 'action_17p_false_positive_wrong_phase_rejected=true\n'
    printf 'action_17p_false_positive_missing_acceptance_rejected=true\n'
    printf 'action_17p_false_positive_raw_output_rejected=true\n'
    printf 'action_17p_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_contents
record_command node_a_driver_regular test -f "$node_a_driver"
record_command node_a_driver_not_symlink test ! -L "$node_a_driver"
record_command node_b_inspector_regular test -f "$node_b_inspector"
record_command node_b_inspector_not_symlink test ! -L "$node_b_inspector"
record_command node_a_driver_owner \
    test "$(stat -c '%U:%G:%a' "$node_a_driver")" = aaron:aaron:755
record_command node_b_inspector_owner \
    test "$(stat -c '%U:%G:%a' "$node_b_inspector")" = aaron:aaron:755

work_dir=$(mktemp -d /tmp/caddy-action17p-runner.XXXXXX)
readonly work_dir
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

node_b_preflight_status=0
run_remote \
    "$node_b_host_alias" "$node_b_target" --preflight \
    "$node_b_inspector" "$work_dir/node-b-preflight.out" \
    "$work_dir/node-b-preflight.err" node_b_preflight_status
record_command node_b_preflight_ssh_status \
    test "$node_b_preflight_status" -eq 0
record_command node_b_preflight_stderr_empty \
    test ! -s "$work_dir/node-b-preflight.err"
if [[ "$node_b_preflight_status" -eq 0 ]]; then
    validate_phase node_b_preflight "$work_dir/node-b-preflight.out" \
        action_17p_node_b preflight
fi

node_a_payload_status=not_run
node_b_payload_status=not_run
node_a_complete_status=not_run
node_b_complete_status=not_run

if [[ "$checks_failed" -eq 0 ]]; then
    node_a_payload_status=0
    run_remote \
        "$node_a_host_alias" "$node_a_target" --payload \
        "$node_a_driver" "$work_dir/node-a-payload.out" \
        "$work_dir/node-a-payload.err" node_a_payload_status
    record_command node_a_payload_ssh_status \
        test "$node_a_payload_status" -eq 0
    record_command node_a_payload_stderr_empty \
        test ! -s "$work_dir/node-a-payload.err"
    if [[ "$node_a_payload_status" -eq 0 ]]; then
        validate_phase node_a_payload "$work_dir/node-a-payload.out" \
            action_17p_node_a payload
    fi
fi

if [[ "$checks_failed" -eq 0 ]]; then
    node_b_payload_status=0
    run_remote \
        "$node_b_host_alias" "$node_b_target" --payload \
        "$node_b_inspector" "$work_dir/node-b-payload.out" \
        "$work_dir/node-b-payload.err" node_b_payload_status
    record_command node_b_payload_ssh_status \
        test "$node_b_payload_status" -eq 0
    record_command node_b_payload_stderr_empty \
        test ! -s "$work_dir/node-b-payload.err"
    if [[ "$node_b_payload_status" -eq 0 ]]; then
        validate_phase node_b_payload "$work_dir/node-b-payload.out" \
            action_17p_node_b payload
    fi
fi

if [[ "$checks_failed" -eq 0 ]]; then
    node_a_manifest=$(value_for action_17p_node_a_value_manifest_sha256 \
        "$work_dir/node-a-payload.out") || node_a_manifest=invalid
    node_b_manifest=$(value_for action_17p_node_b_value_manifest_sha256 \
        "$work_dir/node-b-payload.out") || node_b_manifest=invalid
    record_command payload_manifest_hash_format \
        is_sha256 "$node_a_manifest"
    record_command payload_manifest_hash_equal \
        test "$node_a_manifest" = "$node_b_manifest"
fi

if [[ "$checks_failed" -eq 0 ]]; then
    node_a_complete_status=0
    run_remote \
        "$node_a_host_alias" "$node_a_target" --complete \
        "$node_a_driver" "$work_dir/node-a-complete.out" \
        "$work_dir/node-a-complete.err" node_a_complete_status
    record_command node_a_complete_ssh_status \
        test "$node_a_complete_status" -eq 0
    record_command node_a_complete_stderr_empty \
        test ! -s "$work_dir/node-a-complete.err"
    if [[ "$node_a_complete_status" -eq 0 ]]; then
        validate_phase node_a_complete "$work_dir/node-a-complete.out" \
            action_17p_node_a complete
    fi
fi

if [[ "$checks_failed" -eq 0 ]]; then
    node_b_complete_status=0
    run_remote \
        "$node_b_host_alias" "$node_b_target" --complete \
        "$node_b_inspector" "$work_dir/node-b-complete.out" \
        "$work_dir/node-b-complete.err" node_b_complete_status
    record_command node_b_complete_ssh_status \
        test "$node_b_complete_status" -eq 0
    record_command node_b_complete_stderr_empty \
        test ! -s "$work_dir/node-b-complete.err"
    if [[ "$node_b_complete_status" -eq 0 ]]; then
        validate_phase node_b_complete "$work_dir/node-b-complete.out" \
            action_17p_node_b complete
    fi
fi

if [[ "$checks_failed" -eq 0 ]]; then
    node_a_complete_manifest=$(
        value_for action_17p_node_a_value_manifest_sha256 \
            "$work_dir/node-a-complete.out"
    ) || node_a_complete_manifest=invalid
    node_b_complete_manifest=$(
        value_for action_17p_node_b_value_manifest_sha256 \
            "$work_dir/node-b-complete.out"
    ) || node_b_complete_manifest=invalid
    record_command completion_node_a_manifest_unchanged \
        test "$node_a_complete_manifest" = "$node_a_manifest"
    record_command completion_node_b_manifest_equal \
        test "$node_b_complete_manifest" = "$node_a_manifest"
fi

record_command transcripts_secret_free \
    validate_secret_free "$work_dir"/*.out "$work_dir"/*.err

printf 'action_17p_value_node_b_preflight_status=%s\n' \
    "$node_b_preflight_status"
printf 'action_17p_value_node_a_payload_status=%s\n' "$node_a_payload_status"
printf 'action_17p_value_node_b_payload_status=%s\n' "$node_b_payload_status"
printf 'action_17p_value_node_a_complete_status=%s\n' "$node_a_complete_status"
printf 'action_17p_value_node_b_complete_status=%s\n' "$node_b_complete_status"
printf 'action_17p_value_revision=%s\n' "$revision"
printf 'action_17p_value_parent_revision=%s\n' "$parent_revision"
printf 'action_17p_checks_total=%s\n' "$checks_total"
printf 'action_17p_checks_passed=%s\n' "$checks_passed"
printf 'action_17p_checks_failed=%s\n' "$checks_failed"
printf 'action_17p_first_failure=%s\n' "$first_failure"
printf 'action_17p_release_payload_transferred=%s\n' \
    "$([[ "$node_a_payload_status" == 0 ]] && printf true || printf false)"
printf 'action_17p_completion_marker_transferred=%s\n' \
    "$([[ "$node_a_complete_status" == 0 ]] && printf true || printf false)"
printf 'action_17p_synchronization_service_enabled=false\n'
printf 'action_17p_reconciliation_executed=false\n'
printf 'action_17p_caddy_reload_executed=false\n'
printf 'action_17p_failure_policy=incomplete_release_preserved_no_remote_delete\n'

if [[ "$checks_failed" -ne 0 ]]; then
    printf 'action_17p_acceptance=false\n' >&2
    exit 97
fi

printf 'action_17p_acceptance=true\n'
cleanup
trap - EXIT
if [[ -e "$work_dir" ]]; then
    printf 'action_17p_workstation_cleanup_complete=false\n' >&2
    exit 97
fi
printf 'action_17p_workstation_cleanup_complete=true\n'
