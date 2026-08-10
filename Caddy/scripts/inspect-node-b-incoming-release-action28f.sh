#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28f_node_b
readonly incoming_root=/var/lib/caddy-sync/incoming/node-a
readonly historical_release=$incoming_root/action17p-node-a-to-node-b-bootstrap
readonly historical_release_manifest_sha256=81afa957c65b4f8a3f539b0018ebd700b0c926812f1b1e18b2ea7ade0be0e1b3
readonly historical_payload_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly candidate_revision=20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63
readonly candidate_parent=action16ar-retry-node-a-default-deny
readonly candidate_release=$incoming_root/$candidate_revision
readonly candidate_release_manifest_sha256=c72b5bc5a6586ac3be098c0c5ca2fc3dc01a09c2afe4dcf90ed4bdbda6d166de
readonly candidate_payload_manifest_sha256=fdc6ed955f14226ac3e1777eca37507cc8ab6ca16add3135dece9d6964e27568
readonly receiver=/usr/local/libexec/caddy-sync-release-receiver-v2
readonly finalizer=/usr/local/libexec/finalize-incoming-release-v2.sh
readonly authorized_keys=/var/lib/caddy-sync/.ssh/authorized_keys
readonly receiver_sha256=a94c7a45531787055da622a0dac180f98e52bd0ba967424a4cf22a4852539d9e
readonly finalizer_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d
readonly authorized_keys_sha256=54eeda8ae3c94e878a38d76ccade91642ba9ab193b5f416ea1bf308a500a1bc1
checks_total=0
checks_passed=0
checks_failed=0
first_failure=none

record_result() {
    local result_label=$1
    local result_value=$2
    checks_total=$((checks_total + 1))
    if [[ "$result_value" == true ]]; then
        printf '%s_check_%s=true\n' "$prefix" "$result_label"
        checks_passed=$((checks_passed + 1))
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$result_label" >&2
    checks_failed=$((checks_failed + 1))
    [[ "$first_failure" != none ]] || first_failure=$result_label
    return 0
}

record_command() {
    local command_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        record_result "$command_label" true
    else
        record_result "$command_label" false
    fi
}

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

manifest_hashes_valid() {
    local action28_manifest_release=$1

    (
        cd "$action28_manifest_release" || exit
        sha256sum --strict --check manifest.sha256 >/dev/null
    )
}

expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_node_b caddy_active \
        lsyncd_inactive caddy_lsyncd_inactive reconcile_path_inactive \
        reconcile_service_inactive receiver_regular receiver_not_symlink \
        receiver_metadata receiver_hash_exact receiver_syntax finalizer_regular \
        finalizer_not_symlink finalizer_metadata finalizer_hash_exact finalizer_syntax \
        authorized_keys_regular authorized_keys_not_symlink authorized_keys_metadata \
        authorized_keys_hash_exact authorization_source_role_node_a
    if [[ "${1:-}" == preflight ]]; then
        printf '%s\n' incoming_root_directory incoming_root_not_symlink \
            historical_release_directory historical_release_not_symlink \
            historical_request_regular historical_request_empty historical_complete_regular \
            historical_complete_empty historical_pending_absent \
            historical_release_manifest_hash_exact historical_payload_manifest_hash_exact \
            historical_manifest_hashes_valid historical_directories_locked historical_files_locked \
            incoming_child_count_preflight candidate_absent
    else
        printf '%s\n' incoming_root_directory incoming_root_not_symlink \
            release_directory release_not_symlink \
            release_request_regular release_request_empty release_complete_regular \
            release_complete_not_symlink release_complete_empty release_pending_absent \
            release_revision_exact release_parent_exact release_source_node_a \
            release_manifest_hash_exact payload_manifest_hash_exact manifest_hashes_valid \
            release_symlinks_absent release_special_files_absent release_hardlinks_absent \
            release_directories_locked release_files_locked historical_release_directory \
            historical_release_not_symlink historical_request_regular historical_request_empty \
            historical_complete_regular historical_complete_empty historical_pending_absent \
            historical_release_manifest_hash_exact historical_payload_manifest_hash_exact \
            historical_manifest_hashes_valid historical_directories_locked historical_files_locked \
            incoming_child_count_complete
    fi
}

record_historical_continuity() {
    record_command historical_release_directory test -d "$historical_release"
    record_command historical_release_not_symlink test ! -L "$historical_release"
    record_command historical_request_regular test -f "$historical_release/.finalize-request"
    record_command historical_request_empty test ! -s "$historical_release/.finalize-request"
    record_command historical_complete_regular test -f "$historical_release/.complete"
    record_command historical_complete_empty test ! -s "$historical_release/.complete"
    record_command historical_pending_absent test ! -e "$historical_release/.complete.pending"
    record_command historical_release_manifest_hash_exact test \
        "$(file_hash "$historical_release/release-manifest.json" 2>/dev/null || true)" = \
        "$historical_release_manifest_sha256"
    record_command historical_payload_manifest_hash_exact test \
        "$(file_hash "$historical_release/manifest.sha256" 2>/dev/null || true)" = \
        "$historical_payload_manifest_sha256"
    record_command historical_manifest_hashes_valid \
        manifest_hashes_valid "$historical_release"
    record_command historical_directories_locked test \
        -z "$(find "$historical_release" -type d ! -perm 0550 -print -quit)"
    record_command historical_files_locked test \
        -z "$(find "$historical_release" -type f ! -perm 0440 -print -quit)"
}

record_receiver_continuity() {
    record_command receiver_regular test -f "$receiver"
    record_command receiver_not_symlink test ! -L "$receiver"
    record_command receiver_metadata test \
        "$(stat -c '%U:%G:%a' "$receiver" 2>/dev/null || true)" = root:root:755
    record_command receiver_hash_exact test \
        "$(file_hash "$receiver" 2>/dev/null || true)" = "$receiver_sha256"
    record_command receiver_syntax /bin/bash -n "$receiver"
    record_command finalizer_regular test -f "$finalizer"
    record_command finalizer_not_symlink test ! -L "$finalizer"
    record_command finalizer_metadata test \
        "$(stat -c '%U:%G:%a' "$finalizer" 2>/dev/null || true)" = root:root:755
    record_command finalizer_hash_exact test \
        "$(file_hash "$finalizer" 2>/dev/null || true)" = "$finalizer_sha256"
    record_command finalizer_syntax /bin/bash -n "$finalizer"
    record_command authorized_keys_regular test -f "$authorized_keys"
    record_command authorized_keys_not_symlink test ! -L "$authorized_keys"
    record_command authorized_keys_metadata test \
        "$(stat -c '%U:%G:%a' "$authorized_keys" 2>/dev/null || true)" = \
        caddy-sync:caddy-sync:600
    record_command authorized_keys_hash_exact test \
        "$(file_hash "$authorized_keys" 2>/dev/null || true)" = \
        "$authorized_keys_sha256"
    record_command authorization_source_role_node_a grep -Fq \
        'caddy-sync-release-receiver-v2 --source-role node-a' "$authorized_keys"
}

if [[ "${1:-}" == --expected-checks && $# -eq 2 ]]; then
    [[ "$2" =~ ^(preflight|complete)$ ]] || exit 64
    expected_checks "$2"
    exit 0
fi
if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$incoming_root" == /var/lib/caddy-sync/incoming/node-a ]]
    [[ "$candidate_release" == "$incoming_root/$candidate_revision" ]]
    printf '%s_self_test_complete=true\n' "$prefix"
    exit 0
fi
if [[ $# -lt 1 || ! "$1" =~ ^--(preflight|complete)$ ]]; then
    printf 'Usage: %s --preflight | --complete REVISION PARENT MANIFEST_SHA256\n' \
        "${0##*/}" >&2
    exit 64
fi
readonly phase=${1#--}
revision=unavailable
parent_revision=unavailable
manifest_sha256=unavailable
if [[ "$phase" == complete ]]; then
    [[ $# -eq 4 ]] || exit 64
    revision=$2
    parent_revision=$3
    manifest_sha256=$4
    [[ "$revision" == "$candidate_revision" ]] || exit 64
    [[ "$parent_revision" == "$candidate_parent" ]] || exit 64
    [[ "$manifest_sha256" == "$candidate_payload_manifest_sha256" ]] || exit 64
elif [[ $# -ne 1 ]]; then
    exit 64
fi

record_command identity_root test "$(id -u)" -eq 0
record_command working_directory_root test "$(pwd -P)" = /
record_command hostname_node_b test "$(hostname)" = j1-svpihole00
record_command caddy_active test \
    "$(systemctl is-active caddy.service 2>/dev/null || true)" = active
record_command lsyncd_inactive test \
    "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
record_command caddy_lsyncd_inactive test \
    "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = inactive
record_command reconcile_path_inactive test \
    "$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)" = inactive
record_command reconcile_service_inactive test \
    "$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)" = inactive
record_receiver_continuity

if [[ "$phase" == preflight ]]; then
    record_command incoming_root_directory test -d "$incoming_root"
    record_command incoming_root_not_symlink test ! -L "$incoming_root"
    record_historical_continuity
    record_command incoming_child_count_preflight test \
        "$(find "$incoming_root" -mindepth 1 -maxdepth 1 -print | wc -l)" -eq 1
    record_command candidate_absent test ! -e "$candidate_release"
else
    release_dir="$incoming_root/$revision"
    record_command incoming_root_directory test -d "$incoming_root"
    record_command incoming_root_not_symlink test ! -L "$incoming_root"
    record_command release_directory test -d "$release_dir"
    record_command release_not_symlink test ! -L "$release_dir"
    record_command release_request_regular test -f "$release_dir/.finalize-request"
    record_command release_request_empty test ! -s "$release_dir/.finalize-request"
    record_command release_complete_regular test -f "$release_dir/.complete"
    record_command release_complete_not_symlink test ! -L "$release_dir/.complete"
    record_command release_complete_empty test ! -s "$release_dir/.complete"
    record_command release_pending_absent test ! -e "$release_dir/.complete.pending"
    record_command release_revision_exact test \
        "$(jq -r '.revision // empty' "$release_dir/release-manifest.json")" = "$revision"
    record_command release_parent_exact test \
        "$(jq -r '.parent_revision // empty' "$release_dir/release-manifest.json")" = \
        "$parent_revision"
    record_command release_source_node_a test \
        "$(jq -r '.source_node // empty' "$release_dir/release-manifest.json")" = node-a
    record_command release_manifest_hash_exact test \
        "$(file_hash "$release_dir/release-manifest.json")" = \
        "$candidate_release_manifest_sha256"
    record_command payload_manifest_hash_exact test \
        "$(file_hash "$release_dir/manifest.sha256")" = "$manifest_sha256"
    # The positional parameter is intentionally expanded by the child shell.
    # shellcheck disable=SC2016
    record_command manifest_hashes_valid /bin/bash -c \
        'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$release_dir"
    record_command release_symlinks_absent test \
        -z "$(find "$release_dir" -type l -print -quit)"
    record_command release_special_files_absent test \
        -z "$(find "$release_dir" ! -type d ! -type f -print -quit)"
    record_command release_hardlinks_absent test \
        -z "$(find "$release_dir" -type f -links +1 -print -quit)"
    record_command release_directories_locked test \
        -z "$(find "$release_dir" -type d ! -perm 0550 -print -quit)"
    record_command release_files_locked test \
        -z "$(find "$release_dir" -type f ! -perm 0440 -print -quit)"
    record_historical_continuity
    record_command incoming_child_count_complete test \
        "$(find "$incoming_root" -mindepth 1 -maxdepth 1 -print | wc -l)" -eq 2
fi

printf '%s_value_phase=%s\n' "$prefix" "$phase"
printf '%s_value_revision=%s\n' "$prefix" "$revision"
printf '%s_value_parent_revision=%s\n' "$prefix" "$parent_revision"
printf '%s_value_manifest_sha256=%s\n' "$prefix" "$manifest_sha256"
printf '%s_checks_total=%s\n' "$prefix" "$checks_total"
printf '%s_checks_passed=%s\n' "$prefix" "$checks_passed"
printf '%s_checks_failed=%s\n' "$prefix" "$checks_failed"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_inspector_finalizer_invoked=false\n' "$prefix"
printf '%s_lsyncd_enabled=false\n' "$prefix"
printf '%s_reconciliation_executed=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
if [[ "$checks_failed" -ne 0 ]]; then
    printf '%s_acceptance=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_acceptance=true\n' "$prefix"
