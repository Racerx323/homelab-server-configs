# Nautobot roadmap and acceptance status

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
| 4 — Dual-stack identity | Permanent ULA and literal dual-stack identity passed. Authorized DNS correction now passes all 24 node/VIP checks and dual-stack FQDN SSH. Stage-4 technical acceptance review passed; terminal records and archival remain pending. |
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
Next prepare terminal acceptance/evidence and schema-compatible identity records,
then obtain Git publication authorization for archival. The accepted-state
manifest still records stage 3 only;
no further ULA addition is indicated. Restic, runtime and Caddy remain separately
gated. Git commit/push and backup cleanup were not performed.

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

Future Webmin HTTPS access is intended through Caddy under its separate onboarding
lifecycle; direct Webmin certificate replacement is not the selected follow-up.
The SMART upstream issue remains awaiting maintainer response per the user. No
background issue-monitoring task or upstream publication is created by this record.
