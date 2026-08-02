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
[[ "$(dpkg-query -W -f='${db:Status-Abbrev}' caddy)" == 'ii ' ]]
[[ "$(dpkg-query -W -f='${Version}' caddy)" == 2.11.4 ]]
for unit in caddy.service caddy-api.service; do
    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
done
if pgrep -x caddy >/dev/null; then
    printf 'Unexpected Caddy process before dependency simulation.\n' >&2
    exit 1
fi
for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
    systemctl is-active --quiet "$service"
done

inventory_before=$(package_inventory)
services_before=$(protected_service_state)
listeners_before=$(ss -H -lntup | sort)

printf '%s\n' '--- current requested-package state ---'
for package in "${packages[@]}"; do
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

simulation=$(
    LC_ALL=C apt-get -s install --no-install-recommends \
        "${packages[@]}" 2>&1
)
printf '%s\n' '--- APT simulation ---'
printf '%s\n' "$simulation"

install_count=$(
    awk '$1 == "Inst" { count++ } END { print count + 0 }' <<<"$simulation"
)
configure_count=$(
    awk '$1 == "Conf" { count++ } END { print count + 0 }' <<<"$simulation"
)
remove_count=$(
    awk '$1 == "Remv" { count++ } END { print count + 0 }' <<<"$simulation"
)
[[ "$install_count" -eq "$configure_count" ]]
[[ "$remove_count" -eq 0 ]]
printf 'planned_install_or_upgrade_count=%s\n' "$install_count"
printf 'planned_configure_count=%s\n' "$configure_count"
printf 'planned_remove_count=%s\n' "$remove_count"

inventory_after=$(package_inventory)
services_after=$(protected_service_state)
listeners_after=$(ss -H -lntup | sort)
[[ "$inventory_after" == "$inventory_before" ]]
[[ "$services_after" == "$services_before" ]]
[[ "$listeners_after" == "$listeners_before" ]]

printf 'ha_sync_dependency_simulation_complete=true\n'
