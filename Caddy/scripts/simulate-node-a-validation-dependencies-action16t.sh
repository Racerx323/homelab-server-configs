#!/usr/bin/env bash

set -euo pipefail

packages=(
    bash
    coreutils
    findutils
    iproute2
    iputils-arping
    jq
    ndisc6
    openssl
    procps
    tcpdump
    util-linux
    uuid-runtime
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

[[ "$(dpkg-query -W -f='${db:Status-Abbrev}' lsyncd)" == 'ii ' ]]
[[ "$(dpkg-query -W -f='${Version}' lsyncd)" == 2.2.3-1 ]]
[[ "$(systemctl is-active lsyncd.service 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" == masked ]]
if pgrep -x lsyncd >/dev/null; then
    printf 'Unexpected lsyncd process before dependency simulation.\n' >&2
    exit 1
fi

assert_installed_package() {
    local package=$1
    local version=$2

    [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$package")" == 'ii ' ]]
    [[ "$(dpkg-query -W -f='${Version}' "$package")" == "$version" ]]
    [[ "$(dpkg-query -W -f='${Architecture}' "$package")" == arm64 ]]
}

assert_installed_package iputils-arping '3:20221126-1+deb12u1'
assert_installed_package ndisc6 '1.0.5-1+b2'
assert_installed_package tcpdump '4.99.3-1'

uuid_status=$(
    dpkg-query -W -f='${db:Status-Abbrev}' uuid-runtime 2>/dev/null ||
        true
)
[[ -z "$uuid_status" || "$uuid_status" == 'un ' ]]
uuid_policy=$(apt-cache policy uuid-runtime)
uuid_candidate=$(
    awk '/^[[:space:]]*Candidate:/ { print $2; exit }' <<<"$uuid_policy"
)
[[ "$uuid_candidate" == '2.38.1-5+deb12u3' ]]
[[ ! -e /usr/sbin/policy-rc.d && ! -L /usr/sbin/policy-rc.d ]]
[[ -z "$(dpkg --audit)" ]]
for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
    systemctl is-active --quiet "$service"
done

inventory_before=$(package_inventory)
services_before=$(protected_service_state)
listeners_before=$(ss -H -lntup | sort)

printf '%s\n' '--- current validation-package state ---'
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
[[ "$install_count" -eq 1 ]]
[[ "$configure_count" -eq 1 ]]
[[ "$remove_count" -eq 0 ]]
grep -Eq \
    '^Inst uuid-runtime \(2[.]38[.]1-5[+]deb12u3 .*\[arm64\]\)$' \
    <<<"$simulation"
grep -Fxq \
    '0 upgraded, 1 newly installed, 0 to remove and 0 not upgraded.' \
    <<<"$simulation"
printf 'planned_install_count=%s\n' "$install_count"
printf 'planned_configure_count=%s\n' "$configure_count"
printf 'planned_remove_count=%s\n' "$remove_count"

[[ "$(package_inventory)" == "$inventory_before" ]]
[[ "$(protected_service_state)" == "$services_before" ]]
[[ "$(ss -H -lntup | sort)" == "$listeners_before" ]]
[[ -z "$(dpkg --audit)" ]]

printf 'validation_dependency_simulation_complete=true\n'
