#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28f_node_a
readonly current_release=/etc/caddy/current
readonly node_a_ipv6=fd36:5aa8:6971:1::53
readonly node_b_fqdn=pihole00.local.theama.co
readonly private_key=/var/lib/caddy-sync/.ssh/id_ed25519
readonly known_hosts=/var/lib/caddy-sync/.ssh/known_hosts
readonly outbound_root=/var/lib/caddy-sync/outbound
readonly retained_release=$outbound_root/action17p-node-a-to-node-b-bootstrap
readonly candidate_revision=20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63
readonly candidate_parent=action16ar-retry-node-a-default-deny
readonly candidate_release=$outbound_root/$candidate_revision
readonly candidate_release_manifest_sha256=c72b5bc5a6586ac3be098c0c5ca2fc3dc01a09c2afe4dcf90ed4bdbda6d166de
readonly candidate_payload_manifest_sha256=fdc6ed955f14226ac3e1777eca37507cc8ab6ca16add3135dece9d6964e27568
readonly candidate_tree_sha256=ad5bf3781d8c45eb1c6153aca85766ca58dd65ab06c825041f0d8014f3f3244b
readonly candidate_metadata=994:990:550:4096:1786304072
readonly expected_outbound_root_identity=994:990:750
readonly expected_retained_tree_sha256=dc6f4359cd6f0f424f2db89b180d63d5478f0de36c344e406c707340b57ceb37
readonly expected_current_tree_sha256=b7f3dfba3b0dc2aa278f0d1e6dd02fc7d2be6ef0eb656f12f7bc7288df12ebd9
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

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
    if [[ "$first_failure" == none ]]; then
        first_failure=$result_label
    fi
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
line_count() { awk 'END { print NR }' "$1"; }

safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$stream_path"
}

emit_stream() {
    local stream_label=$1
    local stream_path=$2

    printf '%s_value_%s_bytes=%s\n' "$prefix" "$stream_label" \
        "$(wc -c <"$stream_path")"
    printf '%s_value_%s_lines=%s\n' "$prefix" "$stream_label" \
        "$(line_count "$stream_path")"
    printf '%s_value_%s_sha256=%s\n' "$prefix" "$stream_label" \
        "$(file_hash "$stream_path")"
    if ! safe_stream "$stream_path"; then
        printf '%s_value_%s_classification=unsafe_retained\n' \
            "$prefix" "$stream_label" >&2
        trap - EXIT
        printf '%s_value_%s_protected_evidence=%s\n' \
            "$prefix" "$stream_label" "${stream_path%/*}" >&2
        return 97
    fi
    printf '%s_value_%s_classification=bounded_safe\n' "$prefix" "$stream_label"
    while IFS= read -r stream_line || [[ -n "$stream_line" ]]; do
        printf '%s_value_%s_content=%s\n' "$prefix" "$stream_label" \
            "$(printf '%s' "$stream_line" | base64 -w 0)"
    done <"$stream_path"
}

remote_shell_value() {
    printf '%s' \
        "ssh -6 -F /dev/null -b $node_a_ipv6" \
        " -i $private_key -o BatchMode=yes" \
        " -o ClearAllForwardings=yes -o ConnectTimeout=5" \
        " -o GlobalKnownHostsFile=/dev/null" \
        " -o HostKeyAlias=$node_b_fqdn -o IdentitiesOnly=yes" \
        " -o KbdInteractiveAuthentication=no" \
        " -o PasswordAuthentication=no" \
        " -o PreferredAuthentications=publickey" \
        " -o ServerAliveCountMax=2 -o ServerAliveInterval=2" \
        " -o StrictHostKeyChecking=yes -o UpdateHostKeys=no" \
        " -o UserKnownHostsFile=$known_hosts"
}

tree_digest() {
    local action28f_node_a_tree_root=$1

    (
        cd "$action28f_node_a_tree_root" || exit
        find . -printf '%P|%y|%U:%G:%m:%s\n' | LC_ALL=C sort
        find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}
manifest_paths_safe() {
    awk '
        length($0) == 0 { bad = 1; next }
        {
            hash = substr($0, 1, 64)
            separator = substr($0, 65, 2)
            path = substr($0, 67)
            if (length(hash) != 64 || hash !~ /^[0-9a-f]+$/ ||
                separator != "  " || path !~ /^[.][/][^[:cntrl:]]+$/ ||
                path ~ /(^|[/])[.][.]([/]|$)/ || path ~ /[/][/]/ ||
                path ~ /[/][.]([/]|$)/ || path ~ /[/]$/) bad = 1
        }
        END { exit bad ? 1 : 0 }
    ' "$1"
}
manifest_file_set_matches() {
    local action28f_node_a_release=$1
    local action28f_node_a_expected
    local action28f_node_a_observed
    local action28f_node_a_status=0

    action28f_node_a_expected=$(mktemp /tmp/action28f-expected.XXXXXX) || return 1
    action28f_node_a_observed=$(mktemp /tmp/action28f-observed.XXXXXX) || {
        rm -f -- "$action28f_node_a_expected"
        return 1
    }
    awk '{ print substr($0, 67) }' "$action28f_node_a_release/manifest.sha256" |
        LC_ALL=C sort -u >"$action28f_node_a_expected"
    (
        cd "$action28f_node_a_release" || exit
        find . -type f ! -path ./manifest.sha256 \
            ! -path ./.finalize-request ! -path ./.complete \
            ! -path ./.complete.pending -print | LC_ALL=C sort
    ) >"$action28f_node_a_observed"
    cmp -s "$action28f_node_a_expected" "$action28f_node_a_observed" ||
        action28f_node_a_status=$?
    rm -f -- "$action28f_node_a_expected" "$action28f_node_a_observed"
    return "$action28f_node_a_status"
}
manifest_hashes_valid() {
    (cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null)
}
expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_node_a \
        vrrp_state_regular vrrp_state_not_symlink vrrp_state_master \
        private_key_regular private_key_not_symlink private_key_metadata \
        known_hosts_regular known_hosts_not_symlink caddy_active lsyncd_inactive \
        caddy_lsyncd_inactive reconcile_path_inactive reconcile_service_inactive \
        outbound_root_directory outbound_root_not_symlink outbound_root_identity \
        outbound_child_count_exact retained_release_directory retained_release_not_symlink \
        retained_release_tree_exact retained_finalize_request_absent \
        retained_complete_regular retained_complete_empty retained_complete_pending_absent \
        candidate_directory candidate_not_symlink candidate_metadata_exact \
        candidate_release_manifest_regular candidate_release_manifest_not_symlink \
        candidate_release_manifest_hash_exact candidate_payload_manifest_regular \
        candidate_payload_manifest_not_symlink candidate_payload_manifest_hash_exact \
        candidate_tree_exact candidate_request_regular candidate_request_not_symlink \
        candidate_request_empty candidate_complete_absent candidate_pending_absent \
        candidate_revision_exact candidate_parent_exact candidate_source_node_a \
        candidate_manifest_schema candidate_manifest_paths_safe candidate_file_set_exact \
        candidate_hashes_valid candidate_symlinks_absent candidate_special_files_absent \
        candidate_hardlinks_absent candidate_directories_locked candidate_files_locked \
        current_release_directory current_release_symlink current_release_tree_exact
    if [[ "${1:-}" == transfer ]]; then
        printf '%s\n' rsync_stdout_bounded_safe rsync_stderr_bounded_safe rsync_status_zero
    fi
}
record_preflight() {
    record_command identity_root test "$(id -u)" -eq 0
    record_command working_directory_root test "$(pwd -P)" = /
    record_command hostname_node_a test "$(hostname)" = j1-svpihole0
    record_command vrrp_state_regular test -f /run/caddy-ha/vrrp-state
    record_command vrrp_state_not_symlink test ! -L /run/caddy-ha/vrrp-state
    record_command vrrp_state_master test \
        "$(cat /run/caddy-ha/vrrp-state 2>/dev/null || true)" = MASTER
    record_command private_key_regular test -f "$private_key"
    record_command private_key_not_symlink test ! -L "$private_key"
    record_command private_key_metadata test \
        "$(stat -c '%U:%G:%a' "$private_key" 2>/dev/null || true)" = \
        caddy-sync:caddy-sync:600
    record_command known_hosts_regular test -f "$known_hosts"
    record_command known_hosts_not_symlink test ! -L "$known_hosts"
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
    record_command outbound_root_directory test -d "$outbound_root"
    record_command outbound_root_not_symlink test ! -L "$outbound_root"
    record_command outbound_root_identity test \
        "$(stat -c '%u:%g:%a' "$outbound_root" 2>/dev/null || true)" = \
        "$expected_outbound_root_identity"
    record_command outbound_child_count_exact test \
        "$(find "$outbound_root" -mindepth 1 -maxdepth 1 -print | wc -l)" -eq 2
    record_command retained_release_directory test -d "$retained_release"
    record_command retained_release_not_symlink test ! -L "$retained_release"
    record_command retained_release_tree_exact test "$(tree_digest "$retained_release" 2>/dev/null || true)" = "$expected_retained_tree_sha256"
    record_command retained_finalize_request_absent test ! -e "$retained_release/.finalize-request"
    record_command retained_complete_regular test -f "$retained_release/.complete"
    record_command retained_complete_empty test ! -s "$retained_release/.complete"
    record_command retained_complete_pending_absent test ! -e "$retained_release/.complete.pending"
    record_command candidate_directory test -d "$candidate_release"
    record_command candidate_not_symlink test ! -L "$candidate_release"
    record_command candidate_metadata_exact test \
        "$(stat -c '%u:%g:%a:%s:%Y' "$candidate_release" 2>/dev/null || true)" = \
        "$candidate_metadata"
    record_command candidate_release_manifest_regular test -f "$candidate_release/release-manifest.json"
    record_command candidate_release_manifest_not_symlink test ! -L "$candidate_release/release-manifest.json"
    record_command candidate_release_manifest_hash_exact test \
        "$(file_hash "$candidate_release/release-manifest.json" 2>/dev/null || true)" = \
        "$candidate_release_manifest_sha256"
    record_command candidate_payload_manifest_regular test -f "$candidate_release/manifest.sha256"
    record_command candidate_payload_manifest_not_symlink test ! -L "$candidate_release/manifest.sha256"
    record_command candidate_payload_manifest_hash_exact test \
        "$(file_hash "$candidate_release/manifest.sha256" 2>/dev/null || true)" = \
        "$candidate_payload_manifest_sha256"
    record_command candidate_tree_exact test \
        "$(tree_digest "$candidate_release" 2>/dev/null || true)" = "$candidate_tree_sha256"
    record_command candidate_request_regular test -f "$candidate_release/.finalize-request"
    record_command candidate_request_not_symlink test ! -L "$candidate_release/.finalize-request"
    record_command candidate_request_empty test ! -s "$candidate_release/.finalize-request"
    record_command candidate_complete_absent test ! -e "$candidate_release/.complete"
    record_command candidate_pending_absent test ! -e "$candidate_release/.complete.pending"
    record_command candidate_revision_exact test \
        "$(jq -r '.revision // empty' "$candidate_release/release-manifest.json" 2>/dev/null || true)" = \
        "$candidate_revision"
    record_command candidate_parent_exact test \
        "$(jq -r '.parent_revision // empty' "$candidate_release/release-manifest.json" 2>/dev/null || true)" = \
        "$candidate_parent"
    record_command candidate_source_node_a test \
        "$(jq -r '.source_node // empty' "$candidate_release/release-manifest.json" 2>/dev/null || true)" = node-a
    record_command candidate_manifest_schema jq -e '
        (.revision | type == "string" and length > 0) and
        (.parent_revision | type == "string") and
        .source_node == "node-a" and
        (.created_at | type == "string" and length > 0)
    ' "$candidate_release/release-manifest.json"
    record_command candidate_manifest_paths_safe \
        manifest_paths_safe "$candidate_release/manifest.sha256"
    record_command candidate_file_set_exact manifest_file_set_matches "$candidate_release"
    record_command candidate_hashes_valid manifest_hashes_valid "$candidate_release"
    record_command candidate_symlinks_absent test \
        -z "$(find "$candidate_release" -type l -print -quit)"
    record_command candidate_special_files_absent test \
        -z "$(find "$candidate_release" ! -type d ! -type f -print -quit)"
    record_command candidate_hardlinks_absent test \
        -z "$(find "$candidate_release" -type f -links +1 -print -quit)"
    record_command candidate_directories_locked test \
        -z "$(find "$candidate_release" -type d ! -perm 0550 -print -quit)"
    record_command candidate_files_locked test \
        -z "$(find "$candidate_release" -type f ! -perm 0440 -print -quit)"
    record_command current_release_directory test -d "$current_release"
    record_command current_release_symlink test -L "$current_release"
    record_command current_release_tree_exact test \
        "$(tree_digest "$current_release" 2>/dev/null || true)" = "$expected_current_tree_sha256"
}

if [[ "${1:-}" == --expected-checks && $# -eq 2 ]]; then
    [[ "$2" =~ ^(preflight|transfer)$ ]] || exit 64
    expected_checks "$2"
    exit 0
fi
if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$candidate_revision" == 20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63 ]]
    [[ "$candidate_release" == "$outbound_root/$candidate_revision" ]]
    [[ "$(remote_shell_value)" == *"-b $node_a_ipv6"* ]]
    [[ "$(remote_shell_value)" == *"-i $private_key"* ]]
    [[ "$(remote_shell_value)" == *"IdentitiesOnly=yes"* ]]
    printf '%s_self_test_complete=true\n' "$prefix"
    exit 0
fi

if [[ $# -ne 1 || ! "$1" =~ ^--(preflight|transfer)$ ]]; then
    printf 'Usage: %s --preflight|--transfer\n' "${0##*/}" >&2
    exit 64
fi
readonly phase=${1#--}
record_preflight

revision=$candidate_revision
parent_revision=$candidate_parent
manifest_sha256=$candidate_payload_manifest_sha256
publication_started=false
release_transfer_started=false

if [[ "$phase" == transfer && "$checks_failed" -eq 0 ]]; then
    capture_directory=$(mktemp -d /tmp/caddy-action28f-node-a.XXXXXX)
    readonly capture_directory
    cleanup_capture() {
        # shellcheck disable=SC2317
        rm -rf -- "$capture_directory"
    }
    trap cleanup_capture EXIT
    : >"$capture_directory/rsync.out"
    : >"$capture_directory/rsync.err"
    chmod 0600 "$capture_directory/rsync.out" "$capture_directory/rsync.err"
    remote_shell=$(remote_shell_value)
    release_transfer_started=true
    rsync_status=0
    runuser -u caddy-sync -- timeout --signal=TERM --kill-after=5s 60s \
        rsync --archive --checksum --delay-updates --exclude=.complete \
        --itemize-changes --no-owner --no-group --rsh="$remote_shell" \
        "$candidate_release" "caddy-sync@$node_b_fqdn:/" \
        >"$capture_directory/rsync.out" 2>"$capture_directory/rsync.err" ||
        rsync_status=$?
    if safe_stream "$capture_directory/rsync.out"; then
        emit_stream rsync_stdout "$capture_directory/rsync.out"
        record_result rsync_stdout_bounded_safe true
    else
        record_result rsync_stdout_bounded_safe false
    fi
    if safe_stream "$capture_directory/rsync.err"; then
        emit_stream rsync_stderr "$capture_directory/rsync.err"
        record_result rsync_stderr_bounded_safe true
    else
        record_result rsync_stderr_bounded_safe false
    fi
    record_command rsync_status_zero test "$rsync_status" -eq 0
fi

printf '%s_value_phase=%s\n' "$prefix" "$phase"
printf '%s_value_revision=%s\n' "$prefix" "$revision"
printf '%s_value_parent_revision=%s\n' "$prefix" "$parent_revision"
printf '%s_value_manifest_sha256=%s\n' "$prefix" "$manifest_sha256"
printf '%s_checks_total=%s\n' "$prefix" "$checks_total"
printf '%s_checks_passed=%s\n' "$prefix" "$checks_passed"
printf '%s_checks_failed=%s\n' "$prefix" "$checks_failed"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_publication_started=%s\n' "$prefix" "$publication_started"
printf '%s_release_transfer_started=%s\n' "$prefix" "$release_transfer_started"
printf '%s_lsyncd_enabled=false\n' "$prefix"
printf '%s_reconciliation_executed=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_remote_delete_executed=false\n' "$prefix"

if [[ "$checks_failed" -ne 0 ]]; then
    printf '%s_acceptance=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_acceptance=true\n' "$prefix"
