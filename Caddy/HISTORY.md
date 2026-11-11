# Caddy deployment history

The current branch contains accepted production state and neutral reusable
tools. Annotated Git tags preserve consumed operation definitions, hashes, and
terminal provenance. Inspect a tag when you need the full record.

## Action 35 terminal index

| Action | Terminal result | Annotated tag |
| --- | --- | --- |
| 35 | failed-consumed | `caddy-action35-terminal-2026-08-16` |
| 35a | failed-consumed | `caddy-action35a-terminal-2026-08-16` |
| 35b | failed-consumed | `caddy-action35b-terminal-2026-08-16` |
| 35c | failed-consumed | `caddy-action35c-terminal-2026-08-16` |
| 35d | failed-consumed | `caddy-action35d-terminal-2026-08-16` |
| 35e | failed-consumed | `caddy-action35e-terminal-2026-08-16` |
| 35f | failed-consumed | `caddy-action35f-terminal-2026-08-17` |
| 35g | failed-consumed | `caddy-action35g-terminal-2026-08-17` |
| 35h | failed-consumed | `caddy-action35h-terminal-2026-08-17` |
| 35i | failed-consumed | `caddy-action35i-terminal-2026-08-17` |
| 35j | failed-consumed | `caddy-action35j-terminal-2026-08-17` |
| 35k | failed-consumed | `caddy-action35k-terminal-2026-08-17` |
| 35l | failed-consumed | `caddy-action35l-terminal-2026-08-17` |
| 35m | failed-consumed | `caddy-action35m-terminal-2026-08-17` |
| 35n | failed-consumed | `caddy-action35n-terminal-2026-08-17` |
| 35o | failed-consumed | `caddy-action35o-terminal-2026-08-17` |
| 35p | failed-consumed | `caddy-action35p-terminal-2026-08-17` |
| 35q | failed-consumed | `caddy-action35q-terminal-2026-08-17` |
| 35r | failed-consumed | `caddy-action35r-terminal-2026-08-17` |
| 35s | failed-consumed | `caddy-action35s-terminal-2026-08-17` |
| 35t | failed-consumed | `caddy-action35t-terminal-2026-08-17` |
| 35u | accepted read-only capture | `caddy-action35u-terminal-2026-08-17` |
| 35v | failed-consumed | `caddy-action35v-terminal-2026-08-17` |
| 35w | failed-consumed | `caddy-action35w-terminal-2026-08-18` |
| 35x | failed-consumed | `caddy-action35x-terminal-2026-08-18` |
| 35y | failed-consumed | `caddy-action35y-terminal-2026-08-18` |
| 35z | failed-consumed | `caddy-action35z-terminal-2026-08-18` |
| 35aa | failed-consumed | `caddy-action35aa-terminal-2026-08-18` |
| 35ab | failed-consumed | `caddy-action35ab-terminal-2026-08-18` |
| 35ac | failed-consumed | `caddy-action35ac-terminal-2026-08-18` |
| 35ad | failed-consumed | `caddy-action35ad-terminal-2026-08-18` |
| 35ae | failed-consumed | `caddy-action35ae-terminal-2026-08-18` |
| 35af | failed-consumed | `caddy-action35af-terminal-2026-08-18` |
| 35ag | failed-consumed | `caddy-action35ag-terminal-2026-08-18` |
| 35ah | accepted installation | `caddy-action35ah-terminal-2026-08-18` |
| 35ai | failed-consumed | `caddy-action35ai-terminal-2026-08-18` |
| 35aj | failed-consumed | `caddy-action35aj-terminal-2026-08-18` |
| 35ak | accepted timer repair | `caddy-action35ak-terminal-2026-08-18` |
| 35al | accepted notification standardization | `caddy-action35al-terminal-2026-08-23` |
| 35am | accepted attribution closure | `caddy-action35am-terminal-2026-08-23` |
| 35an | failed-consumed | `caddy-action35an-terminal-2026-08-23` |
| 35ao | failed-consumed | `caddy-action35ao-terminal-2026-08-23` |
| 35ap | manual-intervention, recovered | `caddy-action35ap-terminal-2026-08-24` |
| 35aq | failed-consumed | `caddy-action35aq-terminal-2026-08-24` |
| 35ar | failed-consumed | `caddy-action35ar-terminal-2026-08-24` |
| 35as | accepted controlled exercise and closure | `caddy-action35as-terminal-2026-08-24` |

## Accepted production boundary

Action 35ah installed the accepted coupled serving-health architecture and the
same immutable Caddy release on both nodes. Actions 35ak, 35al, and 35am closed
the Pi-hole web timer and notification contracts. Action 35as accepted the
controlled failure exercise and closed Action 35.

The Action 35 baseline payload manifest SHA-256 was
`2253a491e048c9d670865e3d39efa3c9e9acd92a31ec33219f97ba91428b0133`.
Current inventories and `current-live-state.tsv` describe the production
boundary. Historical quarantine trees, operation specifications, regressions,
and evidence paths remain available through their annotated tags rather than
the working tree.

## Pre-cleanup archive

The annotated pre-cleanup tag recorded by the earlier repository consolidation
preserves the full historical tree that preceded the clean-as-you-go lifecycle.
The governing rule in `AGENTS.md` requires a terminal tag before current-branch
cleanup.

## Node B authentication acceptance, 2026-09-14

- Operation: `20260914-pihole-authentication-node-b`
- Status: archived
- Result: failed-consumed; baseline restoration accepted on both nodes
- Tag: `caddy-authentication-node-b-terminal-2026-09-14`
- Archive: annotated tag pushed for terminal commit `cc2b0db`
- Authorized outer SHA-256: `8a62176be84b6693eef5aec0705ea96a2334b6ffac96e34039b6c74c1b6c25da`

Normal Node A publication and Node B reconciliation completed. The real IPv4
login rejected an incorrect password with HTTP 200 and accepted the configured
password with HTTP 302. The concurrent IPv6 connection failed before HTTP: the
workstation has no IPv6 route to Node B (errno 101, Network is unreachable).
Full login acceptance therefore failed. The runner restored Node B's baseline
release and monitor, withdrew Node A's publication, and proved both nodes'
restoration. Across 320 node-local probes, both families remained healthy;
Node A remained Master with four VIPs and Node B Backup with zero VIPs.
The early failure shortened observation below the full acceptance minimum.

The terminal tag retains the exact executed specification and sanitized
`manifests/serving-health-terminal-result.yaml`, including source and external
evidence hashes. The original workstation `/tmp` evidence and source snapshot
were no longer available at archival, likely following the operator-reported WSL
Ubuntu stop/start. The tag does not contain raw evidence. Consumed data is removed
from the current branch while one replacement operation is registered.
At that operation’s conclusion no candidate was accepted; that consumed bundle must not be rerun.
A later operation must establish workstation dual-stack reachability before mutation.

## Node B authentication connectivity operation

- Operation: `20260914-pihole-authentication-connectivity`
- Result: accepted; outer status 0
- Authorized outer SHA-256: `855f76189cc30b65de1c590b3a8609a3ad2fe430e5b29ef0d381f064fb16f850`
- Node B retained release: `20260914T210529Z-61747c1a-5eaa-42a9-9ded-70310cd4be2a`
- Node A retains its baseline serving release and candidate publication.
- IPv4/IPv6 fresh and idle wrong-password rejection, immediate successful retry,
  authenticated dashboard, and logout passed. All 1208 node-local continuity
  requests succeeded; each node recorded four healthy web checks and zero failures.
  Node A remained MASTER with four VIPs; Node B remained BACKUP with zero.
- Evidence is preserved outside `/tmp`; the sanitized hashes and exact executed
  identities are in `manifests/serving-health-terminal-result.yaml` at the tag below.
- Tag: `caddy-authentication-connectivity-terminal-2026-09-14` (pushed; commit `f32c4b4`).
- Status: archived

The pushed tag retains the exact executed operation and sanitized terminal
manifest. Consumed data is removed from the current branch while Node A activation
and shared-VIP login acceptance are prepared as one replacement operation.
Live execution requires its own exact-bundle authorization.

## Node A authentication activation, 2026-09-14

- Operation: `20260914-pihole-authentication-primary`
- Status: archived
- Archive: annotated tag pushed for terminal commit `f3cafcb`
- Result: failed-consumed; preflight stopped before serving mutation
- Tag: `caddy-authentication-primary-terminal-2026-09-14`
- Authorized outer SHA-256: `0a8f1e4295f1fa38bc4f9316ec6328afba89acd0eaedfdd9d0c73b008ea1a9f8`

Node A and shared-hostname IPv4/IPv6 HTTPS checks passed with verified TLS,
HTTP 200, and the login form. Node B preflight passed. Node A service, residue,
and ownership checks passed, but its release identity predicate rejected the
baseline’s eleven-file inventory because it expected the candidate’s eight files.
Read-only inspection verified the pinned baseline manifest and all eleven file
digests; the three additional files are `tls/leaf.pem`, `tls/intermediates.pem`,
and `tls/certificate-manifest.json`. The retained publication passed the complete
eight-file identity check. The qualification fixture omitted the three baseline
files, explaining why the local scenarios did not expose the predicate defect.

The runner exited 1. It did not install the monitor, activate a release, transition
services, retrieve a password, or attempt login. Both temporary upload dispositions
returned 0. Node A remains on baseline and Node B retains its accepted fix. No new
live acceptance is claimed. The evidence manifest records exact executed hashes;
qualification, source snapshot, and live evidence are protected under
`/home/aaron/code/.caddy-evidence/authentication-primary-0a8f1e4295f1`.

After archive, correct the separately pinned baseline/candidate inventory checks,
model the full baseline in the fixture, and qualify a replacement including
malformed identity rejection and restoration. Node A and shared login acceptance
require that replacement’s exact authorization.

## Node A authentication inventory correction and acceptance, 2026-09-14

- Operation: `20260914-pihole-authentication-inventory`
- Status: archived
- Archive: annotated tag pushed for terminal commit `6a3e9b3`
- Result: accepted; both nodes retain the fixed release and monitor
- Tag: `caddy-authentication-inventory-terminal-2026-09-14`
- Authorized outer SHA-256: `c787b411b066eeb9647943cecf0ae2eb4b8cb61edc366630ac382c0b1d705f72`
- Authorized source commit: `c091a48`

The corrected baseline predicate passed live preflight. Node A installed the
updated monitor and activated the retained publication through its installed
finalizer/reconciler. Real Node A and shared-URL login acceptance passed over
IPv4 and IPv6 with fresh and idle sessions: wrong password rejected, immediate
correct password accepted, dashboard accessible, logout successful, and dashboard
access denied after logout. No login POST was replayed.

All 2,224 availability probes passed (Node A 1,128; Node B 1,096). Cursor-bounded
web-health checks recorded seven healthy results on Node A and eight on Node B,
with zero failures. Node A remained MASTER with four VIPs; Node B remained BACKUP
with zero. All execution phases returned 0; rollback was not needed. Node B's
accepted release and monitor were unchanged.

Both nodes now serve revision `20260914T210529Z-61747c1a-5eaa-42a9-9ded-70310cd4be2a`,
payload manifest `6a1385491cbc36d4fcb07a794553316d0f4bc8193465e45c5fa42b350ea35f88`.
Node A retains its existing publication. Accepted identities and production sources
are updated. Exact executed entrypoints and the operation specification remain
for terminal archival; the original 34-file graph is recorded in the evidence
manifest and preserved by source commit `c091a48` and its workstation snapshot.

Protected qualification and live evidence:
`/home/aaron/code/.caddy-evidence/authentication-primary-c787b411b066`.
Archive cleanup removed consumed inputs and authentication migration tools/tests.
Current tests cover accepted production behavior only. The stream is clean; no
deployment operation is registered.

## Certificate inventory repair preflight, 2026-09-15

- Operation: `20260915-certificates`
- Status: archived
- Archive: annotated tag pushed for terminal commit `0613b89`
- Result: failed-consumed; workstation preflight stopped before any upload or mutation
- Tag: `caddy-certificate-preflight-terminal-2026-09-15`
- Authorized outer SHA-256:
  `9fa87ce665be57789686e18ae4149cfd2ee719ce2307be2768163dc8f79d1319` <!-- gitleaks:allow public deployment SHA-256 -->

Node A IPv4 HTTPS `/healthz` returned HTTP 204 with curl status 0. The
runner incorrectly required 200, although accepted production configuration
explicitly responds 204. The node transaction and qualification substitute
repeat this incorrect expectation. All 16 local scenarios passed against that
inaccurate substitute; they did not establish compatibility with this endpoint.

Execution returned 1 before SSH upload, publication, installation, reload, or
certificate-service invocation. No rollback was needed. The certificate inventory
defect remains unresolved. Exact executed sources are retained unchanged for
archive, with sanitized result hashes in `manifests/serving-health-terminal-result.yaml`.
Protected source, qualification and live evidence are under
`/home/aaron/code/.caddy-evidence/certificate-repair-9fa87ce665be`.

After archival, correct the expected HTTP status in both entrypoints and derive
the fixture response from the accepted production endpoint contract, then
qualify a replacement bundle before requesting its exact live authorization.

Archive cleanup registers one replacement operation with corrected HTTP 204
serving checks. Its live execution requires its own exact bundle authorization.

## Certificate inventory restoration, 2026-09-15

- Operation: `20260915-certificate-health-contract`
- Status: archived
- Archive: annotated tag pushed for terminal commit `43d61b4`
- Result: accepted; standby Node B before primary Node A
- Tag: `caddy-certificate-repair-terminal-2026-09-15`
- Authorized outer SHA-256:
  `b8b7ef083dfbddfb8519705b7a40d4f0765043f11a1391575ad0ee168c6d025f` <!-- gitleaks:allow public deployment SHA-256 -->
- Authorized source commit: `1b7d92e`

Both nodes now select `20260915T145938Z-ac83de9a-42dd-4c8f-8d87-582ce52c7c85`,
payload manifest `8bf60cce81615c254262611ad7dde80cf5719e0b30f7679aade2f2556a11d22d`.
The release restores leaf.pem, intermediates.pem and certificate-manifest.json
from the verified prior release. Current configuration, fullchain and private
key bytes were preserved. Both publishers now enforce complete TLS inventory.

The actual certificate service passed on both nodes with Result=success and
ExecMainStatus=0. IPv4 and IPv6 HTTPS /healthz returned 204 on both nodes.
Node A remained master with all four VIPs; Node B remained backup with zero.
Cursor-bounded journals recorded no ownership transition. Every outer phase
and temporary payload disposition returned 0. Rollback was not needed.

Protected source, qualification and live evidence: `/home/aaron/code/.caddy-evidence/certificate-repair-b8b7ef083dfb`.
The exact executed operation remains unchanged for archival; accepted identities
and current release records reflect the successful repair.

Archive cleanup removed the terminal result and consumed recipe values, reset
the operation to inactive, and returned the deployment stream to clean. Neutral
repair tools and qualification tests remain; there is no deployable operation.

## Uptime Kuma application onboarding — November 11, 2026

Status: archived; result: failed-consumed.
Tag: `caddy-uptime-kuma-onboarding-terminal-2026-11-11` (published; commit `8999dde79a4bc3ad202876ee98a7a4bbe89221ce`).
Authorized outer SHA-256: `8e9e63a4a6c03a7d5e3d1fd5b50e4c60fa7a52db2b65d287798c8c671e47d818`.

One approved attempt exited 1 at standby certificate preflight. Workstation
trusted node health checks passed over both families. Temporary payload staging
completed, then both disposition commands passed after rejection. Publication,
activation, private login and DNS were not reached. The exact failed file check
was not retained; cause remains unconfirmed. No replay is authorized.
The exact executed specification is retained in the terminal archive; the
sealed graph and raw evidence remain in private storage.
The application WORK.md owns follow-up W-091; no project acceptance is claimed.

Retained-evidence follow-up (W-091): the consumed recipe used the repository
reconciler identity where preflight required its accepted installed identity.
The sealed owner manifests already distinguished them. An isolated execution
of the frozen hash predicate reproduces the rejection with archived accepted
bytes. The fixture had installed repository bytes and derived its expected hash
from them. Exact live failed-file identity remains unrecorded. W-092/W-093 own
the correction and diagnostic coverage; the consumed operation stays unchanged.

The W-092/W-093 correction was qualified outside the current tree before
terminal archival. Its patch and qualification are indexed in the application
WORK.md. The published terminal archive preserves the consumed operation;
it does not authorize another live attempt.

Archive cleanup reset the operation to inactive, cleared its consumed recipe
and terminal result, and returned the local deployment stream to clean while
retaining the published tag. The W-092/W-093 neutral correction is applied in
place: installed reconciler identity is distinct from repository source, and
failed file checks retain bounded metadata on captured stderr. Qualification
uses independently verified accepted runtime bytes. Current local validation
and remaining work are recorded in the application WORK.md. No successor or
live authority is created by this cleanup.

## Uptime Kuma application candidate — November 11, 2026

Operation `20261111-uptime-kuma-application-onboarding` is defined locally in the
existing neutral entrypoints after the archived attempt's cleanup. All 22 release
cases, six native application cases and independent authorization-readiness checks
pass against its current graph. The application WORK.md records the sealed bundle,
command and scope under W-095. This is local qualification only: no live approval,
execution or production acceptance. Changes remain uncommitted; the consumed
predecessor and its published tag are unchanged.

### Application candidate terminal result

Status: terminal-pending; result: failed-consumed.
Tag: `caddy-uptime-kuma-application-onboarding-terminal-2026-11-11` (planned; not published).

The approved operation above ran once. Standby preflight passed; primary preflight
exited 1 after the incoming namespace checks and before the certificate-service
capture. No failed-file metadata was emitted, so the exact remaining assertion
is unconfirmed. Both node readbacks and staging dispositions passed. Publication,
activation, private login and DNS were not reached. No rollback was required.

The exact executed operation and neutral entrypoints remain unchanged. The
successor/coverage registries are cleared and the sanitized terminal manifest
records the retained evidence index hash. W-096 in the application WORK.md owns
local diagnosis and the remaining evidence gap. No retry or successor is authorized.
The previous published archive is unchanged; this new terminal archive still
requires its own publication authorization.

Owner-directed follow-up: W-096 investigation is deferred in favor of the approved
primary-first routine-onboarding redesign. The exact failure remains unconfirmed;
no old check is retroactively accepted. The governing plan and onboarding guide
record the new contract, and W-098 in the application WORK.md owns implementation
and qualification. Executed artifacts and the terminal archive boundary remain
unchanged; no successor or live authority is created by the documentation revision.
