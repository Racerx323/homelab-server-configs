#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_17s_retry
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co
readonly expected_revision=action17p-node-a-to-node-b-bootstrap
readonly expected_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly expected_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly empty_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
readonly maximum_inner_stream_bytes=4096
readonly maximum_inner_stream_lines=20
readonly maximum_remote_stream_bytes=1048576
readonly maximum_remote_stream_lines=4096
readonly transaction_sha256=269c48158969f3767b13ffa92aaef1559bcb0c25c64bb19fdb93e70f56713bd0

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly transaction="$script_directory/migrate-node-b-retained-release-marker-action17s-retry.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

line_count() {
    awk 'END { print NR }' "$1"
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

is_nonnegative_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

is_sha256() {
    [[ "$1" =~ ^[0-9a-f]{64}$ ]]
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

    if [[ "$classification_bytes" -gt "$maximum_remote_stream_bytes" ||
        "$classification_lines" -gt "$maximum_remote_stream_lines" ]]; then
        printf 'limit_exceeded\n'
    elif ! secret_free "$classification_path"; then
        printf 'unsafe\n'
    elif LC_ALL=C grep -q '[^[:print:][:space:]]' "$classification_path"; then
        printf 'unsafe\n'
    elif [[ "$classification_bytes" -eq 0 ]]; then
        printf 'empty\n'
    else
        printf 'bounded_safe_unemitted\n'
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
    evidence_classification=$(
        stream_classification \
            "$evidence_bytes" "$evidence_lines" "$evidence_path"
    )
    printf '%s_remote_%s_bytes=%s\n' "$prefix" "$evidence_name" "$evidence_bytes"
    printf '%s_remote_%s_lines=%s\n' "$prefix" "$evidence_name" "$evidence_lines"
    printf '%s_remote_%s_sha256=%s\n' \
        "$prefix" "$evidence_name" "$evidence_sha256"
    printf '%s_remote_%s_classification=%s\n' \
        "$prefix" "$evidence_name" "$evidence_classification"
    printf '%s_remote_%s_raw_emitted=false\n' "$prefix" "$evidence_name"
}

validate_inner_stream_evidence() {
    local evidence_name=$1
    local evidence_transcript=$2
    local evidence_bytes
    local evidence_classification
    local evidence_lines
    local evidence_sha256

    evidence_bytes=$(value_for \
        "action_17s_retry_value_${evidence_name}_bytes" \
        "$evidence_transcript") || return 1
    evidence_lines=$(value_for \
        "action_17s_retry_value_${evidence_name}_lines" \
        "$evidence_transcript") || return 1
    evidence_sha256=$(value_for \
        "action_17s_retry_value_${evidence_name}_sha256" \
        "$evidence_transcript") || return 1
    evidence_classification=$(value_for \
        "action_17s_retry_value_${evidence_name}_classification" \
        "$evidence_transcript") || return 1
    is_nonnegative_integer "$evidence_bytes" || return 1
    is_nonnegative_integer "$evidence_lines" || return 1
    is_sha256 "$evidence_sha256" || return 1
    [[ "$evidence_bytes" -le "$maximum_inner_stream_bytes" ]] || return 1
    [[ "$evidence_lines" -le "$maximum_inner_stream_lines" ]] || return 1
    case "$evidence_classification" in
        empty)
            [[ "$evidence_bytes" -eq 0 ]] || return 1
            [[ "$evidence_lines" -eq 0 ]] || return 1
            [[ "$evidence_sha256" = "$empty_sha256" ]] || return 1
            ;;
        bounded_safe_unemitted)
            [[ "$evidence_bytes" -gt 0 ]] || return 1
            ;;
        *) return 1 ;;
    esac
    require_one "action_17s_retry_${evidence_name}_raw_emitted=false" \
        "$evidence_transcript"
}

transcript_grammar_valid() {
    local grammar_transcript=$1

    awk '
        index($0, "action_17s_retry_") != 1 { invalid++ }
        $0 !~ /^[a-z0-9_]+=([A-Za-z0-9_.:,\/-]+)$/ { invalid++ }
        END { exit invalid ? 1 : 0 }
    ' "$grammar_transcript"
}

verify_transaction() {
    [[ -f "$transaction" && ! -L "$transaction" ]]
    [[ "$(stat -c '%U:%G:%a' "$transaction")" = aaron:aaron:755 ]]
    [[ "$(file_hash "$transaction")" = "$transaction_sha256" ]]
    bash -n "$transaction"
    "$collision_checker" "$transaction" >/dev/null
    "$transaction" --self-test >/dev/null
}

validate_assertion_contract() {
    local assertion_transcript=$1
    local expected_labels
    local observed_labels
    local expected_count
    local observed_count
    local reported_count
    local reported_failed
    local computed_failed
    local reported_first
    local computed_first

    expected_labels=$(mktemp "$work_directory/expected.XXXXXX")
    observed_labels=$(mktemp "$work_directory/observed.XXXXXX")
    "$transaction" --expected-checks | LC_ALL=C sort >"$expected_labels"
    sed -n \
        's/^action_17s_retry_assertion_\([a-z0-9_]*\)=\(true\|false\)$/\1/p' \
        "$assertion_transcript" | LC_ALL=C sort >"$observed_labels"
    expected_count=$(wc -l <"$expected_labels")
    observed_count=$(wc -l <"$observed_labels")
    reported_count=$(value_for action_17s_retry_assertion_count \
        "$assertion_transcript") || reported_count=invalid
    reported_failed=$(value_for action_17s_retry_failed_assertion_count \
        "$assertion_transcript") || reported_failed=invalid
    computed_failed=$(grep -Ec '^action_17s_retry_assertion_[a-z0-9_]+=false$' \
        "$assertion_transcript" || true)
    reported_first=$(value_for action_17s_retry_first_failure \
        "$assertion_transcript") || reported_first=invalid
    computed_first=$(sed -n \
        's/^action_17s_retry_assertion_\([a-z0-9_]*\)=false$/\1/p' \
        "$assertion_transcript" | head -n 1)
    if [[ -z "$computed_first" ]]; then
        computed_first=none
    fi

    [[ "$expected_count" -gt 100 ]] || return 1
    [[ "$observed_count" -eq "$expected_count" ]] || return 1
    [[ "$(sort -u "$observed_labels" | wc -l)" -eq "$observed_count" ]] ||
        return 1
    cmp -s "$expected_labels" "$observed_labels" || return 1
    is_nonnegative_integer "$reported_count" || return 1
    [[ "$reported_count" -eq "$observed_count" ]] || return 1
    is_nonnegative_integer "$reported_failed" || return 1
    [[ "$reported_failed" -eq "$computed_failed" ]] || return 1
    [[ "$reported_first" = "$computed_first" ]] || return 1
    [[ "$computed_failed" -eq 0 ]] || return 1
}

validate_success() {
    local success_error=$1
    local success_output=$2
    local success_status=$3
    local backup_path
    local before_snapshot_hash

    [[ "$success_status" -eq 0 ]] || return 1
    [[ ! -s "$success_error" ]] || return 1
    secret_free "$success_output" "$success_error" || return 1
    transcript_grammar_valid "$success_output" || return 1
    validate_assertion_contract "$success_output" || return 1
    require_one action_17s_retry_preflight_complete=true "$success_output" || return 1
    require_one action_17s_retry_mutation_started=true "$success_output" || return 1
    require_one action_17s_retry_finalizer_invocation_started=true \
        "$success_output" || return 1
    for success_stream in finalizer_stdout finalizer_stderr; do
        validate_inner_stream_evidence "$success_stream" "$success_output" ||
            return 1
        require_one "action_17s_retry_value_${success_stream}_bytes=0" \
            "$success_output" || return 1
        require_one "action_17s_retry_value_${success_stream}_lines=0" \
            "$success_output" || return 1
        require_one \
            "action_17s_retry_value_${success_stream}_sha256=$empty_sha256" \
            "$success_output" || return 1
        require_one \
            "action_17s_retry_value_${success_stream}_classification=empty" \
            "$success_output" || return 1
    done
    require_one action_17s_retry_value_finalizer_status=0 \
        "$success_output" || return 1
    require_one \
        "action_17s_retry_value_revision=$expected_revision" "$success_output" || return 1
    require_one \
        "action_17s_retry_value_payload_sha256=$expected_payload_sha256" \
        "$success_output" || return 1
    require_one \
        "action_17s_retry_value_manifest_sha256=$expected_manifest_sha256" \
        "$success_output" || return 1
    before_snapshot_hash=$(value_for \
        action_17s_retry_value_before_snapshot_sha256 "$success_output") ||
        before_snapshot_hash=invalid
    is_sha256 "$before_snapshot_hash" || return 1
    backup_path=$(value_for action_17s_retry_value_backup_path "$success_output") ||
        backup_path=invalid
    [[ "$backup_path" =~ ^/var/backups/caddy-ha/action17s-retry-node-b-marker-migration\.[A-Za-z0-9]+$ ]] ||
        return 1
    require_one action_17s_retry_finalizer_invoked=true "$success_output" || return 1
    require_one action_17s_retry_marker_migration=true "$success_output" || return 1
    require_one action_17s_retry_payload_content_mutation=false "$success_output" ||
        return 1
    require_one action_17s_retry_lsyncd_reconciliation_activation=false \
        "$success_output" || return 1
    require_one action_17s_retry_caddy_selection_changed=false "$success_output" ||
        return 1
    require_one action_17s_retry_service_mutations=false "$success_output" || return 1
    require_one \
        action_17s_retry_persistent_mutation_scope=finalize_request,complete,rollback_metadata \
        "$success_output" || return 1
    require_one action_17s_retry_node_b_marker_migration_complete=true \
        "$success_output" || return 1
    if grep -Eq \
        '^action_17s_retry_rollback_|manual_intervention_required=true' \
        "$success_output" "$success_error"; then
        return 1
    fi
}

validate_rollback_assertion_contract() {
    local rollback_transcript=$1
    local expected_rollback_labels
    local observed_rollback_labels
    local expected_rollback_count
    local observed_rollback_count

    expected_rollback_labels=$(mktemp "$work_directory/rollback-expected.XXXXXX")
    observed_rollback_labels=$(mktemp "$work_directory/rollback-observed.XXXXXX")
    "$transaction" --expected-rollback-checks | LC_ALL=C sort \
        >"$expected_rollback_labels"
    sed -n \
        's/^action_17s_retry_rollback_assertion_\([a-z0-9_]*\)=\(true\|false\)$/\1/p' \
        "$rollback_transcript" | LC_ALL=C sort >"$observed_rollback_labels"
    expected_rollback_count=$(wc -l <"$expected_rollback_labels")
    observed_rollback_count=$(wc -l <"$observed_rollback_labels")
    [[ "$expected_rollback_count" -gt 40 ]] || return 1
    [[ "$observed_rollback_count" -eq "$expected_rollback_count" ]] || return 1
    [[ "$(sort -u "$observed_rollback_labels" | wc -l)" -eq "$observed_rollback_count" ]] || return 1
    cmp -s "$expected_rollback_labels" "$observed_rollback_labels" || return 1
    if grep -Eq '^action_17s_retry_rollback_assertion_[a-z0-9_]+=false$' \
        "$rollback_transcript"; then
        return 1
    fi
}

validate_failure() {
    local failure_error=$1
    local failure_output=$2
    local failure_status=$3

    [[ "$failure_status" -ne 0 ]] || return 97
    secret_free "$failure_output" "$failure_error" || return 97
    if grep -Fq manual_intervention_required=true \
        "$failure_output" "$failure_error" ||
        grep -Fq action_17s_retry_rollback_complete=false \
            "$failure_output" "$failure_error"; then
        return 97
    fi
    if grep -Fxq action_17s_retry_mutation_started=true "$failure_output"; then
        if grep -Fxq action_17s_retry_finalizer_invocation_started=true \
            "$failure_output"; then
            validate_inner_stream_evidence finalizer_stdout "$failure_output" ||
                return 97
            validate_inner_stream_evidence finalizer_stderr "$failure_output" ||
                return 97
        fi
        require_one action_17s_retry_rollback_started=true "$failure_error" || return 97
        validate_rollback_assertion_contract "$failure_error" || return 97
        require_one action_17s_retry_rollback_complete=true "$failure_error" || return 97
    elif grep -Eq '^action_17s_retry_rollback_' "$failure_output" "$failure_error"; then
        return 97
    fi
}

write_success_fixture() {
    local fixture_destination=$1
    local fixture_label
    local fixture_count

    fixture_count=$("$transaction" --expected-checks | wc -l)
    {
        while IFS= read -r fixture_label; do
            printf 'action_17s_retry_assertion_%s=true\n' "$fixture_label"
        done < <("$transaction" --expected-checks)
        printf '%s\n' \
            "action_17s_retry_assertion_count=$fixture_count" \
            action_17s_retry_failed_assertion_count=0 \
            action_17s_retry_first_failure=none \
            action_17s_retry_preflight_complete=true \
            action_17s_retry_mutation_started=true \
            action_17s_retry_finalizer_invocation_started=true \
            action_17s_retry_value_finalizer_stdout_bytes=0 \
            action_17s_retry_value_finalizer_stdout_lines=0 \
            "action_17s_retry_value_finalizer_stdout_sha256=$empty_sha256" \
            action_17s_retry_value_finalizer_stdout_classification=empty \
            action_17s_retry_finalizer_stdout_raw_emitted=false \
            action_17s_retry_value_finalizer_stderr_bytes=0 \
            action_17s_retry_value_finalizer_stderr_lines=0 \
            "action_17s_retry_value_finalizer_stderr_sha256=$empty_sha256" \
            action_17s_retry_value_finalizer_stderr_classification=empty \
            action_17s_retry_finalizer_stderr_raw_emitted=false \
            action_17s_retry_value_finalizer_status=0 \
            "action_17s_retry_value_revision=$expected_revision" \
            "action_17s_retry_value_payload_sha256=$expected_payload_sha256" \
            "action_17s_retry_value_manifest_sha256=$expected_manifest_sha256" \
            action_17s_retry_value_before_snapshot_sha256=1111111111111111111111111111111111111111111111111111111111111111 \
            action_17s_retry_value_backup_path=/var/backups/caddy-ha/action17s-retry-node-b-marker-migration.ABC123 \
            action_17s_retry_finalizer_invoked=true \
            action_17s_retry_marker_migration=true \
            action_17s_retry_payload_content_mutation=false \
            action_17s_retry_lsyncd_reconciliation_activation=false \
            action_17s_retry_caddy_selection_changed=false \
            action_17s_retry_service_mutations=false \
            action_17s_retry_persistent_mutation_scope=finalize_request,complete,rollback_metadata \
            action_17s_retry_node_b_marker_migration_complete=true
    } >"$fixture_destination"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$expected_target" = pi@10.1.0.54 ]]
        [[ "$expected_host_alias" = pihole00.local.theama.co ]]
        [[ "$transaction_sha256" =~ ^[0-9a-f]{64}$ ]]
        printf '%s_runner_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --source-test)
        [[ $# -eq 1 ]]
        verify_transaction
        printf '%s_runner_source_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]]
        verify_transaction
        work_directory=$(mktemp -d /tmp/caddy-action17s-retry-contract.XXXXXX)
        readonly work_directory
        trap 'rm -rf -- "$work_directory"' EXIT
        : >"$work_directory/empty.err"
        write_success_fixture "$work_directory/valid.out"
        validate_success "$work_directory/empty.err" "$work_directory/valid.out" 0

        cp -- "$work_directory/valid.out" "$work_directory/false.out"
        sed -i '0,/=true/s//=false/' "$work_directory/false.out"
        if validate_success \
            "$work_directory/empty.err" "$work_directory/false.out" 0; then
            printf 'False assertion was accepted.\n' >&2
            exit 1
        fi

        cp -- "$work_directory/valid.out" "$work_directory/duplicate.out"
        printf 'action_17s_retry_assertion_identity_root=true\n' \
            >>"$work_directory/duplicate.out"
        if validate_success \
            "$work_directory/empty.err" "$work_directory/duplicate.out" 0; then
            printf 'Duplicate assertion was accepted.\n' >&2
            exit 1
        fi

        printf '%s\n' \
            action_17s_retry_preflight_complete=true \
            action_17s_retry_mutation_started=true >"$work_directory/rollback.out"
        {
            printf 'action_17s_retry_rollback_started=true\n'
            while IFS= read -r rollback_fixture_label; do
                printf 'action_17s_retry_rollback_assertion_%s=true\n' \
                    "$rollback_fixture_label"
            done < <("$transaction" --expected-rollback-checks)
            printf 'action_17s_retry_rollback_complete=true\n'
        } >"$work_directory/rollback.err"
        validate_failure \
            "$work_directory/rollback.err" "$work_directory/rollback.out" 1
        sed -i '/rollback_complete/d' "$work_directory/rollback.err"
        set +e
        validate_failure \
            "$work_directory/rollback.err" "$work_directory/rollback.out" 1
        rollback_contract_status=$?
        set -e
        [[ "$rollback_contract_status" -eq 97 ]]
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

verify_transaction
work_directory=$(mktemp -d /tmp/caddy-action17s-retry-runner.XXXXXX)
readonly work_directory
readonly remote_output="$work_directory/remote.out"
readonly remote_error="$work_directory/remote.err"

cleanup() {
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

finish() {
    local finish_status=$1

    cleanup
    trap - EXIT
    if [[ -e "$work_directory" || -L "$work_directory" ]]; then
        printf '%s_workstation_cleanup_complete=false\n' "$prefix" >&2
        exit 97
    fi
    printf '%s_workstation_cleanup_complete=true\n' "$prefix"
    exit "$finish_status"
}

ssh_status=0
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
    <"$transaction" >"$remote_output" 2>"$remote_error" || ssh_status=$?

emit_stream_evidence stdout "$remote_output"
emit_stream_evidence stderr "$remote_error"
stdout_classification=$(stream_classification \
    "$(wc -c <"$remote_output")" "$(line_count "$remote_output")" "$remote_output")
stderr_classification=$(stream_classification \
    "$(wc -c <"$remote_error")" "$(line_count "$remote_error")" "$remote_error")
readonly stdout_classification stderr_classification
printf '%s_ssh_status=%s\n' "$prefix" "$ssh_status"

if [[ "$stdout_classification" != bounded_safe_unemitted ||
    "$stderr_classification" != empty &&
    "$stderr_classification" != bounded_safe_unemitted ]]; then
    printf 'Action 17s retry remote output classification is unsafe or unbounded.\n' >&2
    finish 97
fi
transcript_grammar_valid "$remote_output" || {
    printf 'Action 17s retry stdout transcript grammar failed.\n' >&2
    finish 97
}
if [[ -s "$remote_error" ]]; then
    transcript_grammar_valid "$remote_error" || {
        printf 'Action 17s retry stderr transcript grammar failed.\n' >&2
        finish 97
    }
fi
cat "$remote_output"
cat "$remote_error" >&2
if [[ "$ssh_status" -eq 0 ]]; then
    if ! validate_success "$remote_error" "$remote_output" "$ssh_status"; then
        printf 'Action 17s retry success transcript contract failed.\n' >&2
        finish 97
    fi
    printf '%s_runner_acceptance=true\n' "$prefix"
    finish 0
fi

set +e
validate_failure "$remote_error" "$remote_output" "$ssh_status"
failure_validation_status=$?
set -e
if [[ "$failure_validation_status" -eq 97 ]]; then
    printf 'Action 17s retry rollback evidence is incomplete.\n' >&2
    finish 97
fi
printf '%s_runner_acceptance=false\n' "$prefix"
finish "$ssh_status"
