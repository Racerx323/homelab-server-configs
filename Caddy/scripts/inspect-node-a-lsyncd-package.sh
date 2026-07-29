#!/usr/bin/env bash

set -euo pipefail
umask 077

expected_version=2.2.3-1
expected_package_sha=25fc747c79502cab339be19e1ffe10155cf098b2621dd3f28fd47c19ffdfe45a
expected_postinst_sha=729e7b309d25efccb425c8b832de4a20567553509fbf7cced30f352b5c0287b4
work_dir=

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

cleanup() {
    original_rc=$?
    trap - EXIT
    if [[ -n "$work_dir" && -d "$work_dir" ]]; then
        rm -rf -- "$work_dir"
    fi
    exit "$original_rc"
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

mapfile -t old_staging < <(
    find /tmp -mindepth 1 -maxdepth 1 \
        -name 'lsyncd-package-audit-node-a.*' -print |
        sort
)
if ((${#old_staging[@]} != 0)); then
    printf 'Unexpected existing lsyncd audit staging: %s\n' \
        "${old_staging[@]}" >&2
    exit 1
fi

inventory_before=$(package_inventory)
services_before=$(protected_service_state)
listeners_before=$(ss -H -lntup | sort)
[[ -z "$(dpkg --audit)" ]]

work_dir=$(mktemp -d /tmp/lsyncd-package-audit-node-a.XXXXXX)
trap cleanup EXIT
cd "$work_dir"
apt-get download "lsyncd=$expected_version"

shopt -s nullglob
packages=(lsyncd_*_arm64.deb)
shopt -u nullglob
[[ "${#packages[@]}" -eq 1 ]]
package_file=${packages[0]}
[[ -f "$package_file" && ! -L "$package_file" ]]
printf '%s  %s\n' "$expected_package_sha" "$package_file" |
    sha256sum --check --status

mkdir control payload
dpkg-deb --control "$package_file" control
dpkg-deb --extract "$package_file" payload
dpkg-deb --info "$package_file"
dpkg-deb --contents "$package_file"

grep -Fxq 'Package: lsyncd' control/control
grep -Fxq "Version: $expected_version" control/control
grep -Fxq 'Architecture: arm64' control/control
[[ -f control/postinst && ! -L control/postinst ]]
printf '%s  %s\n' "$expected_postinst_sha" control/postinst |
    sha256sum --check --status
grep -Fq 'update-rc.d lsyncd defaults' control/postinst
grep -Fq '_dh_action=start' control/postinst
# shellcheck disable=SC2016 # Match the package script's literal variable.
grep -Fq 'invoke-rc.d lsyncd $_dh_action || exit 1' control/postinst
[[ -f payload/etc/init.d/lsyncd && ! -L payload/etc/init.d/lsyncd ]]
[[ -x payload/etc/init.d/lsyncd ]]
[[ ! -e payload/lib/systemd/system/lsyncd.service ]]

printf '%s\n' '--- lsyncd postinst ---'
sed -n '1,240p' control/postinst
printf '%s\n' '--- lifecycle and service artifact hashes ---'
sha256sum control/postinst payload/etc/init.d/lsyncd

cd /
rm -rf -- "$work_dir"
work_dir=
trap - EXIT

mapfile -t remaining_staging < <(
    find /tmp -mindepth 1 -maxdepth 1 \
        -name 'lsyncd-package-audit-node-a.*' -print |
        sort
)
[[ "${#remaining_staging[@]}" -eq 0 ]]
[[ "$(package_inventory)" == "$inventory_before" ]]
[[ "$(protected_service_state)" == "$services_before" ]]
[[ "$(ss -H -lntup | sort)" == "$listeners_before" ]]
[[ -z "$(dpkg --audit)" ]]
status=$(
    dpkg-query -W -f='${db:Status-Abbrev}' lsyncd 2>/dev/null ||
        true
)
[[ -z "$status" || "$status" == 'un ' ]]
[[ "$(systemctl show --property=LoadState --value lsyncd.service)" == not-found ]]
[[ "$(systemctl is-active lsyncd.service 2>/dev/null || true)" == inactive ]]
for unit in caddy.service caddy-api.service; do
    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
done

printf 'lsyncd_package_sha256=%s\n' "$expected_package_sha"
printf 'lsyncd_package_audit_complete=true\n'
