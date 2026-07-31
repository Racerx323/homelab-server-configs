#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly revision=action17p-node-a-to-node-b-bootstrap
readonly parent_revision=action15-health-follow-redirects
readonly node_a_active_release=/etc/caddy/releases/action16ar-retry-node-a-default-deny
readonly node_b_active_release=/etc/caddy/releases/action15-health-follow-redirects
readonly outbound_release="/var/lib/caddy-sync/outbound/$revision"
readonly incoming_release="/var/lib/caddy-sync/incoming/node-a/$revision"
readonly receiver=/usr/local/libexec/caddy-sync-rsync-receiver
readonly receiver_sha256=65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134

assertion_count=0
failed_assertion_count=0
first_failure=none

record_assertion() {
    local assertion_label=$1
    local assertion_value=$2

    assertion_count=$((assertion_count + 1))
    printf '%s_assertion_%s=%s\n' \
        "$action_prefix" "$assertion_label" "$assertion_value"
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
    local digest_release=$1

    (
        cd "$digest_release" || exit
        find . -type f ! -name .complete -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r sha256sum |
            sha256sum |
            awk '{ print $1 }'
    )
}

manifest_status() {
    local manifest_release=$1

    (
        cd "$manifest_release" || exit
        sha256sum --check manifest.sha256
    )
}

certificate_key_match() {
    local certificate_release=$1
    local certificate_key_hash
    local private_key_hash

    certificate_key_hash=$(
        openssl x509 -in "$certificate_release/tls/fullchain.pem" \
            -pubkey -noout |
            openssl pkey -pubin -outform DER 2>/dev/null |
            sha256sum |
            awk '{ print $1 }'
    )
    private_key_hash=$(
        openssl pkey -in "$certificate_release/tls/privkey.pem" \
            -pubout -outform DER 2>/dev/null |
            sha256sum |
            awk '{ print $1 }'
    )
    [[ "$certificate_key_hash" == "$private_key_hash" ]]
}

state_snapshot() {
    stat -c '%n|%U:%G:%a:%s:%i' \
        /var/lib/caddy-sync \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/quarantine \
        /etc/caddy/current \
        /etc/default/caddy-ha
    printf 'current_link=%s\n' "$(readlink /etc/caddy/current)"
    printf 'current_target=%s\n' "$(readlink -e /etc/caddy/current)"
    find \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/quarantine \
        -printf '%p|%y|%U:%G:%m:%s:%i\n' |
        LC_ALL=C sort
    find \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/quarantine \
        -type f -print0 |
        LC_ALL=C sort -z |
        xargs -0 -r sha256sum
    for snapshot_unit in \
        caddy.service \
        lighttpd.service \
        lsyncd.service \
        caddy-lsyncd.service \
        caddy-sync-reconcile.path \
        caddy-sync-reconcile.service; do
        printf 'unit=%s\n' "$snapshot_unit"
        systemctl show "$snapshot_unit" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts
        printf 'unit_file_state=%s\n' \
            "$(systemctl is-enabled "$snapshot_unit" 2>/dev/null || true)"
    done
}

classify_marker() {
    local marker_path=$1

    if [[ ! -e "$marker_path" && ! -L "$marker_path" ]]; then
        printf 'absent\n'
    elif [[ -f "$marker_path" && ! -L "$marker_path" &&
        ! -s "$marker_path" ]]; then
        printf 'present_empty_regular\n'
    elif [[ -f "$marker_path" && ! -L "$marker_path" ]]; then
        printf 'present_nonempty_regular\n'
    else
        printf 'unsafe_type\n'
    fi
}

is_boolean() {
    [[ "$1" =~ ^(true|false)$ ]]
}

is_mode() {
    [[ "$1" =~ ^[0-7]{3,4}$ ]]
}

is_sha256() {
    [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

is_supported_marker_state() {
    [[ "$1" =~ ^(absent|present_empty_regular)$ ]]
}

is_supported_acl_status() {
    [[ "$1" == not_run || "$1" == 0 ]]
}

is_supported_acl_hash() {
    [[ "$1" == unavailable || "$1" =~ ^[0-9a-f]{64}$ ]]
}

is_supported_conclusion() {
    [[ "$1" =~ ^marker_(absent|present)_release_(nonwritable|writable)$ ]]
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$revision" == action17p-node-a-to-node-b-bootstrap ]]
    [[ "$parent_revision" == action15-health-follow-redirects ]]
    [[ "$node_a_active_release" == /etc/caddy/releases/action16ar-retry-node-a-default-deny ]]
    [[ "$node_b_active_release" == /etc/caddy/releases/action15-health-follow-redirects ]]
    printf 'action_17p_a_inspector_self_test_complete=true\n'
    exit 0
fi

if [[ $# -ne 1 || ! "${1:-}" =~ ^--node-(a|b)$ ]]; then
    printf 'Usage: %s --node-a|--node-b\n' "${0##*/}" >&2
    exit 2
fi

readonly node_role=${1#--}
readonly action_prefix="action_17p_a_${node_role//-/_}"
expected_hostname=$(
    if [[ "$node_role" == node-a ]]; then
        printf 'j1-svpihole0'
    else
        printf 'j1-svpihole00'
    fi
)
readonly expected_hostname
expected_active_release=$(
    if [[ "$node_role" == node-a ]]; then
        printf '%s' "$node_a_active_release"
    else
        printf '%s' "$node_b_active_release"
    fi
)
readonly expected_active_release
inspected_release=$(
    if [[ "$node_role" == node-a ]]; then
        printf '%s' "$outbound_release"
    else
        printf '%s' "$incoming_release"
    fi
)
readonly inspected_release

work_directory=$(mktemp -d "/tmp/caddy-action17p-a-$node_role.XXXXXX")
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

record_command identity_root test "$(id -u)" -eq 0
record_command working_directory_root test "$(pwd -P)" = /
record_command architecture_arm64 test "$(dpkg --print-architecture)" = arm64
record_command hostname_exact test "$(hostname)" = "$expected_hostname"
record_command environment_regular test -f /etc/default/caddy-ha
record_command environment_not_symlink test ! -L /etc/default/caddy-ha
record_command environment_role_exact \
    grep -Fxq "NODE_ROLE=$node_role" /etc/default/caddy-ha
record_command current_link_exact \
    test "$(readlink /etc/caddy/current 2>/dev/null || true)" = \
    "$expected_active_release"
record_command current_target_exact \
    test "$(readlink -e /etc/caddy/current 2>/dev/null || true)" = \
    "$expected_active_release"
record_command caddy_active \
    test "$(systemctl is-active caddy.service 2>/dev/null || true)" = active
record_command lighttpd_active \
    test "$(systemctl is-active lighttpd.service 2>/dev/null || true)" = active
record_command lsyncd_inactive \
    test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
record_command caddy_lsyncd_inactive \
    test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = \
    inactive
record_command reconcile_path_inactive \
    test "$(systemctl is-active caddy-sync-reconcile.path \
        2>/dev/null || true)" = inactive
record_command reconcile_service_inactive \
    test "$(systemctl is-active caddy-sync-reconcile.service \
        2>/dev/null || true)" = inactive
record_command lsyncd_configuration_absent test ! -e /etc/lsyncd/caddy.lua

before_state_path="$work_directory/state-before"
before_error_path="$work_directory/state-before.err"
before_state_status=0
state_snapshot >"$before_state_path" 2>"$before_error_path" ||
    before_state_status=$?
record_command before_state_status_zero test "$before_state_status" -eq 0
record_command before_state_stderr_empty test ! -s "$before_error_path"
before_state_sha256=unavailable
if [[ "$before_state_status" -eq 0 ]]; then
    before_state_sha256=$(file_hash "$before_state_path")
fi

record_command release_directory_present test -d "$inspected_release"
record_command release_path_not_symlink test ! -L "$inspected_release"
record_command release_manifest_regular \
    test -f "$inspected_release/release-manifest.json"
record_command release_manifest_not_symlink \
    test ! -L "$inspected_release/release-manifest.json"
record_command hash_manifest_regular \
    test -f "$inspected_release/manifest.sha256"
record_command hash_manifest_not_symlink \
    test ! -L "$inspected_release/manifest.sha256"
record_command manifest_revision_exact \
    test "$(jq -r '.revision // empty' \
        "$inspected_release/release-manifest.json" 2>/dev/null || true)" = \
    "$revision"
record_command manifest_parent_exact \
    test "$(jq -r '.parent_revision // empty' \
        "$inspected_release/release-manifest.json" 2>/dev/null || true)" = \
    "$parent_revision"
record_command manifest_source_exact \
    test "$(jq -r '.source_node // empty' \
        "$inspected_release/release-manifest.json" 2>/dev/null || true)" = \
    node-a
record_command payload_symlinks_absent \
    test -z "$(find "$inspected_release" -type l -print -quit)"
record_command manifest_hashes_valid manifest_status "$inspected_release"
record_command certificate_parse \
    openssl x509 -in "$inspected_release/tls/fullchain.pem" -noout
record_command private_key_parse \
    openssl pkey -in "$inspected_release/tls/privkey.pem" -noout
record_command certificate_key_match certificate_key_match "$inspected_release"

if [[ "$node_role" == node-a ]]; then
    record_command outbound_parent_directory_metadata \
        test "$(stat -c '%U:%G:%a' /var/lib/caddy-sync/outbound)" = \
        caddy-sync:caddy-sync:750
    record_command outbound_only_expected_release \
        test "$(find /var/lib/caddy-sync/outbound -mindepth 1 -maxdepth 1 \
            -printf '%f\n' | LC_ALL=C sort)" = "$revision"
    record_command incoming_tree_empty \
        test -z "$(find /var/lib/caddy-sync/incoming -mindepth 1 \
            -print -quit)"
    record_command quarantine_tree_empty \
        test -z "$(find /var/lib/caddy-sync/quarantine -mindepth 1 \
            -print -quit)"
else
    record_command receiver_regular test -f "$receiver"
    record_command receiver_not_symlink test ! -L "$receiver"
    record_command receiver_hash_exact \
        test "$(file_hash "$receiver" 2>/dev/null || true)" = "$receiver_sha256"
    record_command incoming_parent_directory_metadata \
        test "$(stat -c '%U:%G:%a' \
            /var/lib/caddy-sync/incoming/node-a 2>/dev/null || true)" = \
        caddy-sync:caddy-sync:750
    record_command incoming_only_node_a \
        test "$(find /var/lib/caddy-sync/incoming -mindepth 1 -maxdepth 1 \
            -printf '%f\n' | LC_ALL=C sort)" = node-a
    record_command incoming_only_expected_release \
        test "$(find /var/lib/caddy-sync/incoming/node-a -mindepth 1 \
            -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)" = "$revision"
    record_command outbound_tree_empty \
        test -z "$(find /var/lib/caddy-sync/outbound -mindepth 1 \
            -print -quit)"
    record_command quarantine_tree_empty \
        test -z "$(find /var/lib/caddy-sync/quarantine -mindepth 1 \
            -print -quit)"
fi

marker_state=$(classify_marker "$inspected_release/.complete")
readonly marker_state
record_command marker_classification_supported \
    is_supported_marker_state "$marker_state"

release_owner=$(stat -c '%U' "$inspected_release" 2>/dev/null || printf unavailable)
readonly release_owner
release_group=$(stat -c '%G' "$inspected_release" 2>/dev/null || printf unavailable)
readonly release_group
release_mode=$(stat -c '%a' "$inspected_release" 2>/dev/null || printf unavailable)
readonly release_mode
record_command release_owner_observed \
    test "$release_owner" != unavailable
record_command release_group_observed \
    test "$release_group" != unavailable
record_command release_mode_format \
    is_mode "$release_mode"

release_writable_by_sync=false
if runuser -u caddy-sync -- test -w "$inspected_release"; then
    release_writable_by_sync=true
fi
readonly release_writable_by_sync
record_command release_writability_boolean \
    is_boolean "$release_writable_by_sync"

acl_tool_available=false
acl_sha256=unavailable
acl_read_status=not_run
if command -v getfacl >/dev/null 2>&1; then
    acl_tool_available=true
    acl_path="$work_directory/release.acl"
    acl_status=0
    getfacl -cp -- "$inspected_release" >"$acl_path" 2>/dev/null ||
        acl_status=$?
    acl_read_status=$acl_status
    if [[ "$acl_status" -eq 0 ]]; then
        acl_sha256=$(file_hash "$acl_path")
    fi
fi
readonly acl_tool_available
readonly acl_sha256
readonly acl_read_status
record_command acl_tool_availability_boolean \
    is_boolean "$acl_tool_available"
record_command acl_read_status_supported \
    is_supported_acl_status "$acl_read_status"
record_command acl_hash_supported \
    is_supported_acl_hash "$acl_sha256"

payload_sha256=unavailable
manifest_sha256=unavailable
if [[ -d "$inspected_release" ]]; then
    payload_sha256=$(payload_digest "$inspected_release" 2>/dev/null ||
        printf unavailable)
fi
if [[ -f "$inspected_release/manifest.sha256" ]]; then
    manifest_sha256=$(file_hash "$inspected_release/manifest.sha256")
fi
readonly payload_sha256
readonly manifest_sha256
record_command payload_digest_format \
    is_sha256 "$payload_sha256"
record_command manifest_digest_format \
    is_sha256 "$manifest_sha256"

after_state_path="$work_directory/state-after"
after_error_path="$work_directory/state-after.err"
after_state_status=0
state_snapshot >"$after_state_path" 2>"$after_error_path" ||
    after_state_status=$?
record_command after_state_status_zero test "$after_state_status" -eq 0
record_command after_state_stderr_empty test ! -s "$after_error_path"
after_state_sha256=unavailable
if [[ "$after_state_status" -eq 0 ]]; then
    after_state_sha256=$(file_hash "$after_state_path")
fi
readonly before_state_sha256
readonly after_state_sha256
record_command state_unchanged \
    test "$after_state_sha256" = "$before_state_sha256"

if [[ "$marker_state" == absent &&
    "$release_writable_by_sync" == false ]]; then
    conclusion=marker_absent_release_nonwritable
elif [[ "$marker_state" == absent &&
    "$release_writable_by_sync" == true ]]; then
    conclusion=marker_absent_release_writable
elif [[ "$marker_state" == present_empty_regular &&
    "$release_writable_by_sync" == false ]]; then
    conclusion=marker_present_release_nonwritable
elif [[ "$marker_state" == present_empty_regular &&
    "$release_writable_by_sync" == true ]]; then
    conclusion=marker_present_release_writable
else
    conclusion=unsafe_marker_state
fi
readonly conclusion
record_command conclusion_supported \
    is_supported_conclusion "$conclusion"

printf '%s_value_node_role=%s\n' "$action_prefix" "$node_role"
printf '%s_value_revision=%s\n' "$action_prefix" "$revision"
printf '%s_value_parent_revision=%s\n' "$action_prefix" "$parent_revision"
printf '%s_value_before_state_sha256=%s\n' \
    "$action_prefix" "$before_state_sha256"
printf '%s_value_after_state_sha256=%s\n' \
    "$action_prefix" "$after_state_sha256"
printf '%s_value_payload_sha256=%s\n' "$action_prefix" "$payload_sha256"
printf '%s_value_manifest_sha256=%s\n' "$action_prefix" "$manifest_sha256"
printf '%s_value_marker_state=%s\n' "$action_prefix" "$marker_state"
printf '%s_value_release_owner=%s\n' "$action_prefix" "$release_owner"
printf '%s_value_release_group=%s\n' "$action_prefix" "$release_group"
printf '%s_value_release_mode=%s\n' "$action_prefix" "$release_mode"
printf '%s_value_release_writable_by_sync=%s\n' \
    "$action_prefix" "$release_writable_by_sync"
printf '%s_value_acl_tool_available=%s\n' \
    "$action_prefix" "$acl_tool_available"
printf '%s_value_acl_sha256=%s\n' "$action_prefix" "$acl_sha256"
printf '%s_value_conclusion=%s\n' "$action_prefix" "$conclusion"
printf '%s_assertion_count=%s\n' "$action_prefix" "$assertion_count"
printf '%s_failed_assertion_count=%s\n' \
    "$action_prefix" "$failed_assertion_count"
printf '%s_first_failure=%s\n' "$action_prefix" "$first_failure"
printf '%s_peer_connections=false\n' "$action_prefix"
printf '%s_release_transfer_executed=false\n' "$action_prefix"
printf '%s_completion_marker_write_executed=false\n' "$action_prefix"
printf '%s_reconciliation_executed=false\n' "$action_prefix"
printf '%s_service_mutations=false\n' "$action_prefix"
printf '%s_persistent_mutations=false\n' "$action_prefix"
printf '%s_remote_complete=true\n' "$action_prefix"

if [[ "$failed_assertion_count" -ne 0 ]]; then
    exit 1
fi
