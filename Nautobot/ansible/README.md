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
play context. The resulting Podman process runs as the `nautobot` account
without requiring Ansible to stage a module as an unprivileged user. Rollback
evidence distinguishes pre-existing, remaining, and newly introduced
automatically removable package residue; rollback never performs autoremove.

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
