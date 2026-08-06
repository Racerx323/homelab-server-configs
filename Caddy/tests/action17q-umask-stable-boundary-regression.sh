#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly boundary=$script_directory/action17q-umask-stable-boundary.sh

check_regression() {
    local regression_check_label=$1

    shift
    if "$@"; then
        printf 'action_17q_umask_boundary_regression_check_%s=true\n' \
            "$regression_check_label"
        return 0
    fi
    printf 'action_17q_umask_boundary_regression_check_%s=false\n' \
        "$regression_check_label" >&2
    return 1
}

test_root=$(mktemp -d /tmp/caddy-action17q-umask-boundary-regression.XXXXXX)
readonly test_root
cleanup() { rm -rf -- "$test_root"; }
trap cleanup EXIT

write_fixture() {
    local written_fixture_path=$1
    local written_fixture_label=$2

    # Dollar-prefixed expressions are literal fixture source.
    # shellcheck disable=SC2016
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'set -Eeuo pipefail'
        printf '%s\n' '[[ "${1:-}" = --self-test && $# -eq 1 ]]'
        printf '%s\n' 'printf "%s:%s\n" "${0##*/}" "$(umask)" >>"$ACTION17Q_UMASK_FIXTURE_LOG"'
        printf '%s\n' \
            "printf '%s\\n' 'fixture_${written_fixture_label}_complete=true'"
        printf '%s\n' 'exit "${ACTION17Q_UMASK_FIXTURE_STATUS:-0}"'
    } >"$written_fixture_path"
    chmod 0755 "$written_fixture_path"
}

write_fixture "$test_root/original" original
write_fixture "$test_root/retry" retry
original_hash=$(sha256sum "$test_root/original" | awk '{ print $1 }')
readonly original_hash
retry_hash=$(sha256sum "$test_root/retry" | awk '{ print $1 }')
readonly retry_hash
printf 'fixture_original_complete=true\n' >"$test_root/original.expected"
printf 'fixture_retry_complete=true\n' >"$test_root/retry.expected"
original_stdout_hash=$(sha256sum "$test_root/original.expected" | awk '{ print $1 }')
readonly original_stdout_hash
retry_stdout_hash=$(sha256sum "$test_root/retry.expected" | awk '{ print $1 }')
readonly retry_stdout_hash

: >"$test_root/valid.log"
ACTION17Q_UMASK_FIXTURE_LOG=$test_root/valid.log \
    /bin/bash "$boundary" --production-path-test \
    "$test_root/original" "$original_hash" "$original_stdout_hash" \
    "$test_root/retry" "$retry_hash" "$retry_stdout_hash" \
    >"$test_root/valid.stdout" 2>"$test_root/valid.stderr"
check_regression valid_stderr_empty test ! -s "$test_root/valid.stderr"
check_regression valid_original_umask_count test \
    "$(grep -Fxc 'original:0022' "$test_root/valid.log")" -eq 2
check_regression valid_retry_umask_count test \
    "$(grep -Fxc 'retry:0022' "$test_root/valid.log")" -eq 2
for expected_valid_label in \
    action_17q_umask_boundary_original_direct_accepted=true \
    action_17q_umask_boundary_original_bash_accepted=true \
    action_17q_umask_boundary_retry_direct_accepted=true \
    action_17q_umask_boundary_retry_bash_accepted=true \
    action_17q_umask_boundary_original_invocation_stdout_equal=true \
    action_17q_umask_boundary_retry_invocation_stdout_equal=true \
    action_17q_umask_boundary_outer_umask_before_exact=true \
    action_17q_umask_boundary_outer_umask_restored=true \
    action_17q_umask_boundary_failure_count=0 \
    action_17q_umask_boundary_node_contact=false \
    action_17q_umask_boundary_podman_invoked=false \
    action_17q_umask_boundary_activation_invoked=false \
    action_17q_umask_boundary_live_mutations=false \
    action_17q_umask_boundary_cleanup_complete=true \
    action_17q_umask_boundary_complete=true; do
    check_regression "valid_${expected_valid_label%%=*}" \
        grep -Fxq "$expected_valid_label" "$test_root/valid.stdout"
done
printf 'action_17q_umask_boundary_regression_valid_fixture_accepted=true\n'

set +e
: >"$test_root/failure.log"
ACTION17Q_UMASK_FIXTURE_LOG=$test_root/failure.log \
    ACTION17Q_UMASK_FIXTURE_STATUS=23 \
    /bin/bash "$boundary" --production-path-test \
    "$test_root/original" "$original_hash" "$original_stdout_hash" \
    "$test_root/retry" "$retry_hash" "$retry_stdout_hash" \
    >"$test_root/failure.stdout" 2>"$test_root/failure.stderr"
failure_status=$?
set -e
check_regression failure_status test "$failure_status" -eq 1
for expected_failure_stdout_label in \
    action_17q_umask_boundary_original_direct_status_zero=false \
    action_17q_umask_boundary_original_bash_status_zero=false \
    action_17q_umask_boundary_retry_direct_status_zero=false \
    action_17q_umask_boundary_retry_bash_status_zero=false \
    action_17q_umask_boundary_failure_count=4 \
    action_17q_umask_boundary_cleanup_complete=true; do
    check_regression "failure_${expected_failure_stdout_label%%=*}" \
        grep -Fxq "$expected_failure_stdout_label" "$test_root/failure.stdout"
done
check_regression failure_complete_false \
    grep -Fxq action_17q_umask_boundary_complete=false "$test_root/failure.stderr"
printf 'action_17q_umask_boundary_regression_false_success_rejected=true\n'

set +e
ACTION17Q_UMASK_FIXTURE_LOG=$test_root/hash.log \
    /bin/bash "$boundary" --production-path-test \
    "$test_root/original" 1111111111111111111111111111111111111111111111111111111111111111 \
    "$original_stdout_hash" "$test_root/retry" "$retry_hash" \
    "$retry_stdout_hash" >"$test_root/hash.stdout" 2>"$test_root/hash.stderr"
hash_status=$?
set -e
check_regression hash_status test "$hash_status" -eq 1
check_regression hash_mismatch_visible \
    grep -Fxq action_17q_umask_boundary_original_source_hash_exact=false \
    "$test_root/hash.stdout"
check_regression hash_complete_false \
    grep -Fxq action_17q_umask_boundary_complete=false "$test_root/hash.stderr"
printf 'action_17q_umask_boundary_regression_false_source_accepted=false\n'
printf 'action_17q_umask_boundary_regression_false_positive_and_false_negative_controls=true\n'
printf 'action_17q_umask_boundary_regression_complete=true\n'
