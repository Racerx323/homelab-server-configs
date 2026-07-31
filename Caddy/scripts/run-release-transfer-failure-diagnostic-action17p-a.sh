#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=cb6100bca0d67a5eabcf432daa5794c91684780cd3a1861ae432550b0e55e8d1
readonly collision_checker_sha256=78b46fcdc6c4ca6b4cfe0121c347e0e101c472d723a891aac2dea7f23f085cd8
readonly node_a_host_alias=pihole0.local.theama.co
readonly node_a_target=pi@10.1.0.53
readonly node_b_host_alias=pihole00.local.theama.co
readonly node_b_target=pi@10.1.0.54
readonly revision=action17p-node-a-to-node-b-bootstrap
readonly parent_revision=action15-health-follow-redirects
readonly node_a_assertion_count=50
readonly node_b_assertion_count=54

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly inspector="$script_directory/inspect-release-transfer-failure-action17p-a.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"

runner_assertion_count=0
runner_failed_assertion_count=0
runner_first_failure=none

record_runner_assertion() {
    local runner_label=$1
    local runner_value=$2

    runner_assertion_count=$((runner_assertion_count + 1))
    printf 'action_17p_a_runner_assertion_%s=%s\n' \
        "$runner_label" "$runner_value"
    if [[ "$runner_value" != true ]]; then
        runner_failed_assertion_count=$((runner_failed_assertion_count + 1))
        if [[ "$runner_first_failure" == none ]]; then
            runner_first_failure=$runner_label
        fi
    fi
}

record_runner_command() {
    local runner_command_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        record_runner_assertion "$runner_command_label" true
    else
        record_runner_assertion "$runner_command_label" false
    fi
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

value_for() {
    local value_key=$1
    local value_transcript=$2
    local value_record

    [[ "$(grep -Ec "^${value_key}=" "$value_transcript")" -eq 1 ]] ||
        return 1
    value_record=$(grep -E "^${value_key}=" "$value_transcript")
    printf '%s\n' "${value_record#*=}"
}

require_one() {
    local required_record=$1
    local required_transcript=$2

    [[ "$(grep -Fxc "$required_record" "$required_transcript")" -eq 1 ]]
}

is_boolean() {
    [[ "$1" =~ ^(true|false)$ ]]
}

is_mode() {
    [[ "$1" =~ ^[0-7]{3,4}$ ]]
}

is_sha256() {
    [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

is_supported_marker_state() {
    [[ "$1" =~ ^(absent|present_empty_regular)$ ]]
}

is_supported_acl_hash() {
    [[ "$1" == unavailable || "$1" =~ ^[0-9a-f]{64}$ ]]
}

is_supported_conclusion() {
    [[ "$1" =~ ^marker_(absent|present)_release_(nonwritable|writable)$ ]]
}

transcript_grammar_valid() {
    local grammar_prefix=$1
    local grammar_transcript=$2

    awk -v prefix="$grammar_prefix" '
        index($0, prefix "_") != 1 { invalid++ }
        $0 !~ /^[a-z0-9_]+=[A-Za-z0-9_.:-]+$/ { invalid++ }
        END { exit invalid ? 1 : 0 }
    ' "$grammar_transcript"
}

secret_free() {
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$@"
}

remote_status_consistent() {
    local status_failed_count=$1
    local status_value=$2

    if [[ "$status_failed_count" -eq 0 && "$status_value" -eq 0 ]]; then
        return 0
    fi
    if [[ "$status_failed_count" -gt 0 && "$status_value" -eq 1 ]]; then
        return 0
    fi
    return 1
}

validate_transcript() {
    local validation_label=$1
    local validation_role=$2
    local validation_path=$3
    local validation_expected_count=$4
    local validation_prefix="action_17p_a_${validation_role//-/_}"
    local validation_check_count
    local validation_unique_count
    local validation_reported_count
    local validation_failed_lines
    local validation_reported_failed
    local validation_first_failure
    local validation_marker_state
    local validation_release_mode
    local validation_release_writable
    local validation_acl_available
    local validation_acl_hash
    local validation_payload_hash
    local validation_manifest_hash
    local validation_before_hash
    local validation_after_hash
    local validation_conclusion

    validation_check_count=$(
        grep -Ec \
            "^${validation_prefix}_assertion_[a-z0-9_]+=(true|false)$" \
            "$validation_path" || true
    )
    validation_unique_count=$(
        sed -n \
            "s/^\\(${validation_prefix}_assertion_[a-z0-9_]*\\)=\\(true\\|false\\)$/\\1/p" \
            "$validation_path" |
            LC_ALL=C sort -u |
            wc -l
    )
    validation_reported_count=$(
        value_for "${validation_prefix}_assertion_count" "$validation_path"
    ) || validation_reported_count=invalid
    validation_failed_lines=$(
        grep -Ec "^${validation_prefix}_assertion_[a-z0-9_]+=false$" \
            "$validation_path" || true
    )
    validation_reported_failed=$(
        value_for "${validation_prefix}_failed_assertion_count" \
            "$validation_path"
    ) || validation_reported_failed=invalid
    validation_first_failure=$(
        value_for "${validation_prefix}_first_failure" "$validation_path"
    ) || validation_first_failure=invalid
    validation_marker_state=$(
        value_for "${validation_prefix}_value_marker_state" "$validation_path"
    ) || validation_marker_state=invalid
    validation_release_mode=$(
        value_for "${validation_prefix}_value_release_mode" "$validation_path"
    ) || validation_release_mode=invalid
    validation_release_writable=$(
        value_for \
            "${validation_prefix}_value_release_writable_by_sync" \
            "$validation_path"
    ) || validation_release_writable=invalid
    validation_acl_available=$(
        value_for \
            "${validation_prefix}_value_acl_tool_available" \
            "$validation_path"
    ) || validation_acl_available=invalid
    validation_acl_hash=$(
        value_for "${validation_prefix}_value_acl_sha256" "$validation_path"
    ) || validation_acl_hash=invalid
    validation_payload_hash=$(
        value_for "${validation_prefix}_value_payload_sha256" \
            "$validation_path"
    ) || validation_payload_hash=invalid
    validation_manifest_hash=$(
        value_for "${validation_prefix}_value_manifest_sha256" \
            "$validation_path"
    ) || validation_manifest_hash=invalid
    validation_before_hash=$(
        value_for "${validation_prefix}_value_before_state_sha256" \
            "$validation_path"
    ) || validation_before_hash=invalid
    validation_after_hash=$(
        value_for "${validation_prefix}_value_after_state_sha256" \
            "$validation_path"
    ) || validation_after_hash=invalid
    validation_conclusion=$(
        value_for "${validation_prefix}_value_conclusion" "$validation_path"
    ) || validation_conclusion=invalid

    record_runner_command "${validation_label}_grammar" \
        transcript_grammar_valid "$validation_prefix" "$validation_path"
    record_runner_command "${validation_label}_assertion_count_exact" \
        test "$validation_check_count" -eq "$validation_expected_count"
    record_runner_command "${validation_label}_assertion_labels_unique" \
        test "$validation_unique_count" -eq "$validation_check_count"
    record_runner_command "${validation_label}_reported_count_exact" \
        test "$validation_reported_count" = "$validation_expected_count"
    record_runner_command "${validation_label}_failed_count_consistent" \
        test "$validation_reported_failed" = "$validation_failed_lines"
    if [[ "$validation_failed_lines" -eq 0 ]]; then
        record_runner_command "${validation_label}_first_failure_none" \
            test "$validation_first_failure" = none
    else
        record_runner_command "${validation_label}_first_failure_labeled" \
            grep -Fxq \
            "${validation_prefix}_assertion_${validation_first_failure}=false" \
            "$validation_path"
    fi
    record_runner_command "${validation_label}_node_role_exact" \
        require_one "${validation_prefix}_value_node_role=$validation_role" \
        "$validation_path"
    record_runner_command "${validation_label}_revision_exact" \
        require_one "${validation_prefix}_value_revision=$revision" \
        "$validation_path"
    record_runner_command "${validation_label}_parent_revision_exact" \
        require_one \
        "${validation_prefix}_value_parent_revision=$parent_revision" \
        "$validation_path"
    record_runner_command "${validation_label}_before_state_hash_format" \
        is_sha256 "$validation_before_hash"
    record_runner_command "${validation_label}_after_state_hash_format" \
        is_sha256 "$validation_after_hash"
    record_runner_command "${validation_label}_internal_state_unchanged" \
        test "$validation_before_hash" = "$validation_after_hash"
    record_runner_command "${validation_label}_payload_hash_format" \
        is_sha256 "$validation_payload_hash"
    record_runner_command "${validation_label}_manifest_hash_format" \
        is_sha256 "$validation_manifest_hash"
    record_runner_command "${validation_label}_marker_state_supported" \
        is_supported_marker_state "$validation_marker_state"
    record_runner_command "${validation_label}_release_mode_format" \
        is_mode "$validation_release_mode"
    record_runner_command "${validation_label}_writability_boolean" \
        is_boolean "$validation_release_writable"
    record_runner_command "${validation_label}_acl_available_boolean" \
        is_boolean "$validation_acl_available"
    record_runner_command "${validation_label}_acl_hash_supported" \
        is_supported_acl_hash "$validation_acl_hash"
    record_runner_command "${validation_label}_conclusion_supported" \
        is_supported_conclusion "$validation_conclusion"
    record_runner_command "${validation_label}_peer_connections_false" \
        require_one "${validation_prefix}_peer_connections=false" \
        "$validation_path"
    record_runner_command "${validation_label}_release_transfer_false" \
        require_one "${validation_prefix}_release_transfer_executed=false" \
        "$validation_path"
    record_runner_command "${validation_label}_marker_write_false" \
        require_one \
        "${validation_prefix}_completion_marker_write_executed=false" \
        "$validation_path"
    record_runner_command "${validation_label}_reconciliation_false" \
        require_one "${validation_prefix}_reconciliation_executed=false" \
        "$validation_path"
    record_runner_command "${validation_label}_service_mutations_false" \
        require_one "${validation_prefix}_service_mutations=false" \
        "$validation_path"
    record_runner_command "${validation_label}_persistent_mutations_false" \
        require_one "${validation_prefix}_persistent_mutations=false" \
        "$validation_path"
    record_runner_command "${validation_label}_remote_complete" \
        require_one "${validation_prefix}_remote_complete=true" \
        "$validation_path"
}

run_remote() {
    local remote_host_alias=$1
    local remote_target=$2
    local remote_role=$3
    local remote_output=$4
    local remote_error=$5
    local remote_status_name=$6
    local remote_status=0

    ssh -T \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o "HostKeyAlias=$remote_host_alias" \
        -o StrictHostKeyChecking=yes \
        "$remote_target" \
        "cd / && sudo -n bash -s -- --$remote_role" \
        <"$inspector" >"$remote_output" 2>"$remote_error" ||
        remote_status=$?
    printf -v "$remote_status_name" '%s' "$remote_status"
}

write_fixture() {
    local fixture_path=$1
    local fixture_role=$2
    local fixture_expected_count=$3
    local fixture_false_index=${4:-0}
    local fixture_marker_state=${5:-absent}
    local fixture_writable=${6:-false}
    local fixture_prefix="action_17p_a_${fixture_role//-/_}"
    local fixture_index
    local fixture_value
    local fixture_failed_count=0
    local fixture_first_failure=none
    local fixture_conclusion
    local fixture_state=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    local fixture_payload=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    local fixture_manifest=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

    for ((fixture_index = 1;  \
    fixture_index <= fixture_expected_count;  \
    fixture_index += 1)); do
        fixture_value=true
        if [[ "$fixture_index" -eq "$fixture_false_index" ]]; then
            fixture_value=false
            fixture_failed_count=1
            fixture_first_failure="fixture_$fixture_index"
        fi
        printf '%s_assertion_fixture_%02d=%s\n' \
            "$fixture_prefix" "$fixture_index" "$fixture_value"
    done >"$fixture_path"
    fixture_conclusion="marker_${fixture_marker_state%%_*}_release_"
    if [[ "$fixture_writable" == true ]]; then
        fixture_conclusion+=writable
    else
        fixture_conclusion+=nonwritable
    fi
    printf '%s\n' \
        "${fixture_prefix}_value_node_role=$fixture_role" \
        "${fixture_prefix}_value_revision=$revision" \
        "${fixture_prefix}_value_parent_revision=$parent_revision" \
        "${fixture_prefix}_value_before_state_sha256=$fixture_state" \
        "${fixture_prefix}_value_after_state_sha256=$fixture_state" \
        "${fixture_prefix}_value_payload_sha256=$fixture_payload" \
        "${fixture_prefix}_value_manifest_sha256=$fixture_manifest" \
        "${fixture_prefix}_value_marker_state=$fixture_marker_state" \
        "${fixture_prefix}_value_release_owner=caddy-sync" \
        "${fixture_prefix}_value_release_group=caddy-sync" \
        "${fixture_prefix}_value_release_mode=550" \
        "${fixture_prefix}_value_release_writable_by_sync=$fixture_writable" \
        "${fixture_prefix}_value_acl_tool_available=false" \
        "${fixture_prefix}_value_acl_sha256=unavailable" \
        "${fixture_prefix}_value_conclusion=$fixture_conclusion" \
        "${fixture_prefix}_assertion_count=$fixture_expected_count" \
        "${fixture_prefix}_failed_assertion_count=$fixture_failed_count" \
        "${fixture_prefix}_first_failure=$fixture_first_failure" \
        "${fixture_prefix}_peer_connections=false" \
        "${fixture_prefix}_release_transfer_executed=false" \
        "${fixture_prefix}_completion_marker_write_executed=false" \
        "${fixture_prefix}_reconciliation_executed=false" \
        "${fixture_prefix}_service_mutations=false" \
        "${fixture_prefix}_persistent_mutations=false" \
        "${fixture_prefix}_remote_complete=true" >>"$fixture_path"
}

reset_runner_assertions() {
    runner_assertion_count=0
    runner_failed_assertion_count=0
    runner_first_failure=none
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$(file_hash "$inspector")" == "$inspector_sha256" ]]
    [[ "$(file_hash "$collision_checker")" == "$collision_checker_sha256" ]]
    bash -n "$inspector" "$collision_checker"
    "$inspector" --self-test >/dev/null
    "$collision_checker" "$inspector" "$0" >/dev/null
    printf 'action_17p_a_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    for source_path in "$inspector" "$collision_checker" "$0"; do
        [[ -f "$source_path" ]]
        [[ ! -L "$source_path" ]]
        [[ "$(stat -c '%U:%G:%a' "$source_path")" == aaron:aaron:755 ]]
    done
    printf 'action_17p_a_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_directory=$(mktemp -d /tmp/caddy-action17p-a-contract.XXXXXX)
    trap 'rm -rf -- "$contract_directory"' EXIT
    write_fixture \
        "$contract_directory/node-a-valid" node-a \
        "$node_a_assertion_count" 0 present_empty_regular false
    write_fixture \
        "$contract_directory/node-b-absent" node-b \
        "$node_b_assertion_count" 0 absent false
    write_fixture \
        "$contract_directory/node-b-present" node-b \
        "$node_b_assertion_count" 0 present_empty_regular false
    write_fixture \
        "$contract_directory/node-b-mismatch" node-b \
        "$node_b_assertion_count" 7 absent false

    reset_runner_assertions
    validate_transcript valid_a node-a "$contract_directory/node-a-valid" \
        "$node_a_assertion_count" >/dev/null
    validate_transcript valid_b_absent node-b \
        "$contract_directory/node-b-absent" \
        "$node_b_assertion_count" >/dev/null
    validate_transcript valid_b_present node-b \
        "$contract_directory/node-b-present" \
        "$node_b_assertion_count" >/dev/null
    [[ "$runner_failed_assertion_count" -eq 0 ]]

    reset_runner_assertions
    validate_transcript mismatch_b node-b \
        "$contract_directory/node-b-mismatch" \
        "$node_b_assertion_count" >/dev/null
    [[ "$runner_failed_assertion_count" -eq 0 ]]
    remote_status_consistent 1 1

    cp -- "$contract_directory/node-b-absent" \
        "$contract_directory/node-b-duplicate"
    printf 'action_17p_a_node_b_assertion_fixture_01=true\n' \
        >>"$contract_directory/node-b-duplicate"
    reset_runner_assertions
    validate_transcript duplicate_b node-b \
        "$contract_directory/node-b-duplicate" \
        "$node_b_assertion_count" >/dev/null
    [[ "$runner_failed_assertion_count" -gt 0 ]]

    cp -- "$contract_directory/node-b-absent" \
        "$contract_directory/node-b-unsafe"
    sed -i \
        's/value_marker_state=absent/value_marker_state=unsafe_type/' \
        "$contract_directory/node-b-unsafe"
    reset_runner_assertions
    validate_transcript unsafe_b node-b \
        "$contract_directory/node-b-unsafe" \
        "$node_b_assertion_count" >/dev/null
    [[ "$runner_failed_assertion_count" -gt 0 ]]

    printf 'action_17p_a_false_negative_absent_marker_accepted=true\n'
    printf 'action_17p_a_false_negative_present_marker_accepted=true\n'
    printf 'action_17p_a_false_negative_semantic_mismatch_classified=true\n'
    printf 'action_17p_a_false_positive_duplicate_assertion_rejected=true\n'
    printf 'action_17p_a_false_positive_unsafe_marker_rejected=true\n'
    printf 'action_17p_a_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

record_runner_command inspector_regular test -f "$inspector"
record_runner_command inspector_not_symlink test ! -L "$inspector"
record_runner_command inspector_hash_exact \
    test "$(file_hash "$inspector")" = "$inspector_sha256"
record_runner_command inspector_owner_exact \
    test "$(stat -c '%U:%G:%a' "$inspector")" = aaron:aaron:755
record_runner_command collision_checker_regular test -f "$collision_checker"
record_runner_command collision_checker_not_symlink test ! -L "$collision_checker"
record_runner_command collision_checker_hash_exact \
    test "$(file_hash "$collision_checker")" = "$collision_checker_sha256"
record_runner_command runner_owner_exact \
    test "$(stat -c '%U:%G:%a' "$0")" = aaron:aaron:755
record_runner_command inspector_syntax bash -n "$inspector"
record_runner_command runner_syntax bash -n "$0"
record_runner_command readonly_local_collisions_absent \
    "$collision_checker" "$inspector" "$0"

work_directory=$(mktemp -d /tmp/caddy-action17p-a-runner.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

node_b_before_status=0
run_remote \
    "$node_b_host_alias" "$node_b_target" node-b \
    "$work_directory/node-b-before.out" "$work_directory/node-b-before.err" \
    node_b_before_status
record_runner_command node_b_before_stderr_empty \
    test ! -s "$work_directory/node-b-before.err"
validate_transcript node_b_before node-b \
    "$work_directory/node-b-before.out" "$node_b_assertion_count"
node_b_before_failed=$(
    value_for action_17p_a_node_b_failed_assertion_count \
        "$work_directory/node-b-before.out"
) || node_b_before_failed=invalid
record_runner_command node_b_before_status_consistent \
    remote_status_consistent "$node_b_before_failed" "$node_b_before_status"

node_a_status=0
run_remote \
    "$node_a_host_alias" "$node_a_target" node-a \
    "$work_directory/node-a.out" "$work_directory/node-a.err" \
    node_a_status
record_runner_command node_a_stderr_empty \
    test ! -s "$work_directory/node-a.err"
validate_transcript node_a node-a "$work_directory/node-a.out" \
    "$node_a_assertion_count"
node_a_failed=$(
    value_for action_17p_a_node_a_failed_assertion_count \
        "$work_directory/node-a.out"
) || node_a_failed=invalid
record_runner_command node_a_status_consistent \
    remote_status_consistent "$node_a_failed" "$node_a_status"

node_b_after_status=0
run_remote \
    "$node_b_host_alias" "$node_b_target" node-b \
    "$work_directory/node-b-after.out" "$work_directory/node-b-after.err" \
    node_b_after_status
record_runner_command node_b_after_stderr_empty \
    test ! -s "$work_directory/node-b-after.err"
validate_transcript node_b_after node-b \
    "$work_directory/node-b-after.out" "$node_b_assertion_count"
node_b_after_failed=$(
    value_for action_17p_a_node_b_failed_assertion_count \
        "$work_directory/node-b-after.out"
) || node_b_after_failed=invalid
record_runner_command node_b_after_status_consistent \
    remote_status_consistent "$node_b_after_failed" "$node_b_after_status"

node_a_payload=$(
    value_for action_17p_a_node_a_value_payload_sha256 \
        "$work_directory/node-a.out"
) || node_a_payload=invalid
node_b_before_payload=$(
    value_for action_17p_a_node_b_value_payload_sha256 \
        "$work_directory/node-b-before.out"
) || node_b_before_payload=invalid
node_b_after_payload=$(
    value_for action_17p_a_node_b_value_payload_sha256 \
        "$work_directory/node-b-after.out"
) || node_b_after_payload=invalid
record_runner_command node_a_node_b_payload_equal \
    test "$node_a_payload" = "$node_b_before_payload"
record_runner_command node_b_payload_unchanged \
    test "$node_b_before_payload" = "$node_b_after_payload"

node_a_manifest=$(
    value_for action_17p_a_node_a_value_manifest_sha256 \
        "$work_directory/node-a.out"
) || node_a_manifest=invalid
node_b_before_manifest=$(
    value_for action_17p_a_node_b_value_manifest_sha256 \
        "$work_directory/node-b-before.out"
) || node_b_before_manifest=invalid
node_b_after_manifest=$(
    value_for action_17p_a_node_b_value_manifest_sha256 \
        "$work_directory/node-b-after.out"
) || node_b_after_manifest=invalid
record_runner_command node_a_node_b_manifest_equal \
    test "$node_a_manifest" = "$node_b_before_manifest"
record_runner_command node_b_manifest_unchanged \
    test "$node_b_before_manifest" = "$node_b_after_manifest"

node_b_before_state=$(
    value_for action_17p_a_node_b_value_before_state_sha256 \
        "$work_directory/node-b-before.out"
) || node_b_before_state=invalid
node_b_after_state=$(
    value_for action_17p_a_node_b_value_after_state_sha256 \
        "$work_directory/node-b-after.out"
) || node_b_after_state=invalid
record_runner_command node_b_cross_run_state_unchanged \
    test "$node_b_before_state" = "$node_b_after_state"
record_runner_command transcripts_secret_free \
    secret_free "$work_directory"/*.out "$work_directory"/*.err

cat \
    "$work_directory/node-b-before.out" \
    "$work_directory/node-a.out" \
    "$work_directory/node-b-after.out"
printf 'action_17p_a_runner_value_node_b_before_status=%s\n' \
    "$node_b_before_status"
printf 'action_17p_a_runner_value_node_a_status=%s\n' "$node_a_status"
printf 'action_17p_a_runner_value_node_b_after_status=%s\n' \
    "$node_b_after_status"
printf 'action_17p_a_runner_assertion_count=%s\n' "$runner_assertion_count"
printf 'action_17p_a_runner_failed_assertion_count=%s\n' \
    "$runner_failed_assertion_count"
printf 'action_17p_a_runner_first_failure=%s\n' "$runner_first_failure"
printf 'action_17p_a_runner_peer_connections=administrative_ssh_only\n'
printf 'action_17p_a_runner_transport_probe_executed=false\n'
printf 'action_17p_a_runner_release_transfer_executed=false\n'
printf 'action_17p_a_runner_completion_marker_write_executed=false\n'
printf 'action_17p_a_runner_reconciliation_executed=false\n'
printf 'action_17p_a_runner_service_mutations=false\n'
printf 'action_17p_a_runner_persistent_mutations=false\n'

if [[ "$runner_failed_assertion_count" -ne 0 ]]; then
    printf 'action_17p_a_runner_classification=evidence_failure\n'
    exit 97
fi
if [[ "$node_b_before_status" -eq 1 || "$node_a_status" -eq 1 ||
    "$node_b_after_status" -eq 1 ]]; then
    printf 'action_17p_a_runner_classification=semantic_mismatch\n'
    exit 1
fi
printf 'action_17p_a_runner_classification=state_verified\n'
