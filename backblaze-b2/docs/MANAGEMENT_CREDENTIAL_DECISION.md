# Backblaze B2 management-credential decision

## Status and boundary

The operator selected `management_credential_creation_required` and confirmed
that the current master application key is unused and safe to invalidate.
Repository evidence proves that the
credential supplied to `backblaze-b2-capability-remediation-preflight-v1`
authenticated but did not provide every required management capability. The
v1 evidence did not retain the present or missing capability names, so it does
not support a narrower claim.

This reviewed decision does not authorize credential discovery, key creation, key
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

Regenerate the confirmed-unused master key through a separate Backblaze-owned
operation and retain it only as an account-control break-glass credential.
After that rotation is accepted, define another operation for creating one
temporary management credential with an exact name, capability set,
expiration, protected storage, acceptance, recovery, and later revocation.
Neither operation may create the Restic replacement key under the same
authorization.

## Reviewed operator decision

The selected path is:

- `management_credential_creation_required`;
- current master application key in use: `false`; and
- current master application key safe to invalidate: `true`.

The next operation rotates the master key and stores it as a separate
account-level break-glass credential. Creating an expiring management key and
rerunning the read-only preflight remain later, separately authorized stages.
