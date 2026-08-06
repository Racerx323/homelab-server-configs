#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20g_retry3_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-node-b-caddy-health-group-action20g-retry3.sh
readonly outer=$caddy_root/scripts/run-node-b-caddy-health-group-correction-action20g-retry3-outer.sh
readonly previous_outer=$caddy_root/scripts/run-node-b-caddy-health-group-correction-action20g-retry2-outer.sh
readonly regression=$test_directory/action20g-retry3-primary-gid-regression.sh
readonly focused_self=$test_directory/action20g-retry3-focused-validation.sh
readonly collision=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$test_directory/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$test_directory/transaction-output-evidence-policy-regression.sh
readonly multifile_grep=$test_directory/multifile-grep-count-policy.sh
readonly portable_awk=$test_directory/portable-awk-policy.sh
readonly outer_labels=$test_directory/outer-local-gate-label-policy-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
run_validation() {
    local action20g_retry3_focused_label=$1

    shift
    if "$@"; then
        printf '%s_%s=true\n' "$prefix" "$action20g_retry3_focused_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$action20g_retry3_focused_label" >&2
    return 1
}
index_modes_exact() {
    local action20g_retry3_mode_path

    for action20g_retry3_mode_path in "$builder" "$outer" "$regression" "$focused_self"; do
        [[ "$(stat -c '%a' "$action20g_retry3_mode_path")" = 755 ]] || return 1
        [[ "$(git -C "$caddy_root/.." ls-files -s -- \
            "Caddy/${action20g_retry3_mode_path#"$caddy_root/"}" | awk '{ print $1 }')" = 100755 ]] || return 1
    done
}
complete_suite_absent() {
    ! grep -Eq 'tests/run\.sh|tests/integration\.sh|complete_suite' \
        "$builder" "$outer" "$regression"
}
live_execution_absent() {
    # The dollar-prefixed expression is literal focused-validator source.
    # shellcheck disable=SC2016
    ! grep -Fqx '/bin/bash "$outer"' "$focused_self"
}
node_b_activation_absent() {
    ! grep -Eq \
        'systemctl[[:space:]]+(reload|restart|start)[[:space:]]+keepalived|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|replace)' \
        "$builder" "$outer" "$regression"
}

run_validation syntax /bin/bash -n "$builder" "$outer" "$regression" "$focused_self"
run_validation shellcheck shellcheck "$builder" "$outer" "$regression" "$focused_self"
run_validation canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$builder" "$outer" "$regression" "$focused_self"
run_validation executable_index_modes index_modes_exact
run_validation collision_policy /bin/bash "$collision" "$builder" "$outer" "$regression" "$focused_self"
run_validation conditional_policy /bin/bash "$conditional"
run_validation output_evidence_policy /bin/bash "$output_evidence"
run_validation multifile_grep_policy /bin/bash "$multifile_grep" --check \
    "$builder" "$outer" "$regression" "$focused_self"
run_validation portable_awk_policy /bin/bash "$portable_awk" --check
run_validation previous_outer_immutable test "$(file_hash "$previous_outer")" = \
    e9f6bf413f2a5aacbd6070b7f130753d52205ef2c9e8823d0f9e6522d082bf99
run_validation builder_exact test "$(file_hash "$builder")" = \
    3940963da753e6052b541058d2d362c9a4d3505f3db02c2c4daf6dfbafbbf39e
run_validation regression_exact test "$(file_hash "$regression")" = \
    3996bd09d3823b582be8bac0d64384eb6d1a5d7a2b8a0a1fb8ad8b5a2c559ae1
run_validation outer_exact test "$(file_hash "$outer")" = \
    f0b5b52806b4bbaaf5652949f81f7e882321b5333fb22b9ac0fb078206872965
run_validation builder_self_test /bin/bash "$builder" --self-test
run_validation regression /bin/bash "$regression"
run_validation outer_self_test /bin/bash "$outer" --self-test
run_validation outer_label_policy /bin/bash "$outer_labels" --runner "$outer"
run_validation complete_suite_bypassed complete_suite_absent
run_validation live_execution_absent live_execution_absent
run_validation node_b_activation_absent node_b_activation_absent
printf '%s_node_contact=false\n' "$prefix"
printf '%s_node_b_activation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
