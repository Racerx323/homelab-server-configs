# Backblaze B2 component rules

These rules apply beneath `backblaze-b2/` and refine the repository rules in
`../AGENTS.md`.

## Architecture authority

- `docs/B2_ARCHITECTURE.md` governs account, bucket, endpoint, application-key,
  lifecycle, encryption, evidence, and recovery boundaries for Backblaze B2.
- Consumer components own their datasets, repository formats, backup tools,
  schedules, retention policies, restore acceptance, and terminal history.
- `docs/B2_CONFIGURATION.md` is the operator procedure. Keep operation results
  and current state out of the architecture and procedure documents.

## Repository contents

- Keep reviewed non-secret bucket definitions, schemas, sanitized identities,
  operation specifications, and operator documentation under `backblaze-b2/`.
- Add a manifest or implementation path only when it contains reviewed values
  or executable behavior. Do not create placeholder trees.
- Keep application keys, key IDs, account identifiers, credential files, raw
  object listings, billing data, and raw evidence outside Git.
- Store secret reference names without storing secret values in arguments,
  bundle hashes, logs, evidence, examples, or fixtures.

## Live-operation boundaries

- Treat account changes, bucket creation or deletion, access changes,
  encryption changes, Object Lock changes, lifecycle changes, application-key
  creation or revocation, and caps or alerts as separate mutation classes.
- Require a scoped operation and authorization before changing the Backblaze
  control plane. A consumer operation cannot authorize a B2-owned change.
- Create consumer keys with bucket and prefix restrictions. Do not use the
  master application key for a backup client.
- Preserve a replacement key before revoking a credential used by a live job.

## Validation

- Validate private access, exact bucket and endpoint identity, lifecycle
  policy, encryption and Object Lock state, key scope, capability set, secret
  absence, and sanitized evidence before accepting a B2 configuration.
- Use Backblaze console or API readback as the final authority. A repository
  definition does not prove that the cloud configuration exists.
