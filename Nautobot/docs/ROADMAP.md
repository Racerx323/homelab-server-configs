# Nautobot roadmap and acceptance status

## Current next action

The isolated historical application restore is accepted and archived. Accepted
state/history are reconciled and the active operation is clean. Current work is
local capture/resume and expanded synthetic workload qualification. Complete the
recurring protection integration gaps below before preparing another live stage. No repeat restore is needed. Private review:
`nautobot-restore-workdir-20260926/REVIEW.json`.

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

Repository review on September 26 found the following gaps. This review did not
contact hosts, resolve credentials or inspect live timers; absence of a repository
implementation is not proof that a host has no manually configured schedule.

| Area | Evidence and gap | Next decision or work |
| --- | --- | --- |
| Workload representativeness | Accepted fixture: 10 Locations, 500 Devices, 2,000 Interfaces, 500 IP assignments, two imports, three exports and ten audits at concurrency two. Intended inventory scale, DNS record mix, media use and Job mix are not bound to an accepted comparison. The five unique hosts in `inventory/prod/hosts.yaml` are deployment inventory, not a complete homelab inventory. | Obtain the intended pilot inventory/export and workload envelope, then compare them with the accepted fixture. Repeat only testing needed to cover material differences. |
| Nightly backup | The shared producer and application capture have qualified one-shot execution. Review-only Nautobot nightly units now exist; no recurring schedule is deployed. The online capture explicitly requires a quiet window and directory-only media. | Define unattended execution/credential ownership, writer/media consistency, schedule/timezone, bounded duration, non-overlap and missed-run behavior before implementing a timer. A historical manual quiet-window approval is not recurring authority. |
| Weekly integrity | Full integrity passed for accepted operations. No recurring check policy or schedule was found. | Choose the plan's full-check policy or an explicitly reviewed subset policy; a subset does not replace full integrity acceptance. |
| Retention | Plan requires 7 daily, 5 weekly and 12 monthly snapshots; no consumer retention execution contract was found. | Review exact snapshot grouping/selection and dry-run candidates. Authorize deletion/retention separately; backup approval does not authorize forget/prune. |
| Monthly restore | Bounded historical restore is accepted; no monthly scheduling contract was found. Media contained directories only. | Define exact-snapshot selection, supervision and retained-payload disposal. Qualify populated-media capture/restore before relying on it for uploads. |
| Monitoring | Accepted host/runtime/workload observations and internal metrics support exist. These do not prove ongoing backup-age, integrity-failure or missed-schedule alerts. No Nautobot-owned recurring protection alert path was found in the reviewed sources. | Review existing Munin/notification ownership and select observable outcomes, alert destination and failure/recovery tests. Internal Prometheus files do not imply a deployed scraper. |
| Stable pilot and Caddy | Caddy onboarding remains stage 6; seven-day stable-pilot acceptance is not recorded. | Prepare the owner-controlled Caddy route after reviewing stage-5 readiness. Define and record the seven-day observation before authority migration or Semaphore. |

The immediate implementation candidate is the recurring application-backup
contract, reusing the qualified capture/Restic primitives after the consistency
and unattended-credential decisions above. Workload comparison now uses the
supplied scale; intended record types, interface density and operation mix remain open. This review grants no scheduled
execution, host contact, retention deletion or Caddy publication.

## Recurring protection definition

The [recurring protection contract](OPERATIONS.md#recurring-application-protection-contract)
now specifies credential bootstrap, bounded capture/writer recovery, scheduling,
integrity, retention isolation, monitoring and qualification. This is repository
preparation only; no timer, provider entity or host change was made.

The shared producer now offers separate capture and upload modes, with a
specification/hash-verified handoff, while preserving default one-shot behavior.
It still labels snapshots with a unique operation tag and unique staging path.
`preservation-node.py` reuses a directory-only media adapter. A recurring timer
cannot safely be added without separating verified capture/writer resume from
network work, providing a stable retention identity, and qualifying media handling.
The existing accepted one-shot behavior must remain covered by regression tests.

| Decision | Current position |
| --- | --- |
| Nightly consistency | Brief nightly writer pause approved for local database/media capture; resume before upload/check. |
| Window and timezone | 03:00–04:00 America/Chicago approved; candidate 03:20 trigger, 450-second capture deadline and 240-second recovery budget. Target duration qualification pending; no catch-up outage outside the window. |
| Unattended credentials | Candidate: minimal read-only Doppler service-token configuration referencing existing canonical secrets, with protected local bootstrap delivery. Candidate lifetime is 90 days with rotation 14 days beforehand; UID 999 executes. Provider entity creation and scope/expiry readback remain pending. |
| Weekly integrity | Full data check is the initial candidate; no subset waiver proposed. |
| Retention | Plan's 7 daily/5 weekly/12 monthly policy; exact recurring dataset filter/grouping and dry-run qualification must precede deletion approval. Historical recovery snapshots remain excluded. |
| Monitoring | User-confirmed persistent endpoint: `http://10.1.3.83:8000/notify/apprise`, saved configuration `apprise`. Transport/authentication and failure/recovery delivery remain unqualified. No test message or new scraper authorized. |
| Workload comparison | One site, 200 devices, 2,000 IPs, 2,000 DNS records and ten Jobs submitted together supplied. Keep worker concurrency two. DNS record types, interface density, Job mix and media use remain to be specified. |

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
retained; disposal failure latches manual intervention. Target disposal acceptance
remains open.

Next: assemble the prerequisite installation and credential-provisioning operation
for separate approval, binding the verified package transaction and the new
disposal helper. Read-only dependency/timer evidence is in private
`nautobot-prerequisite-dependencies-20260928/`; no target mutation occurred.
Target namespace access and disk staging remain unqualified live.
 Do not change production volume permissions to
make the current adapter pass. Private baseline and read-only follow-ups:
`nautobot-recurring-baseline-20260928/REVIEW.json`. No service, package, credential,
backup or notification changes were made. Populated
media, intended DNS type/Job mix and interface density remain open. The operation
stream remains clean; no timer, retention deletion or provider mutation is authorized.

### Intended workload comparison

| Dimension | Accepted synthetic test | Intended pilot | Interpretation |
| --- | --- | --- | --- |
| Sites/Locations | 10 Locations | 1 site | Larger object count alone does not establish the intended location relationships. |
| Devices | 500 | 200 | Fixture count exceeds target; model mix still needs comparison. |
| IP assignments | 500 | 2,000 IPs | Fourfold count gap; assignment distribution and address families need definition. |
| Interfaces | 2,000 total, four per device | Unspecified | Do not infer interface count from IP count. |
| DNS | No DNS workload in the accepted live test | 2,000 DNS records | Expanded local profile uses 2,000 disabled A records; intended type mix remains open. |
| Jobs | Ten audits total, concurrency two | Ten submitted together, queueing permitted | Retain two worker slots; qualify burst queue latency, progress and completion rather than increasing concurrency. |
| Media | Directory-only capture/restore | Unspecified | Populated-media recovery remains unqualified. |

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
