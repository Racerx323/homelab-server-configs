#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_18b_a
readonly revision=action17p-node-a-to-node-b-bootstrap
readonly release="/var/lib/caddy-sync/outbound/$revision"
readonly receiver_v1=/usr/local/libexec/caddy-sync-rsync-receiver
readonly receiver_v2=/usr/local/libexec/caddy-sync-release-receiver-v2
readonly finalizer_v2=/usr/local/libexec/finalize-incoming-release-v2.sh
readonly authorized_keys=/var/lib/caddy-sync/.ssh/authorized_keys
readonly lsyncd_config=/etc/lsyncd/caddy.lua
readonly expected_active_release=/etc/caddy/releases/action16ar-retry-node-a-default-deny
readonly expected_receiver_v1_sha256=65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134
readonly expected_authorization_sha256=6ef8d656053aba6508524aaebd3d215ef9036f8bb6fd1f56cd8b4a654649f968
readonly expected_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly expected_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly expected_node_b_fingerprint='SHA256:ykJmrl499fd2qRm9bYjgyrgeiTCA1rzTelBBKX0gy5g'

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
        find . -type f ! -name .complete \
            ! -name .complete.pending ! -name .finalize-request -print0 |
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

service_snapshot() {
    local property
    local unit

    for unit in caddy.service lighttpd.service lsyncd.service \
        caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-sync-reconcile.service; do
        printf 'unit=%s\n' "$unit"
        for property in ActiveState SubState; do
            systemctl show "$unit" --no-pager --property "$property" --value
        done
        if [[ "$unit" == *.service ]]; then
            for property in MainPID NRestarts; do
                systemctl show "$unit" --no-pager --property "$property" --value
            done
        fi
        systemctl is-enabled "$unit" 2>/dev/null || true
    done
}

stable_state_snapshot() {
    stat -c '%n|%U:%G:%a:%s:%i' \
        "$receiver_v1" "$authorized_keys" "$release" \
        "$release/manifest.sha256" "$release/.complete" \
        /etc/caddy/current /var/backups/caddy-ha
    printf 'receiver_v1=%s\n' "$(file_hash "$receiver_v1")"
    printf 'authorization=%s\n' "$(file_hash "$authorized_keys")"
    printf 'payload=%s\n' "$(payload_digest)"
    printf 'manifest=%s\n' "$(file_hash "$release/manifest.sha256")"
    printf 'complete=%s\n' "$(file_hash "$release/.complete")"
    printf 'current_link=%s\n' "$(readlink /etc/caddy/current)"
    printf 'current_target=%s\n' "$(readlink -e /etc/caddy/current)"
    find "$release" -printf '%P|%y|%U:%G:%m:%s:%i\n' | LC_ALL=C sort
    service_snapshot
}

is_sha256() {
    [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$revision" == action17p-node-a-to-node-b-bootstrap ]]
    for self_test_hash in "$expected_receiver_v1_sha256" \
        "$expected_authorization_sha256" "$expected_payload_sha256" \
        "$expected_manifest_sha256"; do
        is_sha256 "$self_test_hash"
    done
    printf '%s_inspector_self_test_complete=true\n' "$prefix"
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 64
fi

work_directory=$(mktemp -d /tmp/caddy-action18b-a-inspector.XXXXXX)
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
record_command hostname_node_a test "$(hostname)" = j1-svpihole0
record_command architecture_arm64 test "$(dpkg --print-architecture)" = arm64

before_status=0
stable_state_snapshot >"$before_state" 2>"$before_error" || before_status=$?
readonly before_status
record_command before_state_status_zero test "$before_status" -eq 0
record_command before_state_stderr_empty test ! -s "$before_error"
before_sha256=unavailable
if [[ "$before_status" -eq 0 ]]; then
    before_sha256=$(file_hash "$before_state")
fi
readonly before_sha256
record_command before_state_hash_format is_sha256 "$before_sha256"

record_command receiver_v1_regular test -f "$receiver_v1"
record_command receiver_v1_not_symlink test ! -L "$receiver_v1"
record_command receiver_v1_hash_exact \
    test "$(file_hash "$receiver_v1" 2>/dev/null || true)" = \
    "$expected_receiver_v1_sha256"
record_command receiver_v2_absent test ! -e "$receiver_v2"
record_command receiver_v2_not_symlink test ! -L "$receiver_v2"
record_command finalizer_v2_absent test ! -e "$finalizer_v2"
record_command finalizer_v2_not_symlink test ! -L "$finalizer_v2"
record_command authorized_keys_regular test -f "$authorized_keys"
record_command authorized_keys_not_symlink test ! -L "$authorized_keys"
record_command authorized_keys_metadata \
    test "$(stat -c '%U:%G:%a' "$authorized_keys" 2>/dev/null || true)" = \
    caddy-sync:caddy-sync:600
record_command authorized_keys_single_line test "$(wc -l <"$authorized_keys")" -eq 1
record_command authorized_keys_hash_exact \
    test "$(file_hash "$authorized_keys" 2>/dev/null || true)" = \
    "$expected_authorization_sha256"
record_command authorized_keys_node_b_fingerprint \
    test "$(authorization_fingerprint 2>/dev/null || true)" = \
    "$expected_node_b_fingerprint"

record_command release_regular_directory test -d "$release"
record_command release_not_symlink test ! -L "$release"
record_command release_metadata \
    test "$(stat -c '%U:%G:%a' "$release" 2>/dev/null || true)" = \
    caddy-sync:caddy-sync:550
record_command manifest_regular test -f "$release/manifest.sha256"
record_command manifest_not_symlink test ! -L "$release/manifest.sha256"
record_command manifest_hash_exact \
    test "$(file_hash "$release/manifest.sha256" 2>/dev/null || true)" = \
    "$expected_manifest_sha256"
record_command payload_hash_exact test "$(payload_digest 2>/dev/null || true)" = \
    "$expected_payload_sha256"

readonly complete_marker="$release/.complete"
record_command complete_regular test -f "$complete_marker"
record_command complete_not_symlink test ! -L "$complete_marker"
record_command complete_empty test ! -s "$complete_marker"
marker_owner=$(stat -c '%U' "$complete_marker" 2>/dev/null || printf unavailable)
readonly marker_owner
marker_group=$(stat -c '%G' "$complete_marker" 2>/dev/null || printf unavailable)
readonly marker_group
marker_mode=$(stat -c '%a' "$complete_marker" 2>/dev/null || printf unavailable)
readonly marker_mode
marker_bytes=$(stat -c '%s' "$complete_marker" 2>/dev/null || printf unavailable)
readonly marker_bytes
marker_lines=$(awk 'END { print NR }' "$complete_marker" 2>/dev/null || printf unavailable)
readonly marker_lines
marker_sha256=$(file_hash "$complete_marker" 2>/dev/null || printf unavailable)
readonly marker_sha256
record_command complete_owner_observed test "$marker_owner" != unavailable
record_command complete_group_observed test "$marker_group" != unavailable
record_command complete_mode_0440 test "$marker_mode" = 440
record_command complete_bytes_zero test "$marker_bytes" = 0
record_command complete_lines_zero test "$marker_lines" = 0
record_command complete_empty_sha256 \
    test "$marker_sha256" = \
    e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
record_command pending_marker_absent test ! -e "$release/.complete.pending"
record_command pending_marker_not_symlink test ! -L "$release/.complete.pending"
record_command finalize_request_absent test ! -e "$release/.finalize-request"
record_command finalize_request_not_symlink test ! -L "$release/.finalize-request"

marker_classification=unsafe_or_unknown
if [[ -f "$complete_marker" && ! -L "$complete_marker" &&
    ! -s "$complete_marker" && ! -e "$release/.complete.pending" &&
    ! -e "$release/.finalize-request" ]]; then
    marker_classification=sender_build_complete
fi
readonly marker_classification
record_command marker_classification_sender_build_complete \
    test "$marker_classification" = sender_build_complete

record_command current_link_exact \
    test "$(readlink /etc/caddy/current 2>/dev/null || true)" = \
    "$expected_active_release"
record_command current_target_exact \
    test "$(readlink -e /etc/caddy/current 2>/dev/null || true)" = \
    "$expected_active_release"
record_command caddy_active test "$(systemctl is-active caddy.service)" = active
record_command lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
record_command lsyncd_inactive \
    test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
record_command lsyncd_masked \
    test "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" = masked
record_command caddy_lsyncd_inactive \
    test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = inactive
record_command caddy_lsyncd_disabled \
    test "$(systemctl is-enabled caddy-lsyncd.service 2>/dev/null || true)" = disabled
record_command reconcile_path_inactive \
    test "$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)" = inactive
record_command reconcile_service_inactive \
    test "$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)" = inactive
record_command lsyncd_configuration_absent test ! -e "$lsyncd_config"
record_command lsyncd_configuration_not_symlink test ! -L "$lsyncd_config"

action18b_backup_count=$(find /var/backups/caddy-ha -mindepth 1 -maxdepth 1 \
    -name 'action18b-node-a-prerequisite.*' -printf . | wc -c)
readonly action18b_backup_count
record_command action18b_backup_count_zero test "$action18b_backup_count" -eq 0
action18b_stage_count=$(
    find /run /tmp -mindepth 1 -maxdepth 1 \
        \( -name 'caddy-action18b-*' -o -name '.caddy-sync-*-v2.*' \) \
        -printf . 2>/dev/null | wc -c
)
readonly action18b_stage_count
record_command action18b_stage_count_zero test "$action18b_stage_count" -eq 0

after_status=0
stable_state_snapshot >"$after_state" 2>"$after_error" || after_status=$?
readonly after_status
record_command after_state_status_zero test "$after_status" -eq 0
record_command after_state_stderr_empty test ! -s "$after_error"
after_sha256=unavailable
if [[ "$after_status" -eq 0 ]]; then
    after_sha256=$(file_hash "$after_state")
fi
readonly after_sha256
record_command after_state_hash_format is_sha256 "$after_sha256"
record_command state_unchanged test "$after_sha256" = "$before_sha256"

printf '%s_value_marker_classification=%s\n' "$prefix" "$marker_classification"
printf '%s_value_marker_owner=%s\n' "$prefix" "$marker_owner"
printf '%s_value_marker_group=%s\n' "$prefix" "$marker_group"
printf '%s_value_marker_mode=%s\n' "$prefix" "$marker_mode"
printf '%s_value_marker_bytes=%s\n' "$prefix" "$marker_bytes"
printf '%s_value_marker_lines=%s\n' "$prefix" "$marker_lines"
printf '%s_value_marker_sha256=%s\n' "$prefix" "$marker_sha256"
printf '%s_value_action18b_backup_count=%s\n' "$prefix" "$action18b_backup_count"
printf '%s_value_action18b_stage_count=%s\n' "$prefix" "$action18b_stage_count"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$before_sha256"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$after_sha256"
printf '%s_assertion_count=%s\n' "$prefix" "$assertion_count"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_assertion_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_receiver_invoked=false\n' "$prefix"
printf '%s_finalizer_invoked=false\n' "$prefix"
printf '%s_release_mutated=false\n' "$prefix"
printf '%s_authorization_mutated=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_synchronization_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

if [[ "$failed_assertion_count" -ne 0 ]]; then
    exit 1
fi
