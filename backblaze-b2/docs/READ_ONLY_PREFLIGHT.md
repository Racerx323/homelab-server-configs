# Backblaze B2 and Doppler read-only preflight

## Purpose

Run this preflight before the B2 bootstrap operation becomes authorization
ready. It checks account readiness and confirms that the proposed Doppler
configuration does not exist. It creates no bucket, key, config, or secret.

The preflight cannot prove global availability of
`theama-homelab-nautobot-restic-prd`. Backblaze makes that decision during
bucket creation. A collision stops the later operation; the operator must not
choose a substitute.

## Authorization boundary

The preflight requires separate read-only authorization before execution. It
may contact only:

- the governed Backblaze account through the web console; and
- Doppler project metadata for `homelab-dev`.

It must not contact `j2-svpi4mf`, Restic, or any bucket endpoint. It must not
read a Doppler secret name or value.

## Evidence protection

Create one owned temporary directory matching
`/tmp/backblaze-b2-preflight.*`. Set `umask 077`; require directory mode `0700`
and file mode `0600`. Capture bounded sanitized observations, command status,
and stderr. Do not capture screenshots or raw provider responses.

Create the Playwright working directory and browser profile beneath that
protected evidence directory. Run every `playwright-cli` command from the
working directory because Playwright stores session artifacts relative to the
current directory. After inspection, close the named browser, delete its
profile data, and remove its raw `.playwright-cli` artifacts before hashing or
retaining sanitized evidence. Do not create Playwright artifacts beneath the
repository, home directory, or another working directory.

Prepare and enter the bounded paths before starting the browser:

```bash
playwright_working_directory="${evidence_directory}/playwright-work"
playwright_profile_directory="${evidence_directory}/playwright-profile"
install -d -m 0700 \
  "$playwright_working_directory" "$playwright_profile_directory"
cd -- "$playwright_working_directory"
playwright-cli -s=b2preflight open --headed \
  --profile="$playwright_profile_directory" \
  https://secure.backblaze.com/user_signin.htm
```

Use the same working directory for every later `b2preflight` command. Do not
retain either browser directory as evidence. Validate their exact location and
ownership before removing them after `close` and `delete-data` complete.

Exclude account IDs, key IDs, application-key values, unrelated bucket and key
names, billing details, contact information, browser session data, Doppler
tokens, and secret metadata.

## Backblaze console observations

Sign in with the governed administrator account. Navigation controls that open
an empty bucket or application-key draft may be selected for field inspection.
Do not submit a draft, enter a proposed identity, or select a final create,
update, delete, enable, save, or confirmation control.

1. Confirm B2 Cloud Storage is enabled.
2. Confirm the account region and private-bucket creation control are present.
3. Confirm no bucket in this account uses
   `theama-homelab-nautobot-restic-prd`.
4. Confirm no application key in this account uses
   `homelab-nautobot-restic-prd`.
5. Confirm the account exposes usage caps and alert contacts for operator
   review. Record no values.
6. Confirm the application-key form supports exact-bucket scope, Read and
   Write access, List All Bucket Names, empty prefix, and no expiration.
7. Confirm the bucket form supports private access, Backblaze-managed
   encryption, disabled Object Lock, and lifecycle configuration.

Record booleans and the observed non-secret region only. Close the console
without changing state.

## Doppler metadata commands

Use the installed Doppler CLI as the syntax authority. Disable version checks,
environment-derived configuration, debug output, and active-config printing.
Run each pipeline with Bash pipefail enabled. Capture only the final boolean.

```bash
doppler --no-check-version --no-read-env --silent projects --json \
  | jq -e '[.[] | select((.slug // .name) == "homelab-dev")] | length == 1'
```

```bash
doppler --no-check-version --no-read-env --silent \
  environments --project homelab-dev --json \
  | jq -e '[.[] | select(.id == "prd")] | length == 1'
```

The Doppler CLI identifies an environment argument as `environment_id`; its
display name is not the selector. Match the exact JSON `id` field so the
production environment may retain a human-readable name such as `Production`.

```bash
doppler --no-check-version --no-read-env --silent \
  configs --project homelab-dev --environment prd --json \
  | jq -e '[.[] | select(.name == "prd_b2")] | length == 0'
```

Do not use `doppler secrets`, `doppler run`, `doppler configs create`, or a
command that prints the active token or configuration. If `--no-read-env`
prevents authentication, stop and review the authentication source. Do not
remove that flag during execution.

## Acceptance

Accept the preflight only when:

- every Backblaze observation passes without a control-plane mutation;
- all three Doppler pipelines return status zero and boolean `true`;
- `prd_b2` remains absent;
- all Playwright working, profile, log, and snapshot paths were confined to the
  protected evidence directory and raw browser artifacts were removed;
- the evidence contains the approved account region and no excluded data; and
- the operator confirms that no provider, Doppler, Restic, or host state
  changed.

Classify a failed assertion or unexpected existing identity as drift. Stop the
bootstrap workflow and review the desired state. Do not repair, rename, delete,
or create anything during this preflight.

## Result handling

Keep raw evidence outside Git. After execution, a definition-only readiness
transition may record the sanitized decision, evidence hashes, observed
region, and preflight time in the active B2 operation. That transition requires
review and a checkpoint before any live mutation authorization.
