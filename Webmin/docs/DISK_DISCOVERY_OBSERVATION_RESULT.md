# Accepted disk-discovery observation

The October 4–5, 2026 passive observation is accepted for the investigated
single-host configuration. Terminal status was checked and the full retained
raw evidence was independently archived and audited on October 6. This extends
the [two-cycle deployment pilot](DISK_DISCOVERY_DEPLOYMENT_RESULT.md); it does
not qualify other hardware, physical RAID or real hotplug.

## Evidence reviewed

- Window: October 4 at 17:56:26 through October 5 at 17:56:30 CDT.
- Duration: 86,404.027 seconds; 1,437 retained samples.
- Maximum sample gap: 60.271 seconds, below the 90-second limit.
- Completed load, disk-used and temperature collections: 287 each, meeting the
  defined minimum of 287. Two-hour checkpoint: 24 each, minimum 23.
- Temperatures: 41–43°C; final temperature 42°C, with expected drive coverage.
- No command-error, SCSI-timeout or ext4 counter change; no matched kernel
  storage/power/OOM fault in any sample.
- Source/configuration hashes, boot, kernel, package identities, topology and
  monitoring-service identities matched the pinned baseline in every sample.
- Cache and history freshness, collection counts, clock continuity and terminal
  settling were independently recalculated from retained samples.
- Settling: 116.924 seconds after the final completed health-cache write, with
  no sampled active disk query or collector.
- Final state: complete, no alert, observer inactive with successful result.
  No monitoring change or rollback was performed.

All 16 archived file hashes matched the source manifest. Observer inputs also
matched the approved bundle; preserved configuration copies matched their pins.
Readback on October 6 confirmed the protected production file hashes, boot,
kernel and Webmin/smartmontools service identities still matched.

Raw archive SHA-256:
`42211e5d4216ea724ab1dcfbd4e185cfaefb1690e21d958583080c6861884a4a`.

The owner-private archive, per-file hash manifest, audit script and audit result
are retained outside Git under
`disk-discovery-follow-up-20260929/terminal-review-20261006`. Existing remote
operation evidence and the earlier failed run were retained; no cleanup, tag,
commit, push or public posting was performed during this review.

## Limits and follow-up

Samples contain normalized health records, not every original cache byte. The
observer checked health flags when collecting them; those original successful
cache inputs cannot be independently reconstructed. The audit verifies the
retained records and the exact observer implementation. Settling uses the
completed health-cache write, not continuous syscall tracing. The passive run
does not prove absence of every partition-tool invocation; the earlier bounded
pilot traced that behavior for two cycles.

The failed September 29 observer remains a separate incomplete result. Its
empty-container parser defect was corrected in local observation tooling, not
in Webmin. It contributes no uninterrupted hours to this accepted run.

The [upstream report](DISK_DISCOVERY_UPSTREAM_DRAFT.md) separates
the deployed patch from the review-only adaptation to current upstream source.
Follow the [upgrade procedure](DISK_DISCOVERY_UPGRADES.md) before changing Webmin.
