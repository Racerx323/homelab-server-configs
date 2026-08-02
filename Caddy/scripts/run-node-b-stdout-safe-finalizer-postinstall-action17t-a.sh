#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_17t_a
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co
readonly inspector_sha256=50cef92bc6b55b90275a819ee92d511df12132f2ad417c12d359d46f0f56919f
readonly expected_finalizer_sha256=e5ec5aab0f57b9ea68c41f122de282c1d156a6747f9f74dd1f22200079c097e4
readonly expected_backup_path=/var/backups/caddy-ha/action17t-node-b-stdout-safe-finalizer.Z6U7Yc
readonly expected_backup_manifest_sha256=1c77b0bbab0b9b6cc0cd134c6748553fd686e12e665cb7131552578a1182f15d
readonly expected_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly expected_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly inspector="$script_directory/inspect-node-b-stdout-safe-finalizer-postinstall-action17t-a.sh"
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
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$@"
}

transcript_grammar_valid() {
    local grammar_transcript=$1

    awk '
        index($0, "action_17t_a_") != 1 { invalid++ }
        $0 !~ /^[a-z0-9_]+=([A-Za-z0-9_.:,\/-]+)$/ { invalid++ }
        END { exit invalid ? 1 : 0 }
    ' "$grammar_transcript"
}

verify_inspector() {
    local inspector_metadata

    [[ -f "$inspector" && ! -L "$inspector" ]]
    inspector_metadata=$(stat -c '%U:%G:%a' "$inspector")
    if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
        [[ "$inspector_metadata" = root:root:755 ]]
    else
        [[ "$inspector_metadata" = aaron:aaron:755 ]]
    fi
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
        's/^action_17t_a_assertion_\([a-z0-9_]*\)=\(true\|false\)$/\1/p' \
        "$assertion_transcript" | LC_ALL=C sort >"$observed_labels_path"
    expected_count=$(wc -l <"$expected_labels_path")
    observed_count=$(wc -l <"$observed_labels_path")
    reported_count=$(value_for action_17t_a_assertion_count \
        "$assertion_transcript") || reported_count=invalid
    reported_failed=$(value_for action_17t_a_failed_assertion_count \
        "$assertion_transcript") || reported_failed=invalid
    computed_failed=$(grep -Ec '^action_17t_a_assertion_[a-z0-9_]+=false$' \
        "$assertion_transcript" || true)
    reported_first=$(value_for action_17t_a_first_failure \
        "$assertion_transcript") || reported_first=invalid
    computed_first=$(sed -n \
        's/^action_17t_a_assertion_\([a-z0-9_]*\)=false$/\1/p' \
        "$assertion_transcript" | head -n 1)
    [[ -n "$computed_first" ]] || computed_first=none

    [[ "$expected_count" -eq 62 ]] || return 1
    [[ "$observed_count" -eq "$expected_count" ]] || return 1
    [[ "$(sort -u "$observed_labels_path" | wc -l)" -eq "$observed_count" ]] ||
        return 1
    cmp -s "$expected_labels_path" "$observed_labels_path" || return 1
    is_nonnegative_integer "$reported_count" || return 1
    [[ "$reported_count" -eq "$observed_count" ]] || return 1
    is_nonnegative_integer "$reported_failed" || return 1
    [[ "$reported_failed" -eq "$computed_failed" ]] || return 1
    [[ "$reported_first" = "$computed_first" ]] || return 1
}

validate_transcript() {
    local validation_transcript=$1
    local validation_status=$2
    local failed_count
    local before_hash
    local after_hash

    transcript_grammar_valid "$validation_transcript" || return 1
    secret_free "$validation_transcript" || return 1
    validate_assertion_set "$validation_transcript" || return 1
    require_one \
        "action_17t_a_value_finalizer_sha256=$expected_finalizer_sha256" \
        "$validation_transcript" || return 1
    require_one "action_17t_a_value_backup_path=$expected_backup_path" \
        "$validation_transcript" || return 1
    require_one \
        "action_17t_a_value_backup_manifest_sha256=$expected_backup_manifest_sha256" \
        "$validation_transcript" || return 1
    require_one "action_17t_a_value_payload_sha256=$expected_payload_sha256" \
        "$validation_transcript" || return 1
    require_one "action_17t_a_value_manifest_sha256=$expected_manifest_sha256" \
        "$validation_transcript" || return 1
    before_hash=$(value_for action_17t_a_value_before_state_sha256 \
        "$validation_transcript") || before_hash=invalid
    after_hash=$(value_for action_17t_a_value_after_state_sha256 \
        "$validation_transcript") || after_hash=invalid
    is_sha256 "$before_hash" || return 1
    is_sha256 "$after_hash" || return 1
    [[ "$before_hash" = "$after_hash" ]] || return 1
    for validation_marker in \
        finalizer_invoked \
        release_mutated \
        marker_mutated \
        service_mutations \
        lsyncd_reconciliation_activation \
        filesystem_mutations \
        persistent_mutations; do
        require_one "action_17t_a_${validation_marker}=false" \
            "$validation_transcript" || return 1
    done

    failed_count=$(value_for action_17t_a_failed_assertion_count \
        "$validation_transcript") || return 1
    if [[ "$validation_status" -eq 0 ]]; then
        [[ "$failed_count" -eq 0 ]] || return 1
        require_one action_17t_a_first_failure=none "$validation_transcript" ||
            return 1
        require_one action_17t_a_node_b_read_only_postinstall_complete=true \
            "$validation_transcript" || return 1
    elif [[ "$validation_status" -eq 1 ]]; then
        [[ "$failed_count" -gt 0 ]] || return 1
        [[ "$(value_for action_17t_a_first_failure "$validation_transcript")" != none ]] ||
            return 1
        [[ "$(grep -Fc 'action_17t_a_node_b_read_only_postinstall_complete=true' \
            "$validation_transcript")" -eq 0 ]] || return 1
    else
        return 1
    fi
}

make_contract_fixture() {
    local fixture_path=$1
    local fixture_label
    local fixture_count=0
    local fixture_state_sha256=1111111111111111111111111111111111111111111111111111111111111111

    {
        while IFS= read -r fixture_label; do
            printf 'action_17t_a_assertion_%s=true\n' "$fixture_label"
            fixture_count=$((fixture_count + 1))
        done < <("$inspector" --expected-checks)
        printf '%s\n' \
            "action_17t_a_assertion_count=$fixture_count" \
            action_17t_a_failed_assertion_count=0 \
            action_17t_a_first_failure=none \
            "action_17t_a_value_finalizer_sha256=$expected_finalizer_sha256" \
            "action_17t_a_value_backup_path=$expected_backup_path" \
            "action_17t_a_value_backup_manifest_sha256=$expected_backup_manifest_sha256" \
            "action_17t_a_value_payload_sha256=$expected_payload_sha256" \
            "action_17t_a_value_manifest_sha256=$expected_manifest_sha256" \
            "action_17t_a_value_before_state_sha256=$fixture_state_sha256" \
            "action_17t_a_value_after_state_sha256=$fixture_state_sha256" \
            action_17t_a_finalizer_invoked=false \
            action_17t_a_release_mutated=false \
            action_17t_a_marker_mutated=false \
            action_17t_a_service_mutations=false \
            action_17t_a_lsyncd_reconciliation_activation=false \
            action_17t_a_filesystem_mutations=false \
            action_17t_a_persistent_mutations=false \
            action_17t_a_node_b_read_only_postinstall_complete=true
    } >"$fixture_path"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$expected_target" = pi@10.1.0.54 ]]
        [[ "$expected_host_alias" = pihole00.local.theama.co ]]
        is_sha256 "$inspector_sha256"
        is_sha256 "$expected_finalizer_sha256"
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
        verify_inspector
        work_directory=$(mktemp -d /tmp/caddy-action17t-a-contract.XXXXXX)
        readonly work_directory
        trap 'rm -rf -- "$work_directory"' EXIT
        make_contract_fixture "$work_directory/valid"
        validate_transcript "$work_directory/valid" 0
        sed \
            's/action_17t_a_assertion_complete_absent=true/action_17t_a_assertion_complete_absent=false/; s/action_17t_a_failed_assertion_count=0/action_17t_a_failed_assertion_count=1/; s/action_17t_a_first_failure=none/action_17t_a_first_failure=complete_absent/; /action_17t_a_node_b_read_only_postinstall_complete=true/d' \
            "$work_directory/valid" >"$work_directory/mismatch"
        validate_transcript "$work_directory/mismatch" 1
        if validate_transcript "$work_directory/mismatch" 0; then
            printf 'Semantic mismatch was accepted as success.\n' >&2
            exit 1
        fi
        cp -- "$work_directory/valid" "$work_directory/duplicate"
        printf 'action_17t_a_assertion_identity_root=true\n' \
            >>"$work_directory/duplicate"
        if validate_transcript "$work_directory/duplicate" 0; then
            printf 'Duplicate assertion was accepted.\n' >&2
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
work_directory=$(mktemp -d /tmp/caddy-action17t-a-runner.XXXXXX)
readonly work_directory
readonly remote_output="$work_directory/node-b.out"
readonly remote_error="$work_directory/node-b.err"
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

ssh_status=0
ulimit -f 2048
ssh -T \
    -o BatchMode=yes \
    -o ClearAllForwardings=yes \
    -o ConnectTimeout=10 \
    -o "HostKeyAlias=$expected_host_alias" \
    -o KbdInteractiveAuthentication=no \
    -o PasswordAuthentication=no \
    -o PreferredAuthentications=publickey \
    -o StrictHostKeyChecking=yes \
    "$expected_target" \
    'cd / && sudo -n /bin/bash -s --' \
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
elif ! secret_free "$remote_output"; then
    stdout_classification=unsafe
fi
if [[ "$stderr_bytes" -eq 0 ]]; then
    stderr_classification=empty
elif [[ "$stderr_bytes" -gt "$maximum_stream_bytes" ||
    "$stderr_lines" -gt "$maximum_stream_lines" ]]; then
    stderr_classification=limit_exceeded
elif ! secret_free "$remote_error"; then
    stderr_classification=unsafe
fi
readonly stdout_classification stderr_classification

printf '%s_ssh_status=%s\n' "$prefix" "$ssh_status"
printf '%s_remote_stdout_bytes=%s\n' "$prefix" "$stdout_bytes"
printf '%s_remote_stdout_lines=%s\n' "$prefix" "$stdout_lines"
printf '%s_remote_stdout_sha256=%s\n' "$prefix" "$stdout_sha256"
printf '%s_remote_stdout_classification=%s\n' \
    "$prefix" "$stdout_classification"
printf '%s_remote_stdout_raw_emitted=false\n' "$prefix"
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

sed -n '/^action_17t_a_/p' "$remote_output"
if [[ "$ssh_status" -eq 0 ]]; then
    printf '%s_runner_acceptance=true\n' "$prefix"
else
    printf '%s_runner_acceptance=false\n' "$prefix"
fi
printf '%s_workstation_cleanup_complete=true\n' "$prefix"
exit "$ssh_status"
