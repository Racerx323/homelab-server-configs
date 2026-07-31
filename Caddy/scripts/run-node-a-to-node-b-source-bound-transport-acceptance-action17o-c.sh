#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly action_17o_b_runner_sha256=44cf6091609ba1c0a34bd5e09682885b91ccb15d8025e94cfe0fbd978627c993
readonly action_17o_b_refinement_sha256=df5452256ffc3d948f0bd7a6f51cfc1621b1bf7d54ea6211366b9cf45982f14a
readonly action_17o_b_regression_sha256=8d43b5342077b4429e54ed7a70676d3cd9a8d5df4b3f60d499e2ae847653270a
readonly action_17o_runner_sha256=053bd8aa483ed92736aa0bbcee2232b9bf6d17de5ea937e4aea8690fd4e95c48
readonly action_17o_node_a_sha256=f86c256a1e0af8a1e805a0329a6195e548651b28dfafbd160b98c714e5c61b7c
readonly action_17o_node_b_sha256=6d5e7ee4834a58fec35e45f296b83df98963848613483405a961eda4ec301896
readonly action_17o_regression_sha256=284c5e5007f8da42b69e6cb058301f6d279cf9cdda2dfb360ba8326e4fff8569
readonly expected_stdout_sha256=9860f687cf32c9f2a700974bfabf3fe65d8b16f3446a6cd12f206853ed68860f
readonly expected_line_1_sha256=22cfede9db41c0993dc68b423c8a7d7e635bf96a9b5fbdf898d52848c31c6365
readonly expected_line_2_sha256=eba5068def7651e8e469a6d7a6de11b826dd450934ff4600489ef450ea494d49

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly action_17o_b_runner="$script_dir/run-node-a-rsync-classification-refinement-action17o-b.sh"
readonly action_17o_b_refinement="$script_dir/refine-node-a-rsync-output-classification-action17o-b.sh"
readonly action_17o_b_regression="$caddy_root/tests/action17o-b-classification-refinement-regression.sh"
readonly action_17o_runner="$script_dir/run-node-a-to-node-b-source-bound-restricted-transport-action17o.sh"
readonly action_17o_node_a="$script_dir/inspect-node-a-source-bound-restricted-transport-action17o.sh"
readonly action_17o_node_b="$script_dir/inspect-node-b-source-bound-restricted-transport-action17o.sh"
readonly action_17o_regression="$caddy_root/tests/action17o-source-bound-restricted-transport-regression.sh"

acceptance_checks_total=0
acceptance_checks_passed=0
acceptance_checks_failed=0
acceptance_first_failure=none

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

verify_source() {
    local source_path=$1
    local source_hash=$2

    verify_content "$source_path" "$source_hash"
    [[ "$(stat -c '%U:%G:%a' "$source_path")" == aaron:aaron:755 ]]
}

verify_contents() {
    verify_content "$action_17o_b_runner" "$action_17o_b_runner_sha256"
    verify_content "$action_17o_b_refinement" "$action_17o_b_refinement_sha256"
    verify_content "$action_17o_b_regression" "$action_17o_b_regression_sha256"
    verify_content "$action_17o_runner" "$action_17o_runner_sha256"
    verify_content "$action_17o_node_a" "$action_17o_node_a_sha256"
    verify_content "$action_17o_node_b" "$action_17o_node_b_sha256"
    verify_content "$action_17o_regression" "$action_17o_regression_sha256"
}

verify_sources() {
    verify_source "$action_17o_b_runner" "$action_17o_b_runner_sha256"
    verify_source "$action_17o_b_refinement" "$action_17o_b_refinement_sha256"
    verify_source "$action_17o_b_regression" "$action_17o_b_regression_sha256"
    verify_source "$action_17o_runner" "$action_17o_runner_sha256"
    verify_source "$action_17o_node_a" "$action_17o_node_a_sha256"
    verify_source "$action_17o_node_b" "$action_17o_node_b_sha256"
    verify_source "$action_17o_regression" "$action_17o_regression_sha256"
}

record_acceptance_result() {
    local acceptance_label=$1
    local acceptance_value=$2

    acceptance_checks_total=$((acceptance_checks_total + 1))
    if [[ "$acceptance_value" == true ]]; then
        printf 'action_17o_c_check_%s=true\n' "$acceptance_label"
        acceptance_checks_passed=$((acceptance_checks_passed + 1))
    else
        printf 'action_17o_c_check_%s=false\n' "$acceptance_label" >&2
        acceptance_checks_failed=$((acceptance_checks_failed + 1))
        if [[ "$acceptance_first_failure" == none ]]; then
            acceptance_first_failure=$acceptance_label
        fi
    fi
}

record_acceptance_command() {
    local acceptance_command_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        record_acceptance_result "$acceptance_command_label" true
    else
        record_acceptance_result "$acceptance_command_label" false
    fi
}

exact_record_count() {
    local record_text=$1
    local transcript_path=$2

    grep -Fxc "$record_text" "$transcript_path" || true
}

validate_transcript() {
    local transcript_path=$1
    local dependency_status=$2
    local dependency_error_path=$3
    local check_count
    local check_unique_count
    local check_false_count
    local transcript_line_count
    local exact_record
    local record_label

    check_count=$(
        grep -Ec '^action_17o_b_wrapper_check_[a-z0-9_]+=true$' \
            "$transcript_path" || true
    )
    check_unique_count=$(
        sed -n \
            's/^\(action_17o_b_wrapper_check_[a-z0-9_]*\)=true$/\1/p' \
            "$transcript_path" |
            LC_ALL=C sort -u |
            wc -l
    )
    check_false_count=$(
        grep -Ec '^action_17o_b_wrapper_check_[a-z0-9_]+=false$' \
            "$transcript_path" || true
    )
    transcript_line_count=$(wc -l <"$transcript_path")

    record_acceptance_command dependency_status_zero \
        test "$dependency_status" -eq 0
    record_acceptance_command dependency_stderr_empty \
        test ! -s "$dependency_error_path"
    record_acceptance_command transcript_line_count_numeric \
        test "$transcript_line_count" -eq "$transcript_line_count"
    record_acceptance_command transcript_line_count_exact \
        test "$transcript_line_count" -eq 121
    record_acceptance_command inner_check_count_numeric \
        test "$check_count" -eq "$check_count"
    record_acceptance_command inner_check_count_exact \
        test "$check_count" -eq 93
    record_acceptance_command inner_check_unique_count_numeric \
        test "$check_unique_count" -eq "$check_unique_count"
    record_acceptance_command inner_check_labels_unique \
        test "$check_unique_count" -eq "$check_count"
    record_acceptance_command inner_false_check_count_numeric \
        test "$check_false_count" -eq "$check_false_count"
    record_acceptance_command inner_false_check_count_zero \
        test "$check_false_count" -eq 0
    record_acceptance_command transcript_grammar \
        awk '
            /^action_17o_b_wrapper_check_[a-z0-9_]+=true$/ { next }
            /^action_17o_b_(node_b_before|node_a|node_b_after)_ssh_status=0$/ { next }
            /^action_17o_b_stdout_(bytes|lines)=[0-9]+$/ { next }
            /^action_17o_b_stdout_sha256=[0-9a-f]+$/ { next }
            /^action_17o_b_line_[12]_(bytes|fields)=[0-9]+$/ { next }
            /^action_17o_b_line_[12]_sha256=[0-9a-f]+$/ { next }
            /^action_17o_b_line_[12]_classification=[a-z0-9_]+$/ { next }
            /^action_17o_b_sequence_classification=[a-z0-9_:]+$/ { next }
            /^action_17o_b_(raw_stdout_emitted|node_a_state_unchanged|node_b_state_unchanged|release_payload_transferred|synchronization_executed|service_mutations|persistent_mutations)=(true|false)$/ { next }
            /^action_17o_b_wrapper_checks_(total|passed|failed)=[0-9]+$/ { next }
            /^action_17o_b_wrapper_first_failure=[a-z0-9_]+$/ { next }
            /^action_17o_b_runner_acceptance=(true|false)$/ { next }
            /^action_17o_b_workstation_cleanup_complete=(true|false)$/ { next }
            { invalid++ }
            END { exit invalid ? 1 : 0 }
        ' "$transcript_path"

    for exact_record in \
        action_17o_b_node_b_before_ssh_status=0 \
        action_17o_b_node_a_ssh_status=0 \
        action_17o_b_node_b_after_ssh_status=0 \
        action_17o_b_stdout_bytes=40 \
        action_17o_b_stdout_lines=2 \
        "action_17o_b_stdout_sha256=$expected_stdout_sha256" \
        action_17o_b_line_1_bytes=25 \
        action_17o_b_line_1_fields=3 \
        "action_17o_b_line_1_sha256=$expected_line_1_sha256" \
        action_17o_b_line_1_classification=created_expected_relative_directory \
        action_17o_b_line_2_bytes=15 \
        action_17o_b_line_2_fields=2 \
        "action_17o_b_line_2_sha256=$expected_line_2_sha256" \
        action_17o_b_line_2_classification=itemized_current_directory \
        action_17o_b_sequence_classification=created_expected_relative_directory:itemized_current_directory \
        action_17o_b_raw_stdout_emitted=false \
        action_17o_b_node_a_state_unchanged=true \
        action_17o_b_node_b_state_unchanged=true \
        action_17o_b_release_payload_transferred=false \
        action_17o_b_synchronization_executed=false \
        action_17o_b_service_mutations=false \
        action_17o_b_persistent_mutations=false \
        action_17o_b_wrapper_checks_total=93 \
        action_17o_b_wrapper_checks_passed=93 \
        action_17o_b_wrapper_checks_failed=0 \
        action_17o_b_wrapper_first_failure=none \
        action_17o_b_runner_acceptance=true \
        action_17o_b_workstation_cleanup_complete=true; do
        record_label=${exact_record%%=*}
        record_label=${record_label#action_17o_b_}
        record_acceptance_command "${record_label}_exact" \
            test "$(exact_record_count "$exact_record" "$transcript_path")" -eq 1
    done
}

write_contract_fixture() {
    local fixture_path=$1
    local fixture_index

    : >"$fixture_path"
    for ((fixture_index = 1; fixture_index <= 93; fixture_index++)); do
        printf 'action_17o_b_wrapper_check_fixture_%02d=true\n' \
            "$fixture_index" >>"$fixture_path"
    done
    printf '%s\n' \
        action_17o_b_node_b_before_ssh_status=0 \
        action_17o_b_node_a_ssh_status=0 \
        action_17o_b_node_b_after_ssh_status=0 \
        action_17o_b_stdout_bytes=40 \
        action_17o_b_stdout_lines=2 \
        "action_17o_b_stdout_sha256=$expected_stdout_sha256" \
        action_17o_b_line_1_bytes=25 \
        action_17o_b_line_1_fields=3 \
        "action_17o_b_line_1_sha256=$expected_line_1_sha256" \
        action_17o_b_line_1_classification=created_expected_relative_directory \
        action_17o_b_line_2_bytes=15 \
        action_17o_b_line_2_fields=2 \
        "action_17o_b_line_2_sha256=$expected_line_2_sha256" \
        action_17o_b_line_2_classification=itemized_current_directory \
        action_17o_b_sequence_classification=created_expected_relative_directory:itemized_current_directory \
        action_17o_b_raw_stdout_emitted=false \
        action_17o_b_node_a_state_unchanged=true \
        action_17o_b_node_b_state_unchanged=true \
        action_17o_b_release_payload_transferred=false \
        action_17o_b_synchronization_executed=false \
        action_17o_b_service_mutations=false \
        action_17o_b_persistent_mutations=false \
        action_17o_b_wrapper_checks_total=93 \
        action_17o_b_wrapper_checks_passed=93 \
        action_17o_b_wrapper_checks_failed=0 \
        action_17o_b_wrapper_first_failure=none \
        action_17o_b_runner_acceptance=true \
        action_17o_b_workstation_cleanup_complete=true >>"$fixture_path"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_contents
    "$action_17o_b_runner" --self-test >/dev/null
    printf 'action_17o_c_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_sources
    printf 'action_17o_c_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action17o-c-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    write_contract_fixture "$contract_dir/transcript"
    : >"$contract_dir/stderr"
    validate_transcript "$contract_dir/transcript" 0 "$contract_dir/stderr"
    if [[ "$acceptance_checks_failed" -ne 0 ]]; then
        printf 'Action 17o-c contract fixture was rejected.\n' >&2
        exit 1
    fi
    printf 'action_17o_c_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_contents
work_dir=$(mktemp -d /tmp/caddy-action17o-c-runner.XXXXXX)
readonly work_dir
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

dependency_status=0
"$action_17o_b_runner" >"$work_dir/action17o-b.out" \
    2>"$work_dir/action17o-b.err" || dependency_status=$?
validate_transcript \
    "$work_dir/action17o-b.out" "$dependency_status" \
    "$work_dir/action17o-b.err"

printf 'action_17o_c_dependency_status=%s\n' "$dependency_status"
printf 'action_17o_c_checks_total=%s\n' "$acceptance_checks_total"
printf 'action_17o_c_checks_passed=%s\n' "$acceptance_checks_passed"
printf 'action_17o_c_checks_failed=%s\n' "$acceptance_checks_failed"
printf 'action_17o_c_first_failure=%s\n' "$acceptance_first_failure"
printf 'action_17o_c_release_payload_transferred=false\n'
printf 'action_17o_c_synchronization_executed=false\n'
printf 'action_17o_c_service_mutations=false\n'
printf 'action_17o_c_persistent_mutations=false\n'

if [[ "$acceptance_checks_failed" -ne 0 ]]; then
    printf 'action_17o_c_transport_acceptance=false\n' >&2
    exit 97
fi

printf 'action_17o_c_transport_acceptance=true\n'
cleanup
trap - EXIT
if [[ -e "$work_dir" ]]; then
    printf 'action_17o_c_workstation_cleanup_complete=false\n' >&2
    exit 97
fi
printf 'action_17o_c_workstation_cleanup_complete=true\n'
