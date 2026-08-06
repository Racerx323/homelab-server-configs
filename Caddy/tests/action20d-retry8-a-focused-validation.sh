#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly diagnostic=$caddy_root/scripts/diagnose-node-a-caddy-managed-context-action20d-retry8-a.sh
readonly runner=$caddy_root/scripts/run-node-a-caddy-managed-context-action20d-retry8-a.sh
readonly outer=$caddy_root/scripts/run-node-a-caddy-managed-context-action20d-retry8-a-outer.sh
readonly regression=$script_directory/action20d-retry8-a-managed-context-regression.sh
readonly collision=$script_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$script_directory/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$script_directory/transaction-output-evidence-policy-regression.sh
readonly outer_policy=$script_directory/outer-local-gate-label-policy-regression.sh

run_validation() {
    local focused_validation_label=$1

    shift
    if "$@"; then
        printf 'action_20d_retry8_a_focused_%s=true\n' "$focused_validation_label"
        return 0
    fi
    printf 'action_20d_retry8_a_focused_%s=false\n' "$focused_validation_label" >&2
    return 1
}
hash_exact() {
    local focused_expected_hash=$1
    local focused_file=$2

    [[ "$(sha256sum "$focused_file" | awk '{ print $1 }')" = "$focused_expected_hash" ]] || return 1
}
complete_suite_dependency_absent() {
    ! grep -Eq 'complete_suite|tests/run\.sh|tests/integration\.sh|correction_boundary' \
        "$outer" "$regression" || return 1
}
no_live_path_in_definition() {
    # This is an intentional literal source assertion.
    # shellcheck disable=SC2016
    ! grep -Eq '^[[:space:]]*/bin/bash[[:space:]]+"?\$outer"?([[:space:]]|$)' \
        "$0" || return 1
    ! grep -Eq '^[[:space:]]*(ssh|scp|rsync)[[:space:]]' "$regression" "$0" || return 1
}

run_validation diagnostic_exact hash_exact \
    ea1aa14bbf8721a8c4b369a7887b6cee512fbaf39197ebe40689cebfbd5c1490 \
    "$diagnostic"
run_validation runner_exact hash_exact \
    fd829bc9c391fb5c520cc923a5149ac81938c19a1983d6ce803d9f7c25a4ebf7 \
    "$runner"
run_validation regression_exact hash_exact \
    e228d671f20d28c0a1c2900f2db1b8e12f54ccb21310d9319c3ea64193206329 \
    "$regression"
run_validation outer_exact hash_exact \
    20393d5081a694db725221df7bbb219a72e298b04a64c5ca5fc59aed2b6b83b9 \
    "$outer"
run_validation syntax /bin/bash -n "$diagnostic" "$runner" "$outer" \
    "$regression" "$0"
run_validation shellcheck shellcheck "$diagnostic" "$runner" "$outer" \
    "$regression" "$0"
run_validation canonical_format /bin/bash "$script_directory/shfmt-canonical.sh" \
    --check "$diagnostic" "$runner" "$outer" "$regression" "$0"
run_validation collision_policy /bin/bash "$collision" "$diagnostic" "$runner" \
    "$outer" "$regression" "$0"
run_validation conditional_policy /bin/bash "$conditional"
run_validation output_evidence_policy /bin/bash "$output_evidence"
run_validation production_regression /bin/bash "$regression"
run_validation outer_self_test /bin/bash "$outer" --self-test
run_validation outer_label_policy /bin/bash "$outer_policy" --runner "$outer"
run_validation complete_suite_bypassed complete_suite_dependency_absent
run_validation no_live_execution_path no_live_path_in_definition

printf 'action_20d_retry8_a_focused_complete_suite_invoked=false\n'
printf 'action_20d_retry8_a_focused_podman_invoked=false\n'
printf 'action_20d_retry8_a_focused_node_contact=false\n'
printf 'action_20d_retry8_a_focused_health_helper_invoked=false\n'
printf 'action_20d_retry8_a_focused_notification_invoked=false\n'
printf 'action_20d_retry8_a_focused_keepalived_mutations=false\n'
printf 'action_20d_retry8_a_focused_vrrp_mutations=false\n'
printf 'action_20d_retry8_a_focused_vip_mutations=false\n'
printf 'action_20d_retry8_a_focused_validation_complete=true\n'
