#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly environment_file=${PIHOLE_WEB_HEALTH_ENVIRONMENT_FILE:-/etc/default/caddy-ha}
readonly state_directory=${PIHOLE_WEB_HEALTH_STATE_DIRECTORY:-/var/lib/caddy-pihole-web-health}
readonly runtime_directory=${PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY:-/run/caddy-pihole-web-health}
readonly enqueue_command=${PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND:-/usr/local/libexec/caddy-apprise-enqueue}
readonly curl_command=${PIHOLE_WEB_HEALTH_CURL_COMMAND:-/usr/bin/curl}
readonly systemctl_command=${PIHOLE_WEB_HEALTH_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}
readonly date_command=${PIHOLE_WEB_HEALTH_DATE_COMMAND:-/usr/bin/date}
readonly sha256_command=${PIHOLE_WEB_HEALTH_SHA256_COMMAND:-/usr/bin/sha256sum}
readonly state_file=$state_directory/state

log_event() {
    printf 'pihole_web_health event=%s\n' "$1"
}

safe_directory() {
    [[ -d "$1" && ! -L "$1" ]]
}

write_state() {
    local web_health_state=$1
    local web_health_episode=$2
    local web_health_failure_enqueued=$3
    local web_health_recovery_enqueued=$4
    local web_health_temporary

    web_health_temporary=$(mktemp "$state_directory/.state.XXXXXX")
    printf 'schema=caddy-pihole-web-health/v1\nstate=%s\nepisode=%s\nfailure_enqueued=%s\nrecovery_enqueued=%s\n' \
        "$web_health_state" "$web_health_episode" "$web_health_failure_enqueued" \
        "$web_health_recovery_enqueued" >"$web_health_temporary"
    chmod 0600 "$web_health_temporary"
    mv -fT -- "$web_health_temporary" "$state_file"
}

load_state() {
    current_state=healthy
    episode_id=-
    failure_enqueued=false
    recovery_enqueued=false
    [[ -e "$state_file" ]] || return 0
    [[ -f "$state_file" && ! -L "$state_file" ]] || return 1
    [[ "$(stat -c '%a' "$state_file")" = 600 ]] || return 1
    [[ "$(wc -l <"$state_file")" -eq 5 ]] || return 1
    grep -Fxq 'schema=caddy-pihole-web-health/v1' "$state_file" || return 1
    current_state=$(sed -n 's/^state=//p' "$state_file")
    episode_id=$(sed -n 's/^episode=//p' "$state_file")
    failure_enqueued=$(sed -n 's/^failure_enqueued=//p' "$state_file")
    recovery_enqueued=$(sed -n 's/^recovery_enqueued=//p' "$state_file")
    [[ "$current_state" =~ ^(healthy|failed|recovery-pending)$ ]] || return 1
    [[ "$episode_id" = - || "$episode_id" =~ ^[a-f0-9]{32}$ ]] || return 1
    [[ "$failure_enqueued" =~ ^(true|false)$ ]] || return 1
    [[ "$recovery_enqueued" =~ ^(true|false)$ ]] || return 1
}

enqueue_transition() {
    local web_health_kind=$1
    local web_health_severity=$2
    local web_health_message=$3

    "$enqueue_command" --source pihole-web --severity "$web_health_severity" \
        --event-key "pihole-web-$web_health_kind" \
        --stable-id "$episode_id-$web_health_kind" \
        --title "Pi-hole web $web_health_kind" --body "$web_health_message"
}

probe_family() {
    local web_health_family=$1
    local web_health_address=$2
    local web_health_output=$3

    "$curl_command" "--ipv$web_health_family" --silent --show-error --fail \
        --max-time 2 --max-redirs 3 --location --output /dev/null \
        --write-out '%{http_code} %{url_effective}\n' \
        --resolve "$NODE_FQDN:443:$web_health_address" \
        "https://$NODE_FQDN/admin/login.php" >"$web_health_output" 2>&1
}

safe_directory "$state_directory"
safe_directory "$runtime_directory"
[[ -f "$environment_file" && ! -L "$environment_file" ]]
# shellcheck disable=SC1090
source "$environment_file"
: "${NODE_FQDN:?missing NODE_FQDN}"
: "${NODE_IPV4:?missing NODE_IPV4}"
: "${NODE_IPV6:?missing NODE_IPV6}"
readonly NODE_FQDN NODE_IPV4 NODE_IPV6
load_state

if ! "$systemctl_command" is-active --quiet caddy.service; then
    log_event caddy-unavailable-deferred
    exit 0
fi

healthy=true
failure_class=none
if ! "$systemctl_command" is-active --quiet lighttpd.service; then
    healthy=false
    failure_class=service
else
    probe_family 4 "$NODE_IPV4" "$runtime_directory/ipv4" &
    ipv4_pid=$!
    probe_family 6 "[$NODE_IPV6]" "$runtime_directory/ipv6" &
    ipv6_pid=$!
    ipv4_ok=true
    ipv6_ok=true
    wait "$ipv4_pid" || ipv4_ok=false
    wait "$ipv6_pid" || ipv6_ok=false
    if [[ "$ipv4_ok" != true ]]; then
        healthy=false
        failure_class=ipv4-path
    elif [[ "$ipv6_ok" != true ]]; then
        healthy=false
        failure_class=ipv6-path
    elif [[ "$(<"$runtime_directory/ipv4")" != "200 https://$NODE_FQDN/admin/login.php" ]]; then
        healthy=false
        failure_class=ipv4-terminal
    elif [[ "$(<"$runtime_directory/ipv6")" != "200 https://$NODE_FQDN/admin/login.php" ]]; then
        healthy=false
        failure_class=ipv6-terminal
    fi
fi

if [[ "$healthy" != true ]]; then
    if [[ "$current_state" = healthy ]]; then
        episode_id=$(printf '%s\0%s\0%s\n' "$NODE_FQDN" "$failure_class" \
            "$($date_command -u +%s%N)" | "$sha256_command" | cut -c1-32)
        failure_enqueued=false
        recovery_enqueued=false
        write_state failed "$episode_id" false false
    fi
    if [[ "$failure_enqueued" != true ]]; then
        if enqueue_transition failure failure \
            "Pi-hole web health failed on $NODE_FQDN: $failure_class"; then
            failure_enqueued=true
            write_state failed "$episode_id" true false
        else
            log_event enqueue-failure-pending
            exit 0
        fi
    fi
    log_event failure-retained
    exit 0
fi

if [[ "$current_state" != healthy ]]; then
    if [[ "$failure_enqueued" != true ]]; then
        enqueue_transition failure failure \
            "Pi-hole web health failed on $NODE_FQDN: recovered-before-enqueue" || {
            log_event enqueue-failure-pending
            exit 0
        }
        failure_enqueued=true
        write_state recovery-pending "$episode_id" true false
    fi
    if [[ "$recovery_enqueued" != true ]]; then
        write_state recovery-pending "$episode_id" true false
        enqueue_transition recovery info "Pi-hole web health recovered on $NODE_FQDN" || {
            log_event enqueue-recovery-pending
            exit 0
        }
    fi
    write_state healthy - false false
    log_event recovery-enqueued
else
    write_state healthy - false false
    log_event healthy
fi
