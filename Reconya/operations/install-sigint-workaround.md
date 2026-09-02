# ReconYa v0.26.0 SIGINT systemd workaround

## Scope

- Target: `J1-SVMF` (`svmf.local.theama.co`)
- Unit: `/etc/systemd/system/reconya.service`
- Backup: `/var/backups/reconya-sigint-workaround-v1`
- Application binary: unchanged ReconYa v0.26.0

ReconYa v0.26.0 ignores `SIGTERM` and registers its graceful shutdown handler
for `SIGINT`. This operation changes `KillSignal` from `SIGTERM` to `SIGINT`
and changes `TimeoutStopSec` from 10 to 15 seconds. The 15-second limit exceeds
ReconYa's internal 10-second HTTP drain deadline and still bounds a hung stop.

## Preflight and mutation

The deployment entrypoint verifies the J1-SVMF hostname, accepted binary hash,
old and new unit hashes, service health, OUI timer state, and unused staging and
backup paths. It validates the candidate with `systemd-analyze verify` before
changing the live unit.

The entrypoint saves the old unit in a root-only backup, installs the reviewed
unit through a same-directory rename, reloads systemd, and performs one
controlled ReconYa restart.

## Acceptance

- ReconYa logs `Received shutdown signal: interrupt`.
- ReconYa logs `[SUCCESS] Services stopped`.
- The restart log contains no stop timeout or forced kill.
- The restart finishes within 10 seconds.
- ReconYa remains active and enabled, and HTTP returns 200, 302, or 303.
- The OUI timer remains active and enabled.
- The binary hash remains unchanged and no failed systemd unit remains.

## Rollback

Any failure after unit replacement restores the old unit, reloads systemd,
restarts ReconYa, and requires application health. The script preserves the
rejected unit in the root-only backup directory. It exits with a
manual-intervention status when it cannot prove rollback health.

The operation does not alter application configuration, SQLite or OUI data,
credentials, packages, or boot state. It does not remove existing backups or
deployment staging.

## Accepted deployment

J1-SVMF accepted bundle SHA-256
`fbc90c10257cc44ea6acb2c53a08b7a9d03f7aa6fff26c6d902ac2bece820d51` on
September 2, 2026. The controlled restart completed in less than one measured
second and produced both required graceful-shutdown messages without a timeout
or forced kill. The live unit SHA-256 is
`16b99c17b21b0553e1eaeee74720a6429466588ae7d031967ff8b4d344bb8a6e`.
