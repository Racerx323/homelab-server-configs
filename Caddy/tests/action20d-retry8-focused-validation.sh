#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly outer=$caddy_root/scripts/run-node-a-caddy-vrrp-activation-action20d-retry8-outer.sh
readonly regression=$script_directory/action20d-retry8-activation-boundary-regression.sh
readonly validation_outer=$caddy_root/scripts/run-node-a-caddy-health-action20d-retry7-a-retry-outer.sh
readonly readiness_outer=$caddy_root/scripts/run-dual-node-caddy-notifier-context-action20d-c-retry-outer.sh
readonly activation_outer=$caddy_root/scripts/run-node-a-caddy-vrrp-activation-action20d-retry8.sh
readonly transaction=$caddy_root/scripts/activate-node-a-caddy-vrrp-action20d-retry8.sh
readonly collision=$script_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$script_directory/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$script_directory/transaction-output-evidence-policy-regression.sh
readonly outer_policy=$script_directory/outer-local-gate-label-policy-regression.sh

run_validation() {
    local retry8_focused_label=$1

    shift
    if "$@"; then
        printf 'action_20d_retry8_focused_%s=true\n' "$retry8_focused_label"
        return 0
    fi
    printf 'action_20d_retry8_focused_%s=false\n' "$retry8_focused_label" >&2
    return 1
}

hash_exact() {
    local expected_validation_hash=$1
    local inspected_validation_file=$2

    [[ "$(sha256sum "$inspected_validation_file" | awk '{ print $1 }')" = "$expected_validation_hash" ]] || return 1
    return 0
}

complete_suite_dependency_absent() {
    ! grep -Eq 'complete_suite|tests/run\.sh|tests/integration\.sh|correction_boundary' \
        "$outer" || return 1
    return 0
}

run_validation syntax /bin/bash -n "$outer" "$regression" "$activation_outer" \
    "$transaction" "$0"
run_validation shellcheck shellcheck "$outer" "$regression" "$activation_outer" \
    "$transaction" "$0"
run_validation canonical_format /bin/bash "$script_directory/shfmt-canonical.sh" \
    --check "$outer" "$regression" "$activation_outer" "$transaction" "$0"
run_validation collision_policy /bin/bash "$collision" "$outer" "$regression" \
    "$activation_outer" "$transaction" "$0"
run_validation conditional_policy /bin/bash "$conditional"
run_validation output_evidence_policy /bin/bash "$output_evidence"
run_validation complete_suite_bypassed complete_suite_dependency_absent
run_validation validation_outer_immutable hash_exact \
    30830a62bbb03e048b9edd79eb20a5d3b3229c1284b9776aa8966cbc8f82913a \
    "$validation_outer"
run_validation readiness_outer_immutable hash_exact \
    b7e1db77b4889a62d782a0331922f326edd73c87e13a42952441ad7fe9ce9f20 \
    "$readiness_outer"
run_validation activation_outer_exact hash_exact \
    fda34fd7c00ea88539132a29d39d553e4c203bc08cfb0067e7c6c111a130361a \
    "$activation_outer"
run_validation transaction_exact hash_exact \
    2ecf596c4ba0ced6450e96f27068f4e2b17a7bd03e6902906504446fe82a5ca3 \
    "$transaction"
run_validation regression_exact hash_exact \
    755e34e3c5742dfb3b893792972f7df690a8389c742cbc76feae47dc45e17b33 \
    "$regression"
run_validation outer_exact hash_exact \
    1ff2fe0053fe39130777a9c212abbcb40d3adcbee7c0d77d59e87f1c951e3099 \
    "$outer"
run_validation production_boundary_regression /bin/bash "$regression"
run_validation outer_self_test /bin/bash "$outer" --self-test
run_validation outer_label_policy /bin/bash "$outer_policy" --runner "$outer"

if grep -Eq '^[[:space:]]*(podman|ssh|scp|rsync)([[:space:]]|$)' \
    "$outer" "$regression" "$0"; then
    printf 'Action 20d retry8 focused definition contains a direct prohibited command.\n' >&2
    exit 1
fi
printf 'action_20d_retry8_focused_complete_suite_invoked=false\n'
printf 'action_20d_retry8_focused_podman_invoked=false\n'
printf 'action_20d_retry8_focused_node_contact=false\n'
printf 'action_20d_retry8_focused_readiness_invoked=false\n'
printf 'action_20d_retry8_focused_activation_invoked=false\n'
printf 'action_20d_retry8_focused_config_test_invoked=false\n'
printf 'action_20d_retry8_focused_node_b_contact=false\n'
printf 'action_20d_retry8_focused_validation_complete=true\n'
