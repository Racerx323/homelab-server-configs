# Nautobot roadmap and acceptance status

## Current next action

Isolated full application restore preparation is specified in
[OPERATIONS](OPERATIONS.md#isolated-full-application-restore-preparation).
Use accepted preservation snapshot
`7f59d7ccb20ccf6e3c4ea537034db77e0ec558b7a01e7cb2d1bb2bd62b77863c`
and its private logical reference. The source archive is indexed in HISTORY;
its payload covers all six required categories with directory-only media.

Local restore qualification passed on September 26 using disposable AMD64
Nautobot 3.2.3/DNS Models 2.3.0, PostgreSQL 17 and Redis, with Restic 0.18.0.
The actual Ansible path retrieved six hash-bound files from an exact snapshot,
validated/extracted archives, imported an empty database and proved pre-start
logical equality. Native configuration/migration checks, Django health and
fixture exports passed. Wrong repository/snapshot identities, changed payload
hashes and changed database content were rejected. Owned resources and ephemeral
credentials were removed and independently checked. Private evidence:
`nautobot-restore-local-20260926/run-f4100592/REVIEW.json`.

Target-specific isolation and inputs are prepared in
`manifests/application-restore-preparation.yaml`, still inactive. Authorized
read-only collection at 2026-09-26 16:35 UTC matched accepted boot/artifact identities;
five services, linger, guard and HTTP 200 passed. All three ARM64 images are present.
Available memory was about 6.26 GiB, SSD free space about 870 GiB and live database
size about 46 MiB. No matching storage/OOM errors appeared in the bounded
2,000-entry current-boot kernel read. This is an idle observation, not restore-load
acceptance. Private review: `nautobot-restore-baseline-20260926/REVIEW.json`.

Snapshot payload and private logical-reference hashes match the published archive.
During that baseline, no Doppler resolution, B2 contact, download or target mutation occurred. A separate
local probe verified shared loopback-only container networking and cleanup; target
namespace enforcement remains unproven. The first collector's filtered-journal
nonzero exit is retained privately; the complete revised collection exited zero.

The target Ansible path is implemented and qualified locally on September 26.
It uses the actual preservation archive layout, network-less PostgreSQL namespace,
new label-bound storage, hard cgroup limits and an independent user-systemd guard.
The complete disposable run passed import, pre-start logical equality, native
configuration/migration/health checks, repeatable exports, media checks and cleanup.
Actual guard SIGKILL also triggered verified container, volume and credential
removal. The accepted media/dependency archive hashes reproduce from preserved
inputs, including `observed-images-before-stop.json`. Private evidence is under
`nautobot-restore-target-20260926`; this is not production restore acceptance.

Local development failures exposed missing writable Jobs and media health-probe
paths; cleanup passed on those failures. Native health intentionally changes its
test sequence, so exact logical comparison remains before application checks as
planned. Target storage/thermal monitoring reuses the existing root sampler and
fails closed on missing/stale evidence; its target execution is not yet qualified.

Bundle staging and credential delivery are implemented. The actual Ansible path
passed locally with disposable credentials, including copied-input readback,
retrieval/import, logical/native checks, receipt collection and cleanup. A retained
staging retry is rejected. Offline regressions cover partial provider/injection
failures, terminal delivery rejection and altered frozen runtime inputs. Evidence:
`nautobot-restore-delivery-20260926`. A wrong-snapshot run after credential
delivery also proved independent cleanup (`nautobot-restore-delivery-fault-20260926`).
The real baseline caught and corrected a validator assumption: deployed nonsecret
runtime Python files are mode 0644; Quadlets are mode 0600. The disposable
delivery qualification used no target contact or real secrets.

Implementation publication and repository CI passed. The authorized September 26
restore execution failed while arming its cleanup guard, before target credential
delivery, snapshot retrieval or restore container creation. Rootless Podman
inherited inaccessible `/home/ama`; the same read-only health probe from
`/var/lib/nautobot` returned HTTP 200. Controller exit 2 is retained.
Independent cleanup verified absent restore resources and credentials, inactive
monitor/guard, and unchanged identities for all five production services.
Controller-resolved credentials were removed. Nonsecret staging and the consumed
operation definition remain retained pending terminal archival. Private review:
`nautobot-restore-bundle-20260926/REVIEW.json`.

Next: correct working-directory handling and targeted diagnostics, qualify the
privilege-transition path, then archive the failure and prepare a separately
authorized retry. Do not rerun the consumed bundle. Full production restore,
ARM64 restore-load headroom, target namespace enforcement and populated-media
recovery remain unproven. Successful staging and brief host monitoring do not
qualify monitoring across a full restore; local Django checks do not qualify
production uWSGI/browser use.

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
