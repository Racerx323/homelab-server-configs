#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_17u
readonly live_finalizer=/usr/local/libexec/finalize-incoming-release-v2.sh
readonly old_finalizer_sha256=e5ec5aab0f57b9ea68c41f122de282c1d156a6747f9f74dd1f22200079c097e4
readonly new_finalizer_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d
readonly new_validate_block_sha256=009c91d9141372792216d705168b356d1ab968936fbc89ddc01c1dc69ee68d82
readonly new_capture_function_sha256=70fedbe2fb6457a62f011484f09508fac68e6c19a3cb16ad3e8900547bbf5f21
readonly rollback_root=/var/backups/caddy-ha
readonly prior_backup_directory="$rollback_root/action17t-node-b-stdout-safe-finalizer.Z6U7Yc"
readonly prior_backup_finalizer="$prior_backup_directory/finalizer.before"
readonly prior_backup_manifest="$prior_backup_directory/manifest"
readonly prior_backup_finalizer_sha256=a49dadcaa611e641a100e6a4f2b1836fcf9a790876f437ee02e37003d78ef30c
readonly prior_backup_manifest_sha256=1c77b0bbab0b9b6cc0cd134c6748553fd686e12e665cb7131552578a1182f15d
readonly revision=action17p-node-a-to-node-b-bootstrap
readonly release=/var/lib/caddy-sync/incoming/node-a/action17p-node-a-to-node-b-bootstrap
readonly expected_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly expected_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly expected_active_release=/etc/caddy/releases/action15-health-follow-redirects
readonly maximum_stream_bytes=4096
readonly maximum_stream_lines=20
# These source-contract strings intentionally contain literal variable names.
# shellcheck disable=SC2016
readonly validation_capture_line='--adapter caddyfile >/dev/null 2>"$validation_error"'
# shellcheck disable=SC2016
readonly validation_stderr_redirect='2>"$validation_error"'
# shellcheck disable=SC2016
readonly validation_failure_replay='cat -- "$validation_error" >&2 || :'
# shellcheck disable=SC2016
readonly validation_function_call='validate_caddy_configuration "$release_path"'

assertion_count=0
failed_assertion_count=0
first_failure=none
mutation_started=false
transaction_complete=false
rollback_directory=
work_directory=
declare -A state_before=()

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
        printf 'bounded_safe_unemitted\n'
    fi
}

emit_stream_evidence() {
    local evidence_channel=$1
    local evidence_name=$2
    local evidence_path=$3
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
    if [[ "$evidence_channel" == stderr ]]; then
        printf '%s_value_%s_bytes=%s\n' \
            "$prefix" "$evidence_name" "$evidence_bytes" >&2
        printf '%s_value_%s_lines=%s\n' \
            "$prefix" "$evidence_name" "$evidence_lines" >&2
        printf '%s_value_%s_sha256=%s\n' \
            "$prefix" "$evidence_name" "$evidence_sha256" >&2
        printf '%s_value_%s_classification=%s\n' \
            "$prefix" "$evidence_name" "$evidence_classification" >&2
        printf '%s_%s_raw_emitted=false\n' \
            "$prefix" "$evidence_name" >&2
    else
        printf '%s_value_%s_bytes=%s\n' \
            "$prefix" "$evidence_name" "$evidence_bytes"
        printf '%s_value_%s_lines=%s\n' \
            "$prefix" "$evidence_name" "$evidence_lines"
        printf '%s_value_%s_sha256=%s\n' \
            "$prefix" "$evidence_name" "$evidence_sha256"
        printf '%s_value_%s_classification=%s\n' \
            "$prefix" "$evidence_name" "$evidence_classification"
        printf '%s_%s_raw_emitted=false\n' "$prefix" "$evidence_name"
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
        printf '%s_rollback_assertion_%s=true\n' \
            "$prefix" "$rollback_label" >&2
        return 0
    fi
    printf '%s_rollback_assertion_%s=false\n' \
        "$prefix" "$rollback_label" >&2
    return 1
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

release_snapshot() {
    (
        cd "$release"
        find . -printf '%P|%y|%U:%G:%m:%s\n' | LC_ALL=C sort
        find . -type f -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r sha256sum
    )
}

validate_block_hash() {
    awk '
        /^[[:space:]]*require_check caddy_configuration_valid/ {
            capture = 1
        }
        capture { print }
        capture && /validate_caddy_configuration "[$]release_path"/ { exit }
    ' "$1" | sha256sum | awk '{ print $1 }'
}

capture_function_hash() {
    awk '
        /^validate_caddy_configuration[(][)]/ { capture = 1 }
        capture { print }
        capture && /^}/ { exit }
    ' "$1" | sha256sum | awk '{ print $1 }'
}

prior_backup_snapshot() {
    stat -c '%n|%F|%U:%G:%a:%s' \
        "$prior_backup_directory" \
        "$prior_backup_finalizer" \
        "$prior_backup_manifest"
    file_hash "$prior_backup_finalizer"
    file_hash "$prior_backup_manifest"
}

capture_continuity_state() {
    state_before[caddy_active]=$(systemctl is-active caddy.service)
    state_before[lighttpd_active]=$(systemctl is-active lighttpd.service)
    state_before[lsyncd_active]=$(
        systemctl is-active lsyncd.service 2>/dev/null || true
    )
    state_before[lsyncd_enabled]=$(
        systemctl is-enabled lsyncd.service 2>/dev/null || true
    )
    state_before[caddy_lsyncd_active]=$(
        systemctl is-active caddy-lsyncd.service 2>/dev/null || true
    )
    state_before[reconcile_path_active]=$(
        systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true
    )
    state_before[reconcile_service_active]=$(
        systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true
    )
    state_before[current_link]=$(readlink /etc/caddy/current)
    state_before[current_target]=$(readlink -e /etc/caddy/current)
}

validate_continuity() {
    local continuity_namespace=$1
    local continuity_mode=$2

    if [[ "$continuity_mode" == rollback ]]; then
        rollback_check "${continuity_namespace}_caddy_active" \
            test "$(systemctl is-active caddy.service)" = \
            "${state_before[caddy_active]}"
        rollback_check "${continuity_namespace}_lighttpd_active" \
            test "$(systemctl is-active lighttpd.service)" = \
            "${state_before[lighttpd_active]}"
        rollback_check "${continuity_namespace}_lsyncd_active" \
            test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = \
            "${state_before[lsyncd_active]}"
        rollback_check "${continuity_namespace}_lsyncd_enabled" \
            test "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" = \
            "${state_before[lsyncd_enabled]}"
        rollback_check "${continuity_namespace}_caddy_lsyncd_active" \
            test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = \
            "${state_before[caddy_lsyncd_active]}"
        rollback_check "${continuity_namespace}_reconcile_path_active" \
            test "$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)" = \
            "${state_before[reconcile_path_active]}"
        rollback_check "${continuity_namespace}_reconcile_service_active" \
            test "$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)" = \
            "${state_before[reconcile_service_active]}"
        rollback_check "${continuity_namespace}_current_link" \
            test "$(readlink /etc/caddy/current)" = \
            "${state_before[current_link]}"
        rollback_check "${continuity_namespace}_current_target" \
            test "$(readlink -e /etc/caddy/current)" = \
            "${state_before[current_target]}"
    else
        require_check "${continuity_namespace}_caddy_active" \
            test "$(systemctl is-active caddy.service)" = \
            "${state_before[caddy_active]}"
        require_check "${continuity_namespace}_lighttpd_active" \
            test "$(systemctl is-active lighttpd.service)" = \
            "${state_before[lighttpd_active]}"
        require_check "${continuity_namespace}_lsyncd_active" \
            test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = \
            "${state_before[lsyncd_active]}"
        require_check "${continuity_namespace}_lsyncd_enabled" \
            test "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" = \
            "${state_before[lsyncd_enabled]}"
        require_check "${continuity_namespace}_caddy_lsyncd_active" \
            test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = \
            "${state_before[caddy_lsyncd_active]}"
        require_check "${continuity_namespace}_reconcile_path_active" \
            test "$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)" = \
            "${state_before[reconcile_path_active]}"
        require_check "${continuity_namespace}_reconcile_service_active" \
            test "$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)" = \
            "${state_before[reconcile_service_active]}"
        require_check "${continuity_namespace}_current_link" \
            test "$(readlink /etc/caddy/current)" = \
            "${state_before[current_link]}"
        require_check "${continuity_namespace}_current_target" \
            test "$(readlink -e /etc/caddy/current)" = \
            "${state_before[current_target]}"
    fi
}

rollback() {
    local rollback_failed=0
    local rollback_install_status=0
    local rollback_output
    local rollback_error

    [[ "$mutation_started" == true && "$transaction_complete" != true ]] || return 0
    trap - EXIT
    set +e
    printf '%s_rollback_started=true\n' "$prefix" >&2
    rollback_output="$work_directory/rollback-install.out"
    rollback_error="$work_directory/rollback-install.err"
    install -o root -g root -m 0755 \
        "$rollback_directory/finalizer.before" "$live_finalizer" \
        >"$rollback_output" 2>"$rollback_error" || rollback_install_status=$?
    emit_stream_evidence stderr rollback_install_stdout "$rollback_output"
    emit_stream_evidence stderr rollback_install_stderr "$rollback_error"
    rollback_check install_status_zero test "$rollback_install_status" -eq 0 ||
        rollback_failed=1
    rollback_check install_stdout_empty test ! -s "$rollback_output" ||
        rollback_failed=1
    rollback_check install_stderr_empty test ! -s "$rollback_error" ||
        rollback_failed=1
    rollback_check live_finalizer_old_hash \
        test "$(file_hash "$live_finalizer")" = "$old_finalizer_sha256" ||
        rollback_failed=1
    rollback_check live_finalizer_metadata \
        test "$(stat -c '%U:%G:%a' "$live_finalizer")" = root:root:755 ||
        rollback_failed=1
    rollback_check payload_hash_exact \
        test "$(payload_digest)" = "$expected_payload_sha256" || rollback_failed=1
    rollback_check manifest_hash_exact \
        test "$(file_hash "$release/manifest.sha256")" = \
        "$expected_manifest_sha256" || rollback_failed=1
    rollback_check prior_backup_unchanged \
        test "$(prior_backup_snapshot | sha256sum | awk '{ print $1 }')" = \
        "$prior_backup_before_sha256" || rollback_failed=1
    rollback_check request_absent test ! -e "$release/.finalize-request" ||
        rollback_failed=1
    rollback_check pending_absent test ! -e "$release/.complete.pending" ||
        rollback_failed=1
    rollback_check complete_absent test ! -e "$release/.complete" ||
        rollback_failed=1
    validate_continuity rollback_continuity rollback || rollback_failed=1
    rm -rf -- "$rollback_directory"
    rollback_check backup_absent test ! -e "$rollback_directory" ||
        rollback_failed=1
    rm -rf -- "$work_directory"
    rollback_check work_directory_absent test ! -e "$work_directory" ||
        rollback_failed=1
    if [[ "$rollback_failed" -eq 0 ]]; then
        printf '%s_rollback_complete=true\n' "$prefix" >&2
        exit 1
    fi
    printf '%s_rollback_complete=false\n' "$prefix" >&2
    printf '%s_manual_intervention_required=true\n' "$prefix" >&2
    exit 125
}

expected_check_labels() {
    printf '%s\n' \
        identity_root working_directory_root hostname_node_b architecture_arm64 \
        stage_directory stage_not_symlink stage_metadata candidate_regular \
        candidate_not_symlink candidate_metadata candidate_hash candidate_syntax \
        candidate_capture_function_single candidate_capture_function_hash \
        candidate_success_stdout_suppression candidate_success_stderr_capture \
        candidate_failure_stderr_replay candidate_validation_call_single \
        candidate_validate_block_hash \
        live_finalizer_regular live_finalizer_not_symlink live_finalizer_metadata \
        live_finalizer_old_hash live_finalizer_syntax rollback_root_directory \
        rollback_root_not_symlink rollback_root_metadata \
        action17u_backup_count_zero prior_backup_directory \
        prior_backup_not_symlink prior_backup_metadata \
        prior_backup_finalizer_regular prior_backup_finalizer_hash \
        prior_backup_manifest_regular prior_backup_manifest_hash \
        prior_backup_manifest_action prior_backup_manifest_old_hash \
        prior_backup_manifest_new_hash \
        release_directory release_not_symlink release_metadata request_absent \
        request_not_symlink pending_absent pending_not_symlink complete_absent \
        complete_not_symlink payload_hash_exact manifest_hash_exact \
        release_directories_locked release_files_locked caddy_active lighttpd_active \
        lsyncd_inactive lsyncd_masked caddy_lsyncd_inactive reconcile_path_inactive \
        reconcile_service_inactive active_release_expected backup_directory \
        backup_not_symlink backup_metadata \
        backup_finalizer backup_finalizer_not_symlink backup_finalizer_metadata \
        backup_finalizer_hash backup_manifest backup_manifest_metadata \
        install_status_zero install_stdout_empty install_stderr_empty \
        installed_finalizer_regular installed_finalizer_not_symlink \
        installed_finalizer_metadata installed_finalizer_hash installed_finalizer_syntax \
        installed_capture_function_single installed_capture_function_hash \
        installed_success_stdout_suppression installed_success_stderr_capture \
        installed_failure_stderr_replay installed_validation_call_single \
        installed_validate_block_hash \
        payload_hash_unchanged manifest_hash_unchanged release_state_unchanged \
        request_still_absent pending_still_absent complete_still_absent \
        post_caddy_active post_lighttpd_active post_lsyncd_active post_lsyncd_enabled \
        post_caddy_lsyncd_active post_reconcile_path_active \
        post_reconcile_service_active post_current_link post_current_target \
        prior_backup_unchanged backup_retained backup_manifest_final_hash
}

expected_rollback_check_labels() {
    printf '%s\n' \
        install_status_zero install_stdout_empty install_stderr_empty \
        live_finalizer_old_hash live_finalizer_metadata payload_hash_exact \
        manifest_hash_exact prior_backup_unchanged request_absent pending_absent complete_absent \
        rollback_continuity_caddy_active \
        rollback_continuity_lighttpd_active \
        rollback_continuity_lsyncd_active \
        rollback_continuity_lsyncd_enabled \
        rollback_continuity_caddy_lsyncd_active \
        rollback_continuity_reconcile_path_active \
        rollback_continuity_reconcile_service_active \
        rollback_continuity_current_link \
        rollback_continuity_current_target backup_absent work_directory_absent
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$old_finalizer_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$new_finalizer_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$new_validate_block_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$new_capture_function_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$(expected_check_labels | wc -l)" -gt 70 ]]
        [[ "$(expected_check_labels | LC_ALL=C sort -u | wc -l)" = "$(expected_check_labels | wc -l)" ]]
        [[ "$(expected_rollback_check_labels | wc -l)" -eq 22 ]]
        [[ "$(expected_rollback_check_labels | LC_ALL=C sort -u | wc -l)" = "$(expected_rollback_check_labels | wc -l)" ]]
        printf '%s_installer_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --expected-checks)
        [[ $# -eq 1 ]]
        expected_check_labels
        exit 0
        ;;
    --expected-rollback-checks)
        [[ $# -eq 1 ]]
        expected_rollback_check_labels
        exit 0
        ;;
    "")
        printf 'Usage: %s --stage DIRECTORY\n' "${0##*/}" >&2
        exit 2
        ;;
    --stage)
        [[ $# -eq 2 ]]
        ;;
    *)
        printf 'Usage: %s --stage DIRECTORY\n' "${0##*/}" >&2
        exit 2
        ;;
esac

readonly stage_directory=$2
readonly candidate="$stage_directory/finalize-incoming-release-v2.sh"

require_check identity_root test "$(id -u)" -eq 0
require_check working_directory_root test "$(pwd -P)" = /
require_check hostname_node_b test "$(hostname)" = j1-svpihole00
require_check architecture_arm64 test "$(dpkg --print-architecture)" = arm64
require_check stage_directory test -d "$stage_directory"
require_check stage_not_symlink test ! -L "$stage_directory"
require_check stage_metadata \
    test "$(stat -c '%U:%G:%a' "$stage_directory")" = root:root:700
require_check candidate_regular test -f "$candidate"
require_check candidate_not_symlink test ! -L "$candidate"
require_check candidate_metadata \
    test "$(stat -c '%U:%G:%a' "$candidate")" = root:root:600
require_check candidate_hash \
    test "$(file_hash "$candidate")" = "$new_finalizer_sha256"
require_check candidate_syntax bash -n "$candidate"
require_check candidate_capture_function_single \
    test "$(grep -Ec '^validate_caddy_configuration[(][)]' "$candidate")" -eq 1
require_check candidate_capture_function_hash \
    test "$(capture_function_hash "$candidate")" = "$new_capture_function_sha256"
require_check candidate_success_stdout_suppression \
    test "$(grep -Fc -- "$validation_capture_line" "$candidate")" -eq 1
require_check candidate_success_stderr_capture \
    test "$(grep -Fc "$validation_stderr_redirect" "$candidate")" -eq 1
require_check candidate_failure_stderr_replay \
    test "$(grep -Fc "$validation_failure_replay" "$candidate")" -eq 1
require_check candidate_validation_call_single \
    test "$(grep -Fc "$validation_function_call" "$candidate")" -eq 1
require_check candidate_validate_block_hash \
    test "$(validate_block_hash "$candidate")" = "$new_validate_block_sha256"
require_check live_finalizer_regular test -f "$live_finalizer"
require_check live_finalizer_not_symlink test ! -L "$live_finalizer"
require_check live_finalizer_metadata \
    test "$(stat -c '%U:%G:%a' "$live_finalizer")" = root:root:755
require_check live_finalizer_old_hash \
    test "$(file_hash "$live_finalizer")" = "$old_finalizer_sha256"
require_check live_finalizer_syntax bash -n "$live_finalizer"
require_check rollback_root_directory test -d "$rollback_root"
require_check rollback_root_not_symlink test ! -L "$rollback_root"
require_check rollback_root_metadata \
    test "$(stat -c '%U:%G:%a' "$rollback_root")" = root:root:700
require_check action17u_backup_count_zero \
    test "$(find "$rollback_root" -mindepth 1 -maxdepth 1 \
        -type d -name 'action17u-node-b-stderr-safe-finalizer.*' -print | wc -l)" -eq 0
require_check prior_backup_directory test -d "$prior_backup_directory"
require_check prior_backup_not_symlink test ! -L "$prior_backup_directory"
require_check prior_backup_metadata \
    test "$(stat -c '%U:%G:%a' "$prior_backup_directory")" = root:root:700
require_check prior_backup_finalizer_regular test -f "$prior_backup_finalizer"
require_check prior_backup_finalizer_hash \
    test "$(file_hash "$prior_backup_finalizer")" = "$prior_backup_finalizer_sha256"
require_check prior_backup_manifest_regular test -f "$prior_backup_manifest"
require_check prior_backup_manifest_hash \
    test "$(file_hash "$prior_backup_manifest")" = "$prior_backup_manifest_sha256"
require_check prior_backup_manifest_action \
    grep -Fxq action=17t "$prior_backup_manifest"
require_check prior_backup_manifest_old_hash \
    grep -Fxq "old_finalizer_sha256=$prior_backup_finalizer_sha256" \
    "$prior_backup_manifest"
require_check prior_backup_manifest_new_hash \
    grep -Fxq "new_finalizer_sha256=$old_finalizer_sha256" \
    "$prior_backup_manifest"
require_check release_directory test -d "$release"
require_check release_not_symlink test ! -L "$release"
require_check release_metadata \
    test "$(stat -c '%U:%G:%a' "$release")" = caddy-sync:caddy-sync:550
require_check request_absent test ! -e "$release/.finalize-request"
require_check request_not_symlink test ! -L "$release/.finalize-request"
require_check pending_absent test ! -e "$release/.complete.pending"
require_check pending_not_symlink test ! -L "$release/.complete.pending"
require_check complete_absent test ! -e "$release/.complete"
require_check complete_not_symlink test ! -L "$release/.complete"
require_check payload_hash_exact \
    test "$(payload_digest)" = "$expected_payload_sha256"
require_check manifest_hash_exact \
    test "$(file_hash "$release/manifest.sha256")" = "$expected_manifest_sha256"
require_check release_directories_locked \
    test -z "$(find "$release" -type d ! -perm 0550 -print -quit)"
require_check release_files_locked \
    test -z "$(find "$release" -type f ! -perm 0440 -print -quit)"
require_check caddy_active test "$(systemctl is-active caddy.service)" = active
require_check lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
require_check lsyncd_inactive \
    test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
require_check lsyncd_masked \
    test "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" = masked
require_check caddy_lsyncd_inactive \
    test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = inactive
require_check reconcile_path_inactive \
    test "$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)" = inactive
require_check reconcile_service_inactive \
    test "$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)" = inactive
require_check active_release_expected \
    test "$(readlink -e /etc/caddy/current)" = "$expected_active_release"

capture_continuity_state
work_directory=$(mktemp -d /run/caddy-action17u-node-b.XXXXXX)
readonly work_directory
readonly release_before="$work_directory/release.before"
readonly install_output="$work_directory/install.out"
readonly install_error="$work_directory/install.err"
release_snapshot >"$release_before"
release_before_sha256=$(file_hash "$release_before")
readonly release_before_sha256
prior_backup_before_sha256=$(prior_backup_snapshot | sha256sum | awk '{ print $1 }')
readonly prior_backup_before_sha256

printf '%s_preflight_complete=true\n' "$prefix"

trap rollback EXIT
mutation_started=true
printf '%s_mutation_started=true\n' "$prefix"
rollback_directory=$(
    mktemp -d "$rollback_root/action17u-node-b-stderr-safe-finalizer.XXXXXX"
)
chmod 0700 "$rollback_directory"
install -o root -g root -m 0600 \
    "$live_finalizer" "$rollback_directory/finalizer.before"
{
    printf 'action=17t\n'
    printf 'old_finalizer_sha256=%s\n' "$old_finalizer_sha256"
    printf 'new_finalizer_sha256=%s\n' "$new_finalizer_sha256"
} >"$rollback_directory/manifest"
chmod 0600 "$rollback_directory/manifest"
require_check backup_directory test -d "$rollback_directory"
require_check backup_not_symlink test ! -L "$rollback_directory"
require_check backup_metadata \
    test "$(stat -c '%U:%G:%a' "$rollback_directory")" = root:root:700
require_check backup_finalizer test -f "$rollback_directory/finalizer.before"
require_check backup_finalizer_not_symlink \
    test ! -L "$rollback_directory/finalizer.before"
require_check backup_finalizer_metadata \
    test "$(stat -c '%U:%G:%a' "$rollback_directory/finalizer.before")" = \
    root:root:600
require_check backup_finalizer_hash \
    test "$(file_hash "$rollback_directory/finalizer.before")" = \
    "$old_finalizer_sha256"
require_check backup_manifest test -f "$rollback_directory/manifest"
require_check backup_manifest_metadata \
    test "$(stat -c '%U:%G:%a' "$rollback_directory/manifest")" = root:root:600
backup_manifest_sha256=$(file_hash "$rollback_directory/manifest")
readonly backup_manifest_sha256

install_status=0
install -o root -g root -m 0755 "$candidate" "$live_finalizer" \
    >"$install_output" 2>"$install_error" || install_status=$?
readonly install_status
emit_stream_evidence stdout install_stdout "$install_output"
emit_stream_evidence stdout install_stderr "$install_error"
require_check install_status_zero test "$install_status" -eq 0
require_check install_stdout_empty test ! -s "$install_output"
require_check install_stderr_empty test ! -s "$install_error"
require_check installed_finalizer_regular test -f "$live_finalizer"
require_check installed_finalizer_not_symlink test ! -L "$live_finalizer"
require_check installed_finalizer_metadata \
    test "$(stat -c '%U:%G:%a' "$live_finalizer")" = root:root:755
require_check installed_finalizer_hash \
    test "$(file_hash "$live_finalizer")" = "$new_finalizer_sha256"
require_check installed_finalizer_syntax bash -n "$live_finalizer"
require_check installed_capture_function_single \
    test "$(grep -Ec '^validate_caddy_configuration[(][)]' "$live_finalizer")" -eq 1
require_check installed_capture_function_hash \
    test "$(capture_function_hash "$live_finalizer")" = "$new_capture_function_sha256"
require_check installed_success_stdout_suppression \
    test "$(grep -Fc -- "$validation_capture_line" "$live_finalizer")" -eq 1
require_check installed_success_stderr_capture \
    test "$(grep -Fc "$validation_stderr_redirect" "$live_finalizer")" -eq 1
require_check installed_failure_stderr_replay \
    test "$(grep -Fc "$validation_failure_replay" "$live_finalizer")" -eq 1
require_check installed_validation_call_single \
    test "$(grep -Fc "$validation_function_call" "$live_finalizer")" -eq 1
require_check installed_validate_block_hash \
    test "$(validate_block_hash "$live_finalizer")" = "$new_validate_block_sha256"
require_check payload_hash_unchanged \
    test "$(payload_digest)" = "$expected_payload_sha256"
require_check manifest_hash_unchanged \
    test "$(file_hash "$release/manifest.sha256")" = "$expected_manifest_sha256"
release_snapshot >"$work_directory/release.after"
require_check release_state_unchanged \
    test "$(file_hash "$work_directory/release.after")" = "$release_before_sha256"
require_check request_still_absent test ! -e "$release/.finalize-request"
require_check pending_still_absent test ! -e "$release/.complete.pending"
require_check complete_still_absent test ! -e "$release/.complete"
require_check prior_backup_unchanged \
    test "$(prior_backup_snapshot | sha256sum | awk '{ print $1 }')" = \
    "$prior_backup_before_sha256"
validate_continuity post success
require_check backup_retained test -d "$rollback_directory"
require_check backup_manifest_final_hash \
    test "$(file_hash "$rollback_directory/manifest")" = "$backup_manifest_sha256"

printf '%s_assertion_count=%s\n' "$prefix" "$assertion_count"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_assertion_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_value_old_finalizer_sha256=%s\n' "$prefix" "$old_finalizer_sha256"
printf '%s_value_new_finalizer_sha256=%s\n' "$prefix" "$new_finalizer_sha256"
printf '%s_value_revision=%s\n' "$prefix" "$revision"
printf '%s_value_backup_path=%s\n' "$prefix" "$rollback_directory"
printf '%s_finalizer_invoked=false\n' "$prefix"
printf '%s_release_mutated=false\n' "$prefix"
printf '%s_marker_mutated=false\n' "$prefix"
printf '%s_lsyncd_reconciliation_activation=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_persistent_mutation_scope=stderr_safe_finalizer,rollback_backup\n' \
    "$prefix"

transaction_complete=true
trap - EXIT
rm -rf -- "$work_directory"
printf '%s_node_b_stderr_safe_finalizer_install_complete=true\n' "$prefix"
