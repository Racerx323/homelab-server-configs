#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly ssh_dir=/var/lib/caddy-sync/.ssh
readonly private_key="$ssh_dir/id_ed25519"
readonly public_key="$private_key.pub"
readonly known_hosts="$ssh_dir/known_hosts"
readonly environment_file=/etc/default/caddy-ha
readonly node_a_ipv6=fd36:5aa8:6971:1::53
readonly node_b_ipv6=fd36:5aa8:6971:1::54
readonly node_b_fqdn=pihole00.local.theama.co
readonly interface=eth0
readonly denied_command=caddy-action17c-c-a-denied-probe
readonly denied_message='Only the rsync server protocol is permitted.'
readonly expected_key_fingerprint='SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0'
readonly expected_host_fingerprint='SHA256:eDdqL/bS/EuVysKQ7yxJ6lpjJWf2PcymtfPwMlzacbo'

checks_total=0
checks_passed=0
checks_failed=0

record_check() {
    local label=$1

    shift
    checks_total=$((checks_total + 1))
    if "$@" >/dev/null 2>&1; then
        printf 'prestate_check_%s=true\n' "$label"
        checks_passed=$((checks_passed + 1))
    else
        printf 'prestate_check_%s=false\n' "$label"
        checks_failed=$((checks_failed + 1))
    fi
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

known_host_fingerprint() {
    ssh-keygen -F "$node_b_fqdn" -f "$known_hosts" |
        sed '/^#/d' |
        ssh-keygen -lf - -E sha256 |
        awk 'NR == 1 { print $2 }'
}

key_fingerprint() {
    ssh-keygen -lf "$public_key" -E sha256 |
        awk '{ print $2 }'
}

relevant_state() {
    stat -c '%n|%U:%G:%a:%s:%i' \
        /var/lib/caddy-sync \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/quarantine \
        "$ssh_dir" \
        "$private_key" \
        "$public_key" \
        "$known_hosts" \
        "$environment_file"
    sha256sum \
        "$private_key" \
        "$public_key" \
        "$known_hosts" \
        "$environment_file"
    find \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/quarantine \
        -printf '%p|%y|%U:%G:%m:%s:%i\n' |
        sort
    for unit in ssh.service lsyncd.service caddy-lsyncd.service; do
        systemctl show "$unit" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts
        printf 'unit_file_state=%s\n' \
            "$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    done
}

classify_ssh_error() {
    local status=$1
    local error_file=$2

    if [[ "$status" -eq 126 ]] &&
        grep -Fq "$denied_message" "$error_file"; then
        printf 'forced_receiver_rejection\n'
    elif grep -Fq 'Could not resolve hostname' "$error_file"; then
        printf 'name_resolution_failed\n'
    elif grep -Fq 'Cannot assign requested address' "$error_file"; then
        printf 'bind_address_unavailable\n'
    elif grep -Fq 'Network is unreachable' "$error_file"; then
        printf 'network_unreachable\n'
    elif grep -Fq 'No route to host' "$error_file"; then
        printf 'no_route_to_host\n'
    elif grep -Fq 'Connection timed out' "$error_file"; then
        printf 'connection_timed_out\n'
    elif grep -Fq 'Connection refused' "$error_file"; then
        printf 'connection_refused\n'
    elif grep -Fq 'REMOTE HOST IDENTIFICATION HAS CHANGED' "$error_file"; then
        printf 'host_key_mismatch\n'
    elif grep -Fq 'Permission denied' "$error_file"; then
        printf 'publickey_denied\n'
    elif grep -Eq 'Connection closed|Connection reset' "$error_file"; then
        printf 'connection_closed\n'
    else
        printf 'unclassified\n'
    fi
}

debug_marker() {
    local pattern=$1
    local error_file=$2

    if grep -Fq "$pattern" "$error_file"; then
        printf 'true\n'
    else
        printf 'false\n'
    fi
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$node_a_ipv6" == fd36:5aa8:6971:1::53 ]]
    [[ "$node_b_ipv6" == fd36:5aa8:6971:1::54 ]]
    [[ "$node_b_fqdn" == pihole00.local.theama.co ]]
    [[ "$expected_key_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$expected_host_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$denied_command" != rsync\ --server\ * ]]
    printf 'action_17c_c_a_node_a_diagnostic_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

work_dir=$(mktemp -d /tmp/caddy-action17c-c-a.XXXXXX)
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

record_check identity test "$(id -un)" = caddy-sync
record_check working_directory test "$(pwd -P)" = /
record_check hostname test "$(hostname)" = j1-svpihole0
record_check architecture test "$(dpkg --print-architecture)" = arm64
record_check environment_file test -r "$environment_file"
record_check environment_role grep -Fxq 'NODE_ROLE=node-a' "$environment_file"
record_check environment_node_ipv6 \
    grep -Fxq "NODE_IPV6=$node_a_ipv6" "$environment_file"
record_check environment_peer_ipv6 \
    grep -Fxq "PEER_IPV6=$node_b_ipv6" "$environment_file"
record_check environment_sync_target \
    grep -Fxq "SYNC_TARGET=$node_b_fqdn" "$environment_file"
record_check private_key_regular test -f "$private_key"
record_check private_key_not_symlink test ! -L "$private_key"
record_check public_key_regular test -f "$public_key"
record_check known_hosts_regular test -f "$known_hosts"
record_check ssh_directory_mode \
    test "$(stat -c '%U:%G:%a' "$ssh_dir" 2>/dev/null || true)" = \
    caddy-sync:caddy-sync:700
record_check private_key_mode \
    test "$(stat -c '%U:%G:%a' "$private_key" 2>/dev/null || true)" = \
    caddy-sync:caddy-sync:600
record_check known_hosts_mode \
    test "$(stat -c '%U:%G:%a' "$known_hosts" 2>/dev/null || true)" = \
    caddy-sync:caddy-sync:600
record_check public_key_fingerprint \
    test "$(key_fingerprint 2>/dev/null || true)" = "$expected_key_fingerprint"
record_check known_host_fingerprint \
    test "$(known_host_fingerprint 2>/dev/null || true)" = \
    "$expected_host_fingerprint"
record_check stable_ipv6_present \
    grep -Fq "$node_a_ipv6/64" \
    < <(ip -o -6 address show dev "$interface" 2>/dev/null)

printf 'prestate_checks_total=%s\n' "$checks_total"
printf 'prestate_checks_passed=%s\n' "$checks_passed"
printf 'prestate_checks_failed=%s\n' "$checks_failed"
printf 'action_17c_c_a_prestate_collection_complete=true\n'

before_state_status=0
relevant_state >"$work_dir/state-before" 2>"$work_dir/state-before.err" ||
    before_state_status=$?
printf 'before_state_status=%s\n' "$before_state_status"
printf 'before_state_stderr_sha256=%s\n' \
    "$(file_hash "$work_dir/state-before.err")"
if [[ "$before_state_status" -eq 0 ]]; then
    printf 'before_state_sha256=%s\n' "$(file_hash "$work_dir/state-before")"
else
    printf 'before_state_sha256=unavailable\n'
fi

probe_output="$work_dir/probe.out"
probe_error="$work_dir/probe.err"
probe_status=0
ssh -6 -n -T -vv \
    -F /dev/null \
    -b "$node_a_ipv6" \
    -i "$private_key" \
    -o BatchMode=yes \
    -o ClearAllForwardings=yes \
    -o ConnectTimeout=5 \
    -o GlobalKnownHostsFile=/dev/null \
    -o "HostKeyAlias=$node_b_fqdn" \
    -o IdentitiesOnly=yes \
    -o KbdInteractiveAuthentication=no \
    -o PasswordAuthentication=no \
    -o PreferredAuthentications=publickey \
    -o ServerAliveCountMax=2 \
    -o ServerAliveInterval=2 \
    -o StrictHostKeyChecking=yes \
    -o UpdateHostKeys=no \
    -o "UserKnownHostsFile=$known_hosts" \
    "caddy-sync@$node_b_fqdn" \
    "$denied_command" \
    >"$probe_output" 2>"$probe_error" || probe_status=$?

printf 'source_bound_ssh_status=%s\n' "$probe_status"
printf 'source_bound_ssh_error_class=%s\n' \
    "$(classify_ssh_error "$probe_status" "$probe_error")"
printf 'source_bound_ssh_connecting=%s\n' \
    "$(debug_marker 'Connecting to ' "$probe_error")"
printf 'source_bound_ssh_connection_established=%s\n' \
    "$(debug_marker 'Connection established.' "$probe_error")"
printf 'source_bound_ssh_host_key_verified=%s\n' \
    "$(debug_marker "Host '$node_b_fqdn' is known and matches" "$probe_error")"
printf 'source_bound_ssh_public_key_offered=%s\n' \
    "$(debug_marker 'Offering public key:' "$probe_error")"
printf 'source_bound_ssh_server_accepted_key=%s\n' \
    "$(debug_marker 'Server accepts key:' "$probe_error")"
printf 'source_bound_ssh_authenticated=%s\n' \
    "$(debug_marker 'Authenticated to ' "$probe_error")"
printf 'source_bound_forced_receiver_message=%s\n' \
    "$(debug_marker "$denied_message" "$probe_error")"
printf 'source_bound_ssh_stdout_empty=%s\n' \
    "$([[ ! -s "$probe_output" ]] && printf true || printf false)"
printf 'source_bound_ssh_stdout_sha256=%s\n' "$(file_hash "$probe_output")"
printf 'source_bound_ssh_stderr_sha256=%s\n' "$(file_hash "$probe_error")"
printf 'action_17c_c_a_direct_ssh_collection_complete=true\n'

after_state_status=0
relevant_state >"$work_dir/state-after" 2>"$work_dir/state-after.err" ||
    after_state_status=$?
printf 'after_state_status=%s\n' "$after_state_status"
printf 'after_state_stderr_sha256=%s\n' \
    "$(file_hash "$work_dir/state-after.err")"
if [[ "$after_state_status" -eq 0 ]]; then
    printf 'after_state_sha256=%s\n' "$(file_hash "$work_dir/state-after")"
else
    printf 'after_state_sha256=unavailable\n'
fi
if [[ "$before_state_status" -eq 0 &&
    "$after_state_status" -eq 0 ]] &&
    cmp --silent "$work_dir/state-before" "$work_dir/state-after"; then
    printf 'node_a_relevant_state_unchanged=true\n'
else
    printf 'node_a_relevant_state_unchanged=false\n'
fi
printf 'release_payload_transferred=false\n'
printf 'rsync_invoked=false\n'
printf 'service_mutations=false\n'

cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf 'action_17c_c_a_node_a_cleanup_complete=true\n'
printf 'action_17c_c_a_node_a_diagnostic_complete=true\n'
