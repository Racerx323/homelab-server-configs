# ReconYa managed OUI updater installation

## Scope

- Target: `J1-SVMF` (`svmf.local.theama.co`)
- Application: ReconYa v0.26.0
- Seed registry: IEEE MA-L text registry, 40,049 `(hex)` records
- Seed SHA-256:
  `e2fa93fcf56ce075e9fc860d47fb7ed1dc35a6e7b2617bea011475d09b804552`
- Schedule: first day of each month, midnight plus up to six hours of random
  delay, with missed-run recovery

The installation adds one updater script, a oneshot service, a timer, and the
reviewed seed registry. It ensures two explicit `false` settings are present in
ReconYa's existing secret `.env` without recording that file or its hash.

## Preflight

The deployment entrypoint fails closed unless:

- it runs as root on `J1-SVMF`;
- ReconYa is active on port 3008, returns HTTP 200, 302, or 303, and has the
  accepted v0.26.0 binary hash;
- the seed registry has its pinned hash and passes the production validator;
- `OUI_DOWNLOAD_ENABLED` and `VENDOR_LOOKUP_ONLINE_ENABLED` are either absent
  from the live `.env` or occur exactly once with the value `false`;
- the target updater, unit, timer, seed, backup, and staging paths are absent;
  and
- the bundle manifest verifies each non-secret deployment input.

## Mutation and recurring authority

The entrypoint backs up `.env` in a root-only directory and adds either missing
setting as `false`. This accepts both an older live file and a fresh file made
from `../configs/svmf.env.example` without creating duplicate keys. It then
installs the reviewed registry and systemd artifacts, reloads systemd, and
restarts ReconYa so it loads the seed. It enables the timer after ReconYa
passes health checks.

Enabling this timer authorizes each scheduled run to:

- contact `https://standards-oui.ieee.org/oui/oui.txt` over HTTPS;
- replace `/home/pi/reconya/data/oui/oui.txt` after validation when its bytes
  change;
- rotate the last accepted registry to `oui.txt.previous`; and
- restart `reconya.service` and roll back the registry if health checks fail.

The timer does not change other ReconYa settings, install packages, update the
ReconYa binary, reboot the host, or remove retained backups.

## Acceptance

- Both live `.env` settings occur once and equal `false`.
- The installed registry matches the seed hash and passes structural checks.
- The updater script and units match the bundle inputs.
- ReconYa is active and returns an accepted HTTP status.
- The timer is active and enabled with a future trigger.
- No failed systemd unit remains.

## Rollback

On failure after mutation, the deployment entrypoint disables the timer, moves
new files beneath `/var/backups/reconya-oui-bootstrap-v1`, restores the original
secret `.env`, reloads systemd, and restarts ReconYa. Rollback must prove
application health and the absence of installed OUI units. Failed candidate
artifacts remain available for diagnosis.
