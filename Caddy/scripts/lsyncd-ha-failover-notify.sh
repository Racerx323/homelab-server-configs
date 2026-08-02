#!/usr/bin/env bash
set -euo pipefail

readonly apprise_endpoint='http://10.1.3.83:8000/notify/apprise'
readonly state_dir='/run/caddy-ha'
readonly dedupe_dir='/run/caddy-ha-notify'
readonly dedupe_seconds=60

type=${1:-UNKNOWN}
name=${2:-UNKNOWN}
state=${3:-UNKNOWN}
hostname_value=$(hostname -f 2>/dev/null || hostname)

mkdir -p "$state_dir" "$dedupe_dir"
printf '%s\n' "$state" >"$state_dir/vrrp-state"

event_hash=$(
    printf '%s\0%s\0%s\0%s' "$hostname_value" "$type" "$name" "$state" |
        sha256sum |
        awk '{print $1}'
)
stamp_file="$dedupe_dir/keepalived-$event_hash"
now=$(date +%s)
if [[ -f "$stamp_file" ]]; then
    previous=$(<"$stamp_file")
    if [[ "$previous" =~ ^[0-9]+$ ]] &&
        ((now - previous < dedupe_seconds)); then
        logger -t caddy-ha-notify \
            "Suppressed duplicate Caddy HA state notification: $name $state"
        exit 0
    fi
fi
printf '%s\n' "$now" >"$stamp_file"

case "$state" in
    MASTER)
        notification_type=success
        ;;
    BACKUP)
        notification_type=info
        ;;
    FAULT)
        notification_type=failure
        ;;
    *)
        notification_type=warning
        ;;
esac

active_revision=unknown
if [[ -r /etc/caddy/current/release-manifest.json ]]; then
    active_revision=$(
        jq -r '.revision // "unknown"' \
            /etc/caddy/current/release-manifest.json 2>/dev/null || printf unknown
    )
fi

body="Host: $hostname_value
Keepalived type: $type
Group: $name
State: $state
Caddy: $(systemctl is-active caddy.service 2>/dev/null || true)
lsyncd: $(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)
Active revision: $active_revision"

payload=$(
    jq -n \
        --arg title "Caddy HA state changed to $state" \
        --arg body "$body" \
        --arg type "$notification_type" \
        '{title: $title, body: $body, type: $type, format: "text"}'
)

logger -t caddy-ha-notify \
    "Caddy HA $name ($type) changed to $state; revision $active_revision"

(
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
        logger -t caddy-ha-notify "Delivered Caddy HA state notification"
    else
        status=$?
        logger -t caddy-ha-notify \
            "Failed Caddy HA notification: curl status $status: $response"
    fi
) &

exit 0
