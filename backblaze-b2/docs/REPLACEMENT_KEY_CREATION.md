# Backblaze B2 replacement-key creation

## Purpose and authorization boundary

Create the exact least-privilege replacement application key selected in
`CAPABILITY_REMEDIATION_DECISION.md` and store its one-time values only under
the two temporary candidate names in Doppler. This operation is definition-only
and unready. It does not authorize provider or Doppler mutation.

The future live authorization may cover one exact `b2_create_key` request and
the protected candidate-secret write. It must not authorize object access,
canonical-secret promotion, rejected-key revocation, Restic initialization, or
host contact.

## Required preconditions

- The passed v3 preflight tag and evidence hashes match the operation manifest.
- The exact bucket and rejected-key residue remain unchanged.
- The replacement key and both candidate Doppler names remain absent.
- The retained administrator credential still has the five reviewed management
  capabilities.
- The complete implementation, residue handling, terminal evidence, checkpoint,
  and final bundle receive separate review before readiness.

## Exact provider request

Authorize against the standard Backblaze endpoint, validate the returned API
origin, then issue one `POST /b2api/v4/b2_create_key` request with:

```yaml
accountId: RETURNED_ACCOUNT_ID
keyName: homelab-nautobot-restic-prd-v2
bucketIds:
  - 4d1bda761665474eaf030b18
namePrefix: ""
capabilities:
  - listAllBucketNames
  - listBuckets
  - readBuckets
  - listFiles
  - readFiles
  - writeFiles
  - deleteFiles
```

Omit `validDurationInSeconds`. Require the response `options` array to equal
`["s3"]`. Reject an implementation that adds a request field or capability,
changes the bucket or prefix, uses a console preset, or retries creation after
a response may have been accepted.

## Secret handling

Retrieve the administrator values from `homelab-dev/prd_b2_admin` only inside
the client process. Keep the returned replacement key ID and one-time key value
in bounded mutable memory. Send each value through standard input to an exact,
non-shell Doppler command for `homelab-dev/prd_b2`; never place a value in argv,
the environment, a regular file, logs, exceptions, or evidence.

Write only:

- `NAUTOBOT_RESTIC_B2_CANDIDATE_APPLICATION_KEY_ID`; and
- `NAUTOBOT_RESTIC_B2_CANDIDATE_APPLICATION_KEY`.

Verify the two candidate names without reading values. Do not modify the
canonical names.

## Acceptance and residue

Read back the replacement key through the administrator API and require exact
name, bucket-ID list, empty prefix, omitted provider expiration, `s3` option,
and capability set. Confirm candidate-name presence, canonical-name stability,
rejected-key stability, and absence of object or consumer contact.

A pre-creation failure performs local cleanup only. After provider creation,
never retry automatically. If either candidate write or later readback fails,
stop with `manual_intervention`, retain sanitized residue evidence, and require
a separately authorized cleanup or recovery operation. Automatic key or secret
deletion is outside this operation.

Successful creation does not accept the credential for use. Candidate
authentication, the isolated S3 compatibility probe, canonical promotion, and
rejected-key revocation remain separate operations.
