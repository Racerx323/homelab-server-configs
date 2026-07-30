#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly node_b_ipv6=fd36:5aa8:6971:1::54
readonly node_a_ipv6=fd36:5aa8:6971:1::53
readonly interface=eth0
readonly authorized_keys=/var/lib/caddy-sync/.ssh/authorized_keys
readonly expected_key_fingerprint='SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0'
readonly expected_prefix='from="10.1.0.53,fd36:5aa8:6971:1::53",restrict,command="/usr/local/libexec/caddy-sync-rsync-receiver"'

relevant_state() {
    stat -c '%n|%U:%G:%a:%s:%i' \
        /var/lib/caddy-sync \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/quarantine \
        /var/lib/caddy-sync/.ssh \
        "$authorized_keys" \
        /etc/default/caddy-ha
    sha256sum "$authorized_keys" /etc/default/caddy-ha
    find \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/quarantine \
        -printf '%p|%y|%U:%G:%m:%s:%i\n' |
        sort
    systemctl show ssh.service --no-pager \
        -p ActiveState -p SubState -p MainPID -p NRestarts
}

authorization_fingerprint() {
    local key

    key=$(awk '{ print $(NF-2), $(NF-1), $NF }' "$authorized_keys")
    ssh-keygen -lf <(printf '%s\n' "$key") -E sha256 |
        awk '{ print $2 }'
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$node_b_ipv6" == fd36:5aa8:6971:1::54 ]]
    [[ "$node_a_ipv6" == fd36:5aa8:6971:1::53 ]]
    [[ "$interface" == eth0 ]]
    [[ "$expected_key_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$expected_prefix" == *"$node_a_ipv6"* ]]
    printf 'action_17c_a_node_b_inspector_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(id -u)" -eq 0 ]]
[[ "$(hostname)" == j1-svpihole00 ]]
[[ "$(dpkg --print-architecture)" == arm64 ]]
[[ -f "$authorized_keys" && ! -L "$authorized_keys" ]]
[[ "$(stat -c '%U:%G:%a' "$authorized_keys")" == caddy-sync:caddy-sync:600 ]]
[[ "$(wc -l <"$authorized_keys")" -eq 1 ]]
[[ "$(authorization_fingerprint)" == "$expected_key_fingerprint" ]]

state_before=$(relevant_state | sha256sum | awk '{ print $1 }')
readonly state_before
printf 'action_17c_a_node_b_preflight_complete=true\n'

ipv6_address_present=false
ssh_ipv6_listener_present=false
ipv6_route_status=0
ipv6_route_source_matches=false
ipv6_route_device_matches=false
authorization_source_ipv6_present=false
sshd_active=false

if ip -o -6 address show dev "$interface" |
    grep -Fq "$node_b_ipv6/64"; then
    ipv6_address_present=true
fi

if ss -H -lnt6 'sport = :22' |
    awk 'NF { found=1 } END { exit !found }'; then
    ssh_ipv6_listener_present=true
fi

route_record=$(ip -6 route get "$node_a_ipv6" 2>/dev/null) ||
    ipv6_route_status=$?
if [[ "$ipv6_route_status" -eq 0 ]]; then
    if grep -Eq "(^|[[:space:]])src[[:space:]]+$node_b_ipv6([[:space:]]|$)" \
        <<<"$route_record"; then
        ipv6_route_source_matches=true
    fi
    if grep -Eq "(^|[[:space:]])dev[[:space:]]+$interface([[:space:]]|$)" \
        <<<"$route_record"; then
        ipv6_route_device_matches=true
    fi
fi

if grep -Fq "$expected_prefix" "$authorized_keys"; then
    authorization_source_ipv6_present=true
fi
if [[ "$(systemctl is-active ssh.service 2>/dev/null || true)" == active ]]; then
    sshd_active=true
fi

printf 'node_b_ipv6_address_present=%s\n' "$ipv6_address_present"
printf 'node_b_ssh_ipv6_listener_present=%s\n' \
    "$ssh_ipv6_listener_present"
printf 'node_b_ipv6_route_status=%s\n' "$ipv6_route_status"
printf 'node_b_ipv6_route_source_matches=%s\n' \
    "$ipv6_route_source_matches"
printf 'node_b_ipv6_route_device_matches=%s\n' \
    "$ipv6_route_device_matches"
printf 'node_b_authorization_source_ipv6_present=%s\n' \
    "$authorization_source_ipv6_present"
printf 'node_b_sshd_active=%s\n' "$sshd_active"

[[ "$(relevant_state | sha256sum | awk '{ print $1 }')" == "$state_before" ]]
printf 'node_b_relevant_state_unchanged=true\n'
printf 'node_b_release_payload_transferred=false\n'
printf 'node_b_service_mutations=false\n'
printf 'action_17c_a_node_b_inspection_complete=true\n'
