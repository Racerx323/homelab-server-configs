#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_17u_a
readonly revision=action17p-node-a-to-node-b-bootstrap
readonly release="/var/lib/caddy-sync/incoming/node-a/$revision"
readonly source_root=/var/lib/caddy-sync/incoming/node-a
readonly finalizer=/usr/local/libexec/finalize-incoming-release-v2.sh
readonly rollback_root=/var/backups/caddy-ha
readonly backup_directory="$rollback_root/action17u-node-b-stderr-safe-finalizer.N9uEhC"
readonly backup_finalizer="$backup_directory/finalizer.before"
readonly backup_manifest="$backup_directory/manifest"
readonly prior_backup_directory="$rollback_root/action17t-node-b-stdout-safe-finalizer.Z6U7Yc"
readonly prior_backup_manifest="$prior_backup_directory/manifest"
readonly lsyncd_config=/etc/lsyncd/caddy.lua
readonly expected_active_release=/etc/caddy/releases/action15-health-follow-redirects
readonly expected_old_finalizer_sha256=e5ec5aab0f57b9ea68c41f122de282c1d156a6747f9f74dd1f22200079c097e4
readonly expected_new_finalizer_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d
readonly expected_capture_function_sha256=70fedbe2fb6457a62f011484f09508fac68e6c19a3cb16ad3e8900547bbf5f21
readonly expected_validate_block_sha256=009c91d9141372792216d705168b356d1ab968936fbc89ddc01c1dc69ee68d82
readonly expected_backup_manifest_sha256=a992c2ff9bdfde76770ddae910dedfc2a8bbdf6ad25de909ec5cbeacda31d70b
readonly expected_prior_manifest_sha256=1c77b0bbab0b9b6cc0cd134c6748553fd686e12e665cb7131552578a1182f15d
readonly expected_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly expected_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8

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
is_sha256() { [[ "$1" =~ ^[0-9a-f]{64}$ ]]; }

payload_digest() {
    (
        cd "$release" || exit
        find . -type f ! -name .complete ! -name .complete.pending \
            ! -name .finalize-request -print0 |
            LC_ALL=C sort -z | xargs -0 -r sha256sum |
            sha256sum | awk '{ print $1 }'
    )
}

capture_function_hash() {
    awk '
        /^validate_caddy_configuration[(][)]/ { capture = 1 }
        capture { print }
        capture && /^}/ { exit }
    ' "$1" | sha256sum | awk '{ print $1 }'
}

validate_block_hash() {
    awk '
        /^[[:space:]]*require_check caddy_configuration_valid/ { capture = 1 }
        capture { print }
        capture && /validate_caddy_configuration "[$]release_path"/ { exit }
    ' "$1" | sha256sum | awk '{ print $1 }'
}

stable_snapshot() {
    local snapshot_path snapshot_unit
    for snapshot_path in "$finalizer" "$release" "$release/manifest.sha256" \
        "$backup_directory" "$backup_finalizer" "$backup_manifest" \
        "$prior_backup_directory" "$prior_backup_manifest" /etc/caddy/current; do
        stat -c '%n|%F|%U:%G:%a:%s:%i' "$snapshot_path" 2>/dev/null ||
            printf '%s|missing\n' "$snapshot_path"
    done
    for snapshot_path in "$finalizer" "$backup_finalizer" "$backup_manifest" \
        "$prior_backup_manifest" "$release/manifest.sha256"; do
        printf '%s=%s\n' "$snapshot_path" "$(file_hash "$snapshot_path" 2>/dev/null || true)"
    done
    printf 'payload=%s\n' "$(payload_digest 2>/dev/null || true)"
    printf 'current=%s\n' "$(readlink -e /etc/caddy/current 2>/dev/null || true)"
    find "$release" -printf '%P|%y|%U:%G:%m:%s:%i\n' 2>/dev/null | LC_ALL=C sort
    for snapshot_unit in caddy.service lighttpd.service lsyncd.service \
        caddy-lsyncd.service caddy-sync-reconcile.service caddy-sync-reconcile.path; do
        printf 'unit=%s|active=%s|enabled=%s\n' "$snapshot_unit" \
            "$(systemctl is-active "$snapshot_unit" 2>/dev/null || true)" \
            "$(systemctl is-enabled "$snapshot_unit" 2>/dev/null || true)"
    done
}

expected_check_labels() {
    printf '%s\n' \
        identity_root working_directory_root hostname_node_b architecture_arm64 \
        finalizer_regular finalizer_not_symlink finalizer_metadata finalizer_hash_exact \
        finalizer_syntax capture_function_single capture_function_hash_exact \
        validation_call_single success_stdout_suppression_single \
        success_stderr_capture_single failure_stderr_replay_single \
        validate_block_hash_exact rollback_root_directory rollback_root_not_symlink \
        rollback_root_metadata backup_count_one backup_directory backup_not_symlink \
        backup_metadata backup_finalizer_regular backup_finalizer_not_symlink \
        backup_finalizer_metadata backup_finalizer_hash_exact backup_manifest_regular \
        backup_manifest_not_symlink backup_manifest_metadata backup_manifest_hash_exact \
        backup_manifest_action_exact backup_manifest_old_hash_exact \
        backup_manifest_new_hash_exact prior_backup_directory prior_backup_not_symlink \
        prior_backup_metadata prior_backup_manifest_regular prior_backup_manifest_hash_exact \
        release_directory release_not_symlink release_metadata request_absent \
        request_not_symlink pending_absent pending_not_symlink complete_absent \
        complete_not_symlink release_directories_locked release_files_locked \
        payload_hash_exact manifest_hash_exact manifest_hashes_valid \
        source_root_only_expected_release current_link_exact current_target_exact \
        caddy_active lighttpd_active lsyncd_inactive lsyncd_masked \
        caddy_lsyncd_inactive caddy_lsyncd_disabled reconcile_path_inactive \
        reconcile_service_inactive lsyncd_configuration_absent \
        lsyncd_configuration_not_symlink transaction_stage_count_zero \
        bundle_stage_count_zero before_state_hash_format after_state_hash_format state_unchanged
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        for self_hash in "$expected_old_finalizer_sha256" "$expected_new_finalizer_sha256" \
            "$expected_capture_function_sha256" "$expected_validate_block_sha256" \
            "$expected_backup_manifest_sha256" "$expected_prior_manifest_sha256" \
            "$expected_payload_sha256" "$expected_manifest_sha256"; do
            is_sha256 "$self_hash" || exit 1
        done
        [[ "$(expected_check_labels | wc -l)" -eq 71 ]] || exit 1
        [[ "$(expected_check_labels | sort -u | wc -l)" -eq 71 ]] || exit 1
        printf '%s_inspector_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --expected-checks)
        [[ $# -eq 1 ]]
        expected_check_labels
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--self-test|--expected-checks]\n' "${0##*/}" >&2
        exit 2
        ;;
esac

work_directory=$(mktemp -d /tmp/caddy-action17u-a.XXXXXX)
readonly work_directory
trap 'rm -rf -- "$work_directory"' EXIT
readonly before_state="$work_directory/before"
readonly after_state="$work_directory/after"

record_command identity_root test "$(id -u)" -eq 0
record_command working_directory_root test "$(pwd -P)" = /
record_command hostname_node_b test "$(hostname)" = j1-svpihole00
record_command architecture_arm64 test "$(dpkg --print-architecture 2>/dev/null || true)" = arm64
record_command finalizer_regular test -f "$finalizer"
record_command finalizer_not_symlink test ! -L "$finalizer"
record_command finalizer_metadata test "$(stat -c '%U:%G:%a' "$finalizer" 2>/dev/null || true)" = root:root:755
record_command finalizer_hash_exact test "$(file_hash "$finalizer" 2>/dev/null || true)" = "$expected_new_finalizer_sha256"
record_command finalizer_syntax bash -n "$finalizer"
record_command capture_function_single test "$(grep -Ec '^validate_caddy_configuration[(][)]' "$finalizer" 2>/dev/null || true)" -eq 1
record_command capture_function_hash_exact test "$(capture_function_hash "$finalizer" 2>/dev/null || true)" = "$expected_capture_function_sha256"
# The dollar expression is required as literal source text.
# shellcheck disable=SC2016
record_command validation_call_single test "$(grep -Fc 'validate_caddy_configuration "$release_path"' "$finalizer" 2>/dev/null || true)" -eq 1
# shellcheck disable=SC2016
record_command success_stdout_suppression_single test "$(grep -Fc -- '--adapter caddyfile >/dev/null 2>"$validation_error"' "$finalizer" 2>/dev/null || true)" -eq 1
# shellcheck disable=SC2016
record_command success_stderr_capture_single test "$(grep -Fc '2>"$validation_error"' "$finalizer" 2>/dev/null || true)" -eq 1
# shellcheck disable=SC2016
record_command failure_stderr_replay_single test "$(grep -Fc 'cat -- "$validation_error" >&2 || :' "$finalizer" 2>/dev/null || true)" -eq 1
record_command validate_block_hash_exact test "$(validate_block_hash "$finalizer" 2>/dev/null || true)" = "$expected_validate_block_sha256"

record_command rollback_root_directory test -d "$rollback_root"
record_command rollback_root_not_symlink test ! -L "$rollback_root"
record_command rollback_root_metadata test "$(stat -c '%U:%G:%a' "$rollback_root" 2>/dev/null || true)" = root:root:700
record_command backup_count_one test "$(find "$rollback_root" -mindepth 1 -maxdepth 1 -type d -name 'action17u-node-b-stderr-safe-finalizer.*' -print 2>/dev/null | wc -l)" -eq 1
record_command backup_directory test -d "$backup_directory"
record_command backup_not_symlink test ! -L "$backup_directory"
record_command backup_metadata test "$(stat -c '%U:%G:%a' "$backup_directory" 2>/dev/null || true)" = root:root:700
record_command backup_finalizer_regular test -f "$backup_finalizer"
record_command backup_finalizer_not_symlink test ! -L "$backup_finalizer"
record_command backup_finalizer_metadata test "$(stat -c '%U:%G:%a' "$backup_finalizer" 2>/dev/null || true)" = root:root:600
record_command backup_finalizer_hash_exact test "$(file_hash "$backup_finalizer" 2>/dev/null || true)" = "$expected_old_finalizer_sha256"
record_command backup_manifest_regular test -f "$backup_manifest"
record_command backup_manifest_not_symlink test ! -L "$backup_manifest"
record_command backup_manifest_metadata test "$(stat -c '%U:%G:%a' "$backup_manifest" 2>/dev/null || true)" = root:root:600
record_command backup_manifest_hash_exact test "$(file_hash "$backup_manifest" 2>/dev/null || true)" = "$expected_backup_manifest_sha256"
record_command backup_manifest_action_exact grep -Fxq action=17u "$backup_manifest"
record_command backup_manifest_old_hash_exact grep -Fxq "old_finalizer_sha256=$expected_old_finalizer_sha256" "$backup_manifest"
record_command backup_manifest_new_hash_exact grep -Fxq "new_finalizer_sha256=$expected_new_finalizer_sha256" "$backup_manifest"
record_command prior_backup_directory test -d "$prior_backup_directory"
record_command prior_backup_not_symlink test ! -L "$prior_backup_directory"
record_command prior_backup_metadata test "$(stat -c '%U:%G:%a' "$prior_backup_directory" 2>/dev/null || true)" = root:root:700
record_command prior_backup_manifest_regular test -f "$prior_backup_manifest"
record_command prior_backup_manifest_hash_exact test "$(file_hash "$prior_backup_manifest" 2>/dev/null || true)" = "$expected_prior_manifest_sha256"

record_command release_directory test -d "$release"
record_command release_not_symlink test ! -L "$release"
record_command release_metadata test "$(stat -c '%U:%G:%a' "$release" 2>/dev/null || true)" = caddy-sync:caddy-sync:550
record_command request_absent test ! -e "$release/.finalize-request"
record_command request_not_symlink test ! -L "$release/.finalize-request"
record_command pending_absent test ! -e "$release/.complete.pending"
record_command pending_not_symlink test ! -L "$release/.complete.pending"
record_command complete_absent test ! -e "$release/.complete"
record_command complete_not_symlink test ! -L "$release/.complete"
record_command release_directories_locked test -z "$(find "$release" -type d ! -perm 0550 -print -quit 2>/dev/null)"
record_command release_files_locked test -z "$(find "$release" -type f ! -perm 0440 -print -quit 2>/dev/null)"
record_command payload_hash_exact test "$(payload_digest 2>/dev/null || true)" = "$expected_payload_sha256"
record_command manifest_hash_exact test "$(file_hash "$release/manifest.sha256" 2>/dev/null || true)" = "$expected_manifest_sha256"
# The positional parameter is intentionally expanded by the child shell.
# shellcheck disable=SC2016
record_command manifest_hashes_valid bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' _ "$release"
record_command source_root_only_expected_release test "$(find "$source_root" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | LC_ALL=C sort)" = "$revision"
record_command current_link_exact test "$(readlink /etc/caddy/current 2>/dev/null || true)" = "$expected_active_release"
record_command current_target_exact test "$(readlink -e /etc/caddy/current 2>/dev/null || true)" = "$expected_active_release"
record_command caddy_active test "$(systemctl is-active caddy.service 2>/dev/null || true)" = active
record_command lighttpd_active test "$(systemctl is-active lighttpd.service 2>/dev/null || true)" = active
record_command lsyncd_inactive test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
record_command lsyncd_masked test "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" = masked
record_command caddy_lsyncd_inactive test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = inactive
record_command caddy_lsyncd_disabled test "$(systemctl is-enabled caddy-lsyncd.service 2>/dev/null || true)" = disabled
record_command reconcile_path_inactive test "$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)" = inactive
record_command reconcile_service_inactive test "$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)" = inactive
record_command lsyncd_configuration_absent test ! -e "$lsyncd_config"
record_command lsyncd_configuration_not_symlink test ! -L "$lsyncd_config"
record_command transaction_stage_count_zero test "$(find /run -mindepth 1 -maxdepth 1 -type d -name 'caddy-action17u-node-b.*' -print 2>/dev/null | wc -l)" -eq 0
record_command bundle_stage_count_zero test "$(find /run -mindepth 1 -maxdepth 1 -type d -name 'caddy-action17u-stage.*' -print 2>/dev/null | wc -l)" -eq 0

stable_snapshot >"$before_state"
before_state_sha256=$(file_hash "$before_state")
readonly before_state_sha256
record_command before_state_hash_format is_sha256 "$before_state_sha256"
stable_snapshot >"$after_state"
after_state_sha256=$(file_hash "$after_state")
readonly after_state_sha256
record_command after_state_hash_format is_sha256 "$after_state_sha256"
record_command state_unchanged test "$after_state_sha256" = "$before_state_sha256"

printf '%s_assertion_count=%s\n' "$prefix" "$assertion_count"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_assertion_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_value_finalizer_sha256=%s\n' "$prefix" "$expected_new_finalizer_sha256"
printf '%s_value_backup_path=%s\n' "$prefix" "$backup_directory"
printf '%s_value_expected_backup_manifest_sha256=%s\n' "$prefix" "$expected_backup_manifest_sha256"
printf '%s_value_observed_backup_manifest_sha256=%s\n' "$prefix" "$(file_hash "$backup_manifest" 2>/dev/null || true)"
printf '%s_value_payload_sha256=%s\n' "$prefix" "$expected_payload_sha256"
printf '%s_value_manifest_sha256=%s\n' "$prefix" "$expected_manifest_sha256"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$before_state_sha256"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$after_state_sha256"
printf '%s_finalizer_invoked=false\n' "$prefix"
printf '%s_release_mutated=false\n' "$prefix"
printf '%s_marker_mutated=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_lsyncd_reconciliation_activation=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"

[[ "$failed_assertion_count" -eq 0 ]] || exit 1
printf '%s_node_b_read_only_postinstall_complete=true\n' "$prefix"
