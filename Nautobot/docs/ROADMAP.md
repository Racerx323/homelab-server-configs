# Nautobot roadmap and acceptance status

## Current next action

Repository records reviewed September 25, 2026; this is not a fresh host check.
The operation slot is clean and the accepted synthetic workload is archived.
Prepare controller-resilient execution and evidence retention before the next
long operation, then prepare logout persistence. Reboot persistence and isolated
application restore each require their own baseline, recovery review and bundle.
No successor operation is active or authorized by this roadmap.

## Accepted scope and remaining gates

| Gate | Recorded position | Authority |
| --- | --- | --- |
| Stage 3 host baseline | Accepted with recorded storage and external-IPv6 evidence limitations | [Accepted state](../manifests/accepted-live-state.yaml), [history](../HISTORY.md) |
| Stage 4 dual-stack identity | Accepted; DNS owner archive retained | [Accepted state](../manifests/accepted-live-state.yaml) |
| Stage 5 prerequisites and startup | Image, credentials, native readiness, initialization, administrator and startup results archived | [History](../HISTORY.md), component manifests |
| Synthetic workload | Accepted only for repeat-fixture workload, 15 Jobs and application-backup overlap/integrity | [Synthetic acceptance](../manifests/accepted-live-state.yaml) |
| Real-inventory representativeness | Open; compare scale and operation mix with intended inventory | [Master plan](NAUTOBOT_DEPLOYMENT_PLAN.md#stage-5-workload-and-persistence-qualification) |
| Logout and reboot persistence | Open; separate operations | [Procedures](OPERATIONS.md#persistence-procedure) |
| Application restore | Open; canary restore and dump listing do not satisfy it | [Master plan](NAUTOBOT_DEPLOYMENT_PLAN.md#backups-and-recovery) |
| Stage 6 Caddy onboarding | Open; owner lifecycle applies | [Master plan](NAUTOBOT_DEPLOYMENT_PLAN.md#caddy-application-onboarding) |
| Stable pilot, authority migration, Semaphore | Open; seven-day criterion and separate domain acceptance remain | [Master plan](NAUTOBOT_DEPLOYMENT_PLAN.md#validation-and-acceptance) |

## Evidence limits carried forward

The accepted workload's node execution succeeded, but its controller stopped
polling and volatile controller evidence was lost after a workstation restart.
The interruption cause and historical credential-finalizer execution remain
unproven. Scoped recovery and independent readback verified current cleanup.
Do not claim that the existing controller path survives disconnection or restart.

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
