#!/usr/bin/env bash

set -euo pipefail

[[ "$(hostname)" == j1-svpihole0 ]]
ipv4_state=$(ip -o -4 address show dev eth0)
grep -Fq '10.1.0.53/22' <<<"$ipv4_state"
[[ "$(dpkg --print-architecture)" == arm64 ]]

mapfile -t staging < <(
    find /tmp -mindepth 1 -maxdepth 1 \
        -name 'lsyncd-package-audit-node-a.*' -print |
        sort
)
if ((${#staging[@]} != 0)); then
    printf 'Unexpected lsyncd audit staging: %s\n' "${staging[@]}" >&2
    exit 1
fi

for package in lsyncd lua5.3 liblua5.3-0; do
    status=$(
        dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null ||
            true
    )
    [[ -z "$status" || "$status" == 'un ' ]]
done
for target in \
    /etc/init.d/lsyncd \
    /etc/default/lsyncd \
    /etc/lsyncd \
    /lib/systemd/system/lsyncd.service \
    /etc/systemd/system/lsyncd.service \
    /usr/sbin/policy-rc.d; do
    [[ ! -e "$target" && ! -L "$target" ]]
done
[[ "$(systemctl show --property=LoadState --value lsyncd.service)" == not-found ]]
[[ "$(systemctl is-active lsyncd.service 2>/dev/null || true)" == inactive ]]
[[ -z "$(dpkg --audit)" ]]

[[ "$(dpkg-query -W -f='${db:Status-Abbrev}' caddy)" == 'ii ' ]]
[[ "$(dpkg-query -W -f='${Version}' caddy)" == 2.11.4 ]]
for unit in caddy.service caddy-api.service; do
    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
done
if pgrep -x caddy >/dev/null; then
    printf 'Unexpected Caddy process after lsyncd audit attempt.\n' >&2
    exit 1
fi
for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
    systemctl is-active --quiet "$service"
    printf 'protected_service_active=%s\n' "$service"
done

lighttpd_pid=$(systemctl show --property=MainPID --value lighttpd.service)
[[ "$lighttpd_pid" =~ ^[1-9][0-9]*$ ]]
tcp_frontend=$(
    ss -H -ltnp |
        awk '$4 ~ /:80$|:443$/ { print }' |
        sort
)
[[ -n "$tcp_frontend" ]]
if grep -Fv 'users:(("lighttpd"' <<<"$tcp_frontend"; then
    printf 'A non-lighttpd process owns TCP 80 or 443.\n' >&2
    exit 1
fi
grep -Fq "pid=$lighttpd_pid" <<<"$tcp_frontend"
[[ -z "$(
    ss -H -lunp |
        awk '$4 ~ /:443$/ { print }' |
        sort
)" ]]

printf 'lsyncd_audit_cleanup_valid=true\n'
