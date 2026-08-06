#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly outer=$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-retry4-outer.sh
readonly regression=$script_directory/action20d-retry4-activation-boundary-regression.sh
readonly complete_suite=$script_directory/run.sh
readonly integration_suite=$script_directory/integration.sh
readonly correction_boundary=$script_directory/action20d-retry3-a-retry-stale-suite-hash-boundary.sh
readonly readiness_outer=$caddy_root/scripts/run-dual-node-caddy-notifier-context-action20d-c-retry-outer.sh
readonly activation_outer=$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-retry-outer.sh
readonly collision=$script_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$script_directory/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$script_directory/transaction-output-evidence-policy-regression.sh
readonly outer_policy=$script_directory/outer-local-gate-label-policy-regression.sh

run_validation() {
    local retry4_focused_label=$1

    shift
    if "$@"; then
        printf 'action_20d_retry4_focused_%s=true\n' "$retry4_focused_label"
        return 0
    fi
    printf 'action_20d_retry4_focused_%s=false\n' "$retry4_focused_label" >&2
    return 1
}

hash_exact() {
    local expected_validation_hash=$1
    local inspected_validation_file=$2

    [[ "$(sha256sum "$inspected_validation_file" | awk '{ print $1 }')" = "$expected_validation_hash" ]] || return 1
    return 0
}

run_validation syntax /bin/bash -n "$outer" "$regression" "$0"
run_validation shellcheck shellcheck "$outer" "$regression" "$0"
run_validation canonical_format /bin/bash "$script_directory/shfmt-canonical.sh" \
    --check "$outer" "$regression" "$0"
run_validation collision_policy /bin/bash "$collision" "$outer" "$regression" "$0"
run_validation conditional_policy /bin/bash "$conditional"
run_validation output_evidence_policy /bin/bash "$output_evidence"
run_validation complete_suite_exact hash_exact \
    96796968d68081aa183cb8142c952a0378e8653383a74dfe13038f7e771efd8c \
    "$complete_suite"
run_validation integration_suite_exact hash_exact \
    f3da2b630e909e85acbc05fceccd25ca6f418b44d0bfa4e485ca7f04c4447727 \
    "$integration_suite"
run_validation correction_boundary_exact hash_exact \
    82f02ae0e98aaff984c3a377857c235992d8fdbb6db87c33f6af799aa98d491e \
    "$correction_boundary"
run_validation readiness_outer_immutable hash_exact \
    b7e1db77b4889a62d782a0331922f326edd73c87e13a42952441ad7fe9ce9f20 \
    "$readiness_outer"
run_validation activation_outer_immutable hash_exact \
    085eff6386210d36a97682b86c90670b4b42cc249132b4f57dcae0ca5b7018d5 \
    "$activation_outer"
run_validation regression_exact hash_exact \
    a3782acd9bf546118a1d2e69a88c47cf877066593fd6d2067b463d07ae306be3 \
    "$regression"
run_validation outer_exact hash_exact \
    b84ec50826412421d7158b4593428da02c077902bc63561ebdac20b77d187393 \
    "$outer"
run_validation production_boundary_regression /bin/bash "$regression"
run_validation outer_self_test /bin/bash "$outer" --self-test
run_validation outer_label_policy /bin/bash "$outer_policy" --runner "$outer"

if grep -Eq '^[[:space:]]*(podman|ssh|scp|rsync)([[:space:]]|$)' \
    "$outer" "$regression" "$0"; then
    printf 'Action 20d retry4 focused definition contains a direct prohibited command.\n' >&2
    exit 1
fi
printf 'action_20d_retry4_focused_complete_suite_invoked=false\n'
printf 'action_20d_retry4_focused_podman_invoked=false\n'
printf 'action_20d_retry4_focused_node_contact=false\n'
printf 'action_20d_retry4_focused_readiness_invoked=false\n'
printf 'action_20d_retry4_focused_activation_invoked=false\n'
printf 'action_20d_retry4_focused_validation_complete=true\n'
