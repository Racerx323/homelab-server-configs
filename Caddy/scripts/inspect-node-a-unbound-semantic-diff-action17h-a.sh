#!/usr/bin/env bash

set -u -o pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prior_inspector_sha256=f0e0c89732f0db755623870f0d8f72189936bfed6777ce38a805081bdf010387
readonly expected_live_normalized_sha256=ec8e09797cf46462360b5fa7595412155721bc6816bc66d04e729525d6719de7
readonly expected_candidate_normalized_sha256=3a130bd46f72a2ad48f8c5a3079552d107daa483c7523587711e8497211966dd
readonly expected_state_sha256=7b00e0d91512674b446e3b783db77351f8686b867ccf8ccd02283aa7abba6b74
readonly expected_normalized_count=128
readonly expected_difference_count=24
readonly expected_assertion_count=29

assertion_count=0
failed_assertion_count=0
first_failure=none

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

record_assertion() {
    local assertion_label=$1
    local assertion_status=$2
    local observed_value=${3:-unavailable}

    ((assertion_count += 1))
    printf 'action_17h_a_assertion_%s=%s\n' \
        "$assertion_label" "$assertion_status"
    if [[ "$assertion_status" != true ]]; then
        ((failed_assertion_count += 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$assertion_label
        fi
        printf 'action_17h_a_observed_%s=%s\n' \
            "$assertion_label" "$observed_value"
    fi
}

assert_equal() {
    local equality_label=$1
    local observed_value=$2
    local expected_value=$3

    if [[ "$observed_value" == "$expected_value" ]]; then
        record_assertion "$equality_label" true
    else
        record_assertion "$equality_label" false "$observed_value"
    fi
}

assert_regular_file() {
    local regular_label=$1
    local regular_path=$2

    if [[ -f "$regular_path" && ! -L "$regular_path" ]]; then
        record_assertion "$regular_label" true
    else
        record_assertion "$regular_label" false \
            "$(stat -c %F "$regular_path" 2>/dev/null || printf absent)"
    fi
}

value_for() {
    local value_key=$1
    local evidence_path=$2
    local value_record

    if [[ "$(grep -Ec "^${value_key}=" "$evidence_path")" -ne 1 ]]; then
        return 1
    fi
    value_record=$(grep -E "^${value_key}=" "$evidence_path")
    printf '%s\n' "${value_record#*=}"
}

emit_difference_records() {
    local record_prefix=$1
    local difference_path=$2
    local record_index=0
    local directive_line
    local encoded_line

    while IFS= read -r directive_line || [[ -n "$directive_line" ]]; do
        ((record_index += 1))
        encoded_line=$(printf '%s' "$directive_line" | base64 -w 0)
        printf 'action_17h_a_%s_%03d_b64=%s\n' \
            "$record_prefix" "$record_index" "$encoded_line"
    done <"$difference_path"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$expected_difference_count" -eq 24 ]]
    [[ "$expected_assertion_count" -eq 29 ]]
    printf 'action_17h_a_inspector_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" != --stage || $# -ne 2 ]]; then
    printf 'Usage: %s --stage /run/caddy-action17h.*\n' "${0##*/}" >&2
    exit 2
fi

stage_path=$2
readonly stage_path
prior_inspector="$stage_path/inspect-node-a-two-file-unbound-preflight-action17h.sh"
readonly prior_inspector
prior_evidence="$stage_path/action17h.out"
readonly prior_evidence
live_normalized="$stage_path/live.normalized"
readonly live_normalized
candidate_normalized="$stage_path/candidate.normalized"
readonly candidate_normalized
live_only="$stage_path/live-only.normalized"
readonly live_only
candidate_only="$stage_path/candidate-only.normalized"
readonly candidate_only

printf 'action_17h_a_remote_reached=true\n'

assert_regular_file prior_inspector_regular "$prior_inspector"
assert_equal prior_inspector_hash \
    "$(file_hash "$prior_inspector" 2>/dev/null)" "$prior_inspector_sha256"
if [[ "$stage_path" =~ ^/run/caddy-action17h\.[A-Za-z0-9]+$ &&
    -d "$stage_path" && ! -L "$stage_path" ]]; then
    record_assertion stage_directory true
else
    record_assertion stage_directory false "$stage_path"
fi
assert_equal stage_directory_metadata \
    "$(stat -c '%U:%G:%a' "$stage_path" 2>/dev/null)" root:root:700
if command -v base64 >/dev/null; then
    record_assertion command_base64_available true
else
    record_assertion command_base64_available false missing
fi

prior_status=0
/bin/bash "$prior_inspector" --stage "$stage_path" \
    >"$prior_evidence" 2>/dev/null || prior_status=$?
assert_equal prior_exit_status "$prior_status" 1
assert_equal prior_assertion_count \
    "$(value_for action_17h_assertion_count "$prior_evidence" 2>/dev/null)" 51
assert_equal prior_failed_assertion_count \
    "$(value_for action_17h_failed_assertion_count "$prior_evidence" 2>/dev/null)" 3
assert_equal prior_first_failure \
    "$(value_for action_17h_first_failure "$prior_evidence" 2>/dev/null)" \
    normalized_sha256
assert_equal prior_conclusion \
    "$(value_for action_17h_conclusion "$prior_evidence" 2>/dev/null)" \
    node_a_preflight_mismatch
assert_equal prior_remote_complete \
    "$(value_for action_17h_remote_complete "$prior_evidence" 2>/dev/null)" true

prior_false_labels=$(
    grep -E '^action_17h_assertion_[a-z0-9_]+=false$' "$prior_evidence" |
        sed -E 's/^action_17h_assertion_([^=]+)=false$/\1/' |
        LC_ALL=C sort |
        awk 'BEGIN { separator = "" }
            { printf "%s%s", separator, $0; separator = "," }
            END { print "" }'
)
readonly prior_false_labels
assert_equal prior_false_labels "$prior_false_labels" \
    candidate_only_directive_count,live_only_directive_count,normalized_sha256
assert_equal prior_observed_normalized_sha256 \
    "$(value_for action_17h_observed_normalized_sha256 \
        "$prior_evidence" 2>/dev/null)" \
    "$expected_live_normalized_sha256"
assert_equal prior_observed_live_only_count \
    "$(value_for action_17h_observed_live_only_directive_count \
        "$prior_evidence" 2>/dev/null)" "$expected_difference_count"
assert_equal prior_observed_candidate_only_count \
    "$(value_for action_17h_observed_candidate_only_directive_count \
        "$prior_evidence" 2>/dev/null)" "$expected_difference_count"
before_state=$(
    value_for action_17h_before_state_sha256 "$prior_evidence" 2>/dev/null
)
readonly before_state
after_state=$(
    value_for action_17h_after_state_sha256 "$prior_evidence" 2>/dev/null
)
readonly after_state
assert_equal prior_before_state "$before_state" "$expected_state_sha256"
assert_equal prior_state_unchanged "$after_state" "$before_state"

assert_regular_file live_normalized_regular "$live_normalized"
assert_regular_file candidate_normalized_regular "$candidate_normalized"
assert_equal live_normalized_metadata \
    "$(stat -c '%U:%G:%a' "$live_normalized" 2>/dev/null)" root:root:600
assert_equal candidate_normalized_metadata \
    "$(stat -c '%U:%G:%a' "$candidate_normalized" 2>/dev/null)" root:root:600
assert_equal live_normalized_count \
    "$(wc -l <"$live_normalized" 2>/dev/null)" "$expected_normalized_count"
assert_equal candidate_normalized_count \
    "$(wc -l <"$candidate_normalized" 2>/dev/null)" "$expected_normalized_count"
assert_equal live_normalized_hash \
    "$(file_hash "$live_normalized" 2>/dev/null)" \
    "$expected_live_normalized_sha256"
assert_equal candidate_normalized_hash \
    "$(file_hash "$candidate_normalized" 2>/dev/null)" \
    "$expected_candidate_normalized_sha256"

if [[ "$failed_assertion_count" -eq 0 ]]; then
    comm -23 "$live_normalized" "$candidate_normalized" >"$live_only"
    comm -13 "$live_normalized" "$candidate_normalized" >"$candidate_only"
else
    : >"$live_only"
    : >"$candidate_only"
fi
assert_equal live_only_count \
    "$(wc -l <"$live_only" 2>/dev/null)" "$expected_difference_count"
assert_equal candidate_only_count \
    "$(wc -l <"$candidate_only" 2>/dev/null)" "$expected_difference_count"
assert_equal difference_file_metadata \
    "$(stat -c '%U:%G:%a' "$live_only" "$candidate_only" 2>/dev/null |
        LC_ALL=C sort -u |
        awk 'BEGIN { separator = "" }
            { printf "%s%s", separator, $0; separator = "," }
            END { print "" }')" root:root:600
if grep -Eiq \
    'BEGIN [A-Z ]*PRIVATE KEY|DOPPLER_TOKEN|API[_-]?KEY|PASSWORD|SECRET|TOKEN' \
    "$live_only" "$candidate_only"; then
    record_assertion difference_secret_pattern_absent false matched
else
    record_assertion difference_secret_pattern_absent true
fi

printf 'action_17h_a_assertion_count=%s\n' "$assertion_count"
printf 'action_17h_a_failed_assertion_count=%s\n' "$failed_assertion_count"
printf 'action_17h_a_first_failure=%s\n' "$first_failure"
printf 'action_17h_a_live_only_count=%s\n' \
    "$(wc -l <"$live_only" 2>/dev/null)"
printf 'action_17h_a_candidate_only_count=%s\n' \
    "$(wc -l <"$candidate_only" 2>/dev/null)"
printf 'action_17h_a_live_only_sha256=%s\n' \
    "$(file_hash "$live_only" 2>/dev/null)"
printf 'action_17h_a_candidate_only_sha256=%s\n' \
    "$(file_hash "$candidate_only" 2>/dev/null)"
printf 'action_17h_a_before_state_sha256=%s\n' "$before_state"
printf 'action_17h_a_after_state_sha256=%s\n' "$after_state"
printf 'remote_stage_created=true\n'
printf 'dns_queries_performed=false\n'
printf 'dns_configuration_mutations=false\n'
printf 'service_mutations=false\n'
printf 'persistent_mutations=false\n'
if [[ "$failed_assertion_count" -eq 0 ]]; then
    emit_difference_records live_only "$live_only"
    emit_difference_records candidate_only "$candidate_only"
    printf 'action_17h_a_conclusion=semantic_difference_captured\n'
    printf 'action_17h_a_remote_complete=true\n'
    exit 0
fi
printf 'action_17h_a_conclusion=diagnostic_prerequisite_failed\n'
printf 'action_17h_a_remote_complete=true\n'
exit 1
