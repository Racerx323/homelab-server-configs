#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-node-b-caddy-health-group-action20g.sh
readonly outer=$caddy_root/scripts/run-node-b-caddy-health-group-correction-action20g-outer.sh
readonly regression=$test_directory/action20g-node-b-health-group-definition-regression.sh
readonly collision=$test_directory/check-shell-readonly-local-collisions-v2.sh

gate() {
    local action20g_focused_label=$1
    shift
    if "$@"; then
        printf 'action_20g_focused_%s=true\n' "$action20g_focused_label"
        return 0
    fi
    printf 'action_20g_focused_%s=false\n' "$action20g_focused_label" >&2
    return 1
}
pattern_count() {
    local action20g_count_pattern=$1
    local action20g_count_path
    local action20g_count_total=0

    shift
    for action20g_count_path in "$@"; do
        action20g_count_total=$((action20g_count_total + $(grep -Ec \
            "$action20g_count_pattern" "$action20g_count_path" || true)))
    done
    printf '%s\n' "$action20g_count_total"
}
gate syntax /bin/bash -n "$builder" "$outer" "$regression" "$0"
gate shellcheck shellcheck "$builder" "$outer" "$regression" "$0"
gate canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check "$builder" "$outer" "$regression" "$0"
gate collision_policy /bin/bash "$collision" "$builder" "$outer" "$regression" "$0"
gate conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
gate output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
gate regression /bin/bash "$regression"
gate outer_self_test /bin/bash "$outer" --self-test
gate complete_suite_bypassed test "$(pattern_count \
    'tests/run\.sh|tests/integration\.sh|complete_suite' \
    "$builder" "$outer" "$regression")" -eq 0
printf 'action_20g_focused_node_contact=false\n'
printf 'action_20g_focused_node_b_activation=false\n'
printf 'action_20g_focused_complete=true\n'
