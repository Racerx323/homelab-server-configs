# HA Caddy governing plan

## Current status

The dual-node Caddy service is accepted in production. Action 35 closed through
Action 35as on 2026-08-24. The Caddy deployment stream is clean and has no
registered successor.

Node A is the preferred owner. Node B is standby. Both nodes run the same
accepted immutable Caddy release and the same serving-health policy. The
current semantic state is recorded in `current-live-state.tsv`; exact deployed
hashes are recorded in `accepted-live-artifacts.tsv` and
`production-artifacts.tsv`.

No live work is authorized by this document. A future mutation requires one
defined operation, production-path validation, an exact outer-runner SHA-256,
and operator authorization.

## Ownership

| Area | Repository |
| --- | --- |
| Caddy configuration, release tools, systemd units, notification client | `homelab-server-configs` |
| Keepalived, Pi-hole, Unbound, DNS health probe, transition producer | `homelab-dns` |
| Network-controller configuration | `homelab-network` |
| Generic future durable Apprise framework | `homelab-notification` |

The Caddy installer must not overwrite Keepalived, Pi-hole, or Unbound sources.
Cross-repository deployment operations pin exact reviewed files from their
owning repositories.

## Nodes and addresses

| Role | Host | IPv4 | IPv6 |
| --- | --- | --- | --- |
| Preferred node A | `j1-svpihole0` | `10.1.0.53` | `fd36:5aa8:6971:1::53` |
| Standby node B | `j1-svpihole00` | `10.1.0.54` | `fd36:5aa8:6971:1::54` |
| Shared DNS | `pihole.local.theama.co` | `10.1.0.55` | `fd36:5aa8:6971:1::55` |
| Shared Proxy | `proxy.local.theama.co` | `10.1.0.56` | `fd36:5aa8:6971:1::56` |

`pihole-admin.local.theama.co` resolves to the shared Proxy VIP. The node names
remain available for node-specific administration and health checks.

## Coupled ownership

Keepalived owns four VIPs in one `PIHOLE_DUALSTACK` sync group. The DNS VIPs
remain in `virtual_ipaddress`; the Proxy VIPs remain in
`virtual_ipaddress_excluded`. Excluded affects VRRP advertisement encoding, not
ownership. The sync group still adds and removes all four addresses together.

Node A should converge to IPv4 and IPv6 MASTER with four VIPs. Node B should
converge to BACKUP with zero VIPs. The design rejects split ownership,
simultaneous ownership, one-family ownership, and an owner that cannot serve
DNS or trusted HTTPS.

Keepalived uses:

- `check-dns.sh` for Pi-hole FTL and Unbound serving health.
- `check-caddy.sh` for trusted Caddy HTTPS serving health.

Both scripts run under their configured `keepalived_script` identities. They
fit inside the two-second timeout and terminate with their child processes when
Keepalived sends SIGTERM. Keepalived's exit and signal observation controls
eligibility. Status publication remains best effort.

## Service boundaries

Pi-hole FTL accepts client DNS. Unbound provides recursive resolution and the
internal authoritative zone. lighttpd serves the node-local Pi-hole web
backend. Caddy terminates TLS and proxies web requests. Keepalived assigns the
shared DNS and Proxy addresses.

The Pi-hole/lighttpd monitor runs from a systemd timer. It checks both node
families through Caddy and reports Proxy backend failure and recovery. It never
changes VRRP eligibility.

Caddy uses active and passive reverse-proxy health checks for the Pi-hole web
backend. The backend check and the node `/healthz` endpoint serve different
purposes: Caddy selects a backend with the first; Keepalived tests the public
node serving path with the second.

## Caddy release contract

`/etc/caddy/current` selects one immutable protocol-v2 release. Each release
contains its payload manifest, release identity, configuration, and protected
TLS material. Caddy starts with:

```text
/usr/bin/caddy run --environ --config /etc/caddy/current/Caddyfile --adapter caddyfile
```

The accepted payload manifest SHA-256 is:

```text
2253a491e048c9d670865e3d39efa3c9e9acd92a31ec33219f97ba91428b0133
```

`caddy-release-source.tsv` pins the five non-secret repository sources that
belong to that release. TLS files remain outside Git.

The repository Caddy source set contains:

- `Caddyfile`
- `conf.d/00-health.caddy`
- `conf.d/10-pihole-admin.caddy`
- `conf.d/90-default-deny.caddy`
- `conf.d/91-exact-listener-default-deny.caddy`

## Publication and synchronization

Node A performs normal publication. The publisher creates an immutable
revision, validates it, records the target, and exposes the outbound state to
managed lsyncd. Node B receives the candidate under its incoming namespace.
The finalizer validates manifest contents, ownership, modes, marker state, and
release identity. The reconciler chooses one valid target and activates it.

Node B can publish with `--emergency` while it owns IPv4 and IPv6 and all four
VIPs. Emergency publication freezes normal transport and retains the same
manifest, validation, and reconciliation rules.

The receiver rejects unsafe paths, symlinks, hard links, special files,
malformed manifests, incomplete markers, wrong source identities, and changed
payloads. The reconciler fails closed on same-parent conflicts and multiple
eligible targets.

Accepted steady state has empty incoming, outbound, and quarantine namespaces.
A permitted namespace may be absent or may exist as a protected empty
directory. Tests execute both accepted forms and reject adjacent unsafe forms.

## Protocol-v2 services

| Component | Purpose |
| --- | --- |
| `caddy-lsyncd.service` | Managed release transport |
| `caddy-sync-reconcile.path` | Watches finalized incoming state |
| `caddy-sync-reconcile.service` | Validates and activates one release |
| `caddy-sync-health.timer` | Checks synchronization health |
| `caddy-cert-expiry.timer` | Checks certificate expiry |
| `caddy-sync-failure@.service` | Enqueues bounded replication failures |

The generic `lsyncd.service` remains masked. The managed Caddy unit owns the
transport configuration and runtime directory.

## Durable notification delivery

Producers write bounded `caddy-apprise-queue/v1` records through
`caddy-apprise-enqueue`. The enqueue helper publishes a record atomically under
`/var/lib/caddy-apprise-queue`. The path and persistent timer activate the
delivery worker. The worker retries with bounded backoff, records a local
receipt after acceptance, and moves an exhausted record to dead letter.

Delivery failure cannot change DNS, Caddy, Keepalived, lsyncd, or
reconciliation results. The delivery contract is at least once because a
crash can occur after the remote endpoint accepts a request and before the
worker commits its receipt.

Current notifications use one multiline plain-text format and the Apprise
severity icons. Keepalived notifications preserve the prior state. Authorized
transactions mark intentional stops as planned maintenance. See
`APPRISE_DELIVERY.md` for operations and security rules.

## Systemd persistence

Installable units and drop-ins are listed in `systemd-lifecycle.tsv`. The
installer enables the required paths and timers and leaves static services to
their trigger units. Validation checks enablement, active state where required,
unit identities, and the correct environment-file boundary.

The Pi-hole web worker runs as `pi:pi` with supplementary group `caddy-tls`.
Its unit grants write access to the persistent notification queue. Acceptance
requires a direct successful service invocation followed by a separate
timer-owned healthy invocation.

## Security and file modes

- Root owns system configuration and systemd units.
- `caddy-tls` grants bounded read access to protected Caddy environment and TLS
  material.
- `caddy-sync` owns protocol transport namespaces.
- Queue directories use `pi:pi:0700`; queue records use `0600`.
- Protocol namespace roots use the recorded `caddy-sync` ownership and
  protected modes.
- Runtime evidence uses unique `/tmp` roots with bounded UTF-8 files and no
  secrets.

Scripts reject unsafe roots, symlinks, special files, control characters,
oversized streams, malformed identities, and ambiguous state.

## Deployment transaction rules

The repository keeps one neutral transaction and one neutral outer runner. A
small operation specification supplies the versioned intent. The current
operation is inactive.

Future live work follows this order:

1. Verify repositories and the deployment stream.
2. Validate the accepted current-production baseline.
3. Mutate and accept Node B.
4. Mutate and accept Node A.
5. Prove stable preferred ownership and continuous service.
6. Read back bounded evidence and remove exact temporary programs.

Rollback restores Node A and then Node B in reverse mutation order. The
transaction returns 125 only when mutation occurred and exact recovery cannot
be proven.

Production-path tests execute the same outer and transaction state machines.
They may substitute bounded external commands, but those substitutes must
receive the exact emitted command and create observable causal effects. Tests
cannot fabricate transport, journal, status, mutation, rollback, acceptance,
or success evidence.

## Production manifests

| Manifest | Authority |
| --- | --- |
| `accepted-live-artifacts.tsv` | Accepted deployed hashes |
| `production-artifacts.tsv` | Repository-to-node mappings |
| `current-live-state.tsv` | Accepted semantic cluster state |
| `runtime-production.tsv` | Runtime lifecycle boundary |
| `caddy-release-source.tsv` | Accepted non-secret Caddy release sources |
| `serving-health-production.tsv` | Accepted serving-health files |
| `durable-apprise-production.tsv` | Accepted durable-notification files |
| `config-lifecycle.tsv` | Complete configuration classification |
| `deployable-successor.tsv` | Current successor state |

Lifecycle registries also cover manifests, scripts, systemd units, templates,
and tests.

## Validation

Run host profiles with explicit host-only flags:

```bash
Caddy/tests/run-focused.sh --profile current-repository-policies --phase host --container never
Caddy/tests/run-focused.sh --profile current-serving-health --phase host --container never
Caddy/tests/run-focused.sh --profile current-synchronization --phase host --container never
Caddy/tests/deployable-successor-policy.sh --check
```

Use one network-disabled Debian batch when a change depends on Debian tooling
or systemd behavior:

```bash
Caddy/tests/run-focused-container.sh --profiles current-repository-policies,current-serving-health,current-synchronization
```

The clean stream must reject `--authorization-ready`.

## Rollback invariants

- Keep one healthy owner throughout a standby-first deployment.
- Do not reload both nodes at once.
- Do not accept split-family or simultaneous ownership.
- Preserve the previous release until the new release passes acceptance.
- Restore exact files, modes, owners, enablement, and release selection.
- Prove final Node A MASTER and Node B BACKUP state after rollback.
- Keep delivery failure outside rollback and serving-health decisions.

## Active deviations

1. The installed Keepalived 2.2.7 parser mode does not provide a sound
   configuration acceptance check. The deployment validates exact source,
   script behavior, daemon-owned results, and bounded journals instead.
2. Proxy VIPs remain under `virtual_ipaddress_excluded` so ownership follows
   the coupled sync group without placing those addresses in VRRP adverts.
3. Apprise delivery remains at least once. The worker sends a stable
   `Idempotency-Key`, but the remote endpoint does not promise duplicate
   suppression.
4. The generic durable notification package has not replaced the accepted
   Caddy/DNS client. That work belongs to `homelab-notification`.

## Completed work and archive

Action 35 accepted coupled DNS and Caddy health, immutable publication,
standby-first installation, durable notifications, and controlled failure
behavior. `Caddy/HISTORY.md` records each terminal result and annotated tag.
Git history holds the full executed definitions.

## Next work

No deployment action is pending. Maintain operator documentation from current
manifests and neutral scripts. Define a new successor only for a reviewed live
change.
