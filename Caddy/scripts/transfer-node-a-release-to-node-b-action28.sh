#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28_node_a
readonly publisher=/usr/local/libexec/publish-release-v2.sh
readonly publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669
readonly source_release=/etc/caddy/current
readonly node_a_ipv6=fd36:5aa8:6971:1::53
readonly node_b_fqdn=pihole00.local.theama.co
readonly private_key=/var/lib/caddy-sync/.ssh/id_ed25519
readonly known_hosts=/var/lib/caddy-sync/.ssh/known_hosts
readonly outbound_root=/var/lib/caddy-sync/outbound
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

record_preflight() {
    record_command identity_root test "$(id -u)" -eq 0
    record_command working_directory_root test "$(pwd -P)" = /
    record_command hostname_node_a test "$(hostname)" = j1-svpihole0
    record_command publisher_regular test -f "$publisher"
    record_command publisher_not_symlink test ! -L "$publisher"
    record_command publisher_executable test -x "$publisher"
    record_command publisher_hash_exact test \
        "$(file_hash "$publisher" 2>/dev/null || true)" = "$publisher_sha256"
    record_command source_release_directory test -d "$source_release"
    record_command source_release_symlink test -L "$source_release"
    record_command source_manifest_regular test -f "$source_release/release-manifest.json"
    record_command source_complete_regular test -f "$source_release/.complete"
    record_command source_complete_empty test ! -s "$source_release/.complete"
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
    record_command outbound_root_regular test -d "$outbound_root"
    record_command outbound_root_not_symlink test ! -L "$outbound_root"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$publisher_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$(remote_shell_value)" == *"-b $node_a_ipv6"* ]]
    [[ "$(remote_shell_value)" == *"-i $private_key"* ]]
    [[ "$(remote_shell_value)" == *"IdentitiesOnly=yes"* ]]
    [[ "$source_release" == /etc/caddy/current ]]
    printf '%s_self_test_complete=true\n' "$prefix"
    exit 0
fi

if [[ $# -ne 1 || ! "$1" =~ ^--(preflight|transfer)$ ]]; then
    printf 'Usage: %s --preflight|--transfer\n' "${0##*/}" >&2
    exit 64
fi
readonly phase=${1#--}
record_preflight

revision=unavailable
parent_revision=unavailable
manifest_sha256=unavailable
publication_started=false
release_transfer_started=false

if [[ "$phase" == transfer && "$checks_failed" -eq 0 ]]; then
    capture_directory=$(mktemp -d /tmp/caddy-action28-node-a.XXXXXX)
    readonly capture_directory
    cleanup_capture() {
        # shellcheck disable=SC2317
        rm -rf -- "$capture_directory"
    }
    trap cleanup_capture EXIT
    : >"$capture_directory/publish.out"
    : >"$capture_directory/publish.err"
    chmod 0600 "$capture_directory/publish.out" "$capture_directory/publish.err"
    publication_started=true
    publish_status=0
    "$publisher" --source "$source_release" --node-role node-a \
        >"$capture_directory/publish.out" 2>"$capture_directory/publish.err" ||
        publish_status=$?
    emit_stream publisher_stdout "$capture_directory/publish.out"
    emit_stream publisher_stderr "$capture_directory/publish.err"
    record_command publisher_status_zero test "$publish_status" -eq 0
    if [[ "$publish_status" -eq 0 ]]; then
        revision=$(sed -n \
            's/^Published protocol-v2 release \([A-Za-z0-9][A-Za-z0-9._-]*\) for receiver validation\.$/\1/p' \
            "$capture_directory/publish.out")
        record_command publisher_revision_single test \
            "$(printf '%s\n' "$revision" | grep -Ec '^[A-Za-z0-9][A-Za-z0-9._-]*$')" -eq 1
    fi
    release_dir="$outbound_root/$revision"
    if [[ "$checks_failed" -eq 0 ]]; then
        record_command release_regular test -d "$release_dir"
        record_command release_not_symlink test ! -L "$release_dir"
        record_command release_request_regular test -f "$release_dir/.finalize-request"
        record_command release_request_empty test ! -s "$release_dir/.finalize-request"
        record_command release_complete_absent test ! -e "$release_dir/.complete"
        record_command release_source_node_a test \
            "$(jq -r '.source_node // empty' "$release_dir/release-manifest.json")" = node-a
        parent_revision=$(jq -r '.parent_revision // empty' \
            "$release_dir/release-manifest.json")
        manifest_sha256=$(file_hash "$release_dir/manifest.sha256")
    fi
    if [[ "$checks_failed" -eq 0 ]]; then
        : >"$capture_directory/rsync.out"
        : >"$capture_directory/rsync.err"
        chmod 0600 "$capture_directory/rsync.out" "$capture_directory/rsync.err"
        remote_shell=$(remote_shell_value)
        release_transfer_started=true
        rsync_status=0
        runuser -u caddy-sync -- timeout --signal=TERM --kill-after=5s 60s \
            rsync --archive --checksum --delay-updates --exclude=.complete \
            --itemize-changes --no-owner --no-group --rsh="$remote_shell" \
            "$release_dir" "caddy-sync@$node_b_fqdn:/" \
            >"$capture_directory/rsync.out" 2>"$capture_directory/rsync.err" ||
            rsync_status=$?
        emit_stream rsync_stdout "$capture_directory/rsync.out"
        emit_stream rsync_stderr "$capture_directory/rsync.err"
        record_command rsync_status_zero test "$rsync_status" -eq 0
    fi
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
