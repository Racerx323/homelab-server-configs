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
readonly node_a_ipv6=fd36:5aa8:6971:1::53
readonly node_b_ipv6=fd36:5aa8:6971:1::54
readonly node_b_host_alias=pihole00.local.theama.co
readonly interface=eth0
readonly denied_command=caddy-action17c-denied-probe
readonly denied_message='Only the rsync server protocol is permitted.'
readonly expected_key_fingerprint='SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0'
readonly expected_host_fingerprint='SHA256:eDdqL/bS/EuVysKQ7yxJ6lpjJWf2PcymtfPwMlzacbo'

known_host_fingerprint() {
    ssh-keygen -F "$node_b_host_alias" -f "$known_hosts" |
        sed '/^#/d' |
        ssh-keygen -lf - -E sha256 |
        awk 'NR == 1 { print $2 }'
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
        /etc/default/caddy-ha
    sha256sum \
        "$private_key" \
        "$public_key" \
        "$known_hosts" \
        /etc/default/caddy-ha
    find \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/quarantine \
        -printf '%p|%y|%U:%G:%m:%s:%i\n' |
        sort
    systemctl show ssh.service --no-pager \
        -p ActiveState -p SubState -p MainPID -p NRestarts
}

classify_ssh_error() {
    local status=$1
    local error_file=$2

    if [[ "$status" -eq 126 ]] &&
        grep -Fxq "$denied_message" "$error_file"; then
        printf 'forced_receiver_rejection\n'
    elif grep -Fq 'Network is unreachable' "$error_file"; then
        printf 'network_unreachable\n'
    elif grep -Fq 'No route to host' "$error_file"; then
        printf 'no_route_to_host\n'
    elif grep -Fq 'Connection timed out' "$error_file"; then
        printf 'connection_timed_out\n'
    elif grep -Fq 'Connection refused' "$error_file"; then
        printf 'connection_refused\n'
    elif grep -Fq 'Permission denied (publickey)' "$error_file"; then
        printf 'publickey_denied\n'
    elif grep -Fq 'REMOTE HOST IDENTIFICATION HAS CHANGED' "$error_file"; then
        printf 'host_key_mismatch\n'
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
    [[ "$node_b_host_alias" == pihole00.local.theama.co ]]
    [[ "$expected_key_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$expected_host_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$denied_command" != rsync\ --server\ * ]]
    printf 'action_17c_a_node_a_diagnostic_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(id -u)" -eq 0 ]]
[[ "$(hostname)" == j1-svpihole0 ]]
[[ "$(dpkg --print-architecture)" == arm64 ]]
[[ -f "$private_key" && ! -L "$private_key" ]]
[[ -f "$public_key" && ! -L "$public_key" ]]
[[ -f "$known_hosts" && ! -L "$known_hosts" ]]
[[ "$(stat -c '%U:%G:%a' "$private_key")" == caddy-sync:caddy-sync:600 ]]
[[ "$(stat -c '%U:%G:%a' "$known_hosts")" == caddy-sync:caddy-sync:600 ]]
[[ "$(ssh-keygen -lf "$public_key" -E sha256 |
    awk '{ print $2 }')" == "$expected_key_fingerprint" ]]
[[ "$(known_host_fingerprint)" == "$expected_host_fingerprint" ]]

state_before=$(relevant_state | sha256sum | awk '{ print $1 }')
readonly state_before
printf 'action_17c_a_node_a_preflight_complete=true\n'

work_dir=$(mktemp -d /run/caddy-action17c-a-ipv6.XXXXXX)
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

ipv6_address_present=false
ipv6_route_status=0
ipv6_route_source_matches=false
ipv6_route_device_matches=false
icmp_status=0
ssh_status=0

if ip -o -6 address show dev "$interface" |
    grep -Fq "$node_a_ipv6/64"; then
    ipv6_address_present=true
fi

route_record=$(ip -6 route get "$node_b_ipv6" 2>/dev/null) ||
    ipv6_route_status=$?
if [[ "$ipv6_route_status" -eq 0 ]]; then
    if grep -Eq "(^|[[:space:]])src[[:space:]]+$node_a_ipv6([[:space:]]|$)" \
        <<<"$route_record"; then
        ipv6_route_source_matches=true
    fi
    if grep -Eq "(^|[[:space:]])dev[[:space:]]+$interface([[:space:]]|$)" \
        <<<"$route_record"; then
        ipv6_route_device_matches=true
    fi
fi

runuser -u caddy-sync -- \
    ping -6 -n -c 1 -W 2 "$node_b_ipv6" \
    >"$work_dir/ping.out" 2>"$work_dir/ping.err" || icmp_status=$?

runuser -u caddy-sync -- \
    ssh -6 -n -T -vv \
    -F /dev/null \
    -i "$private_key" \
    -o BatchMode=yes \
    -o IdentitiesOnly=yes \
    -o PreferredAuthentications=publickey \
    -o PasswordAuthentication=no \
    -o KbdInteractiveAuthentication=no \
    -o StrictHostKeyChecking=yes \
    -o UpdateHostKeys=no \
    -o GlobalKnownHostsFile=/dev/null \
    -o "UserKnownHostsFile=$known_hosts" \
    -o "HostKeyAlias=$node_b_host_alias" \
    -o ClearAllForwardings=yes \
    -o ConnectTimeout=5 \
    -o ServerAliveInterval=2 \
    -o ServerAliveCountMax=2 \
    "caddy-sync@$node_b_ipv6" \
    "$denied_command" \
    >"$work_dir/ssh.out" 2>"$work_dir/ssh.err" || ssh_status=$?

ssh_error_class=$(classify_ssh_error "$ssh_status" "$work_dir/ssh.err")
readonly ssh_error_class
neighbor_state=$(
    ip -6 neigh show to "$node_b_ipv6" dev "$interface" |
        awk 'NR == 1 { print $NF }'
)
neighbor_state=${neighbor_state:-absent}
case "$neighbor_state" in
    REACHABLE | STALE | DELAY | PROBE | INCOMPLETE | FAILED | NOARP | PERMANENT | absent) ;;
    *) neighbor_state=other ;;
esac

printf 'node_a_ipv6_address_present=%s\n' "$ipv6_address_present"
printf 'node_a_ipv6_route_status=%s\n' "$ipv6_route_status"
printf 'node_a_ipv6_route_source_matches=%s\n' \
    "$ipv6_route_source_matches"
printf 'node_a_ipv6_route_device_matches=%s\n' \
    "$ipv6_route_device_matches"
printf 'node_a_ipv6_neighbor_state=%s\n' "$neighbor_state"
printf 'node_a_ipv6_icmp_status=%s\n' "$icmp_status"
printf 'node_a_ipv6_ssh_status=%s\n' "$ssh_status"
printf 'node_a_ipv6_ssh_error_class=%s\n' "$ssh_error_class"
printf 'node_a_ipv6_ssh_connecting=%s\n' \
    "$(debug_marker "Connecting to $node_b_ipv6" "$work_dir/ssh.err")"
printf 'node_a_ipv6_ssh_connection_established=%s\n' \
    "$(debug_marker 'Connection established.' "$work_dir/ssh.err")"
printf 'node_a_ipv6_ssh_host_key_verified=%s\n' \
    "$(debug_marker "Host '$node_b_host_alias' is known and matches" \
        "$work_dir/ssh.err")"
printf 'node_a_ipv6_ssh_public_key_offered=%s\n' \
    "$(debug_marker 'Offering public key:' "$work_dir/ssh.err")"
printf 'node_a_ipv6_ssh_server_accepted_key=%s\n' \
    "$(debug_marker 'Server accepts key:' "$work_dir/ssh.err")"
printf 'node_a_ipv6_ssh_authenticated=%s\n' \
    "$(debug_marker 'Authenticated to ' "$work_dir/ssh.err")"
printf 'node_a_ipv6_forced_receiver_message=%s\n' \
    "$(debug_marker "$denied_message" "$work_dir/ssh.err")"
printf 'node_a_ipv6_ssh_stderr_sha256=%s\n' \
    "$(sha256sum "$work_dir/ssh.err" | awk '{ print $1 }')"

[[ "$(relevant_state | sha256sum | awk '{ print $1 }')" == "$state_before" ]]
printf 'node_a_relevant_state_unchanged=true\n'
printf 'release_payload_transferred=false\n'
printf 'rsync_invoked=false\n'
printf 'service_mutations=false\n'

cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf 'action_17c_a_node_a_cleanup_complete=true\n'
printf 'action_17c_a_node_a_diagnostic_complete=true\n'
