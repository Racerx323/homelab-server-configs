#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28f
readonly node_b_alias=pihole00.local.theama.co
readonly node_b_target=pi@10.1.0.54
readonly node_a_alias=pihole0.local.theama.co
readonly node_a_target=pi@10.1.0.53
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096
readonly driver_sha256=23a36fda7fa4087026678d10305b3d61cd1d4e1193c154d1a68b3ba3c4a700aa
readonly inspector_sha256=3260a3d52884ab141f26356ebecd2699f611dac359d1f921c96a2037234bc906
readonly candidate_revision=20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63
readonly candidate_parent=action16ar-retry-node-a-default-deny
readonly candidate_manifest_sha256=fdc6ed955f14226ac3e1777eca37507cc8ab6ca16add3135dece9d6964e27568

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${CADDY_ACTION28F_CADDY_ROOT:-${script_directory%/scripts}}
readonly driver="$script_directory/transfer-retained-node-a-release-action28f.sh"
readonly inspector="$script_directory/inspect-node-b-incoming-release-action28f.sh"
readonly source_context="$caddy_root/tests/run-source-test-in-context.sh"

ssh_binary=${CADDY_ACTION28F_SSH_BINARY:-ssh}
readonly ssh_binary
checks_total=0
checks_passed=0
checks_failed=0
first_failure=none

record_result() {
    local result_label=$1
    local result_value=$2
    checks_total=$((checks_total + 1))
    if [[ "$result_value" == true ]]; then
        printf '%s_check_%s=true\n' "$prefix" "$result_label"
        checks_passed=$((checks_passed + 1))
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$result_label" >&2
    checks_failed=$((checks_failed + 1))
    [[ "$first_failure" != none ]] || first_failure=$result_label
    return 0
}

record_command() {
    local command_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        record_result "$command_label" true
    else
        record_result "$command_label" false
    fi
}

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }

verify_source() {
    local expected_hash=$1
    local source_path=$2

    [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
    [[ -x "$source_path" ]] || return 1
    [[ "$(file_hash "$source_path")" == "$expected_hash" ]] || return 1
    bash -n "$source_path"
}

verify_sources() {
    verify_source "$driver_sha256" "$driver" || return 1
    verify_source "$inspector_sha256" "$inspector" || return 1
    [[ -x "$source_context" ]] || return 1
}

working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
            return 0
            ;;
        *) return 1 ;;
    esac
}

safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$stream_path"
}

emit_stream() {
    local stream_label=$1
    local stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_label" \
        "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_label" \
        "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_label" \
        "$(file_hash "$stream_path")"
    if ! safe_stream "$stream_path"; then
        trap - EXIT
        printf '%s_%s_classification=unsafe_retained\n' \
            "$prefix" "$stream_label" >&2
        printf '%s_%s_protected_evidence=%s\n' \
            "$prefix" "$stream_label" "${stream_path%/*}" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$stream_label"
    while IFS= read -r stream_line || [[ -n "$stream_line" ]]; do
        printf '%s_%s_content=%s\n' "$prefix" "$stream_label" \
            "$(printf '%s' "$stream_line" | base64 -w 0)"
    done <"$stream_path"
}

value_for() {
    local value_name=$1
    local transcript_path=$2
    local value_record

    [[ "$(grep -Ec "^${value_name}=" "$transcript_path")" -eq 1 ]] || return 1
    value_record=$(grep -E "^${value_name}=" "$transcript_path")
    printf '%s\n' "${value_record#*=}"
}

validate_transcript() {
    local validation_label=$1
    local transcript_prefix=$2
    local transcript_path=$3
    local expected_phase=$4
    local observed_status=$5
    local count_true
    local count_total
    local count_passed
    local count_failed
    local observed_phase
    local producer
    local expected_labels
    local observed_labels
    local grammar_status=0

    if [[ "$transcript_prefix" == action_28f_node_a ]]; then
        producer=$driver
    else
        producer=$inspector
    fi
    expected_labels=$(mktemp /tmp/action28f-expected-labels.XXXXXX) || return 1
    observed_labels=$(mktemp /tmp/action28f-observed-labels.XXXXXX) || {
        rm -f -- "$expected_labels"
        return 1
    }
    "$producer" --expected-checks "$expected_phase" |
        sed "s/^/${transcript_prefix}_check_/; s/$/=true/" >"$expected_labels"
    sed -n "/^${transcript_prefix}_check_/p" "$transcript_path" >"$observed_labels"
    cmp -s "$expected_labels" "$observed_labels" || grammar_status=1
    rm -f -- "$expected_labels" "$observed_labels"

    while IFS= read -r transcript_line || [[ -n "$transcript_line" ]]; do
        case "$transcript_line" in
            "${transcript_prefix}_check_"*"=true" | \
                "${transcript_prefix}_value_phase="* | \
                "${transcript_prefix}_value_revision="* | \
                "${transcript_prefix}_value_parent_revision="* | \
                "${transcript_prefix}_value_manifest_sha256="* | \
                "${transcript_prefix}_value_rsync_stdout_bytes="* | \
                "${transcript_prefix}_value_rsync_stdout_lines="* | \
                "${transcript_prefix}_value_rsync_stdout_sha256="* | \
                "${transcript_prefix}_value_rsync_stdout_classification=bounded_safe" | \
                "${transcript_prefix}_value_rsync_stdout_content="* | \
                "${transcript_prefix}_value_rsync_stderr_bytes="* | \
                "${transcript_prefix}_value_rsync_stderr_lines="* | \
                "${transcript_prefix}_value_rsync_stderr_sha256="* | \
                "${transcript_prefix}_value_rsync_stderr_classification=bounded_safe" | \
                "${transcript_prefix}_value_rsync_stderr_content="* | \
                "${transcript_prefix}_checks_total="* | \
                "${transcript_prefix}_checks_passed="* | \
                "${transcript_prefix}_checks_failed=0" | \
                "${transcript_prefix}_first_failure=none" | \
                "${transcript_prefix}_publication_started=false" | \
                "${transcript_prefix}_release_transfer_started="* | \
                "${transcript_prefix}_inspector_finalizer_invoked=false" | \
                "${transcript_prefix}_lsyncd_enabled=false" | \
                "${transcript_prefix}_reconciliation_executed=false" | \
                "${transcript_prefix}_service_mutations=false" | \
                "${transcript_prefix}_remote_delete_executed=false" | \
                "${transcript_prefix}_filesystem_mutations=false" | \
                "${transcript_prefix}_acceptance=true") ;;
            *) grammar_status=1 ;;
        esac
    done <"$transcript_path"

    count_true=$(grep -Ec "^${transcript_prefix}_check_[a-z0-9_]+=true$" \
        "$transcript_path" || true)
    count_total=$(value_for "${transcript_prefix}_checks_total" "$transcript_path") ||
        count_total=invalid
    count_passed=$(value_for "${transcript_prefix}_checks_passed" "$transcript_path") ||
        count_passed=invalid
    count_failed=$(value_for "${transcript_prefix}_checks_failed" "$transcript_path") ||
        count_failed=invalid
    observed_phase=$(value_for "${transcript_prefix}_value_phase" "$transcript_path") ||
        observed_phase=invalid
    record_command "${validation_label}_status_zero" test "$observed_status" -eq 0
    record_command "${validation_label}_grammar_exact" test "$grammar_status" -eq 0
    record_command "${validation_label}_total_numeric" test "$count_total" -eq "$count_total"
    record_command "${validation_label}_passed_numeric" test "$count_passed" -eq "$count_passed"
    record_command "${validation_label}_failed_numeric" test "$count_failed" -eq "$count_failed"
    record_command "${validation_label}_true_matches_total" test "$count_true" -eq "$count_total"
    record_command "${validation_label}_passed_matches_total" test "$count_passed" -eq "$count_total"
    record_command "${validation_label}_failed_zero" test "$count_failed" -eq 0
    record_command "${validation_label}_false_checks_absent" test \
        "$(grep -Ec "^${transcript_prefix}_check_[a-z0-9_]+=false$" \
            "$transcript_path" || true)" -eq 0
    record_command "${validation_label}_phase_exact" test "$observed_phase" = "$expected_phase"
    record_command "${validation_label}_acceptance_single" test \
        "$(grep -Fxc "${transcript_prefix}_acceptance=true" "$transcript_path")" -eq 1
    record_command "${validation_label}_revision_exact" test \
        "$(value_for "${transcript_prefix}_value_revision" "$transcript_path")" = \
        "$([[ "$expected_phase" == preflight ]] && printf unavailable || printf %s "$candidate_revision")"
    record_command "${validation_label}_parent_exact" test \
        "$(value_for "${transcript_prefix}_value_parent_revision" "$transcript_path")" = \
        "$([[ "$expected_phase" == preflight ]] && printf unavailable || printf %s "$candidate_parent")"
    record_command "${validation_label}_manifest_exact" test \
        "$(value_for "${transcript_prefix}_value_manifest_sha256" "$transcript_path")" = \
        "$([[ "$expected_phase" == preflight ]] && printf unavailable || printf %s "$candidate_manifest_sha256")"
}

run_remote() {
    local remote_alias=$1
    local remote_target=$2
    local remote_argument=$3
    local remote_payload=$4
    local remote_stdout=$5
    local remote_stderr=$6
    local status_name=$7
    local remote_status=0

    "$ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=5 \
        -o "HostKeyAlias=$remote_alias" -o StrictHostKeyChecking=yes \
        "$remote_target" "cd / && sudo -n /bin/bash -s -- $remote_argument" \
        <"$remote_payload" >"$remote_stdout" 2>"$remote_stderr" ||
        remote_status=$?
    printf -v "$status_name" '%s' "$remote_status"
}

write_fixture() {
    local fixture_path=$1
    local fixture_prefix=$2
    local fixture_phase=$3
    local producer
    if [[ "$fixture_prefix" == action_28f_node_a ]]; then producer=$driver; else producer=$inspector; fi
    "$producer" --expected-checks "$fixture_phase" |
        sed "s/^/${fixture_prefix}_check_/; s/$/=true/" >"$fixture_path"
    printf '%s\n' \
        "${fixture_prefix}_value_phase=$fixture_phase" \
        "${fixture_prefix}_value_revision=unavailable" \
        "${fixture_prefix}_value_parent_revision=unavailable" \
        "${fixture_prefix}_value_manifest_sha256=unavailable" \
        "${fixture_prefix}_checks_total=$("$producer" --expected-checks "$fixture_phase" | wc -l)" \
        "${fixture_prefix}_checks_passed=$("$producer" --expected-checks "$fixture_phase" | wc -l)" \
        "${fixture_prefix}_checks_failed=0" \
        "${fixture_prefix}_first_failure=none" \
        "${fixture_prefix}_publication_started=false" \
        "${fixture_prefix}_release_transfer_started=false" \
        "${fixture_prefix}_lsyncd_enabled=false" \
        "${fixture_prefix}_reconciliation_executed=false" \
        "${fixture_prefix}_service_mutations=false" \
        "${fixture_prefix}_remote_delete_executed=false" \
        "${fixture_prefix}_acceptance=true" >>"$fixture_path"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        verify_sources
        "$driver" --self-test >/dev/null
        "$inspector" --self-test >/dev/null
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --source-test)
        [[ $# -eq 1 ]]
        verify_sources
        [[ "$(stat -c '%U:%G:%a' "$0")" == aaron:aaron:755 ]]
        printf '%s_source_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]]
        verify_sources
        contract_directory=$(mktemp -d /tmp/caddy-action28-contract.XXXXXX)
        trap 'rm -rf -- "$contract_directory"' EXIT
        write_fixture "$contract_directory/valid" action_28f_node_a preflight
        validate_transcript valid action_28f_node_a \
            "$contract_directory/valid" preflight 0 >/dev/null
        [[ "$checks_failed" -eq 0 ]]
        printf 'action_28f_false_negative_valid_transcript_accepted=true\n'
        sed '0,/=true/s//=false/' \
            "$contract_directory/valid" >"$contract_directory/false"
        checks_total=0 checks_passed=0 checks_failed=0 first_failure=none
        validate_transcript false_check action_28f_node_a \
            "$contract_directory/false" preflight 1 >/dev/null 2>&1
        [[ "$checks_failed" -gt 0 ]]
        printf 'action_28f_false_positive_failed_assertion_rejected=true\n'
        cp -- "$contract_directory/valid" "$contract_directory/duplicate"
        printf 'action_28f_node_a_value_phase=preflight\n' \
            >>"$contract_directory/duplicate"
        checks_total=0 checks_passed=0 checks_failed=0 first_failure=none
        validate_transcript duplicate_value action_28f_node_a \
            "$contract_directory/duplicate" preflight 0 >/dev/null 2>&1
        [[ "$checks_failed" -gt 0 ]]
        printf 'action_28f_false_positive_duplicate_value_rejected=true\n'
        cp -- "$contract_directory/valid" "$contract_directory/extra"
        printf 'true\n' >>"$contract_directory/extra"
        checks_total=0 checks_passed=0 checks_failed=0 first_failure=none
        validate_transcript extra_line action_28f_node_a \
            "$contract_directory/extra" preflight 0 >/dev/null 2>&1
        [[ "$checks_failed" -gt 0 ]]
        printf 'action_28f_false_positive_unmatched_line_rejected=true\n'
        printf '%s_contract_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]]
        ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
working_directory_approved
work_directory=$(mktemp -d /tmp/caddy-action28f-runner.XXXXXX)
readonly work_directory
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT
for stream_path in node-b-pre.out node-b-pre.err node-a-pre.out node-a-pre.err \
    node-a-transfer.out node-a-transfer.err node-b-complete.out node-b-complete.err; do
    : >"$work_directory/$stream_path"
    chmod 0600 "$work_directory/$stream_path"
done

node_b_pre_status=0
run_remote "$node_b_alias" "$node_b_target" --preflight "$inspector" \
    "$work_directory/node-b-pre.out" "$work_directory/node-b-pre.err" \
    node_b_pre_status
emit_stream node_b_pre_stdout "$work_directory/node-b-pre.out"
emit_stream node_b_pre_stderr "$work_directory/node-b-pre.err"
record_command node_b_preflight_stderr_empty test ! -s "$work_directory/node-b-pre.err"
validate_transcript node_b_preflight action_28f_node_b \
    "$work_directory/node-b-pre.out" preflight "$node_b_pre_status"

node_a_pre_status=not_run
if [[ "$checks_failed" -eq 0 ]]; then
    node_a_pre_status=0
    run_remote "$node_a_alias" "$node_a_target" --preflight "$driver" \
        "$work_directory/node-a-pre.out" "$work_directory/node-a-pre.err" \
        node_a_pre_status
    emit_stream node_a_pre_stdout "$work_directory/node-a-pre.out"
    emit_stream node_a_pre_stderr "$work_directory/node-a-pre.err"
    record_command node_a_preflight_stderr_empty test ! -s "$work_directory/node-a-pre.err"
    validate_transcript node_a_preflight action_28f_node_a \
        "$work_directory/node-a-pre.out" preflight "$node_a_pre_status"
fi

node_a_transfer_status=not_run
node_b_complete_status=not_run
revision=unavailable
parent_revision=unavailable
manifest_sha256=unavailable
if [[ "$checks_failed" -eq 0 ]]; then
    node_a_transfer_status=0
    run_remote "$node_a_alias" "$node_a_target" --transfer "$driver" \
        "$work_directory/node-a-transfer.out" "$work_directory/node-a-transfer.err" \
        node_a_transfer_status
    emit_stream node_a_transfer_stdout "$work_directory/node-a-transfer.out"
    emit_stream node_a_transfer_stderr "$work_directory/node-a-transfer.err"
    record_command node_a_transfer_stderr_empty test ! -s "$work_directory/node-a-transfer.err"
    validate_transcript node_a_transfer action_28f_node_a \
        "$work_directory/node-a-transfer.out" transfer "$node_a_transfer_status"
    revision=$(value_for action_28f_node_a_value_revision \
        "$work_directory/node-a-transfer.out") || revision=unavailable
    parent_revision=$(value_for action_28f_node_a_value_parent_revision \
        "$work_directory/node-a-transfer.out") || parent_revision=unavailable
    manifest_sha256=$(value_for action_28f_node_a_value_manifest_sha256 \
        "$work_directory/node-a-transfer.out") || manifest_sha256=unavailable
    record_command transfer_revision_valid test \
        "$(printf '%s' "$revision" | grep -Ec '^[A-Za-z0-9][A-Za-z0-9._-]*$')" -eq 1
    record_command transfer_parent_valid test \
        "$(printf '%s' "$parent_revision" | grep -Ec '^[A-Za-z0-9][A-Za-z0-9._-]*$')" -eq 1
    record_command transfer_manifest_hash_valid test \
        "$(printf '%s' "$manifest_sha256" | grep -Ec '^[0-9a-f]{64}$')" -eq 1
fi

if [[ "$checks_failed" -eq 0 ]]; then
    node_b_complete_status=0
    run_remote "$node_b_alias" "$node_b_target" \
        "--complete $revision $parent_revision $manifest_sha256" "$inspector" \
        "$work_directory/node-b-complete.out" "$work_directory/node-b-complete.err" \
        node_b_complete_status
    emit_stream node_b_complete_stdout "$work_directory/node-b-complete.out"
    emit_stream node_b_complete_stderr "$work_directory/node-b-complete.err"
    record_command node_b_complete_stderr_empty test ! -s "$work_directory/node-b-complete.err"
    validate_transcript node_b_complete action_28f_node_b \
        "$work_directory/node-b-complete.out" complete "$node_b_complete_status"
fi

printf '%s_value_revision=%s\n' "$prefix" "$revision"
printf '%s_value_parent_revision=%s\n' "$prefix" "$parent_revision"
printf '%s_value_manifest_sha256=%s\n' "$prefix" "$manifest_sha256"
printf '%s_checks_total=%s\n' "$prefix" "$checks_total"
printf '%s_checks_passed=%s\n' "$prefix" "$checks_passed"
printf '%s_checks_failed=%s\n' "$prefix" "$checks_failed"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_lsyncd_enabled=false\n' "$prefix"
printf '%s_reconciliation_executed=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_remote_delete_executed=false\n' "$prefix"
if [[ "$checks_failed" -ne 0 ]]; then
    printf '%s_acceptance=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_acceptance=true\n' "$prefix"
