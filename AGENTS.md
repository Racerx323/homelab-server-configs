# Repository Agent Rules

This file contains repository-specific execution and validation rules. It does
not describe services that are not configured in this repository. GitHub
automation is authoritative only when represented by a tracked file under
`.github/`.

## Deployment authorization cadence

- Workstation-only definitions, edits, focused tests, formatters, linters, and
  policy checks do not require a separate deployment authorization.
- Embed read-only preflight, postcondition, convergence, and residue checks in
  the live transaction that depends on them. Do not create a separate numbered
  diagnostic or acceptance action when the original action retained enough
  evidence to decide the result.
- A follow-up diagnostic is justified only when retained evidence is genuinely
  incomplete or ambiguous. State the missing evidence explicitly.
- Require separate exact SHA-256 authorization for a live mutation, disruptive
  failover, publication, transfer, service transition, or similarly material
  node action. A read-only node query may use the scope already authorized for
  its parent transaction; do not invent an extra gate solely because it uses
  SSH.
- Immutability applies to an exact executed/authorized runner and its retained
  evidence. It does not freeze reusable libraries, unexecuted definitions,
  tests, fixtures, or workstation-only consumers. Fix those directly and
  preserve the executed artifact by path and hash when necessary.

## Testing instructions

- Require all in-scope current-production tests and governing policies to pass.
  Record an unrelated historical failure, but do not block current work unless
  it exposes a shared dependency or policy defect.
- `Caddy/tests/run.sh` is an opt-in historical reconstruction wrapper, not a
  current-production gate. Run it only when historical reconstruction is
  explicitly requested. It uses Podman and therefore must run outside the
  filesystem sandbox on its first attempt.
- Run focused Debian validation only through
  `Caddy/tests/run-focused-container.sh --profiles CSV` or its explicitly
  historical `--action ID` form. The wrapper
  owns the validation image's existing Bash entrypoint, passes `-lc` directly
  instead of supplying a second `/bin/bash`, exports the required
  `CADDY_VALIDATION_CONTAINER=1` marker, disables networking, and mounts the
  workspace read-only. Treat this wrapper as a Podman command and run it
  outside the filesystem sandbox on its first attempt. Do not construct ad hoc
  focused `podman run` invocations.
- The repository `.vscode` directory contains shared configuration and must
  remain trackable. Preserve the root-anchored `!/.vscode/` and
  `!/.vscode/**` rules in `.gitignore`, and run
  `Caddy/tests/vscode-tracking-policy-regression.sh` after ignore-policy
  changes.
- Add or update tests when executable behavior or a safety boundary changes.
  Documentation, journal, manifest-only metadata, and current-hash updates need
  structural validation, not a new behavioral regression by default.
- Run linters and formatters to ensure code quality. For shell files, never run
  bare `shfmt -w`; use
  `Caddy/tests/shfmt-canonical.sh --write FILE [FILE ...]`. Use `--check` for
  validation. The wrapper pins the repository's `-i 4 -ci` policy and rejects
  empty, broad, symbolic-link, and unapproved-repository targets.
- Never consume `grep -c`, `grep --count`, or a combined count option such as
  `grep -Ec` as one scalar when the command has multiple file operands. GNU
  grep emits one filename-prefixed count per file, so numeric evaluation is
  invalid and can hide independently failing assertions. Use one grep command
  per file with a distinct assertion label and an explicit failure return.
  Complex count invocations with five or more command arguments are also
  prohibited in scalar validators; simplify them to the canonical
  `grep COUNT_OPTION PATTERN FILE` shape. Enforce this repository-wide for
  every changed shell file with
  `Caddy/tests/multifile-grep-count-policy.sh --check FILE [FILE ...]`; the
  pre-commit hook runs the same policy automatically.
- Current accepted live-artifact hashes have one canonical source:
  `Caddy/manifests/accepted-live-artifacts.tsv`. Every still-deployable action
  that consumes one of those hashes must be registered in
  `Caddy/manifests/deployable-live-hash-consumers.tsv` by key, consumer path,
  and readonly variable. Never copy a current live hash into a deployable
  consumer without registering it. The always-run pre-commit hook
  `Caddy/tests/accepted-live-hash-policy.sh --check` rejects missing,
  duplicate, malformed, or stale consumers. When accepted live state changes,
  update the canonical manifest in the same change; the policy must invalidate
  every registered stale deployable consumer before any SSH or live action.
  Preserve an executed runner and its evidence immutably, but correct reusable
  code, unexecuted definitions, tests, fixtures, and workstation consumers in
  place. Create a successor only when changing the behavior of an already
  executed live artifact. The typed completeness boundary is
  `Caddy/manifests/production-artifacts.tsv`: every accepted-live key must map
  exactly once to its repository, source path, installed path, node, source
  identity, deployed identity, accepting action, and current lifecycle. A
  rendered artifact may have distinct source and deployed identities; never
  substitute one for the other. Classify every file directly beneath
  `Caddy/manifests/` in `Caddy/manifests/manifest-lifecycle.tsv`. Do not rewrite
  an immutable action definition to update its historical embedded status;
  record its current disposition in the lifecycle registry. The accepted-live
  policy rejects missing inventory entries, source drift in this repository,
  identity/action mismatches, and unclassified manifest files.
- Treat `Caddy/manifests/current-live-state.tsv` as the typed semantic input to
  the next live successor. Its evidence must describe the last accepted final
  state or proven recovery state, including absence or partial-installation
  facts that alter pre-mutation behavior. Never reconstruct that input from an
  older action's initial assumptions.
- Before reporting an outer-runner SHA-256, register the one deployable
  successor in `Caddy/manifests/deployable-successor.tsv` and its complete
  state matrix in `Caddy/manifests/deployable-successor-coverage.tsv`. Both the
  outer runner and remote transaction must expose a no-network
  `--production-path-test`. Routine repository checks use
  `Caddy/tests/deployable-successor-policy.sh --check`, while the mandatory
  pre-authorization gate is
  `Caddy/tests/deployable-successor-policy.sh --authorization-ready`; it must
  reject an empty successor registry, execute both exact entrypoints, and
  require each registered marker exactly once from the entrypoint that owns it.
  The neutral
  registered regression filename must not contain an action identifier.
  Static inspection, direct helper calls, copied predecessor fixtures, emitted
  labels without entrypoint execution, and an outer `--self-test` that stops
  before its first transport boundary are not production-path coverage. Do not
  report or request authorization for an outer SHA-256 unless the
  `--authorization-ready` gate passes.
- Production-path coverage must follow the real generated data and command
  flow from the outer dispatch through every fallible pre-mutation boundary.
  It must build the payload, generate the exact remote path, invoke the real
  upload helper's prepare, accept, and disposition modes against isolated
  local state, construct the exact remote command and arguments without SSH,
  dispatch the transaction test, exercise every state-dependent transaction
  branch, and prove that an accepted branch reaches payload validation and a
  no-mutation sentinel at the mutation boundary. The coverage registry must
  identify `outer` or `transaction` ownership for every marker, and the outer
  test must leave mode-checked evidence of payload identity, remote path,
  prepare/accept/disposition calls, remote command arguments, transaction
  status, and zero mutation beneath an isolated caller-provided `/tmp`
  directory. Cover absent, exact, partial,
  extra, unsafe-metadata, symlink, malformed, and node-role states when they
  affect the successor. Reject any untested outer-to-helper grammar or argument
  boundary. Host and Debian runs are environments for this same logical
  contract, not independent coverage. Both must pass before authorization when
  Debian-sensitive behavior is in scope.
- Shell tooling must target Debian's default POSIX `awk`, not GNU `awk`.
  Interval quantifiers such as `{64}` and `{3,4}` are prohibited inside awk
  regular expressions because support varies across default awk
  implementations. Use an explicit `length()` comparison plus a portable
  character-class expression, or expand the expression without intervals.
  The always-run repository policy
  `Caddy/tests/portable-awk-policy.sh --check` scans every tracked Caddy shell
  entry point and rejects interval quantifiers in inline and multiline awk
  programs. Its regression must accept equivalent Bash regex intervals while
  rejecting both awk forms.
- Every tracked `Caddy/scripts/*.sh` and `Caddy/tests/*.sh` Bash entry point
  must be executable in both the working tree and Git index (`100755`). Local
  `core.fileMode=false` can conceal an index-mode defect, so never accept
  `test -x` alone. Run
  `Caddy/tests/executable-wrapper-policy-regression.sh`; it enumerates the
  tracked set and rejects both working-tree and index mode `0644`, including
  explicit negative controls.
- Keep workstation source ownership checks out of container integration
  commands. Regressions that need a runner's `--source-test` must invoke
  `Caddy/tests/run-source-test-in-context.sh --runner RUNNER`. The policy
  executes the source test only with `aaron:aaron:755` ownership on the
  workstation. In the validation container it accepts only the explicit
  `CADDY_VALIDATION_CONTAINER=1`, `/workspace/...`, `root:root:755`
  read-only bind-mount projection. Do not add ad hoc ownership exceptions.
- Give every decision gate a unique label. This includes mutation status,
  command status, ownership, service/VIP state used for acceptance, rollback,
  recovery, and the final decision. Ordinary observations may be grouped in a
  structured evidence record and need not become individual Boolean assertions.
  Never hide multiple fallible commands behind one success label.
- Production service acceptance must validate boot persistence as well as
  current activity. For Caddy HA, require `caddy.service`,
  `caddy-lsyncd.service`, `caddy-sync-reconcile.path`,
  `caddy-cert-expiry.timer`, `caddy-sync-health.timer`, and
  `caddy-pihole-web-health.timer` to be enabled and active. Require the static
  `caddy-pihole-web-health.service` worker to be independently accepted but
  never enabled directly. Require `caddy-api.service` to be masked and
  inactive; and require
  the distribution `lsyncd.service` to remain masked and inactive so that only
  `caddy-lsyncd.service` can run the managed configuration. The standard
  `emergency.service` and Caddy workers invoked by timers, paths, or
  `OnFailure` must remain static and must never be enabled directly. The
  managed lsyncd service is not healthy merely because systemd reports it
  active: acceptance must prove a positive stable `MainPID`, unchanged
  `NRestarts`, active/running state, successful unit result, a regular,
  nonempty, parseable `/run/caddy-lsyncd/status` diagnostic snapshot, and no
  new cursor-bounded transport or quarantine failure. Do not treat the status
  file's age or periodic modification-time advancement as a liveness
  heartbeat; live Action 30c disproved that contract while the managed process
  remained stable. Before restarting a synchronization publisher,
  inspect its current release and complete outbound candidates and require
  every candidate to be admissible under the node's normal or guarded
  emergency role. Never wake a stale or divergent outbound queue merely to
  refresh health state; retain or quarantine it under an explicit transaction
  boundary. Independently invoke and accept each timer's
  static worker before accepting the timer. The
  transactional reconciler exclusively owns validation, promotion, reload,
  and rollback, so the obsolete
  `caddy-validate-reload.path` and `.service` must remain absent. Enforce this
  source contract with
  `Caddy/tests/systemd-boot-persistence-policy.sh --check`.
- Durable notification acceptance requires
  `caddy-apprise-worker.path` and `caddy-apprise-worker.timer` enabled and
  active, while `caddy-apprise-worker.service` remains static. Keepalived and
  Caddy failure producers may only enqueue bounded local records; they must
  not own HTTP transport. Notification delivery success is never a VRRP,
  Caddy, lsyncd, reconciliation, or health acceptance input. Preserve queued
  and dead-letter records across rollback or uninstall unless an explicitly
  authorized disposition proves they are transaction-owned.
- A producer-side health transition is not durably enqueued until atomic local
  enqueueing succeeds. Persist a stable transition identity and pending state
  before enqueue, retry failed local enqueueing from the producer's subsequent
  timer runs, and acknowledge the transition only after enqueue success. The
  network delivery worker owns retries only after a valid queue record exists.
  Its time-window deduplication is not a substitute for producer-side crash
  recovery. A transition producer must use a stable idempotency identity so a
  crash after enqueue but before local acknowledgement cannot create a later
  duplicate. Notification state and delivery success remain outside VRRP and
  serving-health decisions.
- DNS readiness must retain the server, port, name, type, command status, and
  safe answer used by the decision. These may be one structured query record;
  they do not require a separate Boolean label for every field.
- Bound post-command journal evidence with a journal cursor captured before the
  command and `journalctl --after-cursor` afterward. Do not construct a
  `--since` timestamp and assume the target journalctl parser accepts that
  representation. If a timestamp boundary is unavoidable, production-path
  regression must exercise that exact representation against the target
  Debian journalctl version before live use.
- Define a versioned canonical transcript or structured schema at each
  cross-script producer boundary and test the real producer there once.
  Consumers validate the schema version, required records, uniqueness, order
  where semantically meaningful, and status. Do not replay the full producer
  from every consumer regression or duplicate its entire assertion inventory.
  Synthetic fixtures may test consumer rejection after the canonical producer
  contract itself has production-path coverage.
- Keep `Caddy/tests/transcript-contract-ratchet-policy-regression.sh` for
  historical visibility, but do not require an append-only deployment action
  to correct an unexecuted or workstation-only consumer. Historical runner
  exceptions remain immutable by exact path and hash.
- Treat temporary deployment staging filesystems such as `/run` and `/tmp` as
  potentially mounted `noexec`. Invoke every staged Bash artifact explicitly
  with `/bin/bash`; never execute it directly by pathname. A regression for a
  staged runner must exercise a non-executable-but-readable script fixture and
  prove that the production path still reaches it through `/bin/bash`.
- Every SSH transport that streams a Bash artifact on standard input must set
  the remote working directory explicitly before privilege escalation. Use the
  exact remote-command boundary `cd / && sudo -n /bin/bash -s --` unless the
  action has a separately documented and validated working-directory contract.
  The inspector's own `PWD` assertion is additional evidence, not a substitute
  for transport enforcement. Run
  `Caddy/tests/remote-streamed-bash-cwd-policy.sh --check FILE [FILE ...]` for
  every changed runner; pre-commit enforces the same rule and permits historical
  defects only through an exact immutable path-and-hash exception.
- Every SSH transport that streams a command or Bash artifact must preserve a
  local workstation evidence copy under `/tmp` during the original execution.
  Create a unique `0700` evidence directory, redirect stdout and stderr into
  distinct `0600` files, record the exact SSH exit status, and classify and
  emit bounded-safe content before evaluating acceptance. Retain the local
  files and report their path at handoff; an EXIT trap must not delete the only
  capture. A remote `/tmp` log created with `nohup` may supplement this contract
  only for a separately authorized long-running command; it never replaces the
  local capture and must not be introduced for synchronous transactional or
  read-only actions. Mark governed runners with
  `ssh-local-evidence-contract-v1` and enforce them with
  `Caddy/tests/ssh-stream-local-evidence-policy.sh --check FILE [FILE ...]`.
- Any staged artifact consumed by an unprivileged identity must be placed in a
  dedicated staging directory that is a direct child of an explicitly
  validated searchable runtime parent such as `/run`. Keep protected payloads,
  installers, archives, and secrets in a separate `root:root:0700` staging
  tree; never nest the unprivileged consumer's stage beneath that tree. If a
  direct-child layout is impossible, fail closed unless every ancestor is
  independently labeled and proven searchable under the exact runtime UID,
  primary GID, and cleared supplementary groups. Install only the intended
  consumer artifact into the searchable stage, require exact owner/group/mode,
  reject extra files and symlinks, and install cleanup handling before the
  first fallible operation after creating any stage. Production-path
  regression must construct the complete ancestor chain, execute readability
  and the real artifact entry point under the exact cleared-group identity,
  reject a root-only ancestor, and prove the protected payload remains
  unreadable. Static immediate-directory metadata is never sufficient.
- A generated validator that controls a live mutation must execute its
  safety-critical production decision path with both accepting and rejecting
  coverage. It may consume a versioned canonical producer fixture after the
  real producer contract has been tested centrally; it need not replay every
  upstream observation or assertion.
- Never rely on `set -e` or `set -E` to propagate a failure from a validator
  function. Bash disables errexit semantics when a function is evaluated by
  `if`, `!`, `&&`, or `||`, so a later successful command can overwrite an
  earlier failure. Every predicate, comparison, parser, and nested validator in
  a conditional validator must use an explicit `|| return`, a guarded `if`, or
  an equivalent explicit status return. Mark straight-line validator regions
  with `conditional-validator-explicit-failures-begin` and
  `conditional-validator-explicit-failures-end`, and enforce them with
  `Caddy/tests/conditional-validator-errexit-policy-regression.sh`. Every new
  validator regression must include an early-invalid/later-valid transcript and
  prove rejection, covering both false-positive and false-negative behavior.
  Any custom predicate or policy helper passed through `require_gate`, `if`,
  `!`, `&&`, or `||` must mark its assertion body even when it appears small;
  an unmarked helper is not an accepted validation boundary. When a fallible
  command and its explicit return span separate physical lines, mark the
  return line with `conditional-validator-requires-return` so the policy
  verifies the boundary instead of relying on visual review.
- Run `Caddy/tests/check-shell-readonly-local-collisions-v2.sh` and the
  conditional-validator policy for changed shell entry points. Their shared
  repository regressions own the generic negative dynamic-scope and
  early-invalid/later-valid fixtures; do not reproduce those fixtures inside
  every action-specific regression.
- A live transactional command whose stdout or stderr affects acceptance must
  capture both streams during that same execution. Before testing emptiness or
  content, emit independently labeled, bounded byte count, line count,
  SHA-256, and safe classification records. Metadata alone is not sufficient:
  after classification, emit bounded safe content between explicit begin/end
  labels, or retain it at a reported protected path with exact ownership, mode,
  and hash. Record empty streams explicitly. Suppress unsafe content and retain
  it only in a protected evidence path for separately authorized inspection.
  Never defer stream capture to a follow-on action, delete the only useful
  capture before its evidence outcome is secured, or print unclassified raw
  output. Classify executed historical actions in the lifecycle registries and
  exclude them from current-production policies; do not accumulate per-action
  hash exceptions in current checks. Require corrected or new actions to pass
  `Caddy/tests/transaction-output-evidence-policy-regression.sh`.
- Validate executable changes with the focused host tests and governing
  policies for the changed boundary. Add the focused Debian 12 Podman slice
  only when behavior depends on Debian packages, tools, system identities,
  permissions, mount projection, or runtime semantics. Skip the container for
  documentation, journal, manifest-only metadata, accepted-hash registry, and
  workstation-only transcript-consumer changes.
- Select routine Caddy validation through the versioned manifest
  `Caddy/tests/focused-validation.yaml` and
  `Caddy/tests/run-focused.sh`. Use `--profile NAME` for a current production
  boundary, `--action ID` only for intentional historical reconstruction, or
  `--changed --base REF` for fail-closed changed-path selection. Inspect the
  deterministic plan with `--explain` when reviewing scope. The runner must
  deduplicate tests and shared policies, retain its `0600` result summary
  beneath a reported `0700` `/tmp` directory, and start at most one
  network-disabled Debian container for a selected batch. The manifest may
  contain only tracked test paths and named policy identifiers; never place
  shell commands or copied SHA-256 identities in it. Enforce completeness,
  path safety, and lifecycle classification with
  `Caddy/tests/focused-validation-manifest-policy.sh --check`. Keep historical
  action selection in `Caddy/tests/historical-actions.yaml` and validate that
  opt-in index separately with
  `Caddy/tests/historical-action-index-policy.sh --check`.
- Treat `Caddy/tests/test-lifecycle.tsv` as the complete lifecycle registry for
  every tracked entry beneath `Caddy/tests/`. Current profiles select only
  neutral `production-current` regressions; action-named tests, `run.sh`, and
  `integration.sh` remain `historical-preserved` opt-in reconstruction
  artifacts. A neutral current regression must execute the current production
  entry point directly and may not delegate its behavioral decision to an
  action-specific historical regression. Historical fixtures may provide
  provenance or rejection inputs, but they cannot substitute for exercising
  the current entry point. Enforce
  inventory completeness and classification with the always-run
  `Caddy/tests/test-lifecycle-policy.sh --check` hook.
- The generic `install-caddy-ha.sh` Caddy component is bootstrap-only. It must
  fail closed when `/etc/caddy/current` already exists and must never modify an
  accepted production release or selection. Production release changes use the
  current protocol-v2 publisher, receiver, finalizer, and reconciler contract.
- Treat `Caddy/manifests/template-lifecycle.tsv` as the canonical lifecycle
  registry for `Caddy/templates/`, with the human-readable disposition in
  `Caddy/templates/README.md`. A retained template is not deployable unless its
  registry entry is `production-current` and `deployable=yes`. Preserve
  historical template paths and bytes for executed-action provenance, but
  never consume historical, rejected, superseded, or deferred templates from
  production inventory or installers. Keepalived configuration is owned only
  by `homelab-dns/Keepalived/configs/`; the canonical lsyncd sources are the
  node-specific files in `Caddy/configs/lsyncd/`. Historical renderer output
  requires its explicit offline-reconstruction flag. Enforce this boundary
  with the always-run `Caddy/tests/template-lifecycle-policy.sh --check` hook.
- Treat `Caddy/templates/caddy-ha.env-v2.in` as the only production Caddy
  environment template. Its contract is exactly `NODE_FQDN`, `NODE_IPV4`, and
  `NODE_IPV6`, once each and in that order. Keep Keepalived ownership,
  priority, peer transport, synchronization role, and interface data out of
  `/etc/default/caddy-ha`; those values belong to their authoritative
  Keepalived, lsyncd, publisher, or reconciliation sources. Preserve
  `Caddy/templates/caddy-ha.env.in` only as historical provenance. Enforce the
  production contract with the always-run
  `Caddy/tests/caddy-environment-v2-policy.sh --check` hook.
- Treat `Caddy/manifests/script-lifecycle.tsv` and
  `Caddy/manifests/systemd-lifecycle.tsv` as the only reusable installer
  allowlists for scripts and systemd files. Every file in those source trees
  must have exactly one lifecycle entry. Only `production-current` entries
  with `node-installable=yes` may be installed; never infer current status from
  a generic filename or copy an entire source tree. Keep deferred Munin,
  rejected backend units, workstation tools, historical actions, and
  superseded implementations out of the default installer. Enforce this with
  the always-run `Caddy/tests/deployment-lifecycle-policy.sh --check` hook.
- Do not run the complete preserved historical host/Podman suite as a live
  deployment gate. Final acceptance uses the current production-path suite,
  applicable shared policies, and current live evidence. Preserve historical
  tests and evidence for the post-deployment streamlining review, but do not
  let stale historical hashes block current work. `Caddy/tests/run.sh` and
  `Caddy/tests/integration.sh` are explicit opt-in historical reconstruction
  entrypoints and must not be called by a current-production profile.
- Preserve backward compatibility only when it is an explicit requirement;
  intentional migrations and replacements may deliberately break obsolete
  internal contracts.
