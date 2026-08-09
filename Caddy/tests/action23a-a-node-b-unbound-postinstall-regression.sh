#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_23a_a_regression
readonly fixture_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-node-b-unbound-a-records-post-action23a-a.sh
readonly outer=$caddy_root/scripts/run-node-b-unbound-a-records-post-action23a-a-outer.sh
readonly collision_checker=$test_directory/check-shell-readonly-local-collisions-v2.sh

record_gate() {
    local action23aa_regression_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action23aa_regression_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action23aa_regression_gate_label" >&2
    return 1
}
write_mock_ssh() {
    local action23aa_regression_mock=$1

    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'printf '\''%s\n'\'' "$@" >"$ACTION23AA_MOCK_ARGS"' \
        'cat >/dev/null' \
        'cat "$ACTION23AA_MOCK_STDOUT"' \
        'cat "$ACTION23AA_MOCK_STDERR" >&2' \
        'exit "$ACTION23AA_MOCK_STATUS"' >"$action23aa_regression_mock" || return 1
    chmod 0755 "$action23aa_regression_mock"
}
run_case() (
    local action23aa_regression_case_root=$1
    local action23aa_regression_transcript=$2
    local action23aa_regression_remote_status=$3
    local action23aa_regression_expected_status=$4
    local action23aa_regression_stderr_content=${5:-}
    local action23aa_regression_mock=$action23aa_regression_case_root/mock-ssh
    local action23aa_regression_mock_stderr=$action23aa_regression_case_root/mock.stderr
    local action23aa_regression_mock_args=$action23aa_regression_case_root/mock.args
    local action23aa_regression_outer_stdout=$action23aa_regression_case_root/outer.stdout
    local action23aa_regression_outer_stderr=$action23aa_regression_case_root/outer.stderr
    local action23aa_regression_observed_status=0

    install -d -m 0700 "$action23aa_regression_case_root" || return 1
    write_mock_ssh "$action23aa_regression_mock" || return 1
    printf '%s' "$action23aa_regression_stderr_content" >"$action23aa_regression_mock_stderr" || return 1
    CADDY_ACTION23AA_TEST_MODE=1 \
        CADDY_ACTION23AA_SSH_BINARY=$action23aa_regression_mock \
        ACTION23AA_MOCK_ARGS=$action23aa_regression_mock_args \
        ACTION23AA_MOCK_STDOUT=$action23aa_regression_transcript \
        ACTION23AA_MOCK_STDERR=$action23aa_regression_mock_stderr \
        ACTION23AA_MOCK_STATUS=$action23aa_regression_remote_status \
        /bin/bash "$outer" --test-transport \
        >"$action23aa_regression_outer_stdout" 2>"$action23aa_regression_outer_stderr" ||
        action23aa_regression_observed_status=$?
    if [[ "$action23aa_regression_observed_status" -ne "$action23aa_regression_expected_status" ]]; then
        printf '%s_case_status_observed=%s\n' "$prefix" "$action23aa_regression_observed_status" >&2
        printf '%s_case_status_expected=%s\n' "$prefix" "$action23aa_regression_expected_status" >&2
        printf '%s_case_stdout_begin\n' "$prefix" >&2
        cat "$action23aa_regression_outer_stdout" >&2
        printf '%s_case_stdout_end\n' "$prefix" >&2
        printf '%s_case_stderr_begin\n' "$prefix" >&2
        cat "$action23aa_regression_outer_stderr" >&2
        printf '%s_case_stderr_end\n' "$prefix" >&2
        return 1
    fi
    if ! grep -Fqx 'pi@10.1.0.54' "$action23aa_regression_mock_args"; then
        printf '%s_case_target_argument=false\n' "$prefix" >&2
        return 1
    fi
    if ! grep -Fqx 'cd / && sudo -n /bin/bash -s --' "$action23aa_regression_mock_args"; then
        printf '%s_case_remote_command_argument=false\n' "$prefix" >&2
        return 1
    fi
    if [[ "$action23aa_regression_expected_status" -eq 0 ]]; then
        grep -Fqx action_23a_a_outer_acceptance=true "$action23aa_regression_outer_stdout" || return 1
        grep -Fqx action_23a_a_outer_complete=true "$action23aa_regression_outer_stdout" || return 1
        [[ ! -s "$action23aa_regression_outer_stderr" ]] || return 1
    fi
)
run_validation_case() (
    local action23aa_regression_case_root=$1
    local action23aa_regression_transcript=$2
    local action23aa_regression_remote_status=$3
    local action23aa_regression_expected_status=$4
    local action23aa_regression_stderr_content=${5:-}
    local action23aa_regression_stderr=$action23aa_regression_case_root/remote.stderr
    local action23aa_regression_stdout=$action23aa_regression_case_root/validator.stdout
    local action23aa_regression_validator_stderr=$action23aa_regression_case_root/validator.stderr
    local action23aa_regression_observed_status=0

    install -d -m 0700 "$action23aa_regression_case_root" || return 1
    printf '%s' "$action23aa_regression_stderr_content" >"$action23aa_regression_stderr" || return 1
    CADDY_ACTION23AA_TEST_MODE=1 /bin/bash "$outer" --test-validate \
        "$action23aa_regression_transcript" "$action23aa_regression_stderr" \
        "$action23aa_regression_remote_status" \
        >"$action23aa_regression_stdout" 2>"$action23aa_regression_validator_stderr" ||
        action23aa_regression_observed_status=$?
    [[ "$action23aa_regression_observed_status" -eq "$action23aa_regression_expected_status" ]]
)
run_regression() (
    local action23aa_regression_root
    local action23aa_regression_valid
    local action23aa_regression_case
    local action23aa_regression_collision_fixture
    local action23aa_regression_collision_status=0

    action23aa_regression_root=$(mktemp -d /tmp/caddy-action23a-a-regression.XXXXXX) || return 1
    trap 'rm -rf -- "$action23aa_regression_root"' EXIT
    action23aa_regression_valid=$action23aa_regression_root/valid.transcript
    /bin/bash "$inspector" --contract-transcript >"$action23aa_regression_valid" || return 1
    record_gate expected_checks_unique test \
        "$(/bin/bash "$inspector" --expected-checks | wc -l)" -eq \
        "$(/bin/bash "$inspector" --expected-checks | LC_ALL=C sort -u | wc -l)" || return 1
    record_gate valid_production_path run_case \
        "$action23aa_regression_root/valid" "$action23aa_regression_valid" 0 0 || return 1

    for action23aa_regression_case in false missing duplicate reordered changed_state changed_hash; do
        cp -- "$action23aa_regression_valid" \
            "$action23aa_regression_root/$action23aa_regression_case.transcript" || return 1
    done
    sed -i '0,/action_23a_a_check_local_zone_hash_exact=true/s//action_23a_a_check_local_zone_hash_exact=false/' \
        "$action23aa_regression_root/false.transcript" || return 1
    sed -i '0,/action_23a_a_check_local_zone_hash_exact=true/d' \
        "$action23aa_regression_root/missing.transcript" || return 1
    printf '%s\n' action_23a_a_check_local_zone_hash_exact=true \
        >>"$action23aa_regression_root/duplicate.transcript" || return 1
    awk 'NR == 1 { first=$0; next } NR == 2 { print; print first; next } { print }' \
        "$action23aa_regression_valid" >"$action23aa_regression_root/reordered.tmp" || return 1
    mv "$action23aa_regression_root/reordered.tmp" \
        "$action23aa_regression_root/reordered.transcript" || return 1
    sed -i "s/action_23a_a_value_after_state_sha256=$fixture_state_sha256/action_23a_a_value_after_state_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/" \
        "$action23aa_regression_root/changed_state.transcript" || return 1
    sed -i 's/action_23a_a_value_local_zone_sha256=b0c6549c1ac5825de7c50e60e5c825cddb51f5d75056f0fd37c196d670886160/action_23a_a_value_local_zone_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/' \
        "$action23aa_regression_root/changed_hash.transcript" || return 1
    for action23aa_regression_case in false missing duplicate reordered changed_state changed_hash; do
        record_gate "${action23aa_regression_case}_rejected" run_validation_case \
            "$action23aa_regression_root/$action23aa_regression_case" \
            "$action23aa_regression_root/$action23aa_regression_case.transcript" 0 97 || return 1
    done
    record_gate stderr_rejected run_validation_case "$action23aa_regression_root/stderr" \
        "$action23aa_regression_valid" 0 97 bounded-safe-error || return 1
    record_gate nonzero_status_preserved run_validation_case "$action23aa_regression_root/status" \
        "$action23aa_regression_valid" 7 7 || return 1

    action23aa_regression_collision_fixture=$action23aa_regression_root/collision.sh
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' 'readonly action23aa_collision=value' \
        'collision() {' '    local action23aa_collision=other' \
        '    printf '\''%s\n'\'' "$action23aa_collision"' '}' \
        >"$action23aa_regression_collision_fixture" || return 1
    /bin/bash "$collision_checker" "$action23aa_regression_collision_fixture" \
        >/dev/null 2>&1 || action23aa_regression_collision_status=$?
    record_gate dynamic_scope_collision_rejected test \
        "$action23aa_regression_collision_status" -eq 1 || return 1
    record_gate collision_policy_clean /bin/bash "$collision_checker" \
        "$inspector" "$outer" "$0" || return 1
    printf '%s_false_negative_valid_transcript_accepted=true\n' "$prefix"
    printf '%s_false_positive_invalid_transcripts_rejected=true\n' "$prefix"
    printf '%s_false_negative_nonzero_status_preserved=true\n' "$prefix"
    printf '%s_node_a_contacted=false\n' "$prefix"
    printf '%s_node_b_contacted=false\n' "$prefix"
    printf '%s_action_executed=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
)

run_regression
