# Caddy authentication resilience plan

## Scope and accepted state

The governing architecture remains [caddy_plan-v1.1.md](caddy_plan-v1.1.md).
Both nodes now retain the fixed Pi-hole proxy release and independent IPv4/IPv6
web monitor. Node A and the shared URL passed real incorrect-password rejection,
immediate successful retry, dashboard access, logout, and denial after logout,
using fresh and idle sessions over both address families. The runner observed
2,224 successful availability probes, zero web-health failures, and no VIP movement.
Node A remained MASTER with four VIPs; Node B remained BACKUP with zero.
Accepted identities are in [the live-state manifest](../manifests/current-live-state.tsv).

The latest accepted operation is terminal-pending in [HISTORY.md](../HISTORY.md).
Its exact executed specification and entrypoints are retained for archive; the
authorized input graph is preserved at source commit `c091a48` and in the protected
workstation evidence snapshot. Production configuration and deployed-hash registries
now describe the accepted fix. Qualification and live evidence are protected
outside `/tmp`. Earlier failed operations remain in their pushed archive tags.

The baseline inventory defect was corrected by selecting separate eleven-file
baseline and eight-file candidate allowlists using their pinned manifest identities.
All nineteen full-outer scenarios and twenty-two decision records passed, including
changed/missing/extra baseline files, rollback, interruption, and evidence rejection.
The subsequent authorized live run passed without rollback.

Archive the accepted terminal commit before resetting consumed deployment inputs.
The retained preparation tool and qualification fixtures describe the executed
baseline-to-candidate transition; do not rerun that consumed operation against the
new accepted source. Reconcile those neutral tools with current production sources
during archive cleanup before defining another deployment.

## Repository audit

| Area | Finding and disposition |
| --- | --- |
| `scripts/check-pihole-web-health.sh` | IPv4 precedence hid dual failures; source now reports both results and separates HTTP, TLS, connection, timeout, redirect, and terminal failures. |
| `tests/serving-health-regression.sh` | Generic failure lacked family coverage; isolated mixed-family cases cover, sanitization, deduplication, enqueue retry, and recovery coverage. Validate source separately from accepted deployed identity. |
| `docs/APPLICATION_ONBOARDING.md` | Authentication ownership existed but rejection/retry acceptance was missing; require it for every authenticated web interface. |
| `templates/reverse-proxy.caddy.example` | Passive checks and 5xx policy require an application-specific review; document `0s` and the authentication gate without changing the token schema. |
| `configs/caddy/conf.d/10-pihole-admin.caddy` | Accepted source removes passive exclusion and disables local upstream reuse; both nodes passed live acceptance. |
| Release and deployment manifests | Both nodes’ accepted identities are recorded; retain the consumed operation until its terminal archive is pushed. |
| Operator and project documents | Link this plan and explain notification classifications and authentication acceptance. |

Only Pi-hole administration is an application proxy in the current production
fragment inventory. Health and default-deny fragments have no login flow.
The proposed generator must carry the authentication gate into its input and
acceptance contracts. DNS, Keepalived, and notification delivery behavior need
no change for this work.

## Implemented behavior

An incorrect password must yield the application’s normal rejection and permit
an immediate successful retry. The incident showed a closed upstream connection
followed by passive exclusion of the only backend. The connection closure’s
cause remains unproven.

The accepted candidate removes `fail_duration 30s` and adds this local upstream
transport setting, retaining active health checks:

```caddyfile
transport http {
    keepalive off
}
```

Login POSTs are never replayed. No password, Pi-hole configuration, DNS,
Keepalived configuration, or notification delivery behavior is changed.
The web monitor reports both families independently, distinguishing HTTP status,
TLS, connection, timeout, redirect, and other terminal failures. Web health
remains notification-only and does not determine VRRP eligibility.

## Accepted activation procedure

1. Verify both numeric IPv4/IPv6 HTTPS paths for Node A and the shared hostname,
   retaining SNI and certificate verification. Require HTTP 200 and the login
   form before uploads, SSH, or credential retrieval.
2. Upload the minimal pinned payload, check Node B’s accepted release and monitor,
   then check Node A’s baseline and exact retained publication. Reject incoming
   or quarantine residue, extra publication entries, service or ownership drift.
   Validate the complete eleven-file baseline separately from the eight-file
   candidate, including certificate metadata and decomposed certificates.
3. Start cursor-bounded health evidence and continuity/address observers on both
   nodes. Require Node A MASTER with four VIPs and Node B BACKUP with zero.
4. Atomically replace Node A’s monitor with a protected baseline backup. Stop
   Node A synchronization/reconciliation while staging its existing publication
   for the installed finalizer and reconciler. Reconciliation owns selection and
   Caddy reload. Resume Node A synchronization after successful activation.
5. Test Node A login, then verify ownership and test the shared URL. Recheck
   ownership afterward. Both targets exercise fresh and idle connections on
   IPv4 and IPv6: incorrect password, immediate correct password, authenticated
   dashboard, logout, and denied dashboard after logout. Each target includes
   90 seconds of health observation and concurrent opposite-family requests.
6. Accept the candidate on Node A and unchanged accepted state on Node B. Reject
   HTTP 502/503, health failure/recovery events, DNS failures, ownership changes,
   malformed evidence, excessive probe gaps, and observer residue. Preserve the
   publication and both accepted releases on success.

Node B is never reloaded, rolled back, or republished by this operation. There is
no deliberate failover. The publication is an existing accepted input, not a new
release produced during this stage.

## Failure and rollback

Before mutation, clean up only proven owned upload paths. Persist activation
intent before any service transition. A failed primary activation or login
triggers restoration of Node A’s original release and web monitor, followed by
service, identity, ownership, availability, and evidence checks. Stop primary
reconciliation before reverting selection; reload the baseline even when a
previous failure already restored its symlink. Dispose only of the exact
transaction-owned local candidate after identity verification.

Preserve Node B’s accepted release and the retained Node A publication throughout
rollback. Unknown identities, ambiguous interrupted mutations, lost acceptance
readback, or unproven restoration return 125 and retain recovery inputs. A
proven restoration returns failure, never successful deployment acceptance.

## Login secret and automation

The operator confirmed that Node A and Node B use the same web password. Both
node tests therefore use the existing reference:

```text
homelab-dev / prd_caddy / PIHOLE_NODE_B_WEB_PASSWORD
```

The reference name is retained; no secret is copied, reset, or rotated. Doppler
retrieval uses a bounded pipe, fixed provider command, successful provider exit,
and descendant cleanup. Passwords and session cookies stay in memory; no values
enter argv, environment, files, evidence, or raw diagnostics. A stored Pi-hole
password hash is not a substitute for the web password.

The standalone validator supports `--password-fd` or `--password-doppler`.
Shared-route authentication requires `--shared-owner node-a`. This is an explicit
assertion by the caller; the deployment outer runner supplies the authoritative
before/after ownership checks and continuous VIP evidence. Connectivity-only
checks retrieve no secret and issue no POST.

All new authenticated proxies must meet the rejection/retry gate in
[APPLICATION_ONBOARDING.md](APPLICATION_ONBOARDING.md), including generator
outputs. Valid Caddy syntax alone cannot satisfy functional login acceptance.

## Qualification and handoff

The current isolated fixture starts from a real published/finalized/reconciled
standby candidate, then executes the current primary outer runner and transaction.
Node A’s finalizer/reconciler run inside a private mount namespace with their
normal absolute paths. Synthetic TLS and external service/transport models remain
inside a network-disabled Podman container. Caddy and login HTTP are real fixture
processes; unavailable external systems produce effects only in response to the
commands under test.

Qualify preflight failures, normal activation, node/shared login failure, failed
reload/restoration, interrupted helper installation, lost activation reply, lost
readback, DNS failure, and malformed observation evidence. Retain the unchanged
source graph, actual command streams, observed state, and zero observer residue.
The policy rejects stale graphs and rehashed evidence that lacks the required
causal command sequence.

```bash
/bin/bash Caddy/tests/run-focused-container.sh --profiles authentication-outer
# Use the evidence directory reported by that run:
CADDY_AUTH_QUALIFICATION_EVIDENCE=/tmp/REPORTED-EVIDENCE-DIRECTORY \
  /bin/bash Caddy/tests/deployable-successor-policy.sh --authorization-ready
```

Complete targeted host tests and repository hooks, preserve qualification outside
`/tmp`, and prepare the review document containing the exact outer SHA-256,
execution command, target identities, acceptance, and rollback. Request live
authorization only after those checks pass. The accepted live identities, production sources, handoff, and terminal history
are updated. Archive the consumed operation before removing its records.
