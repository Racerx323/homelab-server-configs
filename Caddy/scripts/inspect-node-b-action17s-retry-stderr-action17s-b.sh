#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_17s_b
readonly revision=action17p-node-a-to-node-b-bootstrap
readonly source_root=/var/lib/caddy-sync/incoming/node-a
readonly release="$source_root/$revision"
readonly finalizer=/usr/local/libexec/finalize-incoming-release-v2.sh
readonly expected_finalizer_sha256=e5ec5aab0f57b9ea68c41f122de282c1d156a6747f9f74dd1f22200079c097e4
readonly expected_validate_block_sha256=be85e806dfefe0781806e8f95f00c2e1e1d4ef9393aca24efa2a382bad99ccde
readonly expected_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly expected_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly expected_active_release=/etc/caddy/releases/action15-health-follow-redirects
readonly expected_failed_stderr_bytes=724
readonly expected_failed_stderr_lines=6
readonly expected_failed_stderr_sha256=dd0e90054410c6fd8e6c9812dd9162eaead43bc3b2d9c67cbe4854b589d351c2

assertion_count=0
failed_assertion_count=0
first_failure=none

record_assertion() {
    local assertion_label=$1
    local assertion_value=$2

    assertion_count=$((assertion_count + 1))
    printf '%s_assertion_%s=%s\n' "$prefix" "$assertion_label" "$assertion_value"
    if [[ "$assertion_value" != true ]]; then
        failed_assertion_count=$((failed_assertion_count + 1))
        [[ "$first_failure" != none ]] || first_failure=$assertion_label
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

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

payload_digest() {
    (
        cd "$release"
        find . -type f ! -name .complete ! -name .complete.pending \
            ! -name .finalize-request -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r sha256sum |
            sha256sum | awk '{ print $1 }'
    )
}

release_snapshot() {
    (
        cd "$release"
        find . -printf '%P|%y|%U:%G:%m:%s\n' | LC_ALL=C sort
        find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
    )
}

validate_block() {
    awk '
        /^[[:space:]]*require_check caddy_configuration_valid/ { capture = 1 }
        capture { print }
        capture && /--adapter caddyfile/ { exit }
    ' "$finalizer"
}

expected_assertion_labels() {
    printf '%s\n' \
        identity_root working_directory_root hostname_node_b architecture_arm64 \
        finalizer_regular finalizer_not_symlink finalizer_metadata \
        finalizer_hash_exact finalizer_syntax validate_block_single \
        validate_block_line_count_exact validate_block_hash_exact \
        validate_invocation_single validate_stdout_redirect_exact \
        validate_old_unredirected_absent validate_stderr_redirect_absent \
        release_directory release_not_symlink release_metadata request_absent \
        request_not_symlink pending_absent pending_not_symlink complete_absent \
        complete_not_symlink release_directories_locked release_files_locked \
        payload_hash_exact manifest_hash_exact manifest_hashes_valid \
        source_root_only_expected_release retry_backup_count_zero \
        retry_work_directory_count_zero current_link_exact current_target_exact \
        lsyncd_configuration_absent caddy_active lighttpd_active lsyncd_inactive \
        lsyncd_masked caddy_lsyncd_inactive reconcile_path_inactive \
        reconcile_service_inactive release_state_unchanged current_link_unchanged \
        current_target_unchanged caddy_active_unchanged lighttpd_active_unchanged \
        lsyncd_active_state_unchanged lsyncd_unit_file_state_unchanged \
        caddy_lsyncd_active_state_unchanged reconcile_path_active_state_unchanged \
        reconcile_service_active_state_unchanged
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$expected_finalizer_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$expected_validate_block_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$expected_failed_stderr_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$(expected_assertion_labels | wc -l)" -gt 50 ]]
    [[ "$(expected_assertion_labels | LC_ALL=C sort -u | wc -l)" = "$(expected_assertion_labels | wc -l)" ]]
    printf '%s_inspector_self_test_complete=true\n' "$prefix"
    exit 0
elif [[ "${1:-}" == --expected-checks && $# -eq 1 ]]; then
    expected_assertion_labels
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--expected-checks]\n' "${0##*/}" >&2
    exit 2
fi

work_directory=$(mktemp -d /tmp/caddy-action17s-b-node-b.XXXXXX)
readonly work_directory
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT
readonly before_release="$work_directory/release.before"
readonly after_release="$work_directory/release.after"
readonly validate_source="$work_directory/caddy-validate.source"

record_command identity_root test "$(id -u)" -eq 0
record_command working_directory_root test "$(pwd -P)" = /
record_command hostname_node_b test "$(hostname)" = j1-svpihole00
record_command architecture_arm64 test "$(dpkg --print-architecture)" = arm64
record_command finalizer_regular test -f "$finalizer"
record_command finalizer_not_symlink test ! -L "$finalizer"
record_command finalizer_metadata test "$(stat -c '%U:%G:%a' "$finalizer")" = root:root:755
record_command finalizer_hash_exact test "$(file_hash "$finalizer")" = "$expected_finalizer_sha256"
record_command finalizer_syntax bash -n "$finalizer"
validate_block >"$validate_source"
record_command validate_block_single test "$(grep -Fc 'require_check caddy_configuration_valid' "$finalizer")" -eq 1
record_command validate_block_line_count_exact test "$(wc -l <"$validate_source")" -eq 7
record_command validate_block_hash_exact test "$(file_hash "$validate_source")" = "$expected_validate_block_sha256"
record_command validate_invocation_single test "$(grep -Ec '^[[:space:]]*caddy validate ' "$finalizer")" -eq 1
record_command validate_stdout_redirect_exact test "$(grep -Fxc '        --adapter caddyfile >/dev/null' "$finalizer")" -eq 1
record_command validate_old_unredirected_absent test "$(grep -Fxc '        --adapter caddyfile' "$finalizer")" -eq 0
record_command validate_stderr_redirect_absent test "$(grep -Ec '(^|[[:space:]])2>' "$validate_source")" -eq 0
record_command release_directory test -d "$release"
record_command release_not_symlink test ! -L "$release"
record_command release_metadata test "$(stat -c '%U:%G:%a' "$release")" = caddy-sync:caddy-sync:550
record_command request_absent test ! -e "$release/.finalize-request"
record_command request_not_symlink test ! -L "$release/.finalize-request"
record_command pending_absent test ! -e "$release/.complete.pending"
record_command pending_not_symlink test ! -L "$release/.complete.pending"
record_command complete_absent test ! -e "$release/.complete"
record_command complete_not_symlink test ! -L "$release/.complete"
record_command release_directories_locked test -z "$(find "$release" -type d ! -perm 0550 -print -quit)"
record_command release_files_locked test -z "$(find "$release" -type f ! -perm 0440 -print -quit)"
record_command payload_hash_exact test "$(payload_digest)" = "$expected_payload_sha256"
record_command manifest_hash_exact test "$(file_hash "$release/manifest.sha256")" = "$expected_manifest_sha256"
# shellcheck disable=SC2016
record_command manifest_hashes_valid bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' _ "$release"
record_command source_root_only_expected_release test "$(find "$source_root" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)" = "$revision"
record_command retry_backup_count_zero test "$(find /var/backups/caddy-ha -mindepth 1 -maxdepth 1 -type d -name 'action17s-retry-node-b-marker-migration.*' -print | wc -l)" -eq 0
record_command retry_work_directory_count_zero test "$(find /run -mindepth 1 -maxdepth 1 -type d -name 'caddy-action17s-retry-node-b.*' -print | wc -l)" -eq 0
record_command current_link_exact test "$(readlink /etc/caddy/current)" = "$expected_active_release"
record_command current_target_exact test "$(readlink -e /etc/caddy/current)" = "$expected_active_release"
record_command lsyncd_configuration_absent test ! -e /etc/lsyncd/caddy.lua
record_command caddy_active test "$(systemctl is-active caddy.service)" = active
record_command lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
record_command lsyncd_inactive test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
record_command lsyncd_masked test "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" = masked
record_command caddy_lsyncd_inactive test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = inactive
record_command reconcile_path_inactive test "$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)" = inactive
record_command reconcile_service_inactive test "$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)" = inactive

release_snapshot >"$before_release"
before_release_sha256=$(file_hash "$before_release")
before_current_link=$(readlink /etc/caddy/current)
before_current_target=$(readlink -e /etc/caddy/current)
before_caddy_active=$(systemctl is-active caddy.service)
before_lighttpd_active=$(systemctl is-active lighttpd.service)
before_lsyncd_active=$(systemctl is-active lsyncd.service 2>/dev/null || true)
before_lsyncd_enabled=$(systemctl is-enabled lsyncd.service 2>/dev/null || true)
before_caddy_lsyncd_active=$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)
before_reconcile_path_active=$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)
before_reconcile_service_active=$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)
readonly before_release_sha256 before_current_link before_current_target
readonly before_caddy_active before_lighttpd_active before_lsyncd_active before_lsyncd_enabled
readonly before_caddy_lsyncd_active before_reconcile_path_active before_reconcile_service_active
release_snapshot >"$after_release"
record_command release_state_unchanged test "$(file_hash "$after_release")" = "$before_release_sha256"
record_command current_link_unchanged test "$(readlink /etc/caddy/current)" = "$before_current_link"
record_command current_target_unchanged test "$(readlink -e /etc/caddy/current)" = "$before_current_target"
record_command caddy_active_unchanged test "$(systemctl is-active caddy.service)" = "$before_caddy_active"
record_command lighttpd_active_unchanged test "$(systemctl is-active lighttpd.service)" = "$before_lighttpd_active"
record_command lsyncd_active_state_unchanged test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = "$before_lsyncd_active"
record_command lsyncd_unit_file_state_unchanged test "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" = "$before_lsyncd_enabled"
record_command caddy_lsyncd_active_state_unchanged test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = "$before_caddy_lsyncd_active"
record_command reconcile_path_active_state_unchanged test "$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)" = "$before_reconcile_path_active"
record_command reconcile_service_active_state_unchanged test "$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)" = "$before_reconcile_service_active"

printf '%s_assertion_count=%s\n' "$prefix" "$assertion_count"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_assertion_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_value_finalizer_sha256=%s\n' "$prefix" "$expected_finalizer_sha256"
printf '%s_value_validate_block_sha256=%s\n' "$prefix" "$expected_validate_block_sha256"
printf '%s_value_stderr_source_classification=stdout_suppressed_stderr_unsuppressed_caddy_validate_path\n' "$prefix"
printf '%s_failed_action_stderr_bytes=%s\n' "$prefix" "$expected_failed_stderr_bytes"
printf '%s_failed_action_stderr_lines=%s\n' "$prefix" "$expected_failed_stderr_lines"
printf '%s_failed_action_stderr_sha256=%s\n' "$prefix" "$expected_failed_stderr_sha256"
printf '%s_failed_action_stderr_classification=bounded_safe_unemitted\n' "$prefix"
printf '%s_failed_action_stderr_content_recoverable=false\n' "$prefix"
printf '%s_finalizer_invoked=false\n' "$prefix"
printf '%s_marker_mutations=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
if [[ "$failed_assertion_count" -ne 0 ]]; then exit 1; fi
printf '%s_node_b_read_only_inspection_complete=true\n' "$prefix"
