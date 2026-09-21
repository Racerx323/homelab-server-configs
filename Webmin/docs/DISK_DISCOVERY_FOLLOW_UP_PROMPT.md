# Disk-discovery counter troubleshooting prompt

Use this prompt for the separate investigation. The counter finding does not
block the reviewed Nautobot stage-3 baseline decision. No fix is assumed necessary
or proven safe before diagnosis.

```text
Continue the Webmin disk-discovery counter investigation in
/home/aaron/code/homelab-server-configs. Read applicable AGENTS.md and:
- smartmontools/docs/JMICRON_NVME_PROFILE.md
- Webmin/docs/WEBMIN_ARCHITECTURE.md
- Webmin/docs/PATCHED_POLLING_TRIAL.md
- /home/aaron/code/.local-evidence/scsi-counter-attribution-20260921/RESULT.md
- The exact probe commands, results, installed Webmin source and private ioctl
  trace retained alongside that report.

Target: ama@10.1.2.170, root disk /dev/sda through JMicron 152d:0583.
Verify identity and current versions before relying on historical state.

Known results: smartctl -i, -H and -A -l error each left ioerr_cnt unchanged.
Webmin's parted /dev/sda unit cyl print reproduced one increment, exited zero
and had no reset, timeout or ext4 error during a 75-second follow-up. This
supports, but does not prove individually, the 287 historical cycle increments.
The exact SCSI opcode and sense result remain unknown. Issue #648 concerns
changing self-test-log data and is not established as the same problem.

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

This is a restoration plan, not evidence that polling has been enabled. The
existing observer's normal completion deliberately left `collect_notemp=1`.
