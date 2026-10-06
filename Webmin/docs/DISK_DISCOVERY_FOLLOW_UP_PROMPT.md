# Disk-discovery counter troubleshooting prompt

Read the [September 29 diagnosis](DISK_DISCOVERY_DIAGNOSIS.md) before continuing.
The bounded trace identified an `ata_id` ATA identification rejection. A later
approved passive cycle captured Webmin and udev process ancestry, Parted's
read-write close, the change-event sequence and one matching rejection. Read the
diagnosis for remaining attribution limits and the unresolved earlier second
invocation. The [repository-only assessment](DISK_DISCOVERY_CANDIDATE.md) now defines a
Webmin disk-discovery candidate with local regression coverage and deployment
review inputs. The [authorized single-host deployment](DISK_DISCOVERY_DEPLOYMENT_RESULT.md)
passed two scheduled cycles and the final 75-second follow-up without a discovery
counter increment. Polling remained enabled. The older results below retain
their historical scope; do not replay a completed deployment by default.

The corrected October 4–5 passive observation [passed full evidence review](DISK_DISCOVERY_OBSERVATION_RESULT.md)
on October 6. The observer is inactive; monitoring remains enabled. The earlier
incomplete run remains archived separately.

Use this prompt for the separate investigation. The counter finding does not
block the reviewed Nautobot stage-3 baseline decision. No fix is assumed necessary
or proven safe before diagnosis.

```text
Continue the Webmin disk-discovery counter investigation in
/home/aaron/code/homelab-server-configs. Read applicable AGENTS.md and:
- smartmontools/docs/JMICRON_NVME_PROFILE.md
- Webmin/docs/WEBMIN_ARCHITECTURE.md
- Webmin/docs/PATCHED_POLLING_TRIAL.md
- Webmin/docs/DISK_DISCOVERY_DIAGNOSIS.md
- Webmin/docs/DISK_DISCOVERY_DEPLOYMENT_RESULT.md
- /home/aaron/code/.local-evidence/scsi-counter-attribution-20260921/RESULT.md
- The exact probe commands, results, installed Webmin source and private ioctl
  trace retained alongside that report.

Target: ama@10.1.2.170, root disk /dev/sda through JMicron 152d:0583.
Verify identity and current versions before relying on historical state.

Known results: smartctl -i, -H and -A -l error each left ioerr_cnt unchanged.
Webmin's parted /dev/sda unit cyl print reproduced one increment, exited zero
and had no reset, timeout or ext4 error during a 75-second follow-up. This
supports, but does not prove individually, the 287 historical cycle increments.
The September 21 trace did not identify the opcode or sense. A September 29
follow-up captured ATA PASS-THROUGH(12), carrying IDENTIFY DEVICE, from ata_id,
with ILLEGAL REQUEST / INVALID FIELD IN CDB. Do not repeat that completed
reproduction by default; inspect the remaining udev causality and fix-ownership
questions in DISK_DISCOVERY_DIAGNOSIS.md. Issue #648's changing self-test-log
data is not established as the same problem.

Investigate read-only and prepare a fix if justified:
1. Verify retained hashes, source call chain and current configuration. Preserve
   raw evidence privately. Do not publish serials, addresses or hexadecimal dumps.
2. Inspect the matching installed libparted and Raspberry Pi kernel implementation.
   Trace the observed partition-listing ioctls to candidate SCSI commands. Do not
   infer the failing opcode from an EINVAL return alone.
3. Prepare a bounded reproduction that records command results/sense and counter
   changes. Prefer process-scoped tracing; define cleanup for any tracing setup.
   Obtain scoped authorization before new live queries or tracing changes. Wait
   at least 75 seconds after each disk query and stop on reset, timeout, filesystem
   error, failed health or unexpected behavior. Do not start a drive self-test.
4. Assess the narrowest maintainable fix under its owner: avoid an unnecessary
   discovery query, reuse correct discovery data, or handle an unsupported probe
   appropriately. Do not silence counters, remove health coverage or assume
   replacing parted with fdisk is equivalent. Verify partition-table support,
   multi-drive discovery, caching freshness and hotplug behavior as applicable.
5. Implement and test a repository-only candidate where practical. Prepare exact
   deployment inputs, diff, backup, rollback, source/version checks and success
   criteria before requesting production deployment authorization. Do not modify
   partition tables, packages, transport, boot settings or smartd policy casually.
6. Draft a focused upstream report for the responsible project if warranted.
   Keep it separate from #648 unless evidence establishes a common cause. Public
   posting and live deployment require explicit authorization in this conversation.

Keep Nautobot acceptance and unrelated fleet work separate. Do not reboot,
commit, push, or enable/disable scheduled polling under this troubleshooting
prompt. Record observed behavior separately from hypotheses and untested fixes.
```

## Restoring scheduled temperature polling

The completed patched-Webmin/new-kernel observation supports restoration without
requiring this optional discovery fix first. Define a separate Webmin-owned change:

1. Verify the deployed patch, smartctl and kernel identities still match the
   qualified combination; confirm no failed/active observer will race the change.
2. Preserve the exact system-status configuration and its hash. Change only
   `collect_notemp` to the enabled/default behavior, preserving other settings.
3. Review the exact change and rollback, then obtain authorization for execution.
4. Verify actual scheduled health/temperature collection for at least two cycles,
   with at least 75 seconds after the final drive query. Check kernel resets,
   SCSI timeouts, ext4 errors and process/configuration continuity. A lone known
   discovery-counter increment is not itself a new failed-health event.
5. Restore the exact backup if collection is missing/unexpected or storage faults
   occur. Keep smartd monitoring and its existing alert route intact.

This plan describes restoration after the original observer deliberately left
`collect_notemp=1`. Later retained restoration evidence records enablement, and
the September 29 diagnostic execution verified the enabled configuration.
Do not replay restoration without inspecting current state and obtaining its
separate authorization.

## Related combined-device detection diagnostics

The candidate smartctl `sat/sntjmicron` path introduces SAT identification probes
before NVMe fallback. Its counter increments must be separated from this
parted finding; sharing `ioerr_cnt` does not establish a common rejected opcode.
Use the [focused detection procedure](../../smartmontools/docs/CI_COMPARISON.md#separating-detection-errors-from-scheduled-discovery)
for immediate-versus-settled counters and all-ioctl reporting. Keep monitoring
unchanged and retain any unresolved concurrent-process attribution explicitly.

## Webmin relationship and upstream clarification

The retained September 21 source review establishes the call chain:
`system-status::get_current_drive_temps` →
`smart_status::list_smart_disks_partitions` →
`list_smart_disks_partitions_fdisk` → `fdisk::list_disks_partitions`.
The installed implementation selects `parted` when available and not disabled.
Running its partition-listing command separately reproduced one counter increment.
Thus Webmin can trigger this discovery behavior, but the increment does not require
Webmin to be running: it reproduced in the standalone `parted` command.

This distinguishes the triggering caller from the unresolved underlying mechanism.
The matching historical cycle count supports attribution but does not prove each
historical increment, nor the unexplained extra increment in a later observation.
The September 21 trace did not capture the rejected command or sense. The
later bounded trace identified the `ata_id` rejection described above; it did
not capture the helper's triggering udev event. The subsequent passive cycle
captured the process and event sequence described in the diagnosis, with its
stated attribution limits. Neither observation establishes every historical
increment's cause.

The [September 29 smartmontools clarification](https://github.com/smartmontools/smartmontools/issues/648#issuecomment-5894223773)
explains the two smartctl SAT identification rejections and announces a descriptor
match plus later probe refactoring. It does not diagnose or fix this Webmin/parted
path. Keep any Webmin discovery change under the separate investigation above;
do not disable health polling or replace discovery tools based on that comment.
