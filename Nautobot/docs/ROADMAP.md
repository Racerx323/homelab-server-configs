# Nautobot roadmap and acceptance status

## Current next action

Review and publish the locally validated test-necessity follow-up (W-031)
before preparing another workload trial. The preceding
simplification is published. Hard-coded evidence input paths are removed, retained-fixture
closure checks are model-batched, and broad local validation triggers are narrowed.
The existing small native correctness suite passed; this does not establish target
runtime or capacity. The operation remains clean and disabled.

Schema cleanup removes duplicated operation branches and retired pre-data trials.
Current stage contracts retain authorization and recovery checks; boot continuity
is bound at admission. See W-030 in the work ledger for qualification and limits.

No new permanent controller input store is required. The mistakenly created
`.local-state/nautobot` copy has been removed after verifying unchanged originals.
Bootstrap identity and image-retry records belong to completed stages. Fixture
ownership is needed only to safely replace/dispose retained test data; restore
references validate recovery and are already embedded in recurring snapshots with
accepted hashes. They are not additional runtime installation prerequisites.

For any future replacement, verify the exact original ownership receipt against
the archived hash during preparation. Do not adopt objects by name or invent a
replacement receipt. Future restore preparation selects its accepted snapshot and
reference provenance through the established recovery procedure. No host contact,
new trial, capacity fixture, timeout increase or publication occurred in this work.

The [work ledger](../manifests/workload-review.json) records the changes, existing
tests and remaining limits. Historical evidence is preserved; a private evidence
path is not a mandatory future input location. Current target health and private
input availability were not refreshed by this repository-only work.

## Accepted scope and remaining gates

[Accepted live state](../manifests/accepted-live-state.yaml) owns stage identities
and evidence hashes. [HISTORY](../HISTORY.md) indexes published terminal tags.
Earlier stage-specific `false` or remaining-gate fields describe that stage;
later accepted sections supersede them only within their stated scope.

| Gate | Recorded position | Remaining work |
| --- | --- | --- |
| Host baseline and dual-stack identity | Accepted, with recorded storage and external-IPv6 evidence limitations. | Revalidate scoped readiness at the next authorized admission; old boot IDs are historical. |
| Application runtime | Private application startup accepted September 23. Pinned Nautobot 3.2.3 / DNS Models 2.3.0 and service artifacts are recorded. | No version upgrade is implied. Public-route/browser acceptance belongs to Caddy onboarding. |
| Historical synthetic workload | September 25 default profile accepted with controller-evidence limitations. | Does not cover the agreed mixed DNS/IP profile or establish general host capacity. |
| Logout and reboot persistence | Bounded September 25 stages accepted and archived. | Do not repeat them merely because another workload trial failed. Preserve recorded limitations. |
| Application restore | September 26 historical snapshot restored with logical equality and directory-only media. | Populated media and restored uWSGI/browser serving remain outside that acceptance. |
| Recurring prerequisites and credentials | October 29 package/directory installation and separate credential stage accepted and archived. | Aaron owns credential rotation; see expiry below. No reinstallation is required. |
| Capture, upload and integrity | November 3 capture/resume and exact-snapshot upload/full check accepted. | New snapshots require their own receipts; historical success is not current provider inventory. |
| Notifications | November 3 simulated delivery accepted; November 4 missed and November 5 recovery messages confirmed on email, Discord and Pushover without duplicates. | Preserve bounded retry policy. Aaron owns existing host/user-manager monitoring; local notification cannot report while offline. |
| Disposal and retention | One successful local payload disposal and remote retention dry run accepted November 3. | No remote deletion/prune authority. Older retained payloads need separately reviewed selection. |
| Independent recovery | Two attended failure cases and marker-timer qualification accepted November 3, archived separately. | Does not waive normal cycle or workload acceptance. |
| Nightly schedule | Installed November 4; first-cycle acceptance recorded November 9. Calendar 03:20 and freshness check 04:05 America/Chicago; latest start 03:22. Nightly full integrity selected. | Preserve schedule, start cutoff, finite notification retries and recovery controls. No first-cycle wait remains. |
| Logical-reference promotion | November 10 scheduled snapshot/reference pair accepted and archived; acceptance recorded November 10 CST (November 11 UTC). | Preserve independently captured reference and provenance for each selected restore pair. |
| Monthly restore | November 24 isolated restore of the accepted November 10 pair passed and is archived. | Next monthly restore is due in December; select a new accepted pair and authorize separately. No monthly timer is installed. |
| Agreed mixed workload | November 25 trial failed in retained-fixture replacement before new-profile creation. Rollback/readback passed. | Full intended workload and backup overlap remain unaccepted. Repair the data path before another trial. |
| Caddy and seven-day pilot | Stage-6 onboarding and a defined seven-day stable-pilot acceptance interval are not recorded as accepted. | Use Caddy's owner-controlled procedure after stage-5 readiness review. Backup uptime alone does not establish the pilot. |
| Authority migration and Semaphore | Not accepted. | Exact data-domain reconciliation, explicit ownership cutover and required soak remain gates. |

Full stage 5 remains open. None of the completed backup or restore stages needs
replay to prepare the remaining work. Retained-payload cleanup is separate and is
not a prerequisite without a demonstrated capacity need.

## Latest workload outcome

The November 24 read-only comparison found all 3,518 receipt-owned objects and
controlled fields unchanged, without unexpected scoped inbound relationships.
All 200 colliding Device names belonged to that retained fixture. Names alone do
not establish ownership; the exact receipt remains required for replacement.

The November 25 trial passed admission, then its first replacement-import Job
hit the 840-second soft limit in `delete_owned` ownership checks. New-profile
creation was not reached. The worker traceback establishes the interrupted stage,
not the time spent in each substage. It does not prove the host lacks capacity.

Independent readback verified the prior 3,518 objects unchanged, owned work stopped,
registrations disabled, transient credentials/modules removed and service/artifact/
timer continuity. No exports, audit batch or backup ran. The 364 samples covered an
incomplete interval and do not accept the workload. These are retained observations,
not fresh checks from this audit.

`nautobot-mixed-workload-v1-failed` preserves the live failure and earlier
controller-only failure, both consumed claims and exact nonsecret sources.
Independent remote archive verification passed; inactive controller links were
removed while unit files and receipts were retained. See HISTORY for identities.
No replay, timeout increase, disposal or workload-scope change is authorized.

## Intended workload comparison

Aaron agreed this synthetic profile on November 4. It is a test envelope, not a
discovered production inventory. [The operator procedure](OPERATIONS.md#pilot-workload-profile-and-seven-day-observation)
owns execution and observation details.

| Dimension | Historical accepted test | Agreed pilot |
| --- | --- | --- |
| Locations / devices | 10 / 500 | One site / 200 devices; actual model/relationship representativeness remains to be checked. |
| Interfaces | 2,000 | 800: 20 devices × 24, 140 × 2, 40 × 1. |
| IP assignments | 500 | 2,000: 1,200 IPv4 and 800 IPv6. Benchmark addresses never become network configuration. |
| DNS | None | 800 A, 800 AAAA, 250 PTR, 100 CNAME, 40 TXT and 10 SRV. |
| Jobs | Ten audits, two slots | Ten inventory/DNS audits submitted together; two slots, no writes, bounded queue/completion time. Imports/exports remain separate phases. |
| Media | Directory-only | No uploads in this initial pilot. Populated-media qualification is separate. |

The `--pilot` profile passed native local model validation, rollback, ownership/drift
refusal, repeat import without writes, deterministic exports and Celery audits at
concurrency two. Existing default/expanded datasets remain historical comparison
inputs. Local workstation timings and synthetic backup/restore results do not
establish ARM64 timing or target capacity. The actual-target replacement failure
is the current blocker; further substitute capacity testing will not resolve it.

## Operational follow-ups

- **Credential rotation:** Aaron owns rotation by January 13, 2027 at 21:17:52 UTC;
  the accepted token expires January 27, 2027 at 21:17:52 UTC. Provider state was
  not refreshed in this audit. Use the protected credential procedure.
- **Recovery inputs:** use the accepted snapshot/reference contract, not a new
  workstation store. Preserve the historical ownership receipt until retained
  fixture disposition is resolved. W-017 tracks verification for that conditional
  future operation, not a general deployment gate.
- **Historical failures and payloads:** keep consumed definitions and evidence;
  cleanup requires verified ownership and separate scope. Historical controller
  interruption and credential-finalizer evidence limits remain recorded.
- **Validation cost:** W-019/W-020 record narrowed pre-commit selectors and the
  repository-test audit. W-018 retains the remaining historical schema/manual
  coupling review; no new framework or wholesale test deletion is proposed.

## Record ownership

The [master plan](NAUTOBOT_DEPLOYMENT_PLAN.md) owns architecture and acceptance;
[OPERATIONS](OPERATIONS.md) owns repeatable procedures; manifests own desired,
accepted and active state. HISTORY owns terminal outcomes. CHECKPOINT is navigation
only. The [ROADMAP](ROADMAP.md) owns unresolved audit and workload findings. Use the existing [work ledger](../manifests/workload-review.json), W-014–W-019,
for the audit findings and closure conditions.

The pre-audit roadmap at commit `7617734` retains detailed historical narratives;
current instructions do not require private preparation notes or approval files.
SMART, Webmin, host transport and Caddy remain owner-controlled components.
