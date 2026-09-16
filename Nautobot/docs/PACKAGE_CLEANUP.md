# Reviewed baseline package cleanup

This procedure removes an explicitly reviewed set of obsolete packages and
residual configuration records after host-baseline preflight. It is not a
general autoremove policy and does not authorize package upgrades or reboot.

## Prepare and review

Record exact package names, versions and dpkg states, running kernel and boot
identity in a protected `cleanup_plan` JSON. Its `cleanup` object contains
`host`, `boot_id`, `kernel`, `directory`, and `packages`, keyed by package name
with `version` and `state` values. The current purge playbook is intentionally
limited to the reviewed eleven-entry cleanup on `j2-svpi4mf`; review another
scope before changing that guard.

Run `ansible/playbooks/prepare-package-cleanup.yaml` using the repository Ansible
wrapper, explicit inventory/host limit, `cleanup_plan`, and protected controller
`cleanup_evidence` path. It requires a new protected remote evidence directory.
The helper compares exact package state, simulates only the named purge, obtains
the exact recovery `.deb` files from cache or the configured package sources,
and verifies package/version metadata. It archives affected conffiles, package
metadata, APT marks and boot files; its recovery index records hashes. Treat the
archive as private configuration data. No purge occurs in preparation.

Review the recovery index, actual simulation and running/fallback kernel
retention. Bind the plan, recovery index, playbook, helper, wrapper and inventory
to the authorized bundle. Preserve the exact command and raw streams privately.

## Execute and verify

Use `ansible/playbooks/purge-reviewed-packages.yaml` through the same wrapper.
It checks boot identity, unchanged package database, recovery archive/packages,
and firmware hashes. It then re-simulates and requires precisely the named
removal set with no installs/upgrades before issuing `apt-get --assume-yes purge`
with those explicit names. It does not use `autoremove`. Needrestart runs in
list-only mode; unrelated service restarts are not requested.

The command result is retained before assertions. Verify firmware bytes and boot
identity after execution, independently inspect installed/residual package state
and a new autoremove simulation, and rerun the full read-only host preflight.
Successful purge is not host acceptance. Preserve failed pre-mutation attempts
and do not obscure a mutation-bearing failure with an automatic retry.

## Recovery

Retain exact recovery packages and the original archive. After a partial package
transaction, inspect dpkg state and define the smallest recovery; do not restore
the complete package database over unrelated changes. Previously installed
packages can be reinstalled from the exact preserved `.deb` files after a
dependency simulation. Previously removed packages with residual configuration
must not be blindly reinstalled or started: restore only reviewed original paths
and separately review any package-state reconstruction. Restore package marks
through `apt-mark` using retained evidence.

Unexpected boot-file changes require comparison with the exact backup and
manual review. A recovery reboot is separately authorized. Never remove the
running kernel or an explicitly retained fallback to satisfy a cleanup gate.
