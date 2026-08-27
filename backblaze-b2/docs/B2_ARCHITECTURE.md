# Backblaze B2 architecture

## Scope

This document governs Backblaze B2 account integration, bucket configuration,
application-key policy, provider lifecycle, evidence, and recovery boundaries
within `homelab-server-configs`.

The first consumer is the future Restic repository for Nautobot on
`j2-svpi4mf`. B2 configuration must pass its own acceptance before Restic
initializes or reads a repository.

## Ownership

The `backblaze-b2/` component owns:

- bucket names, IDs, regions, endpoints, and access type;
- server-side encryption and Object Lock decisions;
- provider lifecycle rules;
- application-key names, scopes, capabilities, expiration, and rotation; and
- B2 control-plane operations and sanitized evidence.

Restic owns repository URL construction, repository initialization, encrypted
repository format, snapshots, checks, retention execution, and restores. The
Nautobot component owns its data and recovery acceptance. The approved secrets
system owns credential values.

## Bucket model

Create one private bucket for each approved trust and provider-lifecycle
boundary. The Nautobot Restic consumer starts with a dedicated bucket and an
empty repository prefix. A later consumer must receive its own bucket unless
an architecture review proves that it shares the same access and lifecycle
boundary.

Record the globally unique bucket name, bucket ID, region, and exact
S3-compatible endpoint. Backblaze endpoints use HTTPS and the format
`https://s3.<region>.backblazeb2.com`.

Enable Backblaze-managed server-side encryption unless an approved operation
records a reason to omit it. Restic still provides the backup's primary
client-side encryption. Keep the bucket private.

## Object Lock and lifecycle

Keep Object Lock disabled for the initial Restic repository. Object Lock can
prevent Restic prune and cleanup operations from deleting objects. Add
immutability only after a recovery design defines retention mode, duration,
key capabilities, failure handling, storage growth, and restore tests.

Configure the bucket lifecycle as **Keep only the last version of the file**.
Restic's S3 backend hides obsolete objects; Backblaze retains hidden versions
by default. This lifecycle removes hidden prior versions after Backblaze's
delay without deleting the current objects that form the Restic repository.

Do not add an age-based rule that deletes current objects. Restic owns snapshot
retention and pruning. B2 lifecycle owns removal of hidden object versions
created by S3-compatible deletes.

## Application-key model

Create a dedicated application key for the Nautobot Restic bucket. Restrict it
to the exact bucket and repository prefix. Grant only the capabilities needed
to list, read, write, and delete repository objects. Exclude bucket creation,
bucket deletion, lifecycle administration, replication, Object Lock changes,
legal-hold changes, and governance bypass.

Backblaze requires `listAllBucketNames` for S3 `List Buckets` compatibility
with a bucket-restricted key. Enable it for this integration and record that it
reveals bucket names and IDs, not bucket contents. Verify the resulting key
capabilities after creation instead of relying on the web-console label.

Use the application key ID as `AWS_ACCESS_KEY_ID` and the application key as
`AWS_SECRET_ACCESS_KEY`. Backblaze displays the application key value once.
Store both values in the approved secrets system before closing the result
panel. Do not use the master application key.

## Mutation boundaries

Define separate, authorized operations for:

- account billing, caps, alerts, or security settings;
- bucket creation, access, encryption, Object Lock, or lifecycle changes;
- application-key creation, replacement, expiration, or revocation; and
- bucket, object-version, or provider-side data deletion.

A B2 acceptance operation may read back bucket and key metadata. It must not
initialize a Restic repository. Restic initialization requires its own
hash-bound operation after B2 acceptance.

## Evidence and acceptance

Keep raw provider output outside Git. A sanitized B2 manifest may record:

- bucket name, ID, region, endpoint, access type, and creation owner;
- encryption, Object Lock, and lifecycle state;
- application-key name, bucket and prefix scope, capability names, and
  expiration policy;
- secret reference names and confirmation that values were stored; and
- readback status, evidence hashes, and the acceptance decision.

Do not record account IDs, application-key IDs or values, object listings,
billing details, or unrelated bucket names.

Accept the B2 configuration only after provider readback proves the exact
private bucket, endpoint, encryption state, disabled Object Lock, required
lifecycle, key scope, and capability set. Confirm that the credential values
exist in the approved secrets system without printing them.

## References

- [Create and manage buckets](https://www.backblaze.com/docs/cloud-storage-create-and-manage-buckets)
- [S3-compatible endpoints](https://www.backblaze.com/docs/cloud-storage-call-the-s3-compatible-api)
- [S3-compatible application keys](https://www.backblaze.com/docs/cloud-storage-s3-compatible-app-keys)
- [Application-key capabilities](https://www.backblaze.com/docs/cloud-storage-application-key-capabilities)
- [Object Lock](https://www.backblaze.com/docs/cloud-storage-object-lock)
- [Lifecycle rules](https://www.backblaze.com/docs/cloud-storage-lifecycle-rules)
- [Restic repository preparation](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html#backblaze-b2)
