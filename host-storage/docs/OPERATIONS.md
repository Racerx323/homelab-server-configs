# Host storage operations

## Select and inspect

Set `storage.root.transport_profile: rpi4-x872-usb-storage` only after identifying
the host's actual hardware. Keep the profile's kernel token out of host files.
The current backend discovers the root partition and walks its sysfs ancestors;
it does not assume `/dev/sda` or treat a USB hub as the storage bridge.

Create a private operation JSON outside Git matching
[the schema](../schemas/operation.schema.json). Supply an operation ID, inventory
host, explicit SSH address/user, an unused backup path shaped as
`/boot/firmware/cmdline.txt.host-storage-OPERATION.bak`, and these initial values:

```json
{
  "expected_boot_id": "",
  "expected_root_uuid": "",
  "expected_boot_sha256": "",
  "proposed_boot_sha256": "",
  "authorize_apply": false,
  "authorize_reboot": false,
  "authorize_rollback": false,
  "recovery_confirmed": false,
  "expect_new_boot": false
}
```

These are fields to merge with the operation identity, not a complete executable
operation. Do not place serials, addresses or raw kernel logs in public reports.
Keep evidence beneath a private parent outside Git; every run creates a new
0700 directory and refuses existing paths. Host keys must already be verified.

```sh
python3 host-storage/scripts/run-operation.py --stage preflight   --operation /PRIVATE/operation.json --evidence /PRIVATE/preflight
```

Inspect `preflight-observed.json`, `boot.diff` and `proposed-operation.json`.
Review root UUID/USB ancestry, expected driver, persistent/running quirk and
whether a reboot is actually required. Validate recovery access via an established
independent console; a true boolean is an operator attestation, not an automated
console test. Record exact manual recovery steps and availability constraints
alongside the operation. Review all attached matching USB devices because this
quirk matches vendor/product, not serial number.

## Review and execute a later authorized operation

Use the proposed operation, set only the explicitly authorized stage flags, and
confirm recovery. Generate the digest **after** these changes:

```sh
python3 host-storage/scripts/run-operation.py --stage bundle   --operation /PRIVATE/reviewed-operation.json
```

The digest covers the operation, selected inventory and all component inputs.
Any edit requires a new digest/review. Record exact target, command, boot diff,
backup path, recovery method and later unauthorized stages. Maintain one active
transport operation per deployment stream. Do not create a parallel operation
while a previous one awaits terminal disposition.

```sh
python3 host-storage/scripts/run-operation.py --stage apply   --operation /PRIVATE/reviewed-operation.json   --approved-bundle REVIEWED_SHA256 --evidence /PRIVATE/apply
```

The role repeats preflight, rejects drift, preserves the exact boot file bytes and
owner/group/mode before changing it, then reboots only when required and authorized.
It verifies persistent/active configuration and root UUID after the boot.
A fully converged host requires neither backup creation nor reboot. If only a
reboot was required and no boot bytes were changed, no file backup is created;
file rollback is inapplicable to that operation.
Successful execution still requires operator review of retained kernel context;
warning signature detection is a stop gate, not exhaustive hardware diagnosis.

Use the same runner with `--stage validate` and the reviewed bundle for a later
read-only validation, with a new evidence directory. Do not reuse a pre-reboot
expected boot identity for a different operation. Preserve separate mutation,
validation and acceptance decisions. No storage acceptance or Restic action is
performed by this component.

## Failure and exact recovery

A failed apply does not authorize additional repair attempts. Inspect the private
status and Ansible streams to determine whether mutation occurred. Before mutation,
preserve evidence and clean up only proven operation-owned residue. After mutation,
record manual intervention until recovery or acceptance is independently verified.
The runner does not blindly restore after an unreachable reboot.

When reachable, inspect current bytes and retained backup. The rollback stage
requires the current hash to equal the reviewed proposed hash and the backup hash
to equal the original hash; unexpected drift stops recovery. Explicitly authorize
rollback (and reboot if needed), regenerate/review that bundle, then invoke:

```sh
python3 host-storage/scripts/run-operation.py --stage rollback   --operation /PRIVATE/recovery-operation.json   --approved-bundle REVIEWED_RECOVERY_SHA256 --evidence /PRIVATE/rollback
```

Rollback restores original bytes and owner/group/mode and verifies the hash. If a recovery
reboot is authorized, verify reachability, root UUID, new boot ID and the restored
runtime driver separately against retained preflight evidence. Do not use normal
`validate` to accept an intentionally restored UAS configuration. A rollback with
no reboot proves file restoration only, not restored runtime state.

If SSH fails, use the confirmed console or independently mount the boot partition
on the recovery system. Identify the correct medium; check the retained backup's
SHA-256 against the private preflight record, restore that exact file to
`cmdline.txt`, sync/unmount safely, and boot under the recovery authorization.
If the backup is missing or mismatched, stop rather than synthesize boot arguments.
Preserve the original newline and all unrelated arguments. Record recovery boot,
root continuity, restored bytes and kernel context before declaring recovery.

Retain backups until terminal acceptance/recovery review; delete only an explicitly
verified operation-owned backup under a separate cleanup decision. Archive sanitized
operation definitions and evidence manifests under the repository history policy.
Do not remove the historical Nautobot implementation or evidence during extraction.

## Qualification limits

Fixture tests cover the exact renderer and operation guards. Ansible syntax and
read-only pilot checks cannot prove actual boot mutation, loss-of-SSH recovery,
filesystem durability or HA availability. Live apply/reboot/rollback qualification
is a separate milestone on one selected recoverable host. Do not interrupt an
active Webmin or smartmontools observation to perform it.
