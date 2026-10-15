# Production baseline and package-source review

Read-only review completed October 14, 2026 for the existing pilot. No package
upgrade is selected: the reviewed distribution package does not contain the
qualified candidate's 512-byte/18-record JMicron log handling.

## Host findings

- Installed package: `smartmontools 7.5-2~bpo13+1`, ARM64.
- Boot identity, smartctl/smartd binaries, smartd configuration, Webmin
  system-status configuration and both production service identities match the
  observation baseline. Both services are active with zero recorded restarts.
- The bridge remains `152d:0583`, descriptor `0213`, using `usb-storage`.
  Stable whole-disk/partition mappings are recorded privately. SCSI `ioerr_cnt`
  is `0x2`; ext4 errors are zero.
- Effective policy remains DEVICESCAN with removable-device selection, standby
  handling, the existing Mailrise recipient and Debian smartd-runner. No explicit
  interval override was found. This differs from the restricted qualification
  configuration; full production behavior still needs qualification.
- No observation unit or pending systemd job appeared in the inspection.
  The bounded smartd journal contains the historical October 4 warning pair,
  with no later occurrence in those retained records. The last 200 kernel rows
  contain no matching storage faults. These tails do not establish complete
  journal coverage or a fresh SMART health assessment.
- Mail and sendmail alternatives resolve to bsd-mailx and msmtp. Their package
  ownership and existing route references were checked; no message was sent.
  Initial ownership lookup did not resolve an alternatives link, so a targeted
  read-only lookup verified the actual executable owners.

## Package and source findings

Official Debian InRelease signatures were verified locally using the installed
host's public Debian archive keyring. Signed SHA-256/size entries verified the
ARM64 Packages and Sources indexes. Release timestamps were checked; backports
metadata is valid through October 21, 2026. No target APT lists were refreshed.

| Reviewed source | Available smartmontools version |
| --- | --- |
| Debian trixie/main, ARM64 and source | `7.4-3` |
| Debian trixie-backports/main, ARM64 and source | `7.5-2~bpo13+1` |
| Official upstream latest-release API | `RELEASE_7_5` |

This is a dated review of these distribution suites, not a claim about every
Debian suite or third-party build. The host's cached package policy agrees with
the independently downloaded indexes. No reviewed distribution upgrade contains
the qualified behavior.

The authenticated backports source still limits the JMicron self-test-log command
to `0x218` (19 records). Its Debian patch series does not change scsinvme.cpp or
smartd.cpp. By contrast, the qualified commit
`06489e03695e0cf0a7366f0d402fbff8763bf3e6` caps protected log transfers at
`0x200` and handles 18 self-test records. The two relevant upstream source blobs
were fetched using their exact Git-tree paths and verified against Git blob
hashes; initial guessed paths returned 404 and were not treated as evidence.
A database-only update cannot supply this compiled behavior.

The exact installed backports archive and source archives were downloaded into
private controller storage and verified against signed index hashes. The package's
smartctl, smartd and bundled database hashes match the installed files; the runtime
database also matches the bundled database. This establishes an available rollback
artifact, not tested downgrade or state-format compatibility.

Static maintainer-script review shows database installation and a systemd
daemon-reload plus start/restart during package configuration. A future package
transaction therefore has a monitoring interruption and database-content boundary
even if the conffile is preserved. No scripts from the downloaded package ran.

## Decision and next stage

On October 14, the user selected retaining production unchanged while waiting
for a suitable authenticated Debian package. Existing monitoring and alerts
remain in place; custom-package preparation is not selected. The
[follow-up action](PRODUCTION_TRANSITION_PLAN.md#follow-up-action-package-and-upstream-status)
is due October 28 to review package availability and upstream issue #648.

Production-policy/state compatibility, any newly selected package's lifecycle,
dependency simulation, alert coverage and permitted monitoring interruption remain
open. The baseline is dated evidence, not an indefinitely valid deployment input.
Refresh it before freezing a future execution bundle. Follow the
[production transition plan](PRODUCTION_TRANSITION_PLAN.md).

No SMART read, foreground smartd, self-test, service action, target APT mutation,
notification, production configuration change, commit or publication occurred.

## Evidence

Private evidence is under
`/home/aaron/code/.local-evidence/smartmontools-production-baseline-20261014/`:
`baseline.json`, `VERIFICATION.json`, `RESULT.json`, signed release/index files,
signature outputs, source/package archives, inspected source and maintainer
scripts, upstream release/tree metadata, and `SHA256.json`.

Official sources are `deb.debian.org/debian` for the reviewed suites and
`smartmontools/smartmontools` for upstream release metadata and pinned source.
Raw device identities, routing details and retained journals remain private.
