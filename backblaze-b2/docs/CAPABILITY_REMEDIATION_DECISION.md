# Backblaze B2 application-key capability remediation

## Status and scope

This decision is reviewed. It selects the least-privilege replacement design
and resolves the seven definition blockers identified after the rejected
bootstrap. It does not authorize provider, Doppler, Restic, or host contact.

The rejected bootstrap is preserved by tag
`backblaze-b2-nautobot-bootstrap-v1-rejected-capability-scope`. The created
bucket, rejected application key, Doppler config, and stored credentials remain
live residue. The bucket is empty and no Restic repository has been
initialized.

## Observed conflict

The Backblaze console's **Read and Write** preset created a key restricted to
the exact Nautobot bucket, but provider readback included settings-changing
capabilities such as `writeBuckets`, `writeBucketLifecycleRules`,
`writeBucketEncryption`, and `writeBucketReplications`. Bucket scope does not
make those additional administration capabilities acceptable.

## Decision

Use `POST /b2api/v4/b2_create_key` with an explicit capability array and exact
bucket-ID restriction. The API contract must omit `namePrefix` to request an
unrestricted prefix. Terminal operation outcomes and later operator actions
are recorded in `backblaze-b2/HISTORY.md`, not in this decision.

The reviewed non-secret candidate contract is:

```yaml
key_name: homelab-nautobot-restic-prd-v2
bucket_ids:
  - 4d1bda761665474eaf030b18
name_prefix: null
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

Omit `namePrefix` from the create request. Backblaze represents an unrestricted
key prefix as `null` in application-key metadata; an empty-string request field
is not the same contract.

The candidate excludes bucket creation, deletion, and settings writes; key
administration; lifecycle, encryption, logging, notifications, and
replication writes; retention and legal-hold administration; governance
bypass; and `shareFiles`. Add no capability during execution. A missing
capability is a failed compatibility test and requires a new reviewed
decision—not an in-place expansion.

Backblaze documents the request fields in
[b2_create_key](https://www.backblaze.com/apidocs/b2-create-key). Use the API
URL returned by protected account authorization rather than a hard-coded
account endpoint.

## Resolved blockers

| Blocker | Reviewed resolution |
| --- | --- |
| Replacement-key name | `homelab-nautobot-restic-prd-v2` |
| Temporary Doppler names | `NAUTOBOT_RESTIC_B2_CANDIDATE_APPLICATION_KEY_ID` and `NAUTOBOT_RESTIC_B2_CANDIDATE_APPLICATION_KEY` in `homelab-dev/prd/prd_b2` |
| Administrator authentication and transport | The retained master credential in `homelab-dev/prd/prd_b2_admin`, with `listKeys`, `writeKeys`, `listBuckets`, `readBuckets`, and `listFiles`; the Python client retrieves both exact Doppler values into bounded memory and never places them in argv, environment, regular files, logs, or evidence |
| Capability sufficiency | The seven-capability set is the only candidate; exact API readback and the isolated S3 probe below are mandatory acceptance gates |
| Isolated probe | One random object beneath `__capability_probe__/homelab-nautobot-restic-prd-v2/`; require list, put, head, get, delete, and absence readback; never initialize Restic |
| Doppler promotion and rollback | Store the candidate under temporary names first; leave canonical values unchanged until acceptance; retain the rejected key and canonical values as rollback until promotion readback passes |
| Rejected-key revocation | A separate operation after candidate acceptance, canonical promotion, and proof that no consumer uses the rejected key |

## Authentication boundary

The read-only preflight may call `b2_authorize_account`, `b2_list_keys`,
`b2_list_buckets`, and `b2_list_file_names`. The supplied credential must
authorize successfully and expose `listKeys`, `writeKeys`, `listBuckets`,
`readBuckets`, and `listFiles`. `writeKeys` is observed only to prove future
creation authority;
the preflight must not call a key-creation, key-deletion, bucket-write, or file-
write endpoint.

The implementation must use the Python standard library with default TLS
verification and proxies disabled. It invokes exact, value-only Doppler
lookups for the two reviewed `prd_b2_admin` names with `--no-read-env` and
`--silent`, captures their bounded output only inside the client process,
builds HTTP Basic authorization and the returned account token in memory, and
never serializes raw responses. It must exclude `DOPPLER_TOKEN` and unrelated
environment values from the child process.

## Replacement and compatibility sequence

1. Complete and accept the separately authorized read-only authentication and
   residue preflight.
2. Define a hash-bound replacement-key creation operation using the exact
   reviewed request policy.
3. Stream the one-time replacement values directly into the two temporary
   Doppler candidate names.
4. Require exact API readback of key name, bucket IDs, prefix, expiration,
   `s3` option, and capability set; reject any difference or extra capability.
5. In a separately authorized compatibility stage, create one random probe
   object beneath the reviewed prefix, prove list/head/get behavior and exact
   content, delete it, and prove absence. Retain residue and stop if cleanup
   cannot be proven.
6. Promote candidate values to the canonical Doppler names through a separate
   operation. Keep the rejected key valid until promotion readback succeeds.
7. Revoke the rejected key only through a later operation after proving no
   consumer uses it. Remove temporary Doppler names only after canonical
   authentication succeeds.

No Backblaze B2 configuration is accepted until the replacement passes policy,
authentication, compatibility, promotion, and cleanup gates. Restic
initialization remains a separate later operation.
