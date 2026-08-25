# Nautobot project rules

These rules apply beneath `Nautobot/` and refine the repository rules in
`../AGENTS.md`.

## Architecture authority

- `docs/NAUTOBOT_DEPLOYMENT_PLAN.md` is the sole source of architecture truth
  for the Nautobot deployment on `j2-svpi4mf`.
- Keep the plan limited to accepted architecture, ownership boundaries,
  constraints, implementation stages, risks, validation criteria, and approved
  architecture deviations with rationale.
- Do not store individual task outcomes, operation identifiers, authorization
  hashes, live evidence, current deployment status, or resume points in the
  plan.
- If implementation reveals an architectural conflict, stop, document the
  proposed deviation, and obtain approval before changing the plan or
  continuing along the new path.

## Project records

Use these ownership boundaries when the corresponding artifacts are created:

- `docs/OPERATIONS.md` owns repeatable operator procedures, maintenance,
  recovery, and rollback instructions.
- `HISTORY.md` owns a concise terminal-operation index with result, annotated
  tag, commit, and accepted-state identity. It is not a prose task journal.
- `manifests/desired-state.yaml` owns non-secret intended versions, image
  digests, services, ports, limits, and installable artifact identities.
- `manifests/accepted-live-state.yaml` owns the latest accepted non-secret
  semantic and deployed identity.
- `manifests/operation.yaml` owns at most one pending operation and is neutral
  while the deployment stream is clean.
- Sanitized terminal definitions and evidence manifests are preserved by
  annotated Git tags; raw evidence remains outside Git.

Do not create placeholder files merely to satisfy this layout. Add each file
when its owning implementation or operation contract is reviewed.

## Deployment model

- Use Ansible as the primary host-configuration and orchestration engine before
  Semaphore is accepted. Keep roles and playbooks idempotent and bounded to the
  stage they implement.
- Use rootless Podman and user Quadlets for the application runtime. Do not add
  Docker, a Docker daemon, or rootful application containers.
- Prefer one reusable playbook path plus a thin launcher that verifies the
  deployment bundle, prepares protected evidence storage, and invokes the
  reviewed playbook. Do not reproduce orchestration in parallel shell
  transactions or attempt-numbered runners.
- A custom transaction is justified only for a safety boundary that Ansible,
  Quadlets, systemd, or an owning repository's existing deployment path cannot
  express accurately.
- Resolve and pin ARM64 image digests and dependency identities before defining
  a live pilot operation. Mutable image tags are not deployable inputs.

## Operation lifecycle

1. Compare the intended stage with the architecture plan and ownership table.
2. Collect a bounded read-only baseline and compare it with explicit
   preconditions. Do not mutate during baseline collection.
3. Define one operation with the plan revision, target, stage, source commit,
   exact non-secret inputs, ordered mutations, acceptance checks, and rollback
   boundary.
4. Validate rendering, syntax, target architecture, idempotence, secret
   absence, failure handling, and recovery-sensitive behavior locally where
   possible.
5. Build one SHA-256 deployment-bundle identity over the operation
   specification, desired-state manifest, playbooks, templates, validators,
   and other non-secret execution inputs.
6. Request authorization for that bundle, exact command, target, and one live
   stage. Do not combine later stages into the authorization.
7. Execute the reviewed reusable path, retain bounded decision evidence, and
   accept, roll back, or report manual intervention explicitly.
8. Reconcile accepted-live state only after every stage acceptance criterion
   passes. Preserve the terminal definition and sanitized evidence manifest in
   an annotated tag, add one concise history entry, and return operation state
   to clean.

Fix an unexecuted reusable implementation in place and recompute its bundle.
Do not create a successor operation merely to correct an orchestration mistake
that occurred before live execution. After a mutation-bearing execution, any
new live behavior requires a separately defined and authorized operation.

## Stage and ownership boundaries

- Keep repository implementation definition-only: no host contact, package
  changes, container startup, secrets creation, DNS changes, network changes,
  Caddy publication, or source-of-truth migration.
- Host baseline and Nautobot runtime changes target only `j2-svpi4mf` and use
  the Nautobot operation lifecycle.
- NetworkManager identity and UniFi changes are proposed and executed through
  `homelab-network` under its authorization and rollback process.
- Host and application DNS changes are proposed and executed through
  `homelab-dns` under its HA validation and authorization process.
- Caddy onboarding uses `Caddy/AGENTS.md`, the application-onboarding contract,
  and protocol-v2 lifecycle. Do not reproduce or bypass that lifecycle in the
  Nautobot project.
- Authority migration is one data domain per operation. Require an exact
  repository comparison, resolution of every difference, deterministic export,
  approved Nautobot revision, and explicit ownership update.
- Inventory events, webhooks, Jobs, and Semaphore schedules may produce checks
  or proposals. They must not directly publish or mutate Caddy, DNS, networking,
  HA nodes, or another repository's production state.

## Evidence and acceptance

- Evidence must distinguish preflight, mutation, convergence, service state,
  rollback, final acceptance, and residue. Record expected and observed values,
  command status, and raw-evidence hashes without secret values.
- Use protected bounded directories beneath `/tmp` for workstation and remote
  operation evidence. Long-running remote work writes node-local evidence
  before bounded readback.
- Capture a systemd journal cursor before service mutation and query only the
  cursor-bounded journal afterward.
- A successful Ansible result, image build, container start, or migration is
  not platform acceptance by itself. Apply every relevant host, network,
  application, data, backup, restore, and soak criterion from the architecture
  plan.
- Prove rootless services survive logout and reboot, private services remain
  unexposed, both permanent backend address families work, secrets remain out
  of Git and evidence, and backup plus isolated restore succeeds before
  authority migration.
- Treat Ansible check mode as supplementary evidence; do not rely on it for
  commands, service transitions, database migrations, or recovery behavior it
  cannot faithfully simulate.

## Validation expectations

- Validate YAML, Ansible syntax, rendered Quadlets, systemd dependencies,
  Containerfile builds, ARM64 image identity, configuration schemas, and secret
  scanning for the files changed by the task.
- Test playbook idempotence in a disposable representative environment when
  practical. Run authoritative rootless Podman, user-systemd, networking,
  storage, backup, and restore checks on `j2-svpi4mf` only during the separately
  authorized live stage.
- Test the real launcher and playbook path for material production decisions.
  Do not create a Caddy-style HA simulator, protocol-v2 transport, standby
  sequence, VIP continuity sampler, or successor-coverage schema for the
  single-host Nautobot deployment.
