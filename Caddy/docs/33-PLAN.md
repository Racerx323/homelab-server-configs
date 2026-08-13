# Action 33: Bounded Caddy HA Reliability and Outage Exercise

## Summary

Status: complete through accepted Action 33o. The original definition required
one sequential, fail-closed dual-node reliability exercise covering:

- Protocol-v2 validation and conflict behavior.
- B→A emergency replication while Node A remains online.
- Four explicit node-outage scenarios.
- Standby-first rolling-maintenance rehearsal using current binaries.
- Restoration to the exact accepted Action 32g production baseline.

Scenarios 2 and 4 used automated reboot, not power-off, because no
repository-managed out-of-band power controller exists. Every executed
successor required separate authorization of its exact outer-runner SHA-256.

## Action Structure

- Create one transaction, outer runner, action manifest, and neutral production regression.
- Read current hashes from the accepted-live registry.
- Use unique `action33-<run-id>-<scenario>` paths and exact-path cleanup.
- Preserve historical quarantine and unrelated synchronization state.
- Capture node evidence under `/tmp/caddy-action33` and workstation SSH evidence under `/tmp/caddy-ssh-evidence/action33`.
- Capture journal cursors before each scenario and bounded stdout, stderr, status, timing, ownership, release, service, and rollback evidence.
- Start continuous one-second DNS, trusted HTTPS, and shared Pi-hole UI probes during every outage or ownership transition.
- Restore and independently accept the original baseline after each scenario before continuing.

### Baseline requirements

- Node A: IPv4/IPv6 MASTER and owner of all four DNS/Caddy VIPs.
- Node B: IPv4/IPv6 BACKUP with zero shared VIPs.
- Exact Action 32g production artifacts and current release on both nodes.
- Caddy, managed lsyncd, reconciliation, timers, and Keepalived healthy.
- No finalized candidate, unsafe outbound entry, failed worker, or prior Action 33 residue.
- Record original release paths, revisions, manifests, enabled states, PIDs, restart counts, and complete outgoing/incoming/quarantine inventories.

## Protocol Reliability Cases

### Invalid A→B release

- Publish a transaction-owned candidate containing an intentionally incorrect payload hash.
- Use real lsyncd, restricted receiver, and finalizer paths.
- Require validation failure, no `.complete`, no reconciliation, no reload, no destination release, and no active-release change.
- Freeze transport and remove only the exact Action 33 fixture.

### Interrupted A→B transfer

- Expose an exact active-release replay without `.finalize-request`.
- Require it to remain incomplete and unselectable.
- Add the request marker atomically and require one successful finalization and active-replay reconciliation within 60 seconds.
- Reject promotion, reload, duplicate reconciliation, or revision change.

### Same-parent conflict

- Stop only Node B’s reconciliation path.
- Deliver and finalize two valid candidates sharing the active parent.
- Require the reconciler to fail closed with both retained, no selected winner, no destination creation, no reload, and unchanged current release.
- Capture worker and notifier evidence, remove only the four transaction-owned paths, reset the worker, and restore reconciliation.
- Retain current runtime semantics: same-parent ambiguity is not automatically quarantined.

## Emergency Replication Baseline

Before the outage matrix, prove B→A emergency replication while Node A remains reachable:

1. Relinquish Node A Keepalived ownership while leaving its Caddy, lsyncd, reconciliation, and SSH active.
2. Require Node B stable MASTER with all four VIPs.
3. Confirm ordinary Node B publication is rejected.
4. Publish one guarded `--emergency` revision from Node B and promote it locally.
5. Require online Node A to receive, finalize, reconcile, and activate the same revision.
6. Restore Node A ownership.
7. Publish a normal Node A child of the emergency revision and require Node B to accept it.
8. Restore both nodes to the original pre-Action 33 release before proceeding.

## Four Outage Scenarios

### Scenario 1: Node A controlled Caddy-HA and SSH outage

- Pre-arm a transient recovery unit that restores Node A after 45 seconds.
- Stop Node A Keepalived, Caddy, managed lsyncd, reconciliation path, synchronization-health timer, and `ssh.service`.
- Require new SSH connections to Node A’s physical address to fail and Node B to become stable MASTER.
- Confirm DNS, trusted HTTPS, and the shared UI remain available through Node B.
- Confirm ordinary Node B publication is rejected.
- Publish and promote one guarded emergency revision on Node B.
- Require the release to remain queued and Node A to receive nothing during a 12-second offline window.
- Allow the pre-armed recovery unit to restore SSH, Caddy, lsyncd, and reconciliation while Keepalived remains stopped.
- Require one B→A transfer, finalization, and activation of the emergency revision within 60 seconds.
- Restore Node A Keepalived, require preferred-owner failback, then publish a normal Node A successor to Node B.
- Remove the transient recovery unit and restore the original releases.

### Scenario 2: Node A automated reboot

- Persistently disable Node A Keepalived before reboot so it cannot preempt immediately after startup.
- Schedule reboot through a captured transient command that returns before shutdown.
- Require:
  - The physical SSH endpoint to transition from reachable to unreachable.
  - A changed boot ID after return.
  - Node B stable MASTER with all four VIPs during the outage.
  - Continuous DNS, trusted HTTPS, and shared UI service through Node B.
- While Node A is unreachable, reject ordinary Node B publication, publish and promote one guarded emergency revision, and require it queued.
- Poll Node A’s physical address for at most 300 seconds.
- After Node A returns, require boot-enabled Caddy, managed lsyncd, reconciliation, timers, and SSH to recover without manual service repair.
- Keep Keepalived disabled until Node A receives and activates exactly the queued emergency revision.
- Re-enable and start Keepalived, require preferred-owner failback, then publish the normal Node A successor to Node B.
- Restore the original release and exact Keepalived enablement state.

### Scenario 3: Node B controlled Caddy-HA and SSH outage

- Pre-arm a transient recovery unit on Node B.
- Stop Node B Keepalived, Caddy, managed lsyncd, reconciliation path, synchronization-health timer, and `ssh.service`.
- Require Node A to remain stable MASTER with all four VIPs and shared service continuity.
- Publish and promote one normal Node A revision.
- Require it to remain queued with no Node B incoming candidate during the 12-second outage window.
- Restore Node B SSH, Caddy, lsyncd, reconciliation, timers, and Keepalived.
- Require one A→B transfer, finalization, and activation within 60 seconds.
- Require Node B stable BACKUP, zero VIPs, and no duplicate reconciliation.
- Remove the recovery unit and restore the original releases.

### Scenario 4: Node B automated reboot

- Persistently disable Node B Keepalived before reboot.
- Schedule reboot and require the physical SSH endpoint to transition down and back up with a changed boot ID.
- Require Node A to remain stable MASTER and maintain DNS, trusted HTTPS, and the shared UI.
- While Node B is unreachable, publish and promote one normal Node A revision and require it queued.
- Poll Node B for at most 300 seconds.
- Require boot-enabled Caddy, managed lsyncd, reconciliation, timers, and SSH to recover automatically.
- Require exactly one queued A→B transfer and activation within 60 seconds.
- Re-enable and start Node B Keepalived and require stable BACKUP with zero VIPs.
- Restore the original release and exact Keepalived enablement state.

A powered-off host is not tested; that requires an out-of-band power controller or manual intervention and is outside this bounded automated action.

## Recovery and Final Acceptance

After every phase:

- Freeze fixture-producing transport.
- Restore SSH before attempting remote cleanup.
- Restore service enablement and active states.
- Restore original release symlinks and reload Caddy only when selection changed.
- Remove only exact transaction-owned outgoing, incoming, installed-release, recovery-unit, staging, trigger, and backup artifacts.
- Restore preferred Node A ownership and stable Node B BACKUP state.
- Reset only workers failed by the active scenario.
- Return `125` if either node fails to return, SSH cannot be restored, or ownership, releases, services, or cleanup cannot be proven.

Final acceptance requires:

- Exact original Action 32g production hashes and releases.
- Node A MASTER with all four VIPs; Node B BACKUP with none.
- Persistent units active and enabled, static units not enabled, and masks intact.
- Stable managed-lsyncd state and no unexplained automatic restart increase.
- Empty Action 33 residue and no unexpected quarantine.
- Healthy DNS, TLS, shared and node-specific Pi-hole interfaces, reconciliation, and timers.
- Notification-delivery failures remain recorded but non-blocking.

## Validation

- Exercise the actual generated remote programs, publisher, receiver, finalizer, reconciler, lsyncd configuration, reboot scheduler, transient recovery units, and exact cleanup paths.
- Negative coverage must reject:
  - Invalid or partial release selection.
  - Same-parent winner selection.
  - Node B publication without `--emergency`.
  - Emergency publication before Node B owns both families and all four VIPs.
  - Transport occurring while the destination is offline.
  - Missing down/up transition or unchanged boot ID in reboot scenarios.
  - Keepalived starting prematurely after reboot.
  - Duplicate reconciliation, revision drift, simultaneous ownership, incomplete cleanup, or unproven recovery.
- Add an Action 33 focused profile selecting current synchronization, systemd, ownership, DNS/TLS continuity, and shared policies.
- Run focused host validation and one network-disabled Debian 12 batch only.
- Do not run the historical complete suite.
- Stop after definition and report the exact outer SHA-256 for live authorization.

## Assumptions

- Rolling maintenance uses current installed binaries.
- Scenarios 1 and 3 are controlled Caddy-HA service plus SSH-transport outages.
- Scenarios 2 and 4 are real automated reboots, not power-offs.
- Definition does not contact either HA node.

## Current-production successor boundary

Action 33b supersedes the consumed Action 33a definition without replaying it.
Its baseline and final acceptance classify only the outbound entries present in
current production. Node A may contain zero or more entries; every entry that
exists must satisfy the complete Node A role, immutable-release, manifest,
ownership, and mode contract. Node B remains empty. Historical outbound
fixtures, prior-deployment inventories, and an artificial requirement that
Node A contain a replay are prohibited.

The interrupted-transfer case derives its one replay from the current active
release. Before stopping managed lsyncd or writing a candidate, it must prove
the exact active-revision destination is absent. An existing destination fails
closed without alteration. The action creates and later removes only that
transaction-owned current-production replay.

## Health-timer-guarded successor boundary

Action 33c supersedes consumed Action 33b without rerunning it. Action 33b
proved the current-production outbound contract and invalid-release rejection,
then stopped because `caddy-sync-health.timer` remained active while the
transaction intentionally restarted managed lsyncd. The health worker observed
lsyncd in `activating` state and correctly failed its ordinary production
contract.

Action 33c must stop the synchronization-health timer before every intentional
lsyncd stop or restart. It records and preserves the timer's enabled state,
stops any in-flight health worker, and requires the timer to remain inactive
through the lsyncd transition. After transport restoration, it requires five
stable PID/restart samples and successful lsyncd unit state, resets the health
worker only when it is failed, invokes and accepts the worker independently,
then enables, starts, and accepts the timer. Controlled-outage recovery units
restore SSH, Caddy, lsyncd, and reconciliation but do not start the health
timer; the outer transaction performs the health acceptance afterward.
Reboot scenarios disable the timer before reboot and restore it only after the
returned node's lsyncd service is stable.

The initial Action 33c baseline applies the same guarded sequence so the known
Action 33b-owned Node A health-worker failure can be reset and accepted inside
the authorized transaction. This is not a diagnostic and does not authorize
any predecessor rerun.

Production state must never be seeded merely to satisfy an assertion. Baseline
and final acceptance consume the exact current outgoing, incoming, quarantine,
release, service, and ownership state. Temporary state used by workstation
regression remains beneath workstation `/tmp` and is never uploaded. A live
transaction-owned release is allowed only as an explicit reliability-case
stimulus created by the real protocol-v2 publisher; it may not satisfy a
baseline prerequisite and must be removed by exact path during recovery.

## Fail-closed invalid-transport successor boundary

Action 33d supersedes consumed Action 33c without rerunning it. Action 33c
proved the real receiver/finalizer rejects the deliberately invalid candidate,
then stopped because it incorrectly applied ordinary steady-state PID
stability to the expected fail-closed transport exit.

Action 33d accepts only the exact bounded scenario-owned transition:

- the managed service start command initially succeeds;
- the receiver rejects the invalid manifest;
- managed lsyncd reaches `failed` within 30 seconds;
- systemd reports `Result=exit-code`, `ExecMainStatus=255`, and `MainPID=0`;
- the synchronization-health timer remains enabled but inactive throughout.

Any other result fails closed. After Node B proves the candidate remains
incomplete, no destination release exists, and current selection is unchanged,
the transaction freezes transport and uses the existing exact cleanup and
guarded lsyncd, worker, and timer restoration sequence. Both nodes must return
to the accepted baseline before the interrupted-transfer case begins. This
correction does not seed baseline state and does not convert invalid input into
a successful synchronization result.

## Receiver-rejection-aware successor boundary

Action 33e supersedes consumed Action 33d without rerunning it. Action 33d
proved that the real receiver/finalizer repeatedly rejects the exact
transaction-owned invalid candidate, but production managed lsyncd remained or
returned active instead of exposing the persistent failed unit state required
by that action. The receiver rejection—not a particular transient systemd
state—is the fail-closed protocol result.

Action 33e captures a fresh journal cursor immediately before starting managed
lsyncd and polls only the cursor-bounded `caddy-lsyncd.service` journal for the
exact production rejection
`caddy_sync_finalize_v2_check_manifest_file_set_exact=false`. It independently
requires a successful journal query and the exact rejection within 30 seconds.
On the first observed rejection it immediately stops managed lsyncd, proves the
transport inactive, and keeps `caddy-sync-health.timer` enabled but suspended.
It does not require `Result=exit-code`, `ExecMainStatus=255`, `MainPID=0`, or a
persistent failed state, and it does not accept generic lsyncd or receiver
errors as equivalent evidence.

Node B must then prove the candidate is incomplete, no destination release was
created, and the selected release is unchanged. The existing reverse-order
baseline restoration removes only exact Action 33e paths, stabilizes managed
lsyncd through the existing timer/worker guard, restores the timer, and
independently accepts both nodes before the interrupted-transfer case begins.
All later protocol, rolling-maintenance, online emergency-replication,
controlled-outage, reboot, continuity, recovery, and final-acceptance phases
are retained unchanged. No baseline state is seeded and no separate diagnostic
is required.

## Producer-safe manifest successor boundary

Action 33g supersedes consumed Action 33f without rerunning it. Action 33f
reached the same-parent conflict but constructed each replacement manifest in
`manifest.sha256.new` inside the candidate. Shell redirection created that
file before `find` ran, so it entered its own manifest and was then renamed.
The production receiver correctly rejected the resulting non-exact file set.
Action 33f recovered and independently accepted the exact Action 32g baseline.

Action 33g builds the replacement manifest in a transaction-owned sibling
under the outbound root, outside the candidate enumeration boundary. It then
atomically installs the manifest and independently requires receiver-equivalent
file-set equality and valid checksums before transport may resume. An
interrupted sibling remains inside the exact Action 33g cleanup namespace.

Action 33g begins at same-parent conflict. Completed invalid-release and
interrupted-transfer cases remain consumed. All remaining rolling-maintenance,
online emergency B-to-A replication, controlled-outage, reboot, availability,
recovery, and exact Action 32g final-acceptance requirements remain unchanged.
No historical fixture or production-state seeding is permitted.

## Action 33g execution and bounded-transition continuation boundary

Action 33g was executed once under exact authorization of outer SHA-256
`fa750f9d7b430db9ea0bc13ab73370cb86b8b03ca3cd54b9212646bf2856642f`.
It is consumed and must not be rerun. The corrected manifest construction and
same-parent-conflict case passed, and the complete rolling-maintenance sequence
returned both nodes to the exact Action 32g release and ownership baseline.

The outer returned `1` only because the rolling availability consumer required
zero failed samples across the ownership-transition window. Retained evidence
at `/tmp/caddy-ssh-evidence/action33g/run.t9w5BK/rolling-maintenance.availability`
shows one isolated one-second DNS-VIP query timeout between passing samples;
trusted HTTPS and shared-interface evaluation resumed with the next successful
probe. Final dual-node service, ownership, release, manifest, inventory,
residue, lsyncd-stability, timer, and registry-removal acceptance passed. The
outer did not return `125`, and no additional node diagnostic is required.

The direct continuation must consume the completed same-parent and rolling
phases. Its availability contract may allow only the exact explicitly bounded
VRRP handoff window represented by the retained evidence. It must still reject
any pre-window or post-convergence failure, an unbounded or consecutive outage
beyond the declared SLA, steady-state DNS/HTTPS/UI failure, simultaneous or
incorrect ownership, or incomplete recovery. The continuation begins with the
online guarded B-to-A emergency-replication baseline and retains all controlled
outage, reboot, recovery, evidence, and exact Action 32g final-acceptance
requirements. It may not seed production state, create historical fixtures, or
rerun any consumed predecessor case.

## Action 33h bounded-handoff continuation definition

Action 33h is definition-complete and unexecuted. It consumes the immutable
Action 33g evidence and begins at online guarded B-to-A emergency replication;
same-parent conflict and rolling maintenance are excluded from its live path.
The exact retained rolling stream is repository-pinned at
`Caddy/docs/evidence/action33g-rolling-maintenance.availability`, SHA-256
`926e8f7b15132c0da503c3aca51ab77647afc08b712f0a5e2c9ff3df06f80912`.

The current availability contract requires explicit handoff begin/end markers,
a maximum 15-second handoff, at most one failed sample per handoff, passing
samples immediately before and after a failure, and no more than four seconds
between those pass sample starts. Every failure outside a handoff, consecutive
failure, second failure in one handoff, malformed or overlapping marker, wide
window, edge failure, or steady-state failure is rejected. This bounded SLA is
applied only to deliberate coupled VRRP ownership transitions; it does not
weaken DNS, HTTPS, or shared-interface acceptance after convergence.

All remaining real protocol, guarded publication, controlled outage, reboot,
SSH down/up, boot-ID, queued transfer, reconciliation, timer/worker, recovery,
evidence, exact cleanup, and final Action 32g gates remain. No historical
fixture, production-state seeding, separate diagnostic, or predecessor rerun is
present. Focused host evidence is `/tmp/caddy-focused-validation.dx5MtN` and
network-disabled Debian evidence is
`/tmp/caddy-focused-container-evidence.MJIKZn`. Exact outer SHA-256 for a future
separately authorized execution is
`d8a0ac4e83ef969bfcfa51ef805f8ac60f093809f9de5158a012ee4dbb875aee`.

## Action 33h execution and independently captured rejection successor

Action 33h was executed once under exact authorization of outer SHA-256
`d8a0ac4e83ef969bfcfa51ef805f8ac60f093809f9de5158a012ee4dbb875aee`.
It is consumed and must not be rerun. The exact Action 32g baseline and the
bounded Node A-to-Node B handoff passed with seven of seven availability
samples successful. The action failed before publication because the
`--reject-normal` branch attempted to create two capture paths with one
multi-target `install` command. GNU `install` treated `reject.stderr` as a
directory and returned `1`. Neither the ordinary publisher nor the emergency
publisher ran, and no outage or reboot case began.

Recovery restored and independently accepted both original releases and
manifests, all services and timers, unchanged incoming, outgoing, and
quarantine inventories, Node A MASTER with all four shared VIPs, Node B BACKUP
with zero shared VIPs, and zero Action 33h residue. Evidence is retained at
`/tmp/caddy-ssh-evidence/action33h/run.haEemO`. The return was `1`, not `125`.

Direct Action 33i corrects only that executed live boundary while retaining the
full Action 33h architecture and safety contract. Its real remote program
independently creates `reject.stdout`, `reject.stderr`, and `reject.status`
before invoking the publisher, records the status, emits both bounded streams,
requires nonzero status, and requires the exact guarded rejection. Regression
executes the actual capture helper and rejects the multi-target form. Action
33i starts with online emergency publication because that case remains
unexecuted; completed conflict and rolling-maintenance phases remain excluded.

Focused host evidence is `/tmp/caddy-focused-validation.jaD9CO`; full focused
and network-disabled Debian evidence is `/tmp/caddy-focused-validation.aQidOZ`
and `/tmp/caddy-focused-validation.aQidOZ/debian-evidence`. Exact outer SHA-256
for separately authorized live execution is
`3c0646870e82f02a620d87bbb88eb06ba3e88f2093972a951c91a64a22fd5b36`.

## Action 33i execution and outage-matrix continuation

Action 33i was executed once under its exact authorized hash and is consumed;
it must not be rerun. It completed online guarded B-to-A emergency replication,
normal A-to-B ancestry normalization, and restoration of the original releases.
All 41 availability samples passed. The deliberate handoffs converged in about
6.24 and 22.45 seconds. The outer returned `1`, not `125`, only because the
second duration exceeded the immutable 15-second handoff ceiling. Recovery
proved the exact Action 32g releases, manifests, inventories, services, timers,
preferred ownership, and empty Action 33i residue. Evidence is retained at
`/tmp/caddy-ssh-evidence/action33i/run.29lIJA`. No controlled-outage or reboot
scenario began.

Direct Action 33j consumes all completed cases and begins with the first
unexecuted controlled Node A outage. It then covers the Node A reboot,
controlled Node B outage, and Node B reboot. The explicit handoff ceiling is
60 seconds; the one-isolated-failure, four-second adjacent-pass, and zero
steady-state-failure requirements remain. It uses current production state and
real protocol paths only, without historical fixtures or state seeding, and
retains the complete emergency-only, timer/worker, SSH transition, boot-ID,
queued transfer, reconciliation, cleanup, recovery, status-125, and final exact
Action 32g controls.

Focused host and network-disabled Debian evidence is retained at
`/tmp/caddy-focused-validation.01ONgu` and
`/tmp/caddy-focused-validation.01ONgu/debian-evidence`. Transaction SHA-256 is
`85f4c6d7234be26a3d7dd818f2ff4fcd945e46937bae4f57624a7d0c15e9dfec`;
regression SHA-256 is
`f4bb93bacef923a9471d16c696d3138181fea298b2a393d0c3203abb4ac34803`;
manifest SHA-256 is
`df61b27f882538aa64797824715805c5b7f93f644cfc024ba82789db7a3b489d`.
Live execution requires separate exact authorization of outer SHA-256
`d3b8b5438849ebe2282beb3b83362a74b7e4cea9643780997625e07c1499e4af`.

## Action 33j controlled-outage execution and Action 33k continuation

Action 33j was executed once under its exact authorized hash and is consumed;
it must not be rerun. The controlled Node A outage, guarded emergency B-to-A
replication, normal ancestry restoration, cleanup, and exact Action 32g recovery
all completed. Node B became stable dual-stack MASTER while Node A was offline,
and preferred Node A ownership was restored afterward. All 102 availability
samples passed. The deliberate handoffs lasted about 10.06 and 22.39 seconds,
both below 60 seconds. Evidence is retained at
`/tmp/caddy-ssh-evidence/action33j/run.WmTuzO`.

The outer returned `1`, not `125`, only because its final availability sample
was torn locally: the producer was killed after writing the timestamp and DNS
answer but before appending `ok`. Exact grammar rejected it, after which
automatic recovery again passed full dual-node acceptance and removed both
registry copies. No reboot or Node B outage case began.

Action 33k consumes the completed controlled-outage case and begins at the Node
A reboot. Its producer stops cooperatively between samples: the active bounded
sample finishes, the producer exits, and the consumer waits before parsing. A
bounded fail-closed fallback cannot feed a partial sample to acceptance. The
real start/stop path is regression-tested, and every existing outage, reboot,
emergency-only, timer/worker, SSH transition, boot-ID, synchronization,
cleanup, recovery, status-125, and final Action 32g gate remains.

Focused host and network-disabled Debian evidence is retained at
`/tmp/caddy-focused-validation.jvrui3` and
`/tmp/caddy-focused-validation.jvrui3/debian-evidence`. Transaction SHA-256 is
`8c15438a4ea6179a13db669a635d9d0c400cd38355c45596660be2841f5cf4a5`;
regression SHA-256 is
`c93203c3ea5536486cf4b14e3fb7daa84a93883ce9f67fafd7d6b0dc0085d954`;
manifest SHA-256 is
`3c23edbcce9dc78e7b1f12ab8830a8de08130fe07dd9e848860f6184e80986a7`.
Live execution requires separate exact authorization of outer SHA-256
`da933f4a6896b6e57c9ab87fa47c413d30740e339d7bfee5ca2dc12cd4d39e20`.

## Action 33k execution and Action 33l recovery continuation

Action 33k was executed once under its exact authorized hash and is consumed;
it must not be rerun. The Node A reboot, SSH down/up transition, changed boot
ID, 69 of 69 availability samples, failover, failback, and preferred ownership
convergence all passed. The action returned `125` because its Node A release
and inventory baseline was retained only in node-local `/tmp` and was lost at
reboot. Node A remains on normalized release
`action33k-20260813T000701Z-2499021-node-a-reboot-normalized`, manifest SHA-256
`bf711fa44181d89654ea08530d5fd44a9dade7dc1a4cd5ea42858b1309d8f807`.
Node B remains on exact Action 32g release
`20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04`, manifest SHA-256
`beb54698e8722d6450f1125fd843808a376cf1be31dcbdef8fafe3cc5ba56109`,
with the repeated normalized release quarantined and its reconciliation worker
failed. No Node B scenario ran. Evidence is retained at
`/tmp/caddy-ssh-evidence/action33k/run.z4QPhl`, aggregate SHA-256
`e28139f934ef59d2cd4b75aa90226dd9ab2852f10bb9966fe93c11647c02be3c`.

Direct Action 33l is definition-complete and unexecuted. It freezes transport
standby-first, validates the exact known Action 33k normalized identity at only
its allowed release, incoming, outgoing, and quarantine paths, restores Node A
to exact Action 32g, removes only those validated residues, conditionally
resets Node B's failed reconciler, and requires full dual-node convergence. It
then runs only the unexecuted Node B controlled-outage and reboot cases.

All state needed after reboot is archived, downloaded, mode-locked, and
SHA-256-verified in workstation `/tmp` before reboot. Both the accepted
baseline and Node B pre-reboot scenario cursor are uploaded and independently
verified after return; node-local `/tmp` is never treated as persistent. Exact
cleanup, continuous availability, current production protocol paths,
timer/worker guards, A-to-B queued synchronization, boot-ID checks,
reverse-order recovery, status `125`, and final Action 32g acceptance remain.
No historical fixture, production-state seeding, diagnostic, or predecessor
rerun is present. Focused host validation passed at
`/tmp/caddy-focused-validation.H0L0oa`, and the one network-disabled Debian 12
batch passed at `/tmp/caddy-focused-container-evidence.N3WRKi`. Transaction
SHA-256 is
`26e0d45fe6dcb5d49c8d8859837050c43a025e1351eb324202f6cbc0d32f71dc`;
regression SHA-256 is
`937fcb4a65f01498e3aceb46663e45ec3cd841c9bc6ec6a96de7b87f20091d83`.
Manifest SHA-256 is
`ba44de490fb8f1fd743633d8aab28ddd9838c89142ec3ca7a33c901e4a3427a7`.
Live execution requires separate authorization of exact outer SHA-256
`aea3221bdf3850af14009051ef9b57401906f9f476d60bdf1136179637d9d62b`.

## Action 33l execution and Action 33m two-family successor

Action 33l was executed once under its exact authorized outer SHA-256 and is
consumed; it must not be rerun. It failed closed during the first Node A
read-only recovery preflight with status `1` and exact assertion
`action_33l_remote_node_a_check_failed_action33k_path_exact=false`. No recovery
freeze or mutation entrypoint ran, neither Node B outage scenario began, and
the uploaded registries were removed. Workstation evidence is retained at
`/tmp/caddy-ssh-evidence/action33l/run.xQQgAG`, aggregate SHA-256
`d73c07fc7a1a47a300c5f1c3573fb49ebec20667abe60e903fcccce4259004aa`.

The rejected path belongs to the exact Action 33k emergency revision
`action33k-20260813T000701Z-2499021-node-a-reboot`; Action 33l recognized only
its normalized child
`action33k-20260813T000701Z-2499021-node-a-reboot-normalized`. Direct Action
33m accepts exactly those two families at their protocol-defined release,
incoming, outgoing, or quarantine locations. Before any cleanup, every matching
path must be a safe valid release, carry its exact revision, and have payload
manifest bytes equal to Action 32g after excluding only the intentionally
different `release-manifest.json` identity line. The emergency family must be
from Node B with Action 32g as parent and exact release-manifest SHA-256
`79cacd055fd5823443129b1721e591933317c3ac9ff8c4e00d7694f768a22230`.
The normalized family must be from Node A with the emergency revision as parent
and exact release-manifest SHA-256
`bf711fa44181d89654ea08530d5fd44a9dade7dc1a4cd5ea42858b1309d8f807`.
Any unrecognized path, payload drift, ancestry drift, identity drift, or third
family fails before cleanup.

After this two-family validation, Action 33m retains Action 33l's standby-first
transport freeze, exact Action 32g restoration, exact-path cleanup, conditional
reconciler reset, full convergence, workstation-persistent reboot state,
continuous availability, reverse recovery, and status `125` controls. It then
runs only the unexecuted Node B controlled-outage and reboot scenarios. Action
33m does not rerun Action 33l or any completed Action 33 case. Focused host
validation passed at `/tmp/caddy-focused-validation.zzauzP`, and the single
network-disabled Debian 12 batch passed at
`/tmp/caddy-focused-container-evidence.naE0C2`. Transaction SHA-256 is
`756b158fd8ca307049a4f5c89e0af6f5256433410d31ab859e53887e4f70ef81`;
regression SHA-256 is
`f290bb82880f1b81e2e1c55b010019516c2ca66b9f183592b4c486b3b0ee8323`.
Manifest SHA-256 is
`8fb3ebd48cc963188065e359e02107125f6b6682cc5c3d9403c23ae81ca1b527`.
Live execution requires separate authorization of exact outer SHA-256
`81c5a5e745acf6cb53f82a50efc27b83b35bb3c81ab8cea242604c7e1048d64a`.

## Action 33m execution and Action 33n supported-identity successor

Action 33m was executed once under its exact authorized outer SHA-256 and is
consumed; it must not be rerun. All workstation gates passed, both registries
uploaded successfully, and Node A's first read-only recovery preflight accepted
the exact Action 33k path. The composite family validator then returned status
`1` at `failed_action33k_candidate_valid=false`. No transport freeze, cleanup,
baseline restoration, or outage scenario began. Both registry copies were
removed with status `0`. Evidence is retained at
`/tmp/caddy-ssh-evidence/action33m/run.E9TEiy`, aggregate SHA-256
`b517fc714d7c7442dc8cd68e3af04fc8e81892a7241393be01727f2952da4a7e`.

The rejected prerequisite was the inferred emergency release-manifest hash,
which was reconstructed rather than observed from production. Direct Action
33n removes only that unsupported hash comparison. The emergency family still
requires its exact allowed path and revision, source Node B, parent Action 32g,
a safe valid release, and payload-manifest equality with Action 32g after
excluding only the release identity line. The normalized family retains all of
those structural and payload checks plus source Node A, the exact emergency
parent, and observed release-manifest SHA-256
`bf711fa44181d89654ea08530d5fd44a9dade7dc1a4cd5ea42858b1309d8f807`.
Unknown paths, extra families, unsafe structure, source drift, parent drift,
payload drift, and normalized identity drift remain fail-closed.

Action 33n consumes Action 33m's exact pre-mutation evidence and otherwise
retains the same transport freeze, exact cleanup, Action 32g restoration,
conditional worker reset, convergence, workstation-persistent reboot state,
continuous availability, reverse recovery, and status `125` controls. It runs
only the still-unexecuted Node B controlled-outage and reboot scenarios. No
diagnostic, predecessor rerun, historical fixture, or production-state seeding
is included. Focused host validation passed at
`/tmp/caddy-focused-validation.oMjHkn`; the single network-disabled Debian 12
batch passed at `/tmp/caddy-focused-container-evidence.zG0CaW`. Transaction
SHA-256 is
`78902c19358de600079a1d02150fbaa05b135a5f26f47e05dfab6420c50f2f4d`;
regression SHA-256 is
`c3744f5ae6c977780878ffe50685a0877d2db76423cee2247942466956de486b`.
Manifest SHA-256 is
`e6d81fc2ff31072bbf92bc4655d4e25c6ce0880c6d2ccfe35eaea905b8ea5172`.
Live execution requires separate authorization of exact outer SHA-256
`387aa0b524eec010fbf1141a9e20b6871a78b4e90e24e6142c14119a24463483`.

## Action 33n execution and Action 33o producer-exact successor

Action 33n was executed once under its exact authorized outer SHA-256 and is
consumed; it must not be rerun. Workstation policy, regression, manifest,
registry, and upload gates passed. Node A's first read-only recovery preflight
accepted the Action 32g release identity and exact Action 33k residue path, then
failed closed at `failed_action33k_candidate_valid=false`. No transport freeze,
release restoration, cleanup, service transition, ownership transition, outage,
or reboot began. Both uploaded registries were removed successfully. Evidence
is `/tmp/caddy-ssh-evidence/action33n/run.EVWPHw`, aggregate SHA-256
`54ea29edf6c317c3cbd20aeab677e04ff9d944f5e8477a29e21edd34bf5764b5`.

The rejected comparison was not a production defect. Action 33k's real
`prepare_fixture_source` copied the then-current release and appended one exact
`# Action 33k reliability fixture <revision>` line to `Caddyfile` for every
publication. Therefore its emergency candidate is the Action 32g payload plus
the exact emergency comment, and its normalized child is that emergency
payload plus the exact normalized comment. Action 33n incorrectly discarded
only `release-manifest.json` before comparing manifests and consequently
rejected the intentional `Caddyfile` differences.

Direct Action 33o retains exact allowed paths, revisions, source nodes, parent
chain, safe release structure, complete manifest verification, and normalized
release-manifest SHA-256
`bf711fa44181d89654ea08530d5fd44a9dade7dc1a4cd5ea42858b1309d8f807`.
It compares the complete nonidentity payload inventory and every unchanged
file hash to Action 32g, then reconstructs and compares the two exact
producer-authored `Caddyfile` transformations. Its regression extracts and
executes the immutable Action 33k `prepare_fixture_source` function, redirecting
only the privileged `/run` stage into a private test directory, and proves both
real transformations plus drift rejection. It creates no production fixture
and seeds no production state.

After this corrected read-only family preflight, Action 33o retains Action
33n's transport freeze, exact family cleanup, Action 32g restoration,
conditional worker reset, convergence, workstation-persistent reboot state,
continuous availability, reverse recovery, and manual-intervention status
`125`. It resumes only the unexecuted Node B controlled-outage and reboot
scenarios. Focused host and network-disabled Debian 12 validation passed at
`/tmp/caddy-focused-validation.789on9` (container evidence beneath
`debian-evidence`). Transaction SHA-256 is
`04dd1475fc01f6bf950ea0aad00b73399199c92b6de4de5f3bb6fe72ddd27723`;
regression SHA-256 is
`3c5adade929d44f2dc9ce736b86a9730f6b28e54539218f6eae0c33e62cc4e6a`;
manifest SHA-256 is
`37749729d091c191f2589d60e24feb6a5743e476ede3994f777dc8bcd0dd28cc`.
Live execution requires separate authorization of exact outer SHA-256
`14b1f7d5b1488218fdb0117c992ed615ec64d08283423189ba32862aea22e064`.

## Action 33o execution and Action 33 closure

Action 33o was executed once under exact authorization of outer SHA-256
`14b1f7d5b1488218fdb0117c992ed615ec64d08283423189ba32862aea22e064`.
It returned `0`, is accepted and consumed, and must not be rerun. Its corrected
producer-exact preflight accepted all three retained Action 33k paths across
the two exact revision families. Transport was frozen standby-first, both
nodes were restored to the exact Action 32g release, only the validated Action
33k family was removed, the failed reconciliation state was reset, and full
dual-node convergence passed before the remaining scenarios began.

The Node B controlled Caddy-HA and SSH outage completed with 50 of 50
one-second DNS, trusted-HTTPS, and shared-Pi-hole-interface samples passing.
The normal Node A publication remained queued while Node B was unavailable,
then transferred, finalized, reconciled, and activated once Node B recovered.
Node A remained stable dual-stack MASTER with all four shared VIPs; Node B
returned to stable dual-stack BACKUP with zero shared VIPs. Exact Action 32g
release selection and transaction-owned cleanup were accepted on both nodes.

The Node B automated reboot completed with 40 of 40 availability samples
passing. Node B's boot ID changed from
`8a45746a-5c62-4b1a-a42b-11e901a02bfc` to
`2b244a4e-4fd6-4785-b406-bde2e23d7c10`. The queued normal Node A publication
was transferred exactly once after Node B returned; boot-enabled Caddy,
managed lsyncd, reconciliation, timers, SSH, and Keepalived recovered; and
Node B returned to stable BACKUP with zero shared VIPs. The final steady-state
acceptance added 5 of 5 passing availability samples.

Every retained workstation command-status file contains `0`. Final acceptance
proved the original Action 32g release
`20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04` and manifest SHA-256
`beb54698e8722d6450f1125fd843808a376cf1be31dcbdef8fafe3cc5ba56109`
on both nodes; active and enabled persistent services, paths, and timers;
stable managed-lsyncd PIDs and restart counts; Node A MASTER ownership of all
four shared VIPs; Node B BACKUP ownership of none; absence of outgoing,
incoming, installed-release, and registry residue; and successful shared and
node-specific DNS/UI probes. The observed Node B `STOP` to `BACKUP` notifier
sequences correspond to the two deliberate outage phases; notifier delivery
remained non-blocking.

Node evidence is retained at
`/tmp/caddy-action33o/20260813T014821Z-3215217`. Workstation evidence is
retained at `/tmp/caddy-ssh-evidence/action33o/run.zydNJA`, aggregate SHA-256
`e3a46a0d4f513e07bbf090a9fc934a2c07f92e0ff57ef5551f7f4c486174ba68`.
Action 33 is complete: its invalid-release, interrupted-transfer,
same-parent-conflict, rolling-maintenance, online emergency B-to-A, Node A
controlled-outage/reboot, and Node B controlled-outage/reboot cases have all
been exercised through the consumed Action 33 successor chain. No further
Action 33 diagnostic, continuation, or acceptance action is required.
