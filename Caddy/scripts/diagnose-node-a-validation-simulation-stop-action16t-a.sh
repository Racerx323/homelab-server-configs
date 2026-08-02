#!/usr/bin/env bash

set -euo pipefail

printf 'hostname=%s\n' "$(hostname)"
printf 'architecture=%s\n' "$(dpkg --print-architecture)"
ipv4_state=$(ip -o -4 address show dev eth0)
printf '%s\n' '--- eth0 IPv4 ---'
printf '%s\n' "$ipv4_state"
if grep -Fq '10.1.0.53/22' <<<"$ipv4_state"; then
    printf 'node_ipv4_match=true\n'
else
    printf 'node_ipv4_match=false\n'
fi

printf '%s\n' '--- Caddy and lsyncd state ---'
for package in caddy lsyncd; do
    status=$(
        dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null ||
            true
    )
    version=$(
        dpkg-query -W -f='${Version}' "$package" 2>/dev/null ||
            true
    )
    printf 'package=%s status=%q version=%q\n' \
        "$package" "$status" "$version"
done
for unit in caddy.service caddy-api.service lsyncd.service; do
    printf 'unit=%s active=%s enabled=%s\n' \
        "$unit" \
        "$(systemctl is-active "$unit" 2>/dev/null || true)" \
        "$(systemctl is-enabled "$unit" 2>/dev/null || true)"
done
printf 'caddy_process_count=%s\n' "$(pgrep -xc caddy || true)"
printf 'lsyncd_process_count=%s\n' "$(pgrep -xc lsyncd || true)"

printf '%s\n' '--- Action 3c package state ---'
for package in iputils-arping ndisc6 tcpdump; do
    status=$(
        dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null ||
            true
    )
    version=$(
        dpkg-query -W -f='${Version}' "$package" 2>/dev/null ||
            true
    )
    architecture=$(
        dpkg-query -W -f='${Architecture}' "$package" 2>/dev/null ||
            true
    )
    printf 'package=%s status=%q version=%q architecture=%q\n' \
        "$package" "$status" "$version" "$architecture"
done

printf '%s\n' '--- uuid-runtime state and policy ---'
uuid_status=$(
    dpkg-query -W -f='${db:Status-Abbrev}' uuid-runtime 2>/dev/null ||
        true
)
uuid_version=$(
    dpkg-query -W -f='${Version}' uuid-runtime 2>/dev/null ||
        true
)
uuid_policy=$(apt-cache policy uuid-runtime)
uuid_candidate=$(
    awk '/^[[:space:]]*Candidate:/ { print $2; exit }' <<<"$uuid_policy"
)
printf 'package=uuid-runtime status=%q version=%q candidate=%q\n' \
    "$uuid_status" "$uuid_version" "$uuid_candidate"
printf '%s\n' "$uuid_policy"

if [[ -e /usr/sbin/policy-rc.d || -L /usr/sbin/policy-rc.d ]]; then
    stat -c 'policy=present type=%F owner=%U:%G mode=%a path=%n' \
        /usr/sbin/policy-rc.d
else
    printf 'policy=absent path=/usr/sbin/policy-rc.d\n'
fi

printf '%s\n' '--- protected services ---'
for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
    printf 'protected_service=%s active=%s\n' \
        "$service" \
        "$(systemctl is-active "$service" 2>/dev/null || true)"
done

audit=$(dpkg --audit)
printf 'dpkg_audit_empty=%s\n' \
    "$([[ -z "$audit" ]] && printf true || printf false)"
if [[ -n "$audit" ]]; then
    printf '%s\n' "$audit"
fi
printf 'validation_simulation_diagnostic_complete=true\n'
