# Application credential preparation

The selected references are recorded in
[credential-preparation.json](../manifests/credential-preparation.json).
This document records the preparation contract. The completed provisioning
outcome is recorded separately in [credential-result.json](../manifests/credential-result.json). Use Doppler project `homelab-dev`,
environment `prd`, config `prd_nautobot`; use administrator `admin`. The approved
email is retained in private bootstrap inputs. Do not copy the email or passwords
into public execution evidence. No production values are present in this repo.

## Exact provisioning scope

1. Recheck the exact project/environment and config list using the authenticated
   controller session and TLS-verified `https://api.doppler.com`. Read names only
   for absence/inheritance checks. Unknown response shapes, permission failures
   or timeouts do not prove absence. The preparation observation found no target
   config and only DOPPLER_CONFIG, DOPPLER_ENVIRONMENT and DOPPLER_PROJECT in prd.
2. Create only `prd_nautobot` in existing `prd`; do not create projects, tokens,
   integrations, environments or modify shared `prd`. Intended CLI:
   `doppler configs create prd_nautobot --project homelab-dev --environment prd`.
3. Refuse if any of the four application keys already exists, including inherited
   keys. Review an existing config instead of replacing it. Generate independent
   cryptographically random values: 64 random bytes encoded as hex for Django,
   32 bytes each for PostgreSQL, Redis and the one-time administrator password.
4. Write only the four exact keys from the manifest. Supply values through a
   protected anonymous descriptor or explicitly cleaned 0600 temporary input,
   never command arguments, environment dumps, shell tracing or build files.
   Suppress and boundedly discard CLI response bodies: write APIs can return
   secret values even when the requested operation is just storage. Do not rely
   on `--silent` as secret redaction.
5. Verify the four names and privately compare returned values with generated
   values in memory. Persist only success/failure and non-secret operation
   metadata; no values or password hashes. Inspect name/response shapes explicitly.
6. On an ambiguous write, preserve the config and investigate. Do not regenerate,
   rotate or delete automatically. Once verified, Doppler is the recovery source.
   A separately reviewed rollback may delete only newly created keys/config after
   establishing no consumer uses them. Never delete the shared environment.

The [provisioning implementation](CREDENTIAL_PROVISIONING.md) and its
failure/secret-cleanup tests are now prepared for exact-bundle review. This preparation does not include that
live action or a host-injection action. The repository AGENTS.md requires scoped
exact-bundle authorization for live mutation.

## Runtime delivery contract

The persistent services consume only the first three logical credentials; the
administrator password is consumed by one-time bootstrap only. Use the manifest's
consumer lists to prevent cross-service distribution. Keep existing B2/Restic
credentials with their owning configuration.

The existing runtime candidate expects protected service environment files owned
by UID 999, mode 0600, a non-secret settings file owned by UID 999, mode 0644, and
Podman secret `nautobot-redis-config`. PostgreSQL requires POSTGRES_PASSWORD; Redis
requires an authenticated health probe (REDISCLI_AUTH) and a protected requirepass
configuration. App database/cache settings must resolve the same passwords and
Django key without embedded values. Final variable names and settings must be
verified against the qualified Nautobot version before injection; generating
Quadlets alone does not validate those settings.

Review each generated environment file and Redis secret for escaping and newline
handling using disposable fixture values. Validate configuration loading, plugin
enablement and bootstrap behavior in a separately scoped environment. Bootstrap
must refuse an existing administrator rather than reset it, avoid outputting the
password, and remove transient bootstrap inputs even after failure. Do not leave
bootstrap credentials in web/worker/scheduler environments.

## Runtime image prerequisites

[Runtime inputs](../manifests/runtime-inputs.json) use the qualified OCI manifest
digest, not the local image ID or a mutable tag. Load the independently verified
archive into the runtime account's store only in a separate operation, then verify
its manifest identity and local digest reference before `Pull=never` startup.
If Podman cannot resolve that exact local reference after load, stop and reconcile
it; do not substitute a tag or silently pull from a registry. Data-service images
also require their pinned ARM64 identity checks. Image retention and old build
store cleanup remain separate from runtime installation.

The runtime launcher remains inactive. Actual settings, executable stage schema,
secret injection, backend firewall checks and pre-data backup/restore gates must
be complete before pilot deployment. No DB migration, administrator creation,
Caddy publication or Restic initialization is authorized by this document.

Reference: [Doppler CLI commands](https://github.com/DopplerHQ/cli/blob/master/_autodocs/api-reference/cmd.md).
