# Backblaze B2 master-key rotation operation

## Purpose and authorization boundary

Regenerate an unused Backblaze B2 master application key and store its existing
account-level ID and newly generated one-time value in a dedicated Doppler
administrator config. No master-key rotation operation is active. The archived
v1 execution is indexed in `../HISTORY.md`; future reuse requires a new reviewed
operation definition and hash-bound live authorization.

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

The master key has no operator-selected key name. Its ID is the account-level
identifier formerly called the account ID and remains visible on the App Keys
page. Generating a new master changes and displays only the one-time secret
value; it does not produce a new master key ID.

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
2. Before generation, enter the existing account-level master application-key
   ID shown on the App Keys page into the protected launcher prompt.
3. In **B2 Cloud Storage > Application Keys**, select **Generate New Master
   Application Key** and confirm the provider warning that the old master will
   become invalid.
4. Keep the one-time result visible and enter only its newly generated secret
   value into the separately labelled protected prompt.
5. Stream the existing ID and new value directly into the two reviewed Doppler
   secret names without placing either value in argv, environment, regular
   files, captured output, or evidence.
6. Read back only the two Doppler secret names and prove both are present.
7. Record the provider-confirmed old-master invalidation and close the
   one-time result only after name-only readback passes.

No other Doppler config, secret, B2 application key, bucket, object, lifecycle,
encryption, or account setting may change.

## Protected Doppler write implementation

The reviewed helper is
`backblaze-b2/scripts/protected_doppler_master_write.py`. The inactive launcher
uses explicit, separately labelled terminal prompts for the existing ID and
new one-time value. It rejects empty input before starting the writer, then
creates two owned mode-`0600` FIFOs beneath the protected operation evidence
root. The helper validates and unlinks each FIFO, sends one value at a time to
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

The inactive outer launcher is
`backblaze-b2/scripts/run-master-key-rotation.sh`. It validates the exact
operation-state schema and authorization hash before any Doppler command. With the
operation manifest in clean state, it rejects execution before provider or
Doppler contact. A future definition must explicitly review the expected
Doppler config state instead of inheriting v1's create-if-absent assumption.

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
