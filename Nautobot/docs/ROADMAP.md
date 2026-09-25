# Nautobot roadmap and acceptance status

## Current next action

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

The review bundle remains inactive: current implementation is uncommitted and CI
has not reviewed it. Next commit/publish, verify CI, refresh or re-review the bounded
baseline and activate one exact preservation operation for execution approval.
The active operation slot remains clean. No credentials were resolved and no host
was contacted or changed during bundle preparation. Fresh preservation, new
boot-gate execution and reboot persistence remain unproven; no volatile-data
exclusions or automatic restore are approved.

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
