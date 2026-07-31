#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly node_a_refinement_sha256=df5452256ffc3d948f0bd7a6f51cfc1621b1bf7d54ea6211366b9cf45982f14a
readonly node_b_inspector_sha256=6d5e7ee4834a58fec35e45f296b83df98963848613483405a961eda4ec301896
readonly action_17o_a_diagnostic_sha256=aabb66b50a14459f75b409e666ddf776b48eba9a1457810d74448315e3e4e06c
readonly action_17o_a_runner_sha256=edb264caaa9f5e3397224413637d8adb2439349f30dc173b05b0da45c7bf5e32
readonly action_17o_a_regression_sha256=1b0b9f19efab4f6538f11128ccf435875e71e1516d62c843ee8024baf271d296
readonly historical_runner_sha256=053bd8aa483ed92736aa0bbcee2232b9bf6d17de5ea937e4aea8690fd4e95c48
readonly historical_node_a_sha256=f86c256a1e0af8a1e805a0329a6195e548651b28dfafbd160b98c714e5c61b7c
readonly historical_regression_sha256=284c5e5007f8da42b69e6cb058301f6d279cf9cdda2dfb360ba8326e4fff8569
readonly node_a_host_alias=pihole0.local.theama.co
readonly node_a_target=pi@10.1.0.53
readonly node_b_host_alias=pihole00.local.theama.co
readonly node_b_target=pi@10.1.0.54
readonly expected_stdout_sha256=9860f687cf32c9f2a700974bfabf3fe65d8b16f3446a6cd12f206853ed68860f
readonly expected_line_1_sha256=22cfede9db41c0993dc68b423c8a7d7e635bf96a9b5fbdf898d52848c31c6365
readonly expected_line_2_sha256=eba5068def7651e8e469a6d7a6de11b826dd450934ff4600489ef450ea494d49

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly node_a_refinement="$script_dir/refine-node-a-rsync-output-classification-action17o-b.sh"
readonly node_b_inspector="$script_dir/inspect-node-b-source-bound-restricted-transport-action17o.sh"
readonly action_17o_a_diagnostic="$script_dir/diagnose-node-a-rsync-dry-run-output-action17o-a.sh"
readonly action_17o_a_runner="$script_dir/run-node-a-rsync-dry-run-output-diagnostic-action17o-a.sh"
readonly action_17o_a_regression="$caddy_root/tests/action17o-a-rsync-output-classification-regression.sh"
readonly historical_runner="$script_dir/run-node-a-to-node-b-source-bound-restricted-transport-action17o.sh"
readonly historical_node_a="$script_dir/inspect-node-a-source-bound-restricted-transport-action17o.sh"
readonly historical_regression="$caddy_root/tests/action17o-source-bound-restricted-transport-regression.sh"

wrapper_checks_total=0
wrapper_checks_passed=0
wrapper_checks_failed=0
wrapper_first_failure=none

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
    verify_content "$node_a_refinement" "$node_a_refinement_sha256"
    verify_content "$node_b_inspector" "$node_b_inspector_sha256"
    verify_content "$action_17o_a_diagnostic" "$action_17o_a_diagnostic_sha256"
    verify_content "$action_17o_a_runner" "$action_17o_a_runner_sha256"
    verify_content "$action_17o_a_regression" "$action_17o_a_regression_sha256"
    verify_content "$historical_runner" "$historical_runner_sha256"
    verify_content "$historical_node_a" "$historical_node_a_sha256"
    verify_content "$historical_regression" "$historical_regression_sha256"
}

verify_sources() {
    verify_source "$node_a_refinement" "$node_a_refinement_sha256"
    verify_source "$node_b_inspector" "$node_b_inspector_sha256"
    verify_source "$action_17o_a_diagnostic" "$action_17o_a_diagnostic_sha256"
    verify_source "$action_17o_a_runner" "$action_17o_a_runner_sha256"
    verify_source "$action_17o_a_regression" "$action_17o_a_regression_sha256"
    verify_source "$historical_runner" "$historical_runner_sha256"
    verify_source "$historical_node_a" "$historical_node_a_sha256"
    verify_source "$historical_regression" "$historical_regression_sha256"
}

record_wrapper_result() {
    local wrapper_label=$1
    local wrapper_value=$2

    wrapper_checks_total=$((wrapper_checks_total + 1))
    if [[ "$wrapper_value" == true ]]; then
        printf 'action_17o_b_wrapper_check_%s=true\n' "$wrapper_label"
        wrapper_checks_passed=$((wrapper_checks_passed + 1))
    else
        printf 'action_17o_b_wrapper_check_%s=false\n' "$wrapper_label" >&2
        wrapper_checks_failed=$((wrapper_checks_failed + 1))
        if [[ "$wrapper_first_failure" == none ]]; then
            wrapper_first_failure=$wrapper_label
        fi
    fi
}

record_wrapper_command() {
    local wrapper_command_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        record_wrapper_result "$wrapper_command_label" true
    else
        record_wrapper_result "$wrapper_command_label" false
    fi
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

safe_value() {
    local safe_prefix=$1
    local safe_transcript=$2
    local safe_result

    if safe_result=$(value_for "$safe_prefix" "$safe_transcript"); then
        printf '%s\n' "$safe_result"
    else
        printf 'unavailable\n'
    fi
}

validate_check_set() {
    local validation_scope=$1
    local check_prefix=$2
    local count_prefix=$3
    local check_transcript=$4
    local expected_check_count=$5
    local check_count
    local unique_count
    local false_count
    local total_count
    local passed_count
    local failed_count

    check_count=$(
        grep -Ec "^${check_prefix}[a-z0-9_]+=(true|false)$" \
            "$check_transcript" || true
    )
    unique_count=$(
        sed -n \
            "s/^\\(${check_prefix}[a-z0-9_]*\\)=\\(true\\|false\\)$/\\1/p" \
            "$check_transcript" |
            LC_ALL=C sort -u |
            wc -l
    )
    false_count=$(
        grep -Ec "^${check_prefix}[a-z0-9_]+=false$" \
            "$check_transcript" || true
    )
    total_count=$(safe_value "${count_prefix}_checks_total" "$check_transcript")
    passed_count=$(safe_value "${count_prefix}_checks_passed" "$check_transcript")
    failed_count=$(safe_value "${count_prefix}_checks_failed" "$check_transcript")

    record_wrapper_command "${validation_scope}_check_count_numeric" \
        test "$check_count" -eq "$check_count"
    record_wrapper_command "${validation_scope}_unique_count_numeric" \
        test "$unique_count" -eq "$unique_count"
    record_wrapper_command "${validation_scope}_total_count_unique" \
        test "$(grep -Ec "^${count_prefix}_checks_total=" \
            "$check_transcript")" -eq 1
    record_wrapper_command "${validation_scope}_passed_count_unique" \
        test "$(grep -Ec "^${count_prefix}_checks_passed=" \
            "$check_transcript")" -eq 1
    record_wrapper_command "${validation_scope}_failed_count_unique" \
        test "$(grep -Ec "^${count_prefix}_checks_failed=" \
            "$check_transcript")" -eq 1
    record_wrapper_command "${validation_scope}_total_count_numeric" \
        test "$total_count" -eq "$total_count"
    record_wrapper_command "${validation_scope}_passed_count_numeric" \
        test "$passed_count" -eq "$passed_count"
    record_wrapper_command "${validation_scope}_failed_count_numeric" \
        test "$failed_count" -eq "$failed_count"
    record_wrapper_command "${validation_scope}_labels_unique" \
        test "$check_count" -eq "$unique_count"
    record_wrapper_command "${validation_scope}_count_reconciled" \
        test "$check_count" -eq "$total_count"
    record_wrapper_command "${validation_scope}_expected_check_count" \
        test "$check_count" -eq "$expected_check_count"
    record_wrapper_command "${validation_scope}_passed_reconciled" \
        test "$passed_count" -eq "$total_count"
    record_wrapper_command "${validation_scope}_failed_zero" \
        test "$failed_count" -eq 0
    record_wrapper_command "${validation_scope}_false_records_zero" \
        test "$false_count" -eq 0
}

validate_node_b() {
    local validation_scope=$1
    local node_b_transcript=$2
    local state_hash

    validate_check_set \
        "$validation_scope" action_17o_node_b_check_ action_17o_node_b \
        "$node_b_transcript" 33
    record_wrapper_command "${validation_scope}_transcript_grammar" \
        awk '
            /^action_17o_node_b_check_[a-z0-9_]+=(true|false)$/ { next }
            /^action_17o_node_b_value_state_sha256=[0-9a-f]+$/ { next }
            /^action_17o_node_b_checks_(total|passed|failed)=[0-9]+$/ { next }
            /^action_17o_node_b_first_failure=[a-z0-9_]+$/ { next }
            /^action_17o_node_b_persistent_mutations=(true|false)$/ { next }
            /^action_17o_node_b_synchronization_executed=(true|false)$/ { next }
            /^action_17o_node_b_acceptance=(true|false)$/ { next }
            { invalid++ }
            END { exit invalid ? 1 : 0 }
        ' "$node_b_transcript"
    record_wrapper_command "${validation_scope}_first_failure_unique" \
        test "$(grep -Fxc action_17o_node_b_first_failure=none \
            "$node_b_transcript")" -eq 1
    record_wrapper_command "${validation_scope}_persistent_mutations_false" \
        test "$(grep -Fxc action_17o_node_b_persistent_mutations=false \
            "$node_b_transcript")" -eq 1
    record_wrapper_command "${validation_scope}_synchronization_false" \
        test "$(grep -Fxc action_17o_node_b_synchronization_executed=false \
            "$node_b_transcript")" -eq 1
    record_wrapper_command "${validation_scope}_acceptance_true" \
        test "$(grep -Fxc action_17o_node_b_acceptance=true \
            "$node_b_transcript")" -eq 1
    record_wrapper_command "${validation_scope}_state_hash_unique" \
        test "$(grep -Ec '^action_17o_node_b_value_state_sha256=' \
            "$node_b_transcript")" -eq 1
    state_hash=$(safe_value \
        action_17o_node_b_value_state_sha256 "$node_b_transcript")
    record_wrapper_command "${validation_scope}_state_hash_format" \
        grep -Eq '^[0-9a-f]{64}$' <<<"$state_hash"
}

validate_node_a() {
    local node_a_transcript=$1
    local before_hash
    local after_hash

    validate_check_set \
        node_a action_17o_b_check_ action_17o_b "$node_a_transcript" 45
    record_wrapper_command node_a_transcript_grammar \
        awk '
            /^action_17o_b_check_[a-z0-9_]+=(true|false)$/ { next }
            /^action_17o_b_value_[a-z0-9_]+=[A-Za-z0-9_:.-]+$/ { next }
            /^action_17o_b_raw_stdout_emitted=(true|false)$/ { next }
            /^action_17o_b_checks_(total|passed|failed)=[0-9]+$/ { next }
            /^action_17o_b_first_failure=[a-z0-9_]+$/ { next }
            /^action_17o_b_(release_payload_transferred|synchronization_executed|service_mutations|persistent_mutations)=(true|false)$/ { next }
            /^action_17o_b_node_a_collection_complete=(true|false)$/ { next }
            { invalid++ }
            END { exit invalid ? 1 : 0 }
        ' "$node_a_transcript"
    for exact_record in \
        action_17o_b_first_failure=none \
        action_17o_b_value_rsync_attempted=true \
        action_17o_b_value_rsync_status=0 \
        action_17o_b_value_stdout_bytes=40 \
        action_17o_b_value_stdout_lines=2 \
        "action_17o_b_value_stdout_sha256=$expected_stdout_sha256" \
        action_17o_b_value_line_1_bytes=25 \
        action_17o_b_value_line_1_fields=3 \
        "action_17o_b_value_line_1_sha256=$expected_line_1_sha256" \
        action_17o_b_value_line_1_classification=created_expected_relative_directory \
        action_17o_b_value_line_2_bytes=15 \
        action_17o_b_value_line_2_fields=2 \
        "action_17o_b_value_line_2_sha256=$expected_line_2_sha256" \
        action_17o_b_value_line_2_classification=itemized_current_directory \
        action_17o_b_value_sequence_classification=created_expected_relative_directory:itemized_current_directory \
        action_17o_b_raw_stdout_emitted=false \
        action_17o_b_release_payload_transferred=false \
        action_17o_b_synchronization_executed=false \
        action_17o_b_service_mutations=false \
        action_17o_b_persistent_mutations=false \
        action_17o_b_node_a_collection_complete=true; do
        record_label=${exact_record%%=*}
        record_label=${record_label#action_17o_b_}
        record_wrapper_command "node_a_${record_label}_exact" \
            test "$(grep -Fxc "$exact_record" "$node_a_transcript")" -eq 1
    done

    record_wrapper_command node_a_before_state_hash_unique \
        test "$(grep -Ec '^action_17o_b_value_before_state_sha256=' \
            "$node_a_transcript")" -eq 1
    record_wrapper_command node_a_after_state_hash_unique \
        test "$(grep -Ec '^action_17o_b_value_after_state_sha256=' \
            "$node_a_transcript")" -eq 1
    before_hash=$(safe_value \
        action_17o_b_value_before_state_sha256 "$node_a_transcript")
    after_hash=$(safe_value \
        action_17o_b_value_after_state_sha256 "$node_a_transcript")
    record_wrapper_command node_a_before_state_hash_format \
        grep -Eq '^[0-9a-f]{64}$' <<<"$before_hash"
    record_wrapper_command node_a_after_state_hash_format \
        grep -Eq '^[0-9a-f]{64}$' <<<"$after_hash"
    record_wrapper_command node_a_state_unchanged \
        test "$before_hash" = "$after_hash"
}

validate_secret_free() {
    local secret_scope=$1
    local secret_path=$2

    if grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$secret_path"; then
        record_wrapper_result "${secret_scope}_secret_free" false
    else
        record_wrapper_result "${secret_scope}_secret_free" true
    fi
}

write_node_a_fixture() {
    local fixture_path=$1
    local state_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    local fixture_index

    : >"$fixture_path"
    for ((fixture_index = 1; fixture_index <= 45; fixture_index++)); do
        printf 'action_17o_b_check_fixture_%02d=true\n' \
            "$fixture_index" >>"$fixture_path"
    done
    printf '%s\n' \
        "action_17o_b_value_before_state_sha256=$state_hash" \
        action_17o_b_value_rsync_attempted=true \
        action_17o_b_value_rsync_status=0 \
        action_17o_b_value_stdout_bytes=40 \
        action_17o_b_value_stdout_lines=2 \
        "action_17o_b_value_stdout_sha256=$expected_stdout_sha256" \
        action_17o_b_value_line_1_bytes=25 \
        action_17o_b_value_line_1_fields=3 \
        "action_17o_b_value_line_1_sha256=$expected_line_1_sha256" \
        action_17o_b_value_line_1_classification=created_expected_relative_directory \
        action_17o_b_value_line_2_bytes=15 \
        action_17o_b_value_line_2_fields=2 \
        "action_17o_b_value_line_2_sha256=$expected_line_2_sha256" \
        action_17o_b_value_line_2_classification=itemized_current_directory \
        action_17o_b_value_sequence_classification=created_expected_relative_directory:itemized_current_directory \
        action_17o_b_raw_stdout_emitted=false \
        "action_17o_b_value_after_state_sha256=$state_hash" \
        action_17o_b_checks_total=45 \
        action_17o_b_checks_passed=45 \
        action_17o_b_checks_failed=0 \
        action_17o_b_first_failure=none \
        action_17o_b_release_payload_transferred=false \
        action_17o_b_synchronization_executed=false \
        action_17o_b_service_mutations=false \
        action_17o_b_persistent_mutations=false \
        action_17o_b_node_a_collection_complete=true >>"$fixture_path"
}

write_node_b_fixture() {
    local fixture_path=$1
    local state_hash=$2
    local fixture_index

    : >"$fixture_path"
    for ((fixture_index = 1; fixture_index <= 33; fixture_index++)); do
        printf 'action_17o_node_b_check_fixture_%02d=true\n' \
            "$fixture_index" >>"$fixture_path"
    done
    printf '%s\n' \
        "action_17o_node_b_value_state_sha256=$state_hash" \
        action_17o_node_b_checks_total=33 \
        action_17o_node_b_checks_passed=33 \
        action_17o_node_b_checks_failed=0 \
        action_17o_node_b_first_failure=none \
        action_17o_node_b_persistent_mutations=false \
        action_17o_node_b_synchronization_executed=false \
        action_17o_node_b_acceptance=true >>"$fixture_path"
}

run_remote() {
    local remote_host_alias=$1
    local remote_target=$2
    local remote_command=$3
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
        "$remote_target" "$remote_command" \
        <"$remote_payload" >"$remote_output" 2>"$remote_error" ||
        remote_status=$?
    printf -v "$remote_status_name" '%s' "$remote_status"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_contents
    "$node_a_refinement" --self-test >/dev/null
    "$node_a_refinement" --classifier-test >/dev/null
    "$node_b_inspector" --self-test >/dev/null
    printf 'action_17o_b_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_sources
    printf 'action_17o_b_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action17o-b-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    write_node_a_fixture "$contract_dir/node-a"
    write_node_b_fixture \
        "$contract_dir/node-b-before" \
        cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
    write_node_b_fixture \
        "$contract_dir/node-b-after" \
        cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
    validate_node_b before "$contract_dir/node-b-before"
    validate_node_a "$contract_dir/node-a"
    validate_node_b after "$contract_dir/node-b-after"
    validate_secret_free node_a "$contract_dir/node-a"
    if [[ "$wrapper_checks_failed" -ne 0 ]]; then
        printf 'Action 17o-b contract fixture was rejected.\n' >&2
        exit 1
    fi
    printf 'action_17o_b_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_sources
work_dir=$(mktemp -d /tmp/caddy-action17o-b-runner.XXXXXX)
readonly work_dir
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

node_b_before_status=0
node_a_status=0
node_b_after_status=0
run_remote \
    "$node_b_host_alias" "$node_b_target" \
    'sudo -n /bin/bash -s --' "$node_b_inspector" \
    "$work_dir/node-b-before.out" "$work_dir/node-b-before.err" \
    node_b_before_status
run_remote \
    "$node_a_host_alias" "$node_a_target" \
    "sudo -n /bin/bash -c 'cd / && exec /usr/sbin/runuser -u caddy-sync -- /bin/bash -s --'" \
    "$node_a_refinement" \
    "$work_dir/node-a.out" "$work_dir/node-a.err" node_a_status
run_remote \
    "$node_b_host_alias" "$node_b_target" \
    'sudo -n /bin/bash -s --' "$node_b_inspector" \
    "$work_dir/node-b-after.out" "$work_dir/node-b-after.err" \
    node_b_after_status

record_wrapper_command node_b_before_ssh_status_zero \
    test "$node_b_before_status" -eq 0
record_wrapper_command node_a_ssh_status_zero test "$node_a_status" -eq 0
record_wrapper_command node_b_after_ssh_status_zero \
    test "$node_b_after_status" -eq 0
record_wrapper_command node_b_before_stderr_empty \
    test ! -s "$work_dir/node-b-before.err"
record_wrapper_command node_a_stderr_empty test ! -s "$work_dir/node-a.err"
record_wrapper_command node_b_after_stderr_empty \
    test ! -s "$work_dir/node-b-after.err"

validate_node_b before "$work_dir/node-b-before.out"
validate_node_a "$work_dir/node-a.out"
validate_node_b after "$work_dir/node-b-after.out"
validate_secret_free node_b_before "$work_dir/node-b-before.out"
validate_secret_free node_a "$work_dir/node-a.out"
validate_secret_free node_b_after "$work_dir/node-b-after.out"

before_digest=$(safe_value \
    action_17o_node_b_value_state_sha256 "$work_dir/node-b-before.out")
after_digest=$(safe_value \
    action_17o_node_b_value_state_sha256 "$work_dir/node-b-after.out")
node_a_before_digest=$(safe_value \
    action_17o_b_value_before_state_sha256 "$work_dir/node-a.out")
node_a_after_digest=$(safe_value \
    action_17o_b_value_after_state_sha256 "$work_dir/node-a.out")
record_wrapper_command node_b_state_unchanged \
    test "$before_digest" = "$after_digest"

printf 'action_17o_b_node_b_before_ssh_status=%s\n' "$node_b_before_status"
printf 'action_17o_b_node_a_ssh_status=%s\n' "$node_a_status"
printf 'action_17o_b_node_b_after_ssh_status=%s\n' "$node_b_after_status"
printf 'action_17o_b_stdout_bytes=%s\n' \
    "$(safe_value action_17o_b_value_stdout_bytes "$work_dir/node-a.out")"
printf 'action_17o_b_stdout_lines=%s\n' \
    "$(safe_value action_17o_b_value_stdout_lines "$work_dir/node-a.out")"
printf 'action_17o_b_stdout_sha256=%s\n' \
    "$(safe_value action_17o_b_value_stdout_sha256 "$work_dir/node-a.out")"
printf 'action_17o_b_line_1_bytes=%s\n' \
    "$(safe_value action_17o_b_value_line_1_bytes "$work_dir/node-a.out")"
printf 'action_17o_b_line_1_fields=%s\n' \
    "$(safe_value action_17o_b_value_line_1_fields "$work_dir/node-a.out")"
printf 'action_17o_b_line_1_sha256=%s\n' \
    "$(safe_value action_17o_b_value_line_1_sha256 "$work_dir/node-a.out")"
printf 'action_17o_b_line_1_classification=%s\n' \
    "$(safe_value action_17o_b_value_line_1_classification \
        "$work_dir/node-a.out")"
printf 'action_17o_b_line_2_bytes=%s\n' \
    "$(safe_value action_17o_b_value_line_2_bytes "$work_dir/node-a.out")"
printf 'action_17o_b_line_2_fields=%s\n' \
    "$(safe_value action_17o_b_value_line_2_fields "$work_dir/node-a.out")"
printf 'action_17o_b_line_2_sha256=%s\n' \
    "$(safe_value action_17o_b_value_line_2_sha256 "$work_dir/node-a.out")"
printf 'action_17o_b_line_2_classification=%s\n' \
    "$(safe_value action_17o_b_value_line_2_classification \
        "$work_dir/node-a.out")"
printf 'action_17o_b_sequence_classification=%s\n' \
    "$(safe_value action_17o_b_value_sequence_classification \
        "$work_dir/node-a.out")"
printf 'action_17o_b_raw_stdout_emitted=false\n'
printf 'action_17o_b_node_a_state_unchanged=%s\n' \
    "$([[ "$node_a_before_digest" == "$node_a_after_digest" ]] && printf true || printf false)"
printf 'action_17o_b_node_b_state_unchanged=%s\n' \
    "$([[ "$before_digest" == "$after_digest" ]] && printf true || printf false)"
printf 'action_17o_b_release_payload_transferred=false\n'
printf 'action_17o_b_synchronization_executed=false\n'
printf 'action_17o_b_service_mutations=false\n'
printf 'action_17o_b_persistent_mutations=false\n'
printf 'action_17o_b_wrapper_checks_total=%s\n' "$wrapper_checks_total"
printf 'action_17o_b_wrapper_checks_passed=%s\n' "$wrapper_checks_passed"
printf 'action_17o_b_wrapper_checks_failed=%s\n' "$wrapper_checks_failed"
printf 'action_17o_b_wrapper_first_failure=%s\n' "$wrapper_first_failure"

if [[ "$wrapper_checks_failed" -ne 0 ]]; then
    printf 'action_17o_b_runner_acceptance=false\n' >&2
    exit 97
fi

printf 'action_17o_b_runner_acceptance=true\n'
cleanup
trap - EXIT
if [[ -e "$work_dir" ]]; then
    printf 'action_17o_b_workstation_cleanup_complete=false\n' >&2
    exit 97
fi
printf 'action_17o_b_workstation_cleanup_complete=true\n'
