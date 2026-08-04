#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19d_a_retry
readonly derivation_sha256=43194087265eea5a52e0f10a4b53eb2c4b4625b62ceb053c567a92af37920b22
readonly inspector_sha256=486fb557c59a13f97ef363b96429545560a5dc3e3d413418ac5e289b0bee831a
readonly runner_sha256=3913ea82853827c85804d5909e08130ff7becc738f072a0e61d9154071c14b72
readonly historical_derivation_sha256=f128432030f4fce0be7d2ab71a24fd70f9a966cbd14113b7b5cde02ccabb4f89
readonly historical_regression_sha256=55def1e05bdb4e9f84a991c90ac4bd8b4bcbef9da36981f55ec30033c0c475f8
readonly historical_outer_sha256=f90a6812400d7015527c85dc93a45d96ca2101e5edf7abef822a3d245cb1528c
readonly transcribed_tree_sha256=dad64e4ac7fdbaab2dbdc4bf88feab59d4b6f99ee51ac562e67f968967072f66
readonly expected_tree_sha256=dad64e4ac7fdbaab2db3454ccf79158b6f41e4973086f9937a7c6b737f0a2f66

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly derivation="$caddy_root/scripts/derive-node-a-keepalived-helper-postinstall-action19d-a-retry.sh"
readonly historical_derivation="$caddy_root/scripts/derive-node-a-keepalived-helper-postinstall-action19d-a.sh"
readonly historical_regression="$test_directory/action19d-a-node-a-keepalived-helper-postinstall-regression.sh"
readonly historical_outer="$caddy_root/scripts/run-node-a-keepalived-helper-postinstall-action19d-a-outer.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"
readonly inner_collision_checker="$test_directory/check-shell-readonly-local-collisions.sh"
readonly conditional_policy="$test_directory/conditional-validator-errexit-policy-regression.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

require_gate() {
    local gate_label=$1

    shift
    if "$@"; then
        printf '%s_regression_%s=true\n' "$prefix" "$gate_label"
        return 0
    fi
    printf '%s_regression_%s=false\n' "$prefix" "$gate_label" >&2
    return 1
}

transcribed_pin_absent() {
    local pin_value=$1

    shift
    ! grep -Fq "$pin_value" "$@"
}

regression_root=$(mktemp -d /tmp/caddy-action19d-a-retry-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
readonly rendered_root=$regression_root/Caddy
readonly rendered_scripts=$rendered_root/scripts
readonly rendered_tests=$rendered_root/tests
install -d -m 0700 "$rendered_scripts" "$rendered_tests"
install -m 0755 "$collision_checker" "$inner_collision_checker" \
    "$rendered_tests/"
/bin/bash "$derivation" --output-directory "$rendered_scripts"
readonly inspector=$rendered_scripts/inspect-node-a-keepalived-helper-postinstall-action19d-a-retry.sh
readonly runner=$rendered_scripts/run-node-a-keepalived-helper-postinstall-action19d-a-retry.sh

require_gate derivation_hash_exact test "$(file_hash "$derivation")" = \
    "$derivation_sha256"
require_gate historical_derivation_immutable test \
    "$(file_hash "$historical_derivation")" = \
    "$historical_derivation_sha256"
require_gate historical_regression_immutable test \
    "$(file_hash "$historical_regression")" = \
    "$historical_regression_sha256"
require_gate historical_outer_immutable test \
    "$(file_hash "$historical_outer")" = "$historical_outer_sha256"
require_gate inspector_hash_exact test "$(file_hash "$inspector")" = \
    "$inspector_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = \
    "$runner_sha256"
require_gate syntax_valid bash -n "$derivation" "$inspector" "$runner"
require_gate shellcheck_clean shellcheck "$derivation" "$inspector" "$runner"
require_gate collision_policy_clean "$collision_checker" "$0" \
    "$derivation" "$inspector" "$runner"
require_gate conditional_validator_policy "$conditional_policy" >/dev/null
require_gate derivation_self_test /bin/bash "$derivation" --self-test
require_gate inspector_self_test /bin/bash "$inspector" --self-test
require_gate runner_self_test /bin/bash "$runner" --self-test
contract_output=$(/bin/bash "$runner" --contract-test)
readonly contract_output
require_gate runner_contract_test grep -Fxq \
    action_19d_a_retry_runner_contract_test_complete=true \
    <(printf '%s\n' "$contract_output")
require_gate observed_mismatch_rejected grep -Fxq \
    action_19d_a_retry_runner_contract_tree_mismatch_rejected=true \
    <(printf '%s\n' "$contract_output")
require_gate corrected_pin_inspector grep -Fxq \
    "readonly expected_keepalived_tree_sha256=$expected_tree_sha256" \
    "$inspector"
require_gate corrected_pin_runner grep -Fxq \
    "readonly expected_keepalived_tree_sha256=$expected_tree_sha256" \
    "$runner"
require_gate transcribed_pin_absent transcribed_pin_absent \
    "$transcribed_tree_sha256" \
    "$inspector" "$runner"
require_gate expected_value_emitted test \
    "$(grep -Fc "value_keepalived_tree_expected_sha256" "$inspector")" \
    -eq 1
require_gate observed_value_emitted test \
    "$(grep -Fc "value_keepalived_tree_observed_sha256" "$inspector")" \
    -eq 1
require_gate runner_requires_expected_value grep -Fq \
    "value_keepalived_tree_expected_sha256=\$expected_keepalived_tree_sha256" \
    "$runner"
require_gate runner_requires_observed_value grep -Fq \
    'value_keepalived_tree_observed_sha256' "$runner"
require_gate expected_observed_comparison grep -Fq \
    "\$contract_keepalived_tree_hash" "$runner"

printf '%s_false_negative_corrected_pin_accepted=true\n' "$prefix"
printf '%s_false_negative_observed_hash_emitted=true\n' "$prefix"
printf '%s_false_positive_transcribed_pin_rejected=true\n' "$prefix"
printf '%s_false_positive_observed_hash_mismatch_rejected=true\n' "$prefix"
printf '%s_production_path_network_contact=false\n' "$prefix"
printf '%s_regression_complete=true\n' "$prefix"
