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
readonly diagnostic="$caddy_root/scripts/diagnose-node-a-rsync-dry-run-output-action17o-a.sh"
readonly runner="$caddy_root/scripts/run-node-a-rsync-dry-run-output-diagnostic-action17o-a.sh"
readonly node_b_inspector="$caddy_root/scripts/inspect-node-b-source-bound-restricted-transport-action17o.sh"
readonly historical_runner="$caddy_root/scripts/run-node-a-to-node-b-source-bound-restricted-transport-action17o.sh"
readonly historical_node_a="$caddy_root/scripts/inspect-node-a-source-bound-restricted-transport-action17o.sh"
readonly historical_regression="$caddy_root/tests/action17o-source-bound-restricted-transport-regression.sh"
readonly source_test_policy="$caddy_root/tests/run-source-test-in-context.sh"
readonly diagnostic_sha256=aabb66b50a14459f75b409e666ddf776b48eba9a1457810d74448315e3e4e06c
readonly runner_sha256=edb264caaa9f5e3397224413637d8adb2439349f30dc173b05b0da45c7bf5e32
readonly node_b_inspector_sha256=6d5e7ee4834a58fec35e45f296b83df98963848613483405a961eda4ec301896
readonly historical_runner_sha256=053bd8aa483ed92736aa0bbcee2232b9bf6d17de5ea937e4aea8690fd4e95c48
readonly historical_node_a_sha256=f86c256a1e0af8a1e805a0329a6195e548651b28dfafbd160b98c714e5c61b7c
readonly historical_regression_sha256=284c5e5007f8da42b69e6cb058301f6d279cf9cdda2dfb360ba8326e4fff8569

real_stdout_bytes=
real_stdout_lines=
real_stdout_sha256=
real_stdout_classification=

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
    local fixture_bytes=$2
    local fixture_lines=$3
    local fixture_hash=$4
    local fixture_classification=$5
    local state_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    printf '%s\n' \
        action_17o_a_check_fixture=true \
        "action_17o_a_value_before_state_sha256=$state_hash" \
        action_17o_a_value_rsync_attempted=true \
        action_17o_a_value_rsync_status=0 \
        "action_17o_a_value_stdout_bytes=$fixture_bytes" \
        "action_17o_a_value_stdout_lines=$fixture_lines" \
        "action_17o_a_value_stdout_sha256=$fixture_hash" \
        "action_17o_a_value_stdout_classification=$fixture_classification" \
        action_17o_a_raw_stdout_emitted=false \
        "action_17o_a_value_after_state_sha256=$state_hash" \
        action_17o_a_checks_total=1 \
        action_17o_a_checks_passed=1 \
        action_17o_a_checks_failed=0 \
        action_17o_a_first_failure=none \
        action_17o_a_release_payload_transferred=false \
        action_17o_a_synchronization_executed=false \
        action_17o_a_service_mutations=false \
        action_17o_a_persistent_mutations=false \
        action_17o_a_node_a_collection_complete=true >"$fixture_path"
}

write_node_b_fixture() {
    local fixture_path=$1
    local state_hash=$2

    printf '%s\n' \
        action_17o_node_b_check_fixture=true \
        "action_17o_node_b_value_state_sha256=$state_hash" \
        action_17o_node_b_checks_total=1 \
        action_17o_node_b_checks_passed=1 \
        action_17o_node_b_checks_failed=0 \
        action_17o_node_b_first_failure=none \
        action_17o_node_b_persistent_mutations=false \
        action_17o_node_b_synchronization_executed=false \
        action_17o_node_b_acceptance=true >"$fixture_path"
}

write_fake_ssh() {
    local fake_path=$1

    # shellcheck disable=SC2016
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'set -euo pipefail'
        printf '%s\n' 'printf "%s\n" "$*" >>"$ACTION17O_A_FAKE_SSH_LOG"'
        printf '%s\n' 'cat >/dev/null'
        printf '%s\n' 'case " $* " in'
        printf '%s\n' '    *" pi@10.1.0.53 "*)'
        printf '%s\n' '        cat "$ACTION17O_A_NODE_A_FIXTURE"'
        printf '%s\n' '        ;;'
        printf '%s\n' '    *" pi@10.1.0.54 "*)'
        printf '%s\n' \
            '        count=$(grep -Fc " pi@10.1.0.54 " "$ACTION17O_A_FAKE_SSH_LOG")'
        printf '%s\n' '        if [[ "$count" -eq 1 ]]; then'
        printf '%s\n' '            cat "$ACTION17O_A_NODE_B_BEFORE_FIXTURE"'
        printf '%s\n' '        else'
        printf '%s\n' '            cat "$ACTION17O_A_NODE_B_AFTER_FIXTURE"'
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
        "$historical_runner" \
        "$historical_node_a" \
        "$production_scripts/"
    cp -- "$historical_regression" "$production_tests/"
    sed \
        "s|^PATH=/usr/bin:/bin$|PATH=$production_bin:/usr/bin:/bin|" \
        "$runner" \
        >"$production_scripts/run-node-a-rsync-dry-run-output-diagnostic-action17o-a.sh"
    chmod 0755 \
        "$production_scripts/run-node-a-rsync-dry-run-output-diagnostic-action17o-a.sh"
    write_fake_ssh "$production_bin/ssh"
}

run_production_case() {
    local case_root=$1
    local expected_status=$2
    local expected_marker=$3
    local production_runner="$case_root/Caddy/scripts/run-node-a-rsync-dry-run-output-diagnostic-action17o-a.sh"
    local production_status=0

    : >"$case_root/ssh.log"
    ACTION17O_A_FAKE_SSH_LOG="$case_root/ssh.log" \
        ACTION17O_A_NODE_A_FIXTURE="$case_root/node-a.fixture" \
        ACTION17O_A_NODE_B_BEFORE_FIXTURE="$case_root/node-b-before.fixture" \
        ACTION17O_A_NODE_B_AFTER_FIXTURE="$case_root/node-b-after.fixture" \
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

run_real_rsync_classifier_regression() {
    local classifier_root=$1
    local classifier_source="$classifier_root/classifier.sh"
    local rsync_output="$classifier_root/rsync.out"
    local classified_stdout_bounded
    local classified_stdout_bytes
    local classified_stdout_classification
    local classified_stdout_lines
    local classified_stdout_path_scope_safe
    local classified_stdout_printable
    local classified_stdout_secret_free
    local classified_stdout_sha256
    local expected_stdout_bytes
    local expected_stdout_lines
    local expected_stdout_sha256

    install -d -m 0700 "$classifier_root/source" "$classifier_root/target"
    touch -d '@1000000000' "$classifier_root/target"
    touch -d '@1000000100' "$classifier_root/source"
    rsync --archive --dry-run --itemize-changes \
        "$classifier_root/source/" "$classifier_root/target/" >"$rsync_output"
    [[ -s "$rsync_output" ]]
    expected_stdout_bytes=$(wc -c <"$rsync_output")
    expected_stdout_lines=$(awk 'END { print NR }' "$rsync_output")
    expected_stdout_sha256=$(file_hash "$rsync_output")

    sed -n \
        '/^classify_rsync_stdout()/,/^}$/p' \
        "$diagnostic" >"$classifier_source"
    # shellcheck disable=SC1090
    source "$classifier_source"
    classify_rsync_stdout "$rsync_output"

    [[ "$classified_stdout_bytes" -eq "$expected_stdout_bytes" ]]
    [[ "$classified_stdout_lines" -eq "$expected_stdout_lines" ]]
    [[ "$classified_stdout_sha256" == "$expected_stdout_sha256" ]]
    [[ "$classified_stdout_printable" == true ]]
    [[ "$classified_stdout_secret_free" == true ]]
    [[ "$classified_stdout_path_scope_safe" == true ]]
    [[ "$classified_stdout_bounded" == true ]]
    [[ "$classified_stdout_classification" == itemized_current_directory_only ]]

    real_stdout_bytes=$classified_stdout_bytes
    real_stdout_lines=$classified_stdout_lines
    real_stdout_sha256=$classified_stdout_sha256
    real_stdout_classification=$classified_stdout_classification

    printf 'action_17o_a_real_rsync_stdout_bytes=%s\n' \
        "$real_stdout_bytes"
    printf 'action_17o_a_real_rsync_stdout_lines=%s\n' \
        "$real_stdout_lines"
    printf 'action_17o_a_real_rsync_stdout_sha256=%s\n' \
        "$real_stdout_sha256"
    printf 'action_17o_a_real_rsync_stdout_classification=%s\n' \
        "$real_stdout_classification"
}

run_production_path_regression() {
    local production_root
    local case_name
    local case_root
    local stable_b_hash=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
    local changed_b_hash=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd

    production_root=$(mktemp -d /tmp/caddy-action17o-a-production.XXXXXX)
    trap 'rm -rf -- "$production_root"' RETURN
    run_real_rsync_classifier_regression "$production_root/classifier"

    for case_name in success duplicate unsafe changed-node-b; do
        case_root="$production_root/$case_name"
        install -d -m 0700 "$case_root"
        prepare_production_stage "$case_root"
        write_node_a_fixture \
            "$case_root/node-a.fixture" \
            "$real_stdout_bytes" \
            "$real_stdout_lines" \
            "$real_stdout_sha256" \
            "$real_stdout_classification"
        write_node_b_fixture "$case_root/node-b-before.fixture" "$stable_b_hash"
        write_node_b_fixture "$case_root/node-b-after.fixture" "$stable_b_hash"
    done

    printf 'action_17o_a_value_stdout_sha256=%s\n' \
        "$real_stdout_sha256" \
        >>"$production_root/duplicate/node-a.fixture"
    sed -i \
        's/itemized_current_directory_only/unsafe/' \
        "$production_root/unsafe/node-a.fixture"
    write_node_b_fixture \
        "$production_root/changed-node-b/node-b-after.fixture" \
        "$changed_b_hash"

    run_production_case \
        "$production_root/success" 0 action_17o_a_runner_acceptance=true
    run_production_case \
        "$production_root/duplicate" 97 \
        action_17o_a_node_a_transcript_valid=false
    run_production_case \
        "$production_root/unsafe" 97 \
        action_17o_a_node_a_transcript_valid=false
    run_production_case \
        "$production_root/changed-node-b" 97 \
        action_17o_a_node_b_state_unchanged=false

    printf 'action_17o_a_false_negative_real_rsync_output_accepted=true\n'
    printf 'action_17o_a_false_negative_unchanged_dual_node_continuity_accepted=true\n'
    printf 'action_17o_a_false_positive_duplicate_metadata_rejected=true\n'
    printf 'action_17o_a_false_positive_unsafe_classification_rejected=true\n'
    printf 'action_17o_a_false_positive_node_b_state_change_rejected=true\n'
    printf 'action_17o_a_production_path_network_contact=false\n'
}

if [[ "${1:-}" != --production-test || $# -ne 1 ]]; then
    printf 'Usage: %s --production-test\n' "${0##*/}" >&2
    exit 2
fi

assert_hash "$diagnostic" "$diagnostic_sha256"
assert_hash "$runner" "$runner_sha256"
assert_hash "$node_b_inspector" "$node_b_inspector_sha256"
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

grep -Fq '# ACTION17O_A_CLASSIFIER_BEGIN' "$diagnostic"
grep -Fq '# ACTION17O_A_CLASSIFIER_END' "$diagnostic"
grep -Fq 'action_17o_a_raw_stdout_emitted=false' "$diagnostic" "$runner"
grep -Fq 'action_17o_a_value_stdout_bytes=' "$diagnostic"
grep -Fq 'action_17o_a_value_stdout_lines=' "$diagnostic"
grep -Fq 'action_17o_a_value_stdout_sha256=' "$diagnostic"
grep -Fq 'action_17o_a_value_stdout_classification=' "$diagnostic"
if grep -Fq 'ACTION17O_A_' "$runner"; then
    printf 'Production Action 17o-a runner contains a fixture bypass.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$diagnostic" "$runner"; then
    printf 'Action 17o-a contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*(install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$diagnostic"; then
    printf 'Action 17o-a diagnostic contains a persistent mutation.\n' >&2
    exit 1
fi

if [[ "$(id -un)" == aaron ]]; then
    run_production_path_regression
else
    [[ "${CADDY_VALIDATION_CONTAINER:-0}" == 1 ]]
    printf 'action_17o_a_production_path_host_authoritative=true\n'
    printf 'action_17o_a_container_fixture_bypass_absent=true\n'
fi

printf 'action_17o_a_rsync_output_classification_regression_complete=true\n'
