#!/usr/bin/env bash
set -euo pipefail

readonly live_lighttpd=/etc/lighttpd
readonly original_lighttpd=/etc/.lighttpd-pre-action15-retry3
readonly retry2_failed=/etc/.lighttpd-caddy-action15-retry2.failed
readonly retry1_failed=/etc/.lighttpd-caddy-action15-retry.failed
readonly historical_failed=/etc/.lighttpd-caddy-action15.failed
readonly caddy_current=/etc/caddy/current
readonly caddy_release=/etc/caddy/releases/action15-health-follow-redirects
readonly caddy_environment=/etc/default/caddy-ha
readonly caddy_override=/etc/systemd/system/caddy.service.d/override.conf

readonly promoted_lighttpd_tree_sha256=c627aa2d7915ae64ded7e0b788477d737ebe71b9fb81638c6369ddedf7c5818d
readonly original_lighttpd_tree_sha256=3f48f2374c76207c10841fc8305a1c83e803d68c3698e650f0ee38c928e68bab
readonly retry2_failed_tree_sha256=c627aa2d7915ae64ded7e0b788477d737ebe71b9fb81638c6369ddedf7c5818d
readonly retry1_failed_tree_sha256=c693c9d391785f45f95d62c7c77424f74e6a85ba55d61795b21310d827158b59
readonly historical_failed_tree_sha256=0bdc6ce0d71ae20eba11db969ed57852dd3f2aa5fc89b0e96ced979c40fe9ab9
readonly caddy_tree_sha256=8149af81a446d15fc10b4012f304461d87c41fc57d9e0a2aaa5e3419eb5c1d49
readonly caddy_override_sha256=a292487f4cbde99abce048b97ec15dbae8ef511ec845dcf5740f343e143f39df

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

udp_listener_owned_by() {
    local port=$1
    local process=$2

    ss -H -lnup "sport = :$port" | grep -Fq "\"$process\""
}

[[ $EUID -eq 0 ]]
for command_name in caddy curl grep journalctl lighttpd openssl readlink runuser sha256sum ss systemctl; do
    command -v "$command_name" >/dev/null
done

[[ -d "$live_lighttpd" && ! -L "$live_lighttpd" ]]
[[ -d "$original_lighttpd" && ! -L "$original_lighttpd" ]]
[[ -d "$retry2_failed" && ! -L "$retry2_failed" ]]
[[ -d "$retry1_failed" && ! -L "$retry1_failed" ]]
[[ -d "$historical_failed" && ! -L "$historical_failed" ]]
[[ ! -e /etc/.lighttpd-caddy-action15-retry3 ]]
[[ ! -e /etc/.lighttpd-caddy-action15-retry3.failed ]]
[[ "$(tree_hash "$live_lighttpd")" == "$promoted_lighttpd_tree_sha256" ]]
[[ "$(tree_hash "$original_lighttpd")" == "$original_lighttpd_tree_sha256" ]]
[[ "$(tree_hash "$retry2_failed")" == "$retry2_failed_tree_sha256" ]]
[[ "$(tree_hash "$retry1_failed")" == "$retry1_failed_tree_sha256" ]]
[[ "$(tree_hash "$historical_failed")" == "$historical_failed_tree_sha256" ]]
[[ "$(tree_hash /etc/caddy)" == "$caddy_tree_sha256" ]]
[[ -L "$caddy_current" ]]
[[ "$(readlink -e "$caddy_current")" == "$caddy_release" ]]
[[ "$(sha256sum "$caddy_override" | awk '{print $1}')" == "$caddy_override_sha256" ]]

[[ "$(systemctl is-active caddy.service)" == active ]]
[[ "$(systemctl is-enabled caddy.service)" == disabled ]]
[[ "$(systemctl show caddy.service --property=Type --value)" == notify ]]
[[ "$(systemctl show caddy.service --property=TimeoutStopUSec --value)" == 30s ]]
[[ "$(systemctl is-active lighttpd.service)" == active ]]
[[ "$(systemctl is-enabled lighttpd.service)" == enabled ]]
[[ "$(systemctl is-active keepalived.service)" == active ]]
[[ "$(systemctl is-enabled keepalived.service)" == enabled ]]
[[ "$(systemctl is-active lsyncd.service 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" == masked ]]
[[ ! -e /etc/keepalived/conf.d/caddy-ha.conf ]]

tcp_listener_owned_by 80 caddy
tcp_listener_owned_by 443 caddy
udp_listener_owned_by 443 caddy
tcp_listener_owned_by 8080 lighttpd
tcp_listener_owned_by 2019 caddy
ss -H -lntp 'sport = :8080' |
    grep -F '127.0.0.1:8080' |
    grep -Fq '"lighttpd"'
if ss -H -lntp 'sport = :8080' | grep -qEv '127\.0\.0\.1:8080'; then
    exit 1
fi
ss -H -lntp 'sport = :2019' |
    grep -F '127.0.0.1:2019' |
    grep -Fq '"caddy"'

lighttpd -tt -f "$live_lighttpd/lighttpd.conf"
backend_code=$(
    curl --silent --show-error \
        --connect-timeout 1 --max-time 3 \
        --output /dev/null --write-out '%{http_code}' \
        http://127.0.0.1:8080/admin/
)
[[ "$backend_code" =~ ^[23][0-9][0-9]$ ]]

set -a
# shellcheck disable=SC1090
source "$caddy_environment"
set +a
runuser -u caddy -- \
    caddy validate --config "$caddy_current/Caddyfile" --adapter caddyfile
curl --insecure --fail --silent --show-error --head \
    --connect-timeout 1 --max-time 3 \
    https://localhost/ >/dev/null
for protocol in --http1.1 --http2; do
    code=$(
        curl "$protocol" --insecure --silent --show-error \
            --connect-timeout 1 --max-time 3 \
            --resolve pihole00.local.theama.co:443:10.1.0.54 \
            --output /dev/null --write-out '%{http_code}' \
            https://pihole00.local.theama.co/admin/
    )
    [[ "$code" =~ ^[23][0-9][0-9]$ ]]
done

service_journal=$(
    journalctl --unit=caddy.service \
        --since='2026-07-28 04:40:00 UTC' \
        --no-pager --output=short-iso --lines=160
)
if grep -Fq 'status code out of tolerances' <<<"$service_journal"; then
    exit 1
fi
if grep -Fq 'installing root certificate' <<<"$service_journal"; then
    exit 1
fi

printf '%s\n' '--- served certificate ---'
openssl s_client \
    -connect 10.1.0.54:443 \
    -servername pihole00.local.theama.co \
    </dev/null 2>/dev/null |
    openssl x509 -noout -subject -issuer -dates -ext subjectAltName
printf '%s\n' '--- service properties ---'
systemctl show caddy.service \
    --property=ActiveState \
    --property=SubState \
    --property=UnitFileState \
    --property=Result \
    --property=Type \
    --property=TimeoutStopUSec
printf '%s\n' '--- relevant listeners ---'
ss -H -lntup |
    awk '$5 ~ /:(80|443|8080|2019)$/ {print}' |
    sort
printf '%s\n' '--- bounded caddy journal ---'
printf '%s\n' "$service_journal"
printf 'backend_http_code=%s\n' "$backend_code"
printf 'action_15_cutover_validation_complete=true\n'
