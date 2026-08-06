#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly boundary=$script_directory/action17q-umask-stable-boundary.sh
readonly regression=$script_directory/action17q-umask-stable-boundary-regression.sh
readonly collision=$script_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$script_directory/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$script_directory/transaction-output-evidence-policy-regression.sh

run_focused_gate() {
    local focused_gate_label=$1

    shift
    if "$@"; then
        printf 'action_20d_retry2_b_focused_gate_%s=true\n' "$focused_gate_label"
        return 0
    fi
    printf 'action_20d_retry2_b_focused_gate_%s=false\n' "$focused_gate_label" >&2
    return 1
}

run_focused_gate syntax /bin/bash -n "$boundary" "$regression" "$0"
run_focused_gate shellcheck shellcheck "$boundary" "$regression" "$0"
run_focused_gate formatting "$script_directory/shfmt-canonical.sh" \
    --check "$boundary" "$regression" "$0"
run_focused_gate collision /bin/bash "$collision" "$boundary" "$regression" "$0"
run_focused_gate conditional /bin/bash "$conditional"
run_focused_gate output_evidence /bin/bash "$output_evidence"
run_focused_gate boundary_self /bin/bash "$boundary" --self-test
run_focused_gate boundary_source /bin/bash "$boundary" --source-test
run_focused_gate boundary_contract /bin/bash "$boundary" --contract-test
run_focused_gate regression /bin/bash "$regression"

if grep -Eq '^[[:space:]]*(podman|ssh|scp|rsync)([[:space:]]|$)' \
    "$boundary" "$regression"; then
    printf 'Action 20d-retry2-b contains a prohibited external command.\n' >&2
    exit 1
fi
printf 'action_20d_retry2_b_focused_node_contact=false\n'
printf 'action_20d_retry2_b_focused_podman_invoked=false\n'
printf 'action_20d_retry2_b_focused_readiness_invoked=false\n'
printf 'action_20d_retry2_b_focused_activation_invoked=false\n'
printf 'action_20d_retry2_b_focused_complete=true\n'
