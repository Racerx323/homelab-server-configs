#!/usr/bin/env bash
set -euo pipefail

readonly apprise_endpoint='http://10.1.3.83:8000/notify/apprise'
readonly state_dir='/run/caddy-ha-notify'
readonly dedupe_seconds=300

event=${1:-lsyncd synchronization failure}
hostname_value=$(hostname -f 2>/dev/null || hostname)
mkdir -p "$state_dir"

event_hash=$(printf '%s\0%s' "$hostname_value" "$event" | sha256sum | awk '{print $1}')
stamp_file="$state_dir/lsyncd-failure-$event_hash"
now=$(date +%s)

if [[ -f "$stamp_file" ]]; then
    previous=$(<"$stamp_file")
    if [[ "$previous" =~ ^[0-9]+$ ]] && ((now - previous < dedupe_seconds)); then
        logger -t caddy-ha-notify "Suppressed duplicate lsyncd failure: $event"
        exit 0
    fi
fi
printf '%s\n' "$now" >"$stamp_file"

body="Host: $hostname_value
Event: $event
lsyncd: $(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)
Caddy: $(systemctl is-active caddy.service 2>/dev/null || true)"

payload=$(
    jq -n \
        --arg title "Caddy HA lsyncd failure on $hostname_value" \
        --arg body "$body" \
        '{title: $title, body: $body, type: "failure", format: "text"}'
)

if response=$(
    curl \
        --silent \
        --show-error \
        --fail-with-body \
        --connect-timeout 2 \
        --max-time 5 \
        --header 'Content-Type: application/json' \
        --data "$payload" \
        "$apprise_endpoint" 2>&1
); then
    logger -t caddy-ha-notify "Delivered lsyncd failure notification"
else
    status=$?
    logger -t caddy-ha-notify \
        "Failed lsyncd notification: curl status $status: $response"
    exit "$status"
fi
