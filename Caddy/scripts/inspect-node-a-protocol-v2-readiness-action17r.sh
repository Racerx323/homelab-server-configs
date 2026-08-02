#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_17r_node_a
readonly revision=action17p-node-a-to-node-b-bootstrap
readonly parent_revision=action15-health-follow-redirects
readonly release=/var/lib/caddy-sync/outbound/action17p-node-a-to-node-b-bootstrap
readonly ssh_directory=/var/lib/caddy-sync/.ssh
readonly private_key="$ssh_directory/id_ed25519"
readonly public_key="$private_key.pub"
readonly known_hosts="$ssh_directory/known_hosts"
readonly peer_fqdn=pihole00.local.theama.co
readonly node_ipv4=10.1.0.53
readonly node_ipv6=fd36:5aa8:6971:1::53
readonly peer_ipv4=10.1.0.54
readonly peer_ipv6=fd36:5aa8:6971:1::54
readonly expected_key_fingerprint='SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0'
readonly expected_host_fingerprint='SHA256:eDdqL/bS/EuVysKQ7yxJ6lpjJWf2PcymtfPwMlzacbo'
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

manifest_hashes_valid() {
    (
        cd "$release" || exit
        sha256sum --strict --check manifest.sha256 >/dev/null
    )
}

key_fingerprint() {
    ssh-keygen -lf "$public_key" -E sha256 | awk '{ print $2 }'
}

known_host_fingerprint() {
    ssh-keygen -F "$peer_fqdn" -f "$known_hosts" |
        sed '/^#/d' |
        ssh-keygen -lf - -E sha256 |
        awk 'NR == 1 { print $2 }'
}

ssh_option_exact() {
    local option_name=$1
    local option_value=$2
    local option_file=$3

    awk -v name="$option_name" -v value="$option_value" \
        '$1 == name && $2 == value { found = 1 } END { exit found ? 0 : 1 }' \
        "$option_file"
}

stable_state_snapshot() {
    stat -c '%n|%U:%G:%a:%s:%i' \
        /var/lib/caddy-sync \
        /var/lib/caddy-sync/outbound \
        "$release" \
        "$release/manifest.sha256" \
        "$release/.complete" \
        "$ssh_directory" \
        "$private_key" \
        "$public_key" \
        "$known_hosts" \
        /etc/caddy/current
    sha256sum \
        "$release/manifest.sha256" \
        "$private_key" \
        "$public_key" \
        "$known_hosts"
    find "$release" -printf '%P|%y|%U:%G:%m:%s:%i\n' | LC_ALL=C sort
    find "$release" -type f -print0 |
        LC_ALL=C sort -z |
        xargs -0 -r sha256sum
    readlink /etc/caddy/current
    readlink -e /etc/caddy/current
    for snapshot_unit in \
        caddy.service lighttpd.service lsyncd.service caddy-lsyncd.service; do
        systemctl show "$snapshot_unit" --no-pager \
            -p LoadState -p ActiveState -p SubState -p MainPID -p NRestarts
        printf 'unit_file_state=%s\n' \
            "$(systemctl is-enabled "$snapshot_unit" 2>/dev/null || true)"
    done
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$revision" == action17p-node-a-to-node-b-bootstrap ]]
    [[ "$node_ipv4" == 10.1.0.53 ]]
    [[ "$node_ipv6" == fd36:5aa8:6971:1::53 ]]
    [[ "$peer_ipv4" == 10.1.0.54 ]]
    [[ "$peer_ipv6" == fd36:5aa8:6971:1::54 ]]
    [[ "$expected_payload_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$expected_manifest_sha256" =~ ^[0-9a-f]{64}$ ]]
    printf 'action_17r_node_a_inspector_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

work_directory=$(mktemp -d /tmp/caddy-action17r-node-a.XXXXXX)
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
readonly ipv4_options="$work_directory/ssh-ipv4.options"
readonly ipv4_error="$work_directory/ssh-ipv4.err"
readonly ipv6_options="$work_directory/ssh-ipv6.options"
readonly ipv6_error="$work_directory/ssh-ipv6.err"

record_command identity_root test "$(id -u)" -eq 0
record_command working_directory_root test "$(pwd -P)" = /
record_command hostname_node_a test "$(hostname)" = j1-svpihole0
record_command architecture_arm64 test "$(dpkg --print-architecture)" = arm64
record_command node_ipv4_present \
    grep -Fq "$node_ipv4/22" < <(ip -o -4 address show dev eth0)
record_command node_ipv6_present \
    grep -Fq "$node_ipv6/64" < <(ip -o -6 address show dev eth0)
record_command peer_hosts_ipv4_exact grep -Fxq "$peer_ipv4 $peer_fqdn" /etc/hosts
record_command peer_hosts_ipv6_exact grep -Fxq "$peer_ipv6 $peer_fqdn" /etc/hosts
record_command release_directory_regular test -d "$release"
record_command release_not_symlink test ! -L "$release"
record_command release_metadata \
    test "$(stat -c '%U:%G:%a' "$release" 2>/dev/null || true)" = \
    caddy-sync:caddy-sync:550
record_command release_revision_exact \
    test "$(jq -r '.revision // empty' "$release/release-manifest.json")" = \
    "$revision"
record_command release_parent_exact \
    test "$(jq -r '.parent_revision // empty' "$release/release-manifest.json")" = \
    "$parent_revision"
record_command release_source_exact \
    test "$(jq -r '.source_node // empty' "$release/release-manifest.json")" = \
    node-a
record_command release_symlinks_absent \
    test -z "$(find "$release" -type l -print -quit)"
record_command release_special_files_absent \
    test -z "$(find "$release" ! -type d ! -type f -print -quit)"
record_command release_manifest_hashes_valid manifest_hashes_valid
record_command release_payload_hash_exact \
    test "$(payload_digest)" = "$expected_payload_sha256"
record_command release_manifest_hash_exact \
    test "$(file_hash "$release/manifest.sha256")" = \
    "$expected_manifest_sha256"
record_command legacy_complete_regular test -f "$release/.complete"
record_command legacy_complete_not_symlink test ! -L "$release/.complete"
record_command legacy_complete_empty test ! -s "$release/.complete"
record_command finalize_request_absent test ! -e "$release/.finalize-request"
record_command finalize_request_not_symlink test ! -L "$release/.finalize-request"
record_command complete_pending_absent test ! -e "$release/.complete.pending"
record_command complete_pending_not_symlink test ! -L "$release/.complete.pending"
record_command release_not_writable_by_sync \
    runuser -u caddy-sync -- test ! -w "$release"
record_command private_key_regular test -f "$private_key"
record_command private_key_not_symlink test ! -L "$private_key"
record_command private_key_metadata \
    test "$(stat -c '%U:%G:%a' "$private_key")" = caddy-sync:caddy-sync:600
record_command public_key_regular test -f "$public_key"
record_command public_key_fingerprint \
    test "$(key_fingerprint)" = "$expected_key_fingerprint"
record_command known_hosts_regular test -f "$known_hosts"
record_command known_hosts_metadata \
    test "$(stat -c '%U:%G:%a' "$known_hosts")" = caddy-sync:caddy-sync:600
record_command known_host_fingerprint \
    test "$(known_host_fingerprint)" = "$expected_host_fingerprint"

before_status=0
stable_state_snapshot >"$before_state" 2>"$before_error" || before_status=$?
readonly before_status
record_command before_state_status_zero test "$before_status" -eq 0
record_command before_state_stderr_empty test ! -s "$before_error"
before_state_sha256=$(file_hash "$before_state")
readonly before_state_sha256

ipv4_status=0
runuser -u caddy-sync -- ssh -G -F /dev/null -4 \
    -b "$node_ipv4" -i "$private_key" \
    -o BatchMode=yes -o ClearAllForwardings=yes \
    -o "HostKeyAlias=$peer_fqdn" -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts" \
    "caddy-sync@$peer_fqdn" >"$ipv4_options" 2>"$ipv4_error" || ipv4_status=$?
readonly ipv4_status
record_command ipv4_ssh_g_status_zero test "$ipv4_status" -eq 0
record_command ipv4_ssh_g_stderr_empty test ! -s "$ipv4_error"
record_command ipv4_address_family_exact \
    ssh_option_exact addressfamily inet "$ipv4_options"
record_command ipv4_bind_address_exact \
    ssh_option_exact bindaddress "$node_ipv4" "$ipv4_options"
record_command ipv4_hostname_exact \
    ssh_option_exact hostname "$peer_fqdn" "$ipv4_options"
record_command ipv4_host_key_alias_exact \
    ssh_option_exact hostkeyalias "$peer_fqdn" "$ipv4_options"

ipv6_status=0
runuser -u caddy-sync -- ssh -G -F /dev/null -6 \
    -b "$node_ipv6" -i "$private_key" \
    -o BatchMode=yes -o ClearAllForwardings=yes \
    -o "HostKeyAlias=$peer_fqdn" -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts" \
    "caddy-sync@$peer_fqdn" >"$ipv6_options" 2>"$ipv6_error" || ipv6_status=$?
readonly ipv6_status
record_command ipv6_ssh_g_status_zero test "$ipv6_status" -eq 0
record_command ipv6_ssh_g_stderr_empty test ! -s "$ipv6_error"
record_command ipv6_address_family_exact \
    ssh_option_exact addressfamily inet6 "$ipv6_options"
record_command ipv6_bind_address_exact \
    ssh_option_exact bindaddress "$node_ipv6" "$ipv6_options"
record_command ipv6_hostname_exact \
    ssh_option_exact hostname "$peer_fqdn" "$ipv6_options"
record_command ipv6_host_key_alias_exact \
    ssh_option_exact hostkeyalias "$peer_fqdn" "$ipv6_options"

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
printf '%s_value_source_state=legacy_complete_requires_v2_finalize_request\n' "$prefix"
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
