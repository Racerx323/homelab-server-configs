# Nautobot roadmap and acceptance status

## Current next action

Reboot execution preparation now includes a single-dispatch Ansible path,
controller-durable intent, volatile-host restaging, current-invocation boot-gate
receipts, independent writer recovery, and logical comparisons against accepted
preservation. Fresh read-only evidence collected September 25 at 21:52 UTC shows
healthy services/linger/guard, the unchanged boot and kernel, both proxy address
families at HTTP 200, and SSH/Webmin/Munin reachability. Private evidence:
`nautobot-reboot-preparation-20260925/`. Reboot has not been executed; the new
boot gate and reboot persistence remain unproven. Complete preparation validation,
publication/CI and freeze review before requesting execution authorization.

Repository records reviewed September 25, 2026; this is not a fresh host check.
The synthetic workload and bounded PAM-session logout are accepted and archived.
The logout archive preserves the original redundant-stop orchestration error;
acceptance rests on retained observation, closure and final unit-state evidence.
Accepted state is reconciled and the active operation slot is clean.

Fresh read-only reboot baseline collected September 25: accepted artifact and boot
identities match; services, linger and guard are healthy; both proxy families return
HTTP 200. The boot image matches running kernel `6.18.50+rpt-rpi-v8`.
Private evidence: `nautobot-reboot-baseline-20260925/REVIEW.md`.

Boot-readiness artifact deployment is accepted: the two reviewed files were
installed and the user manager reloaded. The generated gate timeout is five minutes;
boot, running service identities, sessions and before/after HTTP health remained
unchanged. No restart, reboot or rollback occurred. Original backups are retained.
The new gate itself remains unexecuted; reboot persistence is not accepted.
Private evidence: `nautobot-boot-readiness-bundle-20260925/REVIEW.json`.

The terminal archive is published and verified; accepted artifact identities
are reconciled and the active operation slot is clean. Reconciliation is published.
Recovery preservation/comparison preparation is specified in OPERATIONS using the
existing application-backup producer. The user reserved a fresh quiet window
covering capture, later reboot and postboot comparison. This does not establish
absence of scheduled writers or authorize their suspension.

The logical database comparator is implemented and locally qualified against
immutable AMD64 PostgreSQL 17.11 and the existing qualification application image.
Tests cover snapshot isolation during a concurrent committed write, content/order,
duplicates, NULL/empty values, schema/sequences, bounds and transaction cleanup.
Private qualification evidence: `nautobot-logical-snapshot-20260925/`.
This does not qualify execution on ARM64 or every live database object type.

Read-only inventory at 2026-09-25 19:01 UTC found 245 public tables, 64 sequences,
no rows in the database periodic-task or scheduled-Job tables, and 32 successful
Job results. Media contained three directories and no files. Private evidence:
`nautobot-recovery-inventory-20260925/`. A transient idle database connection and
successful historical Jobs do not establish empty broker queues or absent writers.

Preservation preparation now includes an inactive scope contract, executable-stage
schema, Ansible stop/capture/resume path, broker drain, temporary logical client,
stopped-container metadata handling, guarded backup and supervised bundle launcher.
AMD64 native qualification passed with real Celery task completion, Redis priority
and unacknowledged-state checks, and repeatable logical captures. The actual Ansible
block's local failure regression verified all writer-resume attempts and both
credential removals despite injected backup and worker-resume failures. Production
systemd/ARM64 behavior remains a live qualification boundary.
Private evidence: `nautobot-preservation-native-final-20260925/` and
`nautobot-preservation-preparation-20260925/`.

Preservation implementation is published at `e1cac5e`; repository validation and
CodeQL passed. Fresh read-only baseline at 2026-09-25 19:51 UTC matches all reviewed
artifacts, images and boot identity. Five services are healthy with zero restarts;
application health returns HTTP 200, media remains empty and no scheduled writers
are registered. Tmpfs capacity and the installed Restic version match the capture
contract. Private review: `nautobot-preservation-baseline-20260925/REVIEW.md`.

Recovery preservation was executed with exact authorization on September 25.
It failed during worker drain at 20:10 UTC, before logical capture or backup.
Diagnosis confirmed a CLI collision: `shell -c CODE` treats CODE as the
configuration path. The harmless `shell --interface python --command` probe passed;
full drain and preservation remain unqualified. The helper discarded the outer CLI
stderr, and local native tests had bypassed this production entry path.
All writer-resume commands succeeded, final health and delayed storage checks
passed, data-service invocations and boot were unchanged, and both transient
credential files were removed. Missing success-path receipts correctly prevent
acceptance. The consumed definition and protected staging remain retained.
Private evidence: `nautobot-preservation-preparation-20260925/STATUS.md`.

The CLI correction now uses explicit `--command` with probe source on stdin.
Known pre-probe stderr failures and timeouts have fixed sanitized reason codes.
Thirteen preservation regressions and disposable AMD64 integration passed,
including the actual drain phase and real Nautobot parser boundary. All disposable
resources were removed; repository hooks passed. A private inactive successor
bundle is prepared at `nautobot-preservation-drain-fix-20260925/REVIEW.md`.
The consumed v1 definition and sanitized result are preserved in the published
failure tag indexed in HISTORY. Files were byte-verified before removal from main;
the operation slot is clean after accepted preservation archival.

Fresh read-only baseline at 2026-09-25 20:35 UTC matches accepted artifacts and boot;
five services are healthy, HTTP returns 200, media is empty and no scheduled writers
are registered. Retained staging has no credentials, and tmpfs capacity is sufficient.
Review: `nautobot-preservation-retry-baseline-20260925/REVIEW.md`.
Correction `2fda8fa` is published; repository validation and CodeQL passed.
The corrected bundle is frozen against that commit and the 20:35 UTC baseline.
The authorized retry completed and is accepted: all eight receipts passed review.
Logical identity, backup upload/full integrity, resource guard, writer recovery,
health and delayed storage checks passed. Node/controller credentials were removed;
boot and data-service invocations were unchanged. The accepted archive is published
and byte-verified; HISTORY and accepted state now bind snapshot and logical hashes.
The operation slot is clean. No restore or reboot occurred.

Reboot preparation now defines preboot comparison against the preserved identity,
one reboot with no resend, automatic startup observation before any repair, and a
second bounded writer pause for postboot logical comparison followed by recovery.
Reusable sequence and failure cases live in OPERATIONS. The Ansible path and
read-only refresh are implemented; publication/CI precede execution readiness.
Current logical identity has not been rechecked; writer
resume ended the preservation interval. A mismatch requires separate fresh
preservation before reboot. Reboot persistence and full isolated restore remain open.

## Accepted scope and remaining gates

| Gate | Recorded position | Authority |
| --- | --- | --- |
| Stage 3 host baseline | Accepted with recorded storage and external-IPv6 evidence limitations | [Accepted state](../manifests/accepted-live-state.yaml), [history](../HISTORY.md) |
| Stage 4 dual-stack identity | Accepted; DNS owner archive retained | [Accepted state](../manifests/accepted-live-state.yaml) |
| Stage 5 prerequisites and startup | Image, credentials, native readiness, initialization, administrator and startup results archived | [History](../HISTORY.md), component manifests |
| Synthetic workload | Accepted only for repeat-fixture workload, 15 Jobs and application-backup overlap/integrity | [Synthetic acceptance](../manifests/accepted-live-state.yaml) |
| Real-inventory representativeness | Open; compare scale and operation mix with intended inventory | [Master plan](NAUTOBOT_DEPLOYMENT_PLAN.md#stage-5-workload-and-persistence-qualification) |
| Logout and reboot persistence | Bounded PAM logout accepted and archived. Reboot remains open | [Procedures](OPERATIONS.md#persistence-procedure) |
| Application restore | Open; canary restore and dump listing do not satisfy it | [Master plan](NAUTOBOT_DEPLOYMENT_PLAN.md#backups-and-recovery) |
| Stage 6 Caddy onboarding | Open; owner lifecycle applies | [Master plan](NAUTOBOT_DEPLOYMENT_PLAN.md#caddy-application-onboarding) |
| Stable pilot, authority migration, Semaphore | Open; seven-day criterion and separate domain acceptance remain | [Master plan](NAUTOBOT_DEPLOYMENT_PLAN.md#validation-and-acceptance) |

## Evidence limits carried forward

The accepted workload's node execution succeeded, but its controller stopped
polling and volatile controller evidence was lost after a workstation restart.
The interruption cause and historical credential-finalizer execution remain
unproven. Scoped recovery and independent readback verified current cleanup.
The new service envelope passed disposable local lifecycle qualification
(private evidence: `nautobot-controller-supervision-20260925/qualification.json`).
The production launcher has offline coverage; no new workload was executed.
The controller cannot resume work across a workstation restart and never
retries automatically. Historical interruption and cleanup limits remain.

The repeat imports reused a retained owned fixture. Initial-import evidence is
separate; synthetic success is not a claim of production representativeness.
The retained full application snapshot passed integrity checking, not a full
application restore. Full stage 5 remains unaccepted.

Earlier stage-specific remaining-gate fields describe what that stage did not
accept. Read them with the newer synthetic-workload record; do not reinterpret
old baseline `false` fields as current absence of the initialized repository.

## Record ownership

The [master plan](NAUTOBOT_DEPLOYMENT_PLAN.md) owns architecture and criteria;
[OPERATIONS](OPERATIONS.md) owns reusable procedures; manifests own desired,
accepted and active state. [HISTORY](../HISTORY.md) indexes terminal archives.
The checkpoint is navigation only. Earlier preparation narratives are historical
and preserved in the Git snapshot referenced by HISTORY, not current instructions.
SMART and Webmin follow-ups are owned by their components; their upstream status
is not duplicated here and does not introduce a new Nautobot acceptance gate.
