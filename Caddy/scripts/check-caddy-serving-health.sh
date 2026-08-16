#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly environment_file=${CADDY_SERVING_HEALTH_ENVIRONMENT_FILE:-/etc/default/caddy-ha}
readonly curl_command=${CADDY_SERVING_HEALTH_CURL_COMMAND:-/usr/bin/curl}
readonly ss_command=${CADDY_SERVING_HEALTH_SS_COMMAND:-/usr/bin/ss}
readonly systemctl_command=${CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}

fail() {
    printf 'caddy_serving_health_check_%s=false\n' "$1" >&2
    exit 1
}

[[ -f "$environment_file" && ! -L "$environment_file" ]] || fail environment
# shellcheck disable=SC1090
source "$environment_file"
: "${NODE_FQDN:?missing NODE_FQDN}"
: "${NODE_IPV4:?missing NODE_IPV4}"
: "${NODE_IPV6:?missing NODE_IPV6}"
readonly NODE_FQDN NODE_IPV4 NODE_IPV6

"$systemctl_command" is-active --quiet caddy.service || fail service

capture_root=$(mktemp -d /tmp/check-caddy-serving-health.XXXXXX)
readonly capture_root
trap 'rm -rf -- "$capture_root"' EXIT

probe() {
    local serving_health_family=$1
    local serving_health_address=$2
    local serving_health_output=$3

    "$curl_command" "--ipv$serving_health_family" --silent --show-error \
        --fail --max-time 1 --max-redirs 0 --output /dev/null \
        --write-out '%{http_code}\n' \
        --resolve "$NODE_FQDN:443:$serving_health_address" \
        "https://$NODE_FQDN/healthz" >"$serving_health_output" 2>&1
}

probe 4 "$NODE_IPV4" "$capture_root/ipv4" &
ipv4_pid=$!
probe 6 "[$NODE_IPV6]" "$capture_root/ipv6" &
ipv6_pid=$!
readonly ipv4_pid ipv6_pid

ipv4_ok=true
ipv6_ok=true
wait "$ipv4_pid" || ipv4_ok=false
wait "$ipv6_pid" || ipv6_ok=false
[[ "$ipv4_ok" = true ]] || fail ipv4_https
[[ "$ipv6_ok" = true ]] || fail ipv6_https
[[ "$(<"$capture_root/ipv4")" = 204 ]] || fail ipv4_status
[[ "$(<"$capture_root/ipv6")" = 204 ]] || fail ipv6_status

"$ss_command" -H -ltn >"$capture_root/tcp"
"$ss_command" -H -lun >"$capture_root/udp"
grep -Fq -- "$NODE_IPV4:443" "$capture_root/tcp" || fail ipv4_tcp_listener
grep -Fq -- "[$NODE_IPV6]:443" "$capture_root/tcp" || fail ipv6_tcp_listener
grep -Fq -- "$NODE_IPV4:443" "$capture_root/udp" || fail ipv4_udp_listener
grep -Fq -- "[$NODE_IPV6]:443" "$capture_root/udp" || fail ipv6_udp_listener

printf 'caddy_serving_health_check_service=true\n'
printf 'caddy_serving_health_check_ipv4_https=true\n'
printf 'caddy_serving_health_check_ipv6_https=true\n'
printf 'caddy_serving_health_check_listeners=true\n'
printf 'caddy_serving_health_complete=true\n'
