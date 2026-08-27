# Backblaze B2 capability-remediation read-only preflight

## Purpose

Prove that the retained master credential can authenticate to the B2 Native API
and collect the exact non-secret inputs required for a future replacement-key
operation. This v3 successor is definition-only, unready, and requires separate
read-only execution authorization.

It must not create, update, or delete a bucket, key, object, Doppler config, or
secret. It must not contact Restic or any homelab host.

## Protected input and evidence

Create one owned directory matching
`/tmp/backblaze-b2-capability-preflight.*` with mode `0700` and `umask 077`.
The launcher passes no credential argument and requires no interactive input.
The client retrieves only `BACKBLAZE_B2_MASTER_APPLICATION_KEY_ID` and
`BACKBLAZE_B2_MASTER_APPLICATION_KEY` from
`homelab-dev/prd/prd_b2_admin`. Each exact `doppler secrets get NAME --plain`
lookup uses `--no-read-env`, `--silent`, a minimal environment, bounded output,
and an explicit timeout. Reject empty input, embedded newlines, NUL bytes, or
oversized values. Clear mutable buffers after use. Values must never enter
argv, environment variables, regular files, shell tracing, logs, exceptions,
or evidence. Workload metadata uses `doppler secrets --only-names --json`;
`--only-names` must not be placed on the `secrets get` subcommand.

Record each sanitized forward observation as soon as its gate passes. A later
blocker must retain earlier authentication, endpoint, bucket, key, file, and
no-mutation observations without retaining identifiers, tokens, or raw
responses.

Use the Python standard library with default certificate and hostname
verification, HTTPS-only redirects, proxies disabled, bounded response sizes,
and explicit timeouts. Build the initial HTTP Basic authorization and returned
account authorization token only in memory. Do not capture raw JSON responses.

## Allowed API calls

The exact allowlist is:

1. `GET /b2api/v3/b2_authorize_account` on the documented Backblaze account
   authorization origin;
2. `POST <storageApi.apiUrl>/b2api/v4/b2_list_keys`;
3. `POST <storageApi.apiUrl>/b2api/v4/b2_list_buckets`; and
4. `POST <storageApi.apiUrl>/b2api/v4/b2_list_file_names` for the exact bucket.

Reject a returned API URL unless it is HTTPS, has no user information, query,
or fragment, and its hostname is exactly `api.backblazeb2.com` or a single
provider shard matching `api[0-9]+.backblazeb2.com`. Validate the returned S3
URL independently as exactly `https://s3.us-west-002.backblazeb2.com`.

No other endpoint is permitted. In particular, prohibit `b2_create_key`,
`b2_delete_key`, bucket writes, lifecycle or encryption writes, file upload,
file deletion, and every S3 object request.

## Assertions

Require all of the following:

- both exact `prd_b2_admin` secret references resolve without value output;
- account authorization succeeds without exposing account identity or token;
- returned capabilities include `listKeys`, `writeKeys`, `listBuckets`,
  `readBuckets`, and `listFiles`;
- exact bucket `theama-homelab-nautobot-restic-prd` resolves to bucket ID
  `4d1bda761665474eaf030b18`, remains private, and is in `us-west-002`;
- the bucket contains zero current files;
- rejected key `homelab-nautobot-restic-prd` exists;
- replacement key `homelab-nautobot-restic-prd-v2` is absent;
- rejected-key readback still contains the previously observed prohibited
  capability classes;
- Doppler config `homelab-dev/prd/prd_b2` exists;
- both canonical secret names exist without value output; and
- both temporary candidate secret names are absent.

Filter provider and Doppler responses in memory. Evidence may record only the
booleans above, region, endpoint, exact bucket name and ID, reviewed key names,
capability names for the rejected key, command status, bounded error classes,
and hashes. Exclude account IDs, authorization tokens, application-key IDs and
values, unrelated bucket or key names, object listings, billing data, and raw
responses.

## Result handling

Pass only when every assertion succeeds, no response was truncated, credential
input was consumed and discarded, and no mutation endpoint was attempted.
Classify authentication failure, missing authority, unexpected residue,
candidate-name collision, non-empty bucket, unsafe URL, or secret-handling
failure as `blocked`; do not repair anything.

After a passed preflight, preserve only sanitized evidence outside Git. A
separate definition-only transition may bind its hashes to a replacement-key
operation. Passing this preflight does not authorize creating or revoking a
key, writing Doppler secrets, probing S3, initializing Restic, or contacting a
host.
