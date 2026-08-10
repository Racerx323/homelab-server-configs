#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28g_a_residue
readonly revision=20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63
readonly parent_revision=action16ar-retry-node-a-default-deny
readonly release_manifest_sha256=c72b5bc5a6586ac3be098c0c5ca2fc3dc01a09c2afe4dcf90ed4bdbda6d166de
readonly payload_manifest_sha256=fdc6ed955f14226ac3e1777eca37507cc8ab6ca16add3135dece9d6964e27568

role=
expected_hostname=
release_root=
candidate=
snapshot_before=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action28g_a_residue_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28g_a_residue_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28g_a_residue_label" >&2
    printf '%s_first_failure=%s\n' "$prefix" "$action28g_a_residue_label" >&2
    return 1
}
expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact release_root_directory \
        release_root_not_symlink release_root_entry_count_exact hidden_root_entries_absent \
        candidate_directory candidate_not_symlink revision_exact parent_revision_exact \
        release_manifest_regular release_manifest_not_symlink release_manifest_hash_exact \
        payload_manifest_regular payload_manifest_not_symlink payload_manifest_hash_exact \
        finalize_request_regular finalize_request_not_symlink finalize_request_empty \
        complete_marker_absent_node_a complete_marker_not_symlink_node_a complete_marker_regular_node_b \
        complete_marker_not_symlink_node_b complete_marker_empty_node_b \
        pending_marker_absent pending_marker_not_symlink action28f_capture_residue_absent \
        action28f_expected_residue_absent action28f_observed_residue_absent \
        finalizer_expected_residue_absent finalizer_observed_residue_absent snapshot_stable
}
configure_role() {
    case "$role" in
        node-a)
            expected_hostname=j1-svpihole0
            release_root=/var/lib/caddy-sync/outbound
            ;;
        node-b)
            expected_hostname=j1-svpihole00
            release_root=/var/lib/caddy-sync/incoming/node-a
            ;;
        *) return 1 ;;
    esac
    candidate=$release_root/$revision
}
path_count() {
    local action28g_a_residue_pattern=$1

    find /tmp -mindepth 1 -maxdepth 1 -name "$action28g_a_residue_pattern" -print | wc -l
}
snapshot() {
    {
        find "$release_root" -mindepth 1 -maxdepth 2 \
            -printf 'release=%P|%y|%u:%g:%m:%s\n' | LC_ALL=C sort
        printf 'capture=%s\n' "$(path_count 'caddy-action28f-node-a.*')"
        printf 'expected=%s\n' "$(path_count 'action28f-expected.*')"
        printf 'observed=%s\n' "$(path_count 'action28f-observed.*')"
        printf 'finalizer_expected=%s\n' "$(path_count 'caddy-finalize-expected.*')"
        printf 'finalizer_observed=%s\n' "$(path_count 'caddy-finalize-observed.*')"
    } | sha256sum | awk '{ print $1 }'
}
node_a_check() { [[ "$role" != node-a ]] || "$@"; }
node_b_check() { [[ "$role" != node-b ]] || "$@"; }

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]]
        expected_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$(expected_checks | wc -l)" -eq "$(expected_checks | LC_ALL=C sort -u | wc -l)" ]]
        [[ "$revision" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
        [[ ${#release_manifest_sha256} -eq 64 ]]
        [[ ${#payload_manifest_sha256} -eq 64 ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    node-a | node-b)
        [[ $# -eq 1 ]]
        role=$1
        ;;
    *) exit 64 ;;
esac

configure_role
readonly role expected_hostname release_root candidate

record_check identity_root test "$(id -u)" -eq 0
record_check working_directory_root test "$PWD" = /
record_check hostname_exact test "$(hostname)" = "$expected_hostname"
record_check release_root_directory test -d "$release_root"
record_check release_root_not_symlink test ! -L "$release_root"
record_check release_root_entry_count_exact test \
    "$(find "$release_root" -mindepth 1 -maxdepth 1 -print | wc -l)" -eq 2
record_check hidden_root_entries_absent test \
    "$(find "$release_root" -mindepth 1 -maxdepth 1 -name '.*' -print | wc -l)" -eq 0
record_check candidate_directory test -d "$candidate"
record_check candidate_not_symlink test ! -L "$candidate"

snapshot_before=$(snapshot)
readonly snapshot_before

record_check revision_exact test \
    "$(jq -r '.revision // empty' "$candidate/release-manifest.json")" = "$revision"
record_check parent_revision_exact test \
    "$(jq -r '.parent_revision // empty' "$candidate/release-manifest.json")" = "$parent_revision"
record_check release_manifest_regular test -f "$candidate/release-manifest.json"
record_check release_manifest_not_symlink test ! -L "$candidate/release-manifest.json"
record_check release_manifest_hash_exact test \
    "$(file_hash "$candidate/release-manifest.json")" = "$release_manifest_sha256"
record_check payload_manifest_regular test -f "$candidate/manifest.sha256"
record_check payload_manifest_not_symlink test ! -L "$candidate/manifest.sha256"
record_check payload_manifest_hash_exact test \
    "$(file_hash "$candidate/manifest.sha256")" = "$payload_manifest_sha256"
record_check finalize_request_regular test -f "$candidate/.finalize-request"
record_check finalize_request_not_symlink test ! -L "$candidate/.finalize-request"
record_check finalize_request_empty test ! -s "$candidate/.finalize-request"
record_check complete_marker_absent_node_a node_a_check test ! -e "$candidate/.complete"
record_check complete_marker_not_symlink_node_a node_a_check test ! -L "$candidate/.complete"
record_check complete_marker_regular_node_b node_b_check test -f "$candidate/.complete"
record_check complete_marker_not_symlink_node_b node_b_check test ! -L "$candidate/.complete"
record_check complete_marker_empty_node_b node_b_check test ! -s "$candidate/.complete"
record_check pending_marker_absent test ! -e "$candidate/.complete.pending"
record_check pending_marker_not_symlink test ! -L "$candidate/.complete.pending"
record_check action28f_capture_residue_absent test \
    "$(path_count 'caddy-action28f-node-a.*')" -eq 0
record_check action28f_expected_residue_absent test \
    "$(path_count 'action28f-expected.*')" -eq 0
record_check action28f_observed_residue_absent test \
    "$(path_count 'action28f-observed.*')" -eq 0
record_check finalizer_expected_residue_absent test \
    "$(path_count 'caddy-finalize-expected.*')" -eq 0
record_check finalizer_observed_residue_absent test \
    "$(path_count 'caddy-finalize-observed.*')" -eq 0
record_check snapshot_stable test "$(snapshot)" = "$snapshot_before"

printf '%s_value_role=%s\n' "$prefix" "$role"
printf '%s_value_revision=%s\n' "$prefix" "$revision"
printf '%s_value_parent_revision=%s\n' "$prefix" "$parent_revision"
printf '%s_value_release_manifest_sha256=%s\n' "$prefix" "$release_manifest_sha256"
printf '%s_value_payload_manifest_sha256=%s\n' "$prefix" "$payload_manifest_sha256"
printf '%s_value_snapshot_sha256=%s\n' "$prefix" "$snapshot_before"
printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
printf '%s_failed_check_count=0\n' "$prefix"
printf '%s_first_failure=none\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_cleanup_executed=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
