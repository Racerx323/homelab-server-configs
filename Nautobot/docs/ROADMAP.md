# Nautobot roadmap and acceptance status

## Current next action

Recurring prerequisite installation is accepted and archived. Credential-only
provisioning is now accepted: the three canonical references, one config-scoped
read-only token and protected service-owned delivery passed independent readback.
Credential provisioning and capture-only qualification are archived.
The three failed November 3 capture trials are archived. The approved 13:00–14:00
CST successor passed normal capture/resume and independent acceptance. Capture took
13.1 seconds; preparation through verified resume took 281.0 seconds. The health
wait took 159.3 seconds within the new 210-second limit. Every pause, capture, resume,
health and guard-verification task returned zero. Six payload hashes and native
dump parsing passed; writers and HTTP are healthy, database/Redis invocations and
boot unchanged, transient credentials removed, guard inactive and runtime links
removed. Both older payloads and all preserved trees/latches are unchanged.

Capture-only qualification and its archive remain accepted. The separately
approved upload/integrity run on November 3 at 14:14 CST is now accepted: exactly
one snapshot was created and full `restic check --read-data` passed. The producer
finished in 15.0 seconds within its original 300-second limit. Independent readback
confirmed all six hashes, unchanged original capture files and older retained
state, healthy unchanged services, removed credentials, inactive transient unit
and unchanged timer identities. Its payload was retained until the separately
accepted disposal stage below.

The upload/integrity terminal archive is published and byte-verified. The consumed
operation is cleared. See
`manifests/recurring-upload-review.json`, accepted live state and HISTORY.

Notification delivery is accepted: the November 3, 15:01 CST trial submitted both
simulated messages with HTTP 200 on their first attempts. Aaron confirmed both on
email, Discord and Pushover within ten minutes. All 57 independent checks passed;
application services, retained state and timer identities are unchanged, and the
transient notification unit is inactive. Duplicate counts were not separately
quantified; this does not establish exactly-once delivery.

The notification terminal archive is published and byte-verified. The consumed
operation was cleared before the disposal stage. See
`manifests/recurring-notification-review.json`, accepted live state and HISTORY.

Local disposal and remote retention analysis are accepted. The November 3 trial
removed exactly six approved successful-capture files (5,263,489 bytes), retaining
their receipts and empty directory. All 59 independent checks passed. Older
payloads, preserved evidence, application services and timer identities are unchanged;
transient credentials are removed and the operation unit is inactive. The remote
7/5/12 dry run kept the one eligible recurring snapshot, excluded all four historical
snapshots and selected none for removal. All five remote snapshots remain unchanged.
See `manifests/recurring-disposal-review.json` and accepted live state.

The disposal terminal archive is published and independently byte-verified. The
consumed operation is cleared; the deployment stream is clean.

The first recovery/timer setup failure is archived. Its exact runtime tree is now
preserved under `recovery-qualification-retained-bb2e3c00d26e` with every bound
hash, owner and mode unchanged.

The November 3 replacement trial is accepted. Independent node-local recovery
passed both faults: 158.5 seconds after primary-cgroup termination and 159.0 seconds
after guard expiry, within the shared 240-second budget. All three writer resumes,
native health and credential cleanup passed in each case. The marker timer fired
and four calendar evaluations passed. All 85 independent acceptance checks passed;
old staging and evidence, PostgreSQL/Redis invocations, boot and prior timer
identities are unchanged. Qualification links are removed and no schedule is enabled.
The first readback caught a transient Podman healthcheck job; it completed
successfully, and the unchanged checks passed on settled readback. Both are retained.

The terminal archive and qualified retained-state implementation are published.
The annotated tag, archive bytes and all 39 member hashes were independently
verified; the consumed operation is cleared and the deployment stream is clean.
See `manifests/recurring-recovery-review.json` and accepted live state.

The approved recurring schedule was installed on November 4. Ansible completed
without failure or rescue. Independent readback verified runtime hashes and
permissions, all nine unit links and loaded identities, exactly three enabled timers,
unchanged application/boot identities and 27 preservation comparisons. The approved
bundle is consumed; do not replay it. See `manifests/recurring-schedule-review.json`.

The November 5–9 native calendar cycles are accepted as of November 9. Each began
at 03:20 CST and finished around 03:25 with capture, writer readiness, upload, full
integrity, transient credential cleanup and successful-only payload disposal.
Independent readback matched all five snapshots by repository, host, tag and path;
all five older snapshots remain. Nineteen retained-state comparisons passed.
Approved runtime sources, application artifacts, boot/data-service identities,
unit links and protected directories remain unchanged. Generated Python caches
are recorded separately under the reader's narrow protected-file exception.

Aaron confirmed the November 4 missed alert and November 5 recovery on email,
Discord and Pushover, with no duplicates. November 5–8 timing comes from original
receipts and the installation-cursor manager journal; later cycles superseded their
supervisor state. The complete current-state reader passed for November 9.
See accepted live state and `manifests/recurring-schedule-review.json` for identities
and evidence hashes. This establishes scheduled protection, not seven-day pilot
or monthly restore acceptance.

The accepted schedule operation and reader correction are published in the
annotated tag `nautobot-recurring-schedule-v1-accepted`. Independent remote fetch
verified the archive bytes and all 51 member hashes before clearing the consumed
operation. The deployment stream is clean; the running schedule is unchanged.

The November 9 logical-reference capture-only trial is accepted. Capture took
23.4 seconds; preparation through verified resume took 293.3 seconds within the
450-second limit. All 155 independent checks passed, including six payload hashes,
native dump parsing, the 245-table logical reference, writer health, helper and
credential cleanup, and all 16 prior retained/staging trees. The accepted nightly
schedule remains unchanged; the new payload and logical receipts are retained.

The annotated logical-reference trial archive is published and independently
byte-verified, including all 38 members. The consumed operation is cleared; the
deployment stream is clean. Next: prepare separate durable-schedule logical-reference
promotion. See `manifests/logical-capture-review.json`.
Aaron owns existing host/user-manager monitoring and credential rotation.

Remote deletion/prune, older-payload disposal, monthly isolated restore, populated-media
recovery, seven-day pilot acceptance remain separate scopes.

The exact accepted preservation snapshot was retrieved and imported into isolated
ARM64 containers. Complete pre-start logical equality, the 481-entry migration
ledger, native configuration/migration checks, Django health, repeatable exports
and directory-only media checks passed. Nine fetched receipts matched independent
node hashes. Controller and Ansible exited zero.

Independent readback verified unchanged identities for all five production
services, HTTP 200 for both host headers, absent owned containers/volume and
credentials, inactive guard/monitor, and passing delayed storage observation.
Protected retrieved payload, extracted files and staging remain retained for
explicit later disposal. The earlier working-directory failure is published in
`nautobot-application-restore-v1-failed`; its nonsecret staging is also retained.

This qualifies the bounded historical restore with directory-only media. It does
not qualify populated-media recovery, restored uWSGI/browser serving, general
resource headroom or current-data disaster recovery. Full stage 5 remains open.
The [master plan](NAUTOBOT_DEPLOYMENT_PLAN.md#backups-and-recovery) owns criteria;
[OPERATIONS](OPERATIONS.md#isolated-full-application-restore-preparation) owns the
reusable procedure. The published archive and accepted state retain this bounded decision.

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
| Application restore | Bounded historical restore passed; archived and reconciled; populated media remains unqualified | [Master plan](NAUTOBOT_DEPLOYMENT_PLAN.md#backups-and-recovery) |
| Stage 6 Caddy onboarding | Open; owner lifecycle applies | [Master plan](NAUTOBOT_DEPLOYMENT_PLAN.md#caddy-application-onboarding) |
| Stable pilot, authority migration, Semaphore | Open; seven-day criterion and separate domain acceptance remain | [Master plan](NAUTOBOT_DEPLOYMENT_PLAN.md#validation-and-acceptance) |

## Stage-5 gap review

The September 26 repository review established this gap list. Rows below now include
the separately accepted November 3 trials, November 4 installation and November 9
scheduled-cycle acceptance. Earlier stage observations retain their original scope.

| Area | Evidence and gap | Next decision or work |
| --- | --- | --- |
| Workload representativeness | Accepted fixture: 10 Locations, 500 Devices, 2,000 Interfaces, 500 IP assignments, two imports, three exports and ten audits at concurrency two. The synthetic pilot profile below is agreed and its mixed DNS/interface fixture passed native local qualification. Real Celery qualification also passed; live comparison and resource acceptance remain pending. The five unique hosts in `inventory/prod/hosts.yaml` are deployment inventory, not a complete homelab inventory. | Bind any later live fixture transition and resource observation. Compare real inventory/export before claiming representativeness. |
| Nightly backup | Separate prerequisite trials and local repeated-cycle qualification passed. The approved durable schedule was installed November 4; five November 5–9 cycles passed independent acceptance. | Preserve the archived acceptance and keep directory-only media, the writer window and approved schedule unchanged. |
| Weekly integrity | Aaron selected the existing full check after every nightly upload on November 4. Full integrity passed in the separate upload trial and all five accepted nightly cycles. | Keep this path intact; successful nightly checks cover the weekly cadence. A failed or missed backup must not be counted as an integrity check. Independent weekly scheduling is outside this first scope. |
| Retention | The accepted November 3 remote dry run used 7 daily, 5 weekly and 12 monthly, grouped by stable host/tag: one recurring snapshot kept, four historical snapshots excluded, no removal candidates and unchanged inventory. | Refresh exact selection before any future deletion request. Snapshot deletion and prune require their own authorization. |
| Monthly restore | Bounded historical restore is accepted. The monthly contract is defined in OPERATIONS. Local source review found that recurring captures lack its independent full logical reference; no monthly operation or timer is installed. | After the active operation is archived, bind an accepted recurring snapshot, contemporaneous logical reference, isolation, supervision and capacity/deadlines. Retained-payload disposal remains separate. |
| Monitoring | Separate failure/recovery delivery is accepted; finite retry exhaustion is locally qualified. The integrated missed/recovery messages reached all three destinations without duplicates. Aaron owns existing host/user-manager monitoring. | Preserve the accepted delivery evidence. Keep existing monitoring unchanged; local notification cannot report while its host/user manager is offline. |
| Stable pilot and Caddy | Caddy onboarding remains stage 6; seven-day stable-pilot acceptance is not recorded. | Prepare the owner-controlled Caddy route after reviewing stage-5 readiness. Define and record the seven-day observation before authority migration or Semaphore. |

The immediate implementation candidate is the recurring application-backup
contract, reusing the qualified capture/Restic primitives after the consistency
and unattended-credential decisions above. The schedule is now installed under its
separate approval. The agreed synthetic workload below defines the remaining
comparison; this documentation work grants no additional live execution, retention
deletion or Caddy publication.

## Recurring protection definition

The [recurring protection contract](OPERATIONS.md#recurring-application-protection-contract)
now specifies credential bootstrap, bounded capture/writer recovery, scheduling,
integrity, retention isolation, monitoring and qualification. Initial preparation
was repository-only; separately approved stages have since provisioned credentials
and installed the schedule. See the current next action above for acceptance limits.

The shared producer now offers separate capture and upload modes, with a
specification/hash-verified handoff, while preserving default one-shot behavior.
The recurring path uses a stable recurring tag and a unique staging path.
`preservation-node.py` retains its directory-only media adapter. The installed
recurring path separates verified capture/writer resume from network work and
uses qualified directory-only handling; populated media remains outside acceptance.
The existing accepted one-shot behavior must remain covered by regression tests.

| Decision | Current position |
| --- | --- |
| Nightly consistency | Brief nightly writer pause approved for local database/media capture; resume before upload/check. |
| Window and timezone | 03:00–04:00 America/Chicago; installed 03:20 trigger with latest start 03:22, 450-second capture deadline and 240-second recovery budget. Normal capture and independent termination/deadline recovery are accepted. Cutoff/repeated cycles passed local qualification; five native recurring cycles are accepted. No persistent catch-up. |
| Unattended credentials | Accepted and archived: three canonical references, config-scoped read-only token and protected delivery. Aaron owns rotation by January 13, 2027; expiry January 27. UID 999 resolution passed. |
| Weekly integrity | Keep the qualified full check after every nightly upload, as selected November 4. No subset waiver or separate weekly job is proposed. |
| Retention | Plan's 7 daily/5 weekly/12 monthly policy; one exact dry run is accepted. Refresh selection before separate deletion approval. Historical recovery snapshots remain excluded; no delete/prune timer is proposed. |
| Monitoring | Persistent endpoint `http://10.1.3.83:8000/notify/apprise`, saved configuration `apprise`; separate failure/recovery delivery is accepted. Finite retry exhaustion passed local qualification; the integrated missed/recovery path reached all three destinations without duplicates. Aaron owns existing external monitoring; preparation authorizes no additional messages or monitoring changes. |
| Workload comparison | Agreed synthetic profile: one site, 200 devices, 800 unevenly distributed interfaces, 2,000 IPs and 2,000 mixed DNS records; ten consistency audits queued at concurrency two; no media uploads. Qualify the mixed fixture before claiming coverage. |

Local implementation now includes the Ansible capture/resume/upload task include,
multiple IPs per Interface, native disabled A records in a fixture-owned `.invalid`
zone, and a ten-Job single-batch mode using two worker slots. The default historical
fixture and paired submission behavior remain available. The original default
fixture remains byte-identical. Local qualification passed the following checks:

- Seven real Ansible/Restic cases: success, capture failure, failed writer resume,
  health failure, changed payload, upload failure and integrity failure. Every
  resume command was attempted; failed capture/recovery blocked upload; integrity
  failure retained its snapshot; temporary credentials were removed.
- Native Nautobot 3.2.3/DNS Models 2.3.0/PostgreSQL checks at one Location,
  200 Devices, 800 Interfaces, 2,000 IPs and 2,000 disabled A records: rollback,
  ownership refusal, repeat import without writes, deterministic export and audits.
- Fifteen real Celery Jobs and backup/full-integrity overlap. The ten-audit burst
  used two worker slots and completed within 128.1 seconds; the last audit started
  after 102.6 seconds. The initial import took 458.5 seconds. These are workstation
  measurements, not ARM64 resource/headroom acceptance.

Private evidence is under `nautobot-recurring-local-20260928/`. Active cancellation,
retained-fixture/registration checks and owned container/network cleanup passed.
No live state has changed; production watchdog, host staging and ARM64 sampling
remain unqualified by these local tests.

Node-local supervision now has review-only nightly/freshness units, an exclusive
run lock and an independent recovery timer. Ten supervisor regressions and four
real disposable user-systemd cases passed: normal completion, killed primary,
capture deadline and the real recurring Ansible playbook with harmless adapters. The failure cases quiesced the backup service, resumed the test
writers and removed transient credentials. These remain workstation adapter tests.

Rootless command bindings, isolated service-token resolution and standardized
interim direct Apprise delivery now have local implementations. The user deferred
the shared durable client; the current Caddy queue does not accept Nautobot.
Ten binding regressions additionally cover credentials, rootless ordering, external
database clients, standardized local HTTP alerts and independent notification
units. The candidate remains inactive and provider entities have not been created.

The September 28 read-only target baseline found all five application services
running, HTTP 200, passing backend guard and enabled linger. All 15 artifacts in
the accepted startup/boot-readiness registry matched. Podman is 5.4.2, Restic 0.18.0,
systemd 257 and Python 3.13.5; application versions remain Nautobot 3.2.3 and DNS
Models 2.3.0. This is an observation, not recurring deployment acceptance.

Deployment blockers and remaining review:

- Ansible and Doppler were absent from the service account PATH and the checked
  `/usr/bin` and `/usr/local/bin` installation paths.
- Host UID 999 cannot traverse the media volume parent: it is mode 0700 and owned
  by UID/GID 166534. The candidate adapter's direct host-path traversal therefore
  fails. Root-only inspection found three directory entries and no files; this
  does not qualify the rootless capture path.
- `/tmp` is tmpfs with about 4 GiB free, while `/var/lib/nautobot` is on ext4 with
  about 870 GiB free. Select and bound staging explicitly; free disk capacity does
  not make the current tmpfs staging disk-backed.
- No recurring protection units or protection directory are installed. Credentials,
  pause/recovery deadlines and actual notification delivery remain unqualified.
- The observed Sunday `e2scrub_all` timer is near 03:10, overlapping the candidate
  backup trigger. The revised candidate moves to 03:20 and checks scrub inactivity; refresh the timer baseline before enablement.

Namespace-aware directory-only media inspection/archive now passes a local
mapped-UID-999/mode-0700 fixture: ordinary host access was denied, while Podman
unshare inspection and archive succeeded. Production volume permissions are
unchanged. The candidate uses protected ext4 staging under
`/var/lib/nautobot/protection/staging`; admission reserves the full capture budget
plus free-space headroom and refuses retained-capacity exhaustion before pause.
Prerequisite requirements are recorded in `manifests/recurring-protection.yaml`.

Candidate prerequisite artifacts are resolved: Debian `ansible-core`
2.19.11-0+deb13u1 (architecture `all`) and Doppler 3.76.6 (`arm64`), with downloaded
SHA-256 identities in the recurring manifest. The read-only target simulation resolves eight new packages with no upgrades or
removals. The cached Debian release signature and ARM64 package-index hash verify;
the selected Ansible hash matches the downloaded package. Refresh package
availability and transaction identities at deployment; no APT update or install ran.
The dedicated read-only backup config is limited to the three canonical Restic/B2
references, with a proposed 90-day token and rotation 14 days before expiry.
No provider configuration or token has been created.

The timer candidate is now 03:20 Central with a 30-minute orchestration ceiling;
it refuses preparation unless the known `e2scrub_all.service` is inactive.
This reduces the observed 03:10 conflict but is not mutual exclusion against a
later independently started scrub. Refresh timers and qualify duration before
schedule enablement. Successful staging disposal is specified only after verified
snapshot/integrity/writer health; failed payloads require explicit review.
Successful-payload disposal is implemented and passes local receipt, hash, link,
membership and exclusive-lock regressions. Failed/interrupted payloads remain
retained; disposal failure latches manual intervention. One successful-payload
disposal and remote retention dry run are now accepted; remote deletion remains unauthorized.

The September 28 next action was to assemble prerequisite installation and
credential-provisioning definitions. Installation is now accepted and archived;
credential provisioning is accepted and archived. Read-only dependency/timer evidence is in private
`nautobot-prerequisite-dependencies-20260928/`; no target mutation occurred.
Target namespace access and bounded directory-only capture capacity are accepted
for the November 3 trial. General workload/populated-media capacity remains
unqualified. Do not change production volume permissions to make the adapter pass. Private baseline and read-only follow-ups:
`nautobot-recurring-baseline-20260928/REVIEW.json`. That September inspection made no service, package, credential,
backup or notification changes. Populated
media remains unqualified. The September observations and earlier clean-stream
statements describe their historical stages. The current schedule is installed and
its cycles are accepted and archived; retention deletion remains unauthorized.

### Intended workload comparison

Aaron agreed this synthetic profile on November 4. It defines the pilot test, not
a discovered inventory or an accepted runtime result. OPERATIONS owns its
qualification and seven-day observation procedure.

| Dimension | Accepted synthetic test | Intended pilot | Interpretation |
| --- | --- | --- | --- |
| Sites/Locations | 10 Locations | 1 site | Larger object count alone does not establish the intended location relationships. |
| Devices | 500 | 200 | Fixture count exceeds target; model mix still needs comparison. |
| IP assignments | 500 | 2,000 IPs: 1,200 IPv4 and 800 IPv6 | Agreed profile distributes benchmark addresses cyclically across 800 interfaces; native local validation passed. Target resource coverage remains pending. |
| Interfaces | 2,000 total, four per device | 800: 20 devices × 24, 140 × 2, 40 × 1 | Native local qualification passed; density labels do not establish real hardware/model representativeness. |
| DNS | No DNS workload in the accepted live test | 800 A, 800 AAAA, 250 PTR, 100 CNAME, 40 TXT, 10 SRV | Mixed profile passed native Nautobot 3.2.3/DNS Models 2.3.0 validation. No target DNS workload is accepted. |
| Jobs | Ten audits total, concurrency two | Ten inventory/DNS consistency audits submitted together | Keep two slots and separate import/export phases; prove no writes, bounded queue latency and completion. |
| Media | Directory-only capture/restore | No uploads in initial pilot | Agreed exclusion; populated-media recovery remains separate. |

The `--pilot` profile now implements these counts. Native local qualification
passed transaction rollback, ownership/drift refusal, repeat import without writes,
three deterministic exports, ten concurrent audits and wrong-family DNS refusal.
The default and `--expanded` datasets and their generated model operations are
unchanged. Real Celery qualification also passed: two imports, three exports and
ten audits submitted together, with measured peak concurrency two. All audits
completed within 119.7 seconds; the last started after 97.6 seconds. Fixture rows,
including timestamps, were unchanged after repeat import, exports and audits.
The overlapping disposable backup/full-integrity check completed in 16.6 seconds.
Cancellation, exact retained-fixture reuse and all owned container/network cleanup
passed. These are workstation timings, not target headroom or duration acceptance.

The first Celery setup attempt stopped on synthetic-file permissions under a
private umask; no Jobs ran. Explicit read permissions on nonsecret container inputs
fixed the local qualifier, while its credential file remains protected. The failure
and successful rerun are both retained. Private evidence:
`nautobot-mixed-workload-20261104/qualification.json`.

The installed recurring capture still lacks an independent full logical reference.
The opt-in candidate now compares pre-dump and post-capture identities, binds the
reference to the dump/specification and retains it after verified disposal. Local
qualification on the agreed workload compared 245 tables: six-section capture took
7.0 seconds, including probes of 1.47 and 1.52 seconds. Upload/full integrity and an
isolated restore comparison passed; sequence drift and missing/changed references
were refused. A hung helper expired and was removed in 29.0 seconds. These are
workstation results, not ARM64 timing or production pause acceptance. Private
evidence: `nautobot-recurring-logical-20261104/qualification.json`.

The November 9 attended ARM64 trial passed independent acceptance: 23.4-second
capture, 293.3 seconds through verified resume, and logical probes of 5.24 and 4.79
seconds. Native task receipts and the pre-mutation-cursor journal confirm successful
writer recovery. The 450-second capture and 240-second recovery limits are unchanged;
this normal trial did not inject another recovery fault. All 16 prior trees and the
accepted nightly runtime/state/timers are preserved. No helper or credential residue
remains. Private evidence: `nautobot-logical-capture-preparation-20261109/acceptance.json`.

The capture-only operation is archived and its consumed definition is cleared.
Its payload and logical receipts remain retained; no upload, disposal or durable
update occurred. Next, prepare a separate durable update and accept a newly captured
snapshot/reference pair before monthly restore approval. Existing snapshots cannot
acquire an independent reference retrospectively.

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
The preserved application snapshot now passed bounded isolated restore with
directory-only media, archived and reconciled. Full stage 5 remains unaccepted.

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

### Recurring prerequisite installation

The October 29 installation is accepted. Independent readback verified all nine
exact package versions and manual flags, native service-account Ansible 2.19.11
and Doppler 3.76.6, and both UID 999/GID 985 mode 0700 directories on ext4 with
required free capacity. Staging is empty. All 15 accepted application artifacts,
five service InvocationIDs, mapped media, boot identity and nine system timers
remain unchanged; HTTP health is 200. APT/restart/notification policy matched the
pre-install observation. No rollback was needed.

[Accepted-live state](../manifests/accepted-live-state.yaml) records the installed
identity and pushed terminal archive. [HISTORY](../HISTORY.md#recurring-prerequisite-installation)
indexes the exact executed definition, bundle manifest and sanitized acceptance
record. Raw receipts remain private. Prerequisite installation is closed; no further
installation attempt or prerequisite approval is needed.

The subsequent credential stage is accepted separately: only the three canonical
backup references, config-scoped read-only access, expiry/rotation ownership and
protected delivery. No credential values, provider configuration or tokens were
created by this installation. Capture/resume, notification testing and schedules
remain later stages. Native package-changing rollback and actual capture capacity
remain unqualified; successful installation does not establish those outcomes.

### Recurring credential provisioning

The approved credential-only playbook completed on October 29. Independent provider
readback confirmed exactly three canonical reference expressions and one read-only
service token in `homelab-dev/prd_nautobot_backup`. Native UID 999 resolved all three
references; protected file ownership/modes and temporary-value cleanup passed.
Application artifacts, service invocations, packages, mapped media, boot identity
and system timers were preserved.

The token expires January 27, 2027 at 21:17:52 UTC. Aaron owns rotation by
January 13, 2027 at 21:17:52 UTC. Non-secret identity and acceptance hashes are in
`manifests/accepted-live-state.yaml`; the sanitized review and exact executed
definition are preserved in the published terminal tag indexed by HISTORY.
Raw receipts remain private. Credential provisioning is archived; the subsequent
capture-only acceptance is separate. Notifications and schedules remain later
approvals; credential resolution does not qualify B2/Restic access.

### Capture/resume qualification

The November 3 attended trial accepted normal capture/resume with directory-only
media. Six local sections and native dump validation passed; all writer, health
and guard-verification statuses were zero. Protected receipts retain task-level
evidence. The accepted record owns measured durations and evidence identities;
HISTORY indexes terminal archival. Earlier failed payloads/latches and the new
successful payload remain retained for separately approved disposition.

The shared producer defers repository access until upload, so this trial made no
repository-read or upload call. The four temporary runtime links were removed
after healthy completion. Production forced-termination recovery, populated-media
capture, upload/integrity, notifications, disposal and schedule enablement remain
separate qualifications. OPERATIONS owns the reusable procedure.
