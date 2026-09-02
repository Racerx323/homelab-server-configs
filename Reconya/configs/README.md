# ReconYa configuration ownership

`svmf.env.example` is the complete, sanitized application configuration for
ReconYa v0.26.0 on J1-SVMF. It records the ten environment variables consumed
by that release and fixes all non-secret values to the accepted environment
policy. The installed `/home/pi/reconya/.env` is derived from this file, but it
is not a byte-for-byte repository artifact because its login credentials are
target-only secrets. The repository ignore rules reject a copied
`Reconya/configs/*.env` secret file while retaining `*.env.example` templates.

The effective-key audit used the v0.26.0 tag resolved to commit
`ef3aba7e7caf565d59b4c10619527445c589a9dd`. The repository template's ten
keys exactly match the environment lookups in that commit's
`backend/internal/config/config.go`.

## Repository-owned files

| Live path | Repository source | Handling |
| --- | --- | --- |
| `/home/pi/reconya/.env` | `configs/svmf.env.example` | Replace the two credential placeholders on the target and install mode `0600`. |
| `/etc/systemd/system/reconya.service` | `templates/reconya.service` | Install byte-for-byte. |
| `/etc/systemd/system/reconya-oui-update.service` | `templates/reconya-oui-update.service` | Install byte-for-byte. |
| `/etc/systemd/system/reconya-oui-update.timer` | `templates/reconya-oui-update.timer` | Install byte-for-byte. |
| `/usr/local/sbin/update-reconya-oui` | `scripts/update-reconya-oui.sh` | Install byte-for-byte. |

## Target-only state

Do not commit these files:

- `/home/pi/reconya/.env`, because it contains login credentials;
- `/home/pi/reconya/data/reconya.db*`, because these are live SQLite state;
- `/home/pi/reconya/data/oui/oui.txt*`, because these are managed registry
  state; or
- `/var/backups/reconya*`, because these are live rollback artifacts.

The binary is also not stored in Git. Its accepted checksum and deterministic
bundle procedure reside in `../manifests/` and `../operations/`.

## v0.26.0 compatibility notes

The v0.26.0 source consumes only the variables in `svmf.env.example`. The
following keys occurred in the pre-reconciliation live `.env` or its stale
`.env.example`, but v0.26.0 does not read them:

- `DATABASE_TYPE`;
- `JWT_SECRET_KEY`; and
- `IPV6_MONITORING_ENABLED`, `IPV6_MONITOR_INTERFACES`,
  `IPV6_MONITOR_INTERVAL`, `IPV6_LINK_LOCAL_MONITORING`, and
  `IPV6_MULTICAST_MONITORING`.

Do not treat `JWT_SECRET_KEY` as an active security control. ReconYa v0.26.0
uses an application-embedded session key instead of an environment setting.
Restrict the web interface to trusted networks and re-audit this boundary when
upgrading ReconYa.

## Accepted J1-SVMF inventory

The read-only audit on September 2, 2026 found no additional ReconYa systemd
drop-ins, systemd-injected environment, or `pi`/root cron jobs. The only named
configuration artifacts under `/etc` and `/usr/local` were the three units and
updater in the ownership table. Their bytes matched the repository.

The production reconciliation later that day installed the ten-key desired
state. A redacted checksum of the live file matches `svmf.env.example`; the
deployment also proved that both credential lines match the root-only backup.
