#!/usr/bin/env bash

set -euo pipefail

packages=(
    keepalived
    lsyncd
    rsync
    openssh-client
    openssh-server
    lua5.3
    liblua5.3-0
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
        printf '### %s\n' "$service"
        systemctl show "$service" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts
    done
}

assert_package() {
    local package=$1
    local version=$2

    [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$package")" == 'ii ' ]]
    [[ "$(dpkg-query -W -f='${Version}' "$package")" == "$version" ]]
    [[ "$(dpkg-query -W -f='${Architecture}' "$package")" == arm64 ]]
    [[ -z "$(dpkg --verify "$package")" ]]
}

[[ "$(hostname)" == j1-svpihole0 ]]
ip -o -4 address show dev eth0 |
    grep -Fq '10.1.0.53/22'
[[ "$(dpkg --print-architecture)" == arm64 ]]

inventory_before=$(package_inventory)
services_before=$(protected_service_state)
listeners_before=$(ss -H -lntup | sort)
[[ -z "$(dpkg --audit)" ]]

simulation=$(
    LC_ALL=C apt-get -s install --no-install-recommends \
        keepalived lsyncd rsync openssh-client openssh-server 2>&1
)
printf '%s\n' "$simulation"
[[ "$(
    awk '$1 == "Inst" { count++ } END { print count + 0 }' <<<"$simulation"
)" -eq 0 ]]
[[ "$(
    awk '$1 == "Conf" { count++ } END { print count + 0 }' <<<"$simulation"
)" -eq 0 ]]
[[ "$(
    awk '$1 == "Remv" { count++ } END { print count + 0 }' <<<"$simulation"
)" -eq 0 ]]
grep -Fxq \
    '0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.' \
    <<<"$simulation"

assert_package keepalived '1:2.2.7-1+b2'
assert_package lsyncd '2.2.3-1'
assert_package rsync '3.2.7-1+deb12u6'
assert_package openssh-client '1:9.2p1-2+deb12u10'
assert_package openssh-server '1:9.2p1-2+deb12u10'
assert_package lua5.3 '5.3.6-2'
assert_package liblua5.3-0 '5.3.6-2'

keepalived_version=$(/usr/sbin/keepalived --version 2>&1 | sed -n '1p')
lsyncd_version=$(/usr/bin/lsyncd -version 2>&1 | sed -n '1p')
rsync_version=$(/usr/bin/rsync --version | sed -n '1p')
ssh_version=$(/usr/bin/ssh -V 2>&1)
[[ "$keepalived_version" == 'Keepalived v2.2.7 '* ]]
[[ "$lsyncd_version" == 'Version: 2.2.3' ]]
[[ "$rsync_version" == 'rsync  version 3.2.7  protocol version 32' ]]
[[ "$ssh_version" == *'OpenSSH_9.2p1 Debian-2+deb12u10'* ]]
printf 'keepalived_version=%s\n' "$keepalived_version"
printf 'lsyncd_version=%s\n' "$lsyncd_version"
printf 'rsync_version=%s\n' "$rsync_version"
printf 'ssh_version=%s\n' "$ssh_version"

[[ "$(readlink -f /usr/bin/lua)" == /usr/bin/lua5.3 ]]
[[ "$(readlink -f /usr/bin/luac)" == /usr/bin/luac5.3 ]]
printf '%s  %s\n' \
    27e0a67166e36a75f04c6b8548520a59d013442dcbc52542c30836c8e53a3611 \
    /etc/init.d/lsyncd |
    sha256sum --check --status

[[ "$(systemctl is-active lsyncd.service 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" == masked ]]
if pgrep -x lsyncd >/dev/null; then
    printf 'Unexpected lsyncd process during convergence validation.\n' >&2
    exit 1
fi
mapfile -t start_links < <(
    find /etc -maxdepth 2 -type l \
        -path '/etc/rc*.d/S*lsyncd' -print |
        sort
)
[[ "${#start_links[@]}" -eq 0 ]]
mapfile -t kill_links < <(
    find /etc -maxdepth 2 -type l \
        -path '/etc/rc*.d/K*lsyncd' -print |
        sort
)
[[ "${#kill_links[@]}" -gt 0 ]]
printf 'lsyncd_sysv_kill_link_count=%s\n' "${#kill_links[@]}"

[[ ! -e /usr/sbin/policy-rc.d && ! -L /usr/sbin/policy-rc.d ]]
mapfile -t staging < <(
    find /tmp -mindepth 1 -maxdepth 1 \
        \( -name 'lsyncd-package-audit-node-a.*' \
        -o -name 'lsyncd-inhibited-install-node-a.*' \) \
        -print |
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
    printf 'Unexpected Caddy process during convergence validation.\n' >&2
    exit 1
fi

printf '%s  %s\n' \
    568507d5604cb2794106de3de29d1603c3f12c9045bf7fc1ad4342592a1395c1 \
    /etc/lighttpd/lighttpd.conf |
    sha256sum --check --status
printf '%s  %s\n' \
    6da587363054a4db69fb742d23bddde06aec866e11fb7a91bff1a8d75a713f7a \
    /etc/lighttpd/conf-enabled/external.conf |
    sha256sum --check --status
printf '%s  %s\n' \
    cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2 \
    /etc/keepalived/keepalived.conf |
    sha256sum --check --status
for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
    systemctl is-active --quiet "$service"
done

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
grep -Eq '[[:space:]][^[:space:]]*:80[[:space:]]' <<<"$tcp_frontend"
grep -Eq '[[:space:]][^[:space:]]*:443[[:space:]]' <<<"$tcp_frontend"
[[ -z "$(ss -H -lunp | awk '$4 ~ /:443$/ { print }' | sort)" ]]

[[ "$(package_inventory)" == "$inventory_before" ]]
[[ "$(protected_service_state)" == "$services_before" ]]
[[ "$(ss -H -lntup | sort)" == "$listeners_before" ]]
[[ -z "$(dpkg --audit)" ]]

printf 'validated_package_count=%s\n' "${#packages[@]}"
printf 'ha_sync_dependency_convergence_valid=true\n'
