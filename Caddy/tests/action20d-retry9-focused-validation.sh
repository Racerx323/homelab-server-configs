#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly outer=$caddy_root/scripts/run-node-a-caddy-vrrp-activation-action20d-retry9-outer.sh
readonly regression=$script_directory/action20d-retry9-activation-boundary-regression.sh
readonly health_baseline_outer=$caddy_root/scripts/run-node-a-caddy-health-group-postinstall-action20f-a-outer.sh
readonly readiness_probe=$caddy_root/scripts/inspect-dual-node-caddy-readiness-action20d-retry9.sh
readonly readiness_outer=$caddy_root/scripts/run-dual-node-caddy-readiness-action20d-retry9.sh
readonly activation_outer=$caddy_root/scripts/run-node-a-caddy-vrrp-activation-action20d-retry9.sh
readonly transaction=$caddy_root/scripts/activate-node-a-caddy-vrrp-action20d-retry9.sh
readonly collision=$script_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$script_directory/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$script_directory/transaction-output-evidence-policy-regression.sh

run_validation() {
    local retry9_focused_label=$1

    shift
    if "$@"; then
        printf 'action_20d_retry9_focused_%s=true\n' "$retry9_focused_label"
        return 0
    fi
    printf 'action_20d_retry9_focused_%s=false\n' "$retry9_focused_label" >&2
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
    0acc886c5317179571fdc0947e69f19fa57f3aa34f031ab5788727cdfee4750e \
    "$readiness_probe"
run_validation readiness_outer_exact hash_exact \
    c62dd274363107d45a0cbe4735c6da590f20a15455c9243d4c37e65f71ba1792 \
    "$readiness_outer"
run_validation activation_outer_exact hash_exact \
    6209d5e412280e26e1a86b9d689d5ece45c7dfec61162a56aed7a5db6027e5a4 \
    "$activation_outer"
run_validation transaction_exact hash_exact \
    add4ea40cf77e82b4088df2944d157495b602c5e5425d181f24281dba9503cb5 \
    "$transaction"
run_validation regression_exact hash_exact \
    ebbf26d44c418674ae8d13a128071770b4a27f9711f12c5c9fbbdf237a38f189 \
    "$regression"
run_validation outer_exact hash_exact \
    12a9b575fccf982a846659d955364d777fbf40b82efda069f5e15cdf38b9c786 \
    "$outer"
run_validation production_boundary_regression /bin/bash "$regression"

if grep -Eq '^[[:space:]]*(podman|ssh|scp|rsync)([[:space:]]|$)' \
    "$outer" "$regression" "$0"; then
    printf 'Action 20d retry9 focused definition contains a direct prohibited command.\n' >&2
    exit 1
fi
printf 'action_20d_retry9_focused_complete_suite_invoked=false\n'
printf 'action_20d_retry9_focused_podman_invoked=false\n'
printf 'action_20d_retry9_focused_node_contact=false\n'
printf 'action_20d_retry9_focused_readiness_invoked=false\n'
printf 'action_20d_retry9_focused_activation_invoked=false\n'
printf 'action_20d_retry9_focused_config_test_invoked=false\n'
printf 'action_20d_retry9_focused_node_b_contact=false\n'
printf 'action_20d_retry9_focused_validation_complete=true\n'
