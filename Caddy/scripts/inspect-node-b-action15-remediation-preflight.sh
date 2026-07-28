#!/usr/bin/env bash
set -euo pipefail

readonly caddy_current=/etc/caddy/current
readonly caddy_environment=/etc/default/caddy-ha
readonly caddy_override=/etc/systemd/system/caddy.service.d/override.conf
readonly proposed_release=/etc/caddy/releases/action15-health-follow-redirects
readonly proposed_stage=/var/tmp/caddy-ha-action15-remediation

readonly expected_caddyfile_sha256=a42cd4d0c35352b1efe428698e5e0a6946476ab81c77caae607b58e13ef5cc02
readonly expected_pihole_route_sha256=4b51ce90cc9015579eb441538d44b43165572c9298bff7a78b79fed732373b7c
readonly expected_environment_sha256=f692d5b7e0a7e0f0ab142e36face6a8cc8c6680a44a2bcaf6a992247ec4c8113

tcp_listener_owned_by() {
    local port=$1
    local process=$2

    ss -H -lntp "sport = :$port" | grep -Fq "\"$process\""
}

[[ $EUID -eq 0 ]]
for command_name in caddy curl find lighttpd readlink runuser sha256sum ss stat systemctl; do
    command -v "$command_name" >/dev/null
done

[[ -L "$caddy_current" ]]
release_dir=$(readlink -e "$caddy_current")
[[ -n "$release_dir" ]]
[[ "$release_dir" == /etc/caddy/releases/* ]]
[[ -d "$release_dir" && ! -L "$release_dir" ]]
[[ "$(sha256sum "$release_dir/Caddyfile" | awk '{print $1}')" == "$expected_caddyfile_sha256" ]]
[[ "$(sha256sum "$release_dir/conf.d/10-pihole-admin.caddy" | awk '{print $1}')" == "$expected_pihole_route_sha256" ]]
[[ "$(sha256sum "$caddy_environment" | awk '{print $1}')" == "$expected_environment_sha256" ]]

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

set -a
# shellcheck disable=SC1090
source "$caddy_environment"
set +a
runuser -u caddy -- \
    caddy validate --config "$release_dir/Caddyfile" --adapter caddyfile

printf '%s\n' '--- current release topology ---'
printf 'caddy_current_target=%s\n' "$release_dir"
printf 'proposed_release_state=%s\n' "$([[ -e "$proposed_release" || -L "$proposed_release" ]] && printf present || printf absent)"
printf 'proposed_stage_state=%s\n' "$([[ -e "$proposed_stage" || -L "$proposed_stage" ]] && printf present || printf absent)"
find "$release_dir" -xdev -maxdepth 2 \
    \( -type f -o -type l \) \
    -printf '%M %u:%g %p -> %l\n' |
    sort

printf '%s\n' '--- current release hashes ---'
find "$release_dir" -xdev -type f -print0 |
    sort -z |
    xargs -0 sha256sum

printf '%s\n' '--- completion and manifest artifacts ---'
for name in .complete release-manifest.json manifest.sha256; do
    path="$release_dir/$name"
    if [[ -e "$path" || -L "$path" ]]; then
        stat --printf='%A %U:%G %s %n\n' "$path"
        if [[ -f "$path" ]]; then
            sha256sum "$path"
        fi
    else
        printf 'absent %s\n' "$path"
    fi
done

printf '%s\n' '--- caddy unit state and stop contract ---'
systemctl show caddy.service \
    --property=LoadState \
    --property=ActiveState \
    --property=SubState \
    --property=UnitFileState \
    --property=Result \
    --property=TimeoutStopUSec \
    --property=TimeoutStopFailureMode \
    --property=KillMode \
    --property=FragmentPath \
    --property=DropInPaths
if [[ -f "$caddy_override" ]]; then
    stat --printf='%A %U:%G %s %n\n' "$caddy_override"
    sha256sum "$caddy_override"
else
    printf 'absent %s\n' "$caddy_override"
fi
systemctl cat caddy.service

printf '%s\n' '--- relevant listeners ---'
ss -H -lntup |
    awk '$5 ~ /:(80|443|8080|2019)$/ {print}' |
    sort

printf 'action_15_remediation_preflight_complete=true\n'
