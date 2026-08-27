# Backblaze B2 management-credential decision

## Status and boundary

The operator initially selected `management_credential_creation_required` and
confirmed that the former master application key was unused and safe to
invalidate. Repository evidence proves that the
credential supplied to `backblaze-b2-capability-remediation-preflight-v1`
authenticated but did not provide every required management capability. The
v1 evidence did not retain the present or missing capability names, so it does
not support a narrower claim.

The completed master rotation is preserved by the terminal tag indexed in
`../HISTORY.md`. The retained credential is now the reviewed existing
management credential for the bounded read-only v2 preflight and later
hash-bound key creation. Its secret references are
`homelab-dev/prd/prd_b2_admin`; this decision does not record its identity or
values.

This reviewed decision does not authorize key creation, key replacement, key
revocation, secret access, or another preflight execution.

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
authorization. This path is no longer selected because the retained rotated
master provides the required control-plane authority.

## Reviewed operator decision

The selected current path is:

- `existing_management_credential_available`;
- credential source: `homelab-dev/prd/prd_b2_admin` secret references;
- consumer use: prohibited; and
- read-only v2 preflight execution: separately authorized.

The v2 preflight may use the retained master only for the reviewed read-only
control-plane calls. A later replacement-key creation remains a distinct,
hash-bound mutation. The master must never be configured as a Restic or other
workload credential.
