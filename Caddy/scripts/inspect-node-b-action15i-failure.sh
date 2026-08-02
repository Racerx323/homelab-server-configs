#!/usr/bin/env bash
set -euo pipefail

readonly current_release=/etc/caddy/releases/bootstrap
readonly current_link=/etc/caddy/current
readonly current_override=/etc/systemd/system/caddy.service.d/override.conf
readonly stage=/var/tmp/caddy-ha-action15-remediation

readonly current_caddyfile_sha256=a42cd4d0c35352b1efe428698e5e0a6946476ab81c77caae607b58e13ef5cc02
readonly current_route_sha256=4b51ce90cc9015579eb441538d44b43165572c9298bff7a78b79fed732373b7c
readonly current_override_sha256=82535a41bbcbc18e4a875f5359bac3c27071c9472feee5c3232d06a138e99921

tcp_listener_owned_by() {
    local port=$1
    local process=$2

    ss -H -lntp "sport = :$port" | grep -Fq "\"$process\""
}

[[ $EUID -eq 0 ]]
for command_name in curl find lighttpd readlink sha256sum ss systemctl; do
    command -v "$command_name" >/dev/null
done

[[ ! -e "$stage" && ! -L "$stage" ]]
[[ -z "$(find /var/tmp -xdev -maxdepth 1 \
    -name '.caddy-action15i-payload.*' -print -quit)" ]]
[[ -z "$(find /var/tmp -xdev -maxdepth 1 \
    -name '.caddy-action15-validate.*' -print -quit)" ]]

[[ -L "$current_link" ]]
[[ "$(readlink -e "$current_link")" == "$current_release" ]]
[[ "$(sha256sum "$current_release/Caddyfile" | awk '{print $1}')" == "$current_caddyfile_sha256" ]]
[[ "$(sha256sum "$current_release/conf.d/10-pihole-admin.caddy" | awk '{print $1}')" == "$current_route_sha256" ]]
[[ "$(sha256sum "$current_override" | awk '{print $1}')" == "$current_override_sha256" ]]

[[ "$(systemctl is-active caddy.service 2>/dev/null || true)" == failed ]]
[[ "$(systemctl is-enabled caddy.service 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active lighttpd.service)" == active ]]
[[ "$(systemctl is-enabled lighttpd.service)" == enabled ]]
tcp_listener_owned_by 80 lighttpd
tcp_listener_owned_by 443 lighttpd
if ss -H -lntup | awk '$5 ~ /:(8080|2019)$/ {found=1} END {exit !found}'; then
    exit 1
fi
if ss -H -lunp "sport = :443" | grep -q .; then
    exit 1
fi

lighttpd -tt -f /etc/lighttpd/lighttpd.conf
curl --insecure --fail --silent --show-error --head \
    --connect-timeout 1 --max-time 3 \
    --resolve pihole00.local.theama.co:443:10.1.0.54 \
    https://pihole00.local.theama.co/admin/ >/dev/null

printf 'current_release=%s\n' "$(readlink -e "$current_link")"
printf 'current_caddyfile_sha256=%s\n' "$current_caddyfile_sha256"
printf 'current_route_sha256=%s\n' "$current_route_sha256"
printf 'current_override_sha256=%s\n' "$current_override_sha256"
printf 'action_15i_failure_inspection_complete=true\n'
