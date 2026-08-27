# Backblaze B2 master-key rotation read-only preflight

## Purpose

Confirm that the reviewed Backblaze account and Doppler metadata are ready for
the master-key rotation operation. This preflight is definition-only until it
receives separate execution authorization. It creates no key, config, secret,
or other provider resource.

Passing this preflight does not make the rotation authorization-ready. The
protected one-time secret-write path, name-only readback, terminal-result
classification, bundle checkpoint, and explicit live authorization remain
separate gates.

## Authorization boundary

The preflight may later contact only:

- the governed Backblaze account through an already authenticated web-console
  session; and
- Doppler project metadata for `homelab-dev`.

It must not select **Generate New Master Application Key**, accept an
invalidation warning, create `prd_b2_admin`, read secret names or values, or
contact Restic or a homelab host. Navigation and inspection are allowed;
provider or Doppler form submission is prohibited.

## Protected browser and evidence paths

Create one owned directory matching
`/tmp/backblaze-b2-master-key-preflight.*`. Set `umask 077`; require directory
mode `0700` and file mode `0600`. Store only bounded sanitized observations,
command status, and stderr beneath it. Do not capture screenshots, page HTML,
raw provider responses, browser storage, account identifiers, application-key
identifiers, secret metadata, or credential values.

Create the Playwright working directory and profile beneath the evidence root:

```bash
playwright_working_directory="${evidence_directory}/playwright-work"
playwright_profile_directory="${evidence_directory}/playwright-profile"
install -d -m 0700 \
  "$playwright_working_directory" "$playwright_profile_directory"
cd -- "$playwright_working_directory"
playwright-cli -s=b2masterpreflight open --headed \
  --profile="$playwright_profile_directory" \
  https://secure.backblaze.com/user_signin.htm
```

Run every later `b2masterpreflight` command from that working directory. Close
the named browser, delete its profile data, and remove raw Playwright artifacts
before retaining or hashing sanitized evidence. Reject paths outside the
protected evidence root.

Before opening the browser, install one centralized cleanup handler. It must
preserve the original exit status, run for success, blocked results, browser
failure, `HUP`, `INT`, and `TERM`, and perform these ordered actions:

1. disable its own traps so cleanup cannot recurse;
2. close only the named `b2masterpreflight` browser session;
3. delete only that session's Playwright data;
4. verify the working and profile directories resolve beneath the exact owned
   evidence root; and
5. remove those two browser directories and every raw artifact beneath them.

Signal handlers must convert `HUP`, `INT`, and `TERM` to nonzero exits that
flow through the same cleanup handler. Cleanup failure classifies the preflight
as `blocked`; it must not be hidden by the original command status. Retain only
the bounded sanitized evidence records after cleanup succeeds. This is a
required implementation contract, not an operator reminder.

## Backblaze console observations

Use the governed account-owner session with MFA. Record only booleans:

1. The B2 Cloud Storage **Application Keys** page is accessible.
2. The page identifies a current master application key.
3. The control for generating a new master application key is present.
4. Account documentation or visible console text confirms that generating a
   new master invalidates the current master and exposes the new secret once.
5. No provider state changed during inspection.

Do not select the generation control merely to inspect a warning or result
panel. If either behavior cannot be confirmed without crossing the mutation
boundary, stop and leave that observation unsatisfied.

## Doppler metadata commands

Use Bash with pipefail enabled. Disable version checks, environment-derived
configuration, debug output, and active-config printing. Capture only each
pipeline's final boolean and status.

```bash
doppler --no-check-version --no-read-env --silent projects --json \
  | jq -e '[.[] | select((.slug // .name) == "homelab-dev")] | length == 1'
```

```bash
doppler --no-check-version --no-read-env --silent \
  environments --project homelab-dev --json \
  | jq -e '[.[] | select(.id == "prd")] | length == 1'
```

```bash
doppler --no-check-version --no-read-env --silent \
  configs --project homelab-dev --environment prd --json \
  | jq -e '[.[] | select(.name == "prd_b2_admin")] | length == 0'
```

Do not use `doppler secrets`, `doppler run`, `doppler configs create`, or any
command that emits the active token or configuration. If `--no-read-env`
prevents authentication, stop rather than weakening the boundary.

## Acceptance and result handling

Pass only when every console observation and Doppler predicate is true,
`prd_b2_admin` remains absent, raw browser artifacts are removed, and the
operator confirms no Backblaze, Doppler, Restic, or host state changed.

Also require proof that the centralized cleanup handler ran successfully and
that the named session, profile directory, working directory, and raw browser
artifacts are absent before evidence hashes are calculated.

Classify authentication failure, an unexpected existing config, uncertain
master-key state, inability to verify the invalidation boundary read-only, or
evidence-path escape as `blocked`. Do not repair or create anything.

Keep raw evidence outside Git. A later definition-only readiness transition
may record only sanitized booleans, timestamps, and evidence hashes in the
active operation. That transition requires its own review and checkpoint.
