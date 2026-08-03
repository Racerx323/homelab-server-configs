#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly derivation_sha256=f6d2584afced3f503f7ad36aff518e9c3b73809a94d4f6d1ec390a8e4f6a53a1
readonly historical_regression_sha256=962785f102739d9a653c61d2860a549d09cdb15d7775182226e6c6abee0c9ade
readonly rendered_inspector_sha256=e8a4caf2c0fd17924ed7d1aff96383b9d38d28a5864d10ce434697b343428a02
readonly rendered_runner_sha256=d14a3c73a4058d702e872af868ce038af4e926084a7516c76d2c8e2ad28ab0cc

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly derivation="$caddy_root/scripts/derive-node-a-action18b-postfailure-action18b-a-retry.sh"
readonly historical_regression="$test_directory/action18b-a-node-a-postfailure-regression.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

require_hash() {
    local assertion_label=$1
    local assertion_path=$2
    local expected_hash=$3

    [[ "$(file_hash "$assertion_path")" == "$expected_hash" ]] || return 1
    printf 'action_18b_a_retry_regression_assertion_%s=true\n' "$assertion_label"
}

regression_root=$(mktemp -d /tmp/caddy-action18b-a-retry-regression.XXXXXX)
readonly regression_root
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$regression_root"
}
trap cleanup EXIT

require_hash derivation_hash_exact "$derivation" "$derivation_sha256"
require_hash historical_regression_hash_exact \
    "$historical_regression" "$historical_regression_sha256"

readonly staged_caddy="$regression_root/source/Caddy"
install -d -m 0700 "$staged_caddy/scripts" "$staged_caddy/tests"
"$derivation" --output-directory "$staged_caddy/scripts" >/dev/null
install -m 0755 "$collision_checker" "$staged_caddy/tests/"
readonly inspector="$staged_caddy/scripts/inspect-node-a-action18b-postfailure-action18b-a-retry.sh"
readonly runner="$staged_caddy/scripts/run-node-a-action18b-postfailure-action18b-a-retry.sh"

require_hash rendered_inspector_hash_exact "$inspector" "$rendered_inspector_sha256"
require_hash rendered_runner_hash_exact "$runner" "$rendered_runner_sha256"

readonly transformed_regression="$staged_caddy/tests/action18b-a-retry-node-a-postfailure-production-regression.sh"
awk -v inspector_hash="$rendered_inspector_sha256" '
    {
        line = $0
        gsub(/action_18b_a/, "action_18b_a_retry", line)
        gsub(/action18b-a-node-a-postfailure/, "action18b-a-retry-node-a-postfailure", line)
        gsub(/inspect-node-a-action18b-postfailure-action18b-a\.sh/,
            "inspect-node-a-action18b-postfailure-action18b-a-retry.sh", line)
        gsub(/run-node-a-action18b-postfailure-action18b-a\.sh/,
            "run-node-a-action18b-postfailure-action18b-a-retry.sh", line)
        if (line ~ /^readonly inspector_sha256=/) {
            line = "readonly inspector_sha256=" inspector_hash
        }
        print line
    }
' "$historical_regression" >"$transformed_regression"
chmod 0755 "$transformed_regression"

bash -n "$inspector" "$runner" "$transformed_regression"
shellcheck "$inspector" "$runner" "$transformed_regression"
"$collision_checker" "$inspector" "$runner" "$transformed_regression" >/dev/null
"$inspector" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --source-test >/dev/null
"$runner" --contract-test >/dev/null
"$transformed_regression" >/dev/null
printf 'action_18b_a_retry_regression_assertion_intercepted_production_path=true\n'

readonly function_source="$regression_root/transaction-stage-count.sh"
sed -n '/^transaction_stage_count() {$/,/^}$/p' "$inspector" >"$function_source"
[[ "$(grep -Fxc 'transaction_stage_count() {' "$function_source")" -eq 1 ]]
# shellcheck disable=SC1090
source "$function_source"
printf 'action_18b_a_retry_regression_assertion_exact_production_function_loaded=true\n'

readonly fixture_run="$regression_root/fixture/run"
readonly fixture_tmp="$regression_root/fixture/tmp"
readonly own_work_directory="$fixture_tmp/caddy-action18b-a-retry-inspector.self"
install -d -m 0700 "$fixture_run" "$own_work_directory"

[[ "$(transaction_stage_count "$own_work_directory" "$fixture_run" "$fixture_tmp")" -eq 0 ]]
printf 'action_18b_a_retry_false_positive_own_work_directory_excluded=true\n'

install -d -m 0700 "$fixture_tmp/unrelated-directory"
[[ "$(transaction_stage_count "$own_work_directory" "$fixture_run" "$fixture_tmp")" -eq 0 ]]
printf 'action_18b_a_retry_false_positive_unrelated_directory_ignored=true\n'

install -d -m 0700 "$fixture_tmp/caddy-action18b-transaction.leftover"
[[ "$(transaction_stage_count "$own_work_directory" "$fixture_run" "$fixture_tmp")" -eq 1 ]]
printf 'action_18b_a_retry_false_negative_additional_transaction_residue_rejected=true\n'

install -d -m 0700 "$fixture_run/.caddy-sync-receiver-v2.leftover"
[[ "$(transaction_stage_count "$own_work_directory" "$fixture_run" "$fixture_tmp")" -eq 2 ]]
printf 'action_18b_a_retry_false_negative_additional_protocol_v2_residue_rejected=true\n'

# The literal production source must retain these unexpanded shell variables.
# shellcheck disable=SC2016
[[ "$(grep -Fxc '        ! -path "$excluded_path" -printf . 2>/dev/null | wc -c' "$inspector")" -eq 1 ]]
# shellcheck disable=SC2016
[[ "$(grep -Fxc 'action18b_stage_count=$(transaction_stage_count "$work_directory" /run /tmp)' "$inspector")" -eq 1 ]]
printf 'action_18b_a_retry_regression_assertion_exact_self_exclusion_only=true\n'

printf 'action_18b_a_retry_production_path_network_contact=false\n'
printf 'action_18b_a_retry_node_a_postfailure_regression_complete=true\n'
