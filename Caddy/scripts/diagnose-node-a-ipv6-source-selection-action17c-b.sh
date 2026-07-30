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
    elif grep -Fq 'Permission denied' "$error_file"; then
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

run_probe() {
    local label=$1
    local bind_address=$2
    local output_file=$3
    local error_file=$4
    local status=0
    local -a bind_options=()

    if [[ "$bind_address" != none ]]; then
        bind_options=(-b "$bind_address")
    fi

    runuser -u caddy-sync -- \
        ssh -6 -n -T -vv \
        "${bind_options[@]}" \
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
        >"$output_file" 2>"$error_file" || status=$?

    printf '%s_ssh_status=%s\n' "$label" "$status"
    printf '%s_ssh_error_class=%s\n' \
        "$label" "$(classify_ssh_error "$status" "$error_file")"
    printf '%s_ssh_connecting=%s\n' \
        "$label" "$(debug_marker "Connecting to $node_b_ipv6" "$error_file")"
    printf '%s_ssh_connection_established=%s\n' \
        "$label" "$(debug_marker 'Connection established.' "$error_file")"
    printf '%s_ssh_host_key_verified=%s\n' \
        "$label" "$(debug_marker "Host '$node_b_host_alias' is known and matches" \
            "$error_file")"
    printf '%s_ssh_public_key_offered=%s\n' \
        "$label" "$(debug_marker 'Offering public key:' "$error_file")"
    printf '%s_ssh_server_accepted_key=%s\n' \
        "$label" "$(debug_marker 'Server accepts key:' "$error_file")"
    printf '%s_ssh_authenticated=%s\n' \
        "$label" "$(debug_marker 'Authenticated to ' "$error_file")"
    printf '%s_forced_receiver_message=%s\n' \
        "$label" "$(debug_marker "$denied_message" "$error_file")"
    printf '%s_ssh_stderr_sha256=%s\n' \
        "$label" "$(sha256sum "$error_file" | awk '{ print $1 }')"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$node_a_ipv6" == fd36:5aa8:6971:1::53 ]]
    [[ "$node_b_ipv6" == fd36:5aa8:6971:1::54 ]]
    [[ "$node_b_host_alias" == pihole00.local.theama.co ]]
    [[ "$expected_key_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$expected_host_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$denied_command" != rsync\ --server\ * ]]
    printf 'action_17c_b_node_a_diagnostic_self_test_complete=true\n'
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
grep -Fq "$node_a_ipv6/64" < <(ip -o -6 address show dev "$interface")

state_before=$(relevant_state | sha256sum | awk '{ print $1 }')
readonly state_before
printf 'action_17c_b_node_a_preflight_complete=true\n'

work_dir=$(mktemp -d /run/caddy-action17c-b-ipv6.XXXXXX)
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

route_status=0
route_record=$(ip -6 route get "$node_b_ipv6" 2>/dev/null) ||
    route_status=$?
selected_source=$(
    awk '
        {
            for (field = 1; field <= NF; field++) {
                if ($field == "src" && field < NF) {
                    print $(field + 1)
                    exit
                }
            }
        }
    ' <<<"$route_record"
)
selected_source=${selected_source:-none}
if [[ "$selected_source" != none ]] &&
    { [[ ! "$selected_source" =~ ^[0-9A-Fa-f:]+$ ]] ||
        ((${#selected_source} > 39)); }; then
    printf 'Unsafe route-selected IPv6 source.\n' >&2
    exit 97
fi

printf 'node_a_ipv6_route_status=%s\n' "$route_status"
printf 'node_a_ipv6_selected_source=%s\n' "$selected_source"
if [[ "$selected_source" == "$node_a_ipv6" ]]; then
    printf 'node_a_ipv6_selected_source_matches_stable=true\n'
else
    printf 'node_a_ipv6_selected_source_matches_stable=false\n'
fi

run_probe \
    unbound none \
    "$work_dir/unbound.out" "$work_dir/unbound.err"
run_probe \
    bound "$node_a_ipv6" \
    "$work_dir/bound.out" "$work_dir/bound.err"

[[ "$(relevant_state | sha256sum | awk '{ print $1 }')" == "$state_before" ]]
printf 'node_a_relevant_state_unchanged=true\n'
printf 'release_payload_transferred=false\n'
printf 'rsync_invoked=false\n'
printf 'service_mutations=false\n'

cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf 'action_17c_b_node_a_cleanup_complete=true\n'
printf 'action_17c_b_node_a_diagnostic_complete=true\n'
