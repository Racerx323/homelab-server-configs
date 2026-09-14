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

The accepted operation is archived in the pushed tag indexed by
[HISTORY.md](../HISTORY.md). The deployment stream is clean and the neutral
operation specification is inactive. Production configuration and deployed-hash
registries describe the accepted fix. Qualification and live evidence remain
protected outside `/tmp`; the archive preserves the executed input graph.

The baseline inventory defect was corrected by selecting separate eleven-file
baseline and eight-file candidate allowlists using their pinned manifest identities.
All nineteen full-outer scenarios and twenty-two decision records passed, including
changed/missing/extra baseline files, rollback, interruption, and evidence rejection.
The subsequent authorized live run passed without rollback.

Only accepted-production validation remains on the current branch. The completed
migration's preparation, deployment modes, qualification policy, and fixtures were
removed after archival. Tests use current production source and a causal backend;
they do not recreate the old proxy configuration. The standalone login validator
and secret-input tests remain. A future deployment requires a new scoped definition
and qualification; the archived operation is not reusable authority.

## Repository audit

| Area | Finding and disposition |
| --- | --- |
| `scripts/check-pihole-web-health.sh` | IPv4 precedence hid dual failures; source now reports both results and separates HTTP, TLS, connection, timeout, redirect, and terminal failures. |
| `tests/serving-health-regression.sh` | Generic failure lacked family coverage; isolated mixed-family cases cover, sanitization, deduplication, enqueue retry, and recovery coverage. Validate source separately from accepted deployed identity. |
| `docs/APPLICATION_ONBOARDING.md` | Authentication ownership existed but rejection/retry acceptance was missing; require it for every authenticated web interface. |
| `templates/reverse-proxy.caddy.example` | Passive checks and 5xx policy require an application-specific review; document `0s` and the authentication gate without changing the token schema. |
| `configs/caddy/conf.d/10-pihole-admin.caddy` | Accepted source removes passive exclusion and disables local upstream reuse; both nodes passed live acceptance. |
| Release and deployment manifests | Both nodes’ accepted identities are recorded; consumed inputs are archived and the stream is clean. |
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

## Deployment archive

The accepted activation procedure, mutation boundaries, and rollback evidence are
preserved in the pushed tags indexed by [HISTORY.md](../HISTORY.md). There is no
pending activation or rollback operation. Both nodes retain the accepted fix.

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

## Current validation and handoff

Run accepted-production authentication and secret-boundary tests with:

```bash
/bin/bash Caddy/tests/run-focused-container.sh --profiles authentication-resilience
/bin/bash Caddy/tests/deployable-successor-policy.sh --check
```

Tests validate current Caddy source, authentication rejection/retry, single-request
transport failure recovery, active-health failure/recovery, and secret handling.
The production configuration, accepted identities, handoff, and history are current.
The deployment stream is clean; no further live changes are part of this work.
