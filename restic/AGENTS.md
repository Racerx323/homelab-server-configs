# Restic component rules

These rules apply beneath `restic/` and refine the repository rules in
`../AGENTS.md`.

## Architecture authority

- `docs/RESTIC_ARCHITECTURE.md` governs reusable Restic repository,
  credential, backup, restore, retention, evidence, and recovery boundaries.
- Consumer components own their datasets, schedules, operation state,
  acceptance decisions, and terminal history. Restic files must not duplicate
  those records.
- A consumer's governing plan wins for application-specific backup content and
  recovery acceptance. Stop and request an architecture decision when that
  plan conflicts with the Restic architecture.

## Repository contents

- Keep reviewed non-secret configuration, schemas, scripts, templates,
  sanitized repository identities, and operator documentation under `restic/`.
- Add a consumer-specific path only when it contains reviewed configuration.
  Do not create placeholder trees.
- Keep repository passwords, application keys, credential files, raw backup
  data, Restic caches, locks, and raw operation evidence outside Git.
- Store no secret value in command arguments, bundle hashes, logs, evidence,
  examples, or test fixtures.

## Execution boundaries

- Treat repository initialization, backup upload, restore, snapshot deletion,
  retention, prune, unlock, check repair, and repository repair as separate
  mutation classes. Each live operation must authorize its exact classes.
- Select restore inputs by full snapshot ID. Do not use `latest` for an
  acceptance or recovery operation.
- Restore only into a new, empty, mode-checked directory unless a separately
  authorized recovery operation names the live target and rollback boundary.
- Keep `forget`, `prune`, `repair`, and destructive cleanup out of backup or
  restore verification paths.
- Capture secrets through protected files or an approved secret provider.
  Disable command tracing before secret resolution and bound all output.

## Validation

- Validate configuration syntax, shell policy, secret absence, deterministic
  fixture hashes, snapshot selection, restore-path containment, and cleanup
  ownership for each changed implementation.
- Test failure after upload and after restore. Retain the snapshot and evidence
  for operator review unless a separate cleanup action has authorization.
- Use the installed Restic version on the target as the final CLI authority
  during an authorized preflight.
