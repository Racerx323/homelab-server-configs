#!/usr/bin/env bash

set -u
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly environment_file=${CADDY_SERVING_HEALTH_ENVIRONMENT_FILE:-/etc/default/caddy-ha}
readonly curl_command=${CADDY_SERVING_HEALTH_CURL_COMMAND:-/usr/bin/curl}
readonly systemctl_command=${CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}

# Keep SIGTERM at its default disposition; Keepalived signals the full process group.

[[ -f "$environment_file" && ! -L "$environment_file" ]] || exit 1
# shellcheck disable=SC1090
source "$environment_file" || exit 1

[[ ${NODE_FQDN:-} =~ ^[A-Za-z0-9.-]+$ ]] || exit 1
[[ ${NODE_IPV4:-} =~ ^[0-9.]+$ ]] || exit 1
[[ ${NODE_IPV6:-} =~ ^[0-9A-Fa-f:]+$ ]] || exit 1

"$systemctl_command" is-active --quiet caddy.service || exit 1

check_https() {
    local health_family=$1
    local health_address=$2
    local health_status

    health_status=$("$curl_command" "--ipv$health_family" --silent --fail \
        --connect-timeout 0.5 --max-time 0.75 --max-redirs 0 \
        --output /dev/null --write-out '%{http_code}' \
        --resolve "$NODE_FQDN:443:$health_address" \
        "https://$NODE_FQDN/healthz" 2>/dev/null) || return 1
    [[ "$health_status" = 204 ]]
}

check_https 4 "$NODE_IPV4" || exit 1
check_https 6 "[$NODE_IPV6]" || exit 1

exit 0
