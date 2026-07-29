#!/usr/bin/env bash

set -euo pipefail
umask 077

expected_version=2.38.1-5+deb12u3
expected_package_sha=ec80577364ed7bdd1dfcd8d0db9a7878f1c335d17867b20822077aa6242de411
expected_postinst_sha=5bf87cf7e0bf4a99d67ae91cd0279b1d316e10cc4b60007283d29762210ae460
expected_service_sha=a8090eeb6f09b0e895c97e2f27f9c656b27c269d3755f8da26e7f85f3aaaa4b9
expected_socket_sha=21f7cc7b5ffaf73b27f00689e628797a2be947df144b1a0f7ba9356c8d0a4897
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
uuid_policy=$(apt-cache policy uuid-runtime)
uuid_candidate=$(
    awk '/^[[:space:]]*Candidate:/ { print $2; exit }' <<<"$uuid_policy"
)
[[ "$uuid_candidate" == "$expected_version" ]]

if getent passwd uuidd >/dev/null ||
    getent group uuidd >/dev/null; then
    printf 'Unexpected uuidd identity before package inspection.\n' >&2
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
    printf 'Unexpected uuidd process before package inspection.\n' >&2
    exit 1
fi

mapfile -t old_staging < <(
    find /tmp -mindepth 1 -maxdepth 1 \
        -name 'uuid-runtime-package-audit-node-a.*' -print |
        sort
)
[[ "${#old_staging[@]}" -eq 0 ]]

[[ "$(dpkg-query -W -f='${db:Status-Abbrev}' caddy)" == 'ii ' ]]
[[ "$(dpkg-query -W -f='${Version}' caddy)" == 2.11.4 ]]
for unit in caddy.service caddy-api.service lsyncd.service; do
    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
done
if pgrep -x caddy >/dev/null ||
    pgrep -x lsyncd >/dev/null; then
    printf 'Unexpected Caddy or lsyncd process before package inspection.\n' >&2
    exit 1
fi

inventory_before=$(package_inventory)
services_before=$(protected_service_state)
listeners_before=$(ss -H -lntup | sort)
[[ -z "$(dpkg --audit)" ]]

work_dir=$(mktemp -d /tmp/uuid-runtime-package-audit-node-a.XXXXXX)
trap cleanup EXIT
cd "$work_dir"
apt-get download "uuid-runtime=$expected_version"

shopt -s nullglob
packages=(uuid-runtime_*_arm64.deb)
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

grep -Fxq 'Package: uuid-runtime' control/control
grep -Fxq "Version: $expected_version" control/control
grep -Fxq 'Architecture: arm64' control/control
[[ -f control/postinst && ! -L control/postinst ]]
printf '%s  %s\n' "$expected_postinst_sha" control/postinst |
    sha256sum --check --status

grep -Fq 'addgroup --system uuidd' control/postinst
grep -Fq 'adduser --system --quiet --ingroup uuidd' control/postinst
grep -Fq -- '--home /run/uuidd --no-create-home' control/postinst
grep -Fq 'chown uuidd:uuidd /var/lib/libuuid' control/postinst
grep -Fq 'chmod 2775 /var/lib/libuuid' control/postinst
grep -Fq "deb-systemd-helper enable 'uuidd.service'" control/postinst
grep -Fq "deb-systemd-helper enable 'uuidd.socket'" control/postinst
# shellcheck disable=SC2016 # Match the package script's literal variable.
grep -Fq 'invoke-rc.d --skip-systemd-native uuidd $_dh_action || exit 1' \
    control/postinst
# shellcheck disable=SC2016 # Match the package script's literal variable.
grep -Fq \
    "deb-systemd-invoke \$_dh_action 'uuidd.service' 'uuidd.socket'" \
    control/postinst
[[ "$(grep -Fc '_dh_action=start' control/postinst)" -eq 2 ]]

for target in \
    payload/etc/init.d/uuidd \
    payload/lib/systemd/system/uuidd.service \
    payload/lib/systemd/system/uuidd.socket \
    payload/usr/bin/uuidgen \
    payload/usr/bin/uuidparse \
    payload/usr/sbin/uuidd; do
    [[ -f "$target" && ! -L "$target" ]]
done
printf '%s  %s\n' \
    "$expected_service_sha" payload/lib/systemd/system/uuidd.service |
    sha256sum --check --status
printf '%s  %s\n' \
    "$expected_socket_sha" payload/lib/systemd/system/uuidd.socket |
    sha256sum --check --status

printf '%s\n' '--- uuid-runtime postinst ---'
sed -n '1,260p' control/postinst
printf '%s\n' '--- uuidd service artifacts ---'
sed -n '1,220p' payload/lib/systemd/system/uuidd.service
sed -n '1,220p' payload/lib/systemd/system/uuidd.socket
printf '%s\n' '--- lifecycle and service artifact hashes ---'
sha256sum \
    control/postinst \
    payload/etc/init.d/uuidd \
    payload/lib/systemd/system/uuidd.service \
    payload/lib/systemd/system/uuidd.socket

cd /
rm -rf -- "$work_dir"
work_dir=
trap - EXIT

mapfile -t remaining_staging < <(
    find /tmp -mindepth 1 -maxdepth 1 \
        -name 'uuid-runtime-package-audit-node-a.*' -print |
        sort
)
[[ "${#remaining_staging[@]}" -eq 0 ]]
[[ "$(package_inventory)" == "$inventory_before" ]]
[[ "$(protected_service_state)" == "$services_before" ]]
[[ "$(ss -H -lntup | sort)" == "$listeners_before" ]]
[[ -z "$(dpkg --audit)" ]]

uuid_status=$(
    dpkg-query -W -f='${db:Status-Abbrev}' uuid-runtime 2>/dev/null ||
        true
)
[[ -z "$uuid_status" || "$uuid_status" == 'un ' ]]
if getent passwd uuidd >/dev/null ||
    getent group uuidd >/dev/null; then
    printf 'Unexpected uuidd identity after package inspection.\n' >&2
    exit 1
fi
[[ ! -e /var/lib/libuuid && ! -L /var/lib/libuuid ]]
assert_absent_unit uuidd.service
assert_absent_unit uuidd.socket
for unit in caddy.service caddy-api.service lsyncd.service; do
    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
done

printf 'uuid_runtime_package_sha256=%s\n' "$expected_package_sha"
printf 'uuid_runtime_postinst_sha256=%s\n' "$expected_postinst_sha"
printf 'uuid_runtime_package_audit_complete=true\n'
