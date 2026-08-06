#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly boundary=$script_directory/action20d-retry3-a-stale-suite-hash-boundary.sh
readonly regression=$script_directory/action20d-retry3-a-stale-suite-hash-regression.sh
readonly retry2_validator=$script_directory/action20d-retry2-focused-validation.sh
readonly retry2_outer=$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-retry2-outer.sh
readonly retry3_validator=$script_directory/action20d-retry3-focused-validation.sh
readonly retry3_outer=$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-retry3-outer.sh
readonly collision=$script_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$script_directory/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$script_directory/transaction-output-evidence-policy-regression.sh

run_focused_assertion() {
    local focused_assertion_label=$1

    shift
    if "$@"; then
        printf 'action_20d_retry3_a_focused_%s=true\n' "$focused_assertion_label"
        return 0
    fi
    printf 'action_20d_retry3_a_focused_%s=false\n' \
        "$focused_assertion_label" >&2
    return 1
}

hash_exact() {
    local expected_focused_hash=$1
    local inspected_focused_path=$2

    [[ "$(sha256sum "$inspected_focused_path" | awk '{ print $1 }')" = "$expected_focused_hash" ]]
}

suite_wiring_exact() {
    local inspected_suite_path=$1

    # Dollar-prefixed names below are literal suite source.
    # shellcheck disable=SC2016
    [[ "$(grep -Fxc '"$caddy_root/tests/action20d-retry3-a-stale-suite-hash-boundary.sh"' "$inspected_suite_path")" -eq 1 ]] || return 1
    # shellcheck disable=SC2016
    [[ "$(grep -Fxc '"$caddy_root/tests/action20d-retry3-a-focused-validation.sh"' "$inspected_suite_path")" -eq 1 ]] || return 1
    # shellcheck disable=SC2016
    ! grep -Fqx '"$caddy_root/tests/action20d-retry2-focused-validation.sh"' "$inspected_suite_path" || return 1
    # shellcheck disable=SC2016
    ! grep -Fqx '"$caddy_root/tests/action20d-retry3-focused-validation.sh"' "$inspected_suite_path"
}

run_focused_assertion syntax /bin/bash -n "$boundary" "$regression" "$0"
run_focused_assertion shellcheck shellcheck "$boundary" "$regression" "$0"
run_focused_assertion canonical_format /bin/bash "$script_directory/shfmt-canonical.sh" \
    --check "$boundary" "$regression" "$0"
run_focused_assertion collision_policy /bin/bash "$collision" "$boundary" "$regression" "$0"
run_focused_assertion conditional_policy /bin/bash "$conditional"
run_focused_assertion output_evidence_policy /bin/bash "$output_evidence"
run_focused_assertion retry2_validator_immutable hash_exact \
    3a5ddbcb85b307e61511fe8a9d69752df28b0c3650bd842bc7c1036f847e93df \
    "$retry2_validator"
run_focused_assertion retry2_outer_immutable hash_exact \
    6d89fa6fff1ad1bcdb3d627a877e2e34a01c1096f770a7342ad13adeb116b9e5 \
    "$retry2_outer"
run_focused_assertion retry3_validator_immutable hash_exact \
    5d4cefc8f6c79067dd312e7b5f05da1b489f5f690f8ef7100113c9f321d89fa3 \
    "$retry3_validator"
run_focused_assertion retry3_outer_immutable hash_exact \
    0f378ae8638374b7a88a8b64ba93bc3f65bebe925bc5802dbb108393fe4abe7a \
    "$retry3_outer"
run_focused_assertion host_suite_wiring suite_wiring_exact "$script_directory/run.sh"
run_focused_assertion integration_suite_wiring suite_wiring_exact "$script_directory/integration.sh"
run_focused_assertion boundary_self_test /bin/bash "$boundary" --self-test
run_focused_assertion boundary_source_test /bin/bash "$boundary" --source-test
run_focused_assertion boundary_contract_test /bin/bash "$boundary" --contract-test
run_focused_assertion regression /bin/bash "$regression"

if grep -Eq '^[[:space:]]*(podman|ssh|scp|rsync)([[:space:]]|$)' \
    "$boundary" "$regression" "$0"; then
    printf 'Action 20d retry3-a contains a direct prohibited command.\n' >&2
    exit 1
fi
printf 'action_20d_retry3_a_focused_historical_artifacts_modified=false\n'
printf 'action_20d_retry3_a_focused_complete_suite_invoked=false\n'
printf 'action_20d_retry3_a_focused_podman_invoked=false\n'
printf 'action_20d_retry3_a_focused_node_contact=false\n'
printf 'action_20d_retry3_a_focused_readiness_invoked=false\n'
printf 'action_20d_retry3_a_focused_activation_invoked=false\n'
printf 'action_20d_retry3_a_focused_live_mutations=false\n'
printf 'action_20d_retry3_a_focused_validation_complete=true\n'
