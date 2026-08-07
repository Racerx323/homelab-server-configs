#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20l_retry_focused_validation
readonly builder_sha256=466bf864675f0f1033314b70ac033d636aa3e8bbc313674346565e5caaf76fb7
readonly outer_sha256=03bd70834f445f3353f69acaaeda843a43a33105659e80666f91be56593a1ca5
readonly generated_inspector_sha256=a1358c58fb2a322f828a018b1e7094160b4d4f80bd926f13b5524128b5d88171
readonly generated_outer_sha256=6a0b44d1e6b5affedb3f8d1cd4d607e8d14e41777810d87fb59a32487320c92a
readonly generated_regression_sha256=6c536a34131f2e0782b3c9bc8bebb878c24cc674f98482a9563ac1abe71c0c35

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-keepalived-dbus-readiness-action20l-retry.sh
readonly outer=$caddy_root/scripts/run-dual-node-keepalived-dbus-readiness-action20l-retry-outer.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20l_retry_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20l_retry_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20l_retry_focused_label" >&2
    return 1
}
validate_generated() (
    local action20l_retry_focused_output_root=$1
    local action20l_retry_focused_inspector=$action20l_retry_focused_output_root/scripts/inspect-keepalived-dbus-readiness-action20l-retry.sh
    local action20l_retry_focused_generated_outer=$action20l_retry_focused_output_root/scripts/run-dual-node-keepalived-dbus-readiness-action20l-retry-generated.sh
    local action20l_retry_focused_regression=$action20l_retry_focused_output_root/tests/action20l-retry-keepalived-dbus-readiness-regression.sh
    local action20l_retry_focused_expected_health_check="record_check health_metadata_exact test \"\$action20l_retry_health_metadata_observed\" = root:root:755"
    local action20l_retry_focused_expected_health_output="printf '%s_value_health_metadata=%s\\n' \"\$prefix\" \"\$action20l_retry_health_metadata_observed\""

    record_check generated_inspector_hash test \
        "$(file_hash "$action20l_retry_focused_inspector")" = "$generated_inspector_sha256" || return 1
    record_check generated_outer_hash test \
        "$(file_hash "$action20l_retry_focused_generated_outer")" = "$generated_outer_sha256" || return 1
    record_check generated_regression_hash test \
        "$(file_hash "$action20l_retry_focused_regression")" = "$generated_regression_sha256" || return 1
    record_check generated_syntax /bin/bash -n \
        "$action20l_retry_focused_inspector" "$action20l_retry_focused_generated_outer" \
        "$action20l_retry_focused_regression" || return 1
    record_check generated_shellcheck shellcheck \
        "$action20l_retry_focused_inspector" "$action20l_retry_focused_generated_outer" \
        "$action20l_retry_focused_regression" || return 1
    record_check generated_canonical_format shfmt -d -i 4 -ci \
        "$action20l_retry_focused_inspector" "$action20l_retry_focused_generated_outer" \
        "$action20l_retry_focused_regression" || return 1
    record_check corrected_metadata_expectation grep -Fxq \
        "$action20l_retry_focused_expected_health_check" \
        "$action20l_retry_focused_inspector" || return 1
    record_check observed_metadata_output grep -Fxq \
        "$action20l_retry_focused_expected_health_output" \
        "$action20l_retry_focused_inspector" || return 1
    record_check old_metadata_expectation_absent test \
        "$(grep -Fc 'root:caddy-tls:750' "$action20l_retry_focused_inspector")" -eq 0 || return 1
    record_check metadata_consumer_exact grep -Fq \
        'action_20l_retry_value_health_metadata=root:root:755' \
        "$action20l_retry_focused_generated_outer" || return 1
    record_check old_metadata_negative_coverage grep -Fq \
        'candidate_stage_metadata_rejected' "$action20l_retry_focused_regression" || return 1
    record_check generated_regression /bin/bash "$action20l_retry_focused_regression" || return 1
)
run_validation() (
    local action20l_retry_focused_work_root
    local action20l_retry_focused_generated

    action20l_retry_focused_work_root=$(mktemp -d /tmp/caddy-action20l-retry-focused.XXXXXX) || return 1
    trap 'rm -rf -- "$action20l_retry_focused_work_root"' EXIT
    action20l_retry_focused_generated=$action20l_retry_focused_work_root/generated

    record_check builder_hash test "$(file_hash "$builder")" = "$builder_sha256" || return 1
    record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256" || return 1
    record_check syntax /bin/bash -n "$builder" "$outer" "$0" || return 1
    record_check shellcheck shellcheck "$builder" "$outer" "$0" || return 1
    record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" \
        --check "$builder" "$outer" "$0" || return 1
    record_check collision_policy /bin/bash \
        "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
        "$builder" "$outer" "$0" || return 1
    record_check executable_policy /bin/bash \
        "$test_directory/executable-wrapper-policy-regression.sh" || return 1
    record_check outer_label_policy /bin/bash \
        "$test_directory/outer-local-gate-label-policy-regression.sh" \
        --self-test || return 1
    record_check conditional_policy /bin/bash \
        "$test_directory/conditional-validator-errexit-policy-regression.sh" || return 1
    record_check output_evidence_policy /bin/bash \
        "$test_directory/transaction-output-evidence-policy-regression.sh" || return 1
    record_check multifile_grep_policy /bin/bash \
        "$test_directory/multifile-grep-count-policy.sh" --check \
        "$builder" "$outer" "$0" || return 1
    record_check portable_awk_policy /bin/bash \
        "$test_directory/portable-awk-policy.sh" --check \
        "$builder" "$outer" "$0" || return 1
    record_check accepted_live_hash_policy /bin/bash \
        "$test_directory/accepted-live-hash-policy.sh" --check || return 1
    record_check builder_self_test /bin/bash "$builder" --self-test || return 1
    record_check builder_generation /bin/bash "$builder" \
        --output "$action20l_retry_focused_generated" || return 1
    validate_generated "$action20l_retry_focused_generated" || return 1
    record_check outer_self_test /bin/bash "$outer" --self-test || return 1
    printf '%s_node_a_contacted=false\n' "$prefix"
    printf '%s_node_b_contacted=false\n' "$prefix"
    printf '%s_dbus_deployment=false\n' "$prefix"
    printf '%s_keepalived_reload=false\n' "$prefix"
    printf '%s_service_mutation=false\n' "$prefix"
    printf '%s_vrrp_mutation=false\n' "$prefix"
    printf '%s_vip_mutation=false\n' "$prefix"
    printf '%s_action_executed=false\n' "$prefix"
    printf '%s_persistent_live_mutations=false\n' "$prefix"
    printf '%s_complete_suite_bypassed=true\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
)

run_validation
