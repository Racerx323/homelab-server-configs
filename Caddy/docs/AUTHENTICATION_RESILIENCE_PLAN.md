# Caddy authentication resilience plan

## Scope and accepted state

The governing architecture remains [caddy_plan-v1.1.md](caddy_plan-v1.1.md).
Node B has passed real Pi-hole login acceptance and retains the fixed release
and independent IPv4/IPv6 web monitor. Node A still serves the original release
and retains the same candidate publication. Accepted identities are in
[the live-state manifest](../manifests/current-live-state.tsv).

The completed Node B operation and its evidence manifest are archived in the
pushed tag indexed by [HISTORY.md](../HISTORY.md). Its raw acceptance evidence
and qualification copy are protected outside workstation `/tmp`. The earlier
failed attempt’s `/tmp` evidence was purged during the reported WSL restart;
its archive contains hashes, not reconstructed raw evidence.

The authorized Node A run stopped during preflight before monitor installation,
release activation, service transitions, or credential retrieval. Both workstation
connectivity checks and Node B preflight passed. Both temporary upload cleanups
returned success. Node A remains on its original release and monitor.

Read-only inspection found a deployment predicate defect: it checks the accepted
baseline against the candidate’s eight-file inventory. The baseline has eleven
manifest entries, including `tls/leaf.pem`, `tls/intermediates.pem`, and
`tls/certificate-manifest.json`. Its pinned manifest and all eleven file digests
match. The retained candidate matches its eight-file inventory. This is a
qualification gap, not observed release drift: the sixteen passing scenarios
used a baseline fixture that omitted those three files.

The consumed operation is archived in its pushed terminal tag. Its exact source
graph, qualification, and live evidence remain protected outside `/tmp`. The
replacement definition uses separate inventories selected by the pinned manifest
identity: eleven baseline files and eight candidate files. The fixture now
includes the full baseline; additional preflight cases alter certificate metadata,
remove an intermediate file, and add an unexpected file after identity pinning.
All nineteen full-outer scenarios passed, including activation, both login
targets, baseline restoration, and malformed evidence rejection, with zero
observer residue. Node A and shared-URL
functional login acceptance still require the qualified replacement's exact live
authorization.

## Repository audit

| Area | Finding and disposition |
| --- | --- |
| `scripts/check-pihole-web-health.sh` | IPv4 precedence hid dual failures; source now reports both results and separates HTTP, TLS, connection, timeout, redirect, and terminal failures. |
| `tests/serving-health-regression.sh` | Generic failure lacked family coverage; isolated mixed-family cases cover, sanitization, deduplication, enqueue retry, and recovery coverage. Validate source separately from accepted deployed identity. |
| `docs/APPLICATION_ONBOARDING.md` | Authentication ownership existed but rejection/retry acceptance was missing; require it for every authenticated web interface. |
| `templates/reverse-proxy.caddy.example` | Passive checks and 5xx policy require an application-specific review; document `0s` and the authentication gate without changing the token schema. |
| `configs/caddy/conf.d/10-pihole-admin.caddy` | Sole local backend has `fail_duration 30s` and default connection reuse; accepted Node A source remains intact while Node B serves the fixed release. |
| Release and deployment manifests | Retain accepted live identities; archive the consumed operation and prepare Node A activation with workstation connectivity and standby identity gates. |
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

## Primary activation sequence

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
authorization only after those checks pass. After live acceptance, update both
nodes’ accepted identities, production source classifications, handoff, and
terminal history; archive the consumed operation before removing its records.
