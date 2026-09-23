# Nautobot roadmap and acceptance status

Resume reference: [checkpoint](CHECKPOINT.md).

## Current next action

Application startup is accepted for the single-host pilot. All seven groups passed:
native configuration/migrations, HTTP/static, administrator sessions and rejection
checks, dual-stack allowed/denied access, Job/worker concurrency, resource/secret
metadata including heartbeat freshness, and delayed storage observation.

Independent final readback confirmed PostgreSQL, Redis, web, worker and scheduler
running, migration active/exited, zero restarts, five containers, inactive stop
timer and no matching kernel storage/OOM events. The guard did not fire. Services
remain running as authorized at the final startup readback. The published archive
`nautobot-application-startup-v6-accepted` preserves the result and exact inputs;
both CI workflows passed. See [accepted live state](../manifests/accepted-live-state.yaml)
and [history](../HISTORY.md). No fresh host collection was performed during reconciliation.

The operation slot is clean. The read-only running-baseline review completed on
September 23 at 04:44 UTC: 19 comparisons passed, including artifact/image/config
identity, service continuity, limits, heartbeats and effective guard checks.
Private evidence: `/home/aaron/code/.local-evidence/nautobot-running-baseline-20260923/REVIEW.md`.
Idle headroom passed; workload capacity and persistence remain unproven. Retained
cold-copy metadata was checked, not current contents or restore behavior.

Next: implement workload adapters and the bounded sampler, and prepare the
separate persistence operation described in
[workload and persistence preparation](WORKLOAD_PERSISTENCE_PREPARATION.md).
Real application-backup overlap, isolated restore, Caddy onboarding and seven-day
stability remain separate gates. No live mutation was performed during this review.

## Historical preparation and prerequisite results

The following records describe their respective operation times; statements that
services were stopped are superseded by the running startup result above.

Administrator bootstrap is accepted as of September 22, 2026. All five native
checks passed: configuration, no pending migrations, account absence, creation
and exact administrator identity/flags plus positive authentication.
[Bootstrap result](../manifests/administrator-bootstrap-result.json) records the
review. Transient credentials and the disposable container were removed; data
services are stopped, configuration and cold copies remained verified, the guard
did not fire, and the 75-second delayed storage review found no errors.
Published annotated tag `nautobot-administrator-bootstrap-v2-accepted` at
`17dbc01` preserves the consumed definition and accepted result; its remote identity
was verified. The archived result's pending-publication field is historical.
Administrator bootstrap is archived. Do not rerun it: the administrator exists.
The application-startup candidate is implemented with offline rendering,
ordered Ansible startup, native entrypoint, hash-bound launcher, bounded collector
and failure stops. Network packet evidence is accepted and archived. The fresh read-only baseline was collected and reviewed on September 22;
services remain stopped and installed identities match the bootstrap archive.
Concrete session/network/Job probes are implemented locally. Stopped-database
preservation passed on September 22: both volume copies matched content and
metadata, with final stopped-state and identity checks passing. See the
[preservation result](../manifests/startup-preservation-result.json). Preservation
is archived in `nautobot-startup-preservation-v1-accepted`. The refreshed stopped
baseline matched accepted identities. The active startup definition is prepared;
execute only after exact-bundle approval. See [startup execution](STARTUP_EXECUTION.md) and
[startup baseline and recovery](STARTUP_PREFLIGHT_AND_RECOVERY.md) and the sequence in
[bootstrap and startup](BOOTSTRAP_AND_STARTUP.md). No startup bundle is frozen.
The earlier startup-preparation status below is historical. Current startup
acceptance is recorded above; workload and application-aware backup/restore remain pending.

Startup network preflight (September 22) found no target filter rules and direct
same-subnet paths. The historical preflight found the primary selecting floating IPv6 ::56 instead of the
permitted permanent ::53; active Caddy transports have no explicit source binding.
Munin 10.1.3.83 is selected as the non-proxy test vantage. No backend connection
acceptance was tested. See the [network-owner review](../../../homelab-network/Ubiquiti/nautobot-startup-network-preflight.md)
and `manifests/startup-network-handoff.yaml`. Resolve source selection and prepare
same-subnet enforcement before startup activation. The [prepared network design](../../../homelab-network/Ubiquiti/nautobot-backend-network-design.md)
now defines the proposed route/guard scope, rollback and acceptance matrix; it is
implemented and locally tested, with a separate standby-route bundle prepared for
review. That standby attempt failed at the immediate post-reapply route lookup
and rolled back; profile bytes, addresses, boot, services and dual-stack DNS were
verified restored. See the [network operation result](../../../homelab-network/host-network/nautobot/operation-result.json).
The first attempt accepted no preferred-source route. Follow-up found an eight-second standby
Keepalived FAULT interval after IPv6 Caddy health-check failures, followed by BACKUP
recovery. The user accepts brief node interruption with cluster continuity and
node recovery; retain the route approach. Bounded recovery and cluster checks plus retained-state reconciliation are
implemented and the approved retry is accepted for the standby route only.
Its route settled in 6.116 seconds; all 16 sampled health checks passed, with
61.986 seconds after apply completion. A brief node-local IPv6 check failure
recovered without a recorded FAULT transition. See the
[retry result](../../../homelab-network/host-network/nautobot/retry-result.json).
The standby archive is published and its remote tag verified.
[Primary preparation](../../../homelab-network/host-network/nautobot/PRIMARY_PREPARATION.md)
now defines the proposed handoff, route change, failback and rollback scope.
The approved primary handoff/route/failback operation has now passed. Both proxy
preferred sources are verified, original VIP ownership is restored, and both
60-second stability windows passed. Brief transition failures and the existing
dispatcher warning are retained in the [primary result](../../../homelab-network/host-network/nautobot/primary-result.json).
The primary archive tag `nautobot-primary-route-accepted` is published and verified.
The [backend guard preflight](../../../homelab-network/host-network/nautobot/BACKEND_GUARD_PREFLIGHT.md)
passed its first-install baseline, retaining Webmin certificate and existing Munin
IPv6 ACL limitations. IPv4 monitoring works. The guard installation path and recovery reporting are implemented and locally
tested. The first installation stopped at the rootless Podman baseline check due to an
inaccessible inherited working directory. No production guard artifacts/rules
were installed; protected staging remains. See [guard result](../../../homelab-network/host-network/nautobot/guard-result.json).
Staging has since been archived and independently verified; the active path is
absent. The corrected retry guard installation is now accepted: rules and file hashes,
startup dependency, disarmed watchdog and management checks passed. Application
units remain stopped. See [guard retry result](../../../homelab-network/host-network/nautobot/guard-retry-result.json).
The archive commit and annotated tag `nautobot-backend-guard-accepted` are
published and verified.
[Live packet qualification preparation](../../../homelab-network/host-network/nautobot/PACKET_QUALIFICATION_PREPARATION.md)
defines the next bounded listener stage. The live [packet qualification](../../../homelab-network/host-network/nautobot/packet-result.json)
passed for both proxy families and non-proxy denial under current HA ownership.
Listener/tunnel cleanup, unchanged guard and stopped application were verified.
Next archive this result, then prepare the separate startup activation contract.
Actual Caddy traffic, other-ownership packet testing and reboot remain later checks. Packet
qualification and application startup remain separate.
Active service checks alone did not establish historical cluster continuity. [Retry preparation](../../../homelab-network/host-network/nautobot/RETRY_PREPARATION.md). The target guard, live packet
acceptance and reboot persistence remain separate gates. The candidate web unit
now requires the root-owned effective-rule verifier before starting.

Runtime initialization is accepted as of September 22, 2026. The authorized
continuation passed all five native steps in 285.165 seconds, including
`post_upgrade` and the final no-pending-migrations check. Its native plan covered
58 migrations; 56 individual completion messages were recognized by the parser.
Two per-migration completion timings remain unobserved; native completion and
no-pending checks passed. PostgreSQL, Redis and migration are stopped, cold copies
remain verified, the guard did not fire, and the 75-second storage review was quiet.
[Initialization result](../manifests/runtime-initialization-result.json) owns this
acceptance. Terminal commit `6a31396` is preserved by the published annotated tag
`nautobot-runtime-initialization-v1-accepted`; its remote identity was verified
on September 22, 2026. The consumed continuation was cleared before defining
the administrator-bootstrap operation. The archived
result's pending Git archival field records its execution-time state.
[Administrator bootstrap and startup preparation](BOOTSTRAP_AND_STARTUP.md)
records the next two sequential scopes. The bootstrap-only path is implemented
with a strict operation contract, local failure/cleanup tests and native Django
credential-handoff verification. Its first execution failed before creation; the corrected retry is accepted as recorded above. Web, worker,
scheduler, application backup/restore and workload acceptance remain outstanding.

The prerequisite and failed-attempt history below provides context; it does not
override the current accepted initialization result.

Image-store readiness is archived in `nautobot-image-load-v1-ready` at `0dd657b`.
Durable provenance is in [runtime-image-store.json](../manifests/runtime-image-store.json).
V1 through v6 are archived. The approved v7 readiness trial passed all five checks:
settings/plugin registration, native configuration, positive PostgreSQL identity/port,
Redis cache and Redis broker access. All disposable objects were removed. Boot and
configuration continuity passed with 77.8 seconds of quiet delayed observation,
31 samples and a 10.824-second maximum gap. Guard inactive/dead, Result=success.
Result: `manifests/configuration-readiness-result.json`. The consumed operation
is archived as `nautobot-configuration-auth-v7-ready` (`cd15ca7`); the active slot
is clean after accepted administrator-bootstrap archival. Negative security tests were not run and remain unresolved.
This accepts disposable readiness only, not production runtime or administrator login.
Initialization/runtime preparation is below. The fresh read-only
Restic absence preflight passed: Restic 0.18.0, execution user `nautobot`, exact
config-absent status 10, and controller/remote credential cleanup verified.
Result: [restic-preflight-result.json](../manifests/restic-preflight-result.json).
The preflight is archived as `nautobot-restic-absence-20260921-passed`
at `2d96737`. Initialization subsequently passed under its approved bundle:
format 2, full repository ID, empty lock listing, no cache and credential cleanup
verified. [Initialization acceptance](../manifests/restic-initialization-result.json)
owns this result; baseline-era `restic_initialized: false` is historical.
Initialization is archived as `nautobot-restic-initialization-v1-accepted`
at `08a7e62`. The [canary backup/integrity definition](CANARY_BACKUP_INTEGRITY.md)
passed under its approved bundle: one new matching full snapshot ID, successful
backup and full-data check, unchanged source, 75-second quiet kernel review, and
credential cleanup. [Canary acceptance](../manifests/canary-backup-result.json)
records the snapshot identity. The canary is archived as
`nautobot-canary-backup-v1-accepted` at `7521e02`.
The [isolated restore](CANARY_ISOLATED_RESTORE.md) passed under its approved
bundle: exact full snapshot/subtree, independent tree/content comparison,
unchanged source, 75-second quiet cursor-bounded kernel review and credential
cleanup. [Restore acceptance](../manifests/canary-restore-result.json) records the
result. Its published terminal tag is `nautobot-canary-restore-v1-accepted`
at `01bb966`. Initialization stopped before installation and is archived in `nautobot-runtime-initialization-v1-blocked` at `c5040e3`. The corrected retry passed preflight, installed the data services and reached migration, but `post_upgrade` timed out. That failed attempt is historical; the continuation
subsequently completed initialization.
Do not rerun either the consumed backup or restore.
Do not rerun the consumed initialization bundle.
Do not rerun the consumed preflight definition. Historical failed
trial records remain unchanged.
Stage 5, administrator bootstrap, production deployment and application
backup/recovery remain open. Repository initialization and the pre-data canary
backup/integrity/isolated-restore gate are accepted.

Credential provisioning was previously archived at
`nautobot-credentials-v1-provisioned` (`451b82d`). The historical sections below
retain preparation/observation context; older absence and pending-archive claims
are not current-state statements.

## Runtime initialization history and accepted continuation

The approved attempt stopped before runtime installation. Read-only reproduction
identified Podman inheriting inaccessible `/home/ama`; the metadata queries pass
from `/`. No Nautobot units, helper, containers or volumes were created.
The terminal archive in [history](../HISTORY.md) records the result and diagnostic
limitation. Do not rerun the consumed definition. The corrected retry passed the working-directory boundary and preflight, then
installed the private data-service units. Native configuration checking passed;
`post_upgrade` exhausted the bounded native budget. The controller task return
stalled despite migration exiting 69. Independent authorized stops succeeded;
At that failed attempt, PostgreSQL/Redis were inactive, migration had failed,
no containers remained, and both data volumes were retained. Configuration and boot continuity passed; a delayed
kernel review found no storage errors. The retry review in [history](../HISTORY.md)
records the evidence and unresolved command-return gap. Partial database state
requires a reviewed recovery path; do not rerun the first-install bundle. Read-only
follow-up confirmed stopped services, a retained PostgreSQL 17 volume and CPU-heavy
native execution. The precise internal phase remains unknown because output was
discarded. A harmless Ansible failure returned normally with complete diagnostics;
the historical long-running wait remains unreproduced. The
[prepared recovery procedure](RUNTIME_INITIALIZATION.md#recovery-from-partial-initialization)
starts with cold preservation and migration-ledger inspection, not another blind
migration retry. The approved inspection completed on September 22, 2026:
both stopped volumes were independently copied and verified before PostgreSQL
started. Its read-only ledger contains 423 applied migrations. Static comparison
with pinned sources finds 16 core and 10 DNS Models migration files unrecorded;
this was not a complete native migration plan. Initialization was incomplete
at inspection; the later native continuation covered third-party dependencies too.
PostgreSQL stopped afterward, Redis stayed inactive, no containers remain, and
the stop guard was disarmed without firing. The 75-second delayed review found
no storage events. Protected cold copies remain on the host.
[Inspection acceptance](../manifests/database-inspection-result.json) records
identities, hashes and results. The inspection is archived as `nautobot-database-inspection-v1-accepted` at
`16835ad`. A [continuation specification](RUNTIME_INITIALIZATION.md#prepared-continuation-of-retained-migrations)
is implemented with native migration-plan verification, sanitized phase/migration
progress, independent stops and unchanged memory limits. It executed once and
passed; terminal archival is now pending. Do not rerun the continuation or first
installation, and do not discard the cold copies.

The pre-data prerequisite is complete: repository initialization, canary backup
with full integrity checking, and isolated restore are accepted and archived.
The consumed initialization-only operation bound their exact terminal records,
positive application readiness, accepted image IDs, credential provenance and
host identity. Do not rerun consumed prerequisites or add a negative SQLSTATE
qualification gate.

The [initialization procedure](RUNTIME_INITIALIZATION.md) owns the reviewed
implementation, native commands, bounds, acceptance and recovery details. The
launcher and Ansible path select only the private network, two durable volumes,
PostgreSQL, Redis and migration. Six Quadlets are rendered; web, worker and
scheduler units are excluded. The initialization bundle has been consumed. The inspection successor has also been consumed successfully; do not rerun it.

The migration wrapper performs native configuration checking, `post_upgrade`,
a second configuration check and pending-migration checking. It records safe
step outcomes, uses a 1536 MiB ceiling and temporary writable startup paths,
and preserves exact failure evidence. PostgreSQL/Redis keep their existing
ceilings and require healthy private operation and inspected effective limits.
A failed stage attempts independent stops while preserving persistent data.

Local regressions cover the actual selected units and Quadlet parser, native
command sequence and failures, sanitized receipts, data-service assertions,
bundle/prerequisite gates and real Ansible stop sequencing. Database creation occurred during the failed initialization. The continuation
completed the remaining migrations, health and delayed storage checks; the
accepted result above records their scope and diagnostic limitation.

After initialization is accepted, prepare administrator bootstrap and application
startup. The temporary migration static cache does not provide the later web
container's assets: regenerate or supply reviewed static files during that stage.
Before TCP 8080 is published, prove the plan's exact Caddy-node IPv4/ULA source
restriction through the owning network workflow; SSH/Webmin baseline access does
not prove this policy. Login, worker/scheduler health, reboot/logout persistence,
resource headroom, full application backup/restore and pilot soak remain separate
acceptance criteria.

## Historical checkpoint-review boundary

The September 21, 2026 read-only review confirms both new-kernel Webmin
checkpoints passed the bounded polling criteria. The observer completed normally
September 17 and disabled temperature polling as designed. No manual SMART query,
service change, controller mutation or active firewall probe was performed.
Private report: `/home/aaron/code/.local-evidence/webmin-kernel-checkpoint-review-20260921/CHECKPOINT_REVIEW.md`.

The [deployment plan](NAUTOBOT_DEPLOYMENT_PLAN.md) remains the architecture
authority. At that checkpoint review, the [active operation](../manifests/operation.yaml)
remained unaccepted host-baseline convergence. The subsequent stage-3 decision
below accepted the baseline; terminal Git archival and accepted-live identity
reconciliation are now complete; see [history](../HISTORY.md). The inactive Restic contract remains unchanged.

## Numbering and project position

Earlier conversation called storage qualification “Gate 1” and host convergence
“Gate 2.” Those are local acceptance dependencies, not the deployment plan's
numbered execution stages. Use the plan's stage numbers below going forward.

| Plan stage | Position and next evidence |
| --- | --- |
| 1 — Repository plan | Governing definition exists; no architecture change needed for this review. |
| 2 — Repository implementation | Host/preflight and Restic preflight paths exist; runtime rendering/deployment candidates and initialization code exist but are inactive and not live-qualified. Definition work may continue locally. |
| 3 — Host baseline | Accepted baseline only on September 21; terminal evidence recorded. Git archival and terminal accepted-identity reconciliation are complete. No runtime or Restic acceptance. |
| 4 — Dual-stack identity | Permanent ULA and literal dual-stack identity passed. Authorized DNS correction now passes all 24 node/VIP checks and dual-stack FQDN SSH. Stage-4 identity accepted and archived; runtime, Restic and Caddy remain pending. |
| 5 — Nautobot pilot | Not accepted. Requires immutable custom image, reviewed runtime implementation, secrets, data services, migrations, workload and recovery evidence. |
| 6 — Caddy onboarding | Separate Caddy lifecycle after backend readiness; no publication authorized here. |
| 7 — Authority migration | Blocked on reconciliation, full application recovery and seven stable pilot days. |
| 8 — Semaphore | Separate acceptance after Nautobot soak; not part of host remediation. |

Restic initialization and the pre-data canary are separately reviewed dependency
operations between accepted baseline and entrusting application data to storage.
They do not create new deployment-plan stage numbers or accept stage 5.

## Evidence map

Private evidence root on the controller:
`/home/aaron/code/.local-evidence/nautobot-cleanup-polling-20260916/`.
All 78 files listed in its retained `evidence-sha256.json` matched their recorded
hashes during this review. Historical snapshots were not changed. The retained
`preflight-pass.json` contains 59 true checks and `accepted_live_state_written: false`.
Command-success checks are included in that count; it is not 59 independent
architecture acceptance criteria.

| Requirement | Retained evidence and disposition | Remaining boundary |
| --- | --- | --- |
| Packages and residue | Exact required versions; eleven named entries purged; independent audit/residue checks clear. Recovery inputs retained. | No further cleanup indicated by this snapshot; later drift requires review. |
| Services and account | `unit_states`, `zero_failed_units`, `account_identity`, subordinate-range checks and `lingering` passed. | Application services do not exist merely because the user manager works. |
| Rootless capability and memory | `rootless_podman`, `memory_cgroup_available` passed after corrective reboot. | Per-service limits and application logout/reboot survival require pilot tests. |
| Transport and filesystem | Exact quirk, USB root ancestry, driver binding, clean ext4, zero errors and boot continuity passed. | Both checkpoints passed; stage-3 disposition is accepted with the command-counter and SMART limitations recorded below. |
| SMART health | Reduced query health passed and 75-second delayed-error check passed. | Self-test-log data remains unreliable (#648); no self-test or blanket health exception. |
| Thermal and power | Preflight temperature/throttling checks passed; prior retained UniFi Class 4/PoE-good evidence exists. | Explicit port allocation unavailable; workload headroom not established by idle power or temperature. |
| Polling | Initial patched scheduled sequence returned health/44 C; 113.9 seconds of quiet follow-up retained. | September 21 review passed both checkpoints: 5,689 samples, 287 cycles, 1,148 zero-status commands, maximum gap 16 seconds; polling was disabled at completion as designed. See the separate restoration record below for current status. |
| Alerts | Earlier smartd corrected-recipient test B was received by the user. | Daemon activity alone does not prove delivery; this review sends no new test and does not qualify Needrestart alerts. |
| Listeners and identity | Required baseline endpoints, optional loopback stats endpoint and permanent ULA passed. | Baseline reachability and approved deployed-rule evidence passed; external IPv6 testing remains unavailable. DNS/PTR and application exposure follow in later stages. |
| Memory and workload | Controller available; no application workload acceptance evidence. | At least 1.5 GiB available during imports, exports, backups and Jobs; no OOM, persistent swap growth, throttling or sustained over-80 C. |
| Backup and recovery | Provider acceptance and old repository-absence result retained in inactive contract. | Fresh absence review, initialization, canary upload/full check/isolated restore, then real application recovery. |
| Terminal baseline | Preflight passed, mutation not attempted by that preflight. | Independent review and scoped baseline acceptance completed; Terminal archival and accepted identity reconciliation are complete. |

The isolated boot-time MMC/SDIO warning is documented in the private current-boot
review as the onboard Wi-Fi path, without demonstrated USB-root impact. Preserve
that finding; do not silently classify it as a repaired fault or Wi-Fi acceptance.

## Consistency decisions

The convergence guide now labels earlier blockers as historical and points here
for current gaps. Package and boot-review descriptions in the operation no longer
say fresh comparison is missing after the completed preflight. Webmin guidance
now distinguishes its original 7.4 isolation trial from `start-existing` repeat
observations. Existing desired-state limits and deployment-plan criteria agree;
no architecture or desired-state change was needed. Smartmontools and Restic
retain their own policy and procedure ownership.

Current document edits change future bundle inputs. They do not change or
reauthorize the preserved cleanup, preflight or observer bundles. Review those
executions against their retained source snapshots, not today's working tree.

## Next decision

Both Webmin checkpoints passed. The authorized September 21 final stage-3 decision
accepts the host baseline, with the limitations below:
internal IPv4 SSH/Webmin reachability and Munin polling passed, and controller
rules match the intended IPv4/IPv6 policy, but external IPv6 denial remains untested.
The user has no external IPv6 vantage. The approved deployed-gateway inspection
now corroborates the controller policy: the target IPv6 prefixes map to the LAN
bridge and WAN forwarding permits established/related traffic, drops invalid
traffic, then drops remaining traffic. The external test remains unperformed;
rule readback is the approved alternative evidence, not an end-to-end test.
Private evidence: `/home/aaron/code/.local-evidence/nautobot-gateway-review-20260921/REVIEW.md`.
Terminal baseline drift/provenance review is complete. Required packages, account,
services, rootless capabilities and boot continuity match the retained baseline.
The subsequent authorized attribution reproduced one SCSI command-counter
increment during Webmin's `parted` disk-discovery listing; direct identity, health
and attributes/error-log SMART reads produced none. All four had quiet 75-second
follow-ups. The historical one-per-cycle explanation is supported, not proven
for every event; the exact SCSI opcode remains uncaptured. The attribution blocker
is resolved and baseline acceptance records that limitation.
Private attribution: `/home/aaron/code/.local-evidence/scsi-counter-attribution-20260921/RESULT.md`.
Earlier decision:
`/home/aaron/code/.local-evidence/nautobot-terminal-review-20260921/ACCEPTANCE_DECISION.md`.

The self-test-log limitation is command-specific; retained reduced health evidence
can satisfy baseline health recording without a new patch. Webmin certificate trust
is unresolved but is a separate component follow-up, not a new stage-3 requirement.
Private decision: `/home/aaron/code/.local-evidence/nautobot-stage3-review-20260921/ACCEPTANCE_REVIEW.md`.

The decision is archived under the annotated tag recorded in [history](../HISTORY.md).
The [accepted identity](../manifests/accepted-live-state.yaml) records the real
terminal commit/tag and evidence hashes. The active slot is clean. Next prepare
stage 4 under the owning DNS/network procedures.
Explicitly carry
application-dependent host criteria forward to stage 5; baseline acceptance
must not claim full workload acceptance. Do not waive any requirement to break a
dependency cycle. The governing plan now explicitly distinguishes stage-3 baseline acceptance from
stage-5 full workload acceptance; neither record substitutes for the other.
The next-stage preparation below records concrete inactive
operation drafts and the remaining readiness inputs.

## Webmin polling restoration

On September 21, separately authorized restoration removed only `collect_notemp=1`.
Two scheduled patched cycles returned 44 C; eight expected commands succeeded,
with more than 75 seconds of quiet follow-up after the final command. Independent
readback verified configuration, source/binary integrity and tracer detachment.
Polling remains enabled; the verification observer completed. The earlier accepted
baseline snapshot retains its historical disabled-polling state. The documented
SCSI command-counter and self-test-log limitations remain unresolved.
Private evidence: `/home/aaron/code/.local-evidence/webmin-polling-restoration-20260921/RESULT.md`.

## Next-stage preparation after host convergence

## Scope and activation

These are local planning drafts, not executable operations or live authorization.
They follow the evidence map above and preserve the
single active slot in `manifests/operation.yaml`. Do not replace that slot until
host-baseline terminal acceptance and authorized archival are complete. No host
contact, image pull/build, secret resolution, load test or service transition is
part of this preparation.

The immediate next action is stage-4 identity preparation using the accepted
host-baseline identity. Archival and identity reconciliation are complete. The
inactive Restic initialization contract still requires separate review and fresh
repository-absence evidence before activation.
Do not retry historical baseline v3. Commit/tag/push, future live collection and
mutations remain separately scoped. The completed observer is untouched.

## Readiness package for each later operation

Before activation, specify one target/stage, accepted predecessor identity,
source revision, exact non-secret inputs, ordered actions, independent acceptance
checks, bounded evidence and stop/recovery behavior. Validate the implementation
and bind every execution input to a new SHA-256 bundle. Present its exact command,
mutation boundary and rollback for authorization. These drafts deliberately have
no executable command or bundle hash: live readiness inputs and implementation qualification
are not yet complete. Never reuse a historical bundle for changed files.

## Stage 4 — identity and exposure preparation

Owner: Nautobot coordinates; homelab-network owns controller/NetworkManager
changes, homelab-dns owns DNS, and Caddy owns publication.

### Initial prepared scope and source findings (historical)

Initial preparation was repository-only. The subsequent authorized read-only
collection and subsequent DNS deployment are recorded below. This initial
preparation made no production changes; it is not the current deployment status.

The network owner's [ULA operation](../../../homelab-network/Ubiquiti/j2-svpi4mf-ula-operation.md)
still describes adding the address, but stage-3 evidence already observed it.
Verify active and persistent configuration before proposing any correction; do
not replay the addition or remove the existing ULA as cleanup. Correct existing
state calls for owner-record reconciliation, not unnecessary mutation.

The DNS owner's [local-zone source](../../../homelab-dns/Unbound/configs/pihole-local-zone.conf)
initially lacked host A/AAAA/PTR entries. That gap was corrected by the authorized
deployment recorded below. The governing plan requires the exact host records below.

### DNS acceptance matrix

Endpoint identities are from the DNS owner's
[dual-stack runbook](../../../homelab-dns/Keepalived/docs/keepalived-dual-stack-runbook.md).
Reconfirm them during collection; the proxy VIP is not a DNS endpoint.

| Resolver | IPv4 | IPv6 |
| --- | --- | --- |
| Pi-hole primary | `10.1.0.53` | `fd36:5aa8:6971:1::53` |
| Pi-hole secondary | `10.1.0.54` | `fd36:5aa8:6971:1::54` |
| Shared DNS VIP | `10.1.0.55` | `fd36:5aa8:6971:1::55` |

Run all four queries against each of the six endpoints: **24 results**.
An AAAA query over IPv4 does not prove IPv6 DNS transport.

| Query | Required answer set |
| --- | --- |
| `j2-svpi4mf.local.theama.co.` A | `10.1.2.170` only |
| `j2-svpi4mf.local.theama.co.` AAAA | `fd36:5aa8:6971:1::170` only |
| Reverse of `10.1.2.170`, PTR | `j2-svpi4mf.local.theama.co.` only |
| Reverse of `fd36:5aa8:6971:1::170`, PTR | `j2-svpi4mf.local.theama.co.` only |

Retain response status, answering endpoint, transport, question, answer records,
TTL, time, process status and stderr. Require NOERROR and exact answer sets,
normalizing only DNS name case/trailing dots and equivalent IPv6 spellings.
Empty answers, extra addresses, CNAME substitutions, different PTR targets,
SERVFAIL, NXDOMAIN and truncation do not pass. Limit each query to one attempt,
a three-second DNS timeout and ten-second outer limit. Record a TCP retry after
truncation separately; do not replace the original failed observation.

### Ordered read-only host and network review

1. Validate the accepted-state schema, terminal tag/commit, semantic hash and
   evidence hashes. Record source revisions and dirty state for the three owner
   repositories; uncommitted intent is not deployed evidence.
2. Record the administration vantage's source addresses and routes. It must reach
   both IPv4 and ULA endpoints. If the controller lacks IPv6 routing, identify an
   approved internal dual-stack vantage before running that subset. No route is
   an incomplete test, not proof of target failure. Approved administration scope
   is `10.1.0.0/22`; Munin master is `10.1.3.83`, with SSH user `pi`.
3. Connect as `ama` to `10.1.2.170`, using existing credentials and strict host-key
   verification. Capture hostname, boot ID, `eth0` MAC, active profile UUID, IPv4
   and IPv6 addresses and routes. Reuse the read-only selected-property commands
   from the network-owner preflight, including autoconnect and address lifetimes.
   Do not collect secrets or full connection files; do not modify, clone, reapply
   or checkpoint NetworkManager profiles.
4. Require `Wired connection 1` bound to `eth0`, autoconnect enabled, IPv4 and IPv6
   methods `auto`, IPv4 `10.1.2.170/22`, gateway `10.1.0.1`, and persistent plus
   active `fd36:5aa8:6971:1::170/64`. The permanent ULA must have permanent
   preferred/valid lifetimes with no tentative or DAD-failed flags. Preserve the
   additional SLAAC ULA, delegated global IPv6 and RA-supplied IPv6 default route.
   Record dynamic prefixes/lifetimes as observations rather than fixed expectations.
5. Verify the fixed IPv4 assignment to MAC `dc:a6:32:eb:49:69` and relevant ULA
   allocation/neighbor evidence using the [UniFi access procedure](../../../homelab-network/Ubiquiti/UNIFI_ACCESS.md).
   Use its TLS-verified canonical hostname and Doppler references. Limit readback
   to relevant mappings; an empty neighbor table alone cannot prove no duplicate.
6. Collect the DNS matrix. If source and answers differ, inspect only relevant
   deployed local-zone/forwarding entries on both DNS nodes under owner read-only
   authorization. Preserve differences; do not export full resolver configuration.
7. Independently connect by SSH to the IPv4 literal, permanent ULA, and FQDN forced
   separately over IPv4 and IPv6. Each must return the same hostname and boot ID.
   Retain resolved peer addresses and authenticated host-key fingerprints. Use
   strict host-key verification, batch authentication and bounded timeouts. Missing
   trusted alias keys require identity verification, never disabled checking or
   blind trust in a key scan.
8. Repeat address/route/profile readback and compare with step 3. Boot, stable
   address, profile or default-route loss blocks advancement. Explain dynamic
   prefix changes. Carry forward baseline firewall evidence and investigate any
   relevant drift; listener presence alone is not policy verification.

The missing external IPv6 packet test remains a documented limitation, with the
stage-3 approved deployed-rule alternative. Do not claim end-to-end denial.
Exact Caddy node sources and port 8080 enforcement belong to stage 5. Keep Webmin
polling, SMART policy, packages, boot settings and firewall configuration unchanged.

### Evidence and next authorization

Preserve per-probe stdout/stderr/status and start/end timestamps privately in a
protected directory. Bound each stream to 1 MiB and the collection to 16 MiB;
truncation, interrupted SSH and timeouts are incomplete evidence. Hash the files
and index. Record expected/observed values with passed, failed, incomplete or
invalid dispositions. Every required criterion must pass before a separate
stage-4 acceptance decision; this preparation creates no accepted identity.

If records are missing, prepare the four host records in the DNS owner's source,
review both reverse-zone forwarding paths using its
[Pi-hole/Unbound guide](../../../homelab-dns/Unbound/docs/Pi-hole-with-Unbound-local-zone-guide.md),
and prepare an HA-aware deployment. Any mutation requires an exact diff/bundle,
per-node backup, syntax checks, scoped reload, independent DNS checks and exact
rollback. Do not change VIP ownership or introduce failover here. A network
correction similarly requires its owner's recovery and rollback procedure; the
old ULA operation explicitly stops if the permanent address already exists.

### Authorized collection result

The September 21 read-only review verified accepted-baseline provenance, unchanged
boot/profile/address/route state, permanent ULA persistence and the UniFi fixed
IPv4/MAC mapping. Literal IPv4 and ULA SSH returned the same host/boot. ULA SSH
used strict checking against the already trusted IPv4 host identity via an
explicit host-key alias; no known-hosts entries were changed.

All **24 DNS queries returned NXDOMAIN**, so stage 4 failed its DNS criteria.
Both nodes' deployed local-zone fragments lack the host records; relevant
forward and reverse forwarding entries are present. Both FQDN SSH attempts failed
name resolution. These failures are preserved separately from the successful
literal-address tests. The observed ULA neighbor matches the target MAC, but this
does not establish absence of every dormant duplicate allocation. External IPv6
packet denial remains the previously documented limitation.

Private report: `/home/aaron/code/.local-evidence/nautobot-stage4-review-20260921/REVIEW.md`.
The private index retains command results, timestamps, source revisions and hashes.
No production state changed; polling and the accepted stage-3 snapshot remain intact.

**DNS correction deployed and verified (September 21):** the four host records
are installed on both nodes through the DNS owner's
[deployment procedure](../../../homelab-dns/Unbound/docs/host-record-deployment.md).
The initial attempt and verified rollback remain historical evidence. The
corrected reload-settlement gate passed 14 offline tests and the authorized live
retry on each node. Both reloads recorded the transient state and settled.

Pi-hole initially retained negative PTR answers despite correct Unbound data.
The user separately authorized a Pi-hole DNS restart on each node. Secondary
restart and its complete gate preceded primary deployment. All **24 DNS checks
now pass**, including both PTR records through both nodes and both DNS VIPs.
FQDN SSH over IPv4 and IPv6 authenticated the expected host and unchanged boot.
Services and existing local/public DNS controls passed; primary retained both
DNS VIPs in readbacks. Original backups and failed-query evidence are preserved.

Private result:
`/home/aaron/code/.local-evidence/nautobot-dns-readiness-20260921/RETRY_EXECUTION_RESULT.md`.
The subsequent stage-4 technical acceptance review passed, with fresh per-query
DNS evidence, FQDN peer/key identity and post-DNS profile/route continuity.
Private review: `/home/aaron/code/.local-evidence/nautobot-stage4-acceptance-20260921/REVIEW.md`.
Stage-4 identity is now accepted and archived in annotated tag
`nautobot-dual-stack-identity-v1-accepted`; see [history](../HISTORY.md).
The accepted-state manifest retains stage-3 provenance and adds independent
stage-4 identity/provenance. The operation slot remains clean. Remote rollback
backups remain retained; no further ULA addition is needed. Next is stage-5 pilot
readiness, with image/configuration/runtime and Restic stages separately reviewed.

## Stage 5 — runtime and workload draft

Prerequisites: accepted scoped baseline, identity/exposure prerequisites, immutable
ARM64 custom-image digest, reviewed Quadlets/Ansible deployment, external secret
references, approved recovery identity and application configuration. The existing
`desired-state.yaml` supplies base digests and service intent; it does not supply
a finished custom-image deployment digest. Verify those inputs when defining the
pilot rather than silently updating versions in this planning task.

### Historical readiness review — September 21, 2026

Readiness preparation is authorized; runtime deployment is not. Stage-3 and
stage-4 terminal tag/commit identities were reverified, and the stage-4 evidence
hash matches its archive. The operation slot remains clean. Local desired-state,
build-input and workload consistency validation passed. The preceding archival
commit hooks also passed runtime/Restic tests; that is local contract evidence,
not live ARM64 qualification. No images, credentials or host state were changed
in this review.

| Prerequisite | Verified status | Required completion |
| --- | --- | --- |
| Host baseline and dual-stack identity | Accepted terminal records present; provenance reverified | Fresh bounded drift check before a live pilot |
| Custom image | Bounded ARM64 qualification passed and is archived; immutable identity recorded in qualified-image.json | Verify archive load into the runtime store and full application configuration under a separate operation |
| Build location | User selected `j2-svpi4mf` for native ARM64 qualification | Build-host preflight before the exact build bundle |
| Application credentials | homelab-dev/prd_nautobot and admin identity approved; config absent at preparation | Execute separately reviewed creation and protected injection; mappings prepared |
| Recovery identity | `j2-svpi4mf.local.theama.co` approved | Use in renderer and actual ALLOWED_HOSTS |
| Application configuration | Renderer emits a non-secret contract only | Prepare actual protected settings and verify against the built image |
| Runtime activation | Launcher expects `nautobot_pilot`; schema has no executable runtime branch | Review schema, launcher and playbook together, binding stage-3 and stage-4 archive evidence rather than relying only on booleans |
| Backend firewall | Stage-3 management policy accepted; application 8080 policy not accepted | Owner-reviewed exact Caddy-node IPv4/IPv6 sources, allowed/denied tests and rollback |
| Data recovery | B2 provider acceptance exists; Restic initialization/canary/application recovery remain separate | Revalidate absence and secret availability, then separately review initialization, upload and isolated restore |
| Workload | Synthetic fixture contract exists | Implement/qualify imports, Jobs, sampler, application backup and recovery before workload acceptance |

### Recovery and credential decisions

The user approved `j2-svpi4mf.local.theama.co` as the recovery identity.
This does not widen port-8080 access: application host-header acceptance and
firewall access are separate. Review an SSH tunnel if administration recovery
needs access while retaining the Caddy-only backend policy.

The user selected Doppler for all application credentials and confirmed that the
entities have not been created. Proposed project/config is `homelab-dev` /
`prd_nautobot`, following existing repository naming. The user approved this mapping on September 21; names-only inspection confirmed
the config is absent. Credential creation and injection have not occurred.

| Logical reference | Proposed key | Consumers |
| --- | --- | --- |
| `django_secret_key` | `NAUTOBOT_DJANGO_SECRET_KEY` | Migration, web, worker, scheduler |
| `postgresql_password` | `NAUTOBOT_POSTGRESQL_PASSWORD` | PostgreSQL and application services |
| `redis_password` | `NAUTOBOT_REDIS_PASSWORD` | Redis and application services |
| `initial_administrator_credential` | `NAUTOBOT_INITIAL_ADMIN_PASSWORD` | One-time bootstrap only |

Administrator username `admin` is approved. The approved email is retained in
private bootstrap inputs rather than copied into the public repository.
Keep existing Restic/B2 references under their owning configurations; do not copy
or rotate them during application setup. Review generation ownership, access,
recovery and protected injection before creating entities. Never put values in
Git, command arguments, build layers or evidence. Do not distribute bootstrap
credentials to persistent application services.

Missing production credentials do not block image qualification. Static checks
need none; any isolated application checks requiring credentials must use
operation-owned disposable values and explicitly scoped cleanup. Such checks
do not establish production credential delivery readiness.

### Prepared build-host preflight

Target `ama@j2-svpi4mf.local.theama.co`; future build context is rootless
`nautobot`. Before host contact, authorize bounded read-only collection of:

- Hostname, boot ID, architecture, CPU/load, memory/swap, free space/inodes and
  mount options for `/var/lib/nautobot`.
- Account UID/GID/home, linger and user-manager state, and effective memory/CPU
  cgroup delegation, compared with accepted baseline evidence.
- Podman version and selected rootless storage/configuration metadata. Do not
  initialize a new store or start an inactive user manager to satisfy a check.
- Existing image/container/network/volume metadata without credentials or full
  environment/inspect dumps. Identify shared objects before proposing cleanup.
- Failed units, temperature/throttling and bounded current-boot kernel/storage
  errors. No SMART queries, self-tests, package changes or restarts.

Retain timestamps, statuses, bounded streams and source identities in a new
protected evidence directory. No pull, build, container creation, credential
change or monitoring interruption belongs to this preflight. Unavailable
inspection is a readiness gap, not proof that a store is empty.

Require accepted identity/boot continuity or explain drift before progressing.
Select explicit CPU/memory/disk/time bounds using measured headroom, preserving
the plan's host-resource margin. Do not infer disk requirements from compressed
image size. Insufficient resources require another build location, not weaker
production safeguards. Prepare the exact hashed build/qualification bundle only
after reviewing these observations; execution requires separate authorization.

### Authorized build-host preflight result — September 21, 2026

Read-only collection passed for preparing the bounded build operation. Accepted
boot/ARM64 identity and account 999:985 match; the lingering user manager has CPU,
memory and pids delegation. Podman 5.4.2 uses an existing rootless overlay store
with zero images/containers/volumes and only the default bridge. Available memory
was 7.34 GiB, disk space about 874 GiB, swap use zero, temperature 49.2 C and
throttled status zero. No failed units; ext4 error count zero. The bounded kernel
error-pattern query found no matches; this is not a full journal or soak acceptance.

An inherited inaccessible working directory caused the first metadata inspection
to fail; repeating from `/` succeeded. Original failures remain preserved.
Private result: `/home/aaron/code/.local-evidence/nautobot-build-preflight-20260921/REVIEW.md`.

The resource-limited image qualification was authorized and executed on September
21, 2026. It failed at the first containerized RUN step: crun could not write to
the selected service parent's cgroup.procs (`Device or resource busy`). The base
image was pulled into the isolated store; no qualified image was produced.

The watchdog stopped the worker and retained a failed terminal result. Independent
readback confirmed no remaining worker cgroup, unchanged boot, zero ext4 errors
and no cursor-bounded kernel events beyond the delayed-error interval. Both owned
units remain failed/stopped and partial artifacts remain for review. This is not
runtime acceptance or a completed build-resource qualification.

Private execution review and frozen approved inputs:
`/home/aaron/code/.local-evidence/nautobot-image-build-20260921/REVIEW.md`.
The operation manifest retains the exact consumed definition; its preparation-time
false authorization fields do not describe the later external hash approval.
Do not rerun it or treat it as a fresh executable definition. Terminal archival is
pending; accepted-live state remains unchanged.

### Next concrete operation: correct image qualification cgroup placement

Diagnose and locally test the cgroup placement failure without weakening the
2-CPU/3-GiB/no-swap envelope. Preserve the failed operation and its residue before
preparing separately authorized retry and cleanup behavior. The procedure and
remaining image qualification requirements are in [IMAGE_BUILD.md](IMAGE_BUILD.md).
The cgroup correction is now locally tested: the OCI build path names a leaf
below the limited service parent. A private retry candidate uses fresh paths and
retains the failed operation in the active slot pending archival. Its launcher
requires the annotated published failure tag and exact sanitized terminal evidence
before host staging. Its playbook verifies stopped predecessor state before
clearing only the two retained failed-unit markers. No live retry, marker reset,
cleanup or Git publication has occurred during correction/preparation.

The user authorized correction, offline testing and preparation of the retry
bundle, not execution. The candidate review is retained under
`/tmp/nautobot-image-retry-validation/REVIEW.md`. Failure archival/publication and
exact-hash retry authorization remain next. The original qualification checklist
remains below.

1. Bind the existing Containerfile, requirements lock and desired-state hashes.
   Preserve the accepted versions; confirm registry/platform manifests and wheel
   integrity without silently selecting newer releases.
2. Read-only preflight the selected build host's architecture, Podman ownership,
   storage headroom, available resources and isolation. If using the production
   host, explicitly review build resource limits and impact on monitoring.
3. Define Podman image pull/build scope and an isolated validation environment.
   No production credentials, production volumes, service installation, migration
   or public backend listener belongs to this operation. Any disposable database
   needed for application checks must have explicit names, limits and cleanup.
4. Verify image architecture, installed Nautobot/DNS Models versions, dependency
   consistency, executable resolution and settings/plugin loading. Distinguish
   checks that need an isolated database from static import/metadata checks.
   Validate the service command forms against this exact image before deployment.
5. Record the resulting immutable OCI manifest digest and a reproducible transfer
   method. The local `localhost/nautobot-homelab` repository is not a remotely
   pullable registry; do not confuse a local image ID with a deployable manifest
   digest. Define save/load digest verification or a separately authorized registry
   publication path before host provisioning.
6. Retain sanitized build/qualification evidence and exact created-object ownership.
   On failure, stop; remove only proven operation-owned disposable resources under
   the reviewed cleanup scope. Do not broadly prune Podman or remove shared bases.
7. Bind the reviewed inputs and commands into an exact authorization bundle before
   build execution. Once qualified, use the real digest and approved recovery
   identity to render and validate the actual runtime artifacts.

After image qualification, finish secret/configuration provisioning and firewall
readiness, then prepare the executable first-install contract. Prove first-install
absence, effective memory limits and startup ordering in the live pilot; keep
logout/reboot, representative workload, full recovery and seven-day soak as
subsequent acceptance checks. Restic initialization may be prepared independently
now that baseline acceptance exists; it is not automatically authorized here.

| Check | Exact acceptance basis | Stop/recovery boundary |
| --- | --- | --- |
| Memory ceilings | Effective service/container cgroups match web 1536, worker 1536, scheduler 384, PostgreSQL 1536 and Redis 512 MiB; trace each cgroup to its expected rootless process. | A missing/unlimited/wrong limit blocks workload. Correct only reviewed units; preserve service data. |
| Enforcement | Inspect effective kernel limits, not only generated configuration. Any deliberate limit-crossing test must use a separately bounded disposable workload, never the database/application. | No host-wide OOM provocation; preserve evidence and stop the test on guard breach. |
| Startup ordering | Private PostgreSQL/Redis ready; migration succeeds before web/worker/scheduler; worker concurrency 2. | Stop dependents after migration failure; no automatic database downgrade or volume deletion. |
| Backend health | `/health/` returns 200 over both permanent backend families. | No Caddy publication on failure. |
| Exposure | Only intended backend bindings; 8080 allowed solely from exact Caddy nodes; no published PostgreSQL/Redis; denied clients cannot reach backend or baseline management through global IPv6. | Roll back only reviewed network changes under their owner; do not widen allowlists to pass tests. |
| Persistence | Rootless services remain healthy after administration logout and after a separately authorized reboot, with new boot identity and data continuity. | Confirm recovery access first; retain old deployment/configuration and record any partial startup. |
| Representative load | Imports, exports, backup and Jobs complete with at least 1.5 GiB MemAvailable, no OOM/throttling, no persistent swap growth or sustained temperature above 80 C. Record storage errors and service health throughout. | Stop load on errors or resource guard breach; do not tune limits automatically. |
| Recovery and soak | Full application recovery passes; seven days stable pilot operation precede authority migration/Semaphore. | Failures retain evidence; a restart of the acceptance window needs an explicit reviewed reason. |

The inactive `manifests/workload-test.yaml` now specifies the synthetic fixture,
Jobs, phase durations, sampling, idle comparisons and stop/trend rules.
[Operator procedures](OPERATIONS.md) describe rendering and workload qualification.
Before workload readiness, review the pinned-API import/Job adapters, actual
application backup dataset and comparison with intended production scale. Do not
claim representative capacity from an unqualified synthetic fixture.
Capture a journal cursor before workload or service mutation. Correlate sample
coverage/gaps and post-query delayed events, not just successful command exits.

For first deployment, rollback can stop only operation-owned services and restore
reviewed configuration, retaining all created volumes and evidence. Once schema
migration or data writes occur, an older image is not automatically safe: prepare
a verified compatible recovery snapshot/dump and explicit data-recovery decision.
Do not promise automated rollback across an unreviewed database migration.

## Restic A — repository initialization draft

Owner: Nautobot operation state; reusable implementation/procedure belongs to
[Restic](../../restic/docs/REPOSITORY_INITIALIZATION.md); B2 owns provider identity.
Use the unchanged [inactive contract](../manifests/deferred-restic-initialization.yaml).

After terminal baseline acceptance, review reactivation of that contract into the
single slot. Preserve its exact accepted B2 endpoint/bucket/prefix, seven scoped
capabilities, password/key references, independent password-recovery locator and
execution user. Revalidate secret-reference availability without values in output.
Fresh separately authorized read-only preflight must establish exact repository
absence; the old exit-10 record is historical only. Ambiguous access failure stops.

The initialization playbook, guarded launcher and node evidence helper now exist
with offline failure-injection tests. See the owning Restic initialization procedure
for entrypoints and remaining qualification. The historical inactive contract still
records its original unimplemented state; update it only during explicit reactivation
review, alongside the frozen schema and accepted predecessor binding.
Acceptance requires all criteria in the owning initialization procedure and a
terminal repository identity before any upload stage.

Recovery: before mutation, remove only proven owned transient files. After any
initialization attempt, stop and preserve evidence; no automatic retry, remote
delete, password rotation or bucket cleanup. Future classification is read-only.

## Restic B — pre-data upload and integrity draft

Prerequisite: accepted repository ID and terminal initialization record. Use the
exact deterministic canary and isolated source described in
[ISOLATED_BACKUP_RESTORE.md](ISOLATED_BACKUP_RESTORE.md), not application data.

Authorize source creation and backup upload explicitly. Capture before/after
snapshot sets and require exactly one new full ID matching host, path and tag.
Perform the required full data integrity check; bind its result to that repository
and snapshot evidence. Preserve the canary's independent hashes and metadata.
No restore, retention, prune, unlock or repair is implicit in this stage.

On failure after upload, retain the snapshot and evidence. Do not retry the backup
automatically if snapshot identity is ambiguous. Cleanup is limited to separately
reviewed, proven operation-owned local paths; no automatic remote deletion.

## Restic C — isolated canary restore draft

Prerequisite: accepted upload result and exact full snapshot ID from stage B.
Separately authorize restore into a new empty mode-checked directory outside the
source, owned by nautobot and on the reviewed filesystem. Reverify repository and
snapshot identity. Compare all restored paths, sizes, modes and content hashes to
the independent canary definition; inspect cursor-bounded storage errors.

Acceptance proves only pre-data upload/integrity/restore. Preserve the restored
tree and evidence if comparison fails. No live-path overwrite, `latest`, snapshot
deletion or implicit repair. B and C remain parts of the existing canary contract,
with separately reviewed mutation stages; no competing active manifests.

## Restic D — application backup and full recovery draft

This is a later stage-5 requirement, not satisfied by the canary. Prepare a
PostgreSQL custom-format dump plus media, required configuration, image/dependency
manifests, Quadlet/config hashes, versions and migration state. Define dump
consistency, isolated restore identities, secret injection and prevention of
outbound Jobs/schedules before implementation approval.

Use the exact uploaded snapshot and full integrity check. Restore into isolated
volumes/services, import the dump and verify application health, representative
records/media and migration compatibility without touching production. A byte
comparison alone does not prove database/application recovery. Keep backup upload
and recovery execution separately authorized, with no live promotion or deletion.

Nightly schedule and 7-daily/5-weekly/12-monthly retention are desired policy in
the deployment plan. Creating schedules and destructive retention execution require
their own reviewed scope; they are not side effects of initialization or a test.

## Repository audit remediation

Candidate code now checks Redis metadata as JSON, rejects existing Nautobot runtime
objects, and attempts all Restic credential removals before failing cleanup. Desired
state is checked against image references, secret consumers and build inputs. The
workload contract has a schema and drives fixture cardinality. CI includes the
Nautobot hooks and runtime/Restic failure tests with a pinned Quadlet parser.
These are local implementation changes, not live acceptance or checkpoint results.

The historical backup/restore schema is definition-only. The retained initialization
record still describes its original unimplemented review; candidate implementation
exists but activation remains unqualified. Runtime stage-schema activation, workload
Jobs/import adapters/sampling, actual backup and isolated restore remain outstanding.
Stage-3 baseline and stage-5 workload acceptance are explicitly separate in the plan.

The backup/restore definition now replaces the old soak predecessor with explicit
host-baseline and repository-initialization terminal proofs. Exact ordered actions,
acceptance, boundaries and evidence lists replace permissive arrays. Execution is
still blocked, and future executable stages must independently verify those proofs.
Historical authorization labels and structured status provenance now distinguish
retained observations from current authority. Missing event times remain explicitly
unknown; no live status refresh was performed for this repository correction.

## Baseline evidence still to collect

The master plan now references the qualified `sntjmicron` NVMe profile rather than
SAT, and explicitly requires management/monitoring firewall evidence at stage 3.
Use the [baseline firewall matrix](HOST_BASELINE_CONVERGENCE.md#baseline-firewall-evidence-required-for-terminal-acceptance)
to prepare the separately authorized read-only network review. Approved admin and
Munin source identities, applicable controller policy and group membership, denied
client vantage points, and actual IPv4/IPv6 results remain unverified acceptance
inputs. No firewall evidence was collected by this documentation reconciliation.
A passing polling checkpoint or listener inventory cannot close those rows.

Future Webmin HTTPS access is intended through Caddy under its separate onboarding
lifecycle; direct Webmin certificate replacement is not the selected follow-up.
The SMART upstream issue remains awaiting maintainer response per the user. No
background issue-monitoring task or upstream publication is created by this record.

### Authorized image retry

The failed v1 definition and sanitized evidence are archived in annotated,
published tag `nautobot-image-qualification-v1-failed` at commit `64c5c13`.
The active slot now contains the exact authorized v2 retry definition from bundle
`09b71931b20200846384fbc3e1217187adcc600fd481674a63d8f928f2a03224`.
Execution approval covers the frozen bundle; preparation-time false authorization
fields remain part of that exact definition. No runtime acceptance is implied.

### Bounded image retry result

The authorized retry passed its defined static image checks and delayed-error
observation on September 21, 2026. Image ID, OCI manifest digest and archive hash
are retained in [image-qualification-result.json](../manifests/image-qualification-result.json).
Independent controller verification matched all archive/blob digests and ARM64
identity. Forty-one samples, maximum gap 5.39 seconds, no storage/OOM errors and
confirmed stopped workers support this bounded result. Production runtime is not
accepted; start/celery help returned general help, not operational service proof.

Private review: `/home/aaron/code/.local-evidence/nautobot-image-retry-20260921/REVIEW.md`.
Successful-operation archival remains pending; the active slot retains the exact
executed v2 definition. No new build or cleanup should run from it. Next preparation
is artifact-identity reconciliation and application credential/runtime readiness;
Doppler entity creation, deployment and Restic stages remain separately scoped.

### Qualification archival and runtime preparation

The successful v2 qualification is published at tag
`nautobot-image-qualification-v2-qualified`, commit `77ab94a`. The active operation
slot is clean. Qualified artifact provenance is retained in `qualified-image.json`;
host/runtime acceptance boundaries remain unchanged. Eleven runtime artifacts
were rendered with the real OCI manifest digest and approved recovery identity.
The renderer verifies archived evidence before rendering operator inputs.

Doppler preparation confirmed project `homelab-dev`, environment `prd`, target
config `prd_nautobot` absent, and parent `prd` exposing only the three Doppler
metadata names. No secret values were retrieved or created. Four mappings and
generation requirements are in `credential-preparation.json`; the approved
bootstrap email remains in private evidence. See
[CREDENTIAL_PREPARATION.md](CREDENTIAL_PREPARATION.md) for provisioning, injection,
validation and recovery boundaries. Runtime executable contracts, actual settings,
image-store load, firewall and pre-data Restic checks remain pending.

### Credential operation prepared

The single active slot now defines `nautobot-credentials-v1`: create the selected
Doppler config and four application secrets, then inject protected environment
files, non-secret settings and the Redis Podman secret. No administrator password
is injected and no containers or application services are started. The controller
bounds private output and deletes temporary secret payloads; Ansible owns host
preflight, injection and private readback. Existing configs/paths/objects and
ambiguous failures stop without overwrite, rotation or automatic cleanup.

Implementation and tests are linked from [CREDENTIAL_PROVISIONING.md](CREDENTIAL_PROVISIONING.md).
Settings names were verified against the qualified image's source. No Doppler or
host mutation has occurred in this preparation; exact-bundle execution approval
remains required. Application configuration/runtime acceptance remains separate.

### Credential preflight correction

The first authorized credential bundle stopped before cloud or host injection:
rootless metadata commands inherited /home/ama and could not traverse it. The
corrected commands explicitly use / and handle Podman's empty successful secret
list. Eight tests and the corrected read-only host preflight passed (changed=0).
No credentials were created, injected or rotated. The same unmutated operation
remains active; corrected-bundle approval is required before execution.
Private review: `/home/aaron/code/.local-evidence/nautobot-credential-preflight-20260921/REVIEW.md`.

### Credential provisioning completed

The corrected authorized credential bundle completed successfully on September 21.
Doppler config and four credentials were created and privately verified. Six
protected environments, non-secret settings and the Redis Podman secret were
injected and verified; independent metadata checks passed. No containers started,
no administrator was created, and controller temporary-payload cleanup passed.
Result: [credential-result.json](../manifests/credential-result.json).
Private review: `/home/aaron/code/.local-evidence/nautobot-credentials-execution-20260921/REVIEW.md`.

The active operation retains its consumed definition pending terminal archival;
do not rerun its create-only bundle. Credential policy and preparation observations
above are historical inputs, not current absence claims. Next is credential
archival followed by reviewed image-store load and configuration/authentication
qualification. Runtime activation, firewall and pre-data Restic gates remain open.

### Image-load preflight correction

The approved image-load bundle stopped before loading or pulling images on
September 21. Its secret-list command interpreted literal template output as
JSON. Read-only diagnosis confirmed an empty image/container store, the expected
Podman version/store and existing Redis secret; corrected inventory checks passed.
Only non-secret operation staging/evidence was created. The reviewed correction
uses a name template plus metadata-only inspection and ignores only the default
network's synthesized creation timestamp. The failed bundle is preserved in
private execution evidence. Replacement-bundle authorization is required;
application runtime and image-store acceptance remain unperformed.
