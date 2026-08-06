#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly boundary=$script_directory/action20d-retry3-a-stale-suite-hash-boundary.sh

record_regression() {
    local regression_assertion_label=$1

    shift
    if "$@"; then
        printf 'action_20d_retry3_a_regression_%s=true\n' "$regression_assertion_label"
        return 0
    fi
    printf 'action_20d_retry3_a_regression_%s=false\n' \
        "$regression_assertion_label" >&2
    return 1
}

fixture_root=$(mktemp -d /tmp/caddy-action20d-retry3-a-regression.XXXXXX)
readonly fixture_root
cleanup() { rm -rf -- "$fixture_root"; }
trap cleanup EXIT

write_retry2_validator() {
    local fixture_path=$1
    local fixture_status=$2
    local extra_stderr=${3:-}
    local emitted_stdout_label
    local emitted_stderr_label

    {
        printf '%s\n' '#!/usr/bin/env bash'
        for emitted_stdout_label in \
            action_20d_retry2_focused_syntax=true \
            action_20d_retry2_focused_shellcheck=true \
            action_20d_retry2_focused_canonical_format=true \
            action_20d_retry2_focused_collision_policy=true \
            action_20d_retry2_focused_conditional_policy=true \
            action_20d_retry2_focused_output_evidence_policy=true \
            action_20d_retry2_focused_readiness_outer_immutable=true \
            action_20d_retry2_focused_activation_outer_immutable=true \
            action_20d_retry2_focused_production_boundary_regression=true; do
            printf "printf '%%s\\\\n' '%s'\n" "$emitted_stdout_label"
        done
        for emitted_stderr_label in \
            action_20d_retry2_outer_gate_complete_suite_hash=false \
            action_20d_retry2_focused_outer_self_test=false; do
            printf "printf '%%s\\\\n' '%s' >&2\n" "$emitted_stderr_label"
        done
        if [[ -n "$extra_stderr" ]]; then
            printf "printf '%%s\\\\n' '%s' >&2\n" "$extra_stderr"
        fi
        printf 'exit %s\n' "$fixture_status"
    } >"$fixture_path"
    chmod 0755 "$fixture_path"
}

write_retry3_validator() {
    local fixture_path=$1
    local fixture_status=$2
    local emitted_stdout_label

    {
        printf '%s\n' '#!/usr/bin/env bash'
        for emitted_stdout_label in \
            action_20d_retry3_focused_syntax=true \
            action_20d_retry3_focused_shellcheck=true \
            action_20d_retry3_focused_canonical_format=true \
            action_20d_retry3_focused_collision_policy=true \
            action_20d_retry3_focused_conditional_policy=true \
            action_20d_retry3_focused_output_evidence_policy=true; do
            printf "printf '%%s\\\\n' '%s'\n" "$emitted_stdout_label"
        done
        printf "printf '%%s\\\\n' '%s' >&2\n" \
            action_20d_retry3_focused_complete_suite_exact=false
        printf 'exit %s\n' "$fixture_status"
    } >"$fixture_path"
    chmod 0755 "$fixture_path"
}

write_outer() {
    local fixture_path=$1
    local complete_pin=$2
    local integration_pin=$3

    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf 'readonly complete_suite_sha256=%s\n' "$complete_pin"
        printf 'readonly integration_suite_sha256=%s\n' "$integration_pin"
        printf '%s\n' 'exit 0'
    } >"$fixture_path"
    chmod 0755 "$fixture_path"
}

printf '%s\n' complete-current >"$fixture_root/run.sh"
printf '%s\n' integration-current >"$fixture_root/integration.sh"
write_retry2_validator "$fixture_root/retry2-validator" 1
write_retry3_validator "$fixture_root/retry3-validator" 1
write_outer "$fixture_root/retry2-outer" \
    7393ef594f00839d0366b4d9415b04ed76378046e89cb50c2828877ae2b1a21d \
    18acefaef2da1f0cbcff01b1c598344c11aa6a3caf12d017c1847842c74a2e73
write_outer "$fixture_root/retry3-outer" \
    aba6f8bea4c0a5247cfa08bacf4e85e6dd3b92126dbf69be6f360ed36465bbd2 \
    cc1aa4e8873d680fbf144a51eceae921c6b56dd25d534edacde276fadcc8ff8e

fixture_hash() { sha256sum "$1" | awk '{ print $1 }'; }

run_fixture() {
    local fixture_stdout_path=$1
    local fixture_stderr_path=$2
    local expected_run_hash=${3:-$(fixture_hash "$fixture_root/run.sh")}

    /bin/bash "$boundary" --production-path-test \
        "$fixture_root/retry2-validator" "$(fixture_hash "$fixture_root/retry2-validator")" \
        "$fixture_root/retry2-outer" "$(fixture_hash "$fixture_root/retry2-outer")" \
        "$fixture_root/retry3-validator" "$(fixture_hash "$fixture_root/retry3-validator")" \
        "$fixture_root/retry3-outer" "$(fixture_hash "$fixture_root/retry3-outer")" \
        "$fixture_root/run.sh" "$expected_run_hash" \
        "$fixture_root/integration.sh" "$(fixture_hash "$fixture_root/integration.sh")" \
        >"$fixture_stdout_path" 2>"$fixture_stderr_path"
}

run_fixture "$fixture_root/valid.stdout" "$fixture_root/valid.stderr"
record_regression valid_stderr_empty test ! -s "$fixture_root/valid.stderr"
for valid_label in \
    action_20d_retry3_a_stale_hash_boundary_retry2_status_expected=true \
    action_20d_retry3_a_stale_hash_boundary_retry2_stdout_content_exact=true \
    action_20d_retry3_a_stale_hash_boundary_retry2_stderr_content_exact=true \
    action_20d_retry3_a_stale_hash_boundary_retry3_status_expected=true \
    action_20d_retry3_a_stale_hash_boundary_retry3_stdout_content_exact=true \
    action_20d_retry3_a_stale_hash_boundary_retry3_stderr_content_exact=true \
    action_20d_retry3_a_stale_hash_boundary_failure_count=0 \
    action_20d_retry3_a_stale_hash_boundary_historical_artifacts_modified=false \
    action_20d_retry3_a_stale_hash_boundary_complete_suite_invoked=false \
    action_20d_retry3_a_stale_hash_boundary_node_contact=false \
    action_20d_retry3_a_stale_hash_boundary_activation_invoked=false \
    action_20d_retry3_a_stale_hash_boundary_live_mutations=false \
    action_20d_retry3_a_stale_hash_boundary_cleanup_complete=true \
    action_20d_retry3_a_stale_hash_boundary_complete=true; do
    record_regression "valid_${valid_label%%=*}" \
        grep -Fxq "$valid_label" "$fixture_root/valid.stdout"
done
printf 'action_20d_retry3_a_regression_valid_transcripts_accepted=true\n'

write_retry2_validator "$fixture_root/retry2-validator" 0
set +e
run_fixture "$fixture_root/status-zero.stdout" "$fixture_root/status-zero.stderr"
status_zero_status=$?
set -e
record_regression status_zero_rejected test "$status_zero_status" -eq 1
record_regression status_zero_visible grep -Fxq \
    action_20d_retry3_a_stale_hash_boundary_retry2_status_expected=false \
    "$fixture_root/status-zero.stderr"

write_retry2_validator "$fixture_root/retry2-validator" 1 unexpected_failure=false
set +e
run_fixture "$fixture_root/extra-failure.stdout" "$fixture_root/extra-failure.stderr"
extra_failure_status=$?
set -e
record_regression extra_failure_rejected test "$extra_failure_status" -eq 1
record_regression extra_failure_hash_visible grep -Fxq \
    action_20d_retry3_a_stale_hash_boundary_retry2_stderr_hash_exact=false \
    "$fixture_root/extra-failure.stderr"

write_retry2_validator "$fixture_root/retry2-validator" 1
set +e
run_fixture "$fixture_root/hash.stdout" "$fixture_root/hash.stderr" \
    1111111111111111111111111111111111111111111111111111111111111111
hash_status=$?
set -e
record_regression current_hash_mismatch_rejected test "$hash_status" -eq 1
record_regression current_hash_mismatch_visible grep -Fxq \
    action_20d_retry3_a_stale_hash_boundary_complete_suite_hash_exact=false \
    "$fixture_root/hash.stderr"

write_outer "$fixture_root/retry2-outer" \
    1111111111111111111111111111111111111111111111111111111111111111 \
    18acefaef2da1f0cbcff01b1c598344c11aa6a3caf12d017c1847842c74a2e73
set +e
run_fixture "$fixture_root/pin.stdout" "$fixture_root/pin.stderr"
pin_status=$?
set -e
record_regression missing_stale_pin_rejected test "$pin_status" -eq 1
record_regression missing_stale_pin_visible grep -Fxq \
    action_20d_retry3_a_stale_hash_boundary_retry2_complete_pin_exact=false \
    "$fixture_root/pin.stderr"

printf 'action_20d_retry3_a_regression_false_positive_controls=true\n'
printf 'action_20d_retry3_a_regression_false_negative_controls=true\n'
printf 'action_20d_retry3_a_regression_complete=true\n'
