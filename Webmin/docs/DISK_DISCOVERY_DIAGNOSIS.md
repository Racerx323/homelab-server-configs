# Disk-discovery command-error diagnosis

## September 29 bounded reproduction

The previously unknown rejected command was captured: a separate `ata_id`
process issued ATA PASS-THROUGH(12), carrying ATA IDENTIFY DEVICE, and received
CHECK CONDITION with **ILLEGAL REQUEST / INVALID FIELD IN CDB**. The first
rejection completed about 23 milliseconds after the manual Parted process
exited. This identifies the
submitting process and rejected command; the intervening udev event was not
captured.

The authorized health query passed with status zero and no command-error
increment. The partition listing also returned zero. Its observation recorded
two command-error increments and exactly two nonzero SCSI completions, both
from distinct `ata_id` processes with the result above. The later invocation's
initiating caller remains unresolved; it is not a proven scheduled Webmin cycle.

All 1,131 dispatches paired with completions by device tuple, tags, command bytes
and ordering, without unmatched events or recorded trace loss. All captured
cache-flush commands succeeded. Both queries received at least 75 seconds of
post-query observation. No matched kernel storage faults, SCSI timeout increase
or ext4 error increase was observed. The initial health-query handoff before
five-second sampling is retained in the private timing record; that handoff
was not continuous five-second coverage.

The kernel, patched Webmin sources and enabled polling configuration matched
the retained restoration inputs. Polling remained enabled throughout this
investigation. These checks do not change storage/workload acceptance or prove
every historical counter increment had the same cause.

## Installed rules and passive scheduled-cycle observation

The traced Parted process opened the device read-only and then read-write. It
closed the read-write descriptor shortly before the first `ata_id` dispatch.
Matching Debian systemd/udev source provides this possible event chain:

1. Block-device rules enable watching for `IN_CLOSE_WRITE`.
2. The udev manager handles that event by generating a change event.
3. Persistent-storage rules can invoke `ata_id` for a non-removable USB
   mass-storage disk without an already populated serial property.
4. `ata_id` issues the captured ATA identification command.

The subsequent approved inspection verified the installed block-watch rule and
all `ata_id` rule lines against matching source, an active `IN_CLOSE_WRITE`
watch on the disk, and no local storage-rule override. Package verification
reported no udev changes. The applicable source branch is the generic
non-removable USB disk rule. A populated cached serial does not preclude that
probe: the old database is loaded into a separate event clone, and `usb_id`
imports the serial after the `ata_id` rule.

One passive observation of a normal scheduled cycle captured:

1. A Webmin child loading the collection modules and launching the partition
   listing; Parted opened the disk read-only, then read-write, and closed it.
2. The udev manager reading a close-write notification about 1.3 milliseconds
   after that read-write close, followed by disk and partition change events.
3. A udev-worker child executing `ata_id` between the disk's kernel and completed
   udev messages, which shared the same event sequence number.
4. That helper submitting the same ATA identification command and receiving
   the same rejection. Exactly one counter increment occurred.

All 2,744 SCSI starts paired with completions without unmatched events or trace
loss; only the helper's identification command failed. All cache-flush commands
succeeded. Scheduled `smartctl -i`, `-H` and `-A -l error` exited zero, and the
health/temperature cache was updated without a failed-health marker. The capture
ran about 206 seconds, including 75.94 seconds after the final SMART query.
No matched storage faults, timeout/ext4 counter increase, or protected
configuration, service, boot or global tracing drift was observed.

The process ancestry and event ordering are observed; connecting the notification
to the exact rule evaluation also relies on the matching source. Manager trigger
writes and worker-to-event sequence assignment were not instrumented. The watch
number advanced between initial inspection and capture, and its mapping was not
resampled immediately before the notification. Keep these attribution limits
explicit. This cycle had only one rejection and does not retrospectively explain
the second invocation in the earlier manual reproduction.

The matching source versions reviewed were Parted 3.6-5, util-linux/libblkid
2.41.5-0+deb13u1, systemd/udev 257.13-1~deb13u1 and Raspberry Pi kernel package
1:6.18.50-1+rpt1. These are observed investigation identities, not fleet pins.

The rejected feature ioctls in the earlier userspace trace do not establish
rejected drive commands. The captured SCSI failures came from `ata_id`, while
the cache-flush candidate investigated during source review completed
successfully. The exact command is now observed independently of those ioctl
return values.

## Fix ownership

The [repository-only candidate assessment](DISK_DISCOVERY_CANDIDATE.md) defines
the disk metadata contract, proposed caller boundary, local characterization
results and local regression coverage. A repository-only patch and deployment
review inputs now exist. The [single-host deployment result](DISK_DISCOVERY_DEPLOYMENT_RESULT.md)
records successful bounded qualification of the Webmin discovery change.

The later Webmin fix passed bounded qualification on the investigated host;
that does not establish necessity or safety for other hosts. Webmin owns the
repeated discovery trigger and is the first candidate owner: assess a disk-only
SMART discovery path that avoids unnecessary partition enumeration. Preserve
model/controller identification, stable device links, RAID and multi-drive
membership, hotplug freshness and health coverage; retain GPT/MBR support for
callers that need partitions. Validate those contracts in repository fixtures
before proposing deployment.

Parted owns the writable-open behavior, so a read-only listing path is another
upstream option with broader library impact. Udev owns the generic ATA probe,
which also serves real ATA bridges; an exclusion needs stronger device-specific
evidence than this counter finding. The linked Webmin change has local fixture
coverage and a two-cycle live pilot; physical RAID and fleet qualification
remain separate.

Do not disable udev watching, suppress counters, exclude a generic USB ID, or
substitute `fdisk` without that review. Bridge identifiers can also be shared
with ATA devices. A source change, deployment and public report each retain
their separate scope and authorization boundaries.

Keep smartmontools issue 648's self-test-log finding separate. Capturing an ATA
identification rejection from another caller does not establish a common cause
for self-test-log corruption or all historical increments.

## Evidence and cleanup

Raw traces and source archives remain outside Git in the private
`disk-discovery-follow-up-20260929` evidence directory. The execution record
contains command outputs, counter samples, trace statistics, matched completions,
hash manifests and an unpublished upstream inquiry draft. No serials, raw command
buffers or device addresses belong in a public report.

The trace stage originally reported a cleanup failure because it expected the
instance to remain after `trace-cmd extract`; extraction had already removed it.
The original failure record was preserved. Independent readback proved instance
absence, no diagnostic process residue, and unchanged global tracing, services,
boot and protected files. All 22 transferred file hashes matched before the
owned temporary evidence directory was removed. The reviewed outcome records
this reconciliation separately rather than rewriting the initial result.

The earlier assumption that this `extract` invocation defaults to preserving
the instance was incorrect. Future cleanup must verify whether the owned
instance still exists and handle verified absence without a global reset or
an unnecessary retry. No tracing remains active from this investigation.

The passive stage independently verified all 91 transferred capture files before
removing its owned temporary directory. The private trace instance was absent,
no diagnostic tracing processes remained, and every attached parent process had
`TracerPid` zero. Its private result and unpublished Webmin inquiry draft retain
the exact inputs, hashes, event correlation and attribution limits.
