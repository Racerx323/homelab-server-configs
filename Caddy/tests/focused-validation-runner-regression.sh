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
readonly runner=$test_directory/run-focused.sh
readonly policy=$test_directory/focused-validation-manifest-policy.sh

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

work_root=$(mktemp -d /tmp/caddy-focused-runner-regression.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM

record_check manifest_policy /bin/bash "$policy" --check || exit 1
record_check manifest_current_only jq -e '
    .schema_version == 4 and
    (has("historical_actions_manifest") | not) and
    ([.profiles[].host_tests[], .profiles[].debian_tests[]] |
        all(test("action[0-9]") | not))
' "$manifest" || exit 1

list_output=$work_root/list.out
/bin/bash "$runner" --list >"$list_output"
record_check list_profiles grep -Fqx $'profile\tcurrent-synchronization' \
    "$list_output" || exit 1
record_check list_has_no_actions test \
    "$(grep -Ec '^action[[:space:]]' "$list_output" || true)" -eq 0 || exit 1

explain_output=$work_root/explain.out
/bin/bash "$runner" --profile current-systemd-boot-persistence \
    --profile current-systemd-boot-persistence --explain --container never \
    >"$explain_output"
record_check explain_deduplicates_policy test \
    "$(grep -Fxc $'policy\tselected-shell' "$explain_output")" -eq 1 || exit 1
record_check explain_manifest_host diff -u \
    <(jq -r '.profiles["current-systemd-boot-persistence"].host_tests[]' \
        "$manifest" | sed 's/^/host_test\t/') \
    <(grep -E $'^host_test\t' "$explain_output") || exit 1

record_check action_selection_removed command_rejected 64 \
    /bin/bash "$runner" --action action35 --explain || exit 1
record_check unknown_profile_rejected command_rejected 64 \
    /bin/bash "$runner" --profile not-a-profile --explain || exit 1

unknown_policy_manifest=$work_root/unknown-policy.yaml
jq '.profiles["current-synchronization"].policies += ["arbitrary-command"]' \
    "$manifest" >"$unknown_policy_manifest"
record_check unknown_policy_rejected command_rejected 1 env \
    CADDY_FOCUSED_VALIDATION_MANIFEST="$unknown_policy_manifest" \
    /bin/bash "$policy" --check || exit 1

action_test_manifest=$work_root/action-test.yaml
jq '.profiles["current-synchronization"].host_tests += ["Caddy/tests/action35-regression.sh"]' \
    "$manifest" >"$action_test_manifest"
record_check action_test_rejected command_rejected 1 env \
    CADDY_FOCUSED_VALIDATION_MANIFEST="$action_test_manifest" \
    /bin/bash "$policy" --check || exit 1

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
smoke_evidence=$(awk -F= \
    '/^focused_validation_runner_evidence_path=/ { print $2 }' "$smoke_output")
record_check smoke_evidence_directory test -d "$smoke_evidence" || exit 1
record_check smoke_summary_status grep -Fqx \
    $'host\tCaddy/tests/focused-validation-smoke-fixture.sh\t0' \
    "$smoke_evidence/summary.tsv" || exit 1

printf '%s_complete=true\n' "$prefix"
