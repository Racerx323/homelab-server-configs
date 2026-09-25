# Nautobot roadmap and acceptance status

## Current next action

Repository records reviewed September 25, 2026; this is not a fresh host check.
The accepted synthetic workload is archived. The corrected logout operation ran:
its five-minute PAM-session observation passed, but the final redundant stop of
an already-unloaded test unit returned 5 and failed the orchestration assertion.
All 54 samples retained stable running service identities, zero restarts, HTTP
200 and the existing manager session. Both owned units ended inactive with PID 0;
proxy checks passed in both families. Bounded PAM-session logout is accepted by retained-evidence review, with the
original orchestration error explicitly retained; terminal Git archival is pending.
Private evidence: `nautobot-logout-resolution-20260925/REVIEW.md`.

Cleanup handling is corrected and locally tested against the real Ansible
assertions, including unloaded, active, permission-error and failed-read cases.
The sanitized decision is `manifests/logout-persistence-result.json`. Next archive
the consumed definition/bundle and acceptance decision before clearing this
operation. Preserve the original frozen playbook separately from the corrected
reusable implementation. No live retry was needed. Reboot and full application
restore remain separate gates.

## Accepted scope and remaining gates

| Gate | Recorded position | Authority |
| --- | --- | --- |
| Stage 3 host baseline | Accepted with recorded storage and external-IPv6 evidence limitations | [Accepted state](../manifests/accepted-live-state.yaml), [history](../HISTORY.md) |
| Stage 4 dual-stack identity | Accepted; DNS owner archive retained | [Accepted state](../manifests/accepted-live-state.yaml) |
| Stage 5 prerequisites and startup | Image, credentials, native readiness, initialization, administrator and startup results archived | [History](../HISTORY.md), component manifests |
| Synthetic workload | Accepted only for repeat-fixture workload, 15 Jobs and application-backup overlap/integrity | [Synthetic acceptance](../manifests/accepted-live-state.yaml) |
| Real-inventory representativeness | Open; compare scale and operation mix with intended inventory | [Master plan](NAUTOBOT_DEPLOYMENT_PLAN.md#stage-5-workload-and-persistence-qualification) |
| Logout and reboot persistence | Bounded PAM logout accepted; archival pending. Reboot remains open | [Procedures](OPERATIONS.md#persistence-procedure) |
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
