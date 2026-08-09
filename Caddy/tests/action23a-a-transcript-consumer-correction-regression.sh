#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_23a_a_consumer_regression
readonly expected_fixture_sha256=98c0d305f35b0b6d8bb849cd40abcce416ecdc159be0a4059e33cc6561ff3021
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly runner=$caddy_root/scripts/run-action23a-a-transcript-consumer-correction.sh
readonly collision_checker=$test_directory/check-shell-readonly-local-collisions-v2.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_gate() {
    local action23aa_consumer_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action23aa_consumer_regression_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action23aa_consumer_regression_label" >&2
    return 1
}
run_fixture_case() (
    local action23aa_consumer_regression_root=$1
    local action23aa_consumer_regression_fixture=$2
    local action23aa_consumer_regression_expected_status=$3
    local action23aa_consumer_regression_stdout=$action23aa_consumer_regression_root/stdout
    local action23aa_consumer_regression_stderr=$action23aa_consumer_regression_root/stderr
    local action23aa_consumer_regression_status=0

    install -d -m 0700 "$action23aa_consumer_regression_root" || return 1
    CADDY_ACTION23AA_CONSUMER_TEST_MODE=1 /bin/bash "$runner" \
        --test-fixture "$action23aa_consumer_regression_fixture" \
        >"$action23aa_consumer_regression_stdout" 2>"$action23aa_consumer_regression_stderr" ||
        action23aa_consumer_regression_status=$?
    [[ "$action23aa_consumer_regression_status" -eq "$action23aa_consumer_regression_expected_status" ]] || return 1
    if [[ "$action23aa_consumer_regression_expected_status" -eq 0 ]]; then
        grep -Fqx action_23a_a_consumer_correction_acceptance=true \
            "$action23aa_consumer_regression_stdout" || return 1
        grep -Fqx action_23a_a_consumer_correction_complete=true \
            "$action23aa_consumer_regression_stdout" || return 1
        grep -Fqx action_23a_a_consumer_correction_action_executed=false \
            "$action23aa_consumer_regression_stdout" || return 1
        [[ ! -s "$action23aa_consumer_regression_stderr" ]] || return 1
    fi
)
run_regression() (
    local action23aa_consumer_regression_root
    local action23aa_consumer_regression_fixture
    local action23aa_consumer_regression_case
    local action23aa_consumer_regression_collision_fixture
    local action23aa_consumer_regression_collision_status=0

    action23aa_consumer_regression_root=$(mktemp -d /tmp/caddy-action23a-a-consumer-regression.XXXXXX) || return 1
    trap 'rm -rf -- "$action23aa_consumer_regression_root"' EXIT
    action23aa_consumer_regression_fixture=$action23aa_consumer_regression_root/captured.stdout
    CADDY_ACTION23AA_CONSUMER_TEST_MODE=1 /bin/bash "$runner" \
        --build-fixture "$action23aa_consumer_regression_fixture" || return 1
    record_gate fixture_hash_exact test \
        "$(file_hash "$action23aa_consumer_regression_fixture")" = "$expected_fixture_sha256" || return 1
    record_gate fixture_bytes_exact test \
        "$(wc -c <"$action23aa_consumer_regression_fixture")" -eq 5790 || return 1
    record_gate fixture_lines_exact test \
        "$(awk 'END { print NR }' "$action23aa_consumer_regression_fixture")" -eq 114 || return 1
    record_gate valid_production_consumer run_fixture_case \
        "$action23aa_consumer_regression_root/valid" \
        "$action23aa_consumer_regression_fixture" 0 || return 1

    for action23aa_consumer_regression_case in altered missing duplicate false wrong_missing; do
        cp -- "$action23aa_consumer_regression_fixture" \
            "$action23aa_consumer_regression_root/$action23aa_consumer_regression_case.stdout" || return 1
    done
    sed -i 's/action_23a_a_value_local_zone_sha256=b0c6549c/action_23a_a_value_local_zone_sha256=00c6549c/' \
        "$action23aa_consumer_regression_root/altered.stdout" || return 1
    sed -i '/action_23a_a_check_backup_file_hash_exact=true/d' \
        "$action23aa_consumer_regression_root/missing.stdout" || return 1
    printf '%s\n' action_23a_a_check_backup_file_hash_exact=true \
        >>"$action23aa_consumer_regression_root/duplicate.stdout" || return 1
    sed -i 's/action_23a_a_check_backup_file_hash_exact=true/action_23a_a_check_backup_file_hash_exact=false/' \
        "$action23aa_consumer_regression_root/false.stdout" || return 1
    sed -i '/action_23a_a_check_local_zone_hash_exact=true/d' \
        "$action23aa_consumer_regression_root/wrong_missing.stdout" || return 1
    for action23aa_consumer_regression_case in altered missing duplicate false wrong_missing; do
        record_gate "${action23aa_consumer_regression_case}_rejected" run_fixture_case \
            "$action23aa_consumer_regression_root/$action23aa_consumer_regression_case" \
            "$action23aa_consumer_regression_root/$action23aa_consumer_regression_case.stdout" 1 || return 1
    done

    # The literal verifies that the historical source references its own variable.
    # shellcheck disable=SC2016
    record_gate source_redirection_boundary grep -Fqx \
        'record_check unbound_configuration_valid unbound-checkconf "$live_root" >/dev/null || exit 1' \
        "$caddy_root/scripts/inspect-node-b-unbound-a-records-post-action23a-a.sh" || return 1
    record_gate captured_hash_literal grep -Fq "$expected_fixture_sha256" "$runner" || return 1
    action23aa_consumer_regression_collision_fixture=$action23aa_consumer_regression_root/collision.sh
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' 'readonly action23aa_consumer_collision=value' \
        'collision() {' '    local action23aa_consumer_collision=other' \
        '    printf '\''%s\n'\'' "$action23aa_consumer_collision"' '}' \
        >"$action23aa_consumer_regression_collision_fixture" || return 1
    /bin/bash "$collision_checker" "$action23aa_consumer_regression_collision_fixture" \
        >/dev/null 2>&1 || action23aa_consumer_regression_collision_status=$?
    record_gate dynamic_scope_collision_rejected test \
        "$action23aa_consumer_regression_collision_status" -eq 1 || return 1
    record_gate collision_policy_clean /bin/bash "$collision_checker" \
        "$runner" "$0" || return 1
    printf '%s_false_negative_exact_capture_accepted=true\n' "$prefix"
    printf '%s_false_positive_changed_captures_rejected=true\n' "$prefix"
    printf '%s_node_a_contacted=false\n' "$prefix"
    printf '%s_node_b_contacted=false\n' "$prefix"
    printf '%s_action_23a_rerun=false\n' "$prefix"
    printf '%s_action_executed=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
)

run_regression
