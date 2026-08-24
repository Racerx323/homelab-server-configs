# Caddy deployment archive

The main branch contains current production artifacts and approved future work.
Git preserves the complete deployment journal and executed action files.

## Current deployment window

- State: clean
- Latest archive tag: `caddy-action35as-terminal-2026-08-24`
- Terminal action: Action 35as completed all nine controlled serving-failure
  scenarios, is archived and cleaned, and must not be rerun.
- Successor registry: none. The neutral operation specification is inactive.

## Action 35as terminal result

- Tag: `caddy-action35as-terminal-2026-08-24`
- Authorized outer SHA-256:
  `9e0ad4c77ddd5d44ee69cde1bbd57f2dd4b24005602fc85babb29c7b2e42535b`
- Transaction SHA-256:
  `77a8e54d5d3596d09c6340d74a4e2d29ff7c4e7de322271a9527aa84a536240b`
- Result: accepted; exit status 0.
- Workstation evidence: `/tmp/caddy-ssh-evidence-serving_health.eFo6Gh`.
- All nine Node A and Node B Caddy, lighttpd, Pi-hole FTL, Unbound, and
  Keepalived scenarios completed with their required coupled or
  notification-only behavior.
- The complete de-duplicated lighttpd journal accepted exactly one failure and
  one recovery for both node scenarios. Durable notification delivery remained
  outside serving-health decisions.
- Continuous dual-stack evidence, bounded convergence, exact ownership,
  configured failure/recovery thresholds, structured notifications, service
  restoration, evidence readback, and disposition all passed.
- Operator Apprise readback independently confirms the structured DNS failure,
  failover, standby, and recovery sequence plus matching-correlation Proxy
  failure/recovery delivery for the notification-only lighttpd episode.
- All workstation status records were zero. Final acceptance proved three Node
  A `MASTER/MASTER` samples with four VIPs and three Node B `BACKUP/BACKUP`
  samples with zero VIPs.
- Caddy, lighttpd, Pi-hole FTL, Unbound, and Keepalived were active on both
  nodes; mutation and watchdog residue were absent. Rollback was not required.
- Action 35as is consumed and must not be restored, modified, or rerun.
- Status: archived and cleaned. Its consumed operation data and coverage are
  absent from the current deployment window, and the Caddy stream is clean.

## Action 35ar terminal result

- Tag: `caddy-action35ar-terminal-2026-08-24`
- Authorized outer SHA-256:
  `2087730e7bb817c63939dca4f488554492601e5d831b7ab1199cdb9a5e71a437`
- Transaction SHA-256:
  `1d7e0a635d1ca395eb6e146308cb8bec85851dcd6260ff7d824ef07ce44ef769`
- Result: failed-consumed after mutation; observed exit status 1.
- Workstation evidence: `/tmp/caddy-ssh-evidence-serving_health.cpiT8z`.
- The Node A Caddy scenario completed its coupled failover, bounded convergence,
  and recovery. The deliberate Node A lighttpd outage then produced the valid
  durable state `enqueue-failure-pending` and no VIP movement.
- After lighttpd restoration, the full cursor-bounded daemon journal retained
  exactly one `pihole-web` failure enqueue at `2026-08-24T10:37:08.950857-0500`
  and one recovery enqueue at `2026-08-24T10:37:09.786285-0500`. The producer
  logged `recovery-enqueued`, and Apprise delivered the failure as
  `recovered-before-enqueue` followed by recovery with the same correlation ID.
- The narrower identifier-selected notification artifact retained only the
  recovery enqueue. Lighttpd readiness counted that incomplete artifact rather
  than the complete cursor-bounded journal and emitted
  `serving_health_deployment_check_exercise_journal_complete=false`.
- This is an evidence-selection defect, not lost durable delivery and not a
  serving-health architecture defect. A successor must use the complete bounded
  journal evidence for the exact failure/recovery episode and regression-test
  the real selector behavior; the remaining exercise is unchanged.
- Automatic recovery and final acceptance proved three Node A `MASTER/MASTER`
  samples with four VIPs, three Node B `BACKUP/BACKUP` samples with zero VIPs,
  all five serving services active on both nodes, and no mutation or watchdog
  residue.
- Exit status 1 remains immutable. Action 35ar must not be restored, modified,
  or rerun.

## Action 35as definition

- Scope: direct continuation of the controlled DNS and Proxy serving-failure
  exercise using the neutral transaction and outer runner.
- Consumes Action 35ar and its retained evidence without restoring, modifying,
  or rerunning it.
- The complete cursor-bounded journal is the de-duplicated union of the
  service-unit and identifier-selected records. Lighttpd episode acceptance
  evaluates exactly one failure enqueue and one recovery enqueue against that
  complete artifact.
- Real production-path coverage reproduces the observed selector split: the
  failure enqueue is visible only through the service-unit selection and the
  recovery enqueue only through the identifier selection. The old narrow
  notification-only predicate cannot satisfy this case.
- No producer, notification, serving-health, scenario, continuity, ownership,
  restoration, or status-125 behavior changes. The remaining exercise is
  unchanged.
- Definition and validation are repository-only and contact no HA node. Live
  execution requires a separate authorization of the exact neutral outer SHA.
- Authorization-ready command:
  `/bin/bash Caddy/scripts/run-serving-health-deployment-outer.sh`.
- Outer SHA-256:
  `9e0ad4c77ddd5d44ee69cde1bbd57f2dd4b24005602fc85babb29c7b2e42535b`.

## Action 35aq terminal result

- Tag: `caddy-action35aq-terminal-2026-08-24`
- Authorized outer SHA-256:
  `e35bfd28065ccc5e98c8d5ccdce2f801a6a5a15ef015b3d07ad71b159b2fa0bd`
- Transaction SHA-256:
  `86e0653b435d6c0443da46eeb13361edc52a93daf8725d000b6b9e01318ba64b`
- Result: failed-consumed after mutation; observed exit status 1.
- Workstation evidence: `/tmp/caddy-ssh-evidence-serving_health.BPx1JI`.
- Node A's Caddy scenario completed coupled failover and recovery, but the
  continuous samplers retained primary shared-service failures during the
  handoff: Node A IPv6 Proxy HTTPS and shared UI, Node B IPv4 DNS, and a later
  Node A IPv4 Proxy HTTPS request. The then-current repository law rejected
  every failed primary request and used retries only for classification.
- The same scenario's affected-node UI failed while Node A Caddy was
  deliberately stopped. That local outage is expected and the governing plan
  says it is evidence rather than a shared-continuity failure, but the sampler
  predicate did not encode that distinction.
- Node A's lighttpd stop was accepted in systemd state `failed`, and the
  expected node/shared UI outage was repeatedly observed with no VIP movement.
  Two timer invocations durably retained the episode but logged
  `enqueue-failure-pending`; the observer incorrectly accepted only
  `failure-retained` and emitted
  `serving_health_deployment_check_exercise_lighttpd_outage_observed=false`.
- After automatic restoration, the producer enqueued one Proxy failure as
  `recovered-before-enqueue` and one recovery with the same correlation ID.
  The operator's Apprise output confirms both deliveries.
- Outer emergency restoration returned zero. Final acceptance proved Node A
  dual-stack `MASTER` with four VIPs, Node B dual-stack `BACKUP` with zero
  VIPs, all five serving services active on both nodes, and no mutation or
  watchdog residue.
- Exit status 1 remains the immutable result. Action 35aq must not be restored,
  modified, or rerun.

## Action 35ar definition

- Scope: controlled DNS and Proxy serving-failure exercise using the neutral
  reusable transaction and outer runner.
- Consumes Action 35aq and its retained evidence without restoring, modifying,
  or rerunning it.
- The durable Pi-hole web state `enqueue-failure-pending` is accepted during
  the deliberate lighttpd outage only when restoration subsequently produces
  exactly one failure enqueue and one recovery enqueue for that episode.
- The affected node's local UI outage during its deliberate Caddy stop is
  expected evidence. Lighttpd permits only its expected affected-node and
  shared UI outage and remains notification-only with no VIP movement.
- A primary request under settled ownership still rejects. During a deliberate
  coupled failover or failback, a failed shared request is accepted only when
  the same endpoint and family succeeds within 12 seconds and a timestamped
  kernel address event causally proves VIP transition before recovery.
- Missing or late recovery, missing transition evidence, persistent family
  degradation, ambiguous or simultaneous ownership, and all settled-owner
  failures reject.
- Definition and validation are repository-only and contact no HA node. Live
  execution requires a separate authorization of the exact outer SHA-256.
- Authorization readiness passed against the real neutral production paths.
  Command: `/bin/bash Caddy/scripts/run-serving-health-deployment-outer.sh`.
  Outer SHA-256:
  `2087730e7bb817c63939dca4f488554492601e5d831b7ab1199cdb9a5e71a437`.

## Action 35ap terminal result

- Tag: `caddy-action35ap-terminal-2026-08-24`
- Authorized outer SHA-256:
  `6f045f38c55fe956cb7febeff677f658c30a0d1d7e8f70cf38033a1e7f5d984f`
- Transaction SHA-256:
  `45b629440ed9511358e2349ccc3ab3c78abf9f3764fb772c7006d86a1227ce21`
- Result: failed-consumed after mutation; observed exit status 125.
- Workstation evidence: `/tmp/caddy-ssh-evidence-serving_health.h3GlvO`.
- The Node A Caddy scenario completed its coupled failover and recovery: Node B
  assumed all four VIPs, Node A recovered, and the preferred ownership baseline
  returned.
- The Node A lighttpd stop completed, and systemd reported the valid non-running
  state `failed`. The transaction accepted only `inactive` and emitted
  `serving_health_deployment_check_exercise_service_stopped=false`.
- Orchestration defect: the transaction wrote its mutation marker before the
  stop, but the outer runner set `exercise_service_mutated=true` only after the
  entire remote stop call returned successfully. The state assertion failed in
  that gap, so neither the watchdog nor outer emergency restoration ran.
- Manual recovery started Node A lighttpd. Caddy initially returned 503 during
  its configured 30-second backend-down interval, then the Pi-hole web monitor
  emitted one failure and one recovery with the same correlation ID and no VIP
  movement.
- Final manual verification proved Caddy, lighttpd, Pi-hole FTL, Unbound, and
  Keepalived active on both nodes; Node A dual-stack `MASTER` with all four
  VIPs; Node B dual-stack `BACKUP` with zero VIPs; and successful backend,
  node-specific UI, shared UI, trusted IPv4/IPv6, and DNS checks.
- Manual recovery evidence:
  `/tmp/caddy-action35ap-recovery-node-a.stdout` and
  `/tmp/caddy-action35ap-verify-node-{a,b}.stdout`; corresponding stderr files
  are retained with mode `0600`.
- Exit status 125 remains the immutable observed result. Recovery is now proven
  only because the bounded manual intervention completed after the transaction.

## Action 35ao terminal result

- Tag: `caddy-action35ao-terminal-2026-08-23`
- Authorized outer SHA-256:
  `b36a91890b21c7a7550f45caf6a1e6756af0d2f132d6207ad3591fd8bd62df22`
- Transaction SHA-256:
  `fc0feed5d506d53b9f9cc755aec56d9bb540ce0ecea82ffa31aee89ea19604bf`
- Result: failed-consumed after mutation; exit status 125.
- Workstation evidence: `/tmp/caddy-ssh-evidence-serving_health.IUbJF4`.
- The first `node-a-transient-caddy` scenario stopped and restored Caddy on
  Node A. It unexpectedly crossed the coupled failure threshold: Node A moved
  `MASTER -> FAULT`, Node B moved `BACKUP -> MASTER`, and the preferred baseline
  was subsequently restored. No later scenario ran.
- Defect 1: the transient scenario did not bound the interruption to exactly
  one failed Keepalived execution and did not observe ownership continuously;
  its post-restoration ownership check could not prove that VIP movement never
  occurred.
- Defect 2: the journal acceptance expected one
  `VRRP_Script(check-caddy) failed` record but the retained cursor-bounded
  journal observed zero. Structured notifications independently prove the
  `MASTER -> FAULT`, failover, standby, and recovery transitions, so this is an
  incomplete causal-evidence contract rather than an absent notification.
- Defect 3: Node B's continuous sampler recorded one IPv4 shared Pi-hole UI
  failure, `curl: (16) Send failure: Connection reset by peer`; uninterrupted
  shared-UI continuity was not proven.
- Defect 4: the outer production-path test directly wrote expected journal,
  availability, and ownership results for controlled-exercise modes instead of
  executing the real transaction modes and observing their effects. This
  contradicts the repository anti-fabrication rule and allowed authorization
  readiness to pass without covering the live failure paths.
- Defect 5: the outer classified the sampler acceptance failure as a recovery
  failure and returned 125 even though final ownership, service restoration,
  residue, and disposition checks proved recovery. Status 125 is reserved for
  unproven recovery; an acceptance failure with proven restoration must return
  an ordinary nonzero status.
- Final recovery evidence passed: Node A was dual-stack `MASTER` with all four
  VIPs, Node B was dual-stack `BACKUP` with zero VIPs, all five serving services
  were active on both nodes, mutation/watchdog residue was absent, and upload
  disposition and final ownership checks passed.
- Exit status 125 is the immutable observed result. The audit records its
  classification as defective; it does not reinterpret the successful final
  recovery checks as unproven recovery.
- Status: archived and cleaned. The neutral operation specification is inactive
  and the Caddy deployment stream is clean.

## Post-Action 35ao neutral-framework audit

- Scope: repository-only; neither HA node was contacted and no successor was
  defined.
- Removed the nondeterministic single-sample Caddy scenario because stopping a
  service until the first daemon record cannot guarantee restoration before the
  second `interval 3` execution.
- Journal acceptance now uses separate daemon/service and notification
  selectors after the same cursor and waits for causal scenario-specific
  failure and recovery records.
- Sampler rejection is an ordinary acceptance failure when service restoration,
  final ownership, residue, readback, and cleanup remain proven. Status 125 is
  reserved for unproven recovery after mutation.
- The outer production-path test now streams all controlled-exercise modes
  through the real transaction. Its command substitutes derive journal,
  service, and ownership observations from the exact invoked commands; they do
  not write expected transaction results.
- The single Node B IPv4 shared-UI reset occurred at
  `2026-08-23T23:09:56.742761874Z` during preferred-owner failback. Adjacent
  IPv4 and paired IPv6 samples passed. Missing remote-address and connection
  timing evidence prevents a causal distinction between an in-flight TCP reset
  and a serving gap, so the attribution remains unresolved.

### Continuity-evidence correction checkpoint

- Repository-only; neither HA node was contacted and Action 35ap was not
  defined.
- The neutral sampler records each family and endpoint invocation separately,
  preserving primary/retry identity, bounded timing and error classification,
  exact response evidence, local/remote addresses, VRRP state, and VIP count.
- Timestamped kernel address observers span the complete scenario and final
  convergence window on both nodes. The workstation outer runner validates both
  readbacks and causally classifies any primary failure; every failure class
  rejects acceptance.
- Real transaction coverage proves bounded SIGTERM handling, forced-kill
  escalation for a noncooperative observer child, independent evidence records,
  and zero process or temporary residue.
- Action 35ao remains immutable at `caddy-action35ao-terminal-2026-08-23`; the
  corrected contract was defined repository-only before Action 35ap was
  registered.

## Action 35ap definition

- Scope: the separately authorized controlled Node A and Node B DNS/Proxy
  serving-failure exercise from the exact accepted production baseline.
- Action 35ap consumes failed-consumed Action 35ao without restoring,
  modifying, or rerunning it.
- The nondeterministic transient Caddy scenario remains excluded. The nine
  retained scenarios exercise Node A Caddy, lighttpd, Pi-hole FTL, Unbound,
  and Keepalived behavior plus equivalent Node B Caddy, lighttpd, Pi-hole FTL,
  and Unbound behavior.
- Both nodes retained causal per-request dual-stack evidence and timestamped
  kernel address events for the complete exercise. Under Action 35ap's
  historical contract every primary request failure rejected and a retry could
  classify but not excuse it; Action 35ar supersedes that rule prospectively.
- Missing, malformed, duplicate, reordered, oversized, symlinked, incomplete,
  unsafe, or uncorrelatable evidence fails closed. Sampler and observer
  lifecycle acceptance requires bounded SIGTERM handling, child termination,
  and zero residue.
- Definition and production-path validation contact no HA node. Live execution
  remains gated by a separately reported exact outer-runner SHA-256.

## Action 35ao definition

- Scope: controlled Node A and Node B DNS/Proxy serving-failure exercise from
  the accepted current-production baseline.
- Action 35ao consumes Action 35an without restoring or rerunning it.
- The real `exercise-preflight` entrypoint is exercised through the actual
  streamed outer/transaction boundary in production-path coverage. It derives
  the active release contract from `current-live-state.tsv`; the former
  action-pinned release assumption and marker-only preflight are prohibited.
- The scenarios, continuity requirements, service thresholds, restoration,
  status-125 rule, and zero-residue contract remain unchanged from Action 35an.

## Action 35an terminal result

- Tag: `caddy-action35an-terminal-2026-08-23`
- Authorized outer SHA-256:
  `1508a4a9eaedfa3b2c6d35c62161102d1ecf49943fad771e72bdd4ff419097d3`
- Transaction SHA-256:
  `b53258a8d12d6b9e966e7be6597e755793361eb013a833670751c4fddac6f40f`
- Result: failed-consumed during Node B preflight; exit status 1.
- Workstation evidence: `/tmp/caddy-ssh-evidence-serving_health.o6fsV4`.
- Exact failed assertion:
  `serving_health_deployment_check_notification_state_root_empty=false`.
- Cause: the preflight retained the obsolete pre-Action-35al requirement that
  `/var/lib/caddy-serving-health/keepalived-notify` be empty. Accepted Action
  35al production instead maintains the durable
  `PIHOLE_DUALSTACK.state` record there.
- No controlled failure or production mutation ran. Node A was not exercised.
  Both bounded payloads were disposed, failure evidence was read back, and all
  upload, disposition, and readback statuses were zero.
- Status: archived and cleaned. The successor and coverage registries are
  clear, and the neutral operation specification is inactive.
- Repository correction: the neutral preflight now validates the accepted
  durable state file and optional safe persistent lock instead of requiring an
  empty directory. It rejects pending, additional, symlinked, malformed, and
  incorrectly mode-set state. This correction did not contact either node.

## Action 35an archived definition

- Action 35an uses the neutral reusable transaction and outer runner with one
  versioned operation specification; no action-numbered implementation exists.
- Scope: controlled Node A and Node B DNS/Proxy serving-failure exercise with
  continuous dual-stack shared-service evidence, exact VIP ownership,
  structured notification acceptance, restoration, and zero residue.
- Live execution was separately authorized by the exact outer-runner SHA-256
  above and is now consumed.

## Action 35am terminal result

- Tag: `caddy-action35am-terminal-2026-08-23`
- Authorized outer SHA-256:
  `0eaac466e254c97a4d1a886d64a8be82cb533552687124483fd666677289ea7f`
- Transaction SHA-256:
  `369ec7ce6081680256b592dc7db6f51ef4eb63bc187c583e481704ad4070ce73`
- Result: accepted read-only capture; exit status 0.
- Status: archived and cleaned; the neutral operation specification is
  inactive and the Caddy deployment stream is clean.
- Workstation evidence: `/tmp/caddy-ssh-evidence-serving_health.IoAYyJ`.
- Attribution: `unattributed`; zero causal producer candidates were found.
- Config ID `apprise` was confirmed to be an endpoint list without a message
  template. No request observation or retained source matched the exact legacy
  title within the bounded capture contract.
- All capture, evidence-readback, integrity, and temporary-program cleanup
  statuses were zero. No HA node was contacted, no notification was sent, and
  no production state was changed.
- Repository history identifies the exact legacy title and bodies in notifier
  revisions `e9fe1bc` and `6063aa3`; revision `192b1e1` retired that formatter.
  Together with Actions 35al and 35am proving no current production path,
  notification standardization was accepted and Action 35an became the next
  gate at that checkpoint.

## Action 35al definition

- Action 35al uses the neutral reusable transaction and outer runner; it adds
  no action-numbered implementation.
- A bounded read-only capture found no legacy `[Failover Alert] Pi-hole DNS
  Cluster` literal, queued record, or second notifier on either HA node. The
  remaining duplicate is therefore classified outside the node producer and
  durable queue. Config ID `apprise` contains endpoints only and no template.
  Later repository-history review identified the messages as output from
  notifier revisions retired by `192b1e1`.
- The operation installs only the multiline formatter, durable transition
  state producer, minimal distinct-exit health probes, and their exact
  supporting tmpfiles/worker artifacts, Node B before Node A.
- No serving service is restarted or reloaded. The controlled failure exercise
  remains deferred as Action 35am until Action 35al is accepted.

### Action 35al terminal result

- Tag: `caddy-action35al-terminal-2026-08-23`
- Authorized outer SHA-256:
  `9a93d23ce165dbc9d385b7b978897073c16534a82aca61cbd5e4d86a139a75eb`
- Transaction SHA-256:
  `a8a077ff3475b783434a81b4804bfb2461b358fd36965f3d4b970b0401dff6f8`
- DNS source commit:
  `a8b45d827b1771e16141572c3facce7624fa28e0`
- Result: accepted; exit status 0.
- Status: archived and cleaned; the neutral operation specification is
  inactive and the Caddy deployment stream is clean.
- Workstation evidence: `/tmp/caddy-ssh-evidence-serving_health.5JumxL`.
- Node B completed before Node A. Node B accepted the durable bootstrap state
  `BACKUP`; Node A accepted `MASTER`.
- Exact notification, worker, tmpfiles, DNS probe, Caddy probe, and notifier
  artifacts were installed and accepted on both nodes. Installed-form DNS and
  Caddy probes passed, service state remained active, payload disposition was
  proven, and rollback was not required.
- The supplied Apprise config has no template. Subsequent Action 35am and
  repository-history review identified the observed legacy messages as
  historical output from notifier revisions retired by `192b1e1`.

## Action 35ah terminal archive

- Tag: `caddy-action35ah-terminal-2026-08-18`
- Commit: recorded by the annotated tag
- Action: 35ah
- Authorized outer SHA-256:
  `a5d60392c887d1efc37a04080f8d612f43f0968d564729fa705c31fed6257a49`
- Transaction SHA-256:
  `88eac36e3ce093b761ab8085d83c9359c378e03e2c265880bde1bcff131e9ef0`
- Result: accepted
- Exit status: 0
- Workstation evidence: `/tmp/caddy-ssh-evidence-serving_health.tYH9yd`
- Release: both nodes selected immutable revision
  `20260818T221516Z-f8a87266-2c11-475e-af1e-dd026d44ee8d` from Node A.
- Ownership: Node A settled IPv4/IPv6 `MASTER` with all four VIPs; Node B
  settled IPv4/IPv6 `BACKUP` with zero VIPs. Each retained three stable
  samples.
- Acceptance: all repository artifacts, service enablement/state, daemon-owned
  DNS and Caddy health, continuous dual-stack DNS/HTTPS/UI paths, and final
  incoming, quarantine, and outbound residue checks passed.
- Rollback: not required.
- Status: archived and cleaned; the Caddy deployment stream is clean and the
  neutral operation specification is inactive.

### Post-acceptance finding 2026-08-18

- A bounded read-only audit found that both timer-triggered
  `caddy-pihole-web-health.service` invocations fail before `ExecStart` with
  systemd status `226/NAMESPACE`.
- The accepted unit unnecessarily made its mount namespace depend on
  `/run/caddy-apprise`, a delivery-worker runtime directory that is absent
  while the worker is inactive. The enqueue producer uses only the persistent
  `/var/lib/caddy-apprise-queue` path.
- DNS, Caddy, lighttpd, and VRRP serving state remain healthy; the defect
  suppresses notification-only Pi-hole web-health monitoring.
- The Action 35ah tag and accepted evidence remain unchanged. The direct
  successor must replace only this unit on Node B and then Node A, prove a
  successful direct invocation and subsequent timer-triggered invocation on
  each node, and require no serving-service restart.

## Action 35ai definition

- Action 35ai consumes the accepted Action 35ah state and its bounded
  post-acceptance namespace evidence without modifying or rerunning Action
  35ah.
- It replaces only
  `/etc/systemd/system/caddy-pihole-web-health.service`, first on Node B and
  then on Node A. The corrected unit permits queue writes only beneath the
  persistent `/var/lib/caddy-apprise-queue` hierarchy.
- Each node must pass one direct systemd invocation and a later independent
  timer-triggered invocation. Acceptance also preserves the timer state,
  queue permissions, bounded journal evidence, and active Caddy, lighttpd,
  Pi-hole FTL, Unbound, Keepalived, and caddy-lsyncd services.
- Caddy, lighttpd, DNS, Keepalived, release selection, synchronization, and
  VRRP ownership are outside the mutation set and must not be restarted or
  reloaded.
- On failure after mutation, rollback restores Node A and then Node B to the
  exact accepted unit bytes. Status 125 is reserved for recovery or evidence
  cleanup that cannot be proven.

### Action 35ai terminal result

- Tag: `caddy-action35ai-terminal-2026-08-18`
- Authorized outer SHA-256:
  `7843781191b540bb2614070ebf1e548fcfdb89ee4bf77ae1ee01867cc11d11af`
- Transaction SHA-256:
  `d26c9a01b0b8ca9191b610486b9bfabb24e7e8a525d2346e989a3ecd3bea4c64`
- Result: failed-consumed after Node B mutation; exit status 1.
- Workstation evidence: `/tmp/caddy-ssh-evidence-serving_health.gC2cIP`.
- Both node preflights passed. Node B installed the exact corrected unit, but
  its direct systemd invocation failed because the `pi` service identity could
  not read root:`caddy-tls`:0640 `/etc/default/caddy-ha`.
- Cursor-bounded operator journal evidence at
  `2026-08-18T18:04:59.350802-0500` records `Permission denied` at
  `check-pihole-web-health.sh` line 110. This proves the namespace correction
  reached `ExecStart`; the remaining prerequisite is supplementary membership
  in `caddy-tls`.
- Node A was not mutated. Node B rollback restored exact deployed unit hash
  `a1afee302fa521c9d4ba2eb6d7085e98f261ec5fdd464c156dd11aa1f1cfa3f0`,
  queue permissions remained exact, both payloads were removed, and both
  rollback readbacks passed. Recovery was proven, so status 125 was not used.
- Status: archived and cleaned. Action 35ai is consumed and must not be
  modified or rerun.

## Action 35aj definition

- Action 35aj consumes but never reruns failed-consumed Action 35ai.
- It adds only `SupplementaryGroups=caddy-tls` while retaining `User=pi` and
  `Group=pi`, the persistent queue-only writable path, and all existing unit
  hardening.
- Kernel DAC coverage proves that the service identity cannot read the
  protected environment without the supplementary group, can read it with the
  group, and retains primary-identity queue write access. The root-required
  identity case runs in the network-disabled Debian batch.
- The same neutral transaction installs and accepts Node B before Node A,
  requires direct and later timer-owned successful invocations, and captures
  cursor-bounded journal evidence before rollback on every direct-start
  failure.
- No serving, synchronization, release, or VRRP service is restarted or
  reloaded. Reverse rollback remains Node A then Node B, with status 125 only
  when recovery or cleanup cannot be proven.

### Action 35aj terminal result

- Tag: `caddy-action35aj-terminal-2026-08-18`
- Authorized outer SHA-256:
  `6c257535f012db198948c94224bc7d67a5d772ab28246cfa7b970b93429e999c`
- Transaction SHA-256:
  `0f89055f46e0109ef8fb5cf1b32997b096eb10ea69e2f77c7edd9b159f3d92e3`
- Result: failed-consumed after Node B mutation; exit status 1.
- Status: archived and cleaned. Action 35aj is consumed and must not be rerun.
- Workstation evidence: `/tmp/caddy-ssh-evidence-serving_health.YgxxZn`.
- Both node preflights passed. Node B installed the exact candidate, and its
  direct invocation returned `Result=success`, `ExecMainStatus=0`, and
  `SupplementaryGroups=caddy-tls`.
- The bounded journal contains two `pihole_web_health event=healthy` records
  and two successful completions. Acceptance nevertheless rejected the run
  because only one literal systemd `Starting` message appeared after the
  original cursor.
- Node A was not mutated. Node B rollback restored exact deployed unit hash
  `a1afee302fa521c9d4ba2eb6d7085e98f261ec5fdd464c156dd11aa1f1cfa3f0`;
  both payload dispositions and rollback readback passed. Recovery was proven,
  so status 125 was not used.

## Action 35ak definition

- Action 35ak consumes but never reruns failed-consumed Action 35aj.
- It retains the exact proven unit and standby-first installation logic.
- After direct service success it captures a fresh journal cursor, then
  requires one later `pihole_web_health event=healthy`, one successful systemd
  completion, and `Result=success` with `ExecMainStatus=0`.
- Literal systemd `Starting` message counts are not an acceptance input.
- Node B remains fully accepted before Node A; reverse rollback and all
  no-serving-restart constraints remain unchanged.

### Action 35ak terminal result

- Tag: `caddy-action35ak-terminal-2026-08-18`
- Authorized outer SHA-256:
  `d3e0a1cc4f04c9c362c6c6974578a788f1fb1f7a10913cbef0b6993022842770`
- Transaction SHA-256:
  `1be1360d0cc214b8db067919c2a27176b044a06ab0d6871ff6ba45cd7f14dce7`
- Result: accepted; exit status 0.
- Status: archived and cleaned; the neutral operation specification is
  inactive and the Caddy deployment stream is clean.
- Workstation evidence: `/tmp/caddy-ssh-evidence-serving_health.secstj`.
- Node B completed before Node A. Both nodes installed exact unit SHA-256
  `d773cf7b88429b819a7919dbdf5e939654616c84be538ca1ebfd3d7e3ed9c3fc`.
- Direct and later timer-owned invocations returned `Result=success` and
  `ExecMainStatus=0`; each timer window contained the required
  `pihole_web_health event=healthy` record.
- Required services, timer state, supplementary identity, persistent queue
  ownership and modes, readback, and payload disposition passed on both nodes.
  Rollback was not required.

## Action 35ag terminal archive

- Tag: `caddy-action35ag-terminal-2026-08-18`
- Commit: recorded by the annotated tag
- Action: 35ag
- Authorized outer SHA-256:
  `18fc4e3a97bfe7a36e8b30c286d39c56177ce83ece9963ef8c42df9f20f99511`
- Transaction SHA-256:
  `3f4548c6125a33b4aeb0c58f0fa727e67f4066d7548e0f8bff62c2abe2f541ee`
- Result: failed-consumed during Node A preflight, before any production
  mutation
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-serving_health.UaFJlC`
- Failed boundary:
  `serving_health_deployment_check_incoming_node_a_absent=false`
- Finding: Node A's `/var/lib/caddy-sync/incoming/node-a` is an ordinary,
  empty `caddy-sync:caddy-sync:0750` namespace. The preflight incorrectly
  required the valid empty namespace itself to be absent.
- Recovery: both exact upload dispositions and failure readbacks returned 0;
  no installation, publication, service, release, or VRRP mutation ran, so no
  rollback was required.
- Status: archived and cleaned; the neutral implementation now accepts both
  valid protocol-namespace representations and Action 35ah is defined.

## Action 35af terminal archive

- Tag: `caddy-action35af-terminal-2026-08-18`
- Commit: recorded by the annotated tag
- Action: 35af
- Authorized outer SHA-256:
  `7f92c77f68e7b4dd349d6f293057eb49b5216cbaee62f96877c01b2019ea8af5`
- Transaction SHA-256:
  `69e9ac737a8e89f25fbfbc21b0f222dd98c2fc455f8e974919f140fd4efa3366`
- Result: failed-consumed after Node B installation, Node A split-release
  convergence, and publication of the new immutable child release
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35af.JHd23Z`
- Failed boundary: `action_35_af_check_target_revision_absent=false`
- Finding: the publish phase correctly created revision
  `20260818T210340Z-76baa78a-e88a-4ed6-84eb-ced5d2c4cb0c` and durably wrote
  the Node A target record. The following redundant Node A `record-target`
  phase incorrectly required that same record to be absent.
- Recovery: reverse rollback returned status 0 on both nodes, removed only the
  exact new release and outbound candidate, restored the original split
  release, outbound and quarantine state, and kept all IPv4/IPv6 DNS, HTTPS,
  shared-UI, and node-UI probes successful. Keepalived subsequently converged
  to preferred Node A `MASTER` after its normal initial `BACKUP` interval.
- Status: archived and cleaned; the current branch retains the neutral reusable
  implementation and Action 35ag operation data

## Action 35ae terminal archive

- Tag: `caddy-action35ae-terminal-2026-08-18`
- Commit: recorded by the annotated tag
- Action: 35ae
- Authorized outer SHA-256:
  `3e6a3dd4a0c66d9f587ef37072f1aa419b46d303f32dac4409ed6a0cad6a439f`
- Transaction SHA-256:
  `3d0dac4e42fadf3196ed4cc44e730ecd06c5bcf90d0526d4d294623640e2c33b`
- Result: failed-consumed after Node B installation and before any Node A
  promotion or mutation
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35ae.vfzh11`
- Failed boundary:
  `action_35_ae_check_keepalived_daemon_status_records_valid=false`
- Finding: the real Keepalived executions returned 1 within milliseconds.
  Proxy reported a missing IPv4 probe-result record while DNS failed during
  probe-evidence processing. Direct identity checks had passed, and the
  failures occurred far earlier than the two-second Keepalived timeout. The
  background-probe and temporary-result protocol is therefore removed from the
  current tracking helpers rather than wrapped again.
- Recovery: Node B rollback and rollback readback returned 0, Node B returned
  to `BACKUP`, and Node A was not mutated
- Status: terminal tag and commit recorded; consumed machinery was removed by
  the immediate cleanup commit

## Action 35ad terminal archive

- Tag: `caddy-action35ad-terminal-2026-08-18`
- Commit: recorded by the annotated tag
- Action: 35ad
- Authorized outer SHA-256:
  `c08a0d3fb6aab1daa2f70672b9a32ab4af20ee19af0e56b00fdf6a7babfe9ea4`
- Transaction SHA-256:
  `680478c318b865e3387365ac3cbd3d45a1bbcf9db07788295db8950099e9b4db`
- Result: failed-consumed after Node B installation and before any Node A
  promotion or mutation
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35ad.gAKDlx`
- Failed boundary:
  `action_35_ad_check_keepalived_daemon_status_records_valid=false`
- Finding: Keepalived's real scheduled Caddy helper failed at phase
  `probe-result` and durably recorded `phase-operation-failed` with exit 1.
  The unchecked read of an IPv4 or IPv6 probe status/output file can terminate
  under `set -e` before the helper records the family, curl result, or HTTP
  result. The retained evidence therefore localizes the defect without safely
  distinguishing the affected family or result-file state.
- Recovery: Node B rollback and rollback readback returned 0, Node B returned
  to `BACKUP`, and Node A was not mutated
- Status: terminal tag and commit recorded; consumed machinery was removed by
  the immediate cleanup commit

## Action 35ac terminal archive

- Tag: `caddy-action35ac-terminal-2026-08-18`
- Commit: recorded by the annotated tag
- Action: 35ac
- Authorized outer SHA-256:
  `02636fdf36901d1d05ce02935c60cde03c2553325a4caf2509949917e9e8b319`
- Transaction SHA-256:
  `f1407806d7697b15a33146bb64fc9cd0ad0dab0244887c65a9767443949d279e`
- Result: failed-consumed after Node B installation and before any Node A
  promotion or mutation
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35ac.4Yvvp3`
- Failed boundary:
  `action_35_ac_check_keepalived_daemon_status_records_valid=false`
- Finding: Keepalived's real scheduled DNS and Proxy helpers repeatedly exited
  1. Both helpers durably classified only the terminal fallback
  `unclassified-helper-exit`; their direct candidate identity checks and every
  retained DNS, HTTPS, node-interface, and shared-UI continuity probe passed.
  The retained evidence therefore proves the failing daemon boundary but does
  not identify the exact helper operation. No helper path change is justified.
- Recovery: Node B rollback and rollback readback returned 0, Node B returned
  to `BACKUP`, and Node A was not mutated
- Status: terminal tag and commit recorded; consumed machinery was removed by
  the immediate cleanup commit

## Action 35ab terminal archive

- Tag: `caddy-action35ab-terminal-2026-08-18`
- Commit: recorded by the annotated tag
- Action: 35ab
- Authorized outer SHA-256:
  `f7a294f464d9827a3bd6c5045f0cf62ee2b5a4df404d6d56a3d3cd5b045b0dee`
- Transaction SHA-256:
  `64b92402f1b8264ee298d778347aad1f87dfb1cea72c234d7555adabb9df7911`
- Result: failed-consumed after Node B installation and before any Node A
  promotion or mutation
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35ab.Tjs3z3`
- Failed boundary:
  `action_35_ab_check_keepalived_daemon_journal_no_failure=false`
- Finding: after the intentional Keepalived stop and single restart, the
  daemon's first `check-caddy` and `check-dns` executions both returned status
  1. Neither helper produced a classified status transition, so the coupled
  FAULT notification was necessarily unclassified.
- Recovery: Node B rollback and rollback readback returned 0, Node B returned
  to `BACKUP`, and Node A was not mutated
- Status: terminal tag and commit recorded; consumed machinery was removed by
  the immediate cleanup commit

## Action 35aa terminal archive

- Tag: `caddy-action35aa-terminal-2026-08-18`
- Commit: recorded by the annotated tag
- Action: 35aa
- Authorized outer SHA-256:
  `976e1c4a2bccfd49cecf7e8b8a5a01f0c949d825c2a4f3d749ccd437010092e2`
- Transaction SHA-256:
  `4011f7a3edc27491d603bcec28587824a16a3f202555aa915e129e98f7209415`
- Result: failed-consumed after Node B installation and before any Node A
  promotion or mutation
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35aa.o4OC8v`
- Failed boundary: all 24 bounded ownership samples remained dual-stack
  `Fault` with zero shared VIPs, so
  `action_35_aa_check_ownership_convergence=false`
- Finding: all five transaction-launched DNS and Caddy cycles succeeded, but
  Keepalived's own `check-dns` execution entered FAULT at 11:01:30, ten
  seconds before the candidate reload, while the independent schedule was
  still active. The reload inherited DNS as unsuccessful and the daemon's
  immediate `check-caddy` execution also returned status 1. The independent
  schedule perturbed rather than proved the real daemon execution boundary
  and must not be repeated by the successor.
- Recovery: Node B rollback, rollback readback, sampler shutdown, journal
  capture, and exact upload dispositions returned 0; after the rollback
  reload at 11:02:37, the native DNS check recovered and Node B entered
  `BACKUP` at 11:02:39; Node A was not mutated
- Status: terminal tag and commit recorded; consumed machinery was removed by
  the immediate cleanup commit

## Action 35z terminal archive

- Tag: `caddy-action35z-terminal-2026-08-18`
- Commit: recorded by the annotated tag
- Action: 35z
- Authorized outer SHA-256:
  `6348b45b2c8840f23ddf11d0987da5652c7e3ac18bf0d1dfa4aefd84be53ae92`
- Transaction SHA-256:
  `c442ae83bb4ab6a504b639bfa9439da93e6a6dd750f98ac55ad18f65b676aa8f`
- Result: failed-consumed after Node B installation and before any Node A
  promotion or mutation
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35z.riR2sq`
- Failed boundary: all 24 bounded ownership samples remained dual-stack
  `Fault` with zero shared VIPs, so
  `action_35_z_check_ownership_convergence=false`
- Finding: the retained operator journal proved that Keepalived's real
  scheduled boundary reported `check-caddy` status 1 immediately and an
  intermittent `check-dns` status 1 three seconds later. Both direct
  transaction identity checks and every retained continuity probe passed.
  The transaction's journal selector retained the notification enqueue but
  omitted the decisive `Keepalived_vrrp` script-result records.
- Recovery: Node B rollback, rollback readback, sampler shutdown, journal
  capture, and exact upload dispositions returned 0; Node B returned to
  `BACKUP` and Node A was not mutated
- Status: terminal tag and commit recorded; consumed machinery was removed by
  the immediate cleanup commit

## Action 35y terminal archive

- Tag: `caddy-action35y-terminal-2026-08-18`
- Commit: recorded by the annotated tag
- Action: 35y
- Authorized outer SHA-256:
  `2a9c7ea384c67fff6e5ec224da8c91c798f1783b70edc492f4b25303d2a1364a`
- Transaction SHA-256:
  `70ef7928deee004748fcb36fd12f403a0b46e3b96c869edd3cc4dd201957f3dd`
- Result: failed-consumed after Node B installation and before any Node A
  promotion or mutation
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35y.DS3AuU`
- Failed boundary: the installed Caddy helper passed under explicit identity
  `keepalived_script:caddy-tls`, then acceptance rejected the generated Proxy
  status file at `action_35_y_check_proxy_status_metadata=false`
- Finding: the helper creates its atomic status file with the executing
  process's primary group. The new explicit Keepalived group therefore
  correctly produces `keepalived_script:caddy-tls:0644`; the transaction still
  expected the superseded `keepalived_script:keepalived_script:0644` metadata
- Availability: every retained DNS, trusted HTTPS, node-interface, and shared
  Pi-hole UI sample returned status 0
- Recovery: Node B rollback, rollback readback, sampler shutdown, journal
  capture, and exact upload dispositions returned 0; Node B returned to
  `BACKUP` and Node A was not mutated
- Status: terminal tag and commit recorded; consumed machinery was removed by
  the immediate cleanup commit

## Action 35x terminal archive

- Tag: `caddy-action35x-terminal-2026-08-18`
- Commit: recorded by the annotated tag
- Action: 35x
- Authorized outer SHA-256:
  `7658678cc77877fea3cda054ee3cadd766d65667a5a84c96858a7a7089e92881`
- Transaction SHA-256:
  `a592ab73a4e54591ae968be0fe6be7462233932c02fced4506e5378d279b9dd8`
- Result: failed-consumed after Node B installation and before any Node A
  promotion or mutation
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35x.LPohmq`
- Failed boundary: all 24 bounded Node B ownership samples remained
  dual-stack `Fault` with zero shared VIPs, so
  `action_35_x_check_ownership_convergence=false`
- Finding: the installed DNS and Proxy helpers both passed when invoked through
  `runuser`, which initializes supplementary groups. Keepalived's
  `check-caddy` declaration specified only `user keepalived_script`, while the
  protected environment is `root:caddy-tls:0640`; the daemon path therefore
  did not reproduce the accepted Caddy probe's explicit group context
- Availability: every retained DNS, trusted HTTPS, node-interface, and shared
  Pi-hole UI sample returned status 0
- Recovery: Node B rollback, rollback readback, sampler shutdown, journal
  capture, and exact upload dispositions returned 0; Node B returned to
  `BACKUP` and Node A was not mutated
- Status: terminal tag and commit synchronized; consumed machinery was removed
  by the immediate cleanup commit

## Action 35w terminal archive

- Tag: `caddy-action35w-terminal-2026-08-18`
- Commit: recorded by the annotated tag
- Action: 35w
- Authorized outer SHA-256:
  `63126af7ecb6439ca64725f65ec2b24a6ba5fac5a69cd7fb89ad0bf72ca84659`
- Transaction SHA-256:
  `d6009f031c756652819979d9516967428431559d7884889cbbf965cadac60c01`
- Result: failed-consumed after Node B installation and before any Node A
  promotion or mutation
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35w.XsZ21C`
- Failed boundary: Node B acceptance required
  `/run/caddy-serving-health/dns/status`, but the installed DNS helper had not
  yet initialized that production snapshot before Keepalived was reloaded
- Notification evidence: Node B entered the bounded coupled-group `FAULT`
  transition and subsequently returned to `BACKUP`; the absent source snapshot
  forced the expressive notification fallback
  `eligibility-fault-unclassified`
- Recovery: Node B rollback, rollback readback, both journal captures, sampler
  shutdown, and exact upload dispositions returned 0; Node A was not mutated
- Status: terminal tag and commit synchronized; consumed machinery was removed
  by the immediate cleanup commit

## Action 35v terminal archive

- Tag: `caddy-action35v-terminal-2026-08-17`
- Commit: `9c5f955a5fb7382d48429e37b7e3f1beb4abb962`
- Tag object: `e7c8b0c1c90561a9b0701688879aa9f6c62c679b`
- Action: 35v
- Authorized outer SHA-256:
  `8aee367408d1d09b7e9490bc9400050bc5b2012b92baad20e41fbed5fc643803`
- Transaction SHA-256:
  `5b948fe56bc4cf5d5be07631fc4b5418214faf0390ed9534fe9b7f53e5c8d838`
- Result: failed-consumed after Node B installation and before any Node A
  promotion or mutation
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35v.Og4PSy`
- Failed boundary: Node B was sampled in dual-stack `FAULT` with zero VIPs
  immediately after Keepalived reload, before the configured three successful
  health checks could establish stable `BACKUP`
- Secondary rejected evidence: Node A's split-release sampler treated the
  already-proven pre-promotion `/healthz` HTTP 404 as a continuity failure
- Recovery: Node B rollback and both node evidence readbacks returned 0; Node B
  returned to `BACKUP`; Node A was not promoted or mutated
- Status: terminal tag and immediate cleanup commit synchronized

## Archive boundary

- Tag: `caddy-pre-cleanup-history-2026-08-16`
- Commit: `3694303a5ac37c449cdda71260af0e3d97487eb3`
- Tag object: `82f3c6ececded19d044effe0fcda6534c22ad1e0`
- Scope: all executed Actions through 34m, the completed Action 33 reliability
  exercise through 33o, and the pre-cleanup Action 35 definition
- Remote state: tag and commit pushed before the production-only cleanup

Use the tag for authorization provenance, exact executed bytes, old manifests,
historical tests, workstation experiments, and the former full deployment
journal. Do not restore archived files to the current branch unless an operator
requests a historical reconstruction.

## Action 35 terminal archive

- Tag: `caddy-action35-terminal-2026-08-16`
- Commit: `b20e834f481944ea3eb5b9d945c256fd8d4fb96f`
- Tag object: `afef8b98bcac6781f9a408adb0ceb0e614c72fa6`
- Action: 35
- Result: failed-consumed before SSH or live mutation
- Scope: exact authorized runner, transaction, manifest, regression, failed
  workstation result, and repository-wide deployment-window framework
- Remote state: terminal tag, terminal commit, and immediate cleanup commit are
  synchronized as one clean-as-you-go checkpoint

## Action 35a terminal archive

- Tag: `caddy-action35a-terminal-2026-08-16`
- Commit: `f0d86ebba58531d2d40b6edb33d535ac18237d09`
- Tag object: `57d194d61e0a5c4c781efe25f1b216cf13aeb64d`
- Action: 35a
- Authorized outer SHA-256:
  `9ee5dca58b4169a326742da8c4e001aa2ecf31f36d65dd9cc1a376a8c996fa6e`
- Result: failed-consumed after Node A SSH preparation contact and before
  upload, transaction dispatch, or persistent mutation
- Exit status: 1
- Evidence: `/tmp/caddy-ssh-evidence/action35a`
- Failure: OpenSSH remote-shell reconstruction split a multiword
  `/bin/bash -c` command boundary
- Remote state: terminal tag and terminal-result commit pushed before the
  immediate production-branch cleanup

## Action 35b terminal archive

- Tag: `caddy-action35b-terminal-2026-08-16`
- Action: 35b
- Authorized outer SHA-256:
  `06bcab00cbd868c96a600499f4d6e8402686a95d62827c2d4d164f3c6db95d58`
- Result: failed-consumed after both bounded payload uploads and before release
  publication, transaction dispatch, service reload, or Keepalived mutation
- Exit status: 1
- Evidence: `/tmp/caddy-ssh-evidence/action35b`
- Retained payload SHA-256:
  `487cebeff7f13da4a301293f1a80ccc70ca4e7c38768136b9694294d9369a6fe`
- Failure: the unprivileged SSH identity could not traverse and resolve
  `/etc/caddy/current`; the successor must use streamed privileged resolution
- Commit: `ad7a5d1197c3cfb48f573eb7845f79c4af3c1156`
- Tag object: `fc5df66631bb0de7445c1e54c7bca0f0aff768a7`
- Status: terminal tag, terminal commit, and immediate cleanup commit are
  synchronized

## Action 35c terminal archive

- Tag: `caddy-action35c-terminal-2026-08-16`
- Commit: `07bf6eaf1bc90d023184c34048d2dc7f5cbbe113`
- Tag object: `ab007a3cb43991755a64e0a3966e6a49c440732d`
- Action: 35c
- Authorized outer SHA-256:
  `eb832297cff590075cc9f70e931cd38f7bbccf7dc594fa1995f59a85d89c525a`
- Transaction SHA-256:
  `a8a9a0210325a18a42d70afbe17395470a052a1beda713f989acbc4518529070`
- Result: failed-consumed after exact retained-upload disposition, dual-node
  upload, and privileged current-release capture, but before protocol-v2
  publication, transaction dispatch, service reload, or Keepalived mutation
- Exit status: 1
- Evidence: `/tmp/caddy-ssh-evidence/action35c`
- Original release on both nodes:
  `20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04`
- Cleanup: both retained Action 35b uploads and both Action 35c upload trees
  were removed successfully
- Retained exact candidate path on Node A: `/tmp/caddy-action35c-release`
- Failure: candidate Caddy validation did not load `/etc/default/caddy-ha`, so
  `NODE_FQDN` expanded empty and Caddy rejected an empty site label
- Availability evidence: two aggregate samples returned status 9; the direct
  successor must retain independent DNS IPv4, DNS IPv6, HTTPS IPv4, and HTTPS
  IPv6 statuses
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35f terminal archive

- Tag: `caddy-action35f-terminal-2026-08-17`
- Commit: `903ac8b0098a3f2abf4a048b185f074b72a28812`
- Tag object: `7266ae48ab21469cb04fb00e066db669aca6d7e0`
- Action: 35f
- Authorized outer SHA-256:
  `dd160b4a25c5a94dc7d5ae4c15fc1f7195ee8d95a6fd00df493606efdc683c3f`
- Transaction SHA-256:
  `0040150451305ffa43d72eb834d0228f376404123a0eb0cd05721af1e1b3819e`
- Result: failed-consumed during exact Node A retained-candidate validation,
  before upload, publication, transaction dispatch, service reload, or
  Keepalived mutation
- Exit status: 1
- Evidence: `/tmp/caddy-ssh-evidence/action35f`
- Original release on both nodes:
  `20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04`
- Retained exact candidate path on Node A: `/tmp/caddy-action35c-release`
- Observed candidate root identity: `root:caddy-tls:0550`
- Failure: Action 35f correctly derived mode `0550` from protocol v2 but
  incorrectly required owner `root:root`; the production reconciler owns
  immutable releases as `root:caddy-tls`
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35g terminal archive

- Tag: `caddy-action35g-terminal-2026-08-17`
- Action: 35g
- Authorized outer SHA-256:
  `2d22ccf81441b159dd99176efd14f7ea3188ca04439903c750ce0eada0eb0ba3`
- Transaction SHA-256:
  `77d7ff81181363bc642efc5b11425e2d343e6a4f2d7f47213fcf91077a9caac3`
- Result: failed-consumed after protocol-v2 publication and Node B release
  selection, before installation transaction dispatch, service reload, or
  Keepalived mutation
- Exit status: 1
- Evidence: `/tmp/caddy-ssh-evidence/action35g` and
  `/tmp/caddy-ssh-evidence/action35g-postcheck`
- Node A current release:
  `20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04`
- Node B current release:
  `20260817T160328Z-472d68b9-2bfb-40f1-8563-0754067182ca`
- Published release identity: Node A source, Action 32g parent,
  `root:caddy-tls:0550`, manifest JSON SHA-256
  `6049da00c0e7318c3fce98bc6cc78348ded5286998a346f00657df8c1d2a046d`,
  and payload-manifest SHA-256
  `ecb1a00827899bffc47d9e180b4f0a19a6daf0fc4beee9cb52898a9608102962`
- Ownership: Node A IPv4/IPv6 `MASTER` with all four VIPs; Node B IPv4/IPv6
  `BACKUP` with zero VIPs
- Initial postcheck incorrectly inspected `/var/lib/caddy-lsyncd/outgoing`.
  Corrected privileged inspection of the production protocol-v2 root proves
  Node A retains the exact finalized outbound candidate at
  `/var/lib/caddy-sync/outbound/20260817T160328Z-472d68b9-2bfb-40f1-8563-0754067182ca`
  as `caddy-sync:caddy-sync:0550`; Node B retains the identical selected
  immutable release. Matching incoming and quarantine paths are absent.
- Failure: the unprivileged Node B acceptance poll could not traverse
  `/etc/caddy/current`; the direct successor must use privileged streamed Bash
- Availability evidence: IPv4 DNS and HTTPS passed; WSL lacked an IPv6 route,
  so its IPv6 failures are retained but are not valid node-serving acceptance
- Commit: `e79db2b96ffde720e33cbcd79032b852a9989d69`
- Tag object: `8bed4ea2582be5693601c7c0f5370155abdbdc67`
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35d terminal archive

- Tag: `caddy-action35d-terminal-2026-08-16`
- Commit: `1a9e30b7088093ddf8444838bfca8705a404ed19`
- Tag object: `ffc6864994c62b7293919cff7a4fbefff17ae300`
- Action: 35d
- Authorized outer SHA-256:
  `5e131a1a1ec2e95e1bab6b7cc71475f8b4b9281d8789127516a0aa2b05878727`
- Transaction SHA-256:
  `f0e21e91c5dc0050559eba0bcce99289cf7b974672741204313cab8473c502b1`
- Result: failed-consumed after privileged current-release capture on both
  nodes and during exact Node A retained-candidate validation, before upload,
  publication, transaction dispatch, service reload, or Keepalived mutation
- Exit status: 1
- Evidence: `/tmp/caddy-ssh-evidence/action35d`
- Original release on both nodes:
  `20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04`
- Retained exact candidate path on Node A: `/tmp/caddy-action35c-release`
- Failure: Action 35c's real `cp -a current/. candidate/` producer preserved
  the source release root mode as `0755`; Action 35d incorrectly required
  `0700`, and its isolated test hid the mismatch by forcing `0700` after the
  copy
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35e terminal archive

- Tag: `caddy-action35e-terminal-2026-08-16`
- Commit: `e66e55e3c19b275bab1b604fd5b0fce34831599b`
- Tag object: `97c731ddb69f22be220f2101eaf1b689168065ee`
- Action: 35e
- Authorized outer SHA-256:
  `1ac3ae3dd8ac24938794f2ef9731fc534d0ce164f8b8ae78ee34ae8ac77c1ec1`
- Transaction SHA-256:
  `2c31fcabc2357bfc11e21f67ba8bac041f0a12c5eb29e110ac5c453e3ca5f903`
- Result: failed-consumed after privileged current-release capture on both
  nodes and during exact Node A retained-candidate validation, before upload,
  publication, transaction dispatch, service reload, or Keepalived mutation
- Exit status: 1
- Evidence: `/tmp/caddy-ssh-evidence/action35e`
- Original release on both nodes:
  `20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04`
- Retained exact candidate path on Node A: `/tmp/caddy-action35c-release`
- Observed candidate root mode: `0550`
- Failure: protocol-v2 declares and enforces final release directories as
  `0550`, but the Action 35e isolated baseline created its source release as
  `0755`; its real `cp -a` path therefore reproduced the wrong source mode
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35h terminal archive

- Tag: `caddy-action35h-terminal-2026-08-17`
- Commit: `1db3debe848fb2b1913e7fb592f2272403a7e18f`
- Tag object: `3c058c962181b5bc2e9294aa781e0699d27eb1be`
- Action: 35h
- Authorized outer SHA-256:
  `e921503c9a46d5a18777933cc3518b1868a982aa48e1004a14a6f782cff4b9a3`
- Transaction SHA-256:
  `f77dc10659ec610fb88a5ac1371e083ce3ac5e442ce2a334e17dabc75441986a`
- Result: failed-consumed during Node B current-production baseline identity
  validation, before candidate validation, backup creation, serving-health
  installation, Keepalived reload, Node A promotion, or Node A dispatch
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence/action35h`
- Recovered Node B evidence:
  `/tmp/caddy-ssh-evidence/action35h-evidence-recovery`
- Accepted baseline checks: exact split-release and protocol identities, all
  required active/enabled unit checks, baseline residue, and the deployed Node
  B Caddy-helper identity
- Failed assertion: `node_b_dns_health_helper` was the next production
  inventory row and was not accepted or recorded. Expected deployed SHA-256 was
  `7af57e70d80d32434e9cac717afa4af8d9e67c6c6ccd08d15ca9d7046d337b25`.
  The executed transaction did not emit the observed identity, which is an
  evidence-contract defect and must not be guessed.
- Availability: all 384 retained DNS and trusted-HTTPS IPv4/IPv6 samples from
  both nodes returned status 0
- Recovery: both upload trees were removed; Node B rollback and restoration
  handlers returned 0. The exact pre-35h split-release selection was restored.
  No serving-health or Keepalived configuration mutation occurred.
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35i terminal archive

- Tag: `caddy-action35i-terminal-2026-08-17`
- Commit: `b1931c917cddcddb369a23214de6b5bb1084c179`
- Tag object: `ba1d9abd52d78e3b506616bd2c8f8bd4a324ca67`
- Action: 35i
- Authorized outer SHA-256:
  `9de2ca4bc38a62e686c26947a07928943f755467b44cab7f1b44b6e4e220457e`
- Transaction SHA-256:
  `658a53d92cbccd50af9d1f906e513fe2e55ead60b79fb749c76ec4036e5924d0`
- Result: failed-consumed during Node B current-production DNS-helper identity
  validation, before candidate validation, backup creation, installation,
  Keepalived reload, publication, Node A promotion, or Node A transaction
  dispatch
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35i.qvBXIf`
- Expected deployed DNS-helper SHA-256:
  `7af57e70d80d32434e9cac717afa4af8d9e67c6c6ccd08d15ca9d7046d337b25`
- Observed on both nodes: `root:root:0755`, SHA-256
  `4972282ef0a0bed1bc2edec941125b2b3275812445039eede3a720099b95f33d`
- Desired repository SHA-256:
  `294afb4db26a3ccac454636efe091b872724e648c901b467142b31fae489e8aa`
- Recovery: both uploaded payload trees were removed successfully; no live
  mutation entrypoint ran, so rollback was neither required nor attempted
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35j terminal archive

- Tag: `caddy-action35j-terminal-2026-08-17`
- Commit: `7ed52a2773cb8195d9430686262d9bc02717d953`
- Tag object: `78b6b12c8f07c66885083f9c68fd8724eeb56c92`
- Action: 35j
- Authorized outer SHA-256:
  `aa354aa398c9b1495e48587c6b3bd670bf4ef495eb5fa5a72e930f9392043658`
- Transaction SHA-256:
  `c3ae04896a4c84bdd67d5e8c6de13b161ae09f2e44e99c709d0c7a2ec9e28b24`
- Result: failed-consumed during Node B current-production Unbound local-zone
  path validation, before candidate validation, backup creation, installation,
  Keepalived reload, publication, Node A promotion, or Node A dispatch
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35j.v2B8Mg`
- Accepted corrected DNS-helper identity:
  `4972282ef0a0bed1bc2edec941125b2b3275812445039eede3a720099b95f33d`
- Failed assertion: `artifact_node_b_unbound_local_zone_regular=false`; the
  inventory incorrectly used repository source name `pihole0-local-zone.conf`
  as the production target instead of `pihole-local-zone.conf`
- Current-contract correction: the ignored private repository source was later
  renamed to `pihole-local-zone.conf`, matching the production filename
- Recovery: Node A and Node B upload preparation, copy, acceptance, and exact
  disposition all returned 0; no mutation entrypoint ran, so rollback was not
  required or attempted
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35k terminal archive

- Tag: `caddy-action35k-terminal-2026-08-17`
- Commit: `19561672df210fc909a70c2b4d5492d621a512ba`
- Tag object: `78323892a9d40b20e199897b42c2baaac40aba06`
- Action: 35k
- Authorized outer SHA-256:
  `bfaab7f1d14cd0e2d718d8d95ea3acc3646d794a982b0a455512a526e08d43e9`
- Transaction SHA-256:
  `b5caa7691086c82d37b7c98d69fc0a0f13a50c882d43eaff841c65a545f664e9`
- Result: failed-consumed during Node B current-production Unbound local-zone
  identity validation, before candidate validation or any mutation entrypoint
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35k.gLE53y`
- Expected repository and deployed SHA-256:
  `f1f422d64a55a77af4d77a829ed3360341cf89f5f78c8e87419f01c3e593054d`
- Observed Node B SHA-256:
  `c3cf7224451a17e419cc4f2401d032aca435e6fe6e0ac61d37acb3e48b829dd9`
- Recovery: Node A and Node B upload preparation, copy, acceptance, and exact
  disposition all returned 0; no mutation entrypoint ran, so rollback was not
  required or attempted
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35l terminal archive

- Tag: `caddy-action35l-terminal-2026-08-17`
- Commit: `ad14e3e8f14a5794c6f9037e3505b3e7fa330920`
- Tag object: `bf0c3ac2fa83b17fdca25ae28961a2843592fef4`
- Action: 35l
- Authorized outer SHA-256:
  `452d9e6d2640ce6442fed74154c3a17b768e543c1da48789f585f06f18f47602`
- Transaction SHA-256:
  `967a63621b682dbb4aefb979f0d152f8437f17b4779daad68f33dd122516460d`
- Result: failed-consumed during Node B current-production tmpfiles artifact
  path validation, before candidate validation or any mutation entrypoint
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35l.LHr03k`
- Accepted local-zone SHA-256:
  `f1f422d64a55a77af4d77a829ed3360341cf89f5f78c8e87419f01c3e593054d`
- Failed assertion: `artifact_node_b_apprise_tmpfiles_regular=false`; the stale
  inventory target was `/usr/lib/tmpfiles.d/caddy-ha.conf`, while the installed
  file is `/etc/tmpfiles.d/caddy-ha.conf` as shown by operator readback
- Recovery: Node A and Node B upload preparation, copy, acceptance, and exact
  disposition all returned 0; no mutation entrypoint ran, so rollback was not
  required or attempted
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35m terminal archive

- Tag: `caddy-action35m-terminal-2026-08-17`
- Commit: `c3db8d17a2dadc1ee969049f44c18a1ab88aa8f1`
- Tag object: `f538ee163aa3ba53d916a8438d21b116d0f750eb`
- Action: 35m
- Authorized outer SHA-256:
  `337f0ef966da2dc15206952f73e47ca32531ccef734b8e789cfaf7aa5751e0de`
- Transaction SHA-256:
  `a845b7999db81b390778d3bbb21cd7082dd58bbcdcb6c32c5b352bb1c7295195`
- Result: failed-consumed during Node B current-production incoming inventory
  validation, before candidate validation or any mutation entrypoint
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35m.huceey`
- Failed assertion: `incoming_node_a_inventory_empty=false`
- Bounded completion readback: Node B
  `/tmp/caddy-action35m-completion-readback.tsv` contains the sole regular
  `action17p-node-a-to-node-b-bootstrap` directory with exact
  `caddy-sync:caddy-sync:0500` metadata
- Recovery: Node A and Node B upload preparation, copy, acceptance, and exact
  disposition all returned 0; no mutation entrypoint ran, so rollback was not
  required or attempted
- Status: terminal tag and terminal commit are recorded; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35n terminal archive

- Tag: `caddy-action35n-terminal-2026-08-17`
- Commit: `364349a7f416d0800b56eb5c500f0bad15759626`
- Tag object: `34d993ffe5c13d18629158a0accd1258c81140ac`
- Action: 35n
- Authorized outer SHA-256:
  `e0eac2c04da696c5545ad2439a4a59d295a0c38e389b75e035a97a935f5648bd`
- Transaction SHA-256:
  `1a3ef5c67aae2a57bcd20cce26c1fa8be0e97cc230fee3caef72c2cd2f2da2f8`
- Result: failed-consumed during exact Node B retained-entry inventory
  validation, before disposition or any other mutation entrypoint
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35n.XLa3wW`
- Failed assertion: `retained_file_inventory_exact=false`
- Bounded read-only completion inventory: Node B and workstation
  `/tmp/caddy-action35n-retained-inventory.txt`, SHA-256
  `190986c5ca8976ac50729dd5cb040eff4eea9426d17f7e9aa73c1c4c4b170b40`
- Finding: the exact entry is marker-free; `.finalize-request` and `.complete`
  are both absent, while pinned manifests and every payload hash validate
- Recovery: Node A and Node B upload preparation, copy, acceptance, evidence
  readback, and exact disposition all returned 0; no mutation entrypoint ran,
  so rollback was not required or attempted
- Status: terminal tag and terminal commit are recorded; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35o terminal archive

- Tag: `caddy-action35o-terminal-2026-08-17`
- Commit: `a99fd56522224591580ff29b21fca545b65a7674`
- Tag object: `3e0bd6df5b58987b57947868877cfe9f9f05bef2`
- Action: 35o
- Authorized outer SHA-256:
  `8e287b33412fe6e710feae7cb75b160b766ee9bd4b6e1fea18433f0b31cd7e28`
- Transaction SHA-256:
  `a87579d6a2d74992b8af60cbf3c952bf7356d6eb667667920ed2c49a3ab119d4`
- Result: failed-consumed during Node B pre-mutation inventory validation,
  before retained-entry disposition or any production mutation entrypoint
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35o.lHdOqM`
- Failed assertions: the role-inapplicable
  `/var/lib/caddy-sync/incoming/node-b` path was absent but passed through an
  empty-directory helper, and the nonempty quarantine was incorrectly required
  to be empty
- Bounded read-only completion inventory: Node B and workstation
  `/tmp/caddy-action35o-quarantine-inventory.txt`, SHA-256
  `320a6b0718233c69c939f9cd471006f284efcee060cbca7df6b53be2438af7e9`
- Finding: `incoming/node-b` is absent as required on Node B. The quarantine is
  `caddy-sync:caddy-sync:0750` and contains four exact, safe, payload-valid
  retained trees: Action 17p, Action 33k normalized, and two Action 30c Node B
  outbound releases. They were classified read-only and remain unchanged.
- Recovery: both node upload paths and readbacks were disposed successfully;
  no retained-entry disposition or production mutation ran, so rollback was
  not required or attempted
- Status: terminal tag and terminal commit are recorded; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35p terminal archive

- Tag: `caddy-action35p-terminal-2026-08-17`
- Commit: `2e9f757b43cc120bb6736b764aea0bbb5e55d136`
- Tag object: `adb7f88c7934959b3ce413e604c68a730e62786f`
- Action: 35p
- Authorized outer SHA-256:
  `70da8af9e01c5449607a3cada7579c12c933adde5fd0dd5a616f2b7912a646cb`
- Transaction SHA-256:
  `9a99c0f86090bea279f66a9fd2b2bc06f4d58cdaf9ee7dc6fb37860fc4ebbd1b`
- Result: failed-consumed during Node A current-production inventory
  validation, before retained-entry disposition or any production mutation
  entrypoint
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35p.RTAd6J`
- Failed assertion:
  `action_35_p_check_artifact_node_a_lighttpd_prepare_helper_regular=false`
- Finding: `/usr/local/libexec/prepare-lighttpd-config.sh` is absent on Node A;
  it is a repository migration tool rather than a required runtime artifact.
  Node B retains the exact legacy `root:root:0755` copy with SHA-256
  `ce9a78aa487ce55c6fbba553b238160687852361d81c9b37179e4def8f83166f`.
- Recovery: both node upload paths were disposed successfully; no quarantine
  disposition, candidate validation, installation, reload, or production
  mutation ran, so rollback was not required or attempted
- Status: terminal tag and commit are synchronized; consumed machinery and the
  stale runtime-inventory requirement were removed by the immediate cleanup
  commit

## Action 35q terminal archive

- Tag: `caddy-action35q-terminal-2026-08-17`
- Commit: `502c80d93b6672eac5459486247954c1de57d23b`
- Tag object: `3a64fc8fc314b59a588e205335aa12b5af9bf3ce`
- Action: 35q
- Authorized outer SHA-256:
  `042e8bb25c5b44c7e3f6f7c330bb128ba1b6be54128913ad9ea6f6526c5fb7f5`
- Transaction SHA-256:
  `d07bc39db0316a52e82fb3aa94bfc5354b8576b1e487527aca0ad5692597764a`
- Result: failed-consumed during Node A quarantine inventory validation,
  before retained-entry disposition or any production mutation entrypoint
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35q.rtMxPJ`
- Failed assertions: `action_35_q_check_quarantine_empty_inventory=false` and
  `action_35_q_check_quarantine_inventory_empty=false`
- Finding: Node A retains four exact top-level quarantine families: two Node B
  release revisions and two Action 30d outbound revisions. Node B preflight
  and every preceding Node A assertion passed.
- Recovery: Node A and Node B upload preparation, copy, acceptance, failure
  readback, and exact disposition all returned 0. No mutation entrypoint ran,
  so rollback was not required or attempted.
- Status: terminal tag and commit are synchronized; consumed machinery was
  removed by the immediate cleanup commit

## Action 35u terminal archive

- Tag: `caddy-action35u-terminal-2026-08-17`
- Commit: `62fc5a7f1cf2e9b6bb1b849d8596ed1fa0c4c9d3`
- Tag object: `e12e8b0c9f102bd8da8b817b842e7232f12df60f`
- Action: 35u
- Authorized outer SHA-256:
  `ba4a02e74e2c30c50ed899177e7f6ba756e901e4d3ce0d6d08b4b0442bda9659`
- Transaction SHA-256:
  `1d8d87f6c23f13f8cc362c7dfe82a7444d6885209e5c7c89a137f91a511d12fb`
- Result: accepted read-only HTTPS completion capture; no production mutation
- Exit status: 0
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35u.fPCHPN`
- Finding: Node A returned trusted-TLS HTTP 404 from `/healthz` over IPv4 and
  IPv6; Node B returned HTTP 204 over both. Both nodes had exact TCP/UDP
  listeners and active Caddy services.
- Deviation: the capture proxy retained but did not relay helper stdout, so
  Node B's helper-status failure was observer-induced. Independent direct curl
  evidence is authoritative and no additional diagnostic is required.
- Cleanup: every upload, capture, readback, and payload cleanup status was 0
- Status: terminal tag and commit are synchronized; consumed machinery was
  removed by the immediate cleanup commit

## Action 35t terminal archive

- Tag: `caddy-action35t-terminal-2026-08-17`
- Commit: `0ff0afcfb45bf7bcc60a2a32ca1a77f67e9a0be4`
- Tag object: `a4404b5918d480f457761006b43c8d60e4e9220a`
- Action: 35t
- Authorized outer SHA-256:
  `61e1a6c582b76e5c95efcfdeea3b5038043b8270df44c2eb644e985020818f81`
- Transaction SHA-256:
  `e3280a9eebedce710db1596d00ad2bc07d56d09d1d522ce20c11c2619bab6c83`
- Result: failed-consumed during Node A candidate real-identity Caddy
  validation, before disposition or any production mutation entrypoint
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35t.68VRV6`
- Failed assertion: `caddy_serving_health_check_ipv4_https=false`; Node A
  DNS identity and Unbound validation passed, and Node B candidate validation
  passed completely
- Recovery: both failure readbacks and exact upload dispositions returned 0;
  no mutation ran, so rollback was not required
- Status: terminal tag and commits are complete locally; remote synchronization
  is pending explicit approval. Consumed machinery was removed by the immediate
  cleanup commit.

## Action 35s terminal archive

- Tag: `caddy-action35s-terminal-2026-08-17`
- Commit: `61a05390f7eb1d63f3a5e1d2a6fed4217872443f`
- Tag object: `aff561a82bf4528748399462930ab8caccd72e0c`
- Action: 35s
- Authorized outer SHA-256:
  `52a7a1f6dc9cd6eeadef8aafe72a093c081634bb9a3f63a0595de39c4a2aeb4b`
- Transaction SHA-256:
  `100e584cdaed7a53bcdd44868f9061275af3226f80e0b338c465330b7a6b5574`
- Result: failed-consumed during Node B candidate Keepalived parser validation,
  before disposition or any production mutation entrypoint
- Exit status: 143
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35s.BCbKva`
- Failed boundary: the transaction incorrectly used the known-broken,
  unsupported `keepalived --config-test` interface on the installed Keepalived
  version. It terminated with empty stdout/stderr and retained status 143; this
  is not evidence that the candidate configuration was invalid.
- Recovery: both failure readbacks and exact upload dispositions completed;
  no mutation ran, so rollback was not required
- Status: terminal tag and commit are synchronized; consumed machinery was
  removed by the immediate cleanup commit

## Action 35r terminal archive

- Tag: `caddy-action35r-terminal-2026-08-17`
- Commit: `f264e43fd6176132104f7dd1f351c295e58700ec`
- Tag object: `7a716beff8b8ea1503c594f2d7ce685b090bdd3d`
- Action: 35r
- Authorized outer SHA-256:
  `347b9044acde81f2ec9d5dd5b4e86da108bf64c93c731654b78e67b98c201640`
- Transaction SHA-256:
  `7f4b7303eb6666b0651ee0110f609021298e0710825da3439f9cf88d2eb3e50c`
- Result: failed-consumed during Node A quarantine semantic validation,
  before disposition or any production mutation entrypoint
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35r.QXPhkL`
- Failed assertion:
  `action_35_r_check_node_a_quarantine_baseline_node_b_20260811t174240z_31d43261_5cd7_44ce_83e5_947927184d29_file_inventory_exact=false`
- Recovery: both failure readbacks and exact upload dispositions completed;
  no mutation ran, so rollback was not required
- Status: terminal tag and commit are synchronized; consumed machinery was
  removed by the immediate cleanup commit
