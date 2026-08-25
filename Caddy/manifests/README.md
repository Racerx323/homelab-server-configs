# Caddy production manifests

This directory contains current production contracts. The deployment stream is
clean; no successor is registered.

| File | Purpose |
| --- | --- |
| `accepted-live-artifacts.tsv` | Canonical deployed identities |
| `production-artifacts.tsv` | Source, target, node, and deployed identity mapping |
| `reproducibility-production.yaml` | Exact package, application, lighttpd-tree, Unbound, and public SSH identities |
| `caddy-release-source.tsv` | Non-secret repository sources pinned to the accepted immutable Caddy payload |
| `config-lifecycle.tsv` | Complete classification of the Caddy configuration tree |
| `runtime-production.tsv` | Neutral current runtime boundary |
| `current-live-state.tsv` | Accepted semantic input for the next transaction |
| `deployment.yaml` | Current topology and application contract |
| `deployment-streams.tsv` | Caddy deployment-window state and terminal archive boundary |
| `dns-records.yaml` | Application DNS contract |
| `synchronization-protocol-v2.yaml` | Release transport and reconciliation |
| `durable-apprise-production.tsv` | Notification queue installation contract |
| `serving-health-production.tsv` | Current accepted serving-health artifacts |
| `deployable-successor.tsv` | Single live successor registry |
| `deployable-successor-coverage.tsv` | File-backed causal evidence contract for the outer runner and transaction |
| `serving-health-operation.yaml` | Inactive neutral operation contract; changed to a defined operation only for an authorized successor |
| `serving-health-quarantine-baseline.tsv` | Canonical empty quarantine inventory; historical trees are retained only in tagged history |
| `dependencies.yaml` | Package, command, cross-repository, external-input, and rebuild-gap contract |

Lifecycle registries classify the complete configurations, manifests, scripts,
systemd units, and templates. The main branch contains no action-numbered implementations; exact
consumed definitions are retained by the annotated tags in `Caddy/HISTORY.md`.

Keepalived, Pi-hole, and Unbound paths use the `homelab-dns` repository
identity. Caddy paths use `homelab-server-configs`.

An absent accepted-live row is not evidence that a dependency is unnecessary.
The main Unbound configuration and the non-secret rebuild identities are now
recorded from the bounded dual-node inventory described in
`Caddy/docs/REPRODUCIBILITY.md`.

Run:

```bash
Caddy/tests/accepted-live-hash-policy.sh --check
Caddy/tests/deployment-lifecycle-policy.sh --check
Caddy/tests/deployable-successor-policy.sh --check
```

Use `--authorization-ready` only after one successor is registered as
`defined`; it must fail while the stream is clean.
