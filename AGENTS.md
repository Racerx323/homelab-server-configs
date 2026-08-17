# Repository rules

These rules govern current production code and approved future work in this
repository. The annotated tag recorded in `Caddy/HISTORY.md` preserves the
executed deployment archive.

## Scope and archive

- Keep the main branch limited to current production artifacts and approved
  future tasks.
- Preserve executed action artifacts, authorization hashes, and evidence in an
  annotated, pushed Git tag before removing them from the main branch.
- Record each archive boundary in `Caddy/HISTORY.md` with its tag and commit.
- Do not copy archived action files back into current tests or production
  inventories. Inspect the tag when historical reconstruction is requested.
- Fix reusable production code, unexecuted definitions, tests, fixtures, and
  workstation consumers in place.
- A live behavior change to an executed artifact requires a separately
  authorized successor. Repository cleanup and current-contract maintenance do
  not create deployment actions.

## Active deployment windows

- `deployment-streams.tsv` is the repository-wide deployment-window registry.
  Every deployment stream must be registered there, even when its state is
  `clean`.
- A stream may be `clean`, have exactly one `defined` successor, or be
  `terminal-pending` while an accepted or failed-consumed action awaits its
  archive tag. Never carry two pending actions in one stream.
- A terminal-result commit retains the executed action files, records the
  planned annotated tag in the stream history, clears the deployable-successor
  registry, and sets the stream to `terminal-pending`.
- Create and push the annotated tag for that exact terminal-result commit.
  Immediately follow it with a cleanup commit that removes the consumed
  runner, transaction, action manifest, action coverage, action regression,
  fixtures, and retained repository evidence, then sets the stream to `clean`.
- Action-numbered implementation files are allowed only for the action named by
  a `defined` or `terminal-pending` stream. Current validation profiles and
  neutral tests must never invoke them.
- The neutral repository policy
  `Caddy/tests/deployment-window-policy.sh --check` enforces these rules for
  every registered stream. Do not add component-specific exceptions.

## Authorization cadence

- Workstation edits, definitions, focused tests, formatters, and policy checks
  need no deployment authorization.
- Require an exact SHA-256 authorization for live mutation, failover,
  publication, transfer, restart, or service transition.
- Put preflight, convergence, postcondition, and residue checks in the
  transaction that uses them.
- Add a diagnostic only when retained evidence cannot determine the cause.
  State the missing evidence before defining one.
- Do not contact an HA node during a definition-only task.

## Current source boundaries

- `Caddy/configs/` contains production configuration only.
- `Caddy/scripts/` contains current runtime tools, repository tools, and the
  one registered future transaction.
- `Caddy/systemd/` contains installable current units only.
- `Caddy/templates/` contains current templates plus approved future examples.
- `Caddy/manifests/` contains current contracts, accepted identities, and the
  one deployable successor.
- `Caddy/tests/` contains neutral current-production validation only.
- Keepalived, Pi-hole, and Unbound sources belong to `homelab-dns`.
- Network controller artifacts belong to `homelab-network`.
- Never make a generic installer modify an existing production deployment.
  Live migrations use a bounded, standby-first transaction.

## Production inventories

- `Caddy/manifests/accepted-live-artifacts.tsv` is the canonical deployed-hash
  registry.
- `Caddy/manifests/production-artifacts.tsv` maps repository sources to
  installed paths and accepted deployed identities.
- `Caddy/manifests/runtime-production.tsv` records the current runtime
  lifecycle boundary without referring to a historical action.
- `Caddy/manifests/current-live-state.tsv` describes the latest accepted or
  recovered semantic state.
- Keep all current files classified in the relevant lifecycle registry.
- Register only the next deployable action in
  `Caddy/manifests/deployable-successor.tsv`.
- Populate `deployable-successor-coverage.tsv` before reporting an outer
  runner hash.
- Every coverage row names a decision record and its raw evidence. The decision
  must contain independently obtained expected and observed values, command
  status, and the raw-evidence SHA-256. Stdout labels and manually emitted
  coverage markers are summaries only and never satisfy authorization.
- Coverage must include every current production-inventory key and successful
  and failed node-evidence readback paths for both nodes.
- Run
  `Caddy/tests/deployable-successor-policy.sh --authorization-ready` before
  requesting live authorization.
- Keep source and rendered identities typed separately. Do not substitute one
  for the other.

## Current validation

- Run tests selected by `Caddy/tests/focused-validation.yaml`.
- Current tests must execute current entrypoints. They may not delegate behavior
  to archived action regressions.
- Use `Caddy/tests/run-focused.sh --profile NAME` for host validation.
- Use `Caddy/tests/run-focused-container.sh --profiles CSV` for one
  network-disabled Debian 12 batch when Debian behavior is in scope.
- Do not reconstruct the archived full suite during current production work.
- Documentation and manifest metadata need structural checks, not a new
  behavioral test.
- Add a neutral regression when executable behavior or a safety boundary
  changes.
- The host and Debian runs exercise the same contract in two environments.
  They do not count as separate coverage.

## Production-path tests

A registered live transaction and its outer runner must expose no-network
`--production-path-test` modes.

The outer test must:

- construct the real payload;
- generate the exact remote path;
- invoke the upload helper's prepare, accept, and disposition modes;
- construct the exact remote command and arguments;
- dispatch the transaction test;
- retain mode-checked evidence under a caller-provided `/tmp` directory;
- prove zero mutation.
- execute success and failure readback branches for each node and retain the
  actual bounded node evidence in the caller-provided evidence directory.

The transaction test must exercise each state-dependent pre-mutation branch and
reach payload validation plus a no-mutation sentinel on accepted paths. Cover
absent, exact, partial, extra, malformed, unsafe-metadata, symlink, and node-role
states when they affect the action. Emitted labels without entrypoint execution
do not prove coverage.

Production-path tests may create isolated input state and bounded substitutes
for unavailable external systems. They must not pre-write, copy, or print an
expected result as though the real producer, helper, outer runner, or
transaction created it. This prohibition includes fabricated command,
transport, journal, status, mutation, rollback, and acceptance evidence.
Substitutes must receive the exact command emitted by the real entrypoint and
record observable calls and filesystem effects for assertions. A success label
is only a summary emitted after those actual effects have been independently
validated; labels and fixture-authored result files are never evidence by
themselves. Authorization readiness must fail when a production result can be
obtained without executing the registered outer and transaction paths.
The authorization policy verifies causal decision records against their raw
evidence; it never counts stdout markers.

## Shell rules

- Invoke Bash scripts with `/bin/bash`; do not rely on an executable bit as
  the interpreter contract.
- Every tracked `Caddy/scripts/*.sh` and `Caddy/tests/*.sh` entrypoint must
  use mode `100755` in Git and be executable in the worktree.
- Do not reuse a script-level readonly variable name as a function-local name.
  Bash dynamic scope can reject the local declaration.
- Use Debian POSIX `awk`. Avoid interval quantifiers in awk regular
  expressions.
- Do not consume a multi-file `grep -c` result as one scalar.
- Use `Caddy/tests/shfmt-canonical.sh --write FILE...` for changed shell
  files. Do not run bare `shfmt -w`.
- Use `Caddy/tests/multifile-grep-count-policy.sh --check FILE...` for changed
  shell files.
- Never send a multi-command program through `ssh ... /bin/bash -c ...` or
  `ssh ... sudo /bin/bash -c ...`. OpenSSH rebuilds its command arguments as a
  remote-shell string; local argument boundaries and quoting are not preserved.
- Stream every multi-command remote Bash program on standard input through the
  exact boundary `ssh HOST 'cd / && sudo -n /bin/bash -s -- ARG...' <PROGRAM`.
  A deliberately unprivileged program may omit `sudo -n`, but it must retain
  `cd /`, `/bin/bash -s --`, explicit positional arguments, and stdin streaming.
- A production-path test for an SSH runner must execute the runner's live
  transport branch through an isolated SSH substitute that reproduces
  OpenSSH's space-joined remote command and remote-shell parsing. Replacing the
  transport branch with direct local commands, or invoking arguments directly
  without that serialization step, is prohibited.
- Capture SSH stdout, stderr, and status in workstation files beneath `/tmp`.
  Long-running node commands must write node-local evidence beneath `/tmp`
  before the workstation reads it back.
- Bound all captured output. Reject control characters, binary data, secrets,
  and oversized streams.
- Give mutation status, rollback, ownership, service state, and final acceptance
  distinct decision labels. Group ordinary observations in structured evidence.

## Live transaction rules

- Validate standby Node B before Node A.
- Apply and accept Node B before changing Node A.
- Never reload or restart both nodes at the same time.
- Capture a journal cursor before a command and use
  `journalctl --after-cursor` for post-command evidence.
- Keep transaction-owned paths unique and clean up only exact validated paths.
- Roll back in reverse order.
- Return status 125 when a mutation occurred and recovery cannot be proven.
- A pre-mutation failure uses cleanup only.
- Notification delivery failure remains non-blocking.
- Preserve queued notifications and dead letters unless the transaction proves
  they belong to its test record.

## Caddy HA serving contract

- Node A is the preferred owner. Node B is standby.
- The two DNS VIPs and two Caddy VIPs move as one coupled dual-stack ownership
  group.
- Keepalived tracks node-local DNS health and Caddy serving health.
- A sustained Caddy serving failure may move all four VIPs.
- Pi-hole/lighttpd web-backend health generates a durable notification and does
  not change VRRP ownership.
- Shared router, internet, SSH, lsyncd, reconciliation, Apprise, monitoring, and
  certificate timer failures do not change VRRP ownership.
- Keep probes within their Keepalived timeout and validate exact IPv4 and IPv6
  paths.
- Consumed serving-health actions are preserved only by the annotated tags in
  `Caddy/HISTORY.md`. The single registered successor, when present, owns the
  next migration. The generic installer must not deploy that migration.

## Synchronization contract

- Node A publishes normally to Node B through protocol v2.
- Node B publication is rejected unless `--emergency` is used while Node B
  owns both address families and all four VIPs.
- The receiver, finalizer, and reconciler fail closed on malformed, partial, or
  ambiguous candidates.
- Reconciliation owns validation, atomic promotion, Caddy reload, and rollback.
- Inspect the complete role-based outbound inventory before restarting managed
  lsyncd.
- lsyncd and reconciliation are control-plane services. Their health cannot move
  VIPs.

## Systemd contract

Acceptance requires these units enabled and active:

- `caddy.service`
- `caddy-lsyncd.service`
- `caddy-sync-reconcile.path`
- `caddy-cert-expiry.timer`
- `caddy-sync-health.timer`
- `caddy-apprise-worker.path`
- `caddy-apprise-worker.timer`
- `caddy-pihole-web-health.timer` after Action 35

Timer, path, and `OnFailure` workers remain static and must not be enabled
directly. Keep `caddy-api.service` masked and inactive. Keep the distribution
`lsyncd.service` masked and inactive.

Managed-lsyncd acceptance requires an active service, positive MainPID, stable
restart count, successful result, a parseable status snapshot, and no new
cursor-bounded transport or quarantine error. Status-file mtime is not a
heartbeat.

## Durable notifications

- Producers validate input and atomically enqueue a local record.
- Producers do not perform HTTP delivery.
- The persistent queue lives under `/var/lib`; runtime locks live under
  `/run`.
- A producer persists a stable transition identity before enqueue, acknowledges
  it after enqueue, and retries local enqueue on later timer runs.
- The delivery worker owns network retry, backoff, deduplication, receipts, and
  dead-letter disposition after a queue record exists.
- Notification success cannot affect Keepalived, Caddy, DNS, synchronization, or
  health acceptance.

## Repository checks

Run the relevant subset:

```bash
Caddy/tests/accepted-live-hash-policy.sh --check
Caddy/tests/deployment-lifecycle-policy.sh --check
Caddy/tests/template-lifecycle-policy.sh --check
Caddy/tests/test-lifecycle-policy.sh --check
Caddy/tests/focused-validation-manifest-policy.sh --check
Caddy/tests/systemd-boot-persistence-policy.sh --check
Caddy/tests/deployable-successor-policy.sh --check
```

Before live authorization, also run:

```bash
Caddy/tests/deployable-successor-policy.sh --authorization-ready
```
