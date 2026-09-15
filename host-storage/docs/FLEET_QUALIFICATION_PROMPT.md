# Follow-on fleet qualification planning prompt

Use the prompt below to prepare the next milestone. It authorizes repository
planning and local validation only; live inspection and execution need their
own scoped authorization. This document is not a pending live operation.

## Copyable prompt

Continue the host-storage project in
`/home/aaron/code/homelab-server-configs`. Read applicable `AGENTS.md` instructions.
Prepare a concrete, reviewable plan to qualify live boot mutation, reboot,
reachable rollback and console recovery before rolling out the shared storage
profiles to additional servers.

Start with:

- `host-storage/docs/HOST_STORAGE_ARCHITECTURE.md`
- `host-storage/docs/OPERATIONS.md`
- `host-storage/profiles/rpi4-x872-usb-storage.yaml`
- `host-storage/schemas/operation.schema.json`
- `host-storage/scripts/run-operation.py` and `scripts/transport.py`
- `host-storage/ansible/playbooks/` and `ansible/roles/storage_transport/`
- `host-storage/tests/`
- `inventory/README.md` and the relevant production host definitions
- `smartmontools/docs/JMICRON_NVME_PROFILE.md`
- `Webmin/docs/WEBMIN_ARCHITECTURE.md`

If retained, review the private extraction evidence at
`/home/aaron/code/.local-evidence/host-storage-extraction-20260915/REVIEW.md`
and its referenced source snapshot and preflight records. Treat these as historical
evidence, not current host state. Locate and review the latest combined Webmin /
smartmontools observation records before proposing a live window. An elapsed
deadline or inactive observer alone does not establish successful completion.

### Scope and ownership

Work locally on the plan, implementation gap analysis and focused tests. Do not
contact hosts, change inventory selection, deploy, mutate boot configuration,
restart services, reboot, inject failures or publish reports under this prompt.
Prepare separate authorization requests only after the corresponding operation
is concrete and reviewable. Honor any additional authorization explicitly given
in the follow-on session without asking for it again.

Keep transport, boot changes and recovery in `host-storage/`; SMART package and
monitoring policy in `smartmontools/`; and polling behavior in `Webmin/`.
Nautobot and Restic consumers retain workload, storage and backup/restore
acceptance. Preserve historical Nautobot operations, unrelated changes and all
evidence. Do not interrupt an active observation or combine transport testing
with package, firmware, USB power-management or Webmin changes.

### Required planning work

1. **Assess implementation readiness.** Inspect the actual runner and Ansible
   tasks rather than treating the documented workflow as implemented proof.
   Identify gaps in drift protection, backup integrity, reboot validation,
   interrupted execution, unreachable-host handling, recovery and residue
   reporting. Distinguish fixture-tested paths from live-qualified paths.
   Describe required fixes and tests before any live operation is proposed.

2. **Build a candidate matrix from available records.** For each candidate,
   record the inventory host, physical adapter, platform, root topology,
   bridge identity, profile compatibility, active/persistent transport when
   evidenced, workload dependencies, HA role, maintenance constraints and
   recovery access. Label unknown or stale facts. Do not infer compatibility
   from matching USB IDs or appearance. List the exact read-only checks and
   target scope needed to resolve unknowns, without SMART queries.

3. **Select one recoverable qualification pilot.** Prefer a spare or otherwise
   suitable host with independent console access and a legitimate required
   transport change. An already-converged host qualifies the no-op path only;
   do not remove its working quirk just to manufacture mutation coverage.
   If no suitable pilot exists, explain that limitation and propose a separately
   authorized lab setup. Confirm the intended final transport configuration.

4. **Define qualification cases and their evidence.** Cover:
   - Already-correct file and driver: no boot-file mutation, backup or reboot.
   - A required file change: preserve unrelated arguments, exact formatting,
     original bytes and owner/group/mode; verify the reviewed resulting hash.
   - Correct persistent settings but wrong active binding: an explicitly
     authorized reboot, without claiming a file rollback exists when no file
     was changed.
   - Post-reboot convergence: expected new boot identity, root UUID continuity,
     active driver, running quirk, persistent hash and kernel/storage health.
   - Reachable rollback: verify backup and current-file hashes, restore exact
     original bytes/metadata, and separately verify restored runtime state.
   - Console recovery: prove independent access and the exact medium/file
     restoration procedure. Distinguish an access check or tabletop rehearsal
     from an exercised recovery. Any deliberate loss-of-SSH or boot-failure
     injection needs its own reviewed lab scope; do not induce it on production
     merely to complete a checklist.
   - Wrong identity, stale inputs, conflicting quirks, reused or corrupt backup,
     and interrupted execution: stop without unreviewed repair; retain evidence
     and distinguish pre-mutation failure from unresolved post-mutation state.

5. **Prepare authorization and recovery packages.** For each proposed stage,
   specify the exact target, command, input bundle SHA-256, reviewed boot diff,
   private evidence location, original/proposed hashes, boot/root identities,
   unused backup path, permitted mutations and reboot count, timeout, abort
   criteria, console operator, recovery instructions and expected final state.
   Bind authorization to the final inputs, not a provisional digest. Do not
   set authorization or recovery-confirmation fields true without their actual
   supporting approval or access verification. Keep secret values and raw host
   identities out of committed/public evidence.

6. **Define observation and progression gates.** Propose bounded post-change
   observation periods appropriate to the prior failure pattern, with measurable
   kernel/storage health, ordinary disk activity, monitoring continuity and
   workload availability checks. Specify collection completeness and evidence
   review, not merely elapsed time or command exit status. Stop progression on
   storage events, incomplete evidence, unexplained drift or unresolved recovery.
   Keep transport qualification separate from storage/Restic acceptance.

7. **Plan fleet adoption after pilot qualification.** Use explicitly selected
   hosts and one host per operation. Maintain one active operation per component
   deployment stream. Order hosts by recovery readiness and service dependency;
   for HA pairs, verify peer capacity, service/VIP health and the applicable
   owner-approved maintenance procedure before touching a member. `serial: 1`
   alone is insufficient. Do not broaden a profile for unsupported hardware or
   automatically opt in every matching device. Specify per-host review,
   acceptance/recovery, backup retention, residue cleanup and terminal archival
   gates before proceeding to the next host.

### Deliverables and completion boundary

Save a reusable qualification/fleet plan in `host-storage/docs/` and link it
from the component README. Include the candidate matrix, implementation gaps,
test/evidence matrix, pilot recommendation, staged authorization boundaries,
rollback/console procedure, observation criteria and fleet progression gates.
Keep individual operation specifications and raw evidence outside the governing
architecture document; private operation records remain outside Git.

Run focused local checks appropriate to any edits. Use the repository Ansible
temporary-directory wrapper for Ansible validation. Report exactly which paths
are tested, proposed, blocked on missing facts, or still require live qualification.
Finish with the next concrete authorization scope and unresolved decisions.
Do not deploy, accept storage or Restic, commit or push as part of this planning task.
