#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly node_a_inspector_sha256=e181f2e38f98f9df39bfb4992b4e4f91a786e738566c385becbe722709b931f1
readonly node_b_inspector_sha256=f9abd9952612f7855821c0d09a1de01c64fa540c1782aa24512cd035e7a1cdaf
readonly node_a_target=pi@10.1.0.53
readonly node_a_host_alias=pihole0.local.theama.co
readonly node_b_target=pi@10.1.0.54
readonly node_b_host_alias=pihole00.local.theama.co
readonly expected_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly expected_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly node_a_inspector="$script_directory/inspect-node-a-protocol-v2-readiness-action17r.sh"
readonly node_b_inspector="$script_directory/inspect-node-b-protocol-v2-readiness-action17r.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"

runner_assertion_count=0
runner_failed_assertion_count=0
runner_first_failure=none
runner_contract_invalid=false
runner_semantic_mismatch=false

record_runner_assertion() {
    local runner_label=$1
    local runner_value=$2

    runner_assertion_count=$((runner_assertion_count + 1))
    printf 'action_17r_runner_assertion_%s=%s\n' "$runner_label" "$runner_value"
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

record_semantic_command() {
    local semantic_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        record_runner_assertion "$semantic_label" true
    else
        record_runner_assertion "$semantic_label" false
        runner_semantic_mismatch=true
    fi
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_inspectors() {
    local verified_inspector
    local verified_hash

    for verified_inspector in "$node_a_inspector" "$node_b_inspector"; do
        [[ -f "$verified_inspector" && ! -L "$verified_inspector" ]]
        [[ "$(stat -c '%U:%G:%a' "$verified_inspector")" = aaron:aaron:755 ]]
        bash -n "$verified_inspector"
        "$collision_checker" "$verified_inspector" >/dev/null
        "$verified_inspector" --self-test >/dev/null
    done
    for verified_hash in \
        "$node_a_inspector_sha256" "$node_b_inspector_sha256"; do
        [[ "$verified_hash" =~ ^[0-9a-f]{64}$ ]]
    done
    [[ "$(file_hash "$node_a_inspector")" = "$node_a_inspector_sha256" ]]
    [[ "$(file_hash "$node_b_inspector")" = "$node_b_inspector_sha256" ]]
}

value_for() {
    local value_key=$1
    local value_transcript=$2
    local value_record

    [[ "$(grep -Ec "^${value_key}=" "$value_transcript")" -eq 1 ]] || return 1
    value_record=$(grep -E "^${value_key}=" "$value_transcript")
    printf '%s\n' "${value_record#*=}"
}

require_one() {
    local required_record=$1
    local required_transcript=$2

    [[ "$(grep -Fxc "$required_record" "$required_transcript")" -eq 1 ]]
}

is_nonnegative_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

is_sha256() {
    [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

secret_free() {
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$@"
}

extract_source_labels() {
    local source_path=$1

    awk '
        /record_command\(\)/ { next }
        /^[[:space:]]*record_command [a-z0-9_]+/ {
            line = $0
            sub(/^[[:space:]]*record_command /, "", line)
            sub(/[[:space:]].*$/, "", line)
            print line
            next
        }
        /^[[:space:]]*record_command[[:space:]]*\\$/ {
            getline
            line = $0
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]].*$/, "", line)
            print line
        }
    ' "$source_path"
}

transcript_grammar_valid() {
    local grammar_prefix=$1
    local grammar_transcript=$2

    awk -v prefix="$grammar_prefix" '
        index($0, prefix "_") != 1 { invalid++ }
        $0 !~ /^[a-z0-9_]+=[A-Za-z0-9_.:\/-]+$/ { invalid++ }
        END { exit invalid ? 1 : 0 }
    ' "$grammar_transcript"
}

validate_remote_transcript() {
    local validation_label=$1
    local validation_prefix=$2
    local validation_source=$3
    local validation_transcript=$4
    local validation_error=$5
    local validation_status=$6
    local expected_labels
    local observed_labels
    local expected_count
    local observed_count
    local reported_count
    local failed_count
    local reported_failed
    local reported_first
    local computed_first
    local expected_status
    local contract_failures_before
    local before_hash
    local after_hash

    contract_failures_before=$runner_failed_assertion_count
    expected_labels=$(mktemp "$work_directory/${validation_label}.expected.XXXXXX")
    observed_labels=$(mktemp "$work_directory/${validation_label}.observed.XXXXXX")
    extract_source_labels "$validation_source" | LC_ALL=C sort >"$expected_labels"
    sed -n \
        "s/^${validation_prefix}_assertion_\\([a-z0-9_]*\\)=\\(true\\|false\\)$/\\1/p" \
        "$validation_transcript" | LC_ALL=C sort >"$observed_labels"
    expected_count=$(wc -l <"$expected_labels")
    observed_count=$(wc -l <"$observed_labels")
    reported_count=$(value_for "${validation_prefix}_assertion_count" \
        "$validation_transcript") || reported_count=invalid
    failed_count=$(grep -Ec \
        "^${validation_prefix}_assertion_[a-z0-9_]+=false$" \
        "$validation_transcript" || true)
    reported_failed=$(value_for "${validation_prefix}_failed_assertion_count" \
        "$validation_transcript") || reported_failed=invalid
    reported_first=$(value_for "${validation_prefix}_first_failure" \
        "$validation_transcript") || reported_first=invalid
    computed_first=$(sed -n \
        "s/^${validation_prefix}_assertion_\\([a-z0-9_]*\\)=false$/\\1/p" \
        "$validation_transcript" | head -n 1)
    if [[ -z "$computed_first" ]]; then
        computed_first=none
    fi
    if [[ "$failed_count" -eq 0 ]]; then
        expected_status=0
    else
        expected_status=1
    fi
    before_hash=$(value_for "${validation_prefix}_value_before_state_sha256" \
        "$validation_transcript") || before_hash=invalid
    after_hash=$(value_for "${validation_prefix}_value_after_state_sha256" \
        "$validation_transcript") || after_hash=invalid

    record_runner_command "${validation_label}_stderr_empty" \
        test ! -s "$validation_error"
    record_runner_command "${validation_label}_secret_free" \
        secret_free "$validation_transcript" "$validation_error"
    record_runner_command "${validation_label}_grammar_valid" \
        transcript_grammar_valid "$validation_prefix" "$validation_transcript"
    record_runner_command "${validation_label}_expected_count_positive" \
        test "$expected_count" -gt 0
    record_runner_command "${validation_label}_label_count_exact" \
        test "$observed_count" -eq "$expected_count"
    record_runner_command "${validation_label}_labels_exact" \
        cmp -s "$expected_labels" "$observed_labels"
    record_runner_command "${validation_label}_labels_unique" \
        test "$(sort -u "$observed_labels" | wc -l)" -eq "$observed_count"
    record_runner_command "${validation_label}_reported_count_numeric" \
        is_nonnegative_integer "$reported_count"
    record_runner_command "${validation_label}_reported_count_exact" \
        test "$reported_count" = "$observed_count"
    record_runner_command "${validation_label}_reported_failed_numeric" \
        is_nonnegative_integer "$reported_failed"
    record_runner_command "${validation_label}_reported_failed_exact" \
        test "$reported_failed" = "$failed_count"
    record_runner_command "${validation_label}_first_failure_exact" \
        test "$reported_first" = "$computed_first"
    record_runner_command "${validation_label}_status_semantic" \
        test "$validation_status" -eq "$expected_status"
    record_runner_command "${validation_label}_before_hash_format" \
        is_sha256 "$before_hash"
    record_runner_command "${validation_label}_after_hash_format" \
        is_sha256 "$after_hash"
    record_runner_command "${validation_label}_state_unchanged" \
        test "$after_hash" = "$before_hash"

    for validation_marker in \
        peer_connection_executed=false \
        restricted_command_executed=false \
        release_transfer_executed=false \
        marker_mutation=false \
        helper_invocation=false \
        service_mutations=false \
        persistent_mutations=false \
        remote_complete=true; do
        record_runner_command \
            "${validation_label}_${validation_marker%%=*}_exact" \
            require_one "${validation_prefix}_${validation_marker}" \
            "$validation_transcript"
    done
    if [[ "$runner_failed_assertion_count" -ne "$contract_failures_before" ]]; then
        runner_contract_invalid=true
    fi
    if [[ "$failed_count" -eq 0 ]]; then
        record_runner_assertion "${validation_label}_remote_assertions_passed" true
    else
        record_runner_assertion "${validation_label}_remote_assertions_passed" false
        runner_semantic_mismatch=true
    fi
}

run_remote_inspection() {
    local inspection_target=$1
    local inspection_host_alias=$2
    local inspection_source=$3
    local inspection_output=$4
    local inspection_error=$5

    ssh -T \
        -o BatchMode=yes \
        -o ClearAllForwardings=yes \
        -o ConnectTimeout=10 \
        -o "HostKeyAlias=$inspection_host_alias" \
        -o KbdInteractiveAuthentication=no \
        -o PasswordAuthentication=no \
        -o PreferredAuthentications=publickey \
        -o StrictHostKeyChecking=yes \
        "$inspection_target" \
        'cd / && sudo -n /bin/bash -s --' \
        <"$inspection_source" >"$inspection_output" 2>"$inspection_error"
}

write_contract_fixture() {
    local fixture_source=$1
    local fixture_prefix=$2
    local fixture_role=$3
    local fixture_path=$4
    local fixture_label

    {
        while IFS= read -r fixture_label; do
            printf '%s_assertion_%s=true\n' "$fixture_prefix" "$fixture_label"
        done < <(extract_source_labels "$fixture_source")
        printf '%s\n' \
            "${fixture_prefix}_value_payload_sha256=$expected_payload_sha256" \
            "${fixture_prefix}_value_manifest_sha256=$expected_manifest_sha256" \
            "${fixture_prefix}_value_before_state_sha256=1111111111111111111111111111111111111111111111111111111111111111" \
            "${fixture_prefix}_value_after_state_sha256=1111111111111111111111111111111111111111111111111111111111111111"
        if [[ "$fixture_role" = node-a ]]; then
            printf '%s_value_source_state=legacy_complete_requires_v2_finalize_request\n' \
                "$fixture_prefix"
        else
            printf '%s\n' \
                "${fixture_prefix}_value_receiver_state=installed_policy_ready" \
                "${fixture_prefix}_value_release_state=payload_ready_awaiting_finalize_request"
        fi
        printf '%s\n' \
            "${fixture_prefix}_assertion_count=$(extract_source_labels "$fixture_source" | wc -l)" \
            "${fixture_prefix}_failed_assertion_count=0" \
            "${fixture_prefix}_first_failure=none" \
            "${fixture_prefix}_peer_connection_executed=false" \
            "${fixture_prefix}_restricted_command_executed=false" \
            "${fixture_prefix}_release_transfer_executed=false" \
            "${fixture_prefix}_marker_mutation=false" \
            "${fixture_prefix}_helper_invocation=false" \
            "${fixture_prefix}_service_mutations=false" \
            "${fixture_prefix}_persistent_mutations=false" \
            "${fixture_prefix}_remote_complete=true"
    } >"$fixture_path"
}

if [[ "${1:-}" = --self-test && $# -eq 1 ]]; then
    verify_inspectors
    printf 'action_17r_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" = --source-test && $# -eq 1 ]]; then
    verify_inspectors
    printf 'action_17r_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" = --contract-test && $# -eq 1 ]]; then
    work_directory=$(mktemp -d /tmp/caddy-action17r-contract.XXXXXX)
    readonly work_directory
    trap 'rm -rf -- "$work_directory"' EXIT
    write_contract_fixture "$node_a_inspector" action_17r_node_a node-a \
        "$work_directory/node-a.out"
    write_contract_fixture "$node_b_inspector" action_17r_node_b node-b \
        "$work_directory/node-b.out"
    : >"$work_directory/empty.err"
    validate_remote_transcript node_a action_17r_node_a "$node_a_inspector" \
        "$work_directory/node-a.out" "$work_directory/empty.err" 0
    validate_remote_transcript node_b action_17r_node_b "$node_b_inspector" \
        "$work_directory/node-b.out" "$work_directory/empty.err" 0
    [[ "$runner_failed_assertion_count" -eq 0 ]]
    printf 'action_17r_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_inspectors
work_directory=$(mktemp -d /tmp/caddy-action17r-runner.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

node_b_before_status=0
run_remote_inspection "$node_b_target" "$node_b_host_alias" \
    "$node_b_inspector" "$work_directory/node-b-before.out" \
    "$work_directory/node-b-before.err" || node_b_before_status=$?
node_a_status=0
run_remote_inspection "$node_a_target" "$node_a_host_alias" \
    "$node_a_inspector" "$work_directory/node-a.out" \
    "$work_directory/node-a.err" || node_a_status=$?
node_b_after_status=0
run_remote_inspection "$node_b_target" "$node_b_host_alias" \
    "$node_b_inspector" "$work_directory/node-b-after.out" \
    "$work_directory/node-b-after.err" || node_b_after_status=$?

validate_remote_transcript node_b_before action_17r_node_b "$node_b_inspector" \
    "$work_directory/node-b-before.out" "$work_directory/node-b-before.err" \
    "$node_b_before_status"
validate_remote_transcript node_a action_17r_node_a "$node_a_inspector" \
    "$work_directory/node-a.out" "$work_directory/node-a.err" "$node_a_status"
validate_remote_transcript node_b_after action_17r_node_b "$node_b_inspector" \
    "$work_directory/node-b-after.out" "$work_directory/node-b-after.err" \
    "$node_b_after_status"

node_a_payload=$(value_for action_17r_node_a_value_payload_sha256 \
    "$work_directory/node-a.out") || node_a_payload=invalid
node_b_payload=$(value_for action_17r_node_b_value_payload_sha256 \
    "$work_directory/node-b-after.out") || node_b_payload=invalid
node_a_manifest=$(value_for action_17r_node_a_value_manifest_sha256 \
    "$work_directory/node-a.out") || node_a_manifest=invalid
node_b_manifest=$(value_for action_17r_node_b_value_manifest_sha256 \
    "$work_directory/node-b-after.out") || node_b_manifest=invalid
node_b_before_state=$(value_for action_17r_node_b_value_before_state_sha256 \
    "$work_directory/node-b-before.out") || node_b_before_state=invalid
node_b_after_state=$(value_for action_17r_node_b_value_after_state_sha256 \
    "$work_directory/node-b-after.out") || node_b_after_state=invalid

record_semantic_command payload_hashes_cross_node_exact \
    test "$node_a_payload" = "$expected_payload_sha256" \
    -a "$node_b_payload" = "$expected_payload_sha256"
record_semantic_command manifest_hashes_cross_node_exact \
    test "$node_a_manifest" = "$expected_manifest_sha256" \
    -a "$node_b_manifest" = "$expected_manifest_sha256"
record_semantic_command node_a_source_state_exact \
    require_one \
    action_17r_node_a_value_source_state=legacy_complete_requires_v2_finalize_request \
    "$work_directory/node-a.out"
record_semantic_command node_b_receiver_state_exact \
    require_one action_17r_node_b_value_receiver_state=installed_policy_ready \
    "$work_directory/node-b-after.out"
record_semantic_command node_b_release_state_exact \
    require_one \
    action_17r_node_b_value_release_state=payload_ready_awaiting_finalize_request \
    "$work_directory/node-b-after.out"
record_semantic_command node_b_bab_state_unchanged \
    test "$node_b_after_state" = "$node_b_before_state"

printf 'action_17r_node_b_before_ssh_status=%s\n' "$node_b_before_status"
printf 'action_17r_node_a_ssh_status=%s\n' "$node_a_status"
printf 'action_17r_node_b_after_ssh_status=%s\n' "$node_b_after_status"
printf 'action_17r_runner_assertion_count=%s\n' "$runner_assertion_count"
printf 'action_17r_runner_failed_assertion_count=%s\n' \
    "$runner_failed_assertion_count"
printf 'action_17r_runner_first_failure=%s\n' "$runner_first_failure"
printf 'action_17r_finalization_readiness=legacy_release_requires_transactional_marker_migration\n'
printf 'action_17r_peer_connection_executed=false\n'
printf 'action_17r_restricted_command_executed=false\n'
printf 'action_17r_release_transfer_executed=false\n'
printf 'action_17r_marker_mutation=false\n'
printf 'action_17r_helper_invocation=false\n'
printf 'action_17r_service_mutations=false\n'
printf 'action_17r_persistent_mutations=false\n'

if [[ "$runner_contract_invalid" = true ]]; then
    printf 'action_17r_runner_acceptance=false\n'
    exit 97
fi
if [[ "$runner_semantic_mismatch" = true ]]; then
    printf 'action_17r_runner_acceptance=false\n'
    exit 1
fi
printf 'action_17r_runner_acceptance=true\n'
cleanup
trap - EXIT
if [[ -e "$work_directory" ]]; then
    printf 'action_17r_workstation_cleanup_complete=false\n' >&2
    exit 97
fi
printf 'action_17r_workstation_cleanup_complete=true\n'
