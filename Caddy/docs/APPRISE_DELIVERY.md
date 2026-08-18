# Durable Apprise delivery

The HA nodes use one Caddy-owned, persistent local queue for Caddy
synchronization failures and Keepalived state notifications. Producers enqueue
bounded records and return without contacting Apprise. Notification delivery
never participates in VRRP, Caddy, lsyncd, reconciliation, or health decisions.

## Alert content contract

Production producers use one bounded text layout. The enqueue helper adds the
Apprise severity icon and node identity, then validates the complete title and
body before writing the queue record.

| Field | Contract |
| --- | --- |
| Severity | `🚨` failure, `⚠️` warning, `ℹ️` information, or `✅` success/recovery |
| Application | DNS, Proxy, Replication, or Notification Delivery |
| Node | Short hostname and FQDN obtained by the enqueue helper |
| Component and check | Exact service, worker, listener, endpoint, or ownership check |
| Event and state | Failure, transition, failover, recovery, quarantine, retry, or dead-letter, plus the bounded state transition |
| Impact | Serving, ownership, replication, or delivery effect |
| Failure class | Bounded classification such as service inactive, timeout, answer mismatch, TLS failure, HTTP status, listener mismatch, manifest rejection, or ownership mismatch |
| Network and HA context | Relevant address family, endpoint, port, VRRP state, VIP effect, and peer role |
| Status and timing | Bounded command or protocol status, first observation, duration, attempt, or next retry when available |
| Correlation | Stable episode or event identity |
| Evidence and first check | Journald unit/tag or runbook pointer and one safe starting command |

Keepalived reads bounded runtime snapshots written by the DNS and Caddy serving
checks. A `FAULT` notification can name Pi-hole FTL, Unbound, or Caddy and the
failed check without rerunning a probe from the notifier. Pi-hole/lighttpd
monitoring identifies Proxy backend failures and states that VRRP ownership did
not change. Replication workers identify lsyncd, reconciliation,
synchronization health, or certificate-expiry failures.

The notification-delivery worker records retry, dead-letter, and queue health
events in journald. It does not enqueue an alert about its own delivery failure
because that would recurse through the failed channel.

Alerts exclude secrets, environment dumps, complete HTTP responses, unbounded
journal text, and raw command output. Journald and retained transaction
evidence hold the detailed diagnostic data.

## Ownership and paths

| Item | Owner | Path |
| --- | --- | --- |
| Queue schema and enqueue helper | Caddy | `/usr/local/libexec/caddy-apprise-enqueue` |
| Delivery worker | Caddy | `/usr/local/libexec/caddy-apprise-delivery-worker` |
| Persistent queue | Caddy systemd subsystem, runtime user `pi` | `/var/lib/caddy-apprise-queue` |
| Runtime lock and bounded response capture | Caddy systemd subsystem | `/run/caddy-apprise` |
| Keepalived transition producer | `homelab-dns` | `/usr/local/bin/keepalived-notify.sh` |
| Endpoint | Operator infrastructure | `http://10.1.3.83:8000/notify/apprise` |

The endpoint remains an IP literal so delivery does not depend on DNS. Queue
directories are `pi:pi:0700`; records are regular, non-symlink files with mode
`0600`. Pending, inflight, delivered-receipt, and dead-letter state survives a
reboot beneath `/var/lib`.

## Delivery contract

Records use `caddy-apprise-queue/v1` and contain a stable event ID, source,
host, severity, UTC creation time, epoch creation time, retry state, and the
bounded Apprise payload. Producers reject malformed UTF-8, control characters,
oversized values, secret-like content, unsafe keys, unsafe paths, and schema
drift before an atomic same-filesystem link publishes a pending record.

The worker holds an exclusive runtime lock, processes the oldest eligible
record first, and is activated by both a path and persistent timer. Failures
use bounded exponential backoff with deterministic jitter. The eighth failed
attempt moves the complete record to the protected dead-letter directory.
Every transition is summarized in journald without response bodies or secrets.

Delivery is at least once. A record interrupted before a request remains
pending. A record interrupted during a request is requeued after reboot. A
durable receipt prevents another request after local acknowledgement. A crash
after Apprise accepted the request but before the receipt was committed is an
unavoidable distributed-systems ambiguity: the worker retries with the same
`Idempotency-Key`, but duplicate suppression at that boundary depends on the
endpoint honoring that key.

## Operations

```bash
systemctl status caddy-apprise-worker.path caddy-apprise-worker.timer
systemctl start caddy-apprise-worker.service
journalctl -t caddy-apprise-queue -t caddy-apprise-worker --since today
find /var/lib/caddy-apprise-queue -maxdepth 2 -type f -printf '%M %u:%g %p\n'
```

Do not edit queued JSON in place. Resolve the delivery cause, then start the
worker. Dead-letter replay is an explicit operator disposition: validate the
record against the current schema, reset retry state through a separately
reviewed tool or transaction, and atomically return it to `pending`. Never
delete a failed record merely to clear an alert.

Uninstallation removes programs and units but preserves
`/var/lib/caddy-apprise-queue` by default so undelivered evidence is not lost.
Purging it is a separate destructive operator decision.
