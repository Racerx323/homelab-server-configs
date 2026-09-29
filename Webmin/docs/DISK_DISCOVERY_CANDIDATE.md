# Disk-only SMART discovery assessment

## Decision and scope

The disk-only discovery change is implemented in
[`disk-only-discovery.patch`](../patches/disk-only-discovery.patch), with exact
baseline/output hashes in the adjacent JSON manifest. It adds an explicit
scheduled-polling option and shares the existing metadata code between the
disk-only and full partition paths. The user-authorized single-host deployment
has now passed bounded qualification; see the
[deployment result](DISK_DISCOVERY_DEPLOYMENT_RESULT.md). Broader hardware and
fleet qualification remain separate.
The [diagnosis](DISK_DISCOVERY_DIAGNOSIS.md) supports avoiding repeated partition
enumeration during scheduled SMART collection. It does not establish that
changing transport probing or udev policy is necessary.

The assessment and candidate use the retained installed Webmin 2.670 sources and their
previously verified hashes. The implementation stage made no live connection; the later deployment and
qualification used separate explicit authorization. The qualified SMART
polling patch and configured RAID support in those sources must be preserved;
a stock-version label alone is not an adequate patch baseline.

## What the existing code requires

The following locations refer to the retained installed source, not a current
upstream branch.

| Consumer or producer | Relevant contract |
| --- | --- |
| `system-status-lib.pl:446`, `get_current_drive_temps` | Uses each disk's device and passes the whole record to `get_drive_status(..., 1)`. It consumes temperature, errors and health results, not partitions or geometry. |
| `smart-status-lib.pl:352`, `get_drive_status` | Retains NVMe controller fallback, identification, health and basic attributes/error queries. |
| `smart-status-lib.pl:622`, `get_extra_args` | Needs the supplied record's `subtype` and `subdisk` for passthrough, plus existing configuration. Omitting the record can cause another discovery call. |
| `smart-status-lib.pl:54`, Linux discovery adapter | Uses `device`, `type` and `model` to distinguish ordinary drives, 3ware/AMCC, LSI and cciss. Carries descriptions and stable IDs into returned records. |
| `smart-status-lib.pl:231` and `:279` | Adds configured RAID members and deduplicates by device, subtype and subdisk. Device-only deduplication would lose physical members. |
| `fdisk-lib.pl:45`, `list_disks_partitions` | Enumerates kernel devices, builds ID mappings, parses partition-tool output, then enriches models. Disk objects are currently created inside the partition-output parser. |
| `fdisk-lib.pl:603` onward | IDE and SCSI model enrichment is largely proc/sysfs based. This metadata is needed even when partition geometry is not. |

Removing the external command alone would therefore return no disk objects.
Replacing the whole adapter with a list of device names would bypass RAID
selection and can reduce health coverage. A generic `sd*` scan would also lose
existing IDE, NVMe, MMC, legacy controller and fallback behavior.

## Concrete candidate design

1. Add an explicit disk-only option through the scheduled temperature caller,
   SMART discovery wrapper and Linux adapter. Existing no-argument callers keep
   their full-record behavior. Preserve the BSD/fstab fallback paths; this
   candidate targets the Linux fdisk provider.
2. Introduce a disk-metadata provider under Webmin's fdisk module, sharing device
   classification, descriptions, ID mapping and model/controller enrichment
   with full partition discovery. Populate records from kernel metadata rather
   than synthesizing fake Parted output. Do not invent geometry or label an
   uninspected partition table as empty.
3. Run the existing SMART adapter's RAID expansion, configured-member merge,
   sorting and deduplication over those metadata records. Continue passing each
   resulting record to `get_drive_status`; retain its current query flags and
   health parsing.
4. Keep full partition parsing available to partition-management callers.
   Separate its cache from disk-only records so a SMART request cannot populate
   an empty partition list that a later partition caller mistakes for complete
   discovery.
5. Refresh the disk-only inventory and ID mappings on every collection. Do not
   reuse `@list_disks_partitions_cache`: it returns any existing nonempty list
   before enumeration and has no hotplug freshness check in this function.
   A disk removed or replaced during collection must not inherit another
   device's cached controller metadata. Explicitly handle incomplete discovery
   rather than reporting an apparently successful empty health collection.

The candidate adds `list_smart_disks_partitions(1)` for the scheduled caller
and forwards that option to `fdisk::list_disks_partitions(undef, 1)`. Existing
no-argument behavior is retained. Shared per-invocation closures contain the
original classification, ID assignment and model enrichment logic.

The disk-only path checks inventory readability and consistency, snapshots
node/sysfs identity before ID mapping, and rechecks identity after enrichment.
It returns fresh metadata without `parts`, `table` or geometry claims and never
reads or populates the full partition cache. Missing SCSI/RAID models and empty
automatic RAID expansion fail explicitly; there is no hidden Parted fallback.
That failure can abort a collection and is a rollback condition, not evidence
of acceptable monitoring coverage. Identity checks narrow races during discovery;
they cannot eliminate removal after return or make multiple kernel reads atomic.
A Parted version check at module initialization remains possible.

## Local checks and implementation gates

Nine local characterization checks passed against extracted, unchanged SMART
functions with synthetic disk/controller providers. They cover multiple disks
(including a multi-letter SCSI name), stable IDs, LSI physical members, passthrough
arguments, configured-member deduplication and addition, cciss, 3ware, and changed
provider inventory across calls. Exact source hashes, harness and output remain
in the private investigation's `repository-assessment` directory.

Those nine checks established the baseline contract. The candidate now passes
14 Python regression tests, including 22 Perl assertions for RAID and scheduled
collection. Tests apply the actual patch to hash-pinned source fixtures and
compare full partition-parser results against the unchanged baseline. They
cover the following contracts with synthetic trees and canned tool output.
The later live pilot qualified two scheduled cycles on the investigated host.
Other hardware, actual partition-media regression and live hotplug remain
unqualified:

| Fixture or check | Required result |
| --- | --- |
| GPT, MBR, extended partitions, unpartitioned disks | Disk-only discovery does not depend on table contents; full discovery retains accurate partitions and geometry. |
| Mixed USB/SATA, native NVMe, multiple namespaces, IDE/MMC, legacy controller names | Preserve existing inclusion, ordering and transport/controller metadata; do not broaden device coverage accidentally. |
| 3ware/AMCC, LSI, cciss and configured passthrough | Preserve physical-member identity and exact SMART arguments, including subdisk zero and shared controller paths. |
| Disk-only then full discovery, and reverse order | No incomplete-record cache contamination or mutation of shared returned objects. |
| Add, remove, replace under the same device name; delayed/missing ID links | Fresh enumeration and correct identity or an explicit incomplete result, with no silently lost health coverage. |
| Missing proc/sysfs metadata and controller utilities | Defined failure/fallback behavior; no false empty success or guessed RAID mapping. |
| Invocation tracing in an isolated fixture environment | No partition-tool invocation or block-device open from the metadata provider; existing SMART health calls remain. |

The retained library also contains pre-existing behaviors outside this proposed
fix: for example, VirtIO disks are classified separately and the SMART adapter's
ordinary-disk branch selects SCSI/IDE records. Do not silently change that policy
while claiming equivalence. Real hardware and scheduled-cycle qualification are
later deployment checks, not results of these synthetic fixtures.

## Deployment boundary

The [deployment review procedure](DISK_DISCOVERY_DEPLOYMENT.md) defines exact
source/version checks, backup, dependency-ordered installation, reverse-order
rollback and two scheduled-cycle acceptance with a 75-second follow-up. The
[offline preparer](../scripts/prepare-disk-discovery-candidate.py) generates a
deterministic bundle of the before/after sources, diff, manifest and procedure;
it rejects baseline drift and never contacts a target. The separately approved
target-specific execution and its outcome are recorded in the
[deployment result](DISK_DISCOVERY_DEPLOYMENT_RESULT.md). Future deployment or
rollback still requires fresh preflight and scoped authorization. Keep polling
and independent smartd monitoring intact.
