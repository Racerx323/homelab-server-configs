# Backblaze B2 configuration walkthrough

## Authorization boundary

This procedure defines the first B2 configuration. Completing console steps
changes the Backblaze account and requires separate authorization. Repository
review does not authorize bucket creation, key creation, lifecycle changes, or
secret-system changes.

Do not initialize Restic or contact `j2-svpi4mf` during this procedure.

## Phase 1: record the decisions

Review the Phase 1 proposal in
`backblaze-b2/manifests/desired-state.yaml` before opening the Backblaze
console:

| Decision | Required value |
| --- | --- |
| Consumer | `nautobot` |
| Purpose | off-host encrypted Restic repository |
| Bucket name | `theama-homelab-nautobot-restic-prd` |
| Repository prefix | empty for the dedicated Nautobot bucket |
| Creation owner | named operator or authorized B2 operation |
| Access type | private |
| Server-side encryption | Backblaze-managed encryption enabled |
| Object Lock | disabled |
| Lifecycle | Keep only the last version of the file |
| Application-key name | `homelab-nautobot-restic-prd-v2` |
| Key bucket scope | exact Nautobot bucket |
| Key prefix scope | unrestricted; omit `namePrefix` and require `null` readback |
| Key access | read and write, with verified list/read/write/delete file capabilities |
| List all bucket names | enabled for S3 compatibility |
| Key expiration | no provider expiration; replace every 180 days |
| Doppler destination | `homelab-dev/prd_b2` |
| Doppler key ID name | `NAUTOBOT_RESTIC_B2_APPLICATION_KEY_ID` |
| Doppler application-key name | `NAUTOBOT_RESTIC_B2_APPLICATION_KEY` |

The proposed bucket name follows Backblaze and S3-compatible naming rules.
Backblaze confirms global availability only during bucket creation. Stop if
the provider rejects it; do not select a substitute during execution.

`prd_b2` does not exist yet. Its creation and both secret writes require the
same live operation that creates the application key. Do not commit account
identifiers or credentials. Create a sanitized accepted-state manifest after
provider readback supplies verified values.

## Phase 2: prepare the account

1. Sign in to the Backblaze web console using the governed administrator
   account.
2. Confirm B2 Cloud Storage is enabled and the account can create a private
   bucket.
3. Review payment method, usage caps, and alert contacts. Define changes to
   those settings as separate mutation classes in the live operation.
4. Confirm the operator can store the one-time application key value in the
   approved secrets system before creating the key.

Stop if account ownership, billing authority, or secret storage is unclear.

## Phase 3: create the bucket

1. Open **B2 Cloud Storage > Buckets** and choose **Create a Bucket**.
2. Enter the reviewed globally unique bucket name.
3. Set file access to **Private**.
4. Enable Backblaze-managed server-side encryption.
5. Leave Object Lock disabled.
6. Create the bucket.
7. Record the bucket name, bucket ID, region, and Endpoint field outside the
   raw evidence log. The endpoint must match
   `https://s3.<region>.backblazeb2.com`.

Stop if the console creates the bucket in an unexpected region or reports an
endpoint that does not match the reviewed identity.

## Phase 4: configure lifecycle

1. Open the new bucket's **Lifecycle Settings**.
2. Select **Keep only the last version of the file**.
3. Confirm no rule deletes the current version based on age.
4. Save the setting and read it back from the bucket details.

This rule removes hidden prior versions left by Restic's S3-compatible delete
behavior. Restic retains authority over snapshot retention and prune policy.

## Phase 5: create the application key

The console's **Read and Write** preset is rejected because provider readback
proved that it grants bucket-administration capabilities outside the reviewed
consumer boundary. Do not create the replacement through that preset.

Use the separately reviewed and authorized
[`REPLACEMENT_KEY_CREATION.md`](REPLACEMENT_KEY_CREATION.md) operation. It uses
the B2 Native API with the exact seven-capability array, exact bucket-ID list,
an unrestricted prefix represented as `null`, and no provider expiration. It
stores the one-time values only
under the temporary Doppler candidate names. Canonical promotion remains a
separate operation after authentication and compatibility acceptance.

Record the key name, bucket scope, prefix scope, expiration policy, and
capability names. Reject a key with access to all buckets or with bucket,
retention, legal-hold, replication, or governance-administration capabilities.

The key has no provider-enforced expiration because an expired unattended key
would stop backups. Replace it every 180 days. Create and verify the replacement
before revoking the old key; do not overwrite the only working credential.

### API-created key visibility and management

Backblaze Native API v4 calls a key created with the `bucketIds` array a
Multi-Bucket Application Key, including when that array contains only one
bucket. These keys require v4 authorization. Backblaze also documents that
v1-v3 `b2_list_keys` calls omit Multi-Bucket Application Keys, while v4 returns
them. See the official
[Native API version history](https://www.backblaze.com/docs/cloud-storage-native-api-versions)
and [application-key documentation](https://www.backblaze.com/docs/cloud-storage-application-keys).

The operator confirmed that the v4 key created for this component is absent
from the provider web console but present in `b2 key list -l`. Treat console
visibility as informational, not as proof that the key exists or has been
deleted. Backblaze's reviewed documentation does not establish the broader
claim that every CLI- or API-created key is hidden from the console. Use v4 API
readback or a current B2 CLI authenticated with an account-level credential as
the management authority:

```bash
b2 key list -l
b2 key delete APPLICATION_KEY_ID
```

`b2 key list -l` requires `listKeys`; deletion requires `deleteKeys` and is a
separately authorized, irreversible provider mutation. Never put an application
key value on either command line, in Git, or in evidence. The CLI command
contract is documented in Backblaze's
[`key list`](https://github.com/Backblaze/B2_Command_Line_Tool/blob/master/doc/source/subcommands/key_list.md)
and
[`key delete`](https://github.com/Backblaze/B2_Command_Line_Tool/blob/master/doc/source/subcommands/key_delete.md)
references.

## Phase 6: provider readback

Use the Backblaze console or a separately defined read-only API preflight to
confirm:

- the bucket identity, region, and S3 endpoint;
- private access and the expected encryption setting;
- Object Lock disabled and the required lifecycle selected;
- the application key restricted to the exact bucket with an unrestricted
  prefix represented as `null`;
- the expected capability set and expiration policy; and
- both credential values present in the approved secrets system without value
  output.

Capture bounded raw evidence outside Git. Sanitize account identifiers,
credential identifiers, unrelated bucket names, billing data, and object
listings.

## Phase 7: accept and hand off

After all readback gates pass:

1. create a non-secret B2 manifest with the accepted bucket identity and key
   policy;
2. preserve the live operation and sanitized evidence manifest in an annotated
   tag and component history;
3. retire the active B2 operation from the main branch; and
4. hand the endpoint, bucket, unrestricted-prefix policy, and secret reference
   names to the
   Restic component.

The handoff does not authorize `restic init`. Define repository initialization
and recovery-password handling as the next Restic operation.

## Rollback and replacement

Before Restic initialization, rollback may revoke the new application key and
delete the empty bucket after readback proves that it contains no objects.
Bucket deletion and key revocation require explicit authorization.

After Restic stores any object, do not delete the bucket, change lifecycle, or
revoke the only working key as an automatic rollback. Preserve access, capture
evidence, and define a recovery or key-replacement operation.
