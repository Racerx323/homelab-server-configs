#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_17s_a
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co
readonly inspector_sha256=adae35e14b9639c0cfb66ddac33e93e71489c4a06bdca3e10376248c54543da1
readonly expected_finalizer_sha256=a49dadcaa611e641a100e6a4f2b1836fcf9a790876f437ee02e37003d78ef30c
readonly expected_validate_block_sha256=d198df3898fdb385b54d0c95bc99c0d8ad4ad6ed0045e1d51dccee3e6e02aefb
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly inspector="$script_directory/inspect-node-b-action17s-rollback-output-action17s-a.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

line_count() {
    awk 'END { print NR }' "$1"
}

is_nonnegative_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
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
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$@"
}

transcript_grammar_valid() {
    local grammar_transcript=$1

    awk '
        index($0, "action_17s_a_") != 1 { invalid++ }
        $0 !~ /^[a-z0-9_]+=([A-Za-z0-9_.:,\/-]+)$/ { invalid++ }
        END { exit invalid ? 1 : 0 }
    ' "$grammar_transcript"
}

verify_inspector() {
    [[ -f "$inspector" && ! -L "$inspector" ]]
    [[ "$(stat -c '%U:%G:%a' "$inspector")" = aaron:aaron:755 ]]
    [[ "$(file_hash "$inspector")" = "$inspector_sha256" ]]
    bash -n "$inspector"
    "$collision_checker" "$inspector" >/dev/null
    "$inspector" --self-test >/dev/null
}

validate_assertion_set() {
    local assertion_transcript=$1
    local expected_labels_path
    local observed_labels_path
    local expected_count
    local observed_count
    local reported_count
    local reported_failed
    local computed_failed
    local reported_first
    local computed_first

    expected_labels_path=$(mktemp "$work_directory/expected.XXXXXX")
    observed_labels_path=$(mktemp "$work_directory/observed.XXXXXX")
    "$inspector" --expected-checks | LC_ALL=C sort >"$expected_labels_path"
    sed -n \
        's/^action_17s_a_assertion_\([a-z0-9_]*\)=\(true\|false\)$/\1/p' \
        "$assertion_transcript" | LC_ALL=C sort >"$observed_labels_path"
    expected_count=$(wc -l <"$expected_labels_path")
    observed_count=$(wc -l <"$observed_labels_path")
    reported_count=$(value_for action_17s_a_assertion_count \
        "$assertion_transcript") || reported_count=invalid
    reported_failed=$(value_for action_17s_a_failed_assertion_count \
        "$assertion_transcript") || reported_failed=invalid
    computed_failed=$(grep -Ec '^action_17s_a_assertion_[a-z0-9_]+=false$' \
        "$assertion_transcript" || true)
    reported_first=$(value_for action_17s_a_first_failure \
        "$assertion_transcript") || reported_first=invalid
    computed_first=$(sed -n \
        's/^action_17s_a_assertion_\([a-z0-9_]*\)=false$/\1/p' \
        "$assertion_transcript" | head -n 1)
    [[ -n "$computed_first" ]] || computed_first=none

    [[ "$expected_count" -gt 50 ]] || return 1
    [[ "$observed_count" -eq "$expected_count" ]] || return 1
    [[ "$(sort -u "$observed_labels_path" | wc -l)" -eq "$observed_count" ]] ||
        return 1
    cmp -s "$expected_labels_path" "$observed_labels_path" || return 1
    is_nonnegative_integer "$reported_count" || return 1
    [[ "$reported_count" -eq "$observed_count" ]] || return 1
    is_nonnegative_integer "$reported_failed" || return 1
    [[ "$reported_failed" -eq "$computed_failed" ]] || return 1
    [[ "$reported_first" = "$computed_first" ]]
}

validate_transcript() {
    local validation_transcript=$1
    local validation_status=$2
    local failed_count

    transcript_grammar_valid "$validation_transcript"
    secret_free "$validation_transcript"
    validate_assertion_set "$validation_transcript"
    require_one \
        "action_17s_a_value_finalizer_sha256=$expected_finalizer_sha256" \
        "$validation_transcript"
    require_one action_17s_a_value_validate_block_lines=7 \
        "$validation_transcript"
    require_one \
        "action_17s_a_value_validate_block_sha256=$expected_validate_block_sha256" \
        "$validation_transcript"
    require_one \
        action_17s_a_value_stdout_source_classification=unsuppressed_caddy_validate_success_path \
        "$validation_transcript"
    require_one action_17s_a_prior_stdout_bytes_recoverable=false \
        "$validation_transcript"
    require_one action_17s_a_prior_stdout_lines_recoverable=false \
        "$validation_transcript"
    require_one action_17s_a_prior_stdout_sha256_recoverable=false \
        "$validation_transcript"
    require_one action_17s_a_finalizer_invoked=false "$validation_transcript"
    require_one action_17s_a_raw_stdout_source_emitted=false \
        "$validation_transcript"
    require_one action_17s_a_filesystem_mutations=false "$validation_transcript"
    require_one action_17s_a_service_mutations=false "$validation_transcript"
    require_one action_17s_a_persistent_mutations=false "$validation_transcript"

    failed_count=$(value_for action_17s_a_failed_assertion_count \
        "$validation_transcript")
    if [[ "$validation_status" -eq 0 ]]; then
        [[ "$failed_count" -eq 0 ]]
        require_one action_17s_a_first_failure=none "$validation_transcript"
        require_one action_17s_a_node_b_read_only_inspection_complete=true \
            "$validation_transcript"
    elif [[ "$validation_status" -eq 1 ]]; then
        [[ "$failed_count" -gt 0 ]]
        [[ "$(value_for action_17s_a_first_failure "$validation_transcript")" != none ]]
        [[ "$(grep -Fc 'action_17s_a_node_b_read_only_inspection_complete=true' \
            "$validation_transcript")" -eq 0 ]]
    else
        return 1
    fi
}

make_contract_fixture() {
    local fixture_path=$1
    local fixture_label
    local fixture_count=0

    {
        while IFS= read -r fixture_label; do
            printf 'action_17s_a_assertion_%s=true\n' "$fixture_label"
            fixture_count=$((fixture_count + 1))
        done < <("$inspector" --expected-checks)
        printf 'action_17s_a_assertion_count=%s\n' "$fixture_count"
        printf 'action_17s_a_failed_assertion_count=0\n'
        printf 'action_17s_a_first_failure=none\n'
        printf 'action_17s_a_value_finalizer_sha256=%s\n' \
            "$expected_finalizer_sha256"
        printf 'action_17s_a_value_validate_block_lines=7\n'
        printf 'action_17s_a_value_validate_block_sha256=%s\n' \
            "$expected_validate_block_sha256"
        printf 'action_17s_a_value_stdout_source_classification=unsuppressed_caddy_validate_success_path\n'
        printf 'action_17s_a_prior_stdout_bytes_recoverable=false\n'
        printf 'action_17s_a_prior_stdout_lines_recoverable=false\n'
        printf 'action_17s_a_prior_stdout_sha256_recoverable=false\n'
        printf 'action_17s_a_finalizer_invoked=false\n'
        printf 'action_17s_a_raw_stdout_source_emitted=false\n'
        printf 'action_17s_a_filesystem_mutations=false\n'
        printf 'action_17s_a_service_mutations=false\n'
        printf 'action_17s_a_persistent_mutations=false\n'
        printf 'action_17s_a_node_b_read_only_inspection_complete=true\n'
    } >"$fixture_path"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$expected_target" = pi@10.1.0.54 ]]
        [[ "$expected_host_alias" = pihole00.local.theama.co ]]
        [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
        printf '%s_runner_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --source-test)
        [[ $# -eq 1 ]]
        verify_inspector
        printf '%s_runner_source_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]]
        work_directory=$(mktemp -d /tmp/caddy-action17s-a-contract.XXXXXX)
        readonly work_directory
        trap 'rm -rf -- "$work_directory"' EXIT
        make_contract_fixture "$work_directory/valid"
        validate_transcript "$work_directory/valid" 0
        sed \
            's/action_17s_a_assertion_complete_absent=true/action_17s_a_assertion_complete_absent=false/; s/action_17s_a_failed_assertion_count=0/action_17s_a_failed_assertion_count=1/; s/action_17s_a_first_failure=none/action_17s_a_first_failure=complete_absent/; /action_17s_a_node_b_read_only_inspection_complete=true/d' \
            "$work_directory/valid" >"$work_directory/mismatch"
        validate_transcript "$work_directory/mismatch" 1
        if validate_transcript "$work_directory/mismatch" 0; then
            exit 1
        fi
        printf '%s_runner_contract_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 2
        ;;
esac

verify_inspector
work_directory=$(mktemp -d /tmp/caddy-action17s-a-runner.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly remote_output="$work_directory/node-b.out"
readonly remote_error="$work_directory/node-b.err"

ssh_status=0
ulimit -f 2048
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias="$expected_host_alias" \
    -o StrictHostKeyChecking=yes \
    "$expected_target" \
    'cd / && sudo -n /bin/bash -s' \
    <"$inspector" >"$remote_output" 2>"$remote_error" || ssh_status=$?
readonly ssh_status

stdout_bytes=$(wc -c <"$remote_output")
stdout_lines=$(line_count "$remote_output")
stdout_sha256=$(file_hash "$remote_output")
stderr_bytes=$(wc -c <"$remote_error")
stderr_lines=$(line_count "$remote_error")
stderr_sha256=$(file_hash "$remote_error")
readonly stdout_bytes stdout_lines stdout_sha256
readonly stderr_bytes stderr_lines stderr_sha256
stdout_classification=captured_within_bounds
stderr_classification=captured_within_bounds
if [[ "$stdout_bytes" -gt "$maximum_stream_bytes" ||
    "$stdout_lines" -gt "$maximum_stream_lines" ]]; then
    stdout_classification=limit_exceeded
fi
if [[ "$stderr_bytes" -eq 0 ]]; then
    stderr_classification=empty
elif [[ "$stderr_bytes" -gt "$maximum_stream_bytes" ||
    "$stderr_lines" -gt "$maximum_stream_lines" ]]; then
    stderr_classification=limit_exceeded
fi
readonly stdout_classification stderr_classification

printf '%s_ssh_status=%s\n' "$prefix" "$ssh_status"
printf '%s_remote_stdout_bytes=%s\n' "$prefix" "$stdout_bytes"
printf '%s_remote_stdout_lines=%s\n' "$prefix" "$stdout_lines"
printf '%s_remote_stdout_sha256=%s\n' "$prefix" "$stdout_sha256"
printf '%s_remote_stdout_classification=%s\n' \
    "$prefix" "$stdout_classification"
printf '%s_remote_stderr_bytes=%s\n' "$prefix" "$stderr_bytes"
printf '%s_remote_stderr_lines=%s\n' "$prefix" "$stderr_lines"
printf '%s_remote_stderr_sha256=%s\n' "$prefix" "$stderr_sha256"
printf '%s_remote_stderr_classification=%s\n' \
    "$prefix" "$stderr_classification"
printf '%s_remote_stderr_raw_emitted=false\n' "$prefix"

if [[ "$stdout_classification" != captured_within_bounds ||
    "$stderr_classification" != empty || ! "$ssh_status" =~ ^[01]$ ]] ||
    ! validate_transcript "$remote_output" "$ssh_status"; then
    printf '%s_runner_acceptance=false\n' "$prefix" >&2
    printf '%s_workstation_cleanup_complete=true\n' "$prefix" >&2
    exit 97
fi

sed -n '/^action_17s_a_/p' "$remote_output"
if [[ "$ssh_status" -eq 0 ]]; then
    printf '%s_runner_acceptance=true\n' "$prefix"
else
    printf '%s_runner_acceptance=false\n' "$prefix"
fi
printf '%s_workstation_cleanup_complete=true\n' "$prefix"
exit "$ssh_status"
