# ReconYa v0.26.0 binary update

## Scope

- Target: `J1-SVMF` (`svmf.local.theama.co`)
- Service: `reconya.service`
- Installation: `/home/pi/reconya`
- Current binary: ReconYa v0.24.1, SHA-256
  `75101e776500539b5827ba0300fb3435cc4991cd75fcaa9123cf6206fc68f9d3`
- Candidate binary: ReconYa v0.26.0, SHA-256
  `0f5bdd5c2198f190316595b235f7c2c2fe828632baf320f773bcb5c2f990c4c3`
- Candidate archive: SHA-256
  `31e6ee19536e90c24d676446a950feee3d5e8e53fb6ef429e50568eb916be812`

The transaction replaces only `/home/pi/reconya/reconya-linux-arm64`. It does
not modify `.env`, the systemd unit, or any other service. The service is
stopped while its SQLite data directory and old binary are copied into a
root-only backup directory.

## Compatibility decision

Version 0.26.0 adds an `alerts` table and indexes with `CREATE TABLE IF NOT
EXISTS` and `CREATE INDEX IF NOT EXISTS`. The data snapshot is nevertheless
rollback-coupled to the binary because the candidate writes the database.

Version 0.26.0 ignores `SIGTERM` and listens only for `SIGINT`. The binary
update initially retained the live unit's 10-second forced-stop bound. A later,
separately reviewed operation changed the unit to `KillSignal=SIGINT` and
`TimeoutStopSec=15s` so systemd reaches ReconYa's graceful shutdown path.

Each future binary update must inspect the candidate's signal registration and
perform a controlled stop test. Keep `KillSignal=SIGINT` if the candidate still
ignores `SIGTERM`. Restore the standard `SIGTERM` only when the candidate
handles it, drains HTTP connections, and exits before the configured timeout.

The upstream `.env.example` changed. This binary-only operation preserved both
the live `.env` and `.env.example`. The subsequent configuration audit records
the complete effective v0.26.0 desired state in
`../configs/svmf.env.example`; it does not retroactively broaden this binary
operation.

## Preflight

The deployment entrypoint fails closed unless all of these are true:

- it runs as root on host `J1-SVMF`;
- the service is enabled and active, and a GET of `http://127.0.0.1:3008/`
  returns 200, 302, or 303;
- the current binary is a regular, non-symlink ARM64 ELF with the exact v0.24.1
  checksum;
- the candidate archive and extracted binary have the pinned checksums and the
  archive has only the expected two regular files;
- `/home/pi/reconya/data` is a real directory, not a symlink;
- the root-only backup directory does not already exist; and
- the two root paths reserved for bundle upload and extraction do not exist.

## Mutation and acceptance

Upload the exact authorized bundle to
`/root/reconya-v0.26.0-update.tar.gz`, verify its authorized SHA-256 on the
target, and extract it into `/root/reconya-v0.26.0-bundle`. Run the bundled
`deploy-reconya-update.sh` with `/bin/bash`; do not stream or substitute a
controller-side copy. The entrypoint stops `reconya.service`, takes the
stopped-state snapshot, replaces the binary through a same-directory rename,
starts the service, and accepts the update only when:

- the installed checksum is the pinned v0.26.0 binary checksum;
- `reconya.service` is active and enabled;
- port 3008 is listening; and
- a normal HTTP GET returns 200, 302, or 303.

No reboot is part of this operation.

## Rollback

After the service has been stopped, any failure invokes rollback. The script
moves the candidate binary and candidate-mutated data beneath the root-only
backup directory so they remain available. It restores the v0.24.1 binary and
stopped-state data snapshot, then requires the same service and HTTP checks. If
rollback cannot prove those checks, the script exits with a
manual-intervention error and preserves each artifact.

Backup root:

```text
/var/backups/reconya/v0.24.1-to-v0.26.0
```

## Authorization boundary

Preparing and inspecting the bundle is read-only with respect to J1-SVMF.
Uploading the bundle, stopping or starting the service, creating the backup,
replacing the binary, and allowing v0.26.0 to update its database require one
authorization bound to the exact final deployment-bundle SHA-256.
