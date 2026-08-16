#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=focused_validation_runner_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly manifest=$test_directory/focused-validation.yaml
readonly historical_manifest=$test_directory/historical-actions.yaml
readonly runner=$test_directory/run-focused.sh
readonly policy=$test_directory/focused-validation-manifest-policy.sh
readonly historical_policy=$test_directory/historical-action-index-policy.sh
readonly container_wrapper=$test_directory/run-focused-container.sh

record_check() {
    local focused_regression_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$focused_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$focused_regression_label" >&2
    return 1
}

command_rejected() {
    local focused_regression_expected_status=$1

    shift
    local focused_regression_status=0
    "$@" >/dev/null 2>&1 || focused_regression_status=$?
    [[ "$focused_regression_status" -eq "$focused_regression_expected_status" ]]
}

manifest_rejected() {
    local focused_regression_fixture=$1

    command_rejected 1 env CADDY_FOCUSED_VALIDATION_MANIFEST="$focused_regression_fixture" \
        /bin/bash "$policy" --check
}
profile_pattern_matches() {
    local focused_regression_profile=$1
    local focused_regression_field=$2
    local focused_regression_path=$3
    local focused_regression_pattern

    while IFS= read -r focused_regression_pattern; do
        # The manifest value is intentionally a validated glob pattern.
        # shellcheck disable=SC2053
        [[ "$focused_regression_path" != $focused_regression_pattern ]] || return 0
    done < <(jq -r --arg profile "$focused_regression_profile" --arg field "$focused_regression_field" \
        '.profiles[$profile][$field][]' "$manifest")
    return 1
}
profile_pattern_absent() {
    ! profile_pattern_matches "$@"
}

work_root=$(mktemp -d /tmp/caddy-focused-runner-regression.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM

record_check manifest_policy /bin/bash "$policy" --check || exit 1
record_check historical_policy /bin/bash "$historical_policy" --check || exit 1

list_output=$work_root/list.out
/bin/bash "$runner" --list >"$list_output"
record_check list_profile grep -Fqx $'profile\tcurrent-synchronization' "$list_output" || exit 1
record_check list_historical_action grep -Fqx $'action\taction20d-c\thistorical-preserved' "$list_output" || exit 1
accepted_action_line=$(jq -r \
    'first(.actions[] | select(.lifecycle == "accepted-executed") | "action\t\(.id)\t\(.lifecycle)") // empty' \
    "$historical_manifest")
record_check list_accepted_action test -n "$accepted_action_line" || exit 1
record_check list_accepted_action_manifest_derived grep -Fqx \
    "$accepted_action_line" "$list_output" || exit 1

explain_output=$work_root/explain.out
/bin/bash "$runner" --profile current-systemd-boot-persistence \
    --profile current-systemd-boot-persistence --explain --container never \
    >"$explain_output"
record_check explain_deduplicates_policy test \
    "$(grep -Fxc $'policy\tselected-shell' "$explain_output")" -eq 1 || exit 1
expected_systemd_host=$(jq -r '.profiles["current-systemd-boot-persistence"].host_tests[]' "$manifest")
expected_systemd_debian=$(jq -r '.profiles["current-systemd-boot-persistence"].debian_tests[]' "$manifest")
record_check explain_manifest_host diff -u \
    <(printf '%s\n' "$expected_systemd_host" | sed 's/^/host_test\t/') \
    <(grep -E $'^host_test\t' "$explain_output") || exit 1
record_check explain_manifest_debian diff -u \
    <(printf '%s\n' "$expected_systemd_debian" | sed 's/^/debian_test\t/') \
    <(grep -E $'^debian_test\t' "$explain_output") || exit 1
record_check explain_no_historical_suite test \
    "$(grep -Ec $'^(host_test|debian_test)\tCaddy/tests/(run|integration)\.sh$' "$explain_output" || true)" -eq 0 || exit 1

record_check unknown_profile_rejected command_rejected 64 \
    /bin/bash "$runner" --profile not-a-profile --explain || exit 1
record_check unknown_action_rejected command_rejected 64 \
    /bin/bash "$runner" --action action999z --explain || exit 1
record_check conflicting_selection_rejected command_rejected 64 \
    /bin/bash "$runner" --action action30e --profile current-synchronization --explain || exit 1
record_check systemd_dropin_selects_systemd profile_pattern_matches \
    current-systemd-boot-persistence path_patterns \
    Caddy/systemd/caddy.service.d/override.conf || exit 1
record_check systemd_dropin_requires_debian profile_pattern_matches \
    current-systemd-boot-persistence debian_path_patterns \
    Caddy/systemd/caddy.service.d/override.conf || exit 1
record_check documentation_skips_debian profile_pattern_absent \
    current-repository-policies debian_path_patterns Caddy/docs/caddy_plan-v1.1.md || exit 1

duplicate_manifest=$work_root/duplicate.yaml
jq '.actions += [.actions[0]]' "$historical_manifest" >"$duplicate_manifest"
record_check duplicate_action_rejected command_rejected 1 env \
    CADDY_HISTORICAL_ACTION_MANIFEST="$duplicate_manifest" \
    /bin/bash "$historical_policy" --check || exit 1

missing_manifest=$work_root/missing.yaml
jq '.actions = .actions[1:]' "$historical_manifest" >"$missing_manifest"
record_check missing_action_rejected command_rejected 1 env \
    CADDY_HISTORICAL_ACTION_MANIFEST="$missing_manifest" \
    /bin/bash "$historical_policy" --check || exit 1

unknown_policy_manifest=$work_root/unknown-policy.yaml
jq '.profiles["current-synchronization"].policies += ["arbitrary-command"]' \
    "$manifest" >"$unknown_policy_manifest"
record_check unknown_policy_rejected manifest_rejected "$unknown_policy_manifest" || exit 1

embedded_action_manifest=$work_root/embedded-action.yaml
jq '.profiles["current-repository-policies"].host_tests += ["Caddy/tests/durable-apprise-action34j-regression.sh"]' \
    "$manifest" >"$embedded_action_manifest"
record_check embedded_action_test_rejected manifest_rejected \
    "$embedded_action_manifest" || exit 1

hash_manifest=$work_root/hash.yaml
jq '.profiles["current-synchronization"].description = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
    "$manifest" >"$hash_manifest"
record_check duplicate_hash_identity_rejected manifest_rejected "$hash_manifest" || exit 1

smoke_manifest=$work_root/smoke.yaml
jq '
    .profiles["current-repository-policies"].host_tests = ["Caddy/tests/focused-validation-smoke-fixture.sh"] |
    .profiles["current-repository-policies"].debian_tests = [] |
    .profiles["current-repository-policies"].shell_files = [] |
    .profiles["current-repository-policies"].policies = []
' "$manifest" >"$smoke_manifest"
smoke_output=$work_root/smoke.out
CADDY_FOCUSED_VALIDATION_MANIFEST=$smoke_manifest \
    /bin/bash "$runner" --profile current-repository-policies \
    --container never >"$smoke_output"
record_check smoke_test_executed grep -Fq \
    'focused_validation_runner_test_status=host:Caddy/tests/focused-validation-smoke-fixture.sh:0' \
    "$smoke_output" || exit 1
smoke_evidence=$(awk -F= '/^focused_validation_runner_evidence_path=/ { print $2 }' "$smoke_output")
record_check smoke_evidence_directory test -d "$smoke_evidence" || exit 1
record_check smoke_evidence_mode test "$(stat -c '%a' "$smoke_evidence")" = 700 || exit 1
record_check smoke_summary_mode test "$(stat -c '%a' "$smoke_evidence/summary.tsv")" = 600 || exit 1
record_check smoke_summary_status grep -Fqx \
    $'host\tCaddy/tests/focused-validation-smoke-fixture.sh\t0' \
    "$smoke_evidence/summary.tsv" || exit 1

container_smoke_manifest=$work_root/container-smoke.yaml
jq '
    .profiles["current-repository-policies"].host_tests = [] |
    .profiles["current-repository-policies"].debian_tests = ["Caddy/tests/focused-validation-smoke-fixture.sh"] |
    .profiles["current-repository-policies"].shell_files = [] |
    .profiles["current-repository-policies"].policies = []
' "$manifest" >"$container_smoke_manifest"
container_evidence=$work_root/container-evidence
install -d -m 0700 "$container_evidence"
CADDY_VALIDATION_CONTAINER=1 \
    CADDY_FOCUSED_EVIDENCE_ROOT=$container_evidence \
    CADDY_FOCUSED_VALIDATION_MANIFEST=$container_smoke_manifest \
    /bin/bash "$runner" --profile current-repository-policies \
    --phase container --container never >/dev/null
record_check container_evidence_retained grep -Fqx \
    $'debian\tCaddy/tests/focused-validation-smoke-fixture.sh\t0' \
    "$container_evidence/summary.tsv" || exit 1
record_check container_evidence_single_record test \
    "$(wc -l <"$container_evidence/summary.tsv")" -eq 1 || exit 1

record_check container_network_disabled grep -Fq -- '--network none' "$container_wrapper" || exit 1
# The inspected wrapper source must contain literal child-shell parameters.
# shellcheck disable=SC2016
record_check container_batch_runner grep -Fq -- \
    'run-focused.sh --profiles "$1" --phase container --container never' \
    "$container_wrapper" || exit 1
# The inspected wrapper source must contain the literal parent-shell variable.
# shellcheck disable=SC2016
record_check container_evidence_mount grep -Fq -- \
    '--volume "$host_evidence_root:/evidence"' "$container_wrapper" || exit 1
record_check container_evidence_environment grep -Fq -- \
    '--env CADDY_FOCUSED_EVIDENCE_ROOT=/evidence' "$container_wrapper" || exit 1
# The inspected runner source must contain the literal parent-shell variable.
# shellcheck disable=SC2016
record_check parent_evidence_directory_distinct grep -Fq -- \
    'container_evidence_root=$evidence_root/debian-evidence' "$runner" || exit 1
record_check historical_default_false jq -e \
    '.historical_suite.default_selected == false' "$historical_manifest" || exit 1
record_check manifest_has_no_commands test \
    "$(jq '[.. | objects | select(has("command"))] | length' "$manifest")" -eq 0 || exit 1

printf '%s_complete=true\n' "$prefix"
