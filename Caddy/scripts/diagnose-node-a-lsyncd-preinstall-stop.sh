#!/usr/bin/env bash

set -euo pipefail

printf 'hostname=%s\n' "$(hostname)"
printf 'architecture=%s\n' "$(dpkg --print-architecture)"
printf '%s\n' '--- eth0 IPv4 ---'
ip -o -4 address show dev eth0

printf '%s\n' '--- package state and candidates ---'
for package in lsyncd lua5.3 liblua5.3-0; do
    status=$(
        dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null ||
            true
    )
    version=$(
        dpkg-query -W -f='${Version}' "$package" 2>/dev/null ||
            true
    )
    policy=$(apt-cache policy "$package")
    candidate=$(
        awk '/^[[:space:]]*Candidate:/ { print $2; exit }' <<<"$policy"
    )
    printf 'package=%s status=%q version=%q candidate=%q\n' \
        "$package" "$status" "$version" "$candidate"
done

printf '%s\n' '--- target state ---'
for target in \
    /usr/bin/lsyncd \
    /etc/init.d/lsyncd \
    /etc/default/lsyncd \
    /etc/lsyncd \
    /lib/systemd/system/lsyncd.service \
    /etc/systemd/system/lsyncd.service \
    /usr/sbin/policy-rc.d; do
    if [[ -e "$target" || -L "$target" ]]; then
        stat -c 'target=present type=%F owner=%U:%G mode=%a path=%n' "$target"
        if [[ -L "$target" ]]; then
            printf 'target_link=%s -> %s\n' "$target" "$(readlink "$target")"
        fi
    else
        printf 'target=absent path=%s\n' "$target"
    fi
done

printf '%s\n' '--- lsyncd unit state ---'
printf 'lsyncd_load=%s\n' \
    "$(systemctl show --property=LoadState --value lsyncd.service)"
printf 'lsyncd_active=%s\n' \
    "$(systemctl is-active lsyncd.service 2>/dev/null || true)"
printf 'lsyncd_enabled=%s\n' \
    "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)"

printf '%s\n' '--- lsyncd SysV links ---'
find /etc \
    -maxdepth 2 \
    -type l \
    -path '/etc/rc*.d/*lsyncd' \
    -printf '%M %u:%g %p -> %l\n' |
    sort

printf '%s\n' '--- lsyncd audit staging ---'
find /tmp -mindepth 1 -maxdepth 1 \
    -name 'lsyncd-package-audit-node-a.*' \
    -printf '%M %u:%g %p\n' |
    sort

printf '%s\n' '--- Caddy state ---'
printf 'caddy_status=%q\n' \
    "$(dpkg-query -W -f='${db:Status-Abbrev}' caddy 2>/dev/null || true)"
printf 'caddy_version=%q\n' \
    "$(dpkg-query -W -f='${Version}' caddy 2>/dev/null || true)"
for unit in caddy.service caddy-api.service; do
    printf 'caddy_unit=%s active=%s enabled=%s\n' \
        "$unit" \
        "$(systemctl is-active "$unit" 2>/dev/null || true)" \
        "$(systemctl is-enabled "$unit" 2>/dev/null || true)"
done
printf 'caddy_process_count=%s\n' "$(pgrep -xc caddy || true)"

printf '%s\n' '--- protected services ---'
for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
    printf 'protected_service=%s active=%s\n' \
        "$service" \
        "$(systemctl is-active "$service" 2>/dev/null || true)"
done

audit=$(dpkg --audit)
printf 'dpkg_audit_empty=%s\n' "$([[ -z "$audit" ]] && printf true || printf false)"
if [[ -n "$audit" ]]; then
    printf '%s\n' "$audit"
fi
printf 'lsyncd_preinstall_diagnostic_complete=true\n'
