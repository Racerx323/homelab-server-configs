# Nautobot roadmap and acceptance status

## Current next action

Prepare the isolated full application restore contract using the accepted backup:
exact snapshot, PostgreSQL dump, media, configuration, image/dependency manifests,
Quadlets and migration state. Define isolation, independent logical/application
checks, resource limits and cleanup before freezing a separately authorized bundle.
Backup integrity and the pre-data canary restore do not satisfy this gate.

Bounded reboot persistence is accepted and archived. One reboot changed the boot
identity; all five services activated automatically and native boot-readiness
receipts passed. Health was observed at about 258 seconds uptime, both logical
comparisons matched the preserved reference, and writer recovery and final
access/resource/storage checks passed. This is retained September 25 evidence,
not a fresh host-health check.

The original controller exit 2 remains recorded: final collection incorrectly
required two preboot-only files after tmpfs clearing. All nine receipts were
preserved on the controller; seven surviving node receipts matched independently.
The local collection correction passed real Ansible regression checks; it was not
deployed or used to repeat the reboot. The annotated reboot archive is published,
accepted state/history are reconciled, and the consumed operation is cleared.
See [HISTORY](../HISTORY.md) for archive identities and
[accepted state](../manifests/accepted-live-state.yaml) for the bounded decision.

Earlier boot-readiness installation and preservation records describe their own
acceptance boundaries. Their unproven reboot fields are superseded by the newer
reboot acceptance, not current blockers. Raw evidence and retained recovery
copies remain private; no host cleanup or restore was performed during reconciliation.

## Accepted scope and remaining gates

| Gate | Recorded position | Authority |
| --- | --- | --- |
| Stage 3 host baseline | Accepted with recorded storage and external-IPv6 evidence limitations | [Accepted state](../manifests/accepted-live-state.yaml), [history](../HISTORY.md) |
| Stage 4 dual-stack identity | Accepted; DNS owner archive retained | [Accepted state](../manifests/accepted-live-state.yaml) |
| Stage 5 prerequisites and startup | Image, credentials, native readiness, initialization, administrator and startup results archived | [History](../HISTORY.md), component manifests |
| Synthetic workload | Accepted only for repeat-fixture workload, 15 Jobs and application-backup overlap/integrity | [Synthetic acceptance](../manifests/accepted-live-state.yaml) |
| Real-inventory representativeness | Open; compare scale and operation mix with intended inventory | [Master plan](NAUTOBOT_DEPLOYMENT_PLAN.md#stage-5-workload-and-persistence-qualification) |
| Logout and reboot persistence | Bounded PAM logout archived; bounded reboot archived with reporting defect | [Procedures](OPERATIONS.md#persistence-procedure) |
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
accept. Read them with the newer workload and persistence records; do not reinterpret
old baseline `false` fields as current absence of the initialized repository.

## Record ownership

The [master plan](NAUTOBOT_DEPLOYMENT_PLAN.md) owns architecture and criteria;
[OPERATIONS](OPERATIONS.md) owns reusable procedures; manifests own desired,
accepted and active state. [HISTORY](../HISTORY.md) indexes terminal archives.
The checkpoint is navigation only. Earlier preparation narratives are historical
and preserved in the Git snapshot referenced by HISTORY, not current instructions.
SMART and Webmin follow-ups are owned by their components; their upstream status
is not duplicated here and does not introduce a new Nautobot acceptance gate.
