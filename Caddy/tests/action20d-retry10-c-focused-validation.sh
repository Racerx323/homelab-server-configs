#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly diagnostic=$caddy_root/scripts/inspect-node-a-caddy-health-timing-action20d-retry10-c.sh
readonly runner=$caddy_root/scripts/run-node-a-caddy-health-timing-action20d-retry10-c.sh
readonly outer=$caddy_root/scripts/run-node-a-caddy-health-timing-action20d-retry10-c-outer.sh
readonly regression=$test_directory/action20d-retry10-c-health-timing-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
gate() {
    local timing_focused_label=$1

    shift
    if "$@"; then
        printf 'action_20d_retry10_c_focused_%s=true\n' "$timing_focused_label"
        return 0
    fi
    printf 'action_20d_retry10_c_focused_%s=false\n' "$timing_focused_label" >&2
    return 1
}
hash_exact() { [[ "$(file_hash "$2")" = "$1" ]]; }
complete_suite_bypassed() {
    ! grep -Eq 'Caddy/tests/(run|integration)\.sh|tests/(run|integration)\.sh' \
        "$diagnostic" "$runner" "$outer" "$regression"
}
no_live_execution_path() {
    # Dollar-prefixed expressions are intentional literal source checks.
    # shellcheck disable=SC2016
    ! grep -Eq '^[[:space:]]*/bin/bash[[:space:]]+"?\$outer"?([[:space:]]|$)' "$0" || return 1
    ! grep -Eq '^[[:space:]]*(ssh|scp|rsync)[[:space:]]' "$regression" "$0"
}

gate diagnostic_hash hash_exact \
    6d71149eaecbb629be2064d2eeea31b7a6416276568e884633173978b0819034 "$diagnostic"
gate runner_hash hash_exact \
    d0ae53fe95b29f78c2a1997c3e80a94abf524e5686c2f012a677f2be0f35a751 "$runner"
gate regression_hash hash_exact \
    e6e1ee10c674148c14e402bc571b5c0bc3f04ec261188d29e43156b97e6298a7 "$regression"
gate outer_hash hash_exact \
    390586f1c809379bb2d773b4d1cb6d8827e8f419105996c8dc8e50ef1e5079b0 "$outer"
gate syntax /bin/bash -n "$diagnostic" "$runner" "$outer" "$regression" "$0"
gate shellcheck shellcheck "$diagnostic" "$runner" "$outer" "$regression" "$0"
gate canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$diagnostic" "$runner" "$outer" "$regression" "$0"
gate collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$diagnostic" "$runner" "$outer" "$regression" "$0"
gate conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
gate transcript_policy /bin/bash "$test_directory/transcript-contract-ratchet-policy-regression.sh"
gate output_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
gate production_regression /bin/bash "$regression"
gate outer_self_test /bin/bash "$outer" --self-test
gate outer_label_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
gate complete_suite_bypassed complete_suite_bypassed
gate no_live_execution_path no_live_execution_path
printf 'action_20d_retry10_c_focused_node_contact=false\n'
printf 'action_20d_retry10_c_focused_complete_helper_invoked=false\n'
printf 'action_20d_retry10_c_focused_live_mutations=false\n'
printf 'action_20d_retry10_c_focused_complete=true\n'
