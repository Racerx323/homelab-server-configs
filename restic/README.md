# Restic

This directory owns reusable Restic configuration, policy, validation,
scripts, templates, schemas, and sanitized metadata for
`homelab-server-configs`.

Read [docs/RESTIC_ARCHITECTURE.md](docs/RESTIC_ARCHITECTURE.md) before adding a
consumer or live operation. Read [AGENTS.md](AGENTS.md) before changing files
in this directory.

## Ownership

Restic owns the shared backup transport and recovery rules. Each consumer owns
its backup contents, schedule, operation manifest, acceptance decision, and
history. For example, Nautobot keeps its active operation in
`Nautobot/manifests/operation.yaml` and references the shared Restic
architecture.

Backblaze stores encrypted repository data. The approved secrets system stores
repository passwords and application-key values. Git stores reviewed
non-secret definitions and sanitized evidence manifests.

## Layout

The current files establish policy before implementation:

- `AGENTS.md`: scoped editing and execution rules;
- `docs/RESTIC_ARCHITECTURE.md`: shared architecture authority; and
- `.gitignore`: local cache, credential, runtime-data, and evidence exclusions.

Add `configs/`, `scripts/`, `schemas/`, `manifests/`, or consumer-specific
paths only when reviewed content exists.

## Restic configuration boundary

Restic accepts the repository through `RESTIC_REPOSITORY` or
`RESTIC_REPOSITORY_FILE`. Supply the repository password through
`RESTIC_PASSWORD_FILE` or an approved password command. S3-compatible Backblaze
B2 access uses `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` at execution
time. Store none of those secret values in this repository.

Set `RESTIC_CACHE_DIR` to an owned path outside Git for automated jobs. Restic
otherwise follows the user's cache directory and keeps persistent cache data.

No live Restic configuration or executable backup path exists in this
directory yet.
