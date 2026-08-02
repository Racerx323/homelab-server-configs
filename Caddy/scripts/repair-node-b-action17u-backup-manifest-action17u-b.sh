#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_17u_b
readonly backup_directory=/var/backups/caddy-ha/action17u-node-b-stderr-safe-finalizer.N9uEhC
readonly backup_finalizer="$backup_directory/finalizer.before"
readonly backup_manifest="$backup_directory/manifest"
readonly live_finalizer=/usr/local/libexec/finalize-incoming-release-v2.sh
readonly old_finalizer_sha256=e5ec5aab0f57b9ea68c41f122de282c1d156a6747f9f74dd1f22200079c097e4
readonly new_finalizer_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d
readonly old_manifest_sha256=8b7ee379963bec0932dece5b11dd602efba33fe5d76a6e281c4db0c93b60dfbf
readonly new_manifest_sha256=a992c2ff9bdfde76770ddae910dedfc2a8bbdf6ad25de909ec5cbeacda31d70b
readonly release=/var/lib/caddy-sync/incoming/node-a/action17p-node-a-to-node-b-bootstrap
readonly expected_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly expected_release_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly expected_active_release=/etc/caddy/releases/action15-health-follow-redirects
readonly maximum_stream_bytes=4096
readonly maximum_stream_lines=20

assertion_count=0
failed_assertion_count=0
first_failure=none
mutation_started=false
transaction_complete=false
work_directory=
rollback_manifest=
candidate_manifest=
install_stdout=
install_stderr=
state_before=

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
    printf '%s_value_%s_bytes=%s\n' "$prefix" "$evidence_name" "$evidence_bytes"
    printf '%s_value_%s_lines=%s\n' "$prefix" "$evidence_name" "$evidence_lines"
    printf '%s_value_%s_sha256=%s\n' "$prefix" "$evidence_name" "$evidence_sha256"
    printf '%s_value_%s_classification=%s\n' \
        "$prefix" "$evidence_name" "$evidence_classification"
    if [[ "$evidence_classification" == bounded_safe ]]; then
        printf '%s_%s_safe_content_begin=true\n' "$prefix" "$evidence_name"
        cat -- "$evidence_path"
        printf '%s_%s_safe_content_end=true\n' "$prefix" "$evidence_name"
        printf '%s_%s_content_secured=emitted\n' "$prefix" "$evidence_name"
    elif [[ "$evidence_classification" == empty ]]; then
        printf '%s_%s_content_secured=empty\n' "$prefix" "$evidence_name"
    else
        printf '%s_%s_content_secured=protected_until_rollback_or_success\n' \
            "$prefix" "$evidence_name"
    fi
}

require_check() {
    local check_label=$1

    shift
    assertion_count=$((assertion_count + 1))
    if "$@" >/dev/null 2>&1; then
        printf '%s_assertion_%s=true\n' "$prefix" "$check_label"
        return 0
    fi
    failed_assertion_count=$((failed_assertion_count + 1))
    if [[ "$first_failure" == none ]]; then
        first_failure=$check_label
    fi
    printf '%s_assertion_%s=false\n' "$prefix" "$check_label" >&2
    return 1
}

rollback_check() {
    local rollback_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_rollback_assertion_%s=true\n' "$prefix" "$rollback_label" >&2
        return 0
    fi
    printf '%s_rollback_assertion_%s=false\n' "$prefix" "$rollback_label" >&2
    return 1
}

manifest_contract() {
    local contract_action=$1
    local contract_hash=$2
    local contract_path=$3

    [[ -f "$contract_path" && ! -L "$contract_path" ]] || return 1
    [[ "$(file_hash "$contract_path")" == "$contract_hash" ]] || return 1
    [[ "$(line_count "$contract_path")" -eq 3 ]] || return 1
    [[ "$(grep -Fxc "action=$contract_action" "$contract_path")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc "old_finalizer_sha256=$old_finalizer_sha256" "$contract_path")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc "new_finalizer_sha256=$new_finalizer_sha256" "$contract_path")" -eq 1 ]] || return 1
    awk -v action="$contract_action" -v old="$old_finalizer_sha256" -v new="$new_finalizer_sha256" '
        $0 == "action=" action { next }
        $0 == "old_finalizer_sha256=" old { next }
        $0 == "new_finalizer_sha256=" new { next }
        { exit 1 }
    ' "$contract_path" || return 1
}

payload_digest() {
    (
        cd "$release"
        find . -type f \
            ! -name .complete \
            ! -name .complete.pending \
            ! -name .finalize-request \
            -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r sha256sum |
            sha256sum |
            awk '{ print $1 }'
    )
}

continuity_snapshot() {
    {
        stat -c 'backup_dir|%F|%U:%G:%a' "$backup_directory"
        stat -c 'backup_finalizer|%F|%U:%G:%a:%s' "$backup_finalizer"
        stat -c 'backup_manifest_metadata|%F|%U:%G:%a:%s' "$backup_manifest"
        stat -c 'live_finalizer|%F|%U:%G:%a:%s' "$live_finalizer"
        printf 'backup_finalizer_hash|%s\n' "$(file_hash "$backup_finalizer")"
        printf 'live_finalizer_hash|%s\n' "$(file_hash "$live_finalizer")"
        printf 'payload_hash|%s\n' "$(payload_digest)"
        printf 'release_manifest_hash|%s\n' "$(file_hash "$release/manifest.sha256")"
        printf 'active_release|%s\n' "$(readlink -f /etc/caddy/current)"
        printf 'complete|%s\n' "$([[ -e "$release/.complete" ]] && printf present || printf absent)"
        printf 'pending|%s\n' "$([[ -e "$release/.complete.pending" ]] && printf present || printf absent)"
        printf 'request|%s\n' "$([[ -e "$release/.finalize-request" ]] && printf present || printf absent)"
        printf 'caddy|%s\n' "$(systemctl is-active caddy.service)"
        printf 'lighttpd|%s\n' "$(systemctl is-active lighttpd.service)"
        printf 'lsyncd|%s\n' "$(systemctl is-active lsyncd.service 2>/dev/null || true)"
        printf 'caddy_lsyncd|%s\n' "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)"
        printf 'reconcile_path|%s\n' "$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)"
        printf 'reconcile_service|%s\n' "$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)"
    } | sha256sum | awk '{ print $1 }'
}

report_summary() {
    printf '%s_value_assertion_count=%s\n' "$prefix" "$assertion_count"
    printf '%s_value_failed_assertion_count=%s\n' "$prefix" "$failed_assertion_count"
    printf '%s_value_first_failure=%s\n' "$prefix" "$first_failure"
}

rollback_transaction() {
    local original_status=$1
    local rollback_failed=false

    set +e
    printf '%s_rollback_started=true\n' "$prefix" >&2
    if [[ -n "$rollback_manifest" && -f "$rollback_manifest" ]]; then
        install -o root -g root -m 0600 -- "$rollback_manifest" "$backup_manifest"
    fi
    rollback_check manifest_restored_hash \
        test "$(file_hash "$backup_manifest" 2>/dev/null)" = "$old_manifest_sha256" || rollback_failed=true
    rollback_check manifest_restored_contract \
        manifest_contract 17t "$old_manifest_sha256" "$backup_manifest" || rollback_failed=true
    rollback_check manifest_restored_metadata \
        test "$(stat -c '%U:%G:%a' "$backup_manifest" 2>/dev/null)" = root:root:600 || rollback_failed=true
    rollback_check continuity_restored \
        test "$(continuity_snapshot 2>/dev/null)" = "$state_before" || rollback_failed=true
    if [[ -n "$work_directory" && -d "$work_directory" ]]; then
        rm -rf -- "$work_directory"
    fi
    rollback_check work_directory_removed test ! -e "$work_directory" || rollback_failed=true
    if [[ "$rollback_failed" == true ]]; then
        printf '%s_rollback_complete=false\n' "$prefix" >&2
        exit 125
    fi
    printf '%s_rollback_complete=true\n' "$prefix" >&2
    exit "$original_status"
}

on_exit() {
    local status=$?

    if [[ "$transaction_complete" == true ]]; then
        return
    fi
    if [[ "$mutation_started" == true ]]; then
        rollback_transaction "$status"
    fi
    if [[ -n "$work_directory" && -d "$work_directory" ]]; then
        rm -rf -- "$work_directory"
    fi
}
trap on_exit EXIT

print_expected_checks() {
    printf '%s\n' \
        effective_uid_root \
        working_directory_root \
        hostname_node_b \
        architecture_arm64 \
        backup_directory_regular \
        backup_directory_metadata \
        backup_finalizer_regular \
        backup_finalizer_metadata \
        backup_finalizer_hash \
        backup_manifest_regular \
        backup_manifest_metadata \
        backup_manifest_old_hash \
        backup_manifest_old_line_count \
        backup_manifest_old_action_once \
        backup_manifest_old_finalizer_once \
        backup_manifest_new_finalizer_once \
        backup_manifest_old_contract \
        live_finalizer_regular \
        live_finalizer_metadata \
        live_finalizer_hash \
        release_directory_regular \
        release_manifest_regular \
        release_manifest_hash \
        release_payload_hash \
        release_complete_absent \
        release_pending_absent \
        release_request_absent \
        active_release_exact \
        caddy_active \
        lighttpd_active \
        lsyncd_not_active \
        caddy_lsyncd_not_active \
        reconcile_path_not_active \
        reconcile_service_not_active \
        action17u_b_stage_absent \
        rollback_copy_hash \
        rollback_copy_contract \
        candidate_hash \
        candidate_line_count \
        candidate_action_once \
        candidate_old_finalizer_once \
        candidate_new_finalizer_once \
        candidate_contract \
        install_stdout_safe \
        install_stderr_safe \
        repaired_manifest_hash \
        repaired_manifest_line_count \
        repaired_manifest_action_once \
        repaired_manifest_old_finalizer_once \
        repaired_manifest_new_finalizer_once \
        repaired_manifest_contract \
        repaired_manifest_metadata \
        continuity_unchanged \
        work_directory_removed
}

self_test() {
    local self_test_directory
    local old_fixture
    local new_fixture

    self_test_directory=$(mktemp -d /tmp/caddy-action17u-b-self-test.XXXXXX)
    old_fixture="$self_test_directory/old"
    new_fixture="$self_test_directory/new"
    printf 'action=17t\nold_finalizer_sha256=%s\nnew_finalizer_sha256=%s\n' \
        "$old_finalizer_sha256" "$new_finalizer_sha256" >"$old_fixture"
    printf 'action=17u\nold_finalizer_sha256=%s\nnew_finalizer_sha256=%s\n' \
        "$old_finalizer_sha256" "$new_finalizer_sha256" >"$new_fixture"
    manifest_contract 17t "$old_manifest_sha256" "$old_fixture"
    manifest_contract 17u "$new_manifest_sha256" "$new_fixture"
    if manifest_contract 17u "$new_manifest_sha256" "$old_fixture"; then
        return 1
    fi
    rm -rf -- "$self_test_directory"
    printf '%s_self_test_passed=true\n' "$prefix"
}

case "${1:-}" in
    --expected-checks)
        print_expected_checks
        exit 0
        ;;
    --self-test)
        self_test
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--expected-checks|--self-test]\n' "$0" >&2
        exit 64
        ;;
esac

require_check effective_uid_root test "$(id -u)" -eq 0
require_check working_directory_root test "$PWD" = /
require_check hostname_node_b test "$(hostname -s)" = pihole00
require_check architecture_arm64 test "$(dpkg --print-architecture)" = arm64
require_check backup_directory_regular test -d "$backup_directory"
require_check backup_directory_metadata test "$(stat -c '%U:%G:%a' "$backup_directory")" = root:root:700
require_check backup_finalizer_regular test -f "$backup_finalizer"
require_check backup_finalizer_metadata test "$(stat -c '%U:%G:%a' "$backup_finalizer")" = root:root:600
require_check backup_finalizer_hash test "$(file_hash "$backup_finalizer")" = "$old_finalizer_sha256"
require_check backup_manifest_regular test -f "$backup_manifest"
require_check backup_manifest_metadata test "$(stat -c '%U:%G:%a' "$backup_manifest")" = root:root:600
require_check backup_manifest_old_hash test "$(file_hash "$backup_manifest")" = "$old_manifest_sha256"
require_check backup_manifest_old_line_count test "$(line_count "$backup_manifest")" -eq 3
require_check backup_manifest_old_action_once test "$(grep -Fxc action=17t "$backup_manifest")" -eq 1
require_check backup_manifest_old_finalizer_once test "$(grep -Fxc "old_finalizer_sha256=$old_finalizer_sha256" "$backup_manifest")" -eq 1
require_check backup_manifest_new_finalizer_once test "$(grep -Fxc "new_finalizer_sha256=$new_finalizer_sha256" "$backup_manifest")" -eq 1
require_check backup_manifest_old_contract manifest_contract 17t "$old_manifest_sha256" "$backup_manifest"
require_check live_finalizer_regular test -f "$live_finalizer"
require_check live_finalizer_metadata test "$(stat -c '%U:%G:%a' "$live_finalizer")" = root:root:755
require_check live_finalizer_hash test "$(file_hash "$live_finalizer")" = "$new_finalizer_sha256"
require_check release_directory_regular test -d "$release"
require_check release_manifest_regular test -f "$release/manifest.sha256"
require_check release_manifest_hash test "$(file_hash "$release/manifest.sha256")" = "$expected_release_manifest_sha256"
require_check release_payload_hash test "$(payload_digest)" = "$expected_payload_sha256"
require_check release_complete_absent test ! -e "$release/.complete"
require_check release_pending_absent test ! -e "$release/.complete.pending"
require_check release_request_absent test ! -e "$release/.finalize-request"
require_check active_release_exact test "$(readlink -f /etc/caddy/current)" = "$expected_active_release"
require_check caddy_active systemctl is-active --quiet caddy.service
require_check lighttpd_active systemctl is-active --quiet lighttpd.service
require_check lsyncd_not_active test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" != active
require_check caddy_lsyncd_not_active test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" != active
require_check reconcile_path_not_active test "$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)" != active
require_check reconcile_service_not_active test "$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)" != active
require_check action17u_b_stage_absent test "$(find /run -mindepth 1 -maxdepth 1 -type d -name 'caddy-action17u-b.*' -print | wc -l)" -eq 0

state_before=$(continuity_snapshot)
work_directory=$(mktemp -d /run/caddy-action17u-b.XXXXXX)
rollback_manifest="$work_directory/manifest.before"
candidate_manifest="$work_directory/manifest.candidate"
install_stdout="$work_directory/install.stdout"
install_stderr="$work_directory/install.stderr"
install -o root -g root -m 0600 -- "$backup_manifest" "$rollback_manifest"
require_check rollback_copy_hash test "$(file_hash "$rollback_manifest")" = "$old_manifest_sha256"
require_check rollback_copy_contract manifest_contract 17t "$old_manifest_sha256" "$rollback_manifest"
printf 'action=17u\nold_finalizer_sha256=%s\nnew_finalizer_sha256=%s\n' \
    "$old_finalizer_sha256" "$new_finalizer_sha256" >"$candidate_manifest"
chmod 0600 "$candidate_manifest"
require_check candidate_hash test "$(file_hash "$candidate_manifest")" = "$new_manifest_sha256"
require_check candidate_line_count test "$(line_count "$candidate_manifest")" -eq 3
require_check candidate_action_once test "$(grep -Fxc action=17u "$candidate_manifest")" -eq 1
require_check candidate_old_finalizer_once test "$(grep -Fxc "old_finalizer_sha256=$old_finalizer_sha256" "$candidate_manifest")" -eq 1
require_check candidate_new_finalizer_once test "$(grep -Fxc "new_finalizer_sha256=$new_finalizer_sha256" "$candidate_manifest")" -eq 1
require_check candidate_contract manifest_contract 17u "$new_manifest_sha256" "$candidate_manifest"

mutation_started=true
if ! install -o root -g root -m 0600 -- "$candidate_manifest" "$backup_manifest" \
    >"$install_stdout" 2>"$install_stderr"; then
    emit_stream_evidence install_stdout "$install_stdout"
    emit_stream_evidence install_stderr "$install_stderr"
    exit 1
fi
emit_stream_evidence install_stdout "$install_stdout"
emit_stream_evidence install_stderr "$install_stderr"
require_check install_stdout_safe test "$(stream_classification "$(wc -c <"$install_stdout")" "$(line_count "$install_stdout")" "$install_stdout")" = empty
require_check install_stderr_safe test "$(stream_classification "$(wc -c <"$install_stderr")" "$(line_count "$install_stderr")" "$install_stderr")" = empty
require_check repaired_manifest_hash test "$(file_hash "$backup_manifest")" = "$new_manifest_sha256"
require_check repaired_manifest_line_count test "$(line_count "$backup_manifest")" -eq 3
require_check repaired_manifest_action_once test "$(grep -Fxc action=17u "$backup_manifest")" -eq 1
require_check repaired_manifest_old_finalizer_once test "$(grep -Fxc "old_finalizer_sha256=$old_finalizer_sha256" "$backup_manifest")" -eq 1
require_check repaired_manifest_new_finalizer_once test "$(grep -Fxc "new_finalizer_sha256=$new_finalizer_sha256" "$backup_manifest")" -eq 1
require_check repaired_manifest_contract manifest_contract 17u "$new_manifest_sha256" "$backup_manifest"
require_check repaired_manifest_metadata test "$(stat -c '%U:%G:%a' "$backup_manifest")" = root:root:600
require_check continuity_unchanged test "$(continuity_snapshot)" = "$state_before"

rm -rf -- "$work_directory"
require_check work_directory_removed test ! -e "$work_directory"
transaction_complete=true
report_summary
printf '%s_value_old_manifest_sha256=%s\n' "$prefix" "$old_manifest_sha256"
printf '%s_value_new_manifest_sha256=%s\n' "$prefix" "$new_manifest_sha256"
printf '%s_value_backup_directory=%s\n' "$prefix" "$backup_directory"
printf '%s_value_persistent_change=backup_manifest_action_only\n' "$prefix"
printf '%s_transaction_complete=true\n' "$prefix"
