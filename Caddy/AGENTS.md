# Caddy component rules

These rules apply beneath `Caddy/` and refine the component-neutral repository
rules in `../AGENTS.md`. The Caddy deployment is a dual-node HA system, so its
immutable-release, standby-first, evidence, and synchronization controls are
deliberately stricter than the repository defaults.

## Scope and archive

- `docs/caddy_plan-v1.1.md` owns the current Caddy architecture and authorized
  deviations. `HISTORY.md` indexes terminal operations and annotated tags.
- Preserve executed operation specifications, authorization hashes, and
  sanitized evidence manifests in an annotated, pushed Git tag before removing
  them from the main branch.
- Do not copy archived action files back into current tests or production
  inventories. Inspect the tag when historical reconstruction is requested.
- A live behavior change to an executed artifact requires a separately
  authorized successor. Repository cleanup and current-contract maintenance do
  not create deployment actions.

## Active deployment window

- Read `docs/DEPLOYMENT_LIFECYCLE.md` completely before defining, validating,
  executing, closing, or changing the Caddy deployment stream.
- `manifests/deployment-streams.tsv` is the deployment-window registry for this
  component. The Caddy stream may be `clean`, have exactly one `defined`
  operation, or be `terminal-pending` while an accepted or failed-consumed
  operation awaits its archive tag.
- Keep one neutral reusable transaction, one neutral outer runner, one
  production artifact manifest, and at most one small versioned operation
  specification. Never copy the transaction or runner to create a successor.
- A terminal-result commit retains the operation specification, records the
  planned annotated tag in `HISTORY.md`, clears the deployable-successor
  registry, and sets the stream to `terminal-pending`.
- Create and push the annotated tag for that exact terminal-result commit. The
  next repository commit removes consumed operation data, operation coverage,
  and retained repository evidence and returns the stream to `clean`, or
  atomically registers one already validated replacement operation.
  Do not require an otherwise empty intermediate cleanup commit.
- Action-numbered implementation, manifest, regression, and fixture filenames
  are prohibited on the current branch. The operation ID belongs only in the
  operation specification, stream registry, history, commit, and tag.
- `tests/deployment-window-policy.sh --check` enforces the Caddy stream. Do not
  use its Caddy-specific successor or coverage schema for another component.

## Authorization cadence

- Require an exact SHA-256 authorization for Caddy live mutation, failover,
  publication, transfer, restart, reload, or service transition.
- The accepted Caddy authorization identity remains the reviewed outer-runner
  SHA-256 after its operation specification, transaction, state contract, and
  coverage graph are hash-pinned and authorization-ready. That closed graph is
  the Caddy deployment bundle required by the repository rules.
- Put preflight, convergence, postcondition, rollback, and residue checks in
  the transaction that uses them.
- Add a diagnostic only when retained evidence cannot determine the cause.
  State the missing evidence before defining one.
- Do not contact either HA node during a definition-only task.

## Source boundaries

- `configs/` contains production configuration only.
- `scripts/` contains current runtime tools, repository tools, and neutral
  reusable deployment entrypoints.
- `systemd/` contains installable current units only.
- `templates/` contains current templates plus approved future examples.
- `manifests/` contains current contracts, accepted identities, the production
  manifest, and at most one operation specification.
- `tests/` contains neutral current-production validation only.
- Keepalived, Pi-hole, and Unbound sources belong to `homelab-dns`. Network
  controller artifacts belong to `homelab-network`.
- Never make a generic installer modify an existing production deployment.
  Live migrations use a bounded, standby-first transaction.

## Production inventories

- `manifests/accepted-live-artifacts.tsv` is the canonical deployed-hash
  registry.
- `manifests/production-artifacts.tsv` maps repository sources to installed
  paths and accepted deployed identities.
- `manifests/runtime-production.tsv` records the current runtime lifecycle
  boundary without referring to a historical action.
- `manifests/current-live-state.tsv` describes the latest accepted or recovered
  semantic state.
- Keep all current files classified in the relevant lifecycle registry. Keep
  the complete `configs/` tree classified in `config-lifecycle.tsv` and pin the
  accepted immutable release sources in `caddy-release-source.tsv`.
- Register only the next deployable operation in
  `manifests/deployable-successor.tsv`. Populate
  `deployable-successor-coverage.tsv` before reporting an outer-runner hash.
- Every proportional coverage row names a decision record and its raw evidence.
  The decision contains independently obtained expected and observed values,
  command status, and the raw-evidence SHA-256. Stdout labels and manually
  emitted coverage markers are summaries only.
- Coverage proves payload construction, exact transport and command generation,
  the full standby-first phase order, mutation boundaries, convergence,
  rollback, and residue. Do not create one row per ordinary assertion or
  duplicate the production inventory as coverage labels.
- Run `tests/deployable-successor-policy.sh --check` while the stream is clean.
  Run `--authorization-ready` only after a successor is registered and before
  requesting live authorization.
- The inactive operation specification says `action: none`, contains no
  operation-specific baseline or scope, and remains hash-pinned to the neutral
  transaction and outer runner. Clean-state policy rejects stale pins.
- Keep source and rendered identities typed separately.

## Current validation

- Run tests selected by `tests/focused-validation.yaml`. Current tests execute
  current entrypoints and may not delegate behavior to archived action
  regressions.
- Use `tests/run-focused.sh --profile NAME --phase host --container never` for
  host-only validation. Never omit both flags from a host-only run; the default
  `all/auto` mode intentionally launches Podman after the host phase.
- Use `tests/run-focused-container.sh --profiles CSV` for one network-disabled
  Debian 12 batch when Debian behavior is in scope. Invoke this Podman wrapper
  outside the filesystem sandbox on its first attempt.
- Do not reconstruct the archived full suite during current production work.
  Documentation and manifest metadata need structural checks, not a new
  behavioral test.
- Add a neutral regression when executable behavior or a safety boundary
  changes. Host and Debian runs exercise the same contract in two environments;
  they do not count as separate coverage.

## Production-path tests

A registered operation's neutral transaction and outer runner expose
no-network `--production-path-test` modes. The outer test must:

- construct the real payload and exact remote path;
- invoke the upload helper's prepare, accept, and disposition modes;
- construct the exact remote command and arguments;
- dispatch the transaction test;
- retain mode-checked evidence beneath a caller-provided `/tmp` directory;
- prove zero mutation; and
- execute success and failure readback branches for each node with actual
  bounded node evidence.

Tests execute the exact full phase sequence used by the live outer and
transaction entrypoints. Exercise only state variants that can change the
current operation's decision. Emitted labels without entrypoint execution do
not prove coverage.

Every production-state predicate enumerates all representations the live
contract treats as equivalent. Test permitted absent and protected-empty
states plus adjacent non-empty, symlinked, malformed, incorrectly owned, and
incorrectly mode-set states through the real predicate.

Production-path tests may create isolated input state and bounded substitutes
for unavailable external systems. They must not pre-write, copy, or print an
expected result as though the real producer, helper, outer runner, or
transaction created it. This includes command, transport, journal, status,
mutation, rollback, and acceptance evidence.

Substitutes receive the exact command emitted by the real entrypoint and record
observable calls and filesystem effects. External-system substitutes are
causal state machines: they produce journal, service, ownership, or availability
state only in response to the command that creates or queries that state. An
outer-runner test may not implement transaction modes or emit success records
for them. Cursor-bounded journal tests create events through the exercised
service-control path and read only events after the captured cursor.

A success label is only a summary emitted after the actual effects have been
independently validated. Authorization readiness must fail when a production
result can be obtained without executing the registered outer and transaction
paths. The authorization policy verifies causal decision records against raw
evidence; it never counts stdout markers.

Continuity evidence across HA ownership changes is per request, never an
aggregate sample. Each record identifies node role, scenario, monotonic
sequence, address family, endpoint and port, attempt type, bounded times,
command status, expected result, network timings, exposed addresses, sanitized
failure class, and nearest VRRP state and VIP count.

A primary failure under settled ownership rejects. During deliberate failover
or failback, a failed primary is accepted only when the same shared endpoint
and address family succeeds within 12 seconds and timestamped kernel
address-monitor evidence on either node proves a VIP transition between the
failed request and recovery. Missing or late recovery, missing transition
evidence, persistent family degradation, ambiguous or simultaneous ownership,
and every settled-owner failure reject. A retry is evidence, not a broad
waiver.

Timestamped kernel address-monitor events span the mutation window on both
nodes, and the workstation outer runner correlates them with request records.
Missing, malformed, duplicate, reordered, oversized, symlinked, incomplete, or
uncorrelatable evidence fails closed. Samplers and observers terminate promptly
on SIGTERM, terminate their children, and leave no temporary or orphaned
process residue.

Fix neutral implementations in place before executing a defined operation.
After execution, archive the terminal operation and define a successor only
when live behavior must change.

## Caddy shell rules

- Every tracked `scripts/*.sh` and `tests/*.sh` entrypoint uses Git mode
  `100755` and is executable in the worktree.
- Use `../tests/repository/shfmt-canonical.sh --write FILE...` for changed
  shell files. Do not run bare `shfmt -w`.
- Use `../tests/repository/multifile-grep-count-policy.sh --check FILE...` for
  changed shell files.
- A production-path test for an SSH runner executes the live transport branch
  through an isolated SSH substitute that reproduces OpenSSH's space-joined
  remote command and remote-shell parsing. Replacing the transport branch with
  direct local commands, or invoking arguments directly without that
  serialization step, is prohibited.
- Give mutation status, rollback, ownership, service state, and final acceptance
  distinct decision records. Group ordinary observations in structured
  evidence.

## Live transaction rules

- Validate standby Node B before Node A. Apply and accept Node B before changing
  Node A. Never reload or restart both nodes at the same time.
- Capture a journal cursor before a command and use `journalctl --after-cursor`
  for post-command evidence.
- Keep transaction-owned paths unique and clean up only exact validated paths.
  Roll back in reverse order.
- Return status `125` when a mutation occurred and recovery cannot be proven. A
  pre-mutation failure uses cleanup only.
- Notification delivery failure remains non-blocking. Preserve queued
  notifications and dead letters unless the transaction proves they belong to
  its test record.

## Caddy HA serving contract

- Node A is the preferred owner. Node B is standby.
- The two DNS VIPs and two Caddy VIPs move as one coupled dual-stack ownership
  group.
- Keepalived tracks node-local DNS health and Caddy serving health. A sustained
  Caddy serving failure may move all four VIPs.
- Pi-hole/lighttpd web-backend health generates a durable notification and does
  not change VRRP ownership.
- Shared router, internet, SSH, lsyncd, reconciliation, Apprise, monitoring, and
  certificate timer failures do not change VRRP ownership.
- Keep tracking probes within timeout, synchronous, silent, and limited to
  serving decisions. They create no background schedule, temporary protocol,
  snapshot, handler, or diagnostic. Validate the exact IPv4 and IPv6 paths.
- Retain the default SIGTERM disposition in tracking probes. Keepalived owns
  process-group timeout, termination, escalation, and status collection;
  lifecycle coverage proves prompt group termination and no orphan processes.
- Do not invoke `keepalived --config-test` or another Keepalived parser mode as
  a candidate-acceptance prerequisite on the installed production version.
  Repository validation plus bounded standby-first live convergence and
  rollback are authoritative.
- The generic installer must not deploy a serving-health migration.

## Synchronization contract

- Node A publishes normally to Node B through protocol v2.
- Node B publication is rejected unless `--emergency` is used while Node B
  owns both address families and all four VIPs.
- The receiver, finalizer, and reconciler fail closed on malformed, partial, or
  ambiguous candidates. Reconciliation owns validation, atomic promotion,
  Caddy reload, and rollback.
- Inspect the complete role-based outbound inventory before restarting managed
  lsyncd. Synchronization services cannot move VIPs.

## Systemd contract

Acceptance requires these units enabled and active:

- `caddy.service`;
- `caddy-lsyncd.service`;
- `caddy-sync-reconcile.path`;
- `caddy-cert-expiry.timer`;
- `caddy-sync-health.timer`;
- `caddy-apprise-worker.path`;
- `caddy-apprise-worker.timer`; and
- `caddy-pihole-web-health.timer`.

Timer, path, and `OnFailure` workers remain static and are not enabled directly.
Keep `caddy-api.service` and the distribution `lsyncd.service` masked and
inactive.

Managed-lsyncd acceptance requires an active service, positive MainPID, stable
restart count, successful result, parseable status snapshot, and no new
cursor-bounded transport or quarantine error. Status-file mtime is not a
heartbeat.

## Durable notifications

- Producers validate input and atomically enqueue a local record; they do not
  perform HTTP delivery.
- The persistent queue lives under `/var/lib`; runtime locks live under `/run`.
- A producer persists a stable transition identity before enqueue,
  acknowledges it afterward, and retries local enqueue on later timer runs.
- The delivery worker owns network retry, backoff, deduplication, receipts, and
  dead-letter disposition after a queue record exists.
- Notification success cannot affect Keepalived, Caddy, DNS, synchronization,
  or health acceptance.

## Repository checks

Run the relevant subset:

```bash
tests/accepted-live-hash-policy.sh --check
tests/deployment-lifecycle-policy.sh --check
tests/template-lifecycle-policy.sh --check
tests/test-lifecycle-policy.sh --check
tests/focused-validation-manifest-policy.sh --check
tests/systemd-boot-persistence-policy.sh --check
tests/deployable-successor-policy.sh --check
```

Before live authorization, also run:

```bash
tests/deployable-successor-policy.sh --authorization-ready
```
