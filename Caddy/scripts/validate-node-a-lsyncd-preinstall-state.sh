#!/usr/bin/env bash

set -euo pipefail

packages=(
    keepalived
    lsyncd
    rsync
    openssh-client
    openssh-server
)

package_inventory() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        sort
}

protected_service_state() {
    for service in \
        lighttpd.service keepalived.service ssh.service unbound.service \
        pihole-FTL.service munin-node.service; do
        systemctl show "$service" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts
    done
}

[[ "$(hostname)" == j1-svpihole0 ]]
ipv4_state=$(ip -o -4 address show dev eth0)
grep -Fq '10.1.0.53/22' <<<"$ipv4_state"
[[ "$(dpkg --print-architecture)" == arm64 ]]

for package in lsyncd lua5.3 liblua5.3-0; do
    status=$(
        dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null ||
            true
    )
    [[ -z "$status" || "$status" == 'un ' ]]
done
lsyncd_policy=$(apt-cache policy lsyncd)
lua_policy=$(apt-cache policy lua5.3)
liblua_policy=$(apt-cache policy liblua5.3-0)
[[ "$(awk '/^[[:space:]]*Candidate:/ { print $2; exit }' \
    <<<"$lsyncd_policy")" == 2.2.3-1 ]]
[[ "$(awk '/^[[:space:]]*Candidate:/ { print $2; exit }' \
    <<<"$lua_policy")" == 5.3.6-2 ]]
[[ "$(awk '/^[[:space:]]*Candidate:/ { print $2; exit }' \
    <<<"$liblua_policy")" == 5.3.6-2 ]]

for target in \
    /usr/bin/lsyncd \
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
lsyncd_enabled=$(
    systemctl is-enabled lsyncd.service 2>/dev/null ||
        true
)
[[ -z "$lsyncd_enabled" || "$lsyncd_enabled" == not-found ]]

mapfile -t sysv_links < <(
    find /etc \
        -maxdepth 2 \
        -type l \
        -path '/etc/rc*.d/*lsyncd' \
        -print |
        sort
)
[[ "${#sysv_links[@]}" -eq 0 ]]
mapfile -t staging < <(
    find /tmp -mindepth 1 -maxdepth 1 \
        -name 'lsyncd-package-audit-node-a.*' -print |
        sort
)
[[ "${#staging[@]}" -eq 0 ]]

[[ "$(dpkg-query -W -f='${db:Status-Abbrev}' caddy)" == 'ii ' ]]
[[ "$(dpkg-query -W -f='${Version}' caddy)" == 2.11.4 ]]
for unit in caddy.service caddy-api.service; do
    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
done
if pgrep -x caddy >/dev/null; then
    printf 'Unexpected Caddy process before lsyncd installation.\n' >&2
    exit 1
fi
for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
    systemctl is-active --quiet "$service"
done
[[ -z "$(dpkg --audit)" ]]

inventory_before=$(package_inventory)
services_before=$(protected_service_state)
listeners_before=$(ss -H -lntup | sort)

simulation=$(
    LC_ALL=C apt-get -s install --no-install-recommends \
        "${packages[@]}" 2>&1
)
printf '%s\n' "$simulation"
[[ "$(
    awk '$1 == "Inst" { count++ } END { print count + 0 }' <<<"$simulation"
)" -eq 3 ]]
[[ "$(
    awk '$1 == "Conf" { count++ } END { print count + 0 }' <<<"$simulation"
)" -eq 3 ]]
[[ "$(
    awk '$1 == "Remv" { count++ } END { print count + 0 }' <<<"$simulation"
)" -eq 0 ]]
grep -Eq '^Inst liblua5[.]3-0 \(5[.]3[.]6-2 .*\[arm64\]\)$' \
    <<<"$simulation"
grep -Eq '^Inst lua5[.]3 \(5[.]3[.]6-2 .*\[arm64\]\)$' <<<"$simulation"
grep -Eq '^Inst lsyncd \(2[.]2[.]3-1 .*\[arm64\]\)$' <<<"$simulation"
grep -Fxq \
    '0 upgraded, 3 newly installed, 0 to remove and 0 not upgraded.' \
    <<<"$simulation"

[[ "$(package_inventory)" == "$inventory_before" ]]
[[ "$(protected_service_state)" == "$services_before" ]]
[[ "$(ss -H -lntup | sort)" == "$listeners_before" ]]
[[ -z "$(dpkg --audit)" ]]

printf 'lsyncd_preinstall_state_complete=true\n'
