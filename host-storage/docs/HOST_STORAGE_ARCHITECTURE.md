# Host storage architecture

## Decision and ownership

Host inventory selects a reusable transport profile. Shared Ansible roles own
its implementation, rather than embedding host boot changes in a workload or
SMART installer. This makes storage type independently trackable across hosts.

| Owner | Responsibility |
| --- | --- |
| Host inventory | Explicit hardware/transport selection and stable host facts |
| `host-storage/` | Root topology, transport, boot configuration, reboot and recovery |
| `smartmontools/` | Package workaround, smartctl collection and smartd policy |
| `Webmin/` | Temperature polling behavior and its guarded observations |
| Nautobot / Restic consumer | Workload acceptance, backup and restore criteria |

Profiles contain supported platform, bridge ID, boot-file strategy, required
quirk and expected driver. Host files contain `storage.root.transport_profile`;
they do not repeat the kernel token. Existing descriptive transport fields are
checked for consistency. Operation records separately contain expected boot ID,
root UUID, hashes, backup location and stage authorization. None of those runtime
values is a hardware profile or a governing architecture decision.

The first backend supports a directly attached, partitioned ext4 root disk on
Raspberry Pi 4, `/boot/firmware/cmdline.txt`, and `usb-storage`. Reject stacked
root devices, unsupported platforms, ambiguous ancestry, symlink boot files,
multiple quirk parameters, duplicate bridge entries and conflicting flags.
Matching USB IDs alone does not qualify another host's adapter, media or firmware.
The `u` quirk applies to every matching vendor/product device on that host.

## Execution contract

1. **Preflight:** read root-device and USB ancestry, platform, active driver,
   running command line and exact boot bytes. The operator verifies recovery
   access. No SMART requests or changes to another component are permitted.
2. **Plan:** retain the exact diff, target, expected boot/root identities, backup
   path and bundle digest. Authorize the reviewed operation separately.
3. **Apply:** preserve original bytes and metadata; reconcile only the selected
   quirk. Preserve unrelated arguments, whitespace, newline and other bridge
   entries. Conflicting target flags stop execution rather than overwrite policy.
4. **Reboot:** only when required and authorized. Correct persistent bytes and
   active binding are a no-op. Correct bytes with a wrong active driver still
   require reboot and cannot be reported as converged.
5. **Validate:** require root UUID continuity, expected boot transition, persistent
   bytes, running quirk and driver; retain and review current-boot kernel health.
   Immediate transport validation does not prove long-term disk reliability.
6. **Recover:** restore the verified exact backup on a reachable target; use
   explicit console instructions if SSH does not return. Record unresolved
   recovery as manual intervention, never as successful rollback.

Ansible performs host execution. The runner binds exact inputs, one target,
stage authority and private evidence. Inventory changes never trigger deployment.
Initially every operation selects exactly one host. Future reviewed batches must
remain serial and add HA availability gates before progressing to another host.
Do not infer HA safety merely from `serial: 1`.

## History and acceptance

Retain the original [Nautobot remediation](../../Nautobot/docs/STORAGE_REMEDIATION_DECISION.md)
and its operation evidence. New transport changes use this component. Existing
consumer acceptance requirements remain valid; migration of ownership does not
rewrite historical operation manifests or clear any workload/Restic gate.

Repository tests and read-only validation qualify definitions, not live mutation,
reboot or recovery. Qualify those paths in a separately authorized pilot before
fleet rollout. Keep any ongoing Webmin/smartmontools observation undisturbed.
