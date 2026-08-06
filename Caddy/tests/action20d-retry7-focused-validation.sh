#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly outer=$caddy_root/scripts/run-node-a-caddy-vrrp-activation-action20d-retry7-outer.sh
readonly regression=$script_directory/action20d-retry7-activation-boundary-regression.sh
readonly readiness_outer=$caddy_root/scripts/run-dual-node-caddy-notifier-context-action20d-c-retry-outer.sh
readonly activation_outer=$caddy_root/scripts/run-node-a-caddy-vrrp-activation-action20d-retry7.sh
readonly collision=$script_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$script_directory/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$script_directory/transaction-output-evidence-policy-regression.sh
readonly outer_policy=$script_directory/outer-local-gate-label-policy-regression.sh

run_validation() {
    local retry7_focused_label=$1

    shift
    if "$@"; then
        printf 'action_20d_retry7_focused_%s=true\n' "$retry7_focused_label"
        return 0
    fi
    printf 'action_20d_retry7_focused_%s=false\n' "$retry7_focused_label" >&2
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

run_validation syntax /bin/bash -n "$outer" "$regression" "$0"
run_validation shellcheck shellcheck "$outer" "$regression" "$0"
run_validation canonical_format /bin/bash "$script_directory/shfmt-canonical.sh" \
    --check "$outer" "$regression" "$0"
run_validation collision_policy /bin/bash "$collision" "$outer" "$regression" "$0"
run_validation conditional_policy /bin/bash "$conditional"
run_validation output_evidence_policy /bin/bash "$output_evidence"
run_validation complete_suite_bypassed complete_suite_dependency_absent
run_validation readiness_outer_immutable hash_exact \
    b7e1db77b4889a62d782a0331922f326edd73c87e13a42952441ad7fe9ce9f20 \
    "$readiness_outer"
run_validation activation_outer_immutable hash_exact \
    12e1d21ddce53fedc334a5b05b41eb52e86ada242cb698eddd87d8a3937fcb66 \
    "$activation_outer"
run_validation regression_exact hash_exact \
    c9a7997748330a553e5910e22741e3b63e96648932feb08700ad57d7ca2c1a32 \
    "$regression"
run_validation outer_exact hash_exact \
    cf99b26f2266e0b260816f5c4d3f3629f9fe0a6b8fe6810cd72949fc5f780f54 \
    "$outer"
run_validation production_boundary_regression /bin/bash "$regression"
run_validation outer_self_test /bin/bash "$outer" --self-test
run_validation outer_label_policy /bin/bash "$outer_policy" --runner "$outer"

if grep -Eq '^[[:space:]]*(podman|ssh|scp|rsync)([[:space:]]|$)' \
    "$outer" "$regression" "$0"; then
    printf 'Action 20d retry7 focused definition contains a direct prohibited command.\n' >&2
    exit 1
fi
printf 'action_20d_retry7_focused_complete_suite_invoked=false\n'
printf 'action_20d_retry7_focused_podman_invoked=false\n'
printf 'action_20d_retry7_focused_node_contact=false\n'
printf 'action_20d_retry7_focused_readiness_invoked=false\n'
printf 'action_20d_retry7_focused_activation_invoked=false\n'
printf 'action_20d_retry7_focused_config_test_invoked=false\n'
printf 'action_20d_retry7_focused_node_b_contact=false\n'
printf 'action_20d_retry7_focused_validation_complete=true\n'
