# Restic architecture

## Scope

This document governs reusable Restic configuration and execution within
`homelab-server-configs`. Consumer plans define application datasets,
schedules, retention requirements, recovery-point objectives, and acceptance
criteria.

The first consumer is Nautobot on `j2-svpi4mf`. Its deployment plan remains the
architecture authority for Nautobot data and recovery acceptance.

## Ownership

The `restic/` component owns:

- repository URL construction and non-secret identity records;
- credential-injection contracts;
- safe backup, check, snapshot-selection, and restore primitives;
- retention and destructive-command boundaries; and
- reusable schemas, validation, and operator procedures.

Each consumer owns its source paths, database export method, exclusions,
schedule, retention values, operation state, accepted-live state, and terminal
history. The `backblaze-b2/` component owns buckets, application-key policy,
provider lifecycle, and cloud-side acceptance. The approved secrets system
owns credential values and repository password recovery material. Backblaze
stores the remote encrypted objects.

## Repository model

Consume one accepted private Backblaze B2 bucket per approved trust and
provider-lifecycle boundary. The `backblaze-b2/` component creates and accepts
that bucket before Restic repository work begins. Access it through
Backblaze's S3-compatible endpoint with Restic's S3 backend:

```text
s3:https://ENDPOINT/BUCKET/PREFIX
```

Record the exact endpoint, bucket, optional prefix, Restic repository ID, and
initialization owner before a backup operation becomes authorization-ready.
Reject an unaccepted B2 identity. Use the B2-owned, bucket-scoped application
key and its reviewed list, read, write, and delete capabilities.

Repository initialization requires its own operation. A backup or restore
verification must reject an unknown or uninitialized repository and must not
initialize it as a side effect.

## Credentials and local state

Use protected files or an approved secret-provider command for the Restic
repository password. Inject S3-compatible credentials at execution time as
`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. Disable shell tracing before
credential resolution. Evidence may record secret reference names and whether
resolution succeeded; it must not record values.

Set `RESTIC_CACHE_DIR` to a consumer-owned location outside Git. Treat cache
contents, locks, temporary files, raw backup data, and raw evidence as runtime
state. Keep modes at `0700` for protected directories and `0600` for protected
files unless Restic requires a narrower owner-specific setting.

## Backup contract

A reviewed backup operation must:

1. prove the repository, Restic version, execution identity, source mount, and
   secret references before writing data;
2. capture the pre-backup snapshot IDs with `restic snapshots --json`;
3. back up the approved source with an operation-specific tag;
4. capture the post-backup snapshot IDs and require one new snapshot matching
   the approved host, source path, and tag; and
5. record the full new snapshot ID and sanitized command status.

The operation must derive the snapshot ID from the before-and-after set
difference. It must not restore `latest` or select a snapshot from display
order.

## Integrity and restore contract

Run `restic check --read-data` when the consumer requires full repository data
verification. A partial scheduled check may use a reviewed
`--read-data-subset` policy, but it cannot satisfy a full-check acceptance
gate.

Restore the full selected snapshot ID into a new, empty, mode-checked directory
outside each live source path. Compare the restored tree with expected paths,
sizes, modes, and content hashes derived from the reviewed source definition.
Capture filesystem or service errors from a cursor recorded before the
workload.

A pre-data canary proves repository access, upload, integrity checking, and the
isolated restore path. It does not prove that a PostgreSQL dump, application
media, configuration, or migration state can recover a running application.
Each consumer must complete its full recovery test before accepting recovery
or authority migration.

## Failure and cleanup

Before upload, cleanup may remove only a test directory whose path, owner,
mode, type, and operation marker all match the active operation. After upload,
retain the snapshot and bounded evidence when backup identification, integrity
checking, restore, or comparison fails.

Do not run `forget`, `prune`, `repair`, `unlock`, repository deletion, or remote
snapshot cleanup unless a separate authorization names the repository,
snapshot IDs, recovery boundary, and evidence requirements. Never restore over
a live source as part of verification.

## Evidence and acceptance

Keep raw output in a bounded protected directory outside Git. A sanitized
terminal manifest may record repository identity without credentials, Restic
version, snapshot ID, source and restored tree hashes, check result, restore
result, mutation status, cleanup status, raw-evidence hashes, and the consumer's
decision.

Successful command status alone does not prove recovery. The consumer accepts
the operation only after it verifies repository identity, snapshot identity,
full required integrity checks, restored bytes, path isolation, secret absence,
and workload-scoped error logs.

## References

- [Preparing a new repository](https://github.com/restic/restic/blob/master/doc/030_preparing_a_new_repo.md)
- [Scripting with Restic](https://github.com/restic/restic/blob/master/doc/075_scripting.md)
- [Working with repositories](https://github.com/restic/restic/blob/master/doc/045_working_with_repos.md)
- [Restoring from backup](https://github.com/restic/restic/blob/master/doc/050_restore.rst)
