# ReconYa deployment history

## 2026-09-02: SIGINT shutdown workaround accepted

J1-SVMF accepted deployment bundle SHA-256
`fbc90c10257cc44ea6acb2c53a08b7a9d03f7aa6fff26c6d902ac2bece820d51`.
The installed unit SHA-256 is
`16b99c17b21b0553e1eaeee74720a6429466588ae7d031967ff8b4d344bb8a6e`.
Its effective stop policy is `SIGINT`, a 15-second timeout, and `SIGKILL` as
the bounded fallback.

The controlled restart completed in less than one measured second. ReconYa
logged `Received shutdown signal: interrupt` and `[SUCCESS] Services stopped`;
the restart log contained no timeout or forced kill. The service and OUI timer
remained active and enabled, ReconYa loaded 40,046 OUI entries, local and
controller HTTP checks returned 303, and no failed systemd unit remained.

The accepted v0.26.0 binary hash did not change. The root-only prior-unit
backup remains at `/var/backups/reconya-sigint-workaround-v1`. This operation
did not change the environment, application or OUI data, credentials, packages,
or boot state.

The upstream repair is tracked separately in
[Dyneteq/reconya issue 145](https://github.com/Dyneteq/reconya/issues/145).

## 2026-09-02: v0.26.0 binary accepted

J1-SVMF accepted the v0.26.0 ARM64 binary from deployment bundle SHA-256
`3958660ac7483b8b85988f7486751834e87c2b10a5baf417f1cc11f7fb1a26ed`.
The installed binary SHA-256 is
`0f5bdd5c2198f190316595b235f7c2c2fe828632baf320f773bcb5c2f990c4c3`.
The service passed active, enabled, listener, local HTTP, controller HTTP, and
bounded-log checks. The v0.24.1 rollback snapshot remains at
`/var/backups/reconya/v0.24.1-to-v0.26.0`.

ReconYa v0.26.0 still ignores `SIGTERM`. The systemd unit bounded the accepted
deployment stop at 10 seconds before using `SIGKILL`.

## 2026-09-02: managed OUI updater accepted

J1-SVMF accepted the managed OUI updater from deployment bundle SHA-256
`b0d6a4c514ac11a27540681a9bb650f2ae872a6428ff086fa90cf1fbc014d133`.
The installed IEEE seed SHA-256 is
`e2fa93fcf56ce075e9fc860d47fb7ed1dc35a6e7b2617bea011475d09b804552`.
The validator accepted 40,049 `(hex)` records, and ReconYa loaded 40,046 unique
entries after applying IEEE's three reviewed legacy duplicates.

The live `.env` contains one `OUI_DOWNLOAD_ENABLED=false` entry and one
`VENDOR_LOOKUP_ONLINE_ENABLED=false` entry. The timer is active and enabled;
its first scheduled run is October 1, 2026 at 04:08:17 CDT. The accepted
recurring authority covers the HTTPS download, validation, changed-file
replacement, last-file rotation, ReconYa restart, health checks, and automatic
OUI rollback defined in the bundled operation specification.

The root-only pre-install `.env` backup remains at
`/var/backups/reconya-oui-bootstrap-v1/env.original`. The deployment did not
reboot J1-SVMF or remove either ReconYa backup.

## 2026-09-02: configuration completeness audited

A read-only comparison of J1-SVMF, the repository, and the immutable v0.26.0
source confirmed that the live service unit, OUI units, and OUI updater are
byte-identical to their repository sources. The accepted binary also retains
its pinned v0.26.0 checksum. The source audit resolved the v0.26.0 tag to commit
`ef3aba7e7caf565d59b4c10619527445c589a9dd`.

The audit found that `Reconya/configs/` had no application configuration. The
repository now contains a sanitized J1-SVMF `.env` template and a path-by-path
ownership record. The private live `.env` was not copied, hashed, or changed.
The audit did not display or retain its credential values.

The legacy live file omits three effective v0.26.0 settings whose current
defaults match the new template: public-IP lookup disabled, geolocation
disabled, and a six-hour offline alert threshold. It also retains documented
legacy keys that v0.26.0 does not consume. ReconYa remained active throughout
this read-only audit; reconciling the live `.env` requires a separate reviewed
deployment.

No additional ReconYa systemd drop-ins, systemd-injected environment, or
`pi`/root cron jobs were present. The named configuration files found beneath
`/etc` and `/usr/local` were exactly the repository-owned service, OUI units,
and OUI updater.

## 2026-09-02: production environment reconciled

J1-SVMF accepted the ten-key v0.26.0 environment desired state from deployment
bundle SHA-256
`64db59cc145ad8802de19d7b246d3c5ff5673c0d9a8a449848767b8c420816c1`.
The live file now sets public-IP lookup and geolocation to `false`, and it sets
the unreachable-host alert threshold to six hours. The reconciliation removed
the inert `DATABASE_TYPE`, `JWT_SECRET_KEY`, and `IPV6_*` keys.

The entrypoint preserved both credential lines without displaying them. The
redacted live-file SHA-256 matches the repository template checksum
`ed9fe8121990169539a47bfd9e55f764d94995c272a26eb2a61913a7ac3b364f`.
The root-only backup remains at
`/var/backups/reconya-env-v0.26.0-desired-state-v1/env.original`.

ReconYa and its OUI timer passed active and enabled checks. The binary retained
its accepted v0.26.0 checksum, the local endpoint returned HTTP 303, and no
failed systemd unit remained. The operation did not change credentials,
SQLite or OUI data, systemd units, packages, or boot state.

An earlier bundle, SHA-256
`ac6bca7dd8be3bbb4410e07694217c6235913de27f9b44eed8520a5cb58f94bb`,
failed during read-only preflight because of two `awk` portability errors. It
did not create a backup or change `.env`. Fixture coverage now executes both
validators before bundle preparation.
