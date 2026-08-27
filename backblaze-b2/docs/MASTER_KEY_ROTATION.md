# Backblaze B2 master-key rotation operation

## Purpose and authorization boundary

Regenerate the unused Backblaze B2 master application key and store its ID and
one-time value in a dedicated Doppler administrator config. This operation is
definition-only and unready until its blockers are cleared and a hash-bound
live authorization is granted.

Generating the new master key invalidates the previous master and cannot be
rolled back. Do not execute any step from this document without the active
operation manifest and its exact authorization hash.

This operation does not create the temporary management key, replace or revoke
the rejected Restic key, initialize Restic, or contact a homelab host.

## Reviewed identities

| Item | Value |
| --- | --- |
| Doppler project | `homelab-dev` |
| Doppler environment | `prd` |
| Doppler config | `prd_b2_admin` |
| Master key ID secret | `BACKBLAZE_B2_MASTER_APPLICATION_KEY_ID` |
| Master key value secret | `BACKBLAZE_B2_MASTER_APPLICATION_KEY` |
| Credential role | account-control bootstrap and break glass |
| Consumer use | prohibited |
| Provider expiration | unavailable for a master key |

The master key has no operator-selected key name. Backblaze owns its identity
and exposes its value only when generated.

## Required preflight

Follow the separately authorized read-only
[master-key rotation preflight](MASTER_KEY_ROTATION_PREFLIGHT.md). The
preflight may inspect the generation control but must not select it or submit
any provider or Doppler form.

Before the first mutation, require all of the following:

- the operator assertion that the current master key is unused and safe to
  invalidate remains current;
- authenticated Backblaze console access with account ownership and MFA;
- the exact Doppler project and `prd` environment exist;
- Doppler config `prd_b2_admin` is absent;
- the operator can keep the Backblaze one-time result visible until protected
  secret writes and name-only readback finish;
- a mode-`0700` evidence directory is ready for bounded sanitized records; and
- no master-key ID or value can enter Git, argv, shell tracing, logs,
  screenshots, clipboard history, or evidence.

Stop without repair if the Doppler config already exists or any ownership,
identity, secret-transport, or recovery assertion is false.

## Ordered mutation

1. Create only Doppler config `homelab-dev/prd/prd_b2_admin`.
2. In **B2 Cloud Storage > Application Keys**, select **Generate New Master
   Application Key** and confirm the provider warning that the old master will
   become invalid.
3. Keep the one-time result visible.
4. Stream the new master key ID and value directly into the two reviewed
   Doppler secret names without placing either value in argv, environment,
   regular files, captured output, or evidence.
5. Read back only the two Doppler secret names and prove both are present.
6. Record the provider-confirmed old-master invalidation and close the
   one-time result only after name-only readback passes.

No other Doppler config, secret, B2 application key, bucket, object, lifecycle,
encryption, or account setting may change.

## Protected Doppler write implementation

The reviewed helper is
`backblaze-b2/scripts/protected_doppler_master_write.py`. A future hash-bound
launcher must create two owned mode-`0600` FIFOs beneath the protected
operation evidence root and start the helper before accepting either one-time
value. The helper validates and unlinks each FIFO, sends one value at a time to
the exact Doppler secret name through `doppler secrets set NAME` standard
input, and clears its mutable buffer after the command returns.

The helper uses `--no-read-env` and `--silent`, supplies no secret in argv or a
regular file, and retains no command output. Acceptance uses only
`doppler secrets --only-names --json`; any value-bearing response is rejected.
If the key-ID write succeeds but the key-value write fails, classify the result
as `partial_secret_write_manual_intervention`. Do not delete, overwrite, or
retry either secret automatically.

This helper does not create `prd_b2_admin`, select the Backblaze generation
control, or authorize live execution. Those steps remain the responsibility of
a separately reviewed, hash-bound operation launcher.

The full outer launcher is
`backblaze-b2/scripts/run-master-key-rotation.sh`. It validates the exact
operation schema and authorization hash before any Doppler command, proves the
administrator config remains absent, creates only that config, and then pauses
for the operator-controlled Backblaze generation step. It cannot run while the
active operation is unready or has blockers.

Every exit after evidence-root creation records a mode-`0600`, sanitized
terminal result with the last crossed boundary: `pre_mutation`,
`doppler_config_creation_attempted`, `doppler_config_created`,
`master_generated`, `credentials_stored`, or `accepted`. An indeterminate
config-creation response and every interruption or failure after master
generation require manual intervention. Terminal evidence contains hashes,
booleans, and bounded error classes only—never key IDs or values.

## Acceptance and recovery

Accept only when the exact administrator config exists, both reviewed secret
names are present, the one-time panel was not closed early, the provider
reports the old master invalidated, and no secret value or raw browser artifact
was retained.

There is no rollback to the old master. Before master generation, cleanup is
limited to local evidence; retain an already-created empty Doppler config for
review. After generation, keep the one-time result open and retry only the
protected Doppler write. If the value is lost before durable storage, stop for
manual intervention: generating another master requires a new authorization.

The next separately authorized stage creates an expiring five-capability
management application key using the retained master. The master itself must
never be used by Restic or another workload.
