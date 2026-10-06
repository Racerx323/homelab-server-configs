# Webmin report and patch proposal

Published on October 6 as [webmin/webmin#2869](https://github.com/webmin/webmin/issues/2869).
The [publication record](DISK_DISCOVERY_UPSTREAM_PUBLICATION.md) records payload
verification and the distinction between installed and proposed patches. The
reviewed source text below is retained; its patch/test content was embedded in
the issue. No pull request has been created.

## Proposed title

Avoid partition enumeration during scheduled SMART temperature collection

## Proposed report body

Scheduled drive-temperature collection currently requests the complete disk and
partition inventory even though it only needs SMART-capable disk metadata.
On a JMicron USB/NVMe setup, the resulting Parted listing triggers an unrelated
udev identification probe that the bridge rejects. Could the scheduled path
request fresh disk metadata without enumerating partition tables?

The reviewed call chain is:

```text
system-status::get_current_drive_temps
  -> smart_status::list_smart_disks_partitions
  -> list_smart_disks_partitions_fdisk
  -> fdisk::list_disks_partitions
  -> parted partition listing
```

The investigated combination used Webmin 2.670, Parted 3.6-5,
udev 257.13-1~deb13u1, smartmontools 7.5-2~bpo13+1 and kernel
6.18.50+rpt-rpi-v8. The root disk was an NVMe drive behind a JMicron 152d:0583
bridge using usb-storage. These are the tested identities, not requirements for
all installations.

A bounded manual partition listing returned success but was followed by two
command-error increments. Tracing identified the failed command as a separate
`ata_id` process issuing ATA PASS-THROUGH(12), carrying ATA IDENTIFY DEVICE,
with CHECK CONDITION / ILLEGAL REQUEST / INVALID FIELD IN CDB. SMART identity,
health and attribute/error-log queries did not reproduce that increment.

A later passive capture of one normal scheduled cycle observed Webmin launching
Parted, Parted opening the disk read-write and closing it, a udev close-write
notification, disk/partition change events, and a udev-worker child launching
`ata_id`. That helper issued the same rejected command; exactly one counter
increment occurred. All 2,744 SCSI starts paired with completions, without
recorded trace loss. SMART queries and cache-flush commands succeeded, and no
matched storage fault or timeout/ext4 counter increase followed.

The source-backed explanation is Parted's writable close triggering udev's
block-device watch and persistent-storage identification rules. Attribution is
not absolute: manager trigger writes and exact worker-to-event assignment were
not instrumented; the watch mapping was not resampled immediately before the
notification. The second invocation in the earlier manual reproduction remains
unexplained, as do individual historical counter increments.

### Proposed change

Add an optional disk-only discovery path for scheduled SMART collection:

- `fdisk`: reuse disk classification, stable IDs and model/controller metadata;
  return a fresh inventory without partition/geometry queries or use of the
  full partition cache. Fail explicitly on missing or changing metadata.
- `smart-status`: pass the option through while preserving configured and
  detected RAID member expansion, device identity and passthrough arguments.
- `system-status`: select that path only for scheduled temperature collection.

Default partition-management callers retain their existing discovery path.
Health/attribute/error-log queries are unchanged. The change neither suppresses
counters nor disables udev watching, health polling or smartd. A generic bridge
ID exclusion or replacing Parted with another tool is not proposed.

The patch shares existing metadata code between both paths. The diff therefore
contains moved code as well as the new option; maintainers may prefer a different
helper layout. The intended behavior is limited to avoiding unnecessary
partition enumeration for this caller.

### Validation and limitations

The deployed baseline patch passed local discovery fixtures covering GPT/MBR,
partition-cache isolation, multiple device types, changed inventory/IDs/models,
and simulated disappearance and RAID expansion. Its two-cycle live pilot
recorded six successful SMART queries, no partition listings, no command-error
increase and 75.91 seconds of final query settling.

After a controlled reboot, a separate 24-hour passive run retained 1,437 samples
and 287 scheduled collections. Temperatures were 41–43°C; no command-error,
timeout or ext4 counter increased, and no matched kernel storage/power/OOM fault
was recorded. Protected identities and configuration remained stable. The final
health-cache write was followed by 116.92 seconds of settling. The full retained
evidence was archived and independently audited.

The passive run did not continuously trace processes and does not establish
absence of every Parted invocation. It qualifies one host, not physical RAID,
real hotplug or other operating systems. The upstream adaptation below has only
local tests and has not been deployed. Local observation-parser fixes are not
part of the proposed Webmin patch.

### Related reports

Webmin #2838 addressed narrower SMART queries for scheduled temperature
collection. This proposal addresses the separate partition-discovery step.
The adaptation retains the model-name boundary correction associated with
Webmin #2859; it must not turn ordinary disk models containing `9750` into RAID
controllers. This report is separate from smartmontools #648: the discovery
trace does not establish a common cause with its changing self-test-log data.

## Review-only attachments and source review

On October 6, upstream `master` was reviewed at:
`11be3726f7679b6ad87d9b9a8f02ff887fe1b1f6`.
Its version file says 2.670, but its SMART-discovery source differs from the
installed 2.670 baseline. Version equality alone is not a patch-compatibility test.
At that revision, scheduled collection still requests full partition discovery;
no equivalent disk-only option was present in the three reviewed modules.

Searches of issues and PRs in `webmin/webmin` used `parted`, `ata_id`, `JMicron`,
`"disk-only"`, `"list_disks_partitions"` and `"drive temperature"`. All returned
result pages fit within the requested 100-item bounds. No exact duplicate was
identified among those results; this is a scoped search, not proof none exists.
The search responses and exact source files remain in the private review archive.

- [Deployed baseline patch](../patches/disk-only-discovery.patch): retained
  unchanged; does not apply cleanly to the reviewed upstream source.
- [Upstream adaptation](../patches/disk-only-discovery-upstream.patch): applies
  without fuzz to the pinned upstream revision and preserves its `9750` fix.
- [Upstream source/hash manifest](../patches/disk-only-discovery-upstream.json):
  before/after hashes and review-only state; not a production deployment input.

The adaptation passed 13 existing discovery fixture tests against the pinned
upstream source and 28 Perl assertions, including six checks for an ordinary
`ST9750420AS` model. The production preparer test was excluded from this upstream
run because it intentionally accepts only the deployed baseline; its manifest
and deployment path were not repointed to upstream. Raw test logs remain private.

Source references for review:

- GitHub repository: `webmin/webmin`, commit `11be3726f7679b6ad87d9b9a8f02ff887fe1b1f6`.
- Changed paths: `fdisk/fdisk-lib.pl`, `smart-status/smart-status-lib.pl`,
  `system-status/system-status-lib.pl`.
- Related issues: `webmin/webmin#2838` and `webmin/webmin#2859`.

The upstream head and duplicate search were rechecked before the authorized
publication. Raw traces, configurations, serials, private addresses and command
buffers remain private. Any later public follow-up or pull request requires
its own authorized scope.
