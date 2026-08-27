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
