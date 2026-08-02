#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_17u
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co
readonly installer_sha256=b8dcdd8e77f1349a6e2cc9ba270a4582b318fb641077509b5664f70942258c46
readonly old_finalizer_sha256=e5ec5aab0f57b9ea68c41f122de282c1d156a6747f9f74dd1f22200079c097e4
readonly new_finalizer_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d
readonly expected_revision=action17p-node-a-to-node-b-bootstrap
readonly empty_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly installer="$script_directory/install-node-b-stderr-safe-finalizer-action17u.sh"
readonly candidate="$script_directory/finalize-incoming-release-v2-stderr-safe-action17u.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

line_count() {
    awk 'END { print NR }' "$1"
}

is_sha256() {
    [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

is_nonnegative_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
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
    printf '%s_remote_%s_sha256=%s\n' "$prefix" "$evidence_name" "$evidence_sha256"
    printf '%s_remote_%s_classification=%s\n' \
        "$prefix" "$evidence_name" "$evidence_classification"
    printf '%s_remote_%s_raw_emitted=false\n' "$prefix" "$evidence_name"
}

secure_stream_content() {
    local content_name=$1
    local content_path=$2
    local content_classification=$3

    if [[ "$content_classification" == bounded_safe_unemitted ]]; then
        printf '%s_remote_%s_safe_content_begin=true\n' "$prefix" "$content_name"
        cat -- "$content_path"
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

transcript_grammar_valid() {
    local grammar_transcript=$1

    awk '
        index($0, "action_17u_") != 1 { invalid++ }
        $0 !~ /^[a-z0-9_]+=([A-Za-z0-9_.:,\/-]+)$/ { invalid++ }
        END { exit invalid ? 1 : 0 }
    ' "$grammar_transcript"
}

verify_source_content() {
    [[ -f "$installer" && ! -L "$installer" ]]
    [[ -f "$candidate" && ! -L "$candidate" ]]
    [[ "$(file_hash "$installer")" = "$installer_sha256" ]]
    [[ "$(file_hash "$candidate")" = "$new_finalizer_sha256" ]]
    bash -n "$installer" "$candidate"
    "$collision_checker" "$installer" "$candidate" >/dev/null
    "$installer" --self-test >/dev/null
}

verify_workstation_sources() {
    [[ "$(stat -c '%U:%G:%a' "$installer")" = aaron:aaron:755 ]]
    [[ "$(stat -c '%U:%G:%a' "$candidate")" = aaron:aaron:755 ]]
    verify_source_content
}

validate_assertions() {
    local assertion_transcript=$1
    local expected_labels
    local observed_labels
    local expected_count
    local observed_count
    local reported_count
    local reported_failed
    local reported_first

    expected_labels=$(mktemp "$work_directory/expected.XXXXXX")
    observed_labels=$(mktemp "$work_directory/observed.XXXXXX")
    "$installer" --expected-checks | LC_ALL=C sort >"$expected_labels"
    sed -n \
        's/^action_17u_assertion_\([a-z0-9_]*\)=\(true\|false\)$/\1/p' \
        "$assertion_transcript" | LC_ALL=C sort >"$observed_labels"
    expected_count=$(wc -l <"$expected_labels")
    observed_count=$(wc -l <"$observed_labels")
    reported_count=$(value_for action_17u_assertion_count "$assertion_transcript") ||
        reported_count=invalid
    reported_failed=$(value_for action_17u_failed_assertion_count "$assertion_transcript") ||
        reported_failed=invalid
    reported_first=$(value_for action_17u_first_failure "$assertion_transcript") ||
        reported_first=invalid

    [[ "$expected_count" -eq 101 ]] || return 1
    [[ "$observed_count" -eq "$expected_count" ]] || return 1
    [[ "$(sort -u "$observed_labels" | wc -l)" -eq "$observed_count" ]] ||
        return 1
    cmp -s "$expected_labels" "$observed_labels" || return 1
    is_nonnegative_integer "$reported_count" || return 1
    [[ "$reported_count" -eq "$observed_count" ]] || return 1
    [[ "$reported_failed" = 0 ]] || return 1
    [[ "$reported_first" = none ]] || return 1
    ! grep -Eq '^action_17u_assertion_[a-z0-9_]+=false$' "$assertion_transcript"
}

validate_success() {
    local success_error=$1
    local success_output=$2
    local success_status=$3
    local backup_path

    [[ "$success_status" -eq 0 ]] || return 1
    [[ ! -s "$success_error" ]] || return 1
    transcript_grammar_valid "$success_output" || return 1
    validate_assertions "$success_output" || return 1
    if grep -Eq \
        '^action_17u_(finalizer_invoked|release_mutated|marker_mutated|lsyncd_reconciliation_activation|service_mutations)=true$' \
        "$success_output"; then
        return 1
    fi
    require_one action_17u_preflight_complete=true "$success_output" || return 1
    require_one action_17u_mutation_started=true "$success_output" || return 1
    for success_stream in install_stdout install_stderr; do
        require_one "action_17u_value_${success_stream}_bytes=0" \
            "$success_output" || return 1
        require_one "action_17u_value_${success_stream}_lines=0" \
            "$success_output" || return 1
        require_one "action_17u_value_${success_stream}_sha256=$empty_sha256" \
            "$success_output" || return 1
        require_one "action_17u_value_${success_stream}_classification=empty" \
            "$success_output" || return 1
        require_one "action_17u_${success_stream}_raw_emitted=false" \
            "$success_output" || return 1
    done
    require_one "action_17u_value_old_finalizer_sha256=$old_finalizer_sha256" \
        "$success_output" || return 1
    require_one "action_17u_value_new_finalizer_sha256=$new_finalizer_sha256" \
        "$success_output" || return 1
    require_one "action_17u_value_revision=$expected_revision" \
        "$success_output" || return 1
    backup_path=$(value_for action_17u_value_backup_path "$success_output") ||
        backup_path=invalid
    [[ "$backup_path" =~ ^/var/backups/caddy-ha/action17u-node-b-stderr-safe-finalizer\.[A-Za-z0-9]+$ ]] ||
        return 1
    require_one action_17u_finalizer_invoked=false "$success_output" || return 1
    require_one action_17u_release_mutated=false "$success_output" || return 1
    require_one action_17u_marker_mutated=false "$success_output" || return 1
    require_one action_17u_lsyncd_reconciliation_activation=false \
        "$success_output" || return 1
    require_one action_17u_service_mutations=false "$success_output" || return 1
    require_one \
        action_17u_persistent_mutation_scope=stderr_safe_finalizer,rollback_backup \
        "$success_output" || return 1
    require_one action_17u_node_b_stderr_safe_finalizer_install_complete=true \
        "$success_output" || return 1
    if grep -Eq '^action_17u_rollback_|manual_intervention_required=true' \
        "$success_output" "$success_error"; then
        return 1
    fi
}

validate_rollback_assertions() {
    local rollback_transcript=$1
    local expected_labels
    local observed_labels

    expected_labels=$(mktemp "$work_directory/rollback-expected.XXXXXX")
    observed_labels=$(mktemp "$work_directory/rollback-observed.XXXXXX")
    "$installer" --expected-rollback-checks | LC_ALL=C sort >"$expected_labels"
    sed -n \
        's/^action_17u_rollback_assertion_\([a-z0-9_]*\)=\(true\|false\)$/\1/p' \
        "$rollback_transcript" | LC_ALL=C sort >"$observed_labels"
    [[ "$(wc -l <"$expected_labels")" -eq 22 ]] || return 1
    [[ "$(wc -l <"$observed_labels")" -eq 22 ]] || return 1
    [[ "$(sort -u "$observed_labels" | wc -l)" -eq 22 ]] || return 1
    cmp -s "$expected_labels" "$observed_labels" || return 1
    ! grep -Eq '^action_17u_rollback_assertion_[a-z0-9_]+=false$' \
        "$rollback_transcript"
}

validate_failure() {
    local failure_error=$1
    local failure_output=$2
    local failure_status=$3

    [[ "$failure_status" -ne 0 ]] || return 97
    secret_free "$failure_output" "$failure_error" || return 97
    if grep -Fq manual_intervention_required=true \
        "$failure_output" "$failure_error" ||
        grep -Fq action_17u_rollback_complete=false \
            "$failure_output" "$failure_error"; then
        return 97
    fi
    if grep -Fxq action_17u_mutation_started=true "$failure_output"; then
        require_one action_17u_rollback_started=true "$failure_error" || return 97
        for failure_stream in rollback_install_stdout rollback_install_stderr; do
            require_one "action_17u_value_${failure_stream}_bytes=0" \
                "$failure_error" || return 97
            require_one "action_17u_value_${failure_stream}_lines=0" \
                "$failure_error" || return 97
            require_one "action_17u_value_${failure_stream}_sha256=$empty_sha256" \
                "$failure_error" || return 97
            require_one "action_17u_value_${failure_stream}_classification=empty" \
                "$failure_error" || return 97
            require_one "action_17u_${failure_stream}_raw_emitted=false" \
                "$failure_error" || return 97
        done
        validate_rollback_assertions "$failure_error" || return 97
        require_one action_17u_rollback_complete=true "$failure_error" || return 97
    elif grep -Eq '^action_17u_rollback_' "$failure_output" "$failure_error"; then
        return 97
    fi
}

write_remote_bundle() {
    local archive_source=$1
    local bundle_destination=$2

    # Literal remote-script source expands only after reaching Node B.
    # shellcheck disable=SC1003,SC2016
    {
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            'set -Eeuo pipefail' \
            'set +x' \
            'umask 077' \
            'PATH=/usr/sbin:/usr/bin:/sbin:/bin' \
            'export PATH' \
            'cd /' \
            'bundle_stage=$(mktemp -d /run/caddy-action17u-stage.XXXXXX)' \
            'cleanup_bundle_stage() {' \
            '    rm -rf -- "$bundle_stage"' \
            '}' \
            'trap cleanup_bundle_stage EXIT' \
            'install -d -o root -g root -m 0700 "$bundle_stage/payload"' \
            'base64 -d >"$bundle_stage/payload.tar" <<'\''ACTION17U_ARCHIVE'\'''
        base64 "$archive_source"
        printf '%s\n' \
            'ACTION17U_ARCHIVE' \
            'tar --extract --file "$bundle_stage/payload.tar" \' \
            '    --directory "$bundle_stage/payload" \' \
            '    --no-same-owner --no-same-permissions' \
            'chown -R root:root "$bundle_stage/payload"' \
            'chmod 0700 "$bundle_stage/payload"' \
            'chmod 0600 "$bundle_stage/payload"/*' \
            'chmod 0700 \' \
            '    "$bundle_stage/payload/install-node-b-stderr-safe-finalizer-action17u.sh"' \
            'cd /' \
            '/bin/bash \' \
            '    "$bundle_stage/payload/install-node-b-stderr-safe-finalizer-action17u.sh" \' \
            '    --stage "$bundle_stage/payload"'
    } >"$bundle_destination"
    chmod 0600 "$bundle_destination"
    bash -n "$bundle_destination"
}

write_success_fixture() {
    local fixture_destination=$1
    local fixture_label
    local fixture_count

    fixture_count=$("$installer" --expected-checks | wc -l)
    {
        while IFS= read -r fixture_label; do
            printf 'action_17u_assertion_%s=true\n' "$fixture_label"
        done < <("$installer" --expected-checks)
        printf '%s\n' \
            "action_17u_assertion_count=$fixture_count" \
            action_17u_failed_assertion_count=0 \
            action_17u_first_failure=none \
            action_17u_preflight_complete=true \
            action_17u_mutation_started=true \
            action_17u_value_install_stdout_bytes=0 \
            action_17u_value_install_stdout_lines=0 \
            "action_17u_value_install_stdout_sha256=$empty_sha256" \
            action_17u_value_install_stdout_classification=empty \
            action_17u_install_stdout_raw_emitted=false \
            action_17u_value_install_stderr_bytes=0 \
            action_17u_value_install_stderr_lines=0 \
            "action_17u_value_install_stderr_sha256=$empty_sha256" \
            action_17u_value_install_stderr_classification=empty \
            action_17u_install_stderr_raw_emitted=false \
            "action_17u_value_old_finalizer_sha256=$old_finalizer_sha256" \
            "action_17u_value_new_finalizer_sha256=$new_finalizer_sha256" \
            "action_17u_value_revision=$expected_revision" \
            action_17u_value_backup_path=/var/backups/caddy-ha/action17u-node-b-stderr-safe-finalizer.ABC123 \
            action_17u_finalizer_invoked=false \
            action_17u_release_mutated=false \
            action_17u_marker_mutated=false \
            action_17u_lsyncd_reconciliation_activation=false \
            action_17u_service_mutations=false \
            action_17u_persistent_mutation_scope=stderr_safe_finalizer,rollback_backup \
            action_17u_node_b_stderr_safe_finalizer_install_complete=true
    } >"$fixture_destination"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$expected_target" = pi@10.1.0.54 ]]
        [[ "$expected_host_alias" = pihole00.local.theama.co ]]
        is_sha256 "$installer_sha256"
        is_sha256 "$old_finalizer_sha256"
        is_sha256 "$new_finalizer_sha256"
        printf '%s_runner_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --source-test)
        [[ $# -eq 1 ]]
        verify_workstation_sources
        printf '%s_runner_source_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]]
        verify_source_content
        work_directory=$(mktemp -d /tmp/caddy-action17u-contract.XXXXXX)
        readonly work_directory
        trap 'rm -rf -- "$work_directory"' EXIT
        : >"$work_directory/empty.err"
        write_success_fixture "$work_directory/valid.out"
        validate_success "$work_directory/empty.err" "$work_directory/valid.out" 0
        printf 'action_17u_finalizer_invoked=true\n' >>"$work_directory/valid.out"
        if validate_success \
            "$work_directory/empty.err" "$work_directory/valid.out" 0; then
            printf 'Contradictory finalizer evidence was accepted.\n' >&2
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

verify_workstation_sources
work_directory=$(mktemp -d /tmp/caddy-action17u-runner.XXXXXX)
readonly work_directory
readonly payload_directory="$work_directory/payload"
readonly archive_path="$work_directory/payload.tar"
readonly bundle_path="$work_directory/remote-bundle.sh"
readonly remote_output="$work_directory/remote.out"
readonly remote_error="$work_directory/remote.err"
retain_work_directory=false

cleanup() {
    if [[ "$retain_work_directory" != true ]]; then
        rm -rf -- "$work_directory"
    fi
}
trap cleanup EXIT

finish() {
    local finish_status=$1

    cleanup
    trap - EXIT
    if [[ "$retain_work_directory" == true ]]; then
        printf '%s_workstation_evidence_retained=true\n' "$prefix" >&2
        printf '%s_workstation_cleanup_complete=false\n' "$prefix" >&2
        exit "$finish_status"
    fi
    if [[ -e "$work_directory" || -L "$work_directory" ]]; then
        printf '%s_workstation_cleanup_complete=false\n' "$prefix" >&2
        exit 97
    fi
    printf '%s_workstation_cleanup_complete=true\n' "$prefix"
    exit "$finish_status"
}

install -d -m 0700 "$payload_directory"
install -m 0700 "$installer" \
    "$payload_directory/install-node-b-stderr-safe-finalizer-action17u.sh"
install -m 0600 "$candidate" \
    "$payload_directory/finalize-incoming-release-v2.sh"
[[ "$(file_hash "$payload_directory/finalize-incoming-release-v2.sh")" = "$new_finalizer_sha256" ]]
tar --create --file "$archive_path" --directory "$payload_directory" \
    install-node-b-stderr-safe-finalizer-action17u.sh \
    finalize-incoming-release-v2.sh
write_remote_bundle "$archive_path" "$bundle_path"

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
    <"$bundle_path" >"$remote_output" 2>"$remote_error" || ssh_status=$?

emit_stream_evidence stdout "$remote_output"
emit_stream_evidence stderr "$remote_error"
stdout_classification=$(stream_classification \
    "$(wc -c <"$remote_output")" "$(line_count "$remote_output")" "$remote_output")
stderr_classification=$(stream_classification \
    "$(wc -c <"$remote_error")" "$(line_count "$remote_error")" "$remote_error")
readonly stdout_classification stderr_classification
printf '%s_ssh_status=%s\n' "$prefix" "$ssh_status"
secure_stream_content stdout "$remote_output" "$stdout_classification"
secure_stream_content stderr "$remote_error" "$stderr_classification" >&2

if [[ "$stdout_classification" != bounded_safe_unemitted ||
    "$stderr_classification" != empty &&
    "$stderr_classification" != bounded_safe_unemitted ]]; then
    printf 'Action 17u remote output classification is unsafe or unbounded.\n' >&2
    finish 97
fi
transcript_grammar_valid "$remote_output" || {
    printf 'Action 17u stdout transcript grammar failed.\n' >&2
    finish 97
}
if [[ -s "$remote_error" ]]; then
    transcript_grammar_valid "$remote_error" || {
        printf 'Action 17u stderr transcript grammar failed.\n' >&2
        finish 97
    }
fi
if [[ "$ssh_status" -eq 0 ]]; then
    if ! validate_success "$remote_error" "$remote_output" "$ssh_status"; then
        printf 'Action 17u success transcript contract failed.\n' >&2
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
    printf 'Action 17u rollback evidence is incomplete.\n' >&2
    finish 97
fi
printf '%s_runner_acceptance=false\n' "$prefix"
finish "$ssh_status"
