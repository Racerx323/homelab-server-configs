#!/usr/bin/env bash

set -u

interface=eth0
ipv4_vip=10.1.0.56
ipv6_vip=fd36:5aa8:6971:1::56

missing=0
for command_name in ip grep arping ndisc6 tcpdump timeout; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'missing_command=%s\n' "$command_name"
        missing=1
    fi
done
((missing == 0)) || exit 3

if ip -o -4 address show dev "$interface" | grep -Fq "$ipv4_vip/"; then
    printf 'conflict=local_ipv4_assignment\n'
    exit 10
fi

if ip -o -6 address show dev "$interface" | grep -Fq "$ipv6_vip/"; then
    printf 'conflict=local_ipv6_assignment\n'
    exit 11
fi

if grep -R -E \
    --include='*.conf' \
    '^[[:space:]]*virtual_router_id[[:space:]]+(110|111)([[:space:]]|$)' \
    /etc/keepalived; then
    printf 'conflict=configured_vrid\n'
    exit 12
fi

if ! arping -D -q -c 3 -w 5 -I "$interface" "$ipv4_vip"; then
    printf 'conflict=ipv4_neighbor_response\n'
    exit 13
fi

if ndisc6 -q -r 3 "$ipv6_vip" "$interface"; then
    printf 'conflict=ipv6_neighbor_response\n'
    exit 14
fi

capture=$(
    timeout 12 tcpdump -lnvv -i "$interface" \
        'ip proto 112 or ip6 proto 112' 2>&1 || true
)
printf '%s\n' "$capture"

if printf '%s\n' "$capture" |
    grep -Eiq 'vrid[[:space:]]+(110|111)([,[:space:]]|$)'; then
    printf 'conflict=observed_vrid\n'
    exit 15
fi

printf 'vip_vrid_availability_complete=true\n'
