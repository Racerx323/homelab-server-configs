#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=d892f6e06fee2edfbdcdc5a5d559bafb5234a675b0a2d42d8eb23fd77e85bf96
readonly node_a_target=pi@10.1.0.53
readonly node_a_host_alias=pihole0.local.theama.co
readonly remote_prefix=action_17r_b_node_a
readonly max_stderr_bytes=1024
readonly max_stderr_lines=4
readonly pseudo_terminal_notice='Pseudo-terminal will not be allocated because stdin is not a terminal.'

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly inspector="$script_directory/diagnose-node-a-ssh-g-stderr-action17r-b.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"

runner_assertion_count=0
runner_failed_assertion_count=0
runner_first_failure=none
runner_contract_invalid=false

record_assertion() {
    local assertion_label=$1
    local assertion_value=$2

    runner_assertion_count=$((runner_assertion_count + 1))
    printf 'action_17r_b_runner_assertion_%s=%s\n' \
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

secret_free() {
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]|Bearer[[:space:]]' \
        "$@"
}

transcript_grammar_valid() {
    awk '
        index($0, "action_17r_b_node_a_") != 1 { invalid++ }
        $0 !~ /^[a-z0-9_]+=[A-Za-z0-9_+.:=\/-]+$/ { invalid++ }
        END { exit invalid ? 1 : 0 }
    ' "$1"
}

stderr_has_no_nul() {
    od -An -v -t u1 "$1" |
        awk '{ for (field = 1; field <= NF; field++) if ($field == 0) exit 1 }'
}

stderr_is_printable() {
    ! LC_ALL=C grep -q '[^[:print:][:space:]]' "$1"
}

stderr_is_secret_free() {
    secret_free "$1"
}

line_count() {
    awk 'END { print NR + 0 }' "$1"
}

classify_decoded_stderr() {
    local decoded_file=$1
    local normalized_content

    if [[ ! -s "$decoded_file" ]]; then
        printf 'empty\n'
        return
    fi
    normalized_content=$(tr -d '\r' <"$decoded_file")
    if [[ "$(line_count "$decoded_file")" -eq 1 ]] &&
        [[ "$normalized_content" == "$pseudo_terminal_notice" ]]; then
        printf 'pseudo_terminal_not_allocated\n'
    else
        printf 'safe_unclassified\n'
    fi
}

decode_stderr_value() {
    local encoded_value=$1
    local decoded_file=$2

    if [[ "$encoded_value" == empty ]]; then
        : >"$decoded_file"
        return
    fi
    [[ "$encoded_value" != withheld ]]
    printf '%s' "$encoded_value" | base64 -d >"$decoded_file"
}

verify_sources() {
    [[ -f "$inspector" && ! -L "$inspector" ]]
    [[ "$(file_hash "$inspector")" = "$inspector_sha256" ]]
    bash -n "$inspector"
    "$collision_checker" "$inspector" >/dev/null
    "$inspector" --self-test >/dev/null
    "$inspector" --contract-test >/dev/null
}

verify_workstation_metadata() {
    [[ "$(stat -c '%U:%G:%a' "$0")" = aaron:aaron:755 ]]
    [[ "$(stat -c '%U:%G:%a' "$inspector")" = aaron:aaron:755 ]]
}

assert_source_policy() {
    local prohibited_option

    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
        "$0"; then
        printf 'Action 17r-b contains a service mutation.\n' >&2
        return 1
    fi
    if grep -Eq '^[[:space:]]*(/usr/bin/)?(rsync|scp|sftp)[[:space:]]' "$0"; then
        printf 'Action 17r-b contains a transfer command.\n' >&2
        return 1
    fi
    prohibited_option=Identities
    prohibited_option+=Only=yes
    if grep -Fq "$prohibited_option" "$0"; then
        printf 'Action 17r-b administrative SSH sets the prohibited identity-selection option.\n' >&2
        return 1
    fi
    if grep -Eq 'ACTION17RB_(FIXTURE|STATUS|CAPTURE|CALL)' "$0"; then
        printf 'Production Action 17r-b contains a fixture bypass.\n' >&2
        return 1
    fi
    grep -Fq "'cd / && sudo -n /bin/bash -s --'" "$0"
    # shellcheck disable=SC2016
    grep -Fq '<"$inspector" >"$remote_output" 2>"$remote_error"' "$0"
}

validate_family() {
    local family_name=$1
    local transcript_path=$2
    local decoded_path=$3
    local status_value
    local bytes_value
    local lines_value
    local hash_value
    local classification_value
    local encoded_value
    local decode_status=0

    status_value=$(value_for \
        "${remote_prefix}_value_${family_name}_ssh_g_status" \
        "$transcript_path") || status_value=invalid
    bytes_value=$(value_for \
        "${remote_prefix}_value_${family_name}_stderr_bytes" \
        "$transcript_path") || bytes_value=invalid
    lines_value=$(value_for \
        "${remote_prefix}_value_${family_name}_stderr_lines" \
        "$transcript_path") || lines_value=invalid
    hash_value=$(value_for \
        "${remote_prefix}_value_${family_name}_stderr_sha256" \
        "$transcript_path") || hash_value=invalid
    classification_value=$(value_for \
        "${remote_prefix}_value_${family_name}_stderr_classification" \
        "$transcript_path") || classification_value=invalid
    encoded_value=$(value_for \
        "${remote_prefix}_value_${family_name}_stderr_base64" \
        "$transcript_path") || encoded_value=invalid

    record_command "${family_name}_status_numeric" \
        grep -Eq '^[0-9]{1,3}$' <<<"$status_value"
    record_command "${family_name}_status_zero" test "$status_value" = 0
    record_command "${family_name}_bytes_numeric" \
        grep -Eq '^[0-9]{1,4}$' <<<"$bytes_value"
    record_command "${family_name}_bytes_bounded" \
        test "$bytes_value" -le "$max_stderr_bytes"
    record_command "${family_name}_lines_numeric" \
        grep -Eq '^[0-9]{1,2}$' <<<"$lines_value"
    record_command "${family_name}_lines_bounded" \
        test "$lines_value" -le "$max_stderr_lines"
    record_command "${family_name}_hash_format" \
        grep -Eq '^[0-9a-f]{64}$' <<<"$hash_value"
    record_command "${family_name}_classification_supported" \
        grep -Eq '^(empty|pseudo_terminal_not_allocated|safe_unclassified|unsafe_withheld)$' \
        <<<"$classification_value"
    record_command "${family_name}_encoded_value_supported" \
        grep -Eq '^(empty|withheld|[A-Za-z0-9+/]+={0,2})$' <<<"$encoded_value"

    decode_stderr_value "$encoded_value" "$decoded_path" || decode_status=$?
    record_command "${family_name}_decode_status_zero" test "$decode_status" -eq 0
    if [[ "$decode_status" -eq 0 ]]; then
        record_command "${family_name}_decoded_bytes_exact" \
            test "$(stat -c '%s' "$decoded_path")" = "$bytes_value"
        record_command "${family_name}_decoded_lines_exact" \
            test "$(line_count "$decoded_path")" = "$lines_value"
        record_command "${family_name}_decoded_hash_exact" \
            test "$(file_hash "$decoded_path")" = "$hash_value"
        record_command "${family_name}_decoded_nul_absent" \
            stderr_has_no_nul "$decoded_path"
        record_command "${family_name}_decoded_printable" \
            stderr_is_printable "$decoded_path"
        record_command "${family_name}_decoded_secret_free" \
            stderr_is_secret_free "$decoded_path"
        record_command "${family_name}_classification_matches_decoded" \
            test "$(classify_decoded_stderr "$decoded_path")" = \
            "$classification_value"
    else
        record_assertion "${family_name}_decoded_bytes_exact" false
        record_assertion "${family_name}_decoded_lines_exact" false
        record_assertion "${family_name}_decoded_hash_exact" false
        record_assertion "${family_name}_decoded_nul_absent" false
        record_assertion "${family_name}_decoded_printable" false
        record_assertion "${family_name}_decoded_secret_free" false
        record_command "${family_name}_classification_matches_withheld" \
            test "$classification_value" = unsafe_withheld
    fi
}

validate_remote() {
    local remote_status_value=$1
    local transcript_path=$2
    local error_path=$3
    local expected_labels_path=$4
    local observed_labels_path=$5
    local reported_count
    local reported_failed
    local observed_failed
    local reported_first
    local observed_first
    local before_hash
    local after_hash

    record_command remote_status_supported \
        grep -Eq '^(0|1)$' <<<"$remote_status_value"
    record_command remote_stderr_empty test ! -s "$error_path"
    record_command remote_secret_free secret_free "$transcript_path" "$error_path"
    record_command remote_grammar_valid transcript_grammar_valid "$transcript_path"

    extract_source_labels "$inspector" | LC_ALL=C sort >"$expected_labels_path"
    sed -n \
        "s/^${remote_prefix}_assertion_\([a-z0-9_]*\)=\(true\|false\)$/\1/p" \
        "$transcript_path" | LC_ALL=C sort >"$observed_labels_path"
    record_command remote_assertion_labels_exact \
        cmp -s "$expected_labels_path" "$observed_labels_path"
    record_command remote_assertion_labels_unique \
        test "$(uniq -d "$observed_labels_path" | wc -l)" -eq 0

    reported_count=$(value_for "${remote_prefix}_assertion_count" \
        "$transcript_path") || reported_count=invalid
    record_command remote_reported_count_numeric \
        grep -Eq '^[0-9]+$' <<<"$reported_count"
    record_command remote_reported_count_exact \
        test "$reported_count" = "$(wc -l <"$observed_labels_path")"
    reported_failed=$(value_for "${remote_prefix}_failed_assertion_count" \
        "$transcript_path") || reported_failed=invalid
    observed_failed=$(grep -Ec \
        "^${remote_prefix}_assertion_[a-z0-9_]+=false$" \
        "$transcript_path")
    record_command remote_reported_failed_numeric \
        grep -Eq '^[0-9]+$' <<<"$reported_failed"
    record_command remote_reported_failed_exact \
        test "$reported_failed" = "$observed_failed"
    reported_first=$(value_for "${remote_prefix}_first_failure" \
        "$transcript_path") || reported_first=invalid
    observed_first=$(sed -n \
        "s/^${remote_prefix}_assertion_\([a-z0-9_]*\)=false$/\1/p" \
        "$transcript_path" | head -n 1)
    observed_first=${observed_first:-none}
    record_command remote_first_failure_exact \
        test "$reported_first" = "$observed_first"
    if [[ "$remote_status_value" -eq 0 ]]; then
        record_command remote_status_semantic test "$reported_failed" = 0
    else
        record_command remote_status_semantic test "$reported_failed" -gt 0
    fi

    before_hash=$(value_for "${remote_prefix}_value_before_state_sha256" \
        "$transcript_path") || before_hash=invalid
    after_hash=$(value_for "${remote_prefix}_value_after_state_sha256" \
        "$transcript_path") || after_hash=invalid
    record_command before_hash_format grep -Eq '^[0-9a-f]{64}$' <<<"$before_hash"
    record_command after_hash_format grep -Eq '^[0-9a-f]{64}$' <<<"$after_hash"
    record_command state_unchanged test "$before_hash" = "$after_hash"
    for required_record in \
        "${remote_prefix}_peer_connection_executed=false" \
        "${remote_prefix}_restricted_command_executed=false" \
        "${remote_prefix}_release_transfer_executed=false" \
        "${remote_prefix}_marker_mutation=false" \
        "${remote_prefix}_helper_invocation=false" \
        "${remote_prefix}_service_mutations=false" \
        "${remote_prefix}_persistent_mutations=false" \
        "${remote_prefix}_remote_complete=true"; do
        required_label=${required_record#"${remote_prefix}_"}
        required_label=${required_label%%=*}
        record_command "remote_${required_label}_exact" \
            require_one "$required_record" "$transcript_path"
    done
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_sources
    printf 'action_17r_b_runner_self_test_complete=true\n'
    exit 0
fi
if [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_sources
    assert_source_policy
    printf 'action_17r_b_runner_source_test_complete=true\n'
    exit 0
fi
if [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    verify_sources
    assert_source_policy
    printf 'action_17r_b_runner_contract_test_complete=true\n'
    exit 0
fi
if (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_sources
assert_source_policy
verify_workstation_metadata
work_directory=$(mktemp -d /tmp/caddy-action17r-b-runner.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

readonly remote_output="$work_directory/node-a.out"
readonly remote_error="$work_directory/node-a.err"
readonly expected_labels="$work_directory/node-a.expected"
readonly observed_labels="$work_directory/node-a.observed"
readonly ipv4_decoded="$work_directory/ipv4.stderr"
readonly ipv6_decoded="$work_directory/ipv6.stderr"

remote_status=0
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
    <"$inspector" >"$remote_output" 2>"$remote_error" || remote_status=$?

validate_remote "$remote_status" "$remote_output" "$remote_error" \
    "$expected_labels" "$observed_labels"
validate_family ipv4 "$remote_output" "$ipv4_decoded"
validate_family ipv6 "$remote_output" "$ipv6_decoded"

remote_safe=false
if secret_free "$remote_output" "$remote_error" "$ipv4_decoded" "$ipv6_decoded" &&
    transcript_grammar_valid "$remote_output"; then
    remote_safe=true
fi
record_command remote_safe_to_emit test "$remote_safe" = true
if [[ "$remote_safe" == true ]]; then
    printf 'action_17r_b_node_a_transcript_begin=true\n'
    cat -- "$remote_output"
    printf 'action_17r_b_node_a_transcript_end=true\n'
fi

ipv4_classification=$(value_for \
    "${remote_prefix}_value_ipv4_stderr_classification" "$remote_output") ||
    ipv4_classification=invalid
ipv6_classification=$(value_for \
    "${remote_prefix}_value_ipv6_stderr_classification" "$remote_output") ||
    ipv6_classification=invalid
diagnostic_conclusion=safe_stderr_classification_captured
if [[ "$ipv4_classification" == pseudo_terminal_not_allocated ]] &&
    [[ "$ipv6_classification" == pseudo_terminal_not_allocated ]]; then
    diagnostic_conclusion=pseudo_terminal_notice_confirmed_dual_stack
elif [[ "$ipv4_classification" == empty ]] &&
    [[ "$ipv6_classification" == empty ]]; then
    diagnostic_conclusion=stderr_empty_dual_stack
fi

printf '%s\n' \
    "action_17r_b_remote_ssh_status=$remote_status" \
    "action_17r_b_ipv4_stderr_classification=$ipv4_classification" \
    "action_17r_b_ipv6_stderr_classification=$ipv6_classification" \
    "action_17r_b_diagnostic_conclusion=$diagnostic_conclusion" \
    "action_17r_b_runner_assertion_count=$runner_assertion_count" \
    "action_17r_b_runner_failed_assertion_count=$runner_failed_assertion_count" \
    "action_17r_b_runner_first_failure=$runner_first_failure" \
    action_17r_b_peer_connection_executed=false \
    action_17r_b_restricted_command_executed=false \
    action_17r_b_release_transfer_executed=false \
    action_17r_b_marker_mutation=false \
    action_17r_b_helper_invocation=false \
    action_17r_b_service_mutations=false \
    action_17r_b_persistent_mutations=false

if [[ "$runner_contract_invalid" == true ]]; then
    printf 'action_17r_b_runner_acceptance=false\n'
    exit 97
fi
printf 'action_17r_b_runner_acceptance=true\n'
printf 'action_17r_b_workstation_cleanup_complete=true\n'
cleanup
trap - EXIT
