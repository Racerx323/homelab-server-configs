# Raspberry Pi memory-controller correction

Nautobot's host baseline requires cgroup-v2 memory control before application
memory ceilings can be accepted. This correction enables that runtime capability;
it does not alter the host-storage transport profile or qualify other hosts.

## Diagnose

Read the running kernel configuration, `/proc/cmdline`, the actual firmware
command-line file and `/sys/fs/cgroup/cgroup.controllers`. Raspberry Pi firmware
can prepend `cgroup_disable=memory` from its device-tree defaults even though
that token is absent from `/boot/firmware/cmdline.txt`. With `CONFIG_MEMCG=y`,
append `cgroup_enable=memory` to override that earlier default. Do not add the
obsolete `cgroup_memory=1` token. A build without `CONFIG_MEMCG_V1` can omit memory
from `/proc/cgroups` even when the v2 controller works.
See the [Raspberry Pi maintainer explanation](https://github.com/raspberrypi/linux/issues/6980#issuecomment-3149752155).

## Stage

Use `ansible/scripts/plan-memory-controller.py` to render exact original bytes
to a separate private candidate. It preserves line endings and unrelated
arguments and refuses conflicting settings. The current implementation is scoped
to the reviewed Raspberry Pi/JMicron host; it is not a fleet deployment entrypoint.

Prepare a protected JSON plan with a `memory_correction` object containing
`stage: boot_file_only`, `reboot_authorized: false`, `boot_path`,
`backup_directory`, `boot_id`, `before_sha256`, `after_sha256` and exact `content`.
Review the byte diff, preserve original bytes locally, and bind the plan,
playbook, renderer, validators, wrapper and non-secret inventory inputs in the
operation's SHA-256 bundle before authorized execution.

From the repository root, use the repository Ansible wrapper:

```bash
/bin/bash tests/repository/run-with-ansible-local-temp.sh \
  ansible-playbook --inventory inventory/prod/hosts.yaml \
  --limit j2-svpi4mf --user ama \
  Nautobot/ansible/playbooks/stage-memory-controller.yaml \
  --extra-vars memory_controller_plan=/absolute/private/stage-plan.json
```

The playbook verifies the current boot, file identity and reviewed hashes,
preserves `cmdline.before` in a root-only backup directory, verifies its hash,
rechecks drift, stages the candidate and verifies unchanged boot identity.
It performs no reboot. Independently read back the candidate and backup hashes,
firmware configuration hash, boot identity and current controller list. Preserve
stdout, stderr and exit status separately. A partial mutation must be investigated
and either verified or rolled back; do not blindly replay after drift.

## Rollback and reboot boundary

Before restoring, require the live command-line hash to equal the reviewed
candidate hash and the backup hash to equal the original hash. Stop on mismatch.
Use Ansible `copy` with `remote_src: true` to restore the exact backup to the
reviewed boot path with its original ownership and mode, then independently
verify the original hash. A rollback before reboot does not require reboot.

Reboot is a separate authorized stage. Confirm physical/console recovery access
and preserve the exact original locally before proceeding. If SSH does not
return, restore the original command-line bytes on the boot partition through
that recovery path, preserving root identity and the USB transport quirk.
Postboot rollback requires another explicitly scoped reboot.

After reboot, verify a new boot identity, root-device continuity, expected USB
binding and quirk, memory-controller availability and user-manager delegation.
Review kernel/storage/power health under a new boot-bound window. Verify actual
per-service memory-limit enforcement during bounded runtime acceptance; controller
availability alone is insufficient. Storage acceptance and Restic remain separate.

Use `ansible/playbooks/reboot-memory-controller.yaml` for the separately
authorized single-host reboot. Its protected `memory_reboot_plan` JSON input
contains `memory_reboot.stage: reboot_and_validate`, boolean `authorized` and
`recovery_confirmed`, `old_boot_id`, and an `expected_hashes` map of absolute
paths to SHA-256 values. Include the staged command line, original backup,
firmware config and monitoring inputs. Bind the plan, playbook, wrapper,
inventory and exact command before execution. The playbook refuses boot/file
drift, captures a journal cursor, reboots once, and checks new boot identity,
memory-controller availability and file integrity. Collect independent host and
storage evidence afterward; a successful playbook alone does not accept storage.

Record the running kernel before and after reboot. A pending installed kernel
may activate at the same time; verify its configuration and USB behavior rather
than assuming the old kernel remains active. Preserve relevant previous-boot
logs locally before reboot because the host journal may not persist them.
