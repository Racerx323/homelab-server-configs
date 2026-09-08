# Restic

This directory owns reusable Restic configuration, policy, validation,
scripts, templates, schemas, and sanitized metadata for
`homelab-server-configs`.

Read [docs/RESTIC_ARCHITECTURE.md](docs/RESTIC_ARCHITECTURE.md) before adding a
consumer or live operation. Use
[docs/READ_ONLY_PREFLIGHT.md](docs/READ_ONLY_PREFLIGHT.md) to resolve and verify
an existing repository without creating cache or lock objects. Read
[AGENTS.md](AGENTS.md) before changing files in this directory.

The [Backblaze B2 component](../backblaze-b2/README.md) has accepted the
provider bucket, application-key scope, and S3 object transaction for Restic
transport. Repository initialization remains a separate, unimplemented
operation. The reviewed initialization boundary is documented in
[docs/REPOSITORY_INITIALIZATION.md](docs/REPOSITORY_INITIALIZATION.md). Its
active consumer definition records the confirmed password and independent
recovery references plus a passed repository-absence preflight. It remains
unready until the host baseline is accepted, the initialization implementation
is reviewed and checkpointed, a final bundle is calculated, and explicit live
authorization is granted.

## Ownership

Restic owns the shared backup transport and recovery rules. Each consumer owns
its backup contents, schedule, operation manifest, acceptance decision, and
history. For example, Nautobot keeps its active operation in
`Nautobot/manifests/operation.yaml` and references the shared Restic
architecture.

The Backblaze B2 component owns bucket and application-key configuration. The
approved secrets system stores repository passwords and application-key
values. Git stores reviewed non-secret definitions and sanitized evidence
manifests.

## Layout

The current files establish policy and the first repository-access contract:

- `AGENTS.md`: scoped editing and execution rules;
- `docs/RESTIC_ARCHITECTURE.md`: shared architecture authority;
- `docs/READ_ONLY_PREFLIGHT.md`: lock-free, cache-free repository inspection;
- `docs/REPOSITORY_INITIALIZATION.md`: one-time initialization and failure
  boundaries; and
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
