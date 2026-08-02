#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_17u_a
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co
readonly inspector_sha256=38df35f89dc5732320e84ef9ec90ff8b0d5d1cee72d342b025c743c74a0d4210
readonly expected_finalizer_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d
readonly expected_backup_path=/var/backups/caddy-ha/action17u-node-b-stderr-safe-finalizer.N9uEhC
readonly expected_backup_manifest_sha256=a992c2ff9bdfde76770ddae910dedfc2a8bbdf6ad25de909ec5cbeacda31d70b
readonly expected_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly expected_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly inspector="$script_directory/inspect-node-b-stderr-safe-finalizer-postinstall-action17u-a.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
is_sha256() { [[ "$1" =~ ^[0-9a-f]{64}$ ]]; }
is_nonnegative_integer() { [[ "$1" =~ ^[0-9]+$ ]]; }

secret_free() {
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' "$@"
}

verify_inspector_content() {
    [[ -f "$inspector" && ! -L "$inspector" ]]
    [[ "$(file_hash "$inspector")" = "$inspector_sha256" ]]
    bash -n "$inspector"
    "$collision_checker" "$inspector" >/dev/null
    "$inspector" --self-test >/dev/null
}

verify_workstation_inspector() {
    [[ "$(stat -c '%U:%G:%a' "$inspector")" = aaron:aaron:755 ]]
    verify_inspector_content
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

transcript_grammar_valid() {
    awk '
        index($0, "action_17u_a_") != 1 { invalid++ }
        $0 !~ /^[a-z0-9_]+=([A-Za-z0-9_.:,\/-]+)$/ { invalid++ }
        END { exit invalid ? 1 : 0 }
    ' "$1"
}

validate_assertion_set() {
    local transcript=$1
    local expected_labels observed_labels
    local expected_count observed_count unique_count
    local reported_count reported_failed reported_first computed_failed computed_first
    expected_labels=$(mktemp "$work_directory/expected.XXXXXX")
    observed_labels=$(mktemp "$work_directory/observed.XXXXXX")
    "$inspector" --expected-checks | LC_ALL=C sort >"$expected_labels"
    sed -n 's/^action_17u_a_assertion_\([a-z0-9_]*\)=\(true\|false\)$/\1/p' \
        "$transcript" | LC_ALL=C sort >"$observed_labels"
    expected_count=$(wc -l <"$expected_labels")
    observed_count=$(wc -l <"$observed_labels")
    unique_count=$(sort -u "$observed_labels" | wc -l)
    reported_count=$(value_for action_17u_a_assertion_count "$transcript") || return 1
    reported_failed=$(value_for action_17u_a_failed_assertion_count "$transcript") || return 1
    reported_first=$(value_for action_17u_a_first_failure "$transcript") || return 1
    computed_failed=$(grep -Ec '^action_17u_a_assertion_[a-z0-9_]+=false$' "$transcript" || true)
    computed_first=$(sed -n 's/^action_17u_a_assertion_\([a-z0-9_]*\)=false$/\1/p' "$transcript" | head -n 1)
    [[ -n "$computed_first" ]] || computed_first=none
    # conditional-validator-explicit-failures-begin
    [[ "$expected_count" -eq 71 ]] || return 1
    [[ "$observed_count" -eq "$expected_count" ]] || return 1
    [[ "$unique_count" -eq "$expected_count" ]] || return 1
    cmp -s "$expected_labels" "$observed_labels" || return 1
    is_nonnegative_integer "$reported_count" || return 1
    [[ "$reported_count" -eq "$observed_count" ]] || return 1
    is_nonnegative_integer "$reported_failed" || return 1
    [[ "$reported_failed" -eq "$computed_failed" ]] || return 1
    [[ "$reported_first" = "$computed_first" ]] || return 1
    # conditional-validator-explicit-failures-end
}

validate_transcript() {
    local transcript=$1
    local status=$2
    local failed_count before_hash after_hash observed_backup_hash
    # conditional-validator-explicit-failures-begin
    transcript_grammar_valid "$transcript" || return 1
    secret_free "$transcript" || return 1
    validate_assertion_set "$transcript" || return 1
    require_one "action_17u_a_value_finalizer_sha256=$expected_finalizer_sha256" "$transcript" || return 1
    require_one "action_17u_a_value_backup_path=$expected_backup_path" "$transcript" || return 1
    require_one "action_17u_a_value_expected_backup_manifest_sha256=$expected_backup_manifest_sha256" "$transcript" || return 1
    require_one "action_17u_a_value_payload_sha256=$expected_payload_sha256" "$transcript" || return 1
    require_one "action_17u_a_value_manifest_sha256=$expected_manifest_sha256" "$transcript" || return 1
    observed_backup_hash=$(value_for action_17u_a_value_observed_backup_manifest_sha256 "$transcript") || return 1
    is_sha256 "$observed_backup_hash" || return 1
    before_hash=$(value_for action_17u_a_value_before_state_sha256 "$transcript") || return 1
    after_hash=$(value_for action_17u_a_value_after_state_sha256 "$transcript") || return 1
    is_sha256 "$before_hash" || return 1
    is_sha256 "$after_hash" || return 1
    [[ "$before_hash" = "$after_hash" ]] || return 1
    for marker in finalizer_invoked release_mutated marker_mutated service_mutations \
        lsyncd_reconciliation_activation filesystem_mutations persistent_mutations; do
        require_one "action_17u_a_${marker}=false" "$transcript" || return 1
    done
    failed_count=$(value_for action_17u_a_failed_assertion_count "$transcript") || return 1
    # conditional-validator-explicit-failures-end
    if [[ "$status" -eq 0 ]]; then
        [[ "$failed_count" -eq 0 ]] || return 1
        require_one action_17u_a_first_failure=none "$transcript" || return 1
        require_one action_17u_a_node_b_read_only_postinstall_complete=true "$transcript" || return 1
    elif [[ "$status" -eq 1 ]]; then
        [[ "$failed_count" -gt 0 ]] || return 1
        [[ "$(value_for action_17u_a_first_failure "$transcript")" != none ]] || return 1
        if grep -Fq action_17u_a_node_b_read_only_postinstall_complete=true "$transcript"; then
            return 1
        fi
    else
        return 1
    fi
}

make_fixture() {
    local fixture_path=$1
    local fixture_label fixture_count=0
    local fixture_hash=1111111111111111111111111111111111111111111111111111111111111111
    {
        while IFS= read -r fixture_label; do
            printf 'action_17u_a_assertion_%s=true\n' "$fixture_label"
            fixture_count=$((fixture_count + 1))
        done < <("$inspector" --expected-checks)
        printf '%s\n' \
            "action_17u_a_assertion_count=$fixture_count" \
            action_17u_a_failed_assertion_count=0 action_17u_a_first_failure=none \
            "action_17u_a_value_finalizer_sha256=$expected_finalizer_sha256" \
            "action_17u_a_value_backup_path=$expected_backup_path" \
            "action_17u_a_value_expected_backup_manifest_sha256=$expected_backup_manifest_sha256" \
            "action_17u_a_value_observed_backup_manifest_sha256=$expected_backup_manifest_sha256" \
            "action_17u_a_value_payload_sha256=$expected_payload_sha256" \
            "action_17u_a_value_manifest_sha256=$expected_manifest_sha256" \
            "action_17u_a_value_before_state_sha256=$fixture_hash" \
            "action_17u_a_value_after_state_sha256=$fixture_hash" \
            action_17u_a_finalizer_invoked=false action_17u_a_release_mutated=false \
            action_17u_a_marker_mutated=false action_17u_a_service_mutations=false \
            action_17u_a_lsyncd_reconciliation_activation=false \
            action_17u_a_filesystem_mutations=false action_17u_a_persistent_mutations=false \
            action_17u_a_node_b_read_only_postinstall_complete=true
    } >"$fixture_path"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 && "$expected_target" = pi@10.1.0.54 ]]
        is_sha256 "$inspector_sha256"
        printf '%s_runner_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --source-test)
        [[ $# -eq 1 ]]
        verify_workstation_inspector
        printf '%s_runner_source_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]]
        verify_inspector_content
        work_directory=$(mktemp -d /tmp/caddy-action17u-a-contract.XXXXXX)
        readonly work_directory
        trap 'rm -rf -- "$work_directory"' EXIT
        make_fixture "$work_directory/valid"
        validate_transcript "$work_directory/valid" 0
        sed 's/action_17u_a_assertion_backup_manifest_action_exact=true/action_17u_a_assertion_backup_manifest_action_exact=false/; s/action_17u_a_failed_assertion_count=0/action_17u_a_failed_assertion_count=1/; s/action_17u_a_first_failure=none/action_17u_a_first_failure=backup_manifest_action_exact/; /action_17u_a_node_b_read_only_postinstall_complete=true/d' \
            "$work_directory/valid" >"$work_directory/mismatch"
        validate_transcript "$work_directory/mismatch" 1
        if validate_transcript "$work_directory/mismatch" 0; then exit 1; fi
        cp -- "$work_directory/valid" "$work_directory/duplicate"
        printf 'action_17u_a_assertion_identity_root=true\n' >>"$work_directory/duplicate"
        if validate_transcript "$work_directory/duplicate" 0; then exit 1; fi
        printf '%s_runner_contract_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' "${0##*/}" >&2
        exit 2
        ;;
esac

verify_workstation_inspector
work_directory=$(mktemp -d /tmp/caddy-action17u-a-runner.XXXXXX)
readonly work_directory
readonly remote_output="$work_directory/node-b.out"
readonly remote_error="$work_directory/node-b.err"
cleanup_enabled=true
cleanup() {
    # shellcheck disable=SC2317
    [[ "$cleanup_enabled" != true ]] || rm -rf -- "$work_directory"
}
trap cleanup EXIT

ssh_status=0
ulimit -f 2048
ssh -T -o BatchMode=yes -o ClearAllForwardings=yes -o ConnectTimeout=10 \
    -o "HostKeyAlias=$expected_host_alias" -o KbdInteractiveAuthentication=no \
    -o PasswordAuthentication=no -o PreferredAuthentications=publickey \
    -o StrictHostKeyChecking=yes "$expected_target" \
    'cd / && sudo -n /bin/bash -s --' \
    <"$inspector" >"$remote_output" 2>"$remote_error" || ssh_status=$?
readonly ssh_status

stdout_bytes=$(wc -c <"$remote_output")
stdout_lines=$(line_count "$remote_output")
stdout_sha256=$(file_hash "$remote_output")
stderr_bytes=$(wc -c <"$remote_error")
stderr_lines=$(line_count "$remote_error")
stderr_sha256=$(file_hash "$remote_error")
readonly stdout_bytes stdout_lines stdout_sha256 stderr_bytes stderr_lines stderr_sha256
stdout_classification=bounded_safe
stderr_classification=bounded_safe
if [[ "$stdout_bytes" -gt "$maximum_stream_bytes" || "$stdout_lines" -gt "$maximum_stream_lines" ]]; then
    stdout_classification=limit_exceeded
elif ! secret_free "$remote_output"; then
    stdout_classification=unsafe
fi
if [[ "$stderr_bytes" -eq 0 ]]; then
    stderr_classification=empty
elif [[ "$stderr_bytes" -gt "$maximum_stream_bytes" || "$stderr_lines" -gt "$maximum_stream_lines" ]]; then
    stderr_classification=limit_exceeded
elif ! secret_free "$remote_error"; then
    stderr_classification=unsafe
fi
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

if [[ "$stdout_classification" != bounded_safe || "$stderr_classification" != empty || ! "$ssh_status" =~ ^[01]$ ]] ||
    ! validate_transcript "$remote_output" "$ssh_status"; then
    cleanup_enabled=false
    printf '%s_evidence_retained=%s\n' "$prefix" "$work_directory" >&2
    printf '%s_runner_acceptance=false\n' "$prefix" >&2
    exit 97
fi

printf '%s_remote_stdout_safe_content_begin=true\n' "$prefix"
sed -n '/^action_17u_a_/p' "$remote_output"
printf '%s_remote_stdout_safe_content_end=true\n' "$prefix"
printf '%s_remote_stdout_content_secured=emitted\n' "$prefix"
printf '%s_remote_stderr_content_secured=empty\n' "$prefix"
if [[ "$ssh_status" -eq 0 ]]; then
    printf '%s_runner_acceptance=true\n' "$prefix"
else
    printf '%s_runner_acceptance=semantic_mismatch\n' "$prefix"
fi
printf '%s_workstation_cleanup_complete=true\n' "$prefix"
exit "$ssh_status"
