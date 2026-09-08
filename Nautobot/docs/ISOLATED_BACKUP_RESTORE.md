# Isolated pre-data backup and restore verification

## Status and purpose

This is the reviewed successor contract after the Nautobot Restic repository
has been initialized and accepted. It is not an active operation and grants no
authorization.

The verification uses a deterministic canary beneath an operation-owned source
directory on `j2-svpi4mf`. It proves upload, full repository data checking,
exact-snapshot selection, and restoration into a new empty directory before
Nautobot data is entrusted to the storage path. It does not prove recovery of
PostgreSQL, media, application configuration, or a running Nautobot instance.

## Required predecessor state

Do not activate this contract until a terminal repository-initialization record
provides the exact repository ID, format version, initializer identity, and
accepted secret references. The independent repository-password recovery
location must remain confirmed.

The future operation must also retain the accepted Backblaze B2 S3 transport
identity from tag `backblaze-b2-s3-compatibility-v1-completed` and use the
shared Restic procedures.

## Dataset and workflow

Create unique source and restore roots beneath
`/var/lib/nautobot/backup-restore-tests/`, owned by the `nautobot` execution
user with directory mode `0700` and file mode `0600`. Require the source and
restore roots to reside on `/dev/sda2`.

The deterministic file is `predata/canary.txt`, containing exactly:

```text
nautobot isolated backup restore verification v1
```

Its SHA-256 is
`0b8fefbdc586f053d6e69ee230d119d668e2dc7f4739fe61a334227d61142de2`.

The operation must:

1. verify the exact repository ID, Restic version, execution identity, and
   secret references;
2. record source-tree hashes and the pre-backup snapshot-ID set as JSON;
3. create one backup tagged `nautobot-predata-canary-v1`;
4. record the post-backup snapshot-ID set and require exactly one new matching
   full snapshot ID;
5. run `restic check --read-data`;
6. restore that exact snapshot ID into a new empty owned directory;
7. compare the restored tree with independently defined paths, modes, and
   hashes; and
8. inspect cursor-bounded focused storage events and preserve bounded sanitized
   evidence.

Do not select `latest`. Do not restore over the source or a live path. Do not
automatically forget, prune, repair, unlock, delete, or clean up the remote
snapshot. Retain it and the evidence for review after any post-upload failure.

## Acceptance boundary

Acceptance proves only the pre-data storage gate. The Nautobot pilot must later
perform an isolated restore of the real PostgreSQL dump, media, configuration,
image and dependency manifests, Quadlets, and migration state before platform
or authority acceptance.
