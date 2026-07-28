#!/usr/bin/env bash
set -euo pipefail

readonly live_lighttpd=/etc/lighttpd
readonly failed_cutover=/etc/.lighttpd-caddy-action15-retry.failed
readonly candidate_lighttpd=/etc/.lighttpd-caddy-action15-retry
readonly original_lighttpd=/etc/.lighttpd-pre-action15-retry
readonly accepted_stage=/var/tmp/caddy-ha-lighttpd-node-b-action15-retry
readonly historical_failed=/etc/.lighttpd-caddy-action15.failed
readonly caddy_vrrp=/etc/keepalived/conf.d/caddy-ha.conf

readonly live_tree_sha256=3f48f2374c76207c10841fc8305a1c83e803d68c3698e650f0ee38c928e68bab
readonly failed_main_sha256=b712ee21f71a9102ef90d53d07d0a783a1fd848c1fa307d20166029dc14dd248
readonly failed_tree_sha256=c693c9d391785f45f95d62c7c77424f74e6a85ba55d61795b21310d827158b59
readonly historical_failed_tree_sha256=0bdc6ce0d71ae20eba11db969ed57852dd3f2aa5fc89b0e96ced979c40fe9ab9
readonly keepalived_tree_sha256=68d2bc846ad94da2a995f52e0f7829ff1c5706f35e399e40e1a0a552f37afd4f

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
for command_name in curl grep lighttpd sha256sum ss systemctl; do
    command -v "$command_name" >/dev/null
done

[[ -d "$live_lighttpd" && ! -L "$live_lighttpd" ]]
[[ -d "$failed_cutover" && ! -L "$failed_cutover" ]]
[[ -d "$historical_failed" && ! -L "$historical_failed" ]]
[[ -d "$accepted_stage" && ! -L "$accepted_stage" ]]
[[ ! -e "$candidate_lighttpd" ]]
[[ ! -e "$original_lighttpd" ]]
[[ ! -e "$caddy_vrrp" ]]

[[ "$(tree_hash "$live_lighttpd")" == "$live_tree_sha256" ]]
[[ "$(sha256sum "$failed_cutover/lighttpd.conf" | awk '{print $1}')" == "$failed_main_sha256" ]]
[[ "$(tree_hash "$failed_cutover")" == "$failed_tree_sha256" ]]
[[ "$(tree_hash "$historical_failed")" == "$historical_failed_tree_sha256" ]]
[[ "$(tree_hash /etc/keepalived)" == "$keepalived_tree_sha256" ]]

grep -Fqx \
    'include "/etc/.lighttpd-caddy-action15-retry/conf-enabled/*.conf"' \
    "$failed_cutover/lighttpd.conf"
if grep -Fq \
    'include "/etc/lighttpd/conf-enabled/*.conf"' \
    "$failed_cutover/lighttpd.conf"; then
    printf 'Failed cutover tree unexpectedly contains the live include root.\n' >&2
    exit 1
fi

lighttpd -tt -f "$live_lighttpd/lighttpd.conf"
[[ "$(systemctl is-active lighttpd)" == active ]]
[[ "$(systemctl is-enabled lighttpd)" == enabled ]]
[[ "$(systemctl is-active caddy 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled caddy 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active caddy-api 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled caddy-api 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active lsyncd 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled lsyncd 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active caddy-lsyncd 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled caddy-lsyncd 2>/dev/null || true)" == disabled ]]
[[ "$(systemctl is-active keepalived)" == active ]]
[[ "$(systemctl is-enabled keepalived)" == enabled ]]

tcp_listener_owned_by 80 lighttpd
tcp_listener_owned_by 443 lighttpd
if ss -H -lntp 'sport = :8080' | grep -q .; then
    printf 'TCP 8080 is unexpectedly occupied.\n' >&2
    exit 1
fi
if ss -H -lntp 'sport = :2019' | grep -q .; then
    printf 'TCP 2019 is unexpectedly occupied.\n' >&2
    exit 1
fi
if ss -H -lnup 'sport = :443' | grep -q .; then
    printf 'UDP 443 is unexpectedly occupied.\n' >&2
    exit 1
fi

curl --insecure --fail --silent --show-error --head \
    --connect-timeout 1 --max-time 3 \
    --resolve pihole00.local.theama.co:443:10.1.0.54 \
    https://pihole00.local.theama.co/admin/ >/dev/null

printf 'live_lighttpd_tree_sha256=%s\n' "$(tree_hash "$live_lighttpd")"
printf 'failed_cutover_main_sha256=%s\n' \
    "$(sha256sum "$failed_cutover/lighttpd.conf" | awk '{print $1}')"
printf 'failed_cutover_tree_sha256=%s\n' "$(tree_hash "$failed_cutover")"
printf 'historical_failed_tree_sha256=%s\n' \
    "$(tree_hash "$historical_failed")"
printf 'keepalived_tree_sha256=%s\n' "$(tree_hash /etc/keepalived)"
ss -H -lntup |
    awk '$5 ~ /:(80|443|8080|2019)$/ {print}' |
    sort
printf 'action_15_retry_rollback_inspection_complete=true\n'
