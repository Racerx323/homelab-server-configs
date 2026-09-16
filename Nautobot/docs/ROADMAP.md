# Nautobot roadmap and acceptance status

## Review boundary

This September 16, 2026 local review uses retained evidence only. No live host,
observer, provider or secrets-system contact was performed. The last retained
observation says the Webmin trial is running; this review does not establish its
present state or classify either checkpoint.

The [deployment plan](NAUTOBOT_DEPLOYMENT_PLAN.md) remains the architecture
authority. The [active operation](../manifests/operation.yaml) remains host-baseline
convergence, unready for execution and not accepted. The frozen convergence
schema matches that definition. The inactive Restic contract remains unchanged.
No accepted-live identity or terminal history is created by this review.

## Numbering and project position

Earlier conversation called storage qualification “Gate 1” and host convergence
“Gate 2.” Those are local acceptance dependencies, not the deployment plan's
numbered execution stages. Use the plan's stage numbers below going forward.

| Plan stage | Position and next evidence |
| --- | --- |
| 1 — Repository plan | Governing definition exists; no architecture change needed for this review. |
| 2 — Repository implementation | Host/preflight and Restic preflight paths exist; runtime rendering/deployment candidates and initialization code exist but are inactive and not live-qualified. Definition work may continue locally. |
| 3 — Host baseline | Cleanup verified; all 59 preflight checks passed. Polling checkpoint review, baseline firewall evidence and independent terminal baseline decision remain pending. |
| 4 — Dual-stack identity | Permanent ULA present in preflight. Full forward/reverse DNS, dual-stack reachability, route preservation and exposure acceptance remain to be proved through the owning components. |
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
| Transport and filesystem | Exact quirk, USB root ancestry, driver binding, clean ext4, zero errors and boot continuity passed. | Checkpoint coverage and independent storage disposition remain pending. |
| SMART health | Reduced query health passed and 75-second delayed-error check passed. | Self-test-log data remains unreliable (#648); no self-test or blanket health exception. |
| Thermal and power | Preflight temperature/throttling checks passed; prior retained UniFi Class 4/PoE-good evidence exists. | Explicit port allocation unavailable; workload headroom not established by idle power or temperature. |
| Polling | Initial patched scheduled sequence returned health/44 C; 113.9 seconds of quiet follow-up retained. | Review actual two-hour/24-hour records, complete/failure/disable state, coverage, traces, journal and integrity. |
| Alerts | Earlier smartd corrected-recipient test B was received by the user. | Daemon activity alone does not prove delivery; this review sends no new test and does not qualify Needrestart alerts. |
| Listeners and identity | Required baseline endpoints, optional loopback stats endpoint and permanent ULA passed. | Baseline management firewall/reachability and global-IPv6 denial are required before stage-3 acceptance; DNS/PTR and application exposure follow in later stages. |
| Memory and workload | Controller available; no application workload acceptance evidence. | At least 1.5 GiB available during imports, exports, backups and Jobs; no OOM, persistent swap growth, throttling or sustained over-80 C. |
| Backup and recovery | Provider acceptance and old repository-absence result retained in inactive contract. | Fresh absence review, initialization, canary upload/full check/isolated restore, then real application recovery. |
| Terminal baseline | Preflight passed, mutation not attempted by that preflight. | Independent review, baseline firewall evidence, residue review, explicit scoped acceptance, accepted identity and authorized terminal archival. |

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

Review the Webmin checkpoints using the private `FOLLOW_UP_PROMPT.md`. Expected
completion disables temperature polling; that is not a failure or permission
to re-enable it. An incomplete/invalid/failed observation blocks progression
pending read-only investigation. A passed trial supplies one dependency, not
terminal storage or host acceptance.

Then prepare the independent stage-3 terminal review under
[HOST_BASELINE_CONVERGENCE.md](HOST_BASELINE_CONVERGENCE.md). Explicitly carry
application-dependent host criteria forward to stage 5; baseline acceptance
must not claim full workload acceptance. Do not waive any requirement to break a
dependency cycle. The governing plan now explicitly distinguishes stage-3 baseline acceptance from
stage-5 full workload acceptance; neither record substitutes for the other.
The next-stage preparation below records concrete inactive
operation drafts and the remaining readiness inputs.

## Next-stage preparation after host convergence

## Scope and activation

These are local planning drafts, not executable operations or live authorization.
They follow the evidence map above and preserve the
single active slot in `manifests/operation.yaml`. Do not replace that slot until
host-baseline terminal acceptance and authorized archival are complete. No host
contact, image pull/build, secret resolution, load test or service transition is
part of this preparation.

The immediate next operation is the existing stage-3 convergence review, not a
runtime deployment. Review Webmin checkpoints first, then assemble the terminal
baseline evidence and accepted identity under the existing convergence procedure.
Do not retry historical baseline v3. Commit/tag/push, future live collection and
mutations remain separately scoped. The running trial is untouched.

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

Prepare an explicit test matrix for host A/AAAA/PTR, SSH over IPv4/permanent ULA,
preservation of SLAAC/global IPv6/default route, and preservation of the stage-3 baseline SSH/Webmin/Munin access
restrictions. Resolve exact Caddy node source addresses from owning inventory;
do not infer an entire trusted subnet. Record allowed and denied vantage points
and expected outcomes before live probes. Missing vantage points mean incomplete
coverage, not a pass. A failed observation stops advancement; any correction
requires its owner's reviewed operation and exact configuration rollback.

## Stage 5 — runtime and workload draft

Prerequisites: accepted scoped baseline, identity/exposure prerequisites, immutable
ARM64 custom-image digest, reviewed Quadlets/Ansible deployment, external secret
references, approved recovery identity and application configuration. The existing
`desired-state.yaml` supplies base digests and service intent; it does not supply
a finished custom-image deployment digest. Verify those inputs when defining the
pilot rather than silently updating versions in this planning task.

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
