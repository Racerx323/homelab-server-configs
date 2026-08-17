# Caddy production manifests

This directory contains current production contracts and the one approved
future transaction.

| File | Purpose |
| --- | --- |
| `accepted-live-artifacts.tsv` | Canonical deployed identities |
| `production-artifacts.tsv` | Source, target, node, and deployed identity mapping |
| `runtime-production.tsv` | Neutral current runtime boundary |
| `current-live-state.tsv` | Accepted semantic input for the next transaction |
| `deployment.yaml` | Current topology and application contract |
| `dns-records.yaml` | Application DNS contract |
| `synchronization-protocol-v2.yaml` | Release transport and reconciliation |
| `durable-apprise-production.tsv` | Notification queue installation contract |
| `serving-health-production.tsv` | Current serving-health candidate artifacts |
| `deployable-successor.tsv` | Single live successor registry |
| `deployable-successor-coverage.tsv` | File-backed causal evidence contract for the outer runner and transaction |

Lifecycle registries classify the complete manifests, scripts, systemd units,
and templates. The main branch contains no executed action definitions; exact
consumed definitions are retained by the annotated tags in `Caddy/HISTORY.md`.

Keepalived, Pi-hole, and Unbound paths use the `homelab-dns` repository
identity. Caddy paths use `homelab-server-configs`.

Run:

```bash
Caddy/tests/accepted-live-hash-policy.sh --check
Caddy/tests/deployment-lifecycle-policy.sh --check
Caddy/tests/deployable-successor-policy.sh --authorization-ready
```
