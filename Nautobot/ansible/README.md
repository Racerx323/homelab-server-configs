# Nautobot Ansible qualification

`playbooks/qualify-host.yaml` collects the read-only host qualification required
before you define a host-baseline operation. Its target assertion permits only
`j2-svpi4mf`, and the playbook contains no configuration-management tasks. The
collector verifies the permanent ULA and the complete Keepalived ownership
boundary, including any failed-unit registration. It also records APT candidate
versions for the exact host-baseline package specifications.

Review the fixed live command without contacting the host:

```bash
/bin/bash Nautobot/ansible/scripts/run-qualification.sh show-command
```

After separately authorizing that exact read-only execution, run:

```bash
/bin/bash Nautobot/ansible/scripts/run-qualification.sh execute
```

The launcher creates a mode-0700 directory named
`/tmp/nautobot-qualification.*`. It captures up to 4 MiB from each stream,
stores command status in a separate file, and writes a manifest containing
input and evidence hashes. Raw output stays outside Git. The generated manifest
contains no raw host output. Review it before copying it into a later operation.

The launcher makes no host changes. Its Ansible command uses check mode, but
the read-only command tasks still execute. Obtain separate read-only
authorization before running `execute`.

## Host-baseline operation

`../../manifests/operation.yaml` defines the active host-baseline operation.
The definition remains unable to execute while `authorization_ready` is
`false`. Review its blockers and candidate bundle without contacting the host:

```bash
/bin/bash Nautobot/ansible/scripts/run-host-baseline.sh show-bundle
```

The operation requires a fresh qualification after the `homelab-dns`-owned
Keepalived removal. That qualification must also supply exact APT candidate
versions. Update the operation with those `name=version` specifications,
checkpoint the source, clear the reviewed blockers, and calculate the final
bundle before requesting live authorization.

Rootless Podman checks run through `/usr/sbin/runuser` from the privileged
play context. After switching identity, `/usr/bin/env --chdir` enters
`/var/lib/nautobot` before invoking Podman, so the service account never
inherits the SSH user's inaccessible working directory. The resulting Podman
process runs as the `nautobot` account without requiring Ansible to stage a
module as an unprivileged user. Rollback evidence distinguishes pre-existing,
remaining, and newly introduced automatically removable package residue;
rollback never performs autoremove.

The live command has this form:

```bash
/bin/bash Nautobot/ansible/scripts/run-host-baseline.sh execute BUNDLE_SHA256
```

The launcher refuses a dirty worktree, an unready operation, or a bundle hash
mismatch. The playbook applies only the host-baseline stage. It runs rollback
after a task or acceptance failure and reports manual intervention
when an unreachable host prevents rollback proof. A failure before the
preflight evidence boundary is reported as `preflight_failed`, because no
mutation has begun. The launcher keeps bounded raw output and separate
preflight, mutation, acceptance, rollback, and residue records under a
mode-0700 directory in `/tmp`.

## Storage diagnostic operation

`playbooks/diagnose-storage.yaml` defines the read-only diagnostic that follows
the host-baseline v3 storage incident. It records the USB/UAS topology and
negotiated driver, kernel storage and power context, Raspberry Pi throttling
state, extended SMART/NVMe health, and mounted ext4 metadata. It does not run a
SMART self-test, filesystem check, repair, surface scan, USB reset, package or
service change, or reboot.

The diagnostic does not use Ansible's per-task become transport. It runs the
play unprivileged, first proves `/usr/bin/sudo -n /usr/bin/true`, and then uses
an exact reviewed `/usr/bin/sudo -n` argument vector for every remote command
probe.
The launcher self-test compares the complete ordered command set and rejects
additional or altered probe commands.

The corrected collector uses `tune2fs -l`, asks journalctl to suppress its
no-entry marker, and independently removes that marker before counting event
lines. These rules prevent an empty kernel query from being reported as one
event.

Review the definition and candidate bundle without contacting the host:

```bash
/bin/bash Nautobot/ansible/scripts/run-storage-diagnostic.sh show-bundle
```

After the operation is checkpoint-bound, marked authorization-ready, reviewed,
and separately authorized with its exact bundle hash, the live command has this
form:

```bash
/bin/bash Nautobot/ansible/scripts/run-storage-diagnostic.sh execute BUNDLE_SHA256
```

The launcher refuses a dirty worktree, an unready operation, or a bundle hash
mismatch. It stores bounded raw evidence outside Git in a mode-0700
`/tmp/nautobot-storage-diagnostic.*` directory and writes a sanitized summary.
Collection does not decide whether to retain or roll back the converged
host-baseline state. That decision requires operator review of the diagnostic
and the observation requirements in the active operation. Any rollback,
hardware remediation, filesystem repair, or later host-baseline acceptance is
a separate operation and authorization.

## Standalone host-baseline rollback

`playbooks/rollback-host-baseline.yaml` defines the separately authorized
rollback from the converged v3 host state to its evidence-backed pre-v3 state.
It does not reuse the original apply-time rollback tasks because their change
registers existed only in the original Ansible process.

The standalone rollback restores the four service states observed before v3,
removes the account, subordinate IDs, lingering state, and only the nine
packages proven absent before v3. It preserves pre-existing `msmtp` and
`dbus-user-session`, never runs APT autoremove, and reports dependency residue.
Before mutation it requires a quiet storage window, exact root source, exact
APT simulation, the expected account state, and local-recovery confirmation in
the reviewed operation.

Review the unready definition without contacting the host:

```bash
/bin/bash Nautobot/ansible/scripts/run-host-baseline-rollback.sh show-bundle
```

After separate read-only authorization, collect the fresh rollback preflight
without entering the mutation block:

```bash
/bin/bash Nautobot/ansible/scripts/run-host-baseline-rollback.sh preflight
```

The preflight uses Ansible check mode, forces only its read commands to run,
writes bounded local evidence, and ends the play before the first systemd,
account, package, or reboot task.

The eventual live command has this form, but must not be used until every
operation blocker is cleared and the final bundle receives scoped approval:

```bash
/bin/bash Nautobot/ansible/scripts/run-host-baseline-rollback.sh execute BUNDLE_SHA256
```

Storage remediation, filesystem work, network changes, DNS changes, and a
forward host-baseline reapply are outside this rollback operation.

## JMicron UAS-quirk remediation

`playbooks/apply-uas-quirk.yaml` and `scripts/run-uas-quirk.sh` define the
single-host transport A/B test for JMicron `152d:0583`. The operation verifies
the exact root device, bridge identity, current `uas` binding, active
`/boot/firmware/cmdline.txt` hash, single-line formatting, and absence of a
prior rollback copy before mutation.

Review the definition without host contact:

```bash
/bin/bash Nautobot/ansible/scripts/run-uas-quirk.sh show-bundle
```

The separately authorized read-only preflight is:

```bash
/bin/bash Nautobot/ansible/scripts/run-uas-quirk.sh preflight
```

After local-console recovery, backup, fresh preflight, checkpoint, and bundle
gates are satisfied, the mutation command has this form:

```bash
/bin/bash Nautobot/ansible/scripts/run-uas-quirk.sh execute BUNDLE_SHA256
```

The playbook appends `usb-storage.quirks=152d:0583:u` without adding a newline,
reboots once, and requires `usb-storage` rather than `uas`. A reachable
post-reboot acceptance failure restores the exact backup and reboots again.
Failure to regain SSH requires local-console restoration. Immediate acceptance
remains provisional until the corrected storage diagnostic and 24-hour soak
pass; the rollback copy remains in place until terminal acceptance.

If the first reboot does not restore SSH, use the confirmed local console and
restore only the reviewed boot file:

```bash
sudo /usr/bin/cp --force --preserve=mode,ownership,timestamps -- \
  /boot/firmware/cmdline.txt.nautobot-uas-quirk-v1.bak \
  /boot/firmware/cmdline.txt
/usr/bin/sha256sum /boot/firmware/cmdline.txt
sudo /usr/sbin/reboot
```

The restored hash must be
`c1e8648e70a13b54a7c0e9a3c030838cebdc478d88b8c938ebce67f980d6f22f`.
After reboot, `/proc/cmdline` must omit the quirk, `/` must remain on
`/dev/sda2`, and udev must again report `ID_USB_DRIVER=uas`. Retain the backup
until terminal storage acceptance; do not delete it during immediate cleanup.
