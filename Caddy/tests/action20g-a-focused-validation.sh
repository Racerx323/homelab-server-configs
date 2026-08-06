#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20g_a_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-node-b-caddy-health-group-postinstall-action20g-a.sh
readonly runner=$caddy_root/scripts/run-node-b-caddy-health-group-postinstall-action20g-a.sh
readonly outer=$caddy_root/scripts/run-node-b-caddy-health-group-postinstall-action20g-a-outer.sh
readonly regression=$test_directory/action20g-a-node-b-caddy-health-group-postinstall-regression.sh
readonly focused_self=$test_directory/action20g-a-focused-validation.sh
readonly collision=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$test_directory/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$test_directory/transaction-output-evidence-policy-regression.sh
readonly transcript=$test_directory/transcript-contract-ratchet-policy-regression.sh
readonly multifile_grep=$test_directory/multifile-grep-count-policy.sh
readonly portable_awk=$test_directory/portable-awk-policy.sh
readonly outer_labels=$test_directory/outer-local-gate-label-policy-regression.sh
readonly accepted_live_hash=$test_directory/accepted-live-hash-policy.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
run_validation() {
    local action20ga_focused_label=$1

    shift
    if "$@"; then
        printf '%s_%s=true\n' "$prefix" "$action20ga_focused_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$action20ga_focused_label" >&2
    return 1
}
index_modes_exact() {
    local action20ga_mode_path

    for action20ga_mode_path in "$inspector" "$runner" "$outer" "$regression" "$focused_self"; do
        [[ "$(stat -c '%a' "$action20ga_mode_path")" = 755 ]] || return 1
        [[ "$(git -C "$caddy_root/.." ls-files -s -- \
            "Caddy/${action20ga_mode_path#"$caddy_root/"}" | awk '{ print $1 }')" = 100755 ]] || return 1
    done
}
complete_suite_absent() {
    ! grep -Eq 'tests/run\.sh|tests/integration\.sh|complete_suite' \
        "$inspector" "$runner" "$outer" "$regression"
}
live_execution_absent() {
    # The dollar-prefixed expression is literal focused-validator source.
    # shellcheck disable=SC2016
    ! grep -Fqx '/bin/bash "$outer"' "$focused_self"
}
node_b_activation_absent() {
    ! grep -Eq \
        'systemctl[[:space:]]+(reload|restart|start)[[:space:]]+keepalived|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|replace)' \
        "$inspector" "$runner" "$outer" "$regression"
}

run_validation syntax /bin/bash -n "$inspector" "$runner" "$outer" "$regression" "$focused_self"
run_validation shellcheck shellcheck "$inspector" "$runner" "$outer" "$regression" "$focused_self"
run_validation canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$inspector" "$runner" "$outer" "$regression" "$focused_self"
run_validation executable_index_modes index_modes_exact
run_validation collision_policy /bin/bash "$collision" \
    "$inspector" "$runner" "$outer" "$regression" "$focused_self"
run_validation conditional_policy /bin/bash "$conditional"
run_validation output_evidence_policy /bin/bash "$output_evidence"
run_validation transcript_policy /bin/bash "$transcript"
run_validation multifile_grep_policy /bin/bash "$multifile_grep" --check \
    "$inspector" "$runner" "$outer" "$regression" "$focused_self"
run_validation portable_awk_policy /bin/bash "$portable_awk" --check
run_validation accepted_live_hash_policy /bin/bash "$accepted_live_hash" --check
run_validation inspector_exact test "$(file_hash "$inspector")" = \
    57114c6e4a73af7df3ac7b0fa024259a27f9cab3281997b2f67396b73008a9e2
run_validation runner_exact test "$(file_hash "$runner")" = \
    47ff5e804c1f7558118e4e7a54f461ae80c5e1f53bc3582f07dc4a670bafc798
run_validation regression_exact test "$(file_hash "$regression")" = \
    48bf46ca0133fd4f48c426395476259577a6d6f7507273272011ef13c2bf4f96
run_validation outer_exact test "$(file_hash "$outer")" = \
    e354b32749698c83cfe432b1684a384117e134e52fd2341bd7c201431a1e2e4a
run_validation inspector_self_test /bin/bash "$inspector" --self-test
run_validation runner_self_test /bin/bash "$runner" --self-test
run_validation runner_contract_test /bin/bash "$runner" --contract-test
run_validation regression /bin/bash "$regression"
run_validation outer_self_test /bin/bash "$outer" --self-test
run_validation outer_label_policy /bin/bash "$outer_labels" --runner "$outer"
run_validation complete_suite_bypassed complete_suite_absent
run_validation live_execution_absent live_execution_absent
run_validation node_b_activation_absent node_b_activation_absent
printf '%s_node_contact=false\n' "$prefix"
printf '%s_node_b_activation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
