#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20g_retry_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly focused_self=$test_directory/action20g-retry-focused-validation.sh
readonly baseline_builder=$caddy_root/scripts/build-action20g-retry-baseline.sh
readonly correction_builder=$caddy_root/scripts/build-node-b-caddy-health-group-action20g.sh
readonly outer=$caddy_root/scripts/run-node-b-caddy-health-group-correction-action20g-retry-outer.sh
readonly historical_outer=$caddy_root/scripts/run-node-b-caddy-health-group-correction-action20g-outer.sh
readonly regression=$test_directory/action20g-retry-stale-hash-regression.sh
readonly hash_policy=$test_directory/accepted-live-hash-policy.sh
readonly hash_policy_regression=$test_directory/accepted-live-hash-policy-regression.sh
readonly portable_awk_policy=$test_directory/portable-awk-policy.sh
readonly portable_awk_regression=$test_directory/portable-awk-policy-regression.sh
readonly accepted_manifest=$caddy_root/manifests/accepted-live-artifacts.tsv
readonly consumer_registry=$caddy_root/manifests/deployable-live-hash-consumers.tsv
readonly collision=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$test_directory/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$test_directory/transaction-output-evidence-policy-regression.sh
readonly multifile_grep=$test_directory/multifile-grep-count-policy.sh
readonly outer_labels=$test_directory/outer-local-gate-label-policy-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
run_validation() {
    local action20g_retry_focused_label=$1

    shift
    if "$@"; then
        printf '%s_%s=true\n' "$prefix" "$action20g_retry_focused_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$action20g_retry_focused_label" >&2
    return 1
}
hash_exact() {
    local action20g_retry_expected_hash=$1
    local action20g_retry_hash_path=$2

    [[ "$(file_hash "$action20g_retry_hash_path")" = "$action20g_retry_expected_hash" ]]
}
executable_modes_exact() {
    local action20g_retry_mode_path

    for action20g_retry_mode_path in "$baseline_builder" "$outer" "$regression" \
        "$hash_policy" "$hash_policy_regression" "$portable_awk_policy" \
        "$portable_awk_regression" "$focused_self"; do
        [[ "$(stat -c '%a' "$action20g_retry_mode_path")" = 755 ]] || return 1
        [[ "$(git -C "$caddy_root/.." ls-files -s -- \
            "Caddy/${action20g_retry_mode_path#"$caddy_root/"}" | awk '{ print $1 }')" = 100755 ]] || return 1
    done
}
complete_suite_absent() {
    ! grep -Eq 'tests/run\.sh|tests/integration\.sh|complete_suite' \
        "$baseline_builder" "$outer" "$regression" "$hash_policy" \
        "$hash_policy_regression"
}
live_execution_absent() {
    ! grep -Eq \
        '^[[:space:]]*/bin/bash[[:space:]]+"[$](outer|baseline_runner|correction_runner)"[[:space:]]*$' \
        "$focused_self"
}
node_b_activation_absent() {
    ! grep -Eq \
        'systemctl[[:space:]]+(reload|restart|start)[[:space:]]+keepalived|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|replace)' \
        "$baseline_builder" "$outer" "$regression" "$hash_policy" \
        "$hash_policy_regression"
}

run_validation syntax /bin/bash -n "$baseline_builder" "$outer" "$regression" \
    "$hash_policy" "$hash_policy_regression" "$portable_awk_policy" \
    "$portable_awk_regression" "$focused_self"
run_validation shellcheck shellcheck "$baseline_builder" "$outer" "$regression" \
    "$hash_policy" "$hash_policy_regression" "$portable_awk_policy" \
    "$portable_awk_regression" "$focused_self"
run_validation canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$baseline_builder" "$outer" "$regression" "$hash_policy" \
    "$hash_policy_regression" "$portable_awk_policy" "$portable_awk_regression" \
    "$focused_self"
run_validation executable_modes executable_modes_exact
run_validation collision_policy /bin/bash "$collision" "$baseline_builder" "$outer" \
    "$regression" "$hash_policy" "$hash_policy_regression" \
    "$portable_awk_policy" "$portable_awk_regression" "$focused_self"
run_validation conditional_policy /bin/bash "$conditional"
run_validation output_evidence_policy /bin/bash "$output_evidence"
run_validation multifile_grep_policy /bin/bash "$multifile_grep" --check \
    "$baseline_builder" "$outer" "$regression" "$hash_policy" \
    "$hash_policy_regression" "$portable_awk_policy" "$portable_awk_regression" \
    "$focused_self"
run_validation accepted_live_hash_policy /bin/bash "$hash_policy" --check
run_validation accepted_live_hash_policy_regression /bin/bash "$hash_policy_regression"
run_validation portable_awk_policy /bin/bash "$portable_awk_policy" --check
run_validation portable_awk_regression /bin/bash "$portable_awk_regression"
run_validation historical_outer_immutable hash_exact \
    b4a51f8ec33b130ce4ee540ebb310a4393da023693d2b453dec84c3d42ab76a9 \
    "$historical_outer"
run_validation baseline_builder_exact hash_exact \
    dfbd052e6e71747e16a7018301740cac3b0db5c04b69b7bc85095e0faf684b8b \
    "$baseline_builder"
run_validation correction_builder_exact hash_exact \
    8171bf8bf9cc881f4939c1589fbae181f95be110c56c4bee596125d1e5f86c5b \
    "$correction_builder"
run_validation regression_exact hash_exact \
    21ccb477aa84b561f333f599212d145756214db8f8368bea596151834de9aa0d \
    "$regression"
run_validation hash_policy_exact hash_exact \
    ddd0bac4ed05db2b8a082c3df21e5e1b8a439ad5c7d60e74b09ee0aa99629174 \
    "$hash_policy"
run_validation hash_policy_regression_exact hash_exact \
    edefa5e7c66e43395ef6f073ac0831307589b5d66b37e67190e2b3cd9cb0a857 \
    "$hash_policy_regression"
run_validation portable_awk_policy_exact hash_exact \
    30e6be4f4737b9df3c9669572252ee8bff7ae949387a7f96ebe62a2e384fc755 \
    "$portable_awk_policy"
run_validation portable_awk_regression_exact hash_exact \
    8b32ebc8c3edb1f2a5c0fcbf18b154963504c092f04d2b3372bb89d676f6e98e \
    "$portable_awk_regression"
run_validation accepted_manifest_exact hash_exact \
    78f7e81d77acf93be923ca4a95a3f16d3250f6d0b52f767fd3044e6ad6575e44 \
    "$accepted_manifest"
run_validation consumer_registry_exact hash_exact \
    d39c66f73f06b64371ee7327b9c49a1d64567f3c9cb18693d4315931015df541 \
    "$consumer_registry"
run_validation outer_exact hash_exact \
    b22d7f7332215f4b0021759bb56cf4b6bb3cb8cdec4386b3330530a53786702b \
    "$outer"
run_validation regression /bin/bash "$regression"
run_validation outer_self_test /bin/bash "$outer" --self-test
run_validation outer_label_policy /bin/bash "$outer_labels" --runner "$outer"
run_validation complete_suite_bypassed complete_suite_absent
run_validation live_execution_absent live_execution_absent
run_validation node_b_activation_absent node_b_activation_absent
printf '%s_node_contact=false\n' "$prefix"
printf '%s_node_b_activation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
