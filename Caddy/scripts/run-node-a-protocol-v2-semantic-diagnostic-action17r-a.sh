#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly baseline_runner_sha256=ce8b1ba0641c2a03b9aa593c94ddecd1c27ff3ef73e094820d4bb0dc8b8ec71b
readonly node_a_inspector_sha256=e181f2e38f98f9df39bfb4992b4e4f91a786e738566c385becbe722709b931f1
readonly expected_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly expected_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly node_a_target=pi@10.1.0.53
readonly node_a_host_alias=pihole0.local.theama.co

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly baseline_runner="$script_directory/run-dual-node-protocol-v2-readiness-action17r.sh"
readonly node_a_inspector="$script_directory/inspect-node-a-protocol-v2-readiness-action17r.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"

runner_assertion_count=0
runner_failed_assertion_count=0
runner_first_failure=none
runner_contract_invalid=false

record_assertion() {
    local assertion_label=$1
    local assertion_value=$2

    runner_assertion_count=$((runner_assertion_count + 1))
    printf 'action_17r_a_runner_assertion_%s=%s\n' \
        "$assertion_label" "$assertion_value"
    if [[ "$assertion_value" != true ]]; then
        runner_failed_assertion_count=$((runner_failed_assertion_count + 1))
        if [[ "$runner_first_failure" == none ]]; then
            runner_first_failure=$assertion_label
        fi
        runner_contract_invalid=true
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

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

is_nonnegative_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

is_sha256() {
    [[ "$1" =~ ^[0-9a-f]{64}$ ]]
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

secret_free() {
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$@"
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

verify_sources() {
    local verified_path

    for verified_path in "$baseline_runner" "$node_a_inspector"; do
        [[ -f "$verified_path" && ! -L "$verified_path" ]]
        [[ "$(stat -c '%U:%G:%a' "$verified_path")" = aaron:aaron:755 ]]
        bash -n "$verified_path"
        "$collision_checker" "$verified_path" >/dev/null
    done
    [[ "$(file_hash "$baseline_runner")" = "$baseline_runner_sha256" ]]
    [[ "$(file_hash "$node_a_inspector")" = "$node_a_inspector_sha256" ]]
    "$baseline_runner" --self-test >/dev/null
    "$baseline_runner" --source-test >/dev/null
    "$baseline_runner" --contract-test >/dev/null
    "$node_a_inspector" --self-test >/dev/null
    [[ "$(extract_source_labels "$node_a_inspector" | wc -l)" -eq 52 ]]
}

assert_source_policy() {
    local prohibited_option

    prohibited_option=Identities
    prohibited_option+=Only=yes
    if grep -Fq "$prohibited_option" "$0"; then
        printf 'Action 17r-a administrative SSH disables agent identity selection.\n' >&2
        return 1
    fi
    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
        "$0"; then
        printf 'Action 17r-a contains a service mutation.\n' >&2
        return 1
    fi
    if grep -Eq '^[[:space:]]*(/usr/bin/)?(rsync|scp|sftp)[[:space:]]' "$0"; then
        printf 'Action 17r-a contains a transfer command.\n' >&2
        return 1
    fi
    if grep -Eq 'ACTION17RA_(FIXTURE|STATUS|CAPTURE|CALL)' "$0"; then
        printf 'Production Action 17r-a contains a fixture bypass.\n' >&2
        return 1
    fi
    # These assertions intentionally match literal production shell source.
    # shellcheck disable=SC2016
    grep -Fq '"$baseline_runner" >"$baseline_output"' "$0"
    # shellcheck disable=SC2016
    grep -Fq '"$node_a_target"' "$0"
    grep -Fq "'cd / && sudo -n /bin/bash -s --'" "$0"
    # shellcheck disable=SC2016
    grep -Fq 'cat -- "$node_a_output"' "$0"
}

validate_baseline() {
    local baseline_status_value=$1
    local baseline_transcript=$2
    local checked_baseline_error=$3
    local baseline_node_a_status
    local expected_acceptance

    record_command baseline_status_supported \
        test "$baseline_status_value" -ge 0
    record_command baseline_status_bounded \
        test "$baseline_status_value" -le 1
    record_command baseline_stderr_empty test ! -s "$checked_baseline_error"
    record_command baseline_secret_free \
        secret_free "$baseline_transcript" "$checked_baseline_error"
    record_command baseline_grammar_valid \
        transcript_grammar_valid action_17r "$baseline_transcript"
    record_command baseline_node_b_before_ssh_zero \
        require_one action_17r_node_b_before_ssh_status=0 "$baseline_transcript"
    record_command baseline_node_b_after_ssh_zero \
        require_one action_17r_node_b_after_ssh_status=0 "$baseline_transcript"
    record_command baseline_node_b_before_assertions_passed \
        require_one action_17r_runner_assertion_node_b_before_remote_assertions_passed=true \
        "$baseline_transcript"
    record_command baseline_node_b_after_assertions_passed \
        require_one action_17r_runner_assertion_node_b_after_remote_assertions_passed=true \
        "$baseline_transcript"
    record_command baseline_payload_cross_node_exact \
        require_one action_17r_runner_assertion_payload_hashes_cross_node_exact=true \
        "$baseline_transcript"
    record_command baseline_manifest_cross_node_exact \
        require_one action_17r_runner_assertion_manifest_hashes_cross_node_exact=true \
        "$baseline_transcript"
    record_command baseline_node_a_source_state_exact \
        require_one action_17r_runner_assertion_node_a_source_state_exact=true \
        "$baseline_transcript"
    record_command baseline_node_b_receiver_state_exact \
        require_one action_17r_runner_assertion_node_b_receiver_state_exact=true \
        "$baseline_transcript"
    record_command baseline_node_b_release_state_exact \
        require_one action_17r_runner_assertion_node_b_release_state_exact=true \
        "$baseline_transcript"
    record_command baseline_node_b_bab_state_unchanged \
        require_one action_17r_runner_assertion_node_b_bab_state_unchanged=true \
        "$baseline_transcript"
    record_command baseline_peer_connection_false \
        require_one action_17r_peer_connection_executed=false "$baseline_transcript"
    record_command baseline_restricted_command_false \
        require_one action_17r_restricted_command_executed=false "$baseline_transcript"
    record_command baseline_release_transfer_false \
        require_one action_17r_release_transfer_executed=false "$baseline_transcript"
    record_command baseline_marker_mutation_false \
        require_one action_17r_marker_mutation=false "$baseline_transcript"
    record_command baseline_helper_invocation_false \
        require_one action_17r_helper_invocation=false "$baseline_transcript"
    record_command baseline_service_mutations_false \
        require_one action_17r_service_mutations=false "$baseline_transcript"
    record_command baseline_persistent_mutations_false \
        require_one action_17r_persistent_mutations=false "$baseline_transcript"
    record_command baseline_readiness_exact \
        require_one action_17r_finalization_readiness=legacy_release_requires_transactional_marker_migration \
        "$baseline_transcript"

    baseline_node_a_status=$(value_for action_17r_node_a_ssh_status \
        "$baseline_transcript") || baseline_node_a_status=invalid
    record_command baseline_node_a_status_numeric \
        is_nonnegative_integer "$baseline_node_a_status"
    record_command baseline_node_a_status_supported \
        test "$baseline_node_a_status" = 0 -o "$baseline_node_a_status" = 1
    record_command baseline_status_matches_node_a \
        test "$baseline_status_value" = "$baseline_node_a_status"

    expected_acceptance=true
    if [[ "$baseline_status_value" -eq 1 ]]; then
        expected_acceptance=false
    fi
    record_command baseline_acceptance_semantic \
        require_one "action_17r_runner_acceptance=$expected_acceptance" \
        "$baseline_transcript"
}

validate_node_a() {
    local node_a_status_value=$1
    local node_a_transcript=$2
    local checked_node_a_error=$3
    local checked_expected_labels=$4
    local checked_observed_labels=$5
    local expected_count
    local observed_count
    local reported_count
    local failed_count
    local reported_failed
    local reported_first
    local computed_first
    local before_hash
    local after_hash
    local expected_status

    extract_source_labels "$node_a_inspector" | LC_ALL=C sort >"$checked_expected_labels"
    sed -n \
        's/^action_17r_node_a_assertion_\([a-z0-9_]*\)=\(true\|false\)$/\1/p' \
        "$node_a_transcript" | LC_ALL=C sort >"$checked_observed_labels"
    expected_count=$(wc -l <"$checked_expected_labels")
    observed_count=$(wc -l <"$checked_observed_labels")
    reported_count=$(value_for action_17r_node_a_assertion_count \
        "$node_a_transcript") || reported_count=invalid
    failed_count=$(grep -Ec \
        '^action_17r_node_a_assertion_[a-z0-9_]+=false$' \
        "$node_a_transcript" || true)
    reported_failed=$(value_for action_17r_node_a_failed_assertion_count \
        "$node_a_transcript") || reported_failed=invalid
    reported_first=$(value_for action_17r_node_a_first_failure \
        "$node_a_transcript") || reported_first=invalid
    computed_first=$(sed -n \
        's/^action_17r_node_a_assertion_\([a-z0-9_]*\)=false$/\1/p' \
        "$node_a_transcript" | head -n 1)
    if [[ -z "$computed_first" ]]; then
        computed_first=none
    fi
    expected_status=0
    if [[ "$failed_count" -gt 0 ]]; then
        expected_status=1
    fi
    before_hash=$(value_for action_17r_node_a_value_before_state_sha256 \
        "$node_a_transcript") || before_hash=invalid
    after_hash=$(value_for action_17r_node_a_value_after_state_sha256 \
        "$node_a_transcript") || after_hash=invalid

    record_command node_a_status_supported test "$node_a_status_value" -ge 0
    record_command node_a_status_bounded test "$node_a_status_value" -le 1
    record_command node_a_stderr_empty test ! -s "$checked_node_a_error"
    record_command node_a_secret_free \
        secret_free "$node_a_transcript" "$checked_node_a_error"
    record_command node_a_grammar_valid \
        transcript_grammar_valid action_17r_node_a "$node_a_transcript"
    record_command node_a_expected_assertion_count_exact \
        test "$expected_count" -eq 52
    record_command node_a_observed_assertion_count_exact \
        test "$observed_count" -eq "$expected_count"
    record_command node_a_assertion_labels_exact \
        cmp -s "$checked_expected_labels" "$checked_observed_labels"
    record_command node_a_assertion_labels_unique \
        test "$(sort -u "$checked_observed_labels" | wc -l)" -eq "$observed_count"
    record_command node_a_reported_count_numeric \
        is_nonnegative_integer "$reported_count"
    record_command node_a_reported_count_exact \
        test "$reported_count" = "$observed_count"
    record_command node_a_reported_failed_numeric \
        is_nonnegative_integer "$reported_failed"
    record_command node_a_reported_failed_exact \
        test "$reported_failed" = "$failed_count"
    record_command node_a_first_failure_exact \
        test "$reported_first" = "$computed_first"
    record_command node_a_status_semantic \
        test "$node_a_status_value" -eq "$expected_status"
    record_command node_a_before_hash_format is_sha256 "$before_hash"
    record_command node_a_after_hash_format is_sha256 "$after_hash"
    record_command node_a_state_unchanged test "$after_hash" = "$before_hash"
    record_command node_a_payload_hash_exact \
        require_one "action_17r_node_a_value_payload_sha256=$expected_payload_sha256" \
        "$node_a_transcript"
    record_command node_a_manifest_hash_exact \
        require_one "action_17r_node_a_value_manifest_sha256=$expected_manifest_sha256" \
        "$node_a_transcript"
    record_command node_a_source_state_exact \
        require_one action_17r_node_a_value_source_state=legacy_complete_requires_v2_finalize_request \
        "$node_a_transcript"
    record_command node_a_peer_connection_false \
        require_one action_17r_node_a_peer_connection_executed=false \
        "$node_a_transcript"
    record_command node_a_restricted_command_false \
        require_one action_17r_node_a_restricted_command_executed=false \
        "$node_a_transcript"
    record_command node_a_release_transfer_false \
        require_one action_17r_node_a_release_transfer_executed=false \
        "$node_a_transcript"
    record_command node_a_marker_mutation_false \
        require_one action_17r_node_a_marker_mutation=false "$node_a_transcript"
    record_command node_a_helper_invocation_false \
        require_one action_17r_node_a_helper_invocation=false "$node_a_transcript"
    record_command node_a_service_mutations_false \
        require_one action_17r_node_a_service_mutations=false "$node_a_transcript"
    record_command node_a_persistent_mutations_false \
        require_one action_17r_node_a_persistent_mutations=false "$node_a_transcript"
    record_command node_a_remote_complete \
        require_one action_17r_node_a_remote_complete=true "$node_a_transcript"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_sources
    printf 'action_17r_a_runner_self_test_complete=true\n'
    exit 0
fi
if [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_sources
    assert_source_policy
    printf 'action_17r_a_runner_source_test_complete=true\n'
    exit 0
fi
if [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    verify_sources
    assert_source_policy
    printf 'action_17r_a_runner_contract_test_complete=true\n'
    exit 0
fi
if (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_sources
assert_source_policy
work_directory=$(mktemp -d /tmp/caddy-action17r-a-runner.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

readonly baseline_output="$work_directory/baseline.out"
readonly baseline_error="$work_directory/baseline.err"
readonly node_a_output="$work_directory/node-a.out"
readonly node_a_error="$work_directory/node-a.err"
readonly expected_labels="$work_directory/node-a.expected"
readonly observed_labels="$work_directory/node-a.observed"

baseline_status=0
"$baseline_runner" >"$baseline_output" 2>"$baseline_error" || baseline_status=$?
node_a_status=0
ssh -T \
    -o BatchMode=yes \
    -o ClearAllForwardings=yes \
    -o ConnectTimeout=10 \
    -o "HostKeyAlias=$node_a_host_alias" \
    -o KbdInteractiveAuthentication=no \
    -o PasswordAuthentication=no \
    -o PreferredAuthentications=publickey \
    -o StrictHostKeyChecking=yes \
    "$node_a_target" \
    'cd / && sudo -n /bin/bash -s --' \
    <"$node_a_inspector" >"$node_a_output" 2>"$node_a_error" ||
    node_a_status=$?

validate_baseline "$baseline_status" "$baseline_output" "$baseline_error"
validate_node_a "$node_a_status" "$node_a_output" "$node_a_error" \
    "$expected_labels" "$observed_labels"
baseline_node_a_status=$(value_for action_17r_node_a_ssh_status \
    "$baseline_output") || baseline_node_a_status=invalid
record_command node_a_status_matches_baseline \
    test "$node_a_status" = "$baseline_node_a_status"

baseline_safe=false
if secret_free "$baseline_output" "$baseline_error" &&
    transcript_grammar_valid action_17r "$baseline_output"; then
    baseline_safe=true
fi
node_a_safe=false
if secret_free "$node_a_output" "$node_a_error" &&
    transcript_grammar_valid action_17r_node_a "$node_a_output"; then
    node_a_safe=true
fi
record_command baseline_safe_to_emit test "$baseline_safe" = true
record_command node_a_safe_to_emit test "$node_a_safe" = true

if [[ "$baseline_safe" == true ]]; then
    printf 'action_17r_a_baseline_transcript_begin=true\n'
    cat -- "$baseline_output"
    printf 'action_17r_a_baseline_transcript_end=true\n'
fi
if [[ "$node_a_safe" == true ]]; then
    printf 'action_17r_a_node_a_transcript_begin=true\n'
    cat -- "$node_a_output"
    printf 'action_17r_a_node_a_transcript_end=true\n'
fi

node_a_failed=$(value_for action_17r_node_a_failed_assertion_count \
    "$node_a_output") || node_a_failed=invalid
node_a_first=$(value_for action_17r_node_a_first_failure \
    "$node_a_output") || node_a_first=invalid
diagnostic_conclusion=node_a_ready
if [[ "$node_a_status" -eq 1 ]]; then
    diagnostic_conclusion=node_a_semantic_mismatch_identified
fi

printf '%s\n' \
    "action_17r_a_baseline_status=$baseline_status" \
    "action_17r_a_node_a_ssh_status=$node_a_status" \
    "action_17r_a_node_a_failed_assertion_count=$node_a_failed" \
    "action_17r_a_node_a_first_failure=$node_a_first" \
    "action_17r_a_diagnostic_conclusion=$diagnostic_conclusion" \
    "action_17r_a_runner_assertion_count=$runner_assertion_count" \
    "action_17r_a_runner_failed_assertion_count=$runner_failed_assertion_count" \
    "action_17r_a_runner_first_failure=$runner_first_failure" \
    action_17r_a_peer_connection_executed=false \
    action_17r_a_restricted_command_executed=false \
    action_17r_a_release_transfer_executed=false \
    action_17r_a_marker_mutation=false \
    action_17r_a_helper_invocation=false \
    action_17r_a_service_mutations=false \
    action_17r_a_persistent_mutations=false

if [[ "$runner_contract_invalid" == true ]]; then
    printf 'action_17r_a_runner_acceptance=false\n'
    exit 97
fi
printf 'action_17r_a_runner_acceptance=true\n'
printf 'action_17r_a_workstation_cleanup_complete=true\n'
cleanup
trap - EXIT
