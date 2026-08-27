# Backblaze B2 management-credential decision

## Status and boundary

Operator confirmation is required. Repository evidence proves that the
credential supplied to `backblaze-b2-capability-remediation-preflight-v1`
authenticated but did not provide every required management capability. The
v1 evidence did not retain the present or missing capability names, so it does
not support a narrower claim.

This document does not authorize credential discovery, key creation, key
replacement, key revocation, secret access, or another preflight execution.

## Required authority

A suitable existing credential must return all of these capabilities from
`b2_authorize_account`:

- `listKeys`;
- `writeKeys`;
- `listBuckets`;
- `readBuckets`; and
- `listFiles`.

The credential is control-plane input for the bounded remediation operation;
it is not a Restic client credential. Do not substitute the rejected
bucket-scoped Restic key merely because it can list or write objects.

## Decision paths

### Existing credential available

The operator confirms that an existing protected credential with all five
capabilities is available. Define a corrected read-only successor preflight,
bind it to the terminal v1 tag and corrected client, and require a new bundle
hash and execution authorization. Do not record the credential identity or
values.

### No suitable credential available

Define a separate Backblaze-owned mutation operation for creating one
temporary management credential. That operation must specify its exact name,
capabilities, expiration, protected storage, acceptance, recovery, and later
revocation. It must not create the Restic replacement key in the same
authorization.

## Unresolved operator decision

Choose exactly one before defining a successor operation:

- `existing_management_credential_available`; or
- `management_credential_creation_required`.

Until then, `backblaze-b2/manifests/operation.yaml` remains clean and another
preflight or provider mutation is not authorization-ready.
