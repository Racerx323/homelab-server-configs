#!/usr/bin/env bash
set -euo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH
readonly enqueue=/usr/local/libexec/caddy-apprise-enqueue

event=${1:-lsyncd synchronization failure}
hostname_value=$(hostname -f 2>/dev/null || hostname)
body="Host: $hostname_value; Event: $event; lsyncd: $(systemctl is-active caddy-lsyncd.service 2>/dev/null || true); Caddy: $(systemctl is-active caddy.service 2>/dev/null || true)"

if "$enqueue" --source caddy-sync --severity failure \
    --event-key "lsyncd:$event" \
    --title "Caddy HA lsyncd failure on $hostname_value" --body "$body"; then
    logger -t caddy-ha-notify -- "Queued lsyncd failure notification"
else
    status=$?
    logger -t caddy-ha-notify -- "Unable to queue lsyncd failure notification: status $status"
fi

# Notification failure never changes the source worker's failure decision.
exit 0
