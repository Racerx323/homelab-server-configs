#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_17s_b
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co
readonly inspector_sha256=2f2648a9ac9eadf784b17eb3509375a1af7232717d19a9257b06a89f4bf3a992
readonly expected_finalizer_sha256=e5ec5aab0f57b9ea68c41f122de282c1d156a6747f9f74dd1f22200079c097e4
readonly expected_validate_block_sha256=be85e806dfefe0781806e8f95f00c2e1e1d4ef9393aca24efa2a382bad99ccde
readonly expected_failed_stderr_sha256=dd0e90054410c6fd8e6c9812dd9162eaead43bc3b2d9c67cbe4854b589d351c2
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly inspector="$script_directory/inspect-node-b-action17s-retry-stderr-action17s-b.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
is_nonnegative_integer() { [[ "$1" =~ ^[0-9]+$ ]]; }

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
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' "$@"
}

classify_stream() {
    local classification_path=$1
    local classification_bytes=$2
    local classification_lines=$3

    if [[ "$classification_bytes" -eq 0 ]]; then
        printf 'empty\n'
    elif [[ "$classification_bytes" -gt "$maximum_stream_bytes" ||
        "$classification_lines" -gt "$maximum_stream_lines" ]]; then
        printf 'limit_exceeded\n'
    elif ! secret_free "$classification_path"; then
        printf 'unsafe\n'
    else
        printf 'captured_within_bounds_safe\n'
    fi
}

emit_safe_content() {
    local content_name=$1
    local content_path=$2
    local content_classification=$3

    if [[ "$content_classification" == captured_within_bounds_safe ]]; then
        printf '%s_remote_%s_safe_content_begin=true\n' "$prefix" "$content_name"
        sed -n '1,4096p' "$content_path"
        printf '%s_remote_%s_safe_content_end=true\n' "$prefix" "$content_name"
        printf '%s_remote_%s_content_secured=emitted\n' "$prefix" "$content_name"
    elif [[ "$content_classification" == empty ]]; then
        printf '%s_remote_%s_content_secured=empty\n' "$prefix" "$content_name"
    else
        chmod 0700 "$work_directory"
        chmod 0600 "$content_path"
        retain_work_directory=true
        printf '%s_remote_%s_content_secured=protected_retention\n' \
            "$prefix" "$content_name"
        printf '%s_remote_%s_protected_path=%s\n' \
            "$prefix" "$content_name" "$content_path"
        printf '%s_remote_%s_protected_metadata=%s\n' \
            "$prefix" "$content_name" "$(stat -c '%U:%G:%a' "$content_path")"
        printf '%s_remote_%s_protected_sha256=%s\n' \
            "$prefix" "$content_name" "$(file_hash "$content_path")"
    fi
}

transcript_grammar_valid() {
    local grammar_transcript=$1
    awk '
        index($0, "action_17s_b_") != 1 { invalid++ }
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
    local expected_labels_path="$work_directory/expected.labels"
    local observed_labels_path="$work_directory/observed.labels"
    local expected_count observed_count reported_count reported_failed computed_failed
    local reported_first computed_first

    "$inspector" --expected-checks | LC_ALL=C sort >"$expected_labels_path"
    sed -n 's/^action_17s_b_assertion_\([a-z0-9_]*\)=\(true\|false\)$/\1/p' \
        "$assertion_transcript" | LC_ALL=C sort >"$observed_labels_path"
    expected_count=$(wc -l <"$expected_labels_path")
    observed_count=$(wc -l <"$observed_labels_path")
    reported_count=$(value_for action_17s_b_assertion_count "$assertion_transcript") || return 1
    reported_failed=$(value_for action_17s_b_failed_assertion_count "$assertion_transcript") || return 1
    computed_failed=$(grep -Ec '^action_17s_b_assertion_[a-z0-9_]+=false$' "$assertion_transcript" || true)
    reported_first=$(value_for action_17s_b_first_failure "$assertion_transcript") || return 1
    computed_first=$(sed -n 's/^action_17s_b_assertion_\([a-z0-9_]*\)=false$/\1/p' "$assertion_transcript" | head -n 1)
    [[ -n "$computed_first" ]] || computed_first=none
    [[ "$expected_count" -eq 53 ]]
    [[ "$observed_count" -eq "$expected_count" ]]
    [[ "$(sort -u "$observed_labels_path" | wc -l)" -eq "$observed_count" ]]
    cmp -s "$expected_labels_path" "$observed_labels_path"
    is_nonnegative_integer "$reported_count" && [[ "$reported_count" -eq "$observed_count" ]]
    is_nonnegative_integer "$reported_failed" && [[ "$reported_failed" -eq "$computed_failed" ]]
    [[ "$reported_first" = "$computed_first" ]]
}

validate_transcript() {
    local validation_transcript=$1
    local validation_status=$2
    local failed_count

    transcript_grammar_valid "$validation_transcript"
    secret_free "$validation_transcript"
    validate_assertion_set "$validation_transcript"
    require_one "action_17s_b_value_finalizer_sha256=$expected_finalizer_sha256" "$validation_transcript"
    require_one "action_17s_b_value_validate_block_sha256=$expected_validate_block_sha256" "$validation_transcript"
    require_one action_17s_b_value_stderr_source_classification=stdout_suppressed_stderr_unsuppressed_caddy_validate_path "$validation_transcript"
    require_one action_17s_b_failed_action_stderr_bytes=724 "$validation_transcript"
    require_one action_17s_b_failed_action_stderr_lines=6 "$validation_transcript"
    require_one "action_17s_b_failed_action_stderr_sha256=$expected_failed_stderr_sha256" "$validation_transcript"
    require_one action_17s_b_failed_action_stderr_classification=bounded_safe_unemitted "$validation_transcript"
    require_one action_17s_b_failed_action_stderr_content_recoverable=false "$validation_transcript"
    for invariant in finalizer_invoked marker_mutations filesystem_mutations service_mutations persistent_mutations; do
        require_one "action_17s_b_${invariant}=false" "$validation_transcript"
    done
    failed_count=$(value_for action_17s_b_failed_assertion_count "$validation_transcript")
    if [[ "$validation_status" -eq 0 ]]; then
        [[ "$failed_count" -eq 0 ]]
        require_one action_17s_b_first_failure=none "$validation_transcript"
        require_one action_17s_b_node_b_read_only_inspection_complete=true "$validation_transcript"
    elif [[ "$validation_status" -eq 1 ]]; then
        [[ "$failed_count" -gt 0 ]]
        [[ "$(value_for action_17s_b_first_failure "$validation_transcript")" != none ]]
        [[ "$(grep -Fc 'action_17s_b_node_b_read_only_inspection_complete=true' "$validation_transcript")" -eq 0 ]]
    else
        return 1
    fi
}

make_contract_fixture() {
    local fixture_path=$1
    local fixture_label fixture_count=0
    {
        while IFS= read -r fixture_label; do
            printf 'action_17s_b_assertion_%s=true\n' "$fixture_label"
            fixture_count=$((fixture_count + 1))
        done < <("$inspector" --expected-checks)
        printf 'action_17s_b_assertion_count=%s\n' "$fixture_count"
        printf '%s\n' \
            action_17s_b_failed_assertion_count=0 \
            action_17s_b_first_failure=none \
            "action_17s_b_value_finalizer_sha256=$expected_finalizer_sha256" \
            "action_17s_b_value_validate_block_sha256=$expected_validate_block_sha256" \
            action_17s_b_value_stderr_source_classification=stdout_suppressed_stderr_unsuppressed_caddy_validate_path \
            action_17s_b_failed_action_stderr_bytes=724 \
            action_17s_b_failed_action_stderr_lines=6 \
            "action_17s_b_failed_action_stderr_sha256=$expected_failed_stderr_sha256" \
            action_17s_b_failed_action_stderr_classification=bounded_safe_unemitted \
            action_17s_b_failed_action_stderr_content_recoverable=false \
            action_17s_b_finalizer_invoked=false \
            action_17s_b_marker_mutations=false \
            action_17s_b_filesystem_mutations=false \
            action_17s_b_service_mutations=false \
            action_17s_b_persistent_mutations=false \
            action_17s_b_node_b_read_only_inspection_complete=true
    } >"$fixture_path"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 && "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
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
        work_directory=$(mktemp -d /tmp/caddy-action17s-b-contract.XXXXXX)
        readonly work_directory
        trap 'rm -rf -- "$work_directory"' EXIT
        make_contract_fixture "$work_directory/valid"
        validate_transcript "$work_directory/valid" 0
        sed 's/action_17s_b_assertion_complete_absent=true/action_17s_b_assertion_complete_absent=false/; s/action_17s_b_failed_assertion_count=0/action_17s_b_failed_assertion_count=1/; s/action_17s_b_first_failure=none/action_17s_b_first_failure=complete_absent/; /action_17s_b_node_b_read_only_inspection_complete=true/d' "$work_directory/valid" >"$work_directory/mismatch"
        validate_transcript "$work_directory/mismatch" 1
        if validate_transcript "$work_directory/mismatch" 0; then exit 1; fi
        printf '%s_runner_contract_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' "${0##*/}" >&2
        exit 2
        ;;
esac

verify_inspector
work_directory=$(mktemp -d /tmp/caddy-action17s-b-runner.XXXXXX)
readonly work_directory
retain_work_directory=false
cleanup() {
    # shellcheck disable=SC2317
    if [[ "$retain_work_directory" != true ]]; then
        rm -rf -- "$work_directory"
    fi
}
trap cleanup EXIT
readonly remote_output="$work_directory/node-b.out"
readonly remote_error="$work_directory/node-b.err"

ssh_status=0
ulimit -f 2048
ssh -T -o BatchMode=yes -o ConnectTimeout=5 \
    -o HostKeyAlias="$expected_host_alias" -o StrictHostKeyChecking=yes \
    "$expected_target" 'cd / && sudo -n /bin/bash -s' \
    <"$inspector" >"$remote_output" 2>"$remote_error" || ssh_status=$?
readonly ssh_status
stdout_bytes=$(wc -c <"$remote_output")
stdout_lines=$(line_count "$remote_output")
stdout_sha256=$(file_hash "$remote_output")
stderr_bytes=$(wc -c <"$remote_error")
stderr_lines=$(line_count "$remote_error")
stderr_sha256=$(file_hash "$remote_error")
readonly stdout_bytes stdout_lines stdout_sha256 stderr_bytes stderr_lines stderr_sha256
stdout_classification=$(classify_stream "$remote_output" "$stdout_bytes" "$stdout_lines")
stderr_classification=$(classify_stream "$remote_error" "$stderr_bytes" "$stderr_lines")
readonly stdout_classification stderr_classification

printf '%s_ssh_status=%s\n' "$prefix" "$ssh_status"
printf '%s_remote_stdout_bytes=%s\n' "$prefix" "$stdout_bytes"
printf '%s_remote_stdout_lines=%s\n' "$prefix" "$stdout_lines"
printf '%s_remote_stdout_sha256=%s\n' "$prefix" "$stdout_sha256"
printf '%s_remote_stdout_classification=%s\n' "$prefix" "$stdout_classification"
printf '%s_remote_stderr_bytes=%s\n' "$prefix" "$stderr_bytes"
printf '%s_remote_stderr_lines=%s\n' "$prefix" "$stderr_lines"
printf '%s_remote_stderr_sha256=%s\n' "$prefix" "$stderr_sha256"
printf '%s_remote_stderr_classification=%s\n' "$prefix" "$stderr_classification"
emit_safe_content stdout "$remote_output" "$stdout_classification"
emit_safe_content stderr "$remote_error" "$stderr_classification"

if [[ "$stdout_classification" != captured_within_bounds_safe ||
    "$stderr_classification" != empty || ! "$ssh_status" =~ ^[01]$ ]] ||
    ! validate_transcript "$remote_output" "$ssh_status"; then
    printf '%s_runner_acceptance=false\n' "$prefix" >&2
    if [[ "$retain_work_directory" == true ]]; then
        printf '%s_workstation_evidence_retained=true\n' "$prefix" >&2
        printf '%s_workstation_cleanup_complete=false\n' "$prefix" >&2
    else
        printf '%s_workstation_evidence_retained=false\n' "$prefix" >&2
        printf '%s_workstation_cleanup_complete=true\n' "$prefix" >&2
    fi
    exit 97
fi
if [[ "$ssh_status" -eq 0 ]]; then
    printf '%s_runner_acceptance=true\n' "$prefix"
else
    printf '%s_runner_acceptance=false\n' "$prefix"
fi
printf '%s_workstation_cleanup_complete=true\n' "$prefix"
exit "$ssh_status"
