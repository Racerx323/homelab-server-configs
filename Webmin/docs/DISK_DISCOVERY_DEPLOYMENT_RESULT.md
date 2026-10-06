# Disk-only discovery: single-host deployment result

## Accepted scope

The user-authorized September 29 deployment and bounded qualification completed
successfully on the single investigated host. The three candidate Webmin library
files remain installed. This accepts the observed scheduled polling behavior on
that host; it does not qualify other hardware, physical RAID, real hotplug,
long-term reliability, fleet rollout, or Nautobot/Restic storage acceptance.

The [candidate](DISK_DISCOVERY_CANDIDATE.md) and
[deployment procedure](DISK_DISCOVERY_DEPLOYMENT.md) describe the change and
recovery boundaries. The qualified basic SMART polling and configured RAID
modifications were retained. Polling stayed enabled, smartd and its alert route
were unchanged, and no manual drive query, self-test, restart, package operation,
reboot, commit, push or public posting was performed.

## Observed qualification

| Check | Observed result |
| --- | --- |
| Source baseline and installation | Exact before hashes matched; all three after hashes matched the candidate manifest. Ownership and modes were preserved. |
| Runtime source loading | Two distinct scheduled collectors loaded the installed module paths. |
| Scheduled collection | Two complete cycles, about five minutes apart, each with identification, health and attributes/error-log queries exiting zero. |
| Discovery commands | No Parted/fdisk partition listing; two harmless Parted version checks remained. |
| Temperature and health | Both scheduled temperature-history records were 43°C; corresponding health-cache updates had no failed-health/error marker. |
| Observation | About 668 seconds after installation, including 75.91 seconds after the final query; maximum sample gap about 2.21 seconds. |
| Command-error counter | No increase during qualification. |
| Device trace | All 9,043 starts paired with completions; no failed completion, unmatched event, overlapping pairing key or recorded trace loss. |
| Storage and continuity | No matched kernel storage fault, timeout/ext4 counter increase, or boot, service, protected configuration or global tracing drift. |
| Recovery | Rollback was not needed. Exact live backups and their hashes were independently verified. |
| Cleanup | Private trace instance absent, observer inactive, no diagnostic tracer process, attached parent tracer IDs zero, and no source staging files remaining. |

This closes the scheduled-discovery acceptance criteria for this bounded pilot.
It does not assign the unexplained second invocation from the earlier manual
experiment or establish the cause of every historical increment.

## Exact inputs and retained recovery

The installed before/after hashes are in
[`disk-only-discovery.json`](../patches/disk-only-discovery.json).

- Candidate source bundle SHA-256:
  `a7aedf3f7641258018e54bfdbca635456230c668706a1a36868056de229d1b9d`.
- Target-bound execution bundle SHA-256:
  `b4a2b28cd679097cba116707f1480902c5d3ee39c2d75731c6aab55704f1c3e6`.

The private `disk-discovery-follow-up-20260929` evidence archive contains the
execution specification, exact programs, preflight, source backups, query and
SCSI traces, health/history records, independent review and terminal hashes.
All 184 transferred capture files matched their remote hashes. Raw identifiers,
addresses, configurations and command buffers remain outside Git.

The root-owned mode-0700 remote directory
`/var/lib/webmin-disk-discovery-20260929` retains evidence and live source backups
under `backup/`. It contains no active observer. Keep these recovery inputs until
an explicit retention decision; do not substitute the repository fixture copies
for the verified live backups. Any later rollback or deployment is a separate
live operation and must recheck current source/configuration state.

## Passive follow-up

The corrected October 4–5 passive observation [passed full evidence review](DISK_DISCOVERY_OBSERVATION_RESULT.md)
on October 6. The observer is inactive; monitoring remains enabled. The earlier
incomplete run remains archived separately.
