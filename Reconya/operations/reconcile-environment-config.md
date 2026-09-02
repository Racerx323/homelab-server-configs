# ReconYa v0.26.0 environment reconciliation

## Scope

- Target: `J1-SVMF` (`svmf.local.theama.co`)
- Application configuration: `/home/pi/reconya/.env`
- Desired-state source: `../configs/svmf.env.example`
- Backup: `/var/backups/reconya-env-v0.26.0-desired-state-v1`

The operation preserves the existing `LOGIN_USERNAME` and `LOGIN_PASSWORD`
lines without displaying them. It replaces the remaining environment file
with the repository's v0.26.0 desired state, removes inert legacy keys, and
restarts ReconYa so the process loads the new file.

## Desired settings

ReconYa continues to use SQLite at `data/reconya.db` and listen on port 3008.
The operation sets all four outbound lookup controls to `false`. ReconYa uses
the repository-managed IEEE file for vendor data and raises an unreachable-host
alert after six hours.

Public-IP lookup would contact `api.ipify.org`. Geolocation would send that
public IP to `ip-api.com` over plain HTTP. J1-SVMF does not need either service
for local device discovery, so the desired state disables both.

## Preflight and mutation

The deployment entrypoint verifies the host, accepted v0.26.0 binary, current
environment key set, non-secret values, file ownership and mode, service
health, and unused staging and backup paths. It rejects missing, empty, or
duplicate credential lines without printing their values.

The entrypoint creates a root-only backup, copies the original credential lines
into the reviewed template, validates the candidate, and replaces `.env`
through a same-directory rename. It then restarts ReconYa. The separately
installed service workaround sends `SIGINT` and gives ReconYa
15 seconds to finish its graceful shutdown because v0.26.0 ignores `SIGTERM`.

## Acceptance

- The live file has the exact ten-key desired-state set.
- The two credential lines match the root-only backup.
- The file remains owned by `pi:pi` with mode `0600`.
- The ReconYa binary remains unchanged.
- ReconYa remains enabled, becomes healthy, and leaves no failed systemd unit.

## Rollback

Any failure after replacement moves the rejected environment beneath the
backup directory, restores `env.original`, and restarts ReconYa. Rollback must
validate the original legacy key set and application health. The script exits
with a manual-intervention status if it cannot prove both conditions.

This operation does not alter SQLite or OUI data, change credentials, install
packages, modify systemd units, reboot the host, or delete backups.
