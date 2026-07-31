#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly runner="$caddy_root/scripts/run-node-a-to-node-b-source-bound-transport-acceptance-action17o-c.sh"
readonly action_17o_b_runner="$caddy_root/scripts/run-node-a-rsync-classification-refinement-action17o-b.sh"
readonly action_17o_b_refinement="$caddy_root/scripts/refine-node-a-rsync-output-classification-action17o-b.sh"
readonly action_17o_b_regression="$caddy_root/tests/action17o-b-classification-refinement-regression.sh"
readonly action_17o_runner="$caddy_root/scripts/run-node-a-to-node-b-source-bound-restricted-transport-action17o.sh"
readonly action_17o_node_a="$caddy_root/scripts/inspect-node-a-source-bound-restricted-transport-action17o.sh"
readonly action_17o_node_b="$caddy_root/scripts/inspect-node-b-source-bound-restricted-transport-action17o.sh"
readonly action_17o_regression="$caddy_root/tests/action17o-source-bound-restricted-transport-regression.sh"
readonly source_test_policy="$caddy_root/tests/run-source-test-in-context.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"
readonly runner_sha256=8ffe568063ddbc7aefd28e7ad076ea9b4dd91125c6b7f69123f68d657bdeeca9
readonly action_17o_b_runner_sha256=44cf6091609ba1c0a34bd5e09682885b91ccb15d8025e94cfe0fbd978627c993
readonly action_17o_b_refinement_sha256=df5452256ffc3d948f0bd7a6f51cfc1621b1bf7d54ea6211366b9cf45982f14a
readonly action_17o_b_regression_sha256=8d43b5342077b4429e54ed7a70676d3cd9a8d5df4b3f60d499e2ae847653270a
readonly action_17o_runner_sha256=053bd8aa483ed92736aa0bbcee2232b9bf6d17de5ea937e4aea8690fd4e95c48
readonly action_17o_node_a_sha256=f86c256a1e0af8a1e805a0329a6195e548651b28dfafbd160b98c714e5c61b7c
readonly action_17o_node_b_sha256=6d5e7ee4834a58fec35e45f296b83df98963848613483405a961eda4ec301896
readonly action_17o_regression_sha256=284c5e5007f8da42b69e6cb058301f6d279cf9cdda2dfb360ba8326e4fff8569
readonly fixture_stdout_sha256=9860f687cf32c9f2a700974bfabf3fe65d8b16f3446a6cd12f206853ed68860f
readonly fixture_line_1_sha256=22cfede9db41c0993dc68b423c8a7d7e635bf96a9b5fbdf898d52848c31c6365
readonly fixture_line_2_sha256=eba5068def7651e8e469a6d7a6de11b826dd450934ff4600489ef450ea494d49

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

assert_hash() {
    local hash_path=$1
    local hash_expected=$2

    [[ "$(file_hash "$hash_path")" == "$hash_expected" ]]
}

write_valid_fixture() {
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
        "action_17o_b_stdout_sha256=$fixture_stdout_sha256" \
        action_17o_b_line_1_bytes=25 \
        action_17o_b_line_1_fields=3 \
        "action_17o_b_line_1_sha256=$fixture_line_1_sha256" \
        action_17o_b_line_1_classification=created_expected_relative_directory \
        action_17o_b_line_2_bytes=15 \
        action_17o_b_line_2_fields=2 \
        "action_17o_b_line_2_sha256=$fixture_line_2_sha256" \
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

write_fake_dependency() {
    local fake_path=$1

    # shellcheck disable=SC2016
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'set -euo pipefail'
        printf '%s\n' 'printf "called\n" >>"$ACTION17O_C_CALL_LOG"'
        printf '%s\n' 'cat "$ACTION17O_C_FIXTURE"'
        printf '%s\n' 'if [[ -n "${ACTION17O_C_STDERR:-}" ]]; then'
        printf '%s\n' '    printf "%s\n" "$ACTION17O_C_STDERR" >&2'
        printf '%s\n' 'fi'
        printf '%s\n' 'exit "${ACTION17O_C_STATUS:-0}"'
    } >"$fake_path"
    chmod 0755 "$fake_path"
}

prepare_case() {
    local case_root=$1
    local staged_scripts="$case_root/Caddy/scripts"
    local staged_tests="$case_root/Caddy/tests"
    local staged_runner
    local fake_dependency
    local fake_hash

    install -d -m 0700 "$staged_scripts" "$staged_tests"
    cp -- \
        "$runner" \
        "$action_17o_b_refinement" \
        "$action_17o_runner" \
        "$action_17o_node_a" \
        "$action_17o_node_b" \
        "$staged_scripts/"
    cp -- \
        "$action_17o_b_regression" \
        "$action_17o_regression" \
        "$staged_tests/"
    staged_runner="$staged_scripts/${runner##*/}"
    fake_dependency="$staged_scripts/${action_17o_b_runner##*/}"
    write_fake_dependency "$fake_dependency"
    fake_hash=$(file_hash "$fake_dependency")
    sed -i \
        "s/$action_17o_b_runner_sha256/$fake_hash/" \
        "$staged_runner"
    chmod 0755 "$staged_runner"
    write_valid_fixture "$case_root/transcript"
    : >"$case_root/calls"
}

run_case() {
    local case_root=$1
    local expected_status=$2
    local expected_marker=$3
    local dependency_status=${4:-0}
    local dependency_stderr=${5:-}
    local staged_runner="$case_root/Caddy/scripts/${runner##*/}"
    local observed_status=0

    ACTION17O_C_CALL_LOG="$case_root/calls" \
        ACTION17O_C_FIXTURE="$case_root/transcript" \
        ACTION17O_C_STATUS="$dependency_status" \
        ACTION17O_C_STDERR="$dependency_stderr" \
        "$staged_runner" >"$case_root/runner.out" \
        2>"$case_root/runner.err" || observed_status=$?
    [[ "$observed_status" -eq "$expected_status" ]]
    grep -Fq "$expected_marker" \
        "$case_root/runner.out" "$case_root/runner.err"
    [[ "$(wc -l <"$case_root/calls")" -eq 1 ]]
}

run_production_path_regression() {
    local production_root
    local case_name
    local case_root

    production_root=$(mktemp -d /tmp/caddy-action17o-c-production.XXXXXX)
    trap 'rm -rf -- "$production_root"' RETURN
    for case_name in \
        success false-check short-check-set duplicate-check wrong-hash \
        raw-output dependency-stderr dependency-status; do
        case_root="$production_root/$case_name"
        install -d -m 0700 "$case_root"
        prepare_case "$case_root"
    done

    sed -i \
        's/action_17o_b_wrapper_check_fixture_93=true/action_17o_b_wrapper_check_fixture_93=false/' \
        "$production_root/false-check/transcript"
    sed -i \
        '/action_17o_b_wrapper_check_fixture_93=true/d' \
        "$production_root/short-check-set/transcript"
    printf 'action_17o_b_wrapper_check_fixture_01=true\n' \
        >>"$production_root/duplicate-check/transcript"
    sed -i \
        "s/$fixture_stdout_sha256/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/" \
        "$production_root/wrong-hash/transcript"
    printf 'created directory node-a\n' \
        >>"$production_root/raw-output/transcript"

    run_case \
        "$production_root/success" 0 \
        action_17o_c_transport_acceptance=true
    run_case \
        "$production_root/false-check" 97 \
        action_17o_c_check_inner_false_check_count_zero=false
    run_case \
        "$production_root/short-check-set" 97 \
        action_17o_c_check_inner_check_count_exact=false
    run_case \
        "$production_root/duplicate-check" 97 \
        action_17o_c_check_inner_check_labels_unique=false
    run_case \
        "$production_root/wrong-hash" 97 \
        action_17o_c_check_stdout_sha256_exact=false
    run_case \
        "$production_root/raw-output" 97 \
        action_17o_c_check_transcript_grammar=false
    run_case \
        "$production_root/dependency-stderr" 97 \
        action_17o_c_check_dependency_stderr_empty=false 0 diagnostic
    run_case \
        "$production_root/dependency-status" 97 \
        action_17o_c_check_dependency_status_zero=false 1

    printf 'action_17o_c_false_negative_valid_acceptance_accepted=true\n'
    printf 'action_17o_c_false_positive_false_check_rejected=true\n'
    printf 'action_17o_c_false_positive_short_check_set_rejected=true\n'
    printf 'action_17o_c_false_positive_duplicate_check_rejected=true\n'
    printf 'action_17o_c_false_positive_wrong_hash_rejected=true\n'
    printf 'action_17o_c_false_positive_raw_output_rejected=true\n'
    printf 'action_17o_c_false_positive_dependency_stderr_rejected=true\n'
    printf 'action_17o_c_false_positive_dependency_status_rejected=true\n'
    printf 'action_17o_c_dependency_invocation_exactly_once=true\n'
    printf 'action_17o_c_production_path_network_contact=false\n'
}

if [[ "${1:-}" != --production-test || $# -ne 1 ]]; then
    printf 'Usage: %s --production-test\n' "${0##*/}" >&2
    exit 2
fi

assert_hash "$runner" "$runner_sha256"
assert_hash "$action_17o_b_runner" "$action_17o_b_runner_sha256"
assert_hash "$action_17o_b_refinement" "$action_17o_b_refinement_sha256"
assert_hash "$action_17o_b_regression" "$action_17o_b_regression_sha256"
assert_hash "$action_17o_runner" "$action_17o_runner_sha256"
assert_hash "$action_17o_node_a" "$action_17o_node_a_sha256"
assert_hash "$action_17o_node_b" "$action_17o_node_b_sha256"
assert_hash "$action_17o_regression" "$action_17o_regression_sha256"

bash -n "$runner"
shellcheck "$runner"
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null
"$source_test_policy" --runner "$runner" >/dev/null
"$collision_checker" "$runner" "$0" >/dev/null
"$action_17o_b_regression" --production-test >/dev/null

if grep -Fq 'ACTION17O_C_' "$runner"; then
    printf 'Production Action 17o-c runner contains a fixture bypass.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$runner"; then
    printf 'Action 17o-c contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '(^|[[:space:]])rsync([[:space:]]|$)' \
    "$runner"; then
    printf 'Action 17o-c duplicates the pinned transport implementation.\n' >&2
    exit 1
fi

if [[ "$(id -un)" == aaron ]]; then
    run_production_path_regression
else
    [[ "${CADDY_VALIDATION_CONTAINER:-0}" == 1 ]]
    printf 'action_17o_c_production_path_host_authoritative=true\n'
    printf 'action_17o_c_container_fixture_bypass_absent=true\n'
fi

printf 'action_17o_c_source_bound_transport_acceptance_regression_complete=true\n'
