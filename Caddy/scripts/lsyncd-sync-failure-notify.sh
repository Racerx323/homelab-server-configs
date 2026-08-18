#!/usr/bin/env bash
set -euo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH
readonly enqueue=${CADDY_SYNC_FAILURE_ENQUEUE_COMMAND:-/usr/local/libexec/caddy-apprise-enqueue}
readonly systemctl_command=${CADDY_SYNC_FAILURE_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}
readonly logger_command=${CADDY_SYNC_FAILURE_LOGGER_COMMAND:-/usr/bin/logger}
readonly date_command=${CADDY_SYNC_FAILURE_DATE_COMMAND:-/usr/bin/date}

event=${1:-lsyncd synchronization failure}
unit_name=$(sed -n 's/^systemd unit failed: //p' <<<"$event")
[[ "$unit_name" =~ ^[A-Za-z0-9@_.-]{1,128}\.service$ ]] || unit_name=unknown.service
application=Replication
component=replication-worker
check_name=systemd-unit
impact='replication health unknown; serving traffic unaffected'
first_check="systemctl status $unit_name"
case "$unit_name" in
    caddy-lsyncd.service)
        component=lsyncd
        impact='release replication stopped; serving traffic unaffected'
        ;;
    caddy-sync-reconcile.service)
        component=reconciler
        impact='received releases cannot activate; serving traffic unaffected'
        ;;
    caddy-sync-health.service)
        component=replication-health
        impact='replication health validation failed; serving traffic unaffected'
        ;;
    caddy-cert-expiry.service)
        application=Proxy
        component='Caddy certificate'
        check_name=certificate-expiry
        impact='certificate-expiry validation failed; current proxy service unchanged'
        ;;
esac
unit_result=$("$systemctl_command" show "$unit_name" --property=Result --value 2>/dev/null || printf unknown)
[[ "$unit_result" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || unit_result=unknown
lsyncd_state=$("$systemctl_command" is-active caddy-lsyncd.service 2>/dev/null || printf unknown)
caddy_state=$("$systemctl_command" is-active caddy.service 2>/dev/null || printf unknown)
[[ "$lsyncd_state" =~ ^[a-z-]{1,32}$ ]] || lsyncd_state=unknown
[[ "$caddy_state" =~ ^[a-z-]{1,32}$ ]] || caddy_state=unknown
observed_at=$("$date_command" -u +%Y-%m-%dT%H:%M:%SZ)
correlation_value="${unit_name%.service}-$("$date_command" -u +%Y%m%dT%H%M)"

if "$enqueue" --source caddy-sync --severity failure \
    --event-key "lsyncd:$event" \
    --application "$application" \
    --component "$component" \
    --check "$check_name" \
    --event failure \
    --state 'active -> failed' \
    --impact "$impact" \
    --failure-class systemd-unit-failed \
    --network-context 'not applicable' \
    --ha-context 'VIP movement: none; VRRP dependency: no' \
    --status "unit=$unit_name result=$unit_result lsyncd=$lsyncd_state caddy=$caddy_state" \
    --timing "first observed: $observed_at" \
    --correlation "$correlation_value" \
    --evidence "journalctl -u $unit_name" \
    --first-check "$first_check"; then
    "$logger_command" -t caddy-ha-notify -- "Queued lsyncd failure notification"
else
    status=$?
    "$logger_command" -t caddy-ha-notify -- "Unable to queue lsyncd failure notification: status $status"
fi

# Notification failure never changes the source worker's failure decision.
exit 0
