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
readonly diagnostic="$caddy_root/scripts/refine-node-a-rsync-output-classification-action17o-b.sh"
readonly runner="$caddy_root/scripts/run-node-a-rsync-classification-refinement-action17o-b.sh"
readonly node_b_inspector="$caddy_root/scripts/inspect-node-b-source-bound-restricted-transport-action17o.sh"
readonly action_17o_a_diagnostic="$caddy_root/scripts/diagnose-node-a-rsync-dry-run-output-action17o-a.sh"
readonly action_17o_a_runner="$caddy_root/scripts/run-node-a-rsync-dry-run-output-diagnostic-action17o-a.sh"
readonly action_17o_a_regression="$caddy_root/tests/action17o-a-rsync-output-classification-regression.sh"
readonly historical_runner="$caddy_root/scripts/run-node-a-to-node-b-source-bound-restricted-transport-action17o.sh"
readonly historical_node_a="$caddy_root/scripts/inspect-node-a-source-bound-restricted-transport-action17o.sh"
readonly historical_regression="$caddy_root/tests/action17o-source-bound-restricted-transport-regression.sh"
readonly source_test_policy="$caddy_root/tests/run-source-test-in-context.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"
readonly diagnostic_sha256=df5452256ffc3d948f0bd7a6f51cfc1621b1bf7d54ea6211366b9cf45982f14a
readonly runner_sha256=44cf6091609ba1c0a34bd5e09682885b91ccb15d8025e94cfe0fbd978627c993
readonly node_b_inspector_sha256=6d5e7ee4834a58fec35e45f296b83df98963848613483405a961eda4ec301896
readonly action_17o_a_diagnostic_sha256=aabb66b50a14459f75b409e666ddf776b48eba9a1457810d74448315e3e4e06c
readonly action_17o_a_runner_sha256=edb264caaa9f5e3397224413637d8adb2439349f30dc173b05b0da45c7bf5e32
readonly action_17o_a_regression_sha256=1b0b9f19efab4f6538f11128ccf435875e71e1516d62c843ee8024baf271d296
readonly historical_runner_sha256=053bd8aa483ed92736aa0bbcee2232b9bf6d17de5ea937e4aea8690fd4e95c48
readonly historical_node_a_sha256=f86c256a1e0af8a1e805a0329a6195e548651b28dfafbd160b98c714e5c61b7c
readonly historical_regression_sha256=284c5e5007f8da42b69e6cb058301f6d279cf9cdda2dfb360ba8326e4fff8569
readonly expected_stdout_sha256=9860f687cf32c9f2a700974bfabf3fe65d8b16f3446a6cd12f206853ed68860f
readonly expected_line_1_sha256=22cfede9db41c0993dc68b423c8a7d7e635bf96a9b5fbdf898d52848c31c6365
readonly expected_line_2_sha256=eba5068def7651e8e469a6d7a6de11b826dd450934ff4600489ef450ea494d49

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

assert_hash() {
    local hash_path=$1
    local hash_expected=$2

    [[ "$(file_hash "$hash_path")" == "$hash_expected" ]]
}

write_node_a_fixture() {
    local fixture_path=$1
    local fixture_index
    local state_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

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

write_fake_ssh() {
    local fake_path=$1

    # shellcheck disable=SC2016
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'set -euo pipefail'
        printf '%s\n' 'printf "%s\n" "$*" >>"$ACTION17O_B_FAKE_SSH_LOG"'
        printf '%s\n' 'cat >/dev/null'
        printf '%s\n' 'case " $* " in'
        printf '%s\n' '    *" pi@10.1.0.53 "*)'
        printf '%s\n' '        cat "$ACTION17O_B_NODE_A_FIXTURE"'
        printf '%s\n' '        ;;'
        printf '%s\n' '    *" pi@10.1.0.54 "*)'
        printf '%s\n' \
            '        count=$(grep -Fc " pi@10.1.0.54 " "$ACTION17O_B_FAKE_SSH_LOG")'
        printf '%s\n' '        if [[ "$count" -eq 1 ]]; then'
        printf '%s\n' '            cat "$ACTION17O_B_NODE_B_BEFORE_FIXTURE"'
        printf '%s\n' '        else'
        printf '%s\n' '            cat "$ACTION17O_B_NODE_B_AFTER_FIXTURE"'
        printf '%s\n' '        fi'
        printf '%s\n' '        ;;'
        printf '%s\n' '    *)'
        printf '%s\n' '        exit 92'
        printf '%s\n' '        ;;'
        printf '%s\n' 'esac'
    } >"$fake_path"
    chmod 0755 "$fake_path"
}

prepare_production_stage() {
    local production_stage=$1
    local production_scripts="$production_stage/Caddy/scripts"
    local production_tests="$production_stage/Caddy/tests"
    local production_bin="$production_stage/bin"

    install -d -m 0700 \
        "$production_scripts" "$production_tests" "$production_bin"
    cp -- \
        "$diagnostic" \
        "$node_b_inspector" \
        "$action_17o_a_diagnostic" \
        "$action_17o_a_runner" \
        "$historical_runner" \
        "$historical_node_a" \
        "$production_scripts/"
    cp -- \
        "$action_17o_a_regression" \
        "$historical_regression" \
        "$production_tests/"
    sed \
        "s|^PATH=/usr/bin:/bin$|PATH=$production_bin:/usr/bin:/bin|" \
        "$runner" \
        >"$production_scripts/run-node-a-rsync-classification-refinement-action17o-b.sh"
    chmod 0755 \
        "$production_scripts/run-node-a-rsync-classification-refinement-action17o-b.sh"
    write_fake_ssh "$production_bin/ssh"
}

run_production_case() {
    local case_root=$1
    local expected_status=$2
    local expected_marker=$3
    local production_runner="$case_root/Caddy/scripts/run-node-a-rsync-classification-refinement-action17o-b.sh"
    local production_status=0

    : >"$case_root/ssh.log"
    ACTION17O_B_FAKE_SSH_LOG="$case_root/ssh.log" \
        ACTION17O_B_NODE_A_FIXTURE="$case_root/node-a.fixture" \
        ACTION17O_B_NODE_B_BEFORE_FIXTURE="$case_root/node-b-before.fixture" \
        ACTION17O_B_NODE_B_AFTER_FIXTURE="$case_root/node-b-after.fixture" \
        "$production_runner" \
        >"$case_root/runner.out" 2>"$case_root/runner.err" ||
        production_status=$?
    [[ "$production_status" -eq "$expected_status" ]]
    grep -Fq "$expected_marker" \
        "$case_root/runner.out" "$case_root/runner.err"
    [[ "$(wc -l <"$case_root/ssh.log")" -eq 3 ]]
    [[ "$(grep -Fc ' pi@10.1.0.53 ' "$case_root/ssh.log")" -eq 1 ]]
    [[ "$(grep -Fc ' pi@10.1.0.54 ' "$case_root/ssh.log")" -eq 2 ]]
}

run_real_classifier_regression() {
    local classifier_root=$1
    local classifier_source="$classifier_root/classifier.sh"
    local rsync_output="$classifier_root/out"
    local line_1="$classifier_root/line-1"
    local line_2="$classifier_root/line-2"
    local refined_line_bytes
    local refined_line_classification
    local refined_line_fields
    local refined_line_printable
    local refined_line_relative_scope
    local refined_line_secret_free
    local refined_line_sha256

    install -d -m 0700 "$classifier_root/source"
    (
        cd "$classifier_root" || exit 1
        rsync --archive --dry-run --itemize-changes source/ node-a/ >out
    )
    [[ "$(wc -c <"$rsync_output")" -eq 40 ]]
    [[ "$(awk 'END { print NR }' "$rsync_output")" -eq 2 ]]
    [[ "$(file_hash "$rsync_output")" == "$expected_stdout_sha256" ]]
    sed -n '1p' "$rsync_output" >"$line_1"
    sed -n '2p' "$rsync_output" >"$line_2"

    sed -n \
        '/^classify_refined_line()/,/^}$/p' \
        "$diagnostic" >"$classifier_source"
    # shellcheck disable=SC1090
    source "$classifier_source"

    classify_refined_line "$line_1"
    [[ "$refined_line_bytes" -eq 25 ]]
    [[ "$refined_line_fields" -eq 3 ]]
    [[ "$refined_line_sha256" == "$expected_line_1_sha256" ]]
    [[ "$refined_line_printable" == true ]]
    [[ "$refined_line_secret_free" == true ]]
    [[ "$refined_line_relative_scope" == true ]]
    [[ "$refined_line_classification" == created_expected_relative_directory ]]

    classify_refined_line "$line_2"
    [[ "$refined_line_bytes" -eq 15 ]]
    [[ "$refined_line_fields" -eq 2 ]]
    [[ "$refined_line_sha256" == "$expected_line_2_sha256" ]]
    [[ "$refined_line_printable" == true ]]
    [[ "$refined_line_secret_free" == true ]]
    [[ "$refined_line_relative_scope" == true ]]
    [[ "$refined_line_classification" == itemized_current_directory ]]

    printf 'action_17o_b_real_stdout_identity_match=true\n'
    printf 'action_17o_b_real_line_1_refined=true\n'
    printf 'action_17o_b_real_line_2_refined=true\n'
}

run_production_path_regression() {
    local production_root
    local case_name
    local case_root
    local stable_b_hash=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
    local changed_b_hash=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd

    production_root=$(mktemp -d /tmp/caddy-action17o-b-production.XXXXXX)
    trap 'rm -rf -- "$production_root"' RETURN
    for case_name in \
        success wrong-class duplicate-hash raw-output short-check-set \
        changed-node-b; do
        case_root="$production_root/$case_name"
        install -d -m 0700 "$case_root"
        prepare_production_stage "$case_root"
        write_node_a_fixture "$case_root/node-a.fixture"
        write_node_b_fixture "$case_root/node-b-before.fixture" "$stable_b_hash"
        write_node_b_fixture "$case_root/node-b-after.fixture" "$stable_b_hash"
    done

    sed -i \
        's/created_expected_relative_directory/bounded_safe_other/' \
        "$production_root/wrong-class/node-a.fixture"
    printf 'action_17o_b_value_line_1_sha256=%s\n' \
        "$expected_line_1_sha256" \
        >>"$production_root/duplicate-hash/node-a.fixture"
    printf 'created directory node-a\n' \
        >>"$production_root/raw-output/node-a.fixture"
    sed -i \
        '/action_17o_b_check_fixture_45=true/d' \
        "$production_root/short-check-set/node-a.fixture"
    write_node_b_fixture \
        "$production_root/changed-node-b/node-b-after.fixture" \
        "$changed_b_hash"

    run_production_case \
        "$production_root/success" 0 action_17o_b_runner_acceptance=true
    run_production_case \
        "$production_root/wrong-class" 97 \
        action_17o_b_wrapper_check_node_a_value_line_1_classification_exact=false
    run_production_case \
        "$production_root/duplicate-hash" 97 \
        action_17o_b_wrapper_check_node_a_value_line_1_sha256_exact=false
    run_production_case \
        "$production_root/raw-output" 97 \
        action_17o_b_wrapper_check_node_a_transcript_grammar=false
    run_production_case \
        "$production_root/short-check-set" 97 \
        action_17o_b_wrapper_check_node_a_expected_check_count=false
    run_production_case \
        "$production_root/changed-node-b" 97 \
        action_17o_b_wrapper_check_node_b_state_unchanged=false

    printf 'action_17o_b_false_negative_real_classification_accepted=true\n'
    printf 'action_17o_b_false_negative_stable_continuity_accepted=true\n'
    printf 'action_17o_b_false_positive_wrong_class_rejected=true\n'
    printf 'action_17o_b_false_positive_duplicate_hash_rejected=true\n'
    printf 'action_17o_b_false_positive_raw_output_rejected=true\n'
    printf 'action_17o_b_false_positive_short_fixture_rejected=true\n'
    printf 'action_17o_b_false_positive_state_drift_rejected=true\n'
    printf 'action_17o_b_production_path_network_contact=false\n'
}

if [[ "${1:-}" != --production-test || $# -ne 1 ]]; then
    printf 'Usage: %s --production-test\n' "${0##*/}" >&2
    exit 2
fi

assert_hash "$diagnostic" "$diagnostic_sha256"
assert_hash "$runner" "$runner_sha256"
assert_hash "$node_b_inspector" "$node_b_inspector_sha256"
assert_hash "$action_17o_a_diagnostic" "$action_17o_a_diagnostic_sha256"
assert_hash "$action_17o_a_runner" "$action_17o_a_runner_sha256"
assert_hash "$action_17o_a_regression" "$action_17o_a_regression_sha256"
assert_hash "$historical_runner" "$historical_runner_sha256"
assert_hash "$historical_node_a" "$historical_node_a_sha256"
assert_hash "$historical_regression" "$historical_regression_sha256"

bash -n "$diagnostic" "$runner"
shellcheck "$diagnostic" "$runner"
"$diagnostic" --self-test >/dev/null
"$diagnostic" --classifier-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null
"$source_test_policy" --runner "$runner" >/dev/null
"$collision_checker" "$diagnostic" "$runner" >/dev/null
real_classifier_root=$(mktemp -d /tmp/caddy-action17o-b-real.XXXXXX)
run_real_classifier_regression "$real_classifier_root"
rm -rf -- "$real_classifier_root"

grep -Fq '# ACTION17O_B_CLASSIFIER_BEGIN' "$diagnostic"
grep -Fq '# ACTION17O_B_CLASSIFIER_END' "$diagnostic"
grep -Fq 'action_17o_b_raw_stdout_emitted=false' "$diagnostic" "$runner"
if grep -Fq 'ACTION17O_B_' "$runner"; then
    printf 'Production Action 17o-b runner contains a fixture bypass.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$diagnostic" "$runner"; then
    printf 'Action 17o-b contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*(install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$diagnostic"; then
    printf 'Action 17o-b diagnostic contains a persistent mutation.\n' >&2
    exit 1
fi

if [[ "$(id -un)" == aaron ]]; then
    run_production_path_regression
else
    [[ "${CADDY_VALIDATION_CONTAINER:-0}" == 1 ]]
    printf 'action_17o_b_production_path_host_authoritative=true\n'
    printf 'action_17o_b_container_fixture_bypass_absent=true\n'
fi

printf 'action_17o_b_classification_refinement_regression_complete=true\n'
