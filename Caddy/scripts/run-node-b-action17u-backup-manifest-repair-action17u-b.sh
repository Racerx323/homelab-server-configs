#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_17u_b
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co
readonly repair_sha256=c47653c285e7e3db98ed22b163c7f741d781f9d27f6c8feb1293bb70706eb0de
readonly old_manifest_sha256=8b7ee379963bec0932dece5b11dd602efba33fe5d76a6e281c4db0c93b60dfbf
readonly new_manifest_sha256=a992c2ff9bdfde76770ddae910dedfc2a8bbdf6ad25de909ec5cbeacda31d70b
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly repair="$script_directory/repair-node-b-action17u-backup-manifest-action17u-b.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"

work_directory=
retain_work_directory=false

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

line_count() {
    awk 'END { print NR }' "$1"
}

secret_free() {
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$@"
}

stream_classification() {
    local classification_bytes=$1
    local classification_lines=$2
    local classification_path=$3

    if [[ "$classification_bytes" -gt "$maximum_stream_bytes" ||
        "$classification_lines" -gt "$maximum_stream_lines" ]]; then
        printf 'limit_exceeded\n'
    elif ! secret_free "$classification_path"; then
        printf 'unsafe\n'
    elif LC_ALL=C grep -q '[^[:print:][:space:]]' "$classification_path"; then
        printf 'unsafe\n'
    elif [[ "$classification_bytes" -eq 0 ]]; then
        printf 'empty\n'
    else
        printf 'bounded_safe\n'
    fi
}

emit_stream_evidence() {
    local evidence_name=$1
    local evidence_path=$2
    local evidence_bytes
    local evidence_classification
    local evidence_lines
    local evidence_sha256

    evidence_bytes=$(wc -c <"$evidence_path")
    evidence_lines=$(line_count "$evidence_path")
    evidence_sha256=$(file_hash "$evidence_path")
    evidence_classification=$(stream_classification \
        "$evidence_bytes" "$evidence_lines" "$evidence_path")
    printf '%s_remote_%s_bytes=%s\n' "$prefix" "$evidence_name" "$evidence_bytes"
    printf '%s_remote_%s_lines=%s\n' "$prefix" "$evidence_name" "$evidence_lines"
    printf '%s_remote_%s_sha256=%s\n' "$prefix" "$evidence_name" "$evidence_sha256"
    printf '%s_remote_%s_classification=%s\n' \
        "$prefix" "$evidence_name" "$evidence_classification"
    if [[ "$evidence_classification" == bounded_safe ]]; then
        printf '%s_remote_%s_safe_content_begin=true\n' "$prefix" "$evidence_name"
        cat -- "$evidence_path"
        printf '%s_remote_%s_safe_content_end=true\n' "$prefix" "$evidence_name"
        printf '%s_remote_%s_content_secured=emitted\n' "$prefix" "$evidence_name"
    elif [[ "$evidence_classification" == empty ]]; then
        printf '%s_remote_%s_content_secured=empty\n' "$prefix" "$evidence_name"
    else
        retain_work_directory=true
        chmod 0700 "$work_directory"
        chmod 0600 "$evidence_path"
        printf '%s_remote_%s_content_secured=protected_retention\n' "$prefix" "$evidence_name"
        printf '%s_remote_%s_protected_path=%s\n' "$prefix" "$evidence_name" "$evidence_path"
        printf '%s_remote_%s_protected_metadata=%s\n' \
            "$prefix" "$evidence_name" "$(stat -c '%U:%G:%a' "$evidence_path")"
        printf '%s_remote_%s_protected_sha256=%s\n' \
            "$prefix" "$evidence_name" "$evidence_sha256"
    fi
}

require_one() {
    local required_record=$1
    local required_transcript=$2

    [[ "$(grep -Fxc "$required_record" "$required_transcript")" -eq 1 ]]
}

value_for() {
    local value_key=$1
    local value_transcript=$2
    local value_record

    [[ "$(grep -Ec "^${value_key}=" "$value_transcript")" -eq 1 ]] || return 1
    value_record=$(grep -E "^${value_key}=" "$value_transcript")
    printf '%s\n' "${value_record#*=}"
}

verify_source_content() {
    [[ -f "$repair" && ! -L "$repair" ]] || return 1
    [[ "$(file_hash "$repair")" == "$repair_sha256" ]] || return 1
    bash -n "$repair" || return 1
    "$collision_checker" "$repair" >/dev/null || return 1
    "$repair" --self-test >/dev/null || return 1
}

verify_workstation_source() {
    [[ "$(stat -c '%U:%G:%a' "$repair")" == aaron:aaron:755 ]] || return 1
    verify_source_content || return 1
}

transcript_grammar_valid() {
    local grammar_transcript=$1

    awk '
        index($0, "action_17u_b_") != 1 { invalid++ }
        $0 !~ /^[a-z0-9_]+=([A-Za-z0-9_.:,\/-]+)$/ { invalid++ }
        END { exit invalid ? 1 : 0 }
    ' "$grammar_transcript"
}

validate_success_transcript() {
    local validation_transcript=$1
    local expected_label
    local expected_count=0

    transcript_grammar_valid "$validation_transcript" || return 1
    while IFS= read -r expected_label; do
        expected_count=$((expected_count + 1))
        require_one "${prefix}_assertion_${expected_label}=true" \
            "$validation_transcript" || return 1
        [[ "$(grep -Ec "^${prefix}_assertion_${expected_label}=" "$validation_transcript")" -eq 1 ]] || return 1
    done < <("$repair" --expected-checks)
    [[ "$(value_for "${prefix}_value_assertion_count" "$validation_transcript")" -eq "$expected_count" ]] || return 1
    require_one "${prefix}_value_failed_assertion_count=0" "$validation_transcript" || return 1
    require_one "${prefix}_value_first_failure=none" "$validation_transcript" || return 1
    require_one "${prefix}_value_old_manifest_sha256=$old_manifest_sha256" "$validation_transcript" || return 1
    require_one "${prefix}_value_new_manifest_sha256=$new_manifest_sha256" "$validation_transcript" || return 1
    require_one "${prefix}_value_persistent_change=backup_manifest_action_only" "$validation_transcript" || return 1
    require_one "${prefix}_transaction_complete=true" "$validation_transcript" || return 1
    [[ "$(grep -Ec "^${prefix}_rollback_" "$validation_transcript")" -eq 0 ]] || return 1
}

validate_failure_transcript() {
    local validation_transcript=$1

    transcript_grammar_valid "$validation_transcript" || return 1
    [[ "$(grep -Ec "^${prefix}_assertion_[a-z0-9_]+=false$" "$validation_transcript")" -eq 1 ]] || return 1
    [[ "$(grep -Ec "^${prefix}_transaction_complete=true$" "$validation_transcript")" -eq 0 ]] || return 1
}

self_test() {
    verify_source_content
    printf '%s_runner_self_test_passed=true\n' "$prefix"
}

contract_test() {
    local contract_directory
    local contract_transcript
    local expected_label
    local expected_count=0

    contract_directory=$(mktemp -d /tmp/caddy-action17u-b-contract.XXXXXX)
    contract_transcript="$contract_directory/transcript"
    while IFS= read -r expected_label; do
        expected_count=$((expected_count + 1))
        printf '%s_assertion_%s=true\n' "$prefix" "$expected_label" >>"$contract_transcript"
    done < <("$repair" --expected-checks)
    {
        printf '%s_value_assertion_count=%s\n' "$prefix" "$expected_count"
        printf '%s_value_failed_assertion_count=0\n' "$prefix"
        printf '%s_value_first_failure=none\n' "$prefix"
        printf '%s_value_old_manifest_sha256=%s\n' "$prefix" "$old_manifest_sha256"
        printf '%s_value_new_manifest_sha256=%s\n' "$prefix" "$new_manifest_sha256"
        printf '%s_value_backup_directory=/var/backups/caddy-ha/action17u-node-b-stderr-safe-finalizer.N9uEhC\n' "$prefix"
        printf '%s_value_persistent_change=backup_manifest_action_only\n' "$prefix"
        printf '%s_transaction_complete=true\n' "$prefix"
    } >>"$contract_transcript"
    validate_success_transcript "$contract_transcript"
    sed -i "0,/${prefix}_assertion_candidate_hash=true/s//${prefix}_assertion_candidate_hash=false/" "$contract_transcript"
    if validate_success_transcript "$contract_transcript"; then
        return 1
    fi
    if validate_failure_transcript "$contract_transcript"; then
        return 1
    fi
    printf '%s_assertion_candidate_hash=true\n' "$prefix" >>"$contract_transcript"
    if validate_success_transcript "$contract_transcript"; then
        return 1
    fi
    if validate_failure_transcript "$contract_transcript"; then
        return 1
    fi
    rm -rf -- "$contract_directory"
    printf '%s_runner_contract_test_passed=true\n' "$prefix"
}

case "${1:-}" in
    --self-test)
        self_test
        exit 0
        ;;
    --source-test)
        verify_source_content
        printf '%s_runner_source_test_passed=true\n' "$prefix"
        exit 0
        ;;
    --contract-test)
        contract_test
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' "$0" >&2
        exit 64
        ;;
esac

verify_workstation_source
[[ "$PWD" == /home/aaron/code/homelab-server-configs ]]

work_directory=$(mktemp -d /tmp/caddy-action17u-b-runner.XXXXXX)
remote_stdout="$work_directory/remote.stdout"
remote_stderr="$work_directory/remote.stderr"
chmod 0600 "$remote_stdout" "$remote_stderr"

set +e
ssh \
    -T \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o ConnectionAttempts=1 \
    -o StrictHostKeyChecking=yes \
    -o "HostKeyAlias=$expected_host_alias" \
    "$expected_target" \
    'cd / && sudo -n /bin/bash -s --' \
    <"$repair" >"$remote_stdout" 2>"$remote_stderr"
ssh_status=$?
set -e

emit_stream_evidence stdout "$remote_stdout"
emit_stream_evidence stderr "$remote_stderr"

validation_status=0
if [[ "$ssh_status" -eq 0 ]]; then
    validate_success_transcript "$remote_stdout" || validation_status=97
elif [[ "$ssh_status" -eq 125 ]]; then
    validation_status=97
elif ! validate_failure_transcript "$remote_stderr"; then
    validation_status=97
else
    validation_status=$ssh_status
fi

printf '%s_value_ssh_status=%s\n' "$prefix" "$ssh_status"
printf '%s_value_runner_status=%s\n' "$prefix" "$validation_status"
printf '%s_value_repair_sha256=%s\n' "$prefix" "$repair_sha256"
printf '%s_value_target=%s\n' "$prefix" "$expected_target"

if [[ "$retain_work_directory" == false ]]; then
    rm -rf -- "$work_directory"
else
    printf '%s_value_protected_evidence_directory=%s\n' "$prefix" "$work_directory"
fi
exit "$validation_status"
