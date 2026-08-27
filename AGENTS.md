# Repository rules

These rules apply across `homelab-server-configs`. A component may add a
scoped `AGENTS.md` that refines its own architecture, deployment, validation,
and history contracts. Component rules must preserve the authorization,
ownership, evidence, and safety boundaries below.

## Architecture and records

- Each deployable component names one governing architecture document. Treat
  that document as the source of truth for accepted architecture, constraints,
  ownership, stages, and acceptance criteria.
- Change a governing architecture document only for an approved architecture
  decision or deviation. Record the rationale, but do not turn the document
  into an operation log, task transcript, evidence store, or current-state
  ledger.
- Keep desired state, accepted live identities, active operation data,
  terminal outcomes, and operator procedures in component-owned manifests,
  history, operation specifications, and operations documentation.
- Do not claim accepted live state until the component's live acceptance
  checks pass. A repository definition or successful local test is not a live
  deployment result.

## Ownership boundaries

- A component may propose changes owned by another repository or component,
  but it must not silently assume authority over them.
- Keepalived, Pi-hole, Unbound, and authoritative DNS sources belong to
  `homelab-dns`. Network-controller sources belong to `homelab-network`.
  Caddy configuration and its release lifecycle belong to `Caddy/`.
  Backblaze B2 bucket, application-key policy, and cloud lifecycle sources
  belong to `backblaze-b2/`.
- Cross-owner changes use the owning project's validation, authorization,
  execution, acceptance, rollback, and history process.
- Do not make inventory events, webhooks, schedules, or generic installers
  directly mutate DNS, networking, Caddy, HA ownership, or another existing
  production deployment.

## Repository state and history

- Keep the main branch limited to current production artifacts, reusable
  automation, neutral validation, and approved future definitions.
- Keep at most one active live operation per component deployment stream.
  Do not create a second pending operation while one is defined or awaiting
  terminal archival.
- Fix reusable automation, unexecuted definitions, tests, and fixtures in
  place. Do not copy them into action-numbered or attempt-numbered successors.
- Store an operation identifier only in operation state, component history,
  commits, and tags. Do not put individual operation identifiers or outcomes
  in a governing architecture document.
- Preserve the exact terminal operation definition and sanitized evidence
  manifest in an annotated, pushed Git tag before removing consumed operation
  data from the main branch. Record that boundary in the component's history.
- Keep raw or sensitive evidence outside Git. A committed evidence manifest
  may contain sanitized decisions and hashes of bounded external evidence.

## Definition and authorization

- Repository edits, operation definitions, focused tests, formatters, and
  policy checks need no deployment authorization.
- A definition-only task must not contact a live target unless the user has
  explicitly requested or authorized a read-only inspection.
- Read-only inspection does not authorize mutation. Report material drift and
  re-evaluate the operation before requesting live authorization.
- Require scoped authorization for every live stage that can install, remove,
  transfer, publish, restart, reload, fail over, migrate, or otherwise mutate
  production state.
- Bind live authorization to one exact SHA-256 deployment bundle containing
  the operation specification and every non-secret input used by the execution
  path. State the exact command, targets, mutation boundary, acceptance checks,
  rollback boundary, and later stages that remain unauthorized.
- Secrets are external inputs. Identify their references and required
  properties without placing their values in Git, hashes, logs, or evidence.

## Execution and evidence

- Prefer idempotent, declarative automation. Add a custom transaction or outer
  runner only when it owns a real safety boundary that the chosen automation
  engine cannot express clearly.
- Put the exact preflight, mutation, convergence, postcondition, rollback, and
  residue checks beside the execution path that relies on them.
- Derive expected and observed values independently. Labels printed by the
  execution path are summaries, not evidence by themselves.
- Exercise the real producer and execution path in tests when its behavior is
  material. Do not fabricate command, transport, mutation, rollback,
  acceptance, or success results.
- Keep evidence proportional to decisions. Give mutation status, convergence,
  rollback, accepted state, and residue distinct records; group ordinary
  observations instead of emitting one record per assertion.
- Bound captured output, reject secrets and unsafe control data, and use exact,
  mode-checked temporary paths. Clean up only paths whose ownership and scope
  the operation has proved.
- A pre-mutation failure performs cleanup only. After mutation, either prove
  acceptance, prove rollback in reverse order, or stop with an explicit
  manual-intervention result.

## Validation

- Run the smallest test set that covers the changed behavior and its safety
  boundaries. Documentation and manifest metadata normally need structural
  checks rather than new behavioral suites.
- Run repository validation commands that invoke Ansible through
  `tests/repository/run-with-ansible-local-temp.sh`. The helper owns only a
  unique, protected controller-side temporary directory; it must not add
  inventory, transport, privilege, orchestration, or deployment behavior.
- Add a neutral regression when executable behavior or a durable safety
  boundary changes. Current tests must exercise current entrypoints, not
  archived operation implementations.
- Treat local checks as partial when they cannot exercise the authoritative
  parser, runtime, target architecture, or service manager. Record the live
  acceptance check that closes each remaining gap.
- Use Podman for container builds and tests. Do not add Docker-specific
  deployment paths or require a Docker daemon.

## Shell and SSH safety

- Invoke Bash entrypoints with `/bin/bash`; do not rely only on executable-bit
  dispatch.
- Do not reuse a script-level readonly variable name as a function-local name.
  Bash dynamic scope can reject the local declaration.
- Use Debian POSIX `awk`; avoid interval quantifiers in awk regular
  expressions. Do not consume a multi-file `grep -c` result as one scalar.
- Never send a multi-command program through `ssh ... /bin/bash -c ...` or
  `ssh ... sudo /bin/bash -c ...`. Stream it on standard input through
  `ssh HOST 'cd / && sudo -n /bin/bash -s -- ARG...' <PROGRAM`. A deliberately
  unprivileged program may omit `sudo -n` but must retain the other boundaries.
- Capture SSH stdout, stderr, and status separately beneath a protected
  temporary directory. Bound and sanitize every captured stream.
