# Caddy deployment history

The current branch contains accepted production state and neutral reusable
tools. Annotated Git tags preserve consumed operation definitions, hashes, and
terminal provenance. Inspect a tag when you need the full record.

## Action 35 terminal index

| Action | Terminal result | Annotated tag |
| --- | --- | --- |
| 35 | failed-consumed | `caddy-action35-terminal-2026-08-16` |
| 35a | failed-consumed | `caddy-action35a-terminal-2026-08-16` |
| 35b | failed-consumed | `caddy-action35b-terminal-2026-08-16` |
| 35c | failed-consumed | `caddy-action35c-terminal-2026-08-16` |
| 35d | failed-consumed | `caddy-action35d-terminal-2026-08-16` |
| 35e | failed-consumed | `caddy-action35e-terminal-2026-08-16` |
| 35f | failed-consumed | `caddy-action35f-terminal-2026-08-17` |
| 35g | failed-consumed | `caddy-action35g-terminal-2026-08-17` |
| 35h | failed-consumed | `caddy-action35h-terminal-2026-08-17` |
| 35i | failed-consumed | `caddy-action35i-terminal-2026-08-17` |
| 35j | failed-consumed | `caddy-action35j-terminal-2026-08-17` |
| 35k | failed-consumed | `caddy-action35k-terminal-2026-08-17` |
| 35l | failed-consumed | `caddy-action35l-terminal-2026-08-17` |
| 35m | failed-consumed | `caddy-action35m-terminal-2026-08-17` |
| 35n | failed-consumed | `caddy-action35n-terminal-2026-08-17` |
| 35o | failed-consumed | `caddy-action35o-terminal-2026-08-17` |
| 35p | failed-consumed | `caddy-action35p-terminal-2026-08-17` |
| 35q | failed-consumed | `caddy-action35q-terminal-2026-08-17` |
| 35r | failed-consumed | `caddy-action35r-terminal-2026-08-17` |
| 35s | failed-consumed | `caddy-action35s-terminal-2026-08-17` |
| 35t | failed-consumed | `caddy-action35t-terminal-2026-08-17` |
| 35u | accepted read-only capture | `caddy-action35u-terminal-2026-08-17` |
| 35v | failed-consumed | `caddy-action35v-terminal-2026-08-17` |
| 35w | failed-consumed | `caddy-action35w-terminal-2026-08-18` |
| 35x | failed-consumed | `caddy-action35x-terminal-2026-08-18` |
| 35y | failed-consumed | `caddy-action35y-terminal-2026-08-18` |
| 35z | failed-consumed | `caddy-action35z-terminal-2026-08-18` |
| 35aa | failed-consumed | `caddy-action35aa-terminal-2026-08-18` |
| 35ab | failed-consumed | `caddy-action35ab-terminal-2026-08-18` |
| 35ac | failed-consumed | `caddy-action35ac-terminal-2026-08-18` |
| 35ad | failed-consumed | `caddy-action35ad-terminal-2026-08-18` |
| 35ae | failed-consumed | `caddy-action35ae-terminal-2026-08-18` |
| 35af | failed-consumed | `caddy-action35af-terminal-2026-08-18` |
| 35ag | failed-consumed | `caddy-action35ag-terminal-2026-08-18` |
| 35ah | accepted installation | `caddy-action35ah-terminal-2026-08-18` |
| 35ai | failed-consumed | `caddy-action35ai-terminal-2026-08-18` |
| 35aj | failed-consumed | `caddy-action35aj-terminal-2026-08-18` |
| 35ak | accepted timer repair | `caddy-action35ak-terminal-2026-08-18` |
| 35al | accepted notification standardization | `caddy-action35al-terminal-2026-08-23` |
| 35am | accepted attribution closure | `caddy-action35am-terminal-2026-08-23` |
| 35an | failed-consumed | `caddy-action35an-terminal-2026-08-23` |
| 35ao | failed-consumed | `caddy-action35ao-terminal-2026-08-23` |
| 35ap | manual-intervention, recovered | `caddy-action35ap-terminal-2026-08-24` |
| 35aq | failed-consumed | `caddy-action35aq-terminal-2026-08-24` |
| 35ar | failed-consumed | `caddy-action35ar-terminal-2026-08-24` |
| 35as | accepted controlled exercise and closure | `caddy-action35as-terminal-2026-08-24` |

## Accepted production boundary

Action 35ah installed the accepted coupled serving-health architecture and the
same immutable Caddy release on both nodes. Actions 35ak, 35al, and 35am closed
the Pi-hole web timer and notification contracts. Action 35as accepted the
controlled failure exercise and closed Action 35.

The accepted Caddy payload manifest SHA-256 is
`2253a491e048c9d670865e3d39efa3c9e9acd92a31ec33219f97ba91428b0133`.
Current inventories and `current-live-state.tsv` describe the production
boundary. Historical quarantine trees, operation specifications, regressions,
and evidence paths remain available through their annotated tags rather than
the working tree.

## Pre-cleanup archive

The annotated pre-cleanup tag recorded by the earlier repository consolidation
preserves the full historical tree that preceded the clean-as-you-go lifecycle.
The governing rule in `AGENTS.md` requires a terminal tag before current-branch
cleanup.

## Node B authentication acceptance, 2026-09-14

- Operation: `20260914-pihole-authentication-node-b`
- Status: archived
- Result: failed-consumed; baseline restoration accepted on both nodes
- Tag: `caddy-authentication-node-b-terminal-2026-09-14`
- Archive: annotated tag pushed for terminal commit `cc2b0db`
- Authorized outer SHA-256: `8a62176be84b6693eef5aec0705ea96a2334b6ffac96e34039b6c74c1b6c25da`

Normal Node A publication and Node B reconciliation completed. The real IPv4
login rejected an incorrect password with HTTP 200 and accepted the configured
password with HTTP 302. The concurrent IPv6 connection failed before HTTP: the
workstation has no IPv6 route to Node B (errno 101, Network is unreachable).
Full login acceptance therefore failed. The runner restored Node B's baseline
release and monitor, withdrew Node A's publication, and proved both nodes'
restoration. Across 320 node-local probes, both families remained healthy;
Node A remained Master with four VIPs and Node B Backup with zero VIPs.
The early failure shortened observation below the full acceptance minimum.

The terminal tag retains the exact executed specification and sanitized
`manifests/serving-health-terminal-result.yaml`, including source and external
evidence hashes. The original workstation `/tmp` evidence and source snapshot
were no longer available at archival, likely following the operator-reported WSL
Ubuntu stop/start. The tag does not contain raw evidence. Consumed data is removed
from the current branch while one replacement operation is registered.
No candidate is accepted in production, and this consumed bundle must not be rerun.
A later operation must establish workstation dual-stack reachability before mutation.
