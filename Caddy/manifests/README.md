# Caddy manifest catalog

This directory contains two deliberately different artifact classes:

- current production contracts and typed accepted-live inventories;
- immutable action definitions retained for execution and authorization
  provenance.

An action definition's embedded `status`, `mode`, or `execution_status` records
what was true when that exact file was defined. It is not rewritten after live
execution. The governing deployment plan records execution evidence, while
[`manifest-lifecycle.tsv`](manifest-lifecycle.tsv) gives every directory entry
its current repository disposition without changing historical bytes.

## Current production sources

| File | Contract |
| --- | --- |
| `deployment.yaml` | Current application endpoints and coupled DNS/Caddy ownership model |
| `dns-records.yaml` | Accepted application DNS record contract |
| `synchronization-protocol-v2.yaml` | Current release publication, transport, finalization, and reconciliation contract |
| `dependencies.yaml` | Runtime and validation dependency inventory |
| `accepted-live-artifacts.tsv` | Canonical deployed identities by node and accepting action |
| `production-artifacts.tsv` | Typed mapping from repository source to installed artifact and deployed identity |
| `deployable-live-hash-consumers.tsv` | Still-deployable shell consumers of accepted-live identities |
| `template-lifecycle.tsv` | Canonical lifecycle of files beneath `Caddy/templates/` |
| `script-lifecycle.tsv` | Complete script classification and exact node-installable executable mapping |
| `systemd-lifecycle.tsv` | Complete systemd classification and exact node-installable unit mapping |
| `manifest-lifecycle.tsv` | Complete lifecycle classification for this directory |

The production inventory uses repository-qualified paths. Every installable
script and systemd artifact has exactly one Node A row and one Node B row.
`source_sha256` is the current repository input identity. `deployed_sha256` is
the last independently accepted installed identity and may differ after a
repository-only correction or when a source is rendered, as with the Unbound
local-zone file and the node-specific Caddy environment. Such a difference is
intentional pending a separately authorized deployment; it must never be
silently represented as accepted live state. A dash denotes a runtime-generated
source that has no single repository file.

## Lifecycle values

| Lifecycle | Meaning |
| --- | --- |
| `production-current` | Current production contract, inventory, or accepted identity |
| `accepted-executed-definition` | Immutable action definition whose execution was accepted |
| `failed-consumed` | Immutable executed action that failed closed and was consumed |
| `superseded` | Unexecuted or older definition replaced by a successor or current contract |
| `rejected` | Architecture or implementation explicitly rejected for production |
| `workstation-only` | Workstation or WSL validation artifact, never a node deployment input |
| `deferred` | Retained work intentionally outside the current production boundary |

`deployable=yes` is permitted only for `production-current` entries. Historical
action definitions remain non-deployable even when their execution was
accepted. `accepted-executed-definition` is reserved for an immutable action
definition whose accepted execution remains a direct authority for a current
production identity or terminal acceptance; older accepted evidence may be
classified `superseded` once a successor owns that boundary.

## Repository boundaries

Keepalived, Pi-hole, and Unbound source paths use `repository=homelab-dns` plus
a path relative to that repository. Caddy sources use
`repository=homelab-server-configs`. Policies must not interpret a sibling
repository path as relative to this directory.

Run the governing structural check from the server repository root:

```bash
Caddy/tests/accepted-live-hash-policy.sh --check
Caddy/tests/deployment-lifecycle-policy.sh --check
```

The check rejects unclassified manifest files, incomplete or mismatched
accepted-live inventory, stale deployable consumers, unsafe paths, duplicate
keys, and mismatched current-repository source hashes.

The deployment lifecycle policy separately requires every file beneath
`Caddy/scripts/` and `Caddy/systemd/` to have exactly one disposition. It also
cross-checks current systemd executable dependencies, the protocol-v2 forced
receiver, accepted production source paths, and the reusable installer. This
keeps expected installation inputs distinct from claims about already accepted
live hashes.
