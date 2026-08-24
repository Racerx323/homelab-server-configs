# Highly available Caddy

This directory contains the current production surface for the dual-node Caddy
service on the Pi-hole resolver pair.

Node A is the preferred owner. Node B is standby. Keepalived moves both DNS VIPs
and both Caddy VIPs as one dual-stack service group.

Current design and recovery rules live in
[`docs/caddy_plan-v1.1.md`](docs/caddy_plan-v1.1.md). The complete executed
action archive lives at the Git tag recorded in [`HISTORY.md`](HISTORY.md).

## Endpoints

| Name | Purpose |
| --- | --- |
| `proxy.local.theama.co` | Shared reverse proxy |
| `pihole-admin.local.theama.co` | Pi-hole UI on the current coupled owner |
| `pihole0.local.theama.co` | Node A management |
| `pihole00.local.theama.co` | Node B management |

## Current components

| Path | Contents |
| --- | --- |
| `configs/` | Deployable Caddy, lighttpd, lsyncd, sysctl, and tmpfiles state |
| `manifests/` | Current contracts, accepted identities, and successor registries |
| `scripts/` | Current runtime and repository tools |
| `systemd/` | Current installable units and drop-ins |
| `templates/` | Two production templates and one supported non-deployable example |
| `tests/` | Neutral current-production validation |
| `docs/` | Governing plan, operator runbooks, architecture, reproducibility, and durable notification contract |

The `homelab-dns` repository owns Keepalived, Pi-hole, and Unbound sources.
The `homelab-network` repository owns network-controller configuration.

## Operator documentation

| Document | Use |
| --- | --- |
| [`docs/QUICK_START.md`](docs/QUICK_START.md) | Routine inspection and first response |
| [`docs/INSTALLATION.md`](docs/INSTALLATION.md) | Current installation boundary and automation gaps |
| [`docs/OPERATIONS.md`](docs/OPERATIONS.md) | Publication, maintenance, synchronization, and rollback |
| [`docs/UNINSTALLATION.md`](docs/UNINSTALLATION.md) | Standby-first removal and preservation rules |
| [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) | Component-specific diagnosis and evidence |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Accepted as-built component and data-flow model |
| [`docs/APPLICATION_ONBOARDING.md`](docs/APPLICATION_ONBOARDING.md) | Backend inventory, template, validation, and release gate |
| [`docs/PROTOCOL_V2_RELEASE_LIFECYCLE.md`](docs/PROTOCOL_V2_RELEASE_LIFECYCLE.md) | Immutable release construction, transfer, activation, and bookkeeping |
| [`docs/APPRISE_DELIVERY.md`](docs/APPRISE_DELIVERY.md) | Notification and persistent queue authority |
| [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md) | Rebuild inputs and external recovery authority |
| [`docs/caddy_plan-v1.1.md`](docs/caddy_plan-v1.1.md) | Architecture decisions, lifecycle, and authorization authority |

The exact source-control boundary, required external inputs, and known gaps for
a bare-metal rebuild are documented in
[`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md). The accepted Caddy HA
layer's exact non-secret production identities and known inputs are recorded;
the repository does not provide a complete installation or recovery workflow.
Private keys, TLS material, credentials, and their external recovery systems
remain deliberately outside this repository.

## Synchronization

Node A publishes normal protocol-v2 releases to Node B. Node B can publish with
`--emergency` only while it owns both families and all four shared VIPs. The
receiver, finalizer, and reconciler reject malformed, partial, ambiguous, or
unauthorized candidates.

## Services

Both nodes run Caddy, managed lsyncd, reconciliation, certificate checks,
synchronization health checks, durable Apprise delivery, and accepted Caddy
serving-health tracking through Keepalived. Pi-hole/lighttpd backend health is
an accepted notification-only timer and cannot change VRRP eligibility.

## Validation

```bash
Caddy/tests/run-focused.sh --list
Caddy/tests/run-focused.sh --profile current-synchronization --phase host --container never
Caddy/tests/run-focused.sh --profile current-serving-health --phase host --container never
Caddy/tests/deployable-successor-policy.sh --check
```

`--authorization-ready` is valid only while a successor is defined. Live
changes require a separately authorized outer-runner SHA-256.
