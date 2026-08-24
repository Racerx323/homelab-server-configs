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
| `templates/` | Two production templates and one approved future example |
| `tests/` | Neutral current-production validation |
| `docs/` | Governing plan, serving-health plan, and durable notification runbook |

The `homelab-dns` repository owns Keepalived, Pi-hole, and Unbound sources.
The `homelab-network` repository owns network-controller configuration.

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
Caddy/tests/run-focused.sh --profile current-synchronization
Caddy/tests/run-focused.sh --profile current-serving-health
Caddy/tests/deployable-successor-policy.sh --authorization-ready
```

Live changes require a separately authorized outer-runner SHA-256.
