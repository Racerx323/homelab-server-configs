# Repository Agent Rules

This file contains repository-specific execution and validation rules. It does
not describe services that are not configured in this repository. GitHub
automation is authoritative only when represented by a tracked file under
`.github/`.

## CodeRabbit reviews

CodeRabbit requires external network access. Run all `coderabbit review` commands with network escalation (`sandbox_permissions: "require_escalated"`). Request the reusable approval prefix `["coderabbit", "review"]`.

Do not wait for a sandboxed review to time out. If it stalls while connecting, rerun it immediately with network escalation.

---

## Security considerations

- **Least Privilege**: Each automated agent should operate with the minimum permissions necessary to perform its tasks. Review and adjust permissions regularly.
- **Secrets Management**: Sensitive information such as API keys and tokens should be stored securely using GitHub Secrets and not hard-coded in workflows.
- **Monitoring and Alerts**: Set up monitoring for automated workflows to detect and respond to any unusual activity or failures.

---

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
- `Caddy/tests/run.sh` is a Podman wrapper, not a host-only test command. Run it
  outside the filesystem sandbox on its first attempt with the narrowest
  applicable scoped escalation because its final integration phase requires
  the rootless runtime under `/run/user`.
- Run focused Debian validation only through
  `Caddy/tests/run-focused-container.sh Caddy/tests/TEST_SCRIPT`. The wrapper
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
- After moving files or changing imports, check that all files or imports adhere to the project's coding standards.
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
  executed live artifact.
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
  `caddy-cert-expiry.timer`, and `caddy-sync-health.timer` to be enabled and
  active; require `caddy-api.service` to be masked and inactive; and require
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
  output. Preserve historical deficient actions only behind an exact immutable
  hash exception, and require corrected or new actions to pass
  `Caddy/tests/transaction-output-evidence-policy-regression.sh`.
- Validate executable changes with the focused host tests and governing
  policies for the changed boundary. Add the focused Debian 12 Podman slice
  only when behavior depends on Debian packages, tools, system identities,
  permissions, mount projection, or runtime semantics. Skip the container for
  documentation, journal, manifest-only metadata, accepted-hash registry, and
  workstation-only transcript-consumer changes.
- Do not run the complete preserved historical host/Podman suite as a live
  deployment gate. Final acceptance uses the current production-path suite,
  applicable shared policies, and current live evidence. Preserve historical
  tests and evidence for the post-deployment streamlining review, but do not
  let stale historical hashes block the current deployment.
- Test edge cases and error handling in proportion to the changed risk.
- Document any new features or changes to existing functionality.
- Preserve backward compatibility only when it is an explicit requirement;
  intentional migrations and replacements may deliberately break obsolete
  internal contracts.
- Update any relevant documentation or comments in the code.

---

## PR instructions

- **Title format**: [&lt;project_name&gt;] &lt;Title&gt;
- **Description**: Provide a clear and concise description of the changes made in the PR.
- **Related Issues**: Link any related issues or pull requests.
- **Checklist**:
  - [ ] Code is well-tested
  - [ ] Documentation has been updated
  - [ ] Changes have been reviewed by at least one other person
