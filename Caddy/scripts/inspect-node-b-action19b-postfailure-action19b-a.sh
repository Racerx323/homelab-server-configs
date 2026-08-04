#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_19b_a
readonly baseline_prefix=action_19a_a
readonly health_target=/usr/local/libexec/check-caddy.sh
readonly notification_target=/usr/local/libexec/lsyncd-ha-failover-notify.sh
readonly rollback_root=/var/backups/caddy-ha
readonly expected_baseline_assertions=61

baseline_inspector=
work_directory=
assertion_count=0
failed_assertion_count=0
first_failure=none

record_assertion() {
    local assertion_label=$1
    local assertion_value=$2

    assertion_count=$((assertion_count + 1))
    printf '%s_assertion_%s=%s\n' "$prefix" "$assertion_label" \
        "$assertion_value"
    if [[ "$assertion_value" != true ]]; then
        failed_assertion_count=$((failed_assertion_count + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$assertion_label
        fi
    fi
}

record_command() {
    local command_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        record_assertion "$command_label" true
    else
        record_assertion "$command_label" false
    fi
}

validate_baseline_transcript() {
    local expected_labels_path=$1
    local transcript_path=$2
    local expected_label
    local expected_count
    local observed_count
    local observed_unique_count

    expected_count=$(wc -l <"$expected_labels_path") || return 1
    record_command baseline_expected_count_exact \
        test "$expected_count" -eq "$expected_baseline_assertions"
    record_command baseline_expected_labels_unique \
        test "$(LC_ALL=C sort -u "$expected_labels_path" | wc -l)" -eq \
        "$expected_baseline_assertions"
    observed_count=$(grep -Ec \
        "^${baseline_prefix}_assertion_[a-z0-9_]+=true$" \
        "$transcript_path" || true)
    record_command baseline_actual_grammar_count_exact \
        test "$observed_count" -eq "$expected_baseline_assertions"
    observed_unique_count=$(sed -n \
        "s/^\(${baseline_prefix}_assertion_[a-z0-9_]*\)=true$/\1/p" \
        "$transcript_path" | LC_ALL=C sort -u | wc -l)
    record_command baseline_actual_grammar_unique \
        test "$observed_unique_count" -eq "$expected_baseline_assertions"
    while IFS= read -r expected_label; do
        record_command "baseline_${expected_label}_true_once" \
            test "$(grep -Fxc \
                "${baseline_prefix}_assertion_${expected_label}=true" \
                "$transcript_path")" -eq 1
    done <"$expected_labels_path"
    record_command baseline_false_assertions_absent \
        test "$(grep -Ec \
            "^${baseline_prefix}_assertion_[a-z0-9_]+=false$" \
            "$transcript_path" || true)" -eq 0
    record_command baseline_assertion_count_summary_exact grep -Fxq \
        "${baseline_prefix}_assertion_count=${expected_baseline_assertions}" \
        "$transcript_path"
    record_command baseline_failed_count_summary_zero grep -Fxq \
        "${baseline_prefix}_failed_assertion_count=0" "$transcript_path"
    record_command baseline_first_failure_none grep -Fxq \
        "${baseline_prefix}_first_failure=none" "$transcript_path"
    record_command baseline_state_unchanged grep -Fxq \
        "${baseline_prefix}_state_unchanged=true" "$transcript_path"
    record_command baseline_helper_invoked_false grep -Fxq \
        "${baseline_prefix}_helper_invoked=false" "$transcript_path"
    record_command baseline_persistent_mutation_false grep -Fxq \
        "${baseline_prefix}_persistent_mutation=false" "$transcript_path"
    [[ "$failed_assertion_count" -eq 0 ]]
}

write_contract_fixture() {
    local expected_labels_path=$1
    local fixture_path=$2
    local fixture_label

    while IFS= read -r fixture_label; do
        printf '%s_assertion_%s=true\n' "$baseline_prefix" "$fixture_label"
    done <"$expected_labels_path" >"$fixture_path"
    printf '%s\n' \
        "${baseline_prefix}_assertion_count=${expected_baseline_assertions}" \
        "${baseline_prefix}_failed_assertion_count=0" \
        "${baseline_prefix}_first_failure=none" \
        "${baseline_prefix}_state_unchanged=true" \
        "${baseline_prefix}_helper_invoked=false" \
        "${baseline_prefix}_persistent_mutation=false" >>"$fixture_path"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 2 ]] || exit 64
        baseline_inspector=$2
        expected_root=$(mktemp -d /tmp/caddy-action19b-a-self.XXXXXX)
        readonly expected_root
        trap 'rm -rf -- "$expected_root"' EXIT
        "$baseline_inspector" --expected-assertions \
            >"$expected_root/labels"
        test "$(wc -l <"$expected_root/labels")" -eq \
            "$expected_baseline_assertions"
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 2 ]] || exit 64
        baseline_inspector=$2
        contract_root=$(mktemp -d /tmp/caddy-action19b-a-contract.XXXXXX)
        readonly contract_root
        trap 'rm -rf -- "$contract_root"' EXIT
        "$baseline_inspector" --expected-assertions >"$contract_root/labels"
        write_contract_fixture "$contract_root/labels" "$contract_root/valid"
        validate_baseline_transcript "$contract_root/labels" \
            "$contract_root/valid"
        sed 's/_assertion_/_check_/' "$contract_root/valid" \
            >"$contract_root/wrong-grammar"
        assertion_count=0
        failed_assertion_count=0
        first_failure=none
        if validate_baseline_transcript "$contract_root/labels" \
            "$contract_root/wrong-grammar" >/dev/null 2>&1; then
            exit 1
        fi
        printf '%s_contract_actual_grammar_accepted=true\n' "$prefix"
        printf '%s_contract_invented_grammar_rejected=true\n' "$prefix"
        printf '%s_contract_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --baseline-inspector)
        [[ $# -eq 2 ]] || exit 64
        baseline_inspector=$2
        ;;
    *)
        printf 'Usage: %s --baseline-inspector PATH\n' "${0##*/}" >&2
        exit 64
        ;;
esac

record_command identity_root test "$(id -u)" -eq 0
record_command working_directory_root test "$(pwd -P)" = /
record_command hostname_node_b test "$(hostname)" = j1-svpihole00
record_command baseline_inspector_regular test -f "$baseline_inspector"
record_command baseline_inspector_not_symlink test ! -L "$baseline_inspector"
record_command baseline_inspector_metadata \
    test "$(stat -c '%U:%G:%a' "$baseline_inspector")" = root:root:700

work_directory=$(mktemp -d /run/caddy-action19b-a-inspector.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
"$baseline_inspector" --expected-assertions >"$work_directory/labels"
baseline_status=0
"$baseline_inspector" >"$work_directory/baseline.stdout" \
    2>"$work_directory/baseline.stderr" || baseline_status=$?
readonly baseline_status
record_command baseline_status_zero test "$baseline_status" -eq 0
record_command baseline_stderr_empty test ! -s "$work_directory/baseline.stderr"
validate_baseline_transcript "$work_directory/labels" \
    "$work_directory/baseline.stdout"

record_command health_target_absent test ! -e "$health_target"
record_command health_target_not_symlink test ! -L "$health_target"
record_command notification_target_absent test ! -e "$notification_target"
record_command notification_target_not_symlink test ! -L "$notification_target"
record_command action19b_backup_absent \
    test -z "$(find "$rollback_root" -mindepth 1 -maxdepth 1 \
        -name 'action19b-node-b-keepalived-helpers.*' -print -quit)"
record_command action19b_health_install_stage_absent \
    test -z "$(find /usr/local/libexec -mindepth 1 -maxdepth 1 \
        -name '.check-caddy.action19b.*' -print -quit)"
record_command action19b_notification_install_stage_absent \
    test -z "$(find /usr/local/libexec -mindepth 1 -maxdepth 1 \
        -name '.lsyncd-ha-failover-notify.action19b.*' -print -quit)"
record_command action19b_remote_bundle_stage_absent \
    test -z "$(find /run -mindepth 1 -maxdepth 1 \
        -name 'caddy-action19b-stage.*' -print -quit 2>/dev/null)"

printf '%s_assertion_count=%s\n' "$prefix" "$assertion_count"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_assertion_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_helper_invoked=false\n' "$prefix"
printf '%s_filesystem_mutation=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_keepalived_mutation=false\n' "$prefix"
printf '%s_vrrp_vip_mutation=false\n' "$prefix"
printf '%s_persistent_mutation=false\n' "$prefix"
printf '%s_inspection_complete=true\n' "$prefix"

[[ "$failed_assertion_count" -eq 0 ]]
