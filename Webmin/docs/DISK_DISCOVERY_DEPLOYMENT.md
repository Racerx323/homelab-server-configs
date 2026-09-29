# Disk-only discovery deployment review inputs

This procedure defines the deployment review boundary. The separately authorized
[single-host execution result](DISK_DISCOVERY_DEPLOYMENT_RESULT.md) records the
completed pilot. This document itself authorizes no target contact, file transfer,
restart, polling change, deployment or posting.
The target remains the single investigated Webmin host in the private operation
record. Fleet deployment is excluded.

## Exact input preparation

The reviewed diff is `Webmin/patches/disk-only-discovery.patch`. The adjacent
JSON pins its SHA-256 and the before/after hashes of all three affected files:

- `/usr/share/webmin/fdisk/fdisk-lib.pl`
- `/usr/share/webmin/smart-status/smart-status-lib.pl`
- `/usr/share/webmin/system-status/system-status-lib.pl`

Run the local preparer from the repository root with a verified source copy:

```sh
python3 Webmin/scripts/prepare-disk-discovery-candidate.py \
  Webmin/tests/fixtures/disk-discovery/baseline /tmp/webmin-discovery-review
```

The output directory must be new. The resulting deterministic `candidate.tar`
contains exact before/after sources, diff, source manifest, this procedure and
file checksums. Its printed SHA-256 identifies review inputs, not authorization
or live acceptance. Fixtures reproduce retained installed sources; they are not
an instruction to overwrite a drifted host with old files.

## Preflight for a later authorized deployment

Require the exact reviewed bundle hash, target and time window in that approval.
Bind a final execution specification to this bundle before execution. Preflight
must abort on any mismatch or active/incomplete conflicting observer.

1. Verify target/root-device identity, boot, running kernel, Webmin, udev,
   Parted and smartctl versions against the qualified private record. Compare
   all three installed sources with the manifest's `before` hashes; preserve
   the existing basic SMART query and configured RAID modifications.
2. Capture exact system-status and smart-status configuration, smartd policy,
   enabled polling state, service PIDs, current scheduled collector state,
   kernel journal cursor, health/temperature history and storage counters.
   An unexpected configuration, health result or active disk query stops work.
3. Verify staging capacity, source owner/group/mode and absence of symlinks.
   Stage the exact `after` bytes privately on the same filesystem as each
   destination. Validate Perl syntax with the installed Webmin include paths
   in an isolated check; do not invoke the disk functions for syntax checks.
4. In the agreed gap between scheduled collections, verify no active collector
   can consume a partial source update. Prior evidence showed each collector
   loading these modules from files; verify that loading behavior still holds.
   If a restart, schedule change or additional tracing is required, define it
   explicitly before execution rather than inferring permission here.

## Backup and installation order

Before replacing anything, create one root-owned mode-0700 backup directory
whose exact path is recorded in the execution specification. Copy the three
installed sources preserving owner/group/mode and retain their hashes and
metadata. Preserve exact configuration backups for continuity evidence; this
candidate changes no configuration. Verify every backup against the live
`before` hash. Do not rely on the bundle's reference sources as the rollback
backup.

Replace sources in dependency order: **fdisk, smart-status, system-status**.
For each file, verify its expected current hash again, copy the candidate bytes
into a same-directory temporary regular file, set the recorded original
owner/group/mode, verify the `after` hash, then atomically rename it over that
single destination. Never patch a live source file in place. Verify all three
hashes immediately afterwards. This is three atomic replacements, not a
multi-file transaction; any failure requires restoring already replaced files.
Record each completed replacement so rollback does not guess partial state.

## Acceptance observation

Observe at least two actual scheduled collection cycles, followed by at least
75 seconds after the final drive query. Any process/device tracing used to
collect this evidence needs its exact scope and cleanup in the final execution
specification. No extra manual disk queries or self-tests are implied.

- Each expected drive and configured physical RAID member remains represented;
  SMART identification, health, basic attributes and error-log coverage remain.
  Check the actual query arguments and resulting temperature/health history.
- The scheduled disk-only path issues no Parted/fdisk partition listing and
  does not silently fall back to it. A Parted version check during module
  initialization is possible and is not a partition query.
- Attribute counter changes to their submitting process. Success for this
  candidate means no discovery-induced ATA identification rejection; an
  unrelated `ata_id` invocation must not be hidden or automatically blamed on
  scheduled collection.
- No resets, timeouts, filesystem errors, failed health, incomplete discovery,
  missing collection or unexpected source/configuration/process drift occurs.
- No new diagnostic tracing remains after cleanup. Polling stays enabled and
  the independent smartd alert route remains intact.

Synthetic fixtures qualify code paths, not physical RAID hardware or real
hotplug. This pilot cannot establish fleet-wide behavior or resolve historical
unattributed rejections.

## Rollback and postconditions

On an installation failure, failed/incomplete collection or storage fault,
restore every replaced source from the verified live backup in reverse order:
**system-status, smart-status, fdisk**. Use same-directory temporary files and
atomic rename, preserving original owner/group/mode. Compare each restored
file to its recorded `before` hash. Leave monitoring configuration untouched.
Do not restore an unrelated administrator change: a source that matches neither
its recorded before nor after hash requires an explicit conflict report.

Verify the next scheduled collection loads restored sources, produces the
expected health/temperature history, and completes the 75-second follow-up.
Retain evidence and backups through acceptance/rollback review. A restore of
file bytes alone is not proof that a running process uses the restored code.
If process continuity or storage faults prevent this verification, report
rollback as unverified and stop; do not silently restart services or disable
polling.
