# Backblaze B2 application-key capability remediation

## Status and scope

This is an unready, definition-only decision. It does not authorize provider,
Doppler, Restic, or host contact. The rejected bootstrap is preserved by tag
`backblaze-b2-nautobot-bootstrap-v1-rejected-capability-scope`.

The created bucket, rejected application key, Doppler config, and stored
credentials remain live residue. The bucket is empty and no Restic repository
has been initialized. Do not revoke the only stored key, overwrite its Doppler
values, or delete the bucket without a separately reviewed operation.

## Observed conflict

The Backblaze console's **Read and Write** preset created a key restricted to
the exact Nautobot bucket, but the provider readback included settings-changing
capabilities such as `writeBuckets`, `writeBucketLifecycleRules`,
`writeBucketEncryption`, and `writeBucketReplications`. Those capabilities
conflict with the reviewed boundary that B2 configuration remains owned by a
separate provider operation.

The rejected key also has the required file list, read, write, and delete
capabilities. Bucket scope alone does not make its additional administration
capabilities acceptable.

## Options evaluated

| Option | Evaluation |
| --- | --- |
| Accept the console-created key | Rejected. It violates the reviewed least-privilege contract. |
| Recreate the key through the same console preset | Rejected. It would reproduce the observed capability set. |
| Create a replacement with the B2 Native API | Preferred, pending the blockers and validation below. The API accepts an explicit capability list and exact bucket restriction. |
| Revoke or delete current residue now | Rejected. No cleanup mutation is authorized, and replacement access is not yet proven. |

## Proposed API contract

Use `POST /b2api/v4/b2_create_key` only in a future hash-bound operation. Build
the request from independently verified provider metadata and protected
administrator authentication. Never put the account ID, authorization token,
application-key ID, or application-key value in Git, arguments, logs, or
evidence.

The proposed non-secret request policy is:

```yaml
key_name: unresolved_pending_review
bucket_ids:
  - 4d1bda761665474eaf030b18
name_prefix: ""
valid_duration: omitted
capabilities:
  - listAllBucketNames
  - listBuckets
  - readBuckets
  - listFiles
  - readFiles
  - writeFiles
  - deleteFiles
```

The candidate deliberately excludes bucket creation, deletion, settings
writes, lifecycle, encryption, logging, notifications, replication, key
administration, retention, legal hold, and governance bypass. `shareFiles` is
also excluded unless an isolated compatibility test proves it is required.

Backblaze documents the request fields in
[b2_create_key](https://www.backblaze.com/apidocs/b2-create-key). The future
operation must use the API URL returned by protected account authorization,
not a hard-coded account endpoint.

## Required sequence for a future operation

1. Read back the exact bucket ID, empty state, endpoint, and rejected-key
   residue without exposing unrelated provider data.
2. Resolve and review a distinct replacement-key name and temporary Doppler
   candidate-key names.
3. Prove a protected administrator authentication method that has key-creation
   authority without exposing the master credential.
4. Create one exact-bucket replacement key with the explicit capability list.
5. Keep the one-time result open while streaming both values directly to the
   temporary Doppler names.
6. Read back the exact key name, bucket IDs, prefix, expiration, S3 option, and
   capability set. Reject any extra capability.
7. Run a separately authorized isolated S3 compatibility check. It must not
   initialize Restic; any write/delete probe requires an explicit object
   mutation and cleanup contract.
8. Promote the candidate credentials to the canonical Doppler names only
   after candidate acceptance.
9. Treat revocation of the rejected key as a later, separately authorized
   mutation after all consumers are proven to use the replacement.

## Blockers before an operation may be defined

- replacement application-key name review;
- temporary Doppler candidate-key name review;
- protected administrator authentication and API transport design;
- confirmation that the proposed capability set is sufficient for the
  intended S3-compatible Restic client;
- isolated probe scope, cleanup, and evidence design;
- canonical Doppler promotion and rollback design; and
- rejected-key revocation timing and recovery boundary.

No Backblaze B2 configuration is accepted until a replacement passes every
policy and compatibility gate. Restic initialization remains a separate later
operation.
