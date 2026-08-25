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
