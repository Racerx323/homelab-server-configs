#!/usr/bin/env bash
set -euo pipefail

readonly live_lighttpd=/etc/lighttpd
readonly failed_retry2=/etc/.lighttpd-caddy-action15-retry2.failed
readonly candidate_retry2=/etc/.lighttpd-caddy-action15-retry2
readonly original_retry2=/etc/.lighttpd-pre-action15-retry2
readonly previous_retry_failed=/etc/.lighttpd-caddy-action15-retry.failed
readonly historical_failed=/etc/.lighttpd-caddy-action15.failed
readonly caddy_environment=/etc/default/caddy-ha
readonly caddy_config=/etc/caddy/current/Caddyfile
readonly caddy_vrrp=/etc/keepalived/conf.d/caddy-ha.conf

readonly live_tree_sha256=3f48f2374c76207c10841fc8305a1c83e803d68c3698e650f0ee38c928e68bab
readonly previous_retry_failed_tree_sha256=c693c9d391785f45f95d62c7c77424f74e6a85ba55d61795b21310d827158b59
readonly historical_failed_tree_sha256=0bdc6ce0d71ae20eba11db969ed57852dd3f2aa5fc89b0e96ced979c40fe9ab9
readonly keepalived_tree_sha256=68d2bc846ad94da2a995f52e0f7829ff1c5706f35e399e40e1a0a552f37afd4f
readonly caddy_environment_sha256=f692d5b7e0a7e0f0ab142e36face6a8cc8c6680a44a2bcaf6a992247ec4c8113

tree_hash() {
    local root=$1

    (
        cd "$root"
        find . -type f -print0 |
            sort -z |
            xargs -0 sha256sum
    ) | sha256sum | awk '{print $1}'
}

tcp_listener_owned_by() {
    local port=$1
    local process=$2

    ss -H -lntp "sport = :$port" | grep -Fq "\"$process\""
}

[[ $EUID -eq 0 ]]
for command_name in caddy curl journalctl lighttpd runuser sha256sum ss systemctl; do
    command -v "$command_name" >/dev/null
done

[[ -d "$live_lighttpd" && ! -L "$live_lighttpd" ]]
[[ -d "$failed_retry2" && ! -L "$failed_retry2" ]]
[[ -d "$previous_retry_failed" && ! -L "$previous_retry_failed" ]]
[[ -d "$historical_failed" && ! -L "$historical_failed" ]]
[[ ! -e "$candidate_retry2" ]]
[[ ! -e "$original_retry2" ]]
[[ ! -e "$caddy_vrrp" ]]

[[ "$(tree_hash "$live_lighttpd")" == "$live_tree_sha256" ]]
[[ "$(tree_hash "$previous_retry_failed")" == "$previous_retry_failed_tree_sha256" ]]
[[ "$(tree_hash "$historical_failed")" == "$historical_failed_tree_sha256" ]]
[[ "$(tree_hash /etc/keepalived)" == "$keepalived_tree_sha256" ]]
[[ "$(sha256sum "$caddy_environment" | awk '{print $1}')" == "$caddy_environment_sha256" ]]

grep -Fqx \
    'include "/etc/lighttpd/conf-enabled/*.conf"' \
    "$failed_retry2/lighttpd.conf"
lighttpd -tt -f "$live_lighttpd/lighttpd.conf"
[[ "$(systemctl is-active lighttpd)" == active ]]
[[ "$(systemctl is-enabled lighttpd)" == enabled ]]
tcp_listener_owned_by 80 lighttpd
tcp_listener_owned_by 443 lighttpd
curl --insecure --fail --silent --show-error --head \
    --connect-timeout 1 --max-time 3 \
    --resolve pihole00.local.theama.co:443:10.1.0.54 \
    https://pihole00.local.theama.co/admin/ >/dev/null

set -a
# shellcheck disable=SC1090
source "$caddy_environment"
set +a
runuser -u caddy -- \
    caddy validate --config "$caddy_config" --adapter caddyfile

printf '%s\n' '--- paths and hashes ---'
printf 'live_lighttpd_tree_sha256=%s\n' "$(tree_hash "$live_lighttpd")"
printf 'failed_retry2_main_sha256=%s\n' \
    "$(sha256sum "$failed_retry2/lighttpd.conf" | awk '{print $1}')"
printf 'failed_retry2_tree_sha256=%s\n' "$(tree_hash "$failed_retry2")"
printf 'previous_retry_failed_tree_sha256=%s\n' \
    "$(tree_hash "$previous_retry_failed")"
printf 'historical_failed_tree_sha256=%s\n' \
    "$(tree_hash "$historical_failed")"
printf 'keepalived_tree_sha256=%s\n' "$(tree_hash /etc/keepalived)"

printf '%s\n' '--- unit state ---'
systemctl show caddy.service \
    --property=LoadState \
    --property=ActiveState \
    --property=SubState \
    --property=UnitFileState \
    --property=Result \
    --property=ExecMainCode \
    --property=ExecMainStatus \
    --property=NRestarts
systemctl show lighttpd.service \
    --property=LoadState \
    --property=ActiveState \
    --property=SubState \
    --property=UnitFileState \
    --property=Result \
    --property=ExecMainCode \
    --property=ExecMainStatus \
    --property=NRestarts
for unit in caddy-api lsyncd caddy-lsyncd keepalived; do
    printf '%s=%s/%s\n' \
        "$unit" \
        "$(systemctl is-active "$unit" 2>/dev/null || true)" \
        "$(systemctl is-enabled "$unit" 2>/dev/null || true)"
done

printf '%s\n' '--- relevant listeners ---'
ss -H -lntup |
    awk '$5 ~ /:(80|443|8080|2019)$/ {print}' |
    sort

printf '%s\n' '--- bounded caddy journal ---'
journalctl --unit=caddy.service \
    --since='2026-07-28 03:59:00 UTC' \
    --no-pager --output=short-iso --lines=160
printf '%s\n' '--- bounded lighttpd journal ---'
journalctl --unit=lighttpd.service \
    --since='2026-07-28 03:59:00 UTC' \
    --no-pager --output=short-iso --lines=80

printf 'action_15_retry2_failure_inspection_complete=true\n'
