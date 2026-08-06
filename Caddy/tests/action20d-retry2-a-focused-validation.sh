#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly outer=$caddy_root/scripts/run-action20d-retry2-suite-boundary-diagnostic-outer.sh
readonly executed_outer=$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-retry2-outer.sh
readonly regression=$script_directory/action20d-retry2-a-suite-boundary-diagnostic-regression.sh
readonly collision=$script_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$script_directory/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$script_directory/transaction-output-evidence-policy-regression.sh
readonly outer_policy=$script_directory/outer-local-gate-label-policy-regression.sh

run_validation() {
    local focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf 'action_20d_retry2_a_focused_%s=true\n' "$focused_label"
        return 0
    fi
    printf 'action_20d_retry2_a_focused_%s=false\n' "$focused_label" >&2
    return 1
}
hash_exact() {
    local expected_hash=$1
    local inspected_file=$2

    [[ "$(sha256sum "$inspected_file" | awk '{ print $1 }')" = "$expected_hash" ]]
}

run_validation syntax /bin/bash -n "$outer" "$regression" "$0"
run_validation shellcheck shellcheck "$outer" "$regression" "$0"
run_validation canonical_format /bin/bash "$script_directory/shfmt-canonical.sh" --check "$outer" "$regression" "$0"
run_validation collision_policy /bin/bash "$collision" "$outer" "$regression" "$0"
run_validation conditional_policy /bin/bash "$conditional"
run_validation output_evidence_policy /bin/bash "$output_evidence"
run_validation executed_outer_immutable hash_exact \
    6d89fa6fff1ad1bcdb3d627a877e2e34a01c1096f770a7342ad13adeb116b9e5 \
    "$executed_outer"
run_validation production_boundary_regression /bin/bash "$regression"
run_validation outer_self_test /bin/bash "$outer" --self-test
run_validation outer_label_policy /bin/bash "$outer_policy" --runner "$outer"
printf 'action_20d_retry2_a_focused_validation_complete=true\n'
