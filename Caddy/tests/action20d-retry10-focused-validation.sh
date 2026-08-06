#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly outer=$caddy_root/scripts/run-node-a-caddy-vrrp-activation-action20d-retry10-outer.sh
readonly regression=$script_directory/action20d-retry10-activation-boundary-regression.sh
readonly health_baseline_outer=$caddy_root/scripts/run-node-a-caddy-health-group-postinstall-action20f-a-outer.sh
readonly readiness_probe=$caddy_root/scripts/inspect-dual-node-caddy-readiness-action20d-retry10.sh
readonly readiness_outer=$caddy_root/scripts/run-dual-node-caddy-readiness-action20d-retry10.sh
readonly activation_outer=$caddy_root/scripts/run-node-a-caddy-vrrp-activation-action20d-retry10.sh
readonly transaction=$caddy_root/scripts/activate-node-a-caddy-vrrp-action20d-retry10.sh
readonly collision=$script_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$script_directory/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$script_directory/transaction-output-evidence-policy-regression.sh

run_validation() {
    local retry10_focused_label=$1

    shift
    if "$@"; then
        printf 'action_20d_retry10_focused_%s=true\n' "$retry10_focused_label"
        return 0
    fi
    printf 'action_20d_retry10_focused_%s=false\n' "$retry10_focused_label" >&2
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
    "$transaction" "$readiness_probe" "$readiness_outer" "$0"
run_validation shellcheck shellcheck "$outer" "$regression" "$activation_outer" \
    "$transaction" "$readiness_probe" "$readiness_outer" "$0"
run_validation canonical_format /bin/bash "$script_directory/shfmt-canonical.sh" \
    --check "$outer" "$regression" "$activation_outer" "$transaction" \
    "$readiness_probe" "$readiness_outer" "$0"
run_validation collision_policy /bin/bash "$collision" "$outer" "$regression" \
    "$activation_outer" "$transaction" "$readiness_probe" "$readiness_outer" "$0"
run_validation conditional_policy /bin/bash "$conditional"
run_validation output_evidence_policy /bin/bash "$output_evidence"
run_validation complete_suite_bypassed complete_suite_dependency_absent
run_validation health_baseline_outer_immutable hash_exact \
    a4defbeab49958ecaadf1c2e34c259a847ecf0cc5b9a86d359da2c210d8b68c9 \
    "$health_baseline_outer"
run_validation readiness_probe_exact hash_exact \
    7f448b968df5c96feb11e5ca8d0d0cc738b1019edfa61a32ebde4c9c02ea98c0 \
    "$readiness_probe"
run_validation readiness_outer_exact hash_exact \
    ea5b99cb764ff444500bea43efac7c783e20c5d626ed8b594c02f5c71ea328c3 \
    "$readiness_outer"
run_validation activation_outer_exact hash_exact \
    30c297807ed7f0fb48e41c5c653f3c4168b2aa5a05053162c9ece58ef87a88d4 \
    "$activation_outer"
run_validation transaction_exact hash_exact \
    ac8a71333493c28735603bcc9ad74d8dbd4802a2b1b425b4bf4f1c40ce6c04d6 \
    "$transaction"
run_validation regression_exact hash_exact \
    5247599be6f8b60f81e89e78f33e2397c6da2738f77ac2df8a94277610d82f61 \
    "$regression"
run_validation outer_exact hash_exact \
    0bf76de0c4f170b72338d7f7ec2627b7004361c0a59afeab7f410daa4747114c \
    "$outer"
run_validation production_boundary_regression /bin/bash "$regression"

if grep -Eq '^[[:space:]]*(podman|ssh|scp|rsync)([[:space:]]|$)' \
    "$outer" "$regression" "$0"; then
    printf 'Action 20d retry10 focused definition contains a direct prohibited command.\n' >&2
    exit 1
fi
printf 'action_20d_retry10_focused_complete_suite_invoked=false\n'
printf 'action_20d_retry10_focused_podman_invoked=false\n'
printf 'action_20d_retry10_focused_node_contact=false\n'
printf 'action_20d_retry10_focused_readiness_invoked=false\n'
printf 'action_20d_retry10_focused_activation_invoked=false\n'
printf 'action_20d_retry10_focused_config_test_invoked=false\n'
printf 'action_20d_retry10_focused_node_b_contact=false\n'
printf 'action_20d_retry10_focused_validation_complete=true\n'
