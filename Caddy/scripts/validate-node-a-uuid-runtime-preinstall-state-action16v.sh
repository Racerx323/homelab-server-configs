#!/usr/bin/env bash

set -euo pipefail

expected_version=2.38.1-5+deb12u3

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

assert_installed_package() {
    local package=$1
    local version=$2

    [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$package")" == 'ii ' ]]
    [[ "$(dpkg-query -W -f='${Version}' "$package")" == "$version" ]]
    [[ "$(dpkg-query -W -f='${Architecture}' "$package")" == arm64 ]]
}

assert_absent_unit() {
    local unit=$1
    local enabled

    [[ "$(systemctl show --property=LoadState --value "$unit")" == not-found ]]
    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    enabled=$(
        systemctl is-enabled "$unit" 2>/dev/null ||
            true
    )
    [[ -z "$enabled" || "$enabled" == not-found ]]
}

[[ "$(hostname)" == j1-svpihole0 ]]
ipv4_state=$(ip -o -4 address show dev eth0)
grep -Fq '10.1.0.53/22' <<<"$ipv4_state"
[[ "$(dpkg --print-architecture)" == arm64 ]]

uuid_status=$(
    dpkg-query -W -f='${db:Status-Abbrev}' uuid-runtime 2>/dev/null ||
        true
)
[[ -z "$uuid_status" || "$uuid_status" == 'un ' ]]
if [[ "$uuid_status" == 'ii ' ]]; then
    printf 'uuid-runtime is already installed; refusing preinstall gate.\n' >&2
    exit 1
fi
uuid_policy=$(apt-cache policy uuid-runtime)
uuid_candidate=$(
    awk '/^[[:space:]]*Candidate:/ { print $2; exit }' <<<"$uuid_policy"
)
[[ "$uuid_candidate" == "$expected_version" ]]

if getent passwd uuidd >/dev/null ||
    getent group uuidd >/dev/null; then
    printf 'Unexpected uuidd identity before installation.\n' >&2
    exit 1
fi
for target in \
    /var/lib/libuuid \
    /usr/bin/uuidgen \
    /usr/bin/uuidparse \
    /usr/sbin/uuidd \
    /etc/init.d/uuidd \
    /lib/systemd/system/uuidd.service \
    /lib/systemd/system/uuidd.socket \
    /etc/systemd/system/uuidd.service \
    /etc/systemd/system/uuidd.socket \
    /usr/sbin/policy-rc.d; do
    [[ ! -e "$target" && ! -L "$target" ]]
done
assert_absent_unit uuidd.service
assert_absent_unit uuidd.socket
if pgrep -x uuidd >/dev/null; then
    printf 'Unexpected uuidd process before installation.\n' >&2
    exit 1
fi

mapfile -t uuidd_links < <(
    find /etc \
        -maxdepth 4 \
        -type l \
        \( -name 'uuidd.service' -o -name 'uuidd.socket' \
        -o -name '[SK][0-9][0-9]uuidd' \) \
        -print |
        sort
)
[[ "${#uuidd_links[@]}" -eq 0 ]]
mapfile -t staging < <(
    find /tmp -mindepth 1 -maxdepth 1 \
        -name 'uuid-runtime-*' -print |
        sort
)
[[ "${#staging[@]}" -eq 0 ]]

assert_installed_package caddy 2.11.4
assert_installed_package lsyncd 2.2.3-1
assert_installed_package iputils-arping '3:20221126-1+deb12u1'
assert_installed_package ndisc6 '1.0.5-1+b2'
assert_installed_package tcpdump '4.99.3-1'
for unit in caddy.service caddy-api.service lsyncd.service; do
    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
done
if pgrep -x caddy >/dev/null ||
    pgrep -x lsyncd >/dev/null; then
    printf 'Unexpected Caddy or lsyncd process before installation.\n' >&2
    exit 1
fi

for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
    systemctl is-active --quiet "$service"
done
[[ -z "$(dpkg --audit)" ]]

inventory_before=$(package_inventory)
services_before=$(protected_service_state)
listeners_before=$(ss -H -lntup | sort)

printf '%s\n' '--- immediate uuid-runtime preinstallation state ---'
printf 'uuid_runtime_status=%q\n' "$uuid_status"
printf 'uuid_runtime_candidate=%s\n' "$uuid_candidate"
printf 'uuidd_identity=absent\n'
printf 'uuidd_state_directory=absent\n'
printf 'uuidd_units=not-found-inactive-unmasked\n'
printf 'uuidd_process=absent\n'
printf 'uuid_runtime_staging=absent\n'

simulation=$(
    LC_ALL=C apt-get -s install --no-install-recommends \
        "uuid-runtime=$expected_version" 2>&1
)
printf '%s\n' '--- exact APT simulation ---'
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

[[ "$(package_inventory)" == "$inventory_before" ]]
[[ "$(protected_service_state)" == "$services_before" ]]
[[ "$(ss -H -lntup | sort)" == "$listeners_before" ]]
[[ -z "$(dpkg --audit)" ]]

uuid_status_after=$(
    dpkg-query -W -f='${db:Status-Abbrev}' uuid-runtime 2>/dev/null ||
        true
)
[[ "$uuid_status_after" == "$uuid_status" ]]
assert_absent_unit uuidd.service
assert_absent_unit uuidd.socket
if getent passwd uuidd >/dev/null ||
    getent group uuidd >/dev/null ||
    pgrep -x uuidd >/dev/null; then
    printf 'Unexpected uuidd state after read-only simulation.\n' >&2
    exit 1
fi

printf 'planned_install_count=%s\n' "$install_count"
printf 'planned_configure_count=%s\n' "$configure_count"
printf 'planned_remove_count=%s\n' "$remove_count"
printf 'uuid_runtime_preinstall_state_complete=true\n'
