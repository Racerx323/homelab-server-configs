#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28e_c
readonly revision=action17p-node-a-to-node-b-bootstrap
readonly accepted_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8

declare -A seen_checks=()
role=
expected_hostname=
release=
manifest=
payload_manifest=

file_hash_direct() {
    local action28e_c_file=$1

    sha256sum -- "$action28e_c_file" | awk '{ print $1 }'
}
line_count() { awk 'END { print NR }' "$1"; }
last_byte_hex() {
    if [[ ! -s "$1" ]]; then
        printf 'empty\n'
        return 0
    fi
    tail -c 1 -- "$1" | od -An -tx1 | tr -d '[:space:]'
}
valid_sha256() {
    [[ ${#1} -eq 64 ]] || return 1
    [[ "$1" != *[!0-9a-f]* ]]
}
record_check() {
    local action28e_c_label=$1

    shift
    if [[ -n "${seen_checks[$action28e_c_label]+set}" ]]; then
        printf '%s_duplicate_check=%s\n' "$prefix" "$action28e_c_label" >&2
        return 1
    fi
    seen_checks[$action28e_c_label]=true
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action28e_c_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28e_c_label" >&2
    printf '%s_failed_check=%s\n' "$prefix" "$action28e_c_label" >&2
    return 1
}
marker_state() {
    local action28e_c_path=$1

    if [[ ! -e "$action28e_c_path" && ! -L "$action28e_c_path" ]]; then
        printf 'absent\n'
    elif [[ -f "$action28e_c_path" && ! -L "$action28e_c_path" &&
        ! -s "$action28e_c_path" ]]; then
        printf 'regular_empty\n'
    else
        printf 'other\n'
    fi
}
canonical_payload_identity() {
    local action28e_c_file=$1
    local action28e_c_canonical
    local action28e_c_hash
    local action28e_c_size

    action28e_c_canonical=$(mktemp /tmp/action28e-c-canonical.XXXXXX) || return 1
    if ! jq -cS . "$action28e_c_file" >"$action28e_c_canonical"; then
        rm -f -- "$action28e_c_canonical"
        return 1
    fi
    [[ "$(line_count "$action28e_c_canonical")" -eq 1 ]] || {
        rm -f -- "$action28e_c_canonical"
        return 1
    }
    [[ "$(last_byte_hex "$action28e_c_canonical")" == 0a ]] || {
        rm -f -- "$action28e_c_canonical"
        return 1
    }
    action28e_c_size=$(stat -c %s "$action28e_c_canonical") || {
        rm -f -- "$action28e_c_canonical"
        return 1
    }
    [[ "$action28e_c_size" -ge 1 ]] || {
        rm -f -- "$action28e_c_canonical"
        return 1
    }
    if ! action28e_c_hash=$(
        head -c "$((action28e_c_size - 1))" -- "$action28e_c_canonical" |
            sha256sum | awk '{ print $1 }'
    ); then
        rm -f -- "$action28e_c_canonical"
        return 1
    fi
    rm -f -- "$action28e_c_canonical"
    printf '%s\n' "$action28e_c_hash"
}
safe_field() {
    [[ -n "$1" && "$1" != *[[:cntrl:]]* ]]
}
json_object() {
    jq -e 'type == "object"' "$1" >/dev/null
}
snapshot() {
    {
        printf 'manifest_hash=%s\n' "$(file_hash_direct "$manifest")"
        printf 'manifest_metadata=%s\n' "$(stat -c '%u:%g:%a:%s:%Y:%i:%h' "$manifest")"
        printf 'payload_hash=%s\n' "$(file_hash_direct "$payload_manifest")"
        printf 'payload_metadata=%s\n' "$(stat -c '%u:%g:%a:%s:%Y:%i:%h' "$payload_manifest")"
        printf 'request=%s\n' "$(marker_state "$release/.finalize-request")"
        printf 'complete=%s\n' "$(marker_state "$release/.complete")"
        printf 'pending=%s\n' "$(marker_state "$release/.complete.pending")"
    } | sha256sum | awk '{ print $1 }'
}
expected_checks() {
    printf '%s\n' \
        root_identity hostname_exact release_directory release_not_symlink \
        manifest_regular manifest_not_symlink manifest_single_link manifest_json_valid \
        payload_manifest_regular payload_manifest_not_symlink payload_manifest_single_link \
        raw_manifest_hash_valid canonical_manifest_hash_valid payload_manifest_hash_valid \
        revision_safe parent_safe source_safe created_at_safe revision_exact source_node_a \
        complete_regular_empty pending_absent request_role_state snapshot_stable
}
emit_file_identity() {
    local action28e_c_file=$1
    local action28e_c_label=$2

    printf '%s_value_%s_raw_sha256=%s\n' "$prefix" "$action28e_c_label" \
        "$(file_hash_direct "$action28e_c_file")"
    printf '%s_value_%s_bytes=%s\n' "$prefix" "$action28e_c_label" \
        "$(stat -c %s "$action28e_c_file")"
    printf '%s_value_%s_lines=%s\n' "$prefix" "$action28e_c_label" \
        "$(line_count "$action28e_c_file")"
    printf '%s_value_%s_last_byte_hex=%s\n' "$prefix" "$action28e_c_label" \
        "$(last_byte_hex "$action28e_c_file")"
    printf '%s_value_%s_metadata=%s\n' "$prefix" "$action28e_c_label" \
        "$(stat -c '%u:%g:%a:%s:%Y:%i:%h' "$action28e_c_file")"
}
emit_test_identity() {
    local action28e_c_file=$1
    local action28e_c_raw
    local action28e_c_canonical

    action28e_c_raw=$(file_hash_direct "$action28e_c_file") || return 1
    action28e_c_canonical=$(canonical_payload_identity "$action28e_c_file") || return 1
    printf '%s_value_test_raw_sha256=%s\n' "$prefix" "$action28e_c_raw"
    printf '%s_value_test_canonical_payload_sha256=%s\n' "$prefix" "$action28e_c_canonical"
    printf '%s_value_test_bytes=%s\n' "$prefix" "$(stat -c %s "$action28e_c_file")"
    printf '%s_value_test_lines=%s\n' "$prefix" "$(line_count "$action28e_c_file")"
    printf '%s_value_test_last_byte_hex=%s\n' "$prefix" "$(last_byte_hex "$action28e_c_file")"
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]]
        expected_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$(expected_checks | wc -l)" -eq "$(expected_checks | LC_ALL=C sort -u | wc -l)" ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --test-file)
        [[ $# -eq 2 && "${CADDY_ACTION28E_C_TEST_MODE:-}" == 1 ]]
        emit_test_identity "$2"
        exit 0
        ;;
    node-a)
        [[ $# -eq 1 ]]
        role=node-a
        expected_hostname=j1-svpihole0
        release=/var/lib/caddy-sync/outbound/$revision
        ;;
    node-b)
        [[ $# -eq 1 ]]
        role=node-b
        expected_hostname=j1-svpihole00
        release=/var/lib/caddy-sync/incoming/node-a/$revision
        ;;
    *) exit 64 ;;
esac
readonly role expected_hostname release
manifest=$release/release-manifest.json
payload_manifest=$release/manifest.sha256
readonly manifest payload_manifest

record_check root_identity test "$(id -u)" -eq 0
record_check hostname_exact test "$(hostname)" = "$expected_hostname"
record_check release_directory test -d "$release"
record_check release_not_symlink test ! -L "$release"
record_check manifest_regular test -f "$manifest"
record_check manifest_not_symlink test ! -L "$manifest"
record_check manifest_single_link test "$(stat -c %h "$manifest")" -eq 1
record_check manifest_json_valid json_object "$manifest"
record_check payload_manifest_regular test -f "$payload_manifest"
record_check payload_manifest_not_symlink test ! -L "$payload_manifest"
record_check payload_manifest_single_link test "$(stat -c %h "$payload_manifest")" -eq 1

raw_manifest_sha256=$(file_hash_direct "$manifest")
canonical_manifest_sha256=$(canonical_payload_identity "$manifest")
payload_manifest_sha256=$(file_hash_direct "$payload_manifest")
readonly raw_manifest_sha256 canonical_manifest_sha256 payload_manifest_sha256
emit_file_identity "$manifest" manifest
emit_file_identity "$payload_manifest" payload_manifest
printf '%s_value_manifest_canonical_payload_sha256=%s\n' "$prefix" "$canonical_manifest_sha256"
printf '%s_value_accepted_manifest_sha256=%s\n' "$prefix" "$accepted_manifest_sha256"
record_check raw_manifest_hash_valid valid_sha256 "$raw_manifest_sha256"
record_check canonical_manifest_hash_valid valid_sha256 "$canonical_manifest_sha256"
record_check payload_manifest_hash_valid valid_sha256 "$payload_manifest_sha256"

observed_revision=$(jq -r '.revision // empty' "$manifest")
observed_parent=$(jq -r '.parent_revision // empty' "$manifest")
observed_source=$(jq -r '.source_node // empty' "$manifest")
observed_created_at=$(jq -r '.created_at // empty' "$manifest")
readonly observed_revision observed_parent observed_source observed_created_at
record_check revision_safe safe_field "$observed_revision"
record_check parent_safe safe_field "$observed_parent"
record_check source_safe safe_field "$observed_source"
record_check created_at_safe safe_field "$observed_created_at"
record_check revision_exact test "$observed_revision" = "$revision"
record_check source_node_a test "$observed_source" = node-a
printf '%s_value_revision=%s\n' "$prefix" "$observed_revision"
printf '%s_value_parent_revision=%s\n' "$prefix" "$observed_parent"
printf '%s_value_source_node=%s\n' "$prefix" "$observed_source"
printf '%s_value_created_at=%s\n' "$prefix" "$observed_created_at"

request_state=$(marker_state "$release/.finalize-request")
complete_state=$(marker_state "$release/.complete")
pending_state=$(marker_state "$release/.complete.pending")
readonly request_state complete_state pending_state
record_check complete_regular_empty test "$complete_state" = regular_empty
record_check pending_absent test "$pending_state" = absent
if [[ "$role" == node-a ]]; then
    record_check request_role_state test "$request_state" = absent
else
    record_check request_role_state test "$request_state" = regular_empty
fi
printf '%s_value_request_state=%s\n' "$prefix" "$request_state"
printf '%s_value_complete_state=%s\n' "$prefix" "$complete_state"
printf '%s_value_pending_state=%s\n' "$prefix" "$pending_state"

snapshot_before=$(snapshot)
readonly snapshot_before
record_check snapshot_stable test "$(snapshot)" = "$snapshot_before"
printf '%s_value_role=%s\n' "$prefix" "$role"
printf '%s_value_snapshot_sha256=%s\n' "$prefix" "$snapshot_before"
printf '%s_check_count=%s\n' "$prefix" "${#seen_checks[@]}"
printf '%s_failed_check_count=0\n' "$prefix"
printf '%s_first_failure=none\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_cleanup_executed=false\n' "$prefix"
printf '%s_action_28e_rerun=false\n' "$prefix"
printf '%s_action_28e_a_rerun=false\n' "$prefix"
printf '%s_action_28e_b_rerun=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
