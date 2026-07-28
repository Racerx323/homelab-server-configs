#!/usr/bin/env bash
set -euo pipefail

readonly caddy_override=/etc/systemd/system/caddy.service.d/override.conf
readonly expected_override_sha256=82535a41bbcbc18e4a875f5359bac3c27071c9472feee5c3232d06a138e99921

tcp_listener_owned_by() {
    local port=$1
    local process=$2

    ss -H -lntp "sport = :$port" | grep -Fq "\"$process\""
}

[[ $EUID -eq 0 ]]
for command_name in dpkg-query find journalctl readlink sed sha256sum ss stat systemctl; do
    command -v "$command_name" >/dev/null
done

[[ "$(systemctl is-active caddy.service 2>/dev/null || true)" == failed ]]
[[ "$(systemctl is-enabled caddy.service 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active lighttpd.service)" == active ]]
[[ "$(systemctl is-enabled lighttpd.service)" == enabled ]]
[[ -f "$caddy_override" && ! -L "$caddy_override" ]]
[[ "$(sha256sum "$caddy_override" | awk '{print $1}')" == "$expected_override_sha256" ]]
tcp_listener_owned_by 80 lighttpd
tcp_listener_owned_by 443 lighttpd
if ss -H -lntup | awk '$5 ~ /:(8080|2019)$/ {found=1} END {exit !found}'; then
    exit 1
fi
if ss -H -lunp "sport = :443" | grep -q .; then
    exit 1
fi

printf '%s\n' '--- package and mask provenance ---'
dpkg-query --show --showformat='${Package} ${Version} ${db:Status-Status}\n' caddy
stat --printf='%A %U:%G %s %N\n' /etc/systemd/system/caddy.service
printf 'mask_target=%s\n' "$(readlink /etc/systemd/system/caddy.service)"

printf '%s\n' '--- vendor unit candidates ---'
vendor_count=0
while IFS= read -r -d '' unit_path; do
    vendor_count=$((vendor_count + 1))
    stat --printf='%A %U:%G %s %n\n' "$unit_path"
    sha256sum "$unit_path"
    sed -n '1,240p' "$unit_path"
done < <(
    find /lib/systemd/system /usr/lib/systemd/system \
        -xdev -maxdepth 1 -type f -name caddy.service -print0 2>/dev/null |
        sort -z
)
((vendor_count > 0))

printf '%s\n' '--- installed override bytes ---'
stat --printf='%A %U:%G %s %n\n' "$caddy_override"
sha256sum "$caddy_override"
sed -n l "$caddy_override"

printf '%s\n' '--- effective unit timeout and lifecycle properties ---'
systemctl show caddy.service \
    --property=Type \
    --property=NotifyAccess \
    --property=TimeoutStartUSec \
    --property=TimeoutStopUSec \
    --property=TimeoutAbortUSec \
    --property=TimeoutStartFailureMode \
    --property=TimeoutStopFailureMode \
    --property=KillMode \
    --property=KillSignal \
    --property=FinalKillSignal \
    --property=SendSIGKILL \
    --property=Restart \
    --property=RestartUSec \
    --property=LoadState \
    --property=ActiveState \
    --property=SubState \
    --property=UnitFileState \
    --property=Result \
    --property=ExecMainCode \
    --property=ExecMainStatus \
    --property=ExecStart \
    --property=ExecStop \
    --property=ExecStopPost \
    --property=ActiveEnterTimestamp \
    --property=InactiveEnterTimestamp \
    --property=StateChangeTimestamp \
    --property=FragmentPath \
    --property=DropInPaths

printf '%s\n' '--- bounded timeout journal ---'
journalctl --unit=caddy.service \
    --since='2026-07-28 03:59:00 UTC' \
    --until='2026-07-28 04:06:00 UTC' \
    --no-pager --output=short-iso --lines=260

printf '%s\n' '--- relevant listeners ---'
ss -H -lntup |
    awk '$5 ~ /:(80|443|8080|2019)$/ {print}' |
    sort

printf 'action_15_timeout_provenance_complete=true\n'
