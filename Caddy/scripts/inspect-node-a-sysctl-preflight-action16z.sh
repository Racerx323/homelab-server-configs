#!/usr/bin/env bash

set -euo pipefail

readonly baseline=/var/backups/caddy-ha/predeploy-node-a-20260728T184626Z
readonly target=/etc/sysctl.d/70-caddy-ha.conf

package_inventory() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        sort
}

protected_service_state() {
    for service in \
        lighttpd.service keepalived.service ssh.service unbound.service \
        pihole-FTL.service munin-node.service caddy.service \
        caddy-api.service lsyncd.service uuidd.service uuidd.socket; do
        printf '### %s\n' "$service"
        systemctl show "$service" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts
        printf 'unit_file_state=%s\n' \
            "$(systemctl is-enabled "$service" 2>/dev/null || true)"
    done
}

group_names() {
    id -nG "$1" |
        tr ' ' '\n' |
        sed '/^$/d' |
        sort
}

group_members() {
    getent group "$1" |
        cut -d: -f4 |
        tr ',' '\n' |
        sed '/^$/d' |
        sort
}

assert_masked_inactive() {
    local unit=$1

    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
}

valid_binary_sysctl_value() {
    [[ "$1" == 0 || "$1" == 1 ]]
}

staging_paths() {
    find /tmp /var/tmp /etc/sysctl.d \
        -mindepth 1 -maxdepth 1 \
        \( -name 'caddy-sysctl-node-a*' \
        -o -name 'caddy-ha-sysctl-node-a*' \
        -o -name '.70-caddy-ha.conf*' \) \
        -print |
        sort
}

if [[ "${1:-}" == --self-test ]]; then
    valid_binary_sysctl_value 0
    valid_binary_sysctl_value 1
    if valid_binary_sysctl_value 2; then
        printf 'Invalid sysctl value was accepted.\n' >&2
        exit 1
    fi
    printf 'action_16z_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(id -u)" -eq 0 ]]
[[ "$(hostname)" == j1-svpihole0 ]]
ipv4_state=$(ip -o -4 address show dev eth0)
grep -Fq '10.1.0.53/22' <<<"$ipv4_state"
[[ "$(dpkg --print-architecture)" == arm64 ]]
[[ -d "$baseline" && ! -L "$baseline" ]]
(
    cd "$baseline"
    sha256sum --check --status configuration.tar.sha256
    grep -Fxq 'backup_complete=true' backup-manifest.txt
)

[[ -x /usr/sbin/sysctl ]]
sysctl_version=$(/usr/sbin/sysctl --version)
[[ "$sysctl_version" == 'sysctl from procps-ng 4.0.2' ]]
[[ "$(dpkg-query -W -f='${db:Status-Abbrev}' procps)" == 'ii ' ]]
[[ "$(dpkg-query -W -f='${Version}' procps)" == '2:4.0.2-3' ]]
procps_verification=$(dpkg --verify procps)
[[ "$procps_verification" == '??5?????? c /etc/sysctl.conf' ]]

[[ ! -e "$target" && ! -L "$target" ]]
mapfile -t staging_before < <(staging_paths)
[[ "${#staging_before[@]}" -eq 0 ]]

[[ "$(id -u caddy)" -eq 995 ]]
[[ "$(id -g caddy)" -eq 992 ]]
[[ "$(group_names caddy)" == $'caddy\ncaddy-tls\nwww-data' ]]
[[ "$(id -u caddy-sync)" -eq 994 ]]
[[ "$(id -g caddy-sync)" -eq 990 ]]
[[ "$(group_names caddy-sync)" == $'caddy-sync\ncaddy-tls' ]]
[[ "$(getent passwd caddy-sync | cut -d: -f6)" == /var/lib/caddy-sync ]]
[[ "$(getent passwd caddy-sync | cut -d: -f7)" == /bin/sh ]]
[[ "$(passwd --status caddy-sync | awk '{ print $2 }')" == L ]]
[[ "$(id -u keepalived_script)" -eq 993 ]]
[[ "$(id -g keepalived_script)" -eq 989 ]]
[[ "$(group_names keepalived_script)" == $'caddy-tls\nkeepalived_script' ]]
[[ "$(getent passwd keepalived_script | cut -d: -f7)" == /usr/sbin/nologin ]]
[[ "$(passwd --status keepalived_script | awk '{ print $2 }')" == L ]]
[[ "$(getent group caddy-tls | cut -d: -f3)" -eq 991 ]]
[[ "$(group_members caddy-tls)" == $'caddy\ncaddy-sync\nkeepalived_script' ]]

[[ "$(stat -c '%U:%G:%a' /etc/caddy/releases)" == root:caddy-tls:750 ]]
for path in \
    /var/lib/caddy-sync \
    /var/lib/caddy-sync/outbound \
    /var/lib/caddy-sync/incoming \
    /var/lib/caddy-sync/quarantine; do
    [[ "$(stat -c '%U:%G:%a' "$path")" == caddy-sync:caddy-sync:750 ]]
done
[[ "$(stat -c '%U:%G:%a' /var/lib/caddy-sync/.ssh)" == caddy-sync:caddy-sync:700 ]]

for unit in \
    caddy.service caddy-api.service lsyncd.service uuidd.service uuidd.socket; do
    assert_masked_inactive "$unit"
done
for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
    systemctl is-active --quiet "$service"
done
if pgrep -x caddy >/dev/null ||
    pgrep -x lsyncd >/dev/null ||
    pgrep -x uuidd >/dev/null; then
    printf 'Unexpected protected process during sysctl preflight.\n' >&2
    exit 1
fi
[[ ! -e /usr/sbin/policy-rc.d && ! -L /usr/sbin/policy-rc.d ]]

inventory_before=$(package_inventory)
services_before=$(protected_service_state)
listeners_before=$(ss -H -lntup | sort)
protected_hashes_before=$(
    sha256sum -- \
        /etc/lighttpd/lighttpd.conf \
        /etc/lighttpd/conf-enabled/external.conf \
        /etc/keepalived/keepalived.conf
)
[[ -z "$(dpkg --audit)" ]]

ipv4_before=$(/usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind)
ipv6_before=$(/usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind)
valid_binary_sysctl_value "$ipv4_before"
valid_binary_sysctl_value "$ipv6_before"
[[ "$ipv4_before" == 1 ]]
[[ "$ipv6_before" == 0 ]]

ipv4_after=$(/usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind)
ipv6_after=$(/usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind)
[[ "$ipv4_after" == "$ipv4_before" ]]
[[ "$ipv6_after" == "$ipv6_before" ]]
[[ ! -e "$target" && ! -L "$target" ]]
mapfile -t staging_after < <(staging_paths)
[[ "${#staging_after[@]}" -eq 0 ]]
[[ "$(package_inventory)" == "$inventory_before" ]]
[[ "$(protected_service_state)" == "$services_before" ]]
[[ "$(ss -H -lntup | sort)" == "$listeners_before" ]]
[[ "$(
    sha256sum -- \
        /etc/lighttpd/lighttpd.conf \
        /etc/lighttpd/conf-enabled/external.conf \
        /etc/keepalived/keepalived.conf
)" == "$protected_hashes_before" ]]
[[ -z "$(dpkg --audit)" ]]

printf 'sysctl_path=%s\n' "$(readlink -e /usr/sbin/sysctl)"
printf 'sysctl_version=%s\n' "$sysctl_version"
printf 'ipv4_nonlocal_bind=%s\n' "$ipv4_after"
printf 'ipv6_nonlocal_bind=%s\n' "$ipv6_after"
printf 'sysctl_target_present=false\n'
printf 'sysctl_staging_count=0\n'
printf 'node_a_sysctl_preflight_action16z_complete=true\n'
