#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly boundary=$script_directory/action20d-retry3-a-retry-stale-suite-hash-boundary.sh

record_regression() {
    local retry_regression_label=$1

    shift
    if "$@"; then
        printf 'action_20d_retry3_a_retry_regression_%s=true\n' \
            "$retry_regression_label"
        return 0
    fi
    printf 'action_20d_retry3_a_retry_regression_%s=false\n' \
        "$retry_regression_label" >&2
    return 1
}

fixture_root=$(mktemp -d /tmp/caddy-action20d-retry3-a-retry-regression.XXXXXX)
readonly fixture_root
cleanup() { rm -rf -- "$fixture_root"; }
trap cleanup EXIT

readonly -a production_retry3_lines=(
    action_20d_retry3_focused_syntax=true
    action_20d_retry3_focused_shellcheck=true
    action_20d_retry3_focused_canonical_format=true
    readonly_local_collision_count=0
    shell_readonly_local_collision_policy_v2_complete=true
    action_20d_retry3_focused_collision_policy=true
    conditional_validator_historical_errexit_suppression_reproduced=true
    conditional_validator_explicit_return_false_positive_rejected=true
    conditional_validator_explicit_return_false_negative_accepted=true
    conditional_validator_marked_file_count=19
    conditional_validator_errexit_policy_regression_complete=true
    action_20d_retry3_focused_conditional_policy=true
    historical_action_17s_stdout_evidence_exception_hash=325a8fff552646073768a619f5ee793423494d7258c8503624f1b44be0a0e5d8
    historical_action_17s_retry_content_exception_hash=269c48158969f3767b13ffa92aaef1559bcb0c25c64bb19fdb93e70f56713bd0
    transaction_output_evidence_policy_complete=true
    action_20d_retry3_focused_output_evidence_policy=true
)

write_retry2_validator() {
    local retry2_fixture_path=$1
    local retry2_fixture_label

    {
        printf '%s\n' '#!/usr/bin/env bash'
        for retry2_fixture_label in \
            action_20d_retry2_focused_syntax=true \
            action_20d_retry2_focused_shellcheck=true \
            action_20d_retry2_focused_canonical_format=true \
            action_20d_retry2_focused_collision_policy=true \
            action_20d_retry2_focused_conditional_policy=true \
            action_20d_retry2_focused_output_evidence_policy=true \
            action_20d_retry2_focused_readiness_outer_immutable=true \
            action_20d_retry2_focused_activation_outer_immutable=true \
            action_20d_retry2_focused_production_boundary_regression=true; do
            printf "printf '%%s\\\\n' '%s'\n" "$retry2_fixture_label"
        done
        for retry2_fixture_label in \
            action_20d_retry2_outer_gate_complete_suite_hash=false \
            action_20d_retry2_focused_outer_self_test=false; do
            printf "printf '%%s\\\\n' '%s' >&2\n" "$retry2_fixture_label"
        done
        printf '%s\n' 'exit 1'
    } >"$retry2_fixture_path"
    chmod 0755 "$retry2_fixture_path"
}

write_retry3_validator() {
    local retry3_fixture_path=$1
    local retry3_variant=$2
    local retry3_line
    local retry3_index

    {
        printf '%s\n' '#!/usr/bin/env bash'
        for retry3_index in "${!production_retry3_lines[@]}"; do
            retry3_line=${production_retry3_lines[$retry3_index]}
            if [[ "$retry3_variant" = missing && "$retry3_line" = conditional_validator_marked_file_count=19 ]]; then
                continue
            fi
            if [[ "$retry3_variant" = altered && "$retry3_line" = conditional_validator_marked_file_count=19 ]]; then
                retry3_line=conditional_validator_marked_file_count=18
            fi
            if [[ "$retry3_variant" = reordered && "$retry3_index" -eq 7 ]]; then
                retry3_line=${production_retry3_lines[8]}
            elif [[ "$retry3_variant" = reordered && "$retry3_index" -eq 8 ]]; then
                retry3_line=${production_retry3_lines[7]}
            fi
            printf "printf '%%s\\\\n' '%s'\n" "$retry3_line"
        done
        if [[ "$retry3_variant" = extra ]]; then
            printf "printf '%%s\\\\n' '%s'\n" unexpected_policy_output=true
        fi
        printf "printf '%%s\\\\n' '%s' >&2\n" \
            action_20d_retry3_focused_complete_suite_exact=false
        printf '%s\n' 'exit 1'
    } >"$retry3_fixture_path"
    chmod 0755 "$retry3_fixture_path"
}

write_outer() {
    local outer_fixture_path=$1
    local outer_complete_pin=$2
    local outer_integration_pin=$3

    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf 'readonly complete_suite_sha256=%s\n' "$outer_complete_pin"
        printf 'readonly integration_suite_sha256=%s\n' "$outer_integration_pin"
        printf '%s\n' 'exit 0'
    } >"$outer_fixture_path"
    chmod 0755 "$outer_fixture_path"
}

fixture_hash() { sha256sum "$1" | awk '{ print $1 }'; }

write_retry2_validator "$fixture_root/retry2-validator"
write_retry3_validator "$fixture_root/retry3-validator" exact
write_outer "$fixture_root/retry2-outer" \
    7393ef594f00839d0366b4d9415b04ed76378046e89cb50c2828877ae2b1a21d \
    18acefaef2da1f0cbcff01b1c598344c11aa6a3caf12d017c1847842c74a2e73
write_outer "$fixture_root/retry3-outer" \
    aba6f8bea4c0a5247cfa08bacf4e85e6dd3b92126dbf69be6f360ed36465bbd2 \
    cc1aa4e8873d680fbf144a51eceae921c6b56dd25d534edacde276fadcc8ff8e
printf '%s\n' complete-current >"$fixture_root/run.sh"
printf '%s\n' integration-current >"$fixture_root/integration.sh"

run_fixture() {
    local fixture_stdout_path=$1
    local fixture_stderr_path=$2

    /bin/bash "$boundary" --production-path-test \
        "$fixture_root/retry2-validator" "$(fixture_hash "$fixture_root/retry2-validator")" \
        "$fixture_root/retry2-outer" "$(fixture_hash "$fixture_root/retry2-outer")" \
        "$fixture_root/retry3-validator" "$(fixture_hash "$fixture_root/retry3-validator")" \
        "$fixture_root/retry3-outer" "$(fixture_hash "$fixture_root/retry3-outer")" \
        "$fixture_root/run.sh" "$(fixture_hash "$fixture_root/run.sh")" \
        "$fixture_root/integration.sh" "$(fixture_hash "$fixture_root/integration.sh")" \
        >"$fixture_stdout_path" 2>"$fixture_stderr_path"
}

run_fixture "$fixture_root/exact.stdout" "$fixture_root/exact.stderr"
record_regression exact_stderr_empty test ! -s "$fixture_root/exact.stderr"
record_regression exact_complete grep -Fxq \
    action_20d_retry3_a_retry_boundary_complete=true "$fixture_root/exact.stdout"
record_regression exact_failure_count grep -Fxq \
    action_20d_retry3_a_retry_boundary_failure_count=0 "$fixture_root/exact.stdout"
record_regression exact_retry3_content grep -Fxq \
    action_20d_retry3_a_retry_boundary_retry3_stdout_content_exact=true \
    "$fixture_root/exact.stdout"
printf 'action_20d_retry3_a_retry_regression_exact_production_transcript_accepted=true\n'

for negative_variant in missing extra reordered altered; do
    write_retry3_validator "$fixture_root/retry3-validator" "$negative_variant"
    set +e
    run_fixture "$fixture_root/$negative_variant.stdout" \
        "$fixture_root/$negative_variant.stderr"
    negative_status=$?
    set -e
    record_regression "${negative_variant}_status_rejected" \
        test "$negative_status" -eq 1
    record_regression "${negative_variant}_hash_rejected" grep -Fxq \
        action_20d_retry3_a_retry_boundary_retry3_stdout_hash_exact=false \
        "$fixture_root/$negative_variant.stderr"
    record_regression "${negative_variant}_content_rejected" grep -Fxq \
        action_20d_retry3_a_retry_boundary_retry3_stdout_content_exact=false \
        "$fixture_root/$negative_variant.stderr"
    record_regression "${negative_variant}_cleanup" grep -Fxq \
        action_20d_retry3_a_retry_boundary_cleanup_complete=true \
        "$fixture_root/$negative_variant.stdout"
done

printf 'action_20d_retry3_a_retry_regression_missing_output_rejected=true\n'
printf 'action_20d_retry3_a_retry_regression_extra_output_rejected=true\n'
printf 'action_20d_retry3_a_retry_regression_reordered_output_rejected=true\n'
printf 'action_20d_retry3_a_retry_regression_altered_output_rejected=true\n'
printf 'action_20d_retry3_a_retry_regression_false_positive_controls=true\n'
printf 'action_20d_retry3_a_retry_regression_false_negative_controls=true\n'
printf 'action_20d_retry3_a_retry_regression_complete=true\n'
