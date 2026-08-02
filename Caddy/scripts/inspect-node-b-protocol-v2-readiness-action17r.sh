#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_17r_node_b
readonly revision=action17p-node-a-to-node-b-bootstrap
readonly parent_revision=action15-health-follow-redirects
readonly release=/var/lib/caddy-sync/incoming/node-a/action17p-node-a-to-node-b-bootstrap
readonly receiver=/usr/local/libexec/caddy-sync-release-receiver-v2
readonly finalizer=/usr/local/libexec/finalize-incoming-release-v2.sh
readonly authorized_keys=/var/lib/caddy-sync/.ssh/authorized_keys
readonly expected_receiver_sha256=a94c7a45531787055da622a0dac180f98e52bd0ba967424a4cf22a4852539d9e
readonly expected_finalizer_sha256=a49dadcaa611e641a100e6a4f2b1836fcf9a790876f437ee02e37003d78ef30c
readonly expected_authorization_sha256=54eeda8ae3c94e878a38d76ccade91642ba9ab193b5f416ea1bf308a500a1bc1
readonly expected_node_a_fingerprint='SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0'
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
        if [[ "$first_failure" == none ]]; then
            first_failure=$assertion_label
        fi
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

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

payload_digest() {
    (
        cd "$release" || exit
        find . -type f ! -name .complete -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r sha256sum |
            sha256sum |
            awk '{ print $1 }'
    )
}

authorization_fingerprint() {
    awk '{ print $(NF-2), $(NF-1), $NF }' "$authorized_keys" |
        ssh-keygen -lf - -E sha256 |
        awk '{ print $2 }'
}

receiver_command_allowed() {
    local boundary_command=$1

    [[ "$boundary_command" == rsync\ --server\ * &&
        "$boundary_command" != *--delete* ]]
}

receiver_command_rejected() {
    ! receiver_command_allowed "$1"
}

stable_state_snapshot() {
    stat -c '%n|%U:%G:%a:%s:%i' \
        "$receiver" "$finalizer" "$authorized_keys" \
        "$release" "$release/manifest.sha256" /etc/caddy/current
    sha256sum "$receiver" "$finalizer" "$authorized_keys" \
        "$release/manifest.sha256"
    find "$release" -printf '%P|%y|%U:%G:%m:%s:%i\n' | LC_ALL=C sort
    find "$release" -type f -print0 |
        LC_ALL=C sort -z |
        xargs -0 -r sha256sum
    readlink /etc/caddy/current
    readlink -e /etc/caddy/current
    for snapshot_unit in \
        caddy.service lighttpd.service lsyncd.service caddy-lsyncd.service \
        caddy-sync-reconcile.service caddy-sync-reconcile.path; do
        systemctl show "$snapshot_unit" --no-pager \
            -p LoadState -p ActiveState -p SubState -p FragmentPath
        printf 'unit_file_state=%s\n' \
            "$(systemctl is-enabled "$snapshot_unit" 2>/dev/null || true)"
    done
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    receiver_command_allowed 'rsync --server -logDtpre.iLsfxCIvu . /'
    if receiver_command_allowed caddy-sync-readiness-probe; then
        exit 1
    fi
    if receiver_command_allowed 'rsync --server --delete -logDtpre.iLsfxCIvu . /'; then
        exit 1
    fi
    [[ "$expected_receiver_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$expected_finalizer_sha256" =~ ^[0-9a-f]{64}$ ]]
    printf 'action_17r_node_b_inspector_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

work_directory=$(mktemp -d /tmp/caddy-action17r-node-b.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly before_state="$work_directory/state.before"
readonly before_error="$work_directory/state.before.err"
readonly after_state="$work_directory/state.after"
readonly after_error="$work_directory/state.after.err"

record_command identity_root test "$(id -u)" -eq 0
record_command working_directory_root test "$(pwd -P)" = /
record_command hostname_node_b test "$(hostname)" = j1-svpihole00
record_command architecture_arm64 test "$(dpkg --print-architecture)" = arm64
record_command receiver_regular test -f "$receiver"
record_command receiver_not_symlink test ! -L "$receiver"
record_command receiver_metadata \
    test "$(stat -c '%U:%G:%a' "$receiver")" = root:root:755
record_command receiver_hash_exact \
    test "$(file_hash "$receiver")" = "$expected_receiver_sha256"
record_command receiver_syntax bash -n "$receiver"
# The following assertions intentionally match literal installed shell source.
# shellcheck disable=SC2016
record_command receiver_requires_rsync_server \
    grep -Fq '"$command_value" != rsync\ --server\ *' "$receiver"
# shellcheck disable=SC2016
record_command receiver_rejects_delete \
    grep -Fq '"$command_value" == *--delete*' "$receiver"
# shellcheck disable=SC2016
record_command receiver_uses_write_only_no_delete_rrsync \
    grep -Fq '/usr/bin/rrsync -wo -no-del "$receiver_root"' "$receiver"
# shellcheck disable=SC2016
record_command receiver_finalizes_only_after_rsync_success \
    grep -Fq '"$finalizer" --source-role "$source_role"' "$receiver"
record_command boundary_accepts_rsync_server \
    receiver_command_allowed 'rsync --server -logDtpre.iLsfxCIvu . /'
record_command boundary_rejects_arbitrary_command \
    receiver_command_rejected caddy-sync-readiness-probe
record_command boundary_rejects_delete \
    receiver_command_rejected \
    'rsync --server --delete -logDtpre.iLsfxCIvu . /'
record_command finalizer_regular test -f "$finalizer"
record_command finalizer_not_symlink test ! -L "$finalizer"
record_command finalizer_metadata \
    test "$(stat -c '%U:%G:%a' "$finalizer")" = root:root:755
record_command finalizer_hash_exact \
    test "$(file_hash "$finalizer")" = "$expected_finalizer_sha256"
record_command finalizer_syntax bash -n "$finalizer"
record_command finalizer_requires_request_marker \
    grep -Fq -- "-exec test -f '{}/.finalize-request' ';'" "$finalizer"
# shellcheck disable=SC2016
record_command finalizer_validates_before_marker \
    grep -Fq 'validate_release "$release_path" "$release_source_role" "$release_revision"' \
    "$finalizer"
# shellcheck disable=SC2016
record_command finalizer_creates_local_complete \
    grep -Fq 'mv -T -- "$release_path/$pending_name"' "$finalizer"
record_command authorized_keys_regular test -f "$authorized_keys"
record_command authorized_keys_not_symlink test ! -L "$authorized_keys"
record_command authorized_keys_metadata \
    test "$(stat -c '%U:%G:%a' "$authorized_keys")" = caddy-sync:caddy-sync:600
record_command authorized_keys_hash_exact \
    test "$(file_hash "$authorized_keys")" = "$expected_authorization_sha256"
record_command authorized_keys_single_line test "$(wc -l <"$authorized_keys")" -eq 1
record_command authorization_source_ipv4 \
    grep -Fq 'from="10.1.0.53,fd36:5aa8:6971:1::53"' "$authorized_keys"
record_command authorization_restricted grep -Fq ',restrict,command=' "$authorized_keys"
record_command authorization_receiver_v2_role \
    grep -Fq 'command="/usr/local/libexec/caddy-sync-release-receiver-v2 --source-role node-a"' \
    "$authorized_keys"
record_command authorization_fingerprint_exact \
    test "$(authorization_fingerprint)" = "$expected_node_a_fingerprint"
record_command release_directory_regular test -d "$release"
record_command release_not_symlink test ! -L "$release"
record_command release_metadata \
    test "$(stat -c '%U:%G:%a' "$release")" = caddy-sync:caddy-sync:550
record_command release_revision_exact \
    test "$(jq -r '.revision // empty' "$release/release-manifest.json")" = \
    "$revision"
record_command release_parent_exact \
    test "$(jq -r '.parent_revision // empty' "$release/release-manifest.json")" = \
    "$parent_revision"
record_command release_source_exact \
    test "$(jq -r '.source_node // empty' "$release/release-manifest.json")" = \
    node-a
record_command complete_absent test ! -e "$release/.complete"
record_command complete_not_symlink test ! -L "$release/.complete"
record_command complete_pending_absent test ! -e "$release/.complete.pending"
record_command complete_pending_not_symlink test ! -L "$release/.complete.pending"
record_command finalize_request_absent test ! -e "$release/.finalize-request"
record_command finalize_request_not_symlink test ! -L "$release/.finalize-request"
record_command release_payload_hash_exact \
    test "$(payload_digest)" = "$expected_payload_sha256"
record_command release_manifest_hash_exact \
    test "$(file_hash "$release/manifest.sha256")" = \
    "$expected_manifest_sha256"
record_command release_not_writable_by_sync \
    runuser -u caddy-sync -- test ! -w "$release"
record_command caddy_active \
    test "$(systemctl is-active caddy.service)" = active
record_command lighttpd_active \
    test "$(systemctl is-active lighttpd.service)" = active
record_command lsyncd_inactive \
    test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
record_command lsyncd_masked \
    test "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" = masked
record_command caddy_lsyncd_inactive \
    test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = inactive
record_command reconcile_path_inactive \
    test "$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)" = \
    inactive
record_command reconcile_service_inactive \
    test "$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)" = \
    inactive

before_status=0
stable_state_snapshot >"$before_state" 2>"$before_error" || before_status=$?
readonly before_status
record_command before_state_status_zero test "$before_status" -eq 0
record_command before_state_stderr_empty test ! -s "$before_error"
before_state_sha256=$(file_hash "$before_state")
readonly before_state_sha256
after_status=0
stable_state_snapshot >"$after_state" 2>"$after_error" || after_status=$?
readonly after_status
record_command after_state_status_zero test "$after_status" -eq 0
record_command after_state_stderr_empty test ! -s "$after_error"
after_state_sha256=$(file_hash "$after_state")
readonly after_state_sha256
record_command state_unchanged test "$after_state_sha256" = "$before_state_sha256"

printf '%s_value_payload_sha256=%s\n' "$prefix" "$expected_payload_sha256"
printf '%s_value_manifest_sha256=%s\n' "$prefix" "$expected_manifest_sha256"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$before_state_sha256"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$after_state_sha256"
printf '%s_value_receiver_state=installed_policy_ready\n' "$prefix"
printf '%s_value_release_state=payload_ready_awaiting_finalize_request\n' "$prefix"
printf '%s_assertion_count=%s\n' "$prefix" "$assertion_count"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_assertion_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_peer_connection_executed=false\n' "$prefix"
printf '%s_restricted_command_executed=false\n' "$prefix"
printf '%s_release_transfer_executed=false\n' "$prefix"
printf '%s_marker_mutation=false\n' "$prefix"
printf '%s_helper_invocation=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

if [[ "$failed_assertion_count" -ne 0 ]]; then
    exit 1
fi
