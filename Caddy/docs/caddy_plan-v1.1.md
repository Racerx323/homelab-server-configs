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
4. A generic durable notification framework is a separate planned project in
   `homelab-notification`. No Caddy/DNS adoption or migration is approved.
   Future planning must decide source ownership, version pinning, migration,
   and the disposition of the accepted Caddy/DNS implementation.

## Completed work and archive

Action 35 accepted coupled DNS and Caddy health, immutable publication,
standby-first installation, durable notifications, and controlled failure
behavior. It closed through accepted Action 35as on 2026-08-24. The final
accepted checkpoint is preserved by annotated tag
`caddy-action35as-terminal-2026-08-24`.

The controlled failure exercise proved that owner-node Caddy, Pi-hole FTL,
Unbound, and Keepalived failures cause coupled failover with bounded
dual-stack continuity; a lighttpd failure produces one failure and one
recovery notification without VIP movement; and equivalent standby-node
failures do not take ownership from a healthy preferred node. Every scenario
restored services, release state, ownership, queues, and temporary paths.

`Caddy/HISTORY.md` records each terminal result and annotated tag. Git history
holds the full executed definitions. Consumed Action 35 operations must not be
restored or rerun. Action 35 has no pending deployment successor.

## Next work

No deployment action is pending. The next work consists of three
repository-only checkpoints. None contacts a node, changes production,
registers a successor, creates an operation specification, or adds an
action-numbered implementation artifact. The Caddy deployment stream remains
`clean`; `deployable-successor.tsv` remains `none`; and
`deployable-successor-coverage.tsv` remains header-only.

Complete and commit each checkpoint independently. Run the complete
pre-commit suite in every changed repository. Caddy checkpoints must also pass
the current repository-policy host profile. Define a deployment successor only
after the operator approves a specific live change.

### Checkpoint 1: Caddy operator documentation

Build the documentation set from current manifests, neutral scripts, systemd
inventories, and accepted production state:

| Document | Required scope |
| --- | --- |
| `Caddy/docs/QUICK_START.md` | Routine status, expected ownership, endpoint checks, focused validation, and first-response commands |
| `Caddy/docs/INSTALLATION.md` | Current prerequisites, ownership boundaries, partial-tool limitations, manual boundaries, and known installation-automation gaps |
| `Caddy/docs/OPERATIONS.md` | Normal and emergency publication, maintenance, failover interpretation, release retention, certificate renewal, and synchronization |
| `Caddy/docs/UNINSTALLATION.md` | Standby-first removal, release and queue preservation, service disablement, and externally owned boundaries |
| `Caddy/docs/TROUBLESHOOTING.md` | Caddy, DNS, lighttpd, Keepalived, lsyncd, reconciler, TLS, queue, timer, and ownership failures |
| `Caddy/docs/ARCHITECTURE.md` | As-built component boundaries and Mermaid steady-state, publication, and failover diagrams |
| `Caddy/docs/DEPLOYMENT_LIFECYCLE.md` | Caddy operation-window states, terminal archival, production-state equivalence, and causal evidence rules |
| `Caddy/docs/PROTOCOL_V2_RELEASE_LIFECYCLE.md` | Prepared-release construction, protocol-v2 transfer, activation, acceptance, and record reconciliation |

Keep documentation authority separated:

- `APPRISE_DELIVERY.md` owns the accepted notification contract and queue
  operations.
- `REPRODUCIBILITY.md` owns rebuild inputs and external recovery boundaries.
- This governing plan owns architecture decisions, deviations, lifecycle, and
  future authorization rules.
- `Caddy/README.md` becomes the documentation index.

The set must document routine IPv4 and IPv6 DNS and trusted-HTTPS validation;
Node A MASTER with four VIPs and Node B BACKUP with zero VIPs;
notification-only Pi-hole/lighttpd failures; standby-first changes; the ban on
simultaneous node reloads; normal Node A and guarded emergency Node B
publication; rollback and status 125; queue inspection, retry, dead-letter
limitations, capacity monitoring, and evidence-preserving uninstall; and the
package-owned, repository-owned, Pi-hole-owned, and secret/external
boundaries. Operator commands must come from current neutral entrypoints, not
historical action procedures.

`INSTALLATION.md` must describe the current installation boundary without
presenting a clean-node procedure. No current entrypoint performs a complete
installation or disaster recovery. `install-caddy-ha.sh` installs part of the
repository-owned filesystem and identity state; operators must not use it as a
production installation, migration, or recovery workflow. Routine production
changes continue through the neutral operation and protocol-v2 release path.

Checkpoint 1 is complete. The operator documents, README index, and neutral
`operator-documentation-policy.sh` now enforce the current authority,
entrypoint, accepted-live, and operational boundaries. No node contact or live
change occurred.

### Checkpoint 2: Canonical LikeC4 architecture

Update `homelab-docs/architecture/likec4` to describe accepted production.
Model the coupled DNS and Proxy platform; both HA nodes; Pi-hole FTL, Unbound,
lighttpd, Caddy, Keepalived, managed lsyncd, finalizer, and reconciler; the DNS
and Proxy IPv4 and IPv6 VIPs; one `PIHOLE_DUALSTACK` group controlling all four
VIPs; immutable protocol-v2 releases; external TLS material; the persistent
notification queue; Apprise API and notification providers; and repository
ownership boundaries.

Add or update these views:

- `reverse-proxy-ha` for steady-state components and relationships;
- `reverse-proxy-failover` for Caddy or DNS failure, coupled VIP movement,
  continuity, and preferred-owner recovery;
- protocol-v2 publication from the Node A publisher through lsyncd, Node B
  finalization, reconciliation, and activation;
- notification delivery from producer through the durable queue and worker to
  Apprise API and providers; and
- deployment instances for Caddy and lsyncd on both nodes plus the shared
  Proxy VIP.

Remove stale implications of DNS-only VIP ownership, separate Caddy VRRP
instances, Caddy health outside eligibility, planned Munin integration, or a
Proxy VIP independent of `PIHOLE_DUALSTACK`. Validate every edited LikeC4
source with the repository's current validation procedure and record
generated-view provenance according to `homelab-docs` policy.

Checkpoint 2 is complete at `homelab-docs` commit
`a0562883357796c392690fd54177a87f3dbf1f25`. The canonical model retains the
production Pi-hole v5 versions and now records coupled four-VIP ownership,
both node deployments, protocol-v2 publication, durable notification delivery,
external inputs, and repository ownership. Validation passed with the
CI-pinned LikeC4 1.59.1 focused command, `likec4 format --check`, full
`likec4 validate`, and `pre-commit run --all-files`. LikeC4 1.59.1 calculates
`filteredFiles` from files containing reported errors, so the valid focused
run returned `filteredFiles=0` and `filteredErrors=0`; its repeated `--file`
arguments identify the five edited `.c4` sources. No generated export was
committed, no node was contacted, and no deployment successor was created.

### Checkpoint 3: Reverse-proxy backend onboarding

Checkpoint 3 is complete in the repository commit that contains this record.
[`APPLICATION_ONBOARDING.md`](APPLICATION_ONBOARDING.md) now owns the approval
inventory, transport and TLS policy, health contract, request-header boundary,
client restrictions, validation, publication, acceptance, and rollback for a
new backend. `Caddy/templates/reverse-proxy.caddy.example` is a supported
example with lifecycle `supported-example` and `deployable=no`; no production
manifest, installer, or renderer consumes it.

The existing template-lifecycle policy renders HTTP and verified-HTTPS forms
from the exact token allowlist. The network-disabled Debian 12 batch adapted
and validated both forms with Caddy 2.11.4. The operator-documentation policy
now enforces the guide, its authority links, current entrypoints, future-prompt
isolation, and the absence of historical Action commands. Markdown lint, the
current repository-policy host profile, the Debian profile, and the complete
pre-commit suite form this checkpoint's repository acceptance.

No application, endpoint, or DNS record was inferred or registered. No HA node
was contacted, no accepted-live production file or inventory changed, and no
operation specification or deployment successor was created. A later backend
requires an approved inventory, repository and DNS reconciliation, an
immutable protocol-v2 release, production-path validation, and separate live
authorization.

The approved onboarding contract gives every application an A and AAAA record
for the shared Proxy VIPs. Each shared address retains the single canonical
PTR target `proxy.local.theama.co.`, and that canonical name resolves forward
to both Proxy VIPs. Application hostnames do not receive individual PTR
records; Caddy selects them through TLS SNI and the HTTP `Host` header. DNS
acceptance validates the application forward records and the canonical
forward-confirmed reverse mapping without rewriting accepted-live records.

### Future reverse-proxy fragment generator project

The next planned Caddy repository project begins from
[`FUTURE_REVERSE_PROXY_GENERATOR_PROMPT.md`](FUTURE_REVERSE_PROXY_GENERATOR_PROMPT.md).
It must define a deterministic noninteractive renderer, its reviewed input
schema, source-of-truth adapter, orchestration boundary, temporary-release
validation, lifecycle transitions, and authorization boundaries before
implementation begins.

The prompt is the only current reference to this project. Current operator
documents and `Caddy/README.md` must not present the proposed generator as an
accepted capability. The planning project must not select a backend, change
DNS, contact a node, register a deployment successor, create an operation
specification, or publish a release.

### Future complete-installation project

The separately planned complete-installation project does not design or
authorize a clean-node installation. It must begin from
[`FUTURE_COMPLETE_INSTALLATION_PROMPT.md`](FUTURE_COMPLETE_INSTALLATION_PROMPT.md).
That prompt is the only current reference to the future project. The current
operator documents, `Caddy/README.md`, `APPRISE_DELIVERY.md`, and
`REPRODUCIBILITY.md` must not link to it or present its proposed work as an
accepted production capability.

The future project remains definition-only until the operator accepts its
dependency map, ownership model, interfaces, tests, and authorization
boundaries. It is separate from the operator documentation, LikeC4, backend
onboarding, and generic durable-notification work.

### Independent durable-notification framework planning

The generic durable Apprise framework is unrelated to these Caddy
checkpoints. Its planning remains in
`homelab-notification/durable-apprise/PLANNING_PROMPT.md`. That project does not
assume migration or replacement of the accepted Caddy/DNS client. Any future
adoption must first decide repository ownership, version pinning, producer
integration, state compatibility, migration, rollback, and the disposition of
the current implementation.
