# Backblaze B2 S3 compatibility probe

## Purpose and status

This definition specifies the isolated object transaction required to prove
that the canonical Nautobot Restic credential can use Backblaze's
S3-compatible interface. The active operation is unready and definition-only.
It does not authorize provider, Doppler, Restic, or host contact.

The protected SigV4 client, hash-bound Python launcher, and offline failure
regressions are implemented but unreviewed. Direct client execution fails
closed. The launcher remains unready and no live authorization exists yet.

The probe accepts only the seven-capability replacement credential already
stored under the canonical Doppler names. The original overprivileged key was
deleted by the operator, so this operation has no old-key fallback. A failed
probe must not broaden the replacement key or create another key.

## Read-only preflight

Before readiness, the launcher provides a separately authorized `preflight`
mode. It reads only the two canonical `homelab-dev/prd_b2` values into memory,
authenticates them with `b2_authorize_account`, and requires the exact seven
capabilities, bucket identity, null name prefix, no provider expiration, and
reviewed S3 endpoint. It then lists only a fresh generated probe prefix and
requires it to be empty.

The preflight cannot put or delete an object, use administrator or candidate
credentials, fall back to the deleted old key, contact Restic, or contact a
host. Its command is:

```text
python3 backblaze-b2/scripts/run_s3_compatibility_probe.py preflight
```

## Owned probe object

Each execution must generate a fresh 128-bit lowercase hexadecimal run ID from
the operating system cryptographic random source. The only owned object is:

```text
__capability_probe__/homelab-nautobot-restic-prd-v2/RUN_ID/probe.txt
```

The exact object bytes are:

```text
nautobot B2 S3 compatibility probe v1
```

The trailing newline is part of the content. Its SHA-256 is
`d351ee40d27759daeca28938056b90208e9c5b791d1f9267b2aec8ec1ae13089`.
Reject an existing object or any additional object beneath the generated run
prefix before the first write.

## Ordered transaction

The implementation uses the reviewed Backblaze S3 endpoint, exact bucket, and
canonical Doppler secret references. It must keep both credential
values in memory and outside argv, environment dumps, logs, and evidence.

Perform exactly these provider operations:

1. List the generated run prefix and require zero objects.
2. Put the exact probe object once.
3. Head the object and verify its key and content length.
4. List the run prefix and require exactly the owned object.
5. Get the object and compare its bytes and SHA-256 independently.
6. Delete exactly the owned object once.
7. Require a not-found response for the exact object and an empty prefix list.

Do not use Restic, initialize a repository, enumerate unrelated objects, alter
bucket settings, create or delete keys, or contact `j2-svpi4mf`.

## Failure and residue

A failure before the put request cleans only the protected local evidence
directory. After the put may have succeeded, attempt deletion only for the
exact generated object and then verify absence. Never delete by an unbounded
prefix.

If absence cannot be proven, stop with a manual-intervention result, retain
sanitized evidence identifying only the owned key pattern and run ID hash, and
block B2 acceptance. Do not retry the put, hide residue, expand permissions, or
start another probe.

## Acceptance and evidence

Acceptance requires every ordered operation, exact content readback, and final
absence check to pass. Record bounded evidence for the operation phases,
request classes, HTTP status classes, content hash, mutation status, cleanup
status, and residue decision. Do not record account IDs, application-key IDs or
values, authorization headers, signed URLs, unrelated object names, or raw
provider responses.

A successful probe accepts only S3 credential compatibility and cleanup. It
does not initialize or accept a Restic repository, prove backup recovery, or
authorize Nautobot deployment.
