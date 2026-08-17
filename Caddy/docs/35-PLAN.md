# Action 35: Coupled Serving-Health Failover Correction

## Status

Action 35 was authorized and its outer runner was invoked, but it failed on the
workstation before SSH or mutation because its evidence parent directory did
not exist. No node state changed. Action 35 is failed-consumed and must not be
rerun or modified.

The audit after that failure also rejected Action 35's production-path tests:
they fabricated expected evidence and success markers instead of executing the
real outer and transaction state machines. Synthetic production results are
prohibited. Its first corrected successor, Action 35a, is also failed-consumed
and archived as recorded below. Action 35b is failed-consumed and no longer
registered. It uploaded the exact payload to both
nodes but failed before publication or transaction dispatch because the
unprivileged SSH identity could not resolve `/etc/caddy/current`. The direct
Action 35c is also failed-consumed. It reached pre-publication candidate
validation but did not load the required node environment, so Caddy rejected
the empty node-specific site label. Action 35d is failed-consumed after its
pre-upload residue check required a mode that the real Action 35c producer did
not create. Action 35e is also failed-consumed: its isolated baseline ignored
the protocol-v2 `0550` final-directory contract. Action 35f is failed-consumed
after it derived the correct mode but imposed the stale `root:root` ownership
prerequisite on a production `root:caddy-tls` release candidate. The direct
Action 35g accepted and removed that retained candidate, published one new
protocol-v2 release, and Node B selected it. Action 35g then failed because its
unprivileged Node B acceptance poll could not traverse `/etc/caddy/current`.
The direct recovery-and-installation successor is Action 35h; the controlled
failure exercise moves to Action 35i.

Action 35 corrects the coupled DNS/Caddy ownership model so a sustained
node-local DNS-serving or Caddy-serving failure causes the healthy peer to
acquire all four shared VIPs. Pi-hole web-backend failures remain local and
notification-only; they do not move otherwise healthy DNS and Caddy service.

Action 35a was authorized with outer SHA-256
`9ee5dca58b4169a326742da8c4e001aa2ecf31f36d65dd9cc1a376a8c996fa6e`
and exited `1` during Node A's upload-directory preparation. OpenSSH rebuilt
the multiword `/bin/bash -c` invocation through the remote shell, splitting
the intended command string: `set` printed the remote environment and
`install` received an empty path. Node A was contacted, but no upload,
publication, transaction dispatch, service operation, Keepalived operation, or
persistent mutation began. Evidence is retained at
`/tmp/caddy-ssh-evidence/action35a`. Action 35a is failed-consumed and must not
be rerun or modified; its terminal archive is
`caddy-action35a-terminal-2026-08-16`.

## Architecture decision

`PIHOLE_DUALSTACK` remains the sole ownership authority for:

- DNS IPv4 VIP `10.1.0.55`.
- DNS IPv6 VIP `fd36:5aa8:6971:1::55`.
- Caddy IPv4 VIP `10.1.0.56`.
- Caddy IPv6 VIP `fd36:5aa8:6971:1::56`.

All four VIPs continue to move together. The earlier rule prohibiting Caddy
health from moving DNS is superseded: it leaves the shared Caddy endpoint down
on the preferred node while a healthy redundant node remains idle. Under the
corrected contract, sustained failure of either the DNS serving path or the
Caddy process, listener, or trusted-TLS serving path places the local
synchronized group in `FAULT`.

This deliberately trades one short DNS ownership transition for restoration
of the shared Caddy service. A single failed sample is not a sustained failure
and must not move ownership. A lighttpd or Pi-hole web-backend failure is
reported through the durable notification queue so it can be repaired without
moving the DNS and Caddy VIPs.

## Current-production findings

The current Keepalived sources track only `check-dns`:

- Pi-hole FTL and Unbound service failures are detected.
- Exact IPv4 local-zone answers through Pi-hole and Unbound are detected.
- Keepalived process loss is handled by peer advertisement timeout.
- Interface and source-address loss are handled by Keepalived and
  `track_src_ip`.
- Caddy failures do not affect ownership, leaving a healthy redundant Caddy
  node unused; this is the availability defect Action 35 corrects.
- lighttpd failures intentionally do not affect ownership, but the current
  design lacks a specific edge-triggered failure and recovery notification.
- The Caddy helper checks Caddy activity and `https://localhost/`, but does not
  exercise trusted node-specific hostname paths or both address families.
- The DNS helper performs two sequential one-second queries on a one-second
  schedule, permitting overlap and skipped executions.
- The DNS helper does not validate AAAA answers or IPv6 loopback listeners.

## Serving dependency boundary

### Failover-triggering dependencies

The following are node-local serving dependencies. Sustained failure of any
one must make that node ineligible to own `PIHOLE_DUALSTACK`:

- Keepalived VRRP process, tracked interface, and configured source addresses.
- `pihole-FTL.service` and functional Pi-hole DNS responses.
- `unbound.service` and functional direct Unbound responses.
- Correct authoritative A and AAAA answers for the shared DNS name.
- `caddy.service` and functional IPv4 and IPv6 HTTPS listeners.
- Trusted TLS and hostname validation on the node-specific Caddy route.

### Non-triggering control-plane dependencies

The following remain observable and alerting inputs, but must not influence
VRRP eligibility because they do not prevent the node from serving its current
accepted release:

- lsyncd, protocol-v2 publication, finalization, and reconciliation.
- SSH.
- Apprise enqueueing, delivery, retry, and dead-letter processing.
- Keepalived DBus.
- Certificate-expiry and synchronization-health timers.
- Monitoring and metrics collection.
- `lighttpd.service`, PHP, and the Pi-hole web backend. Their failure requires
  a specific durable failure notification, not a VRRP ownership transition.
- External internet, router, public-recursive, or other shared dependencies
  whose failure could place both nodes into `FAULT` without improving service.

An actually invalid or expired served certificate is a serving failure and is
detected by the trusted HTTPS probe. Failure of the certificate-expiry worker
alone is not.

## Corrected health contracts

### DNS health helper

Replace the current sequential helper contract with one bounded, fail-closed
helper that:

1. Requires `pihole-FTL.service` and `unbound.service` active.
2. Queries Pi-hole on port 53 through IPv4 and IPv6 loopback.
3. Queries Unbound on port 5335 through IPv4 and IPv6 loopback.
4. Requires the exact A answer `10.1.0.55` and exact AAAA answer
   `fd36:5aa8:6971:1::55` from both resolver paths.
5. Runs independent queries concurrently, captures every status and safe
   observed answer, and fails if a query command itself fails.
6. Rejects empty, duplicate, extra, malformed, cross-family, public, or
   node-specific answers.
7. Uses only the authoritative local zone; it does not turn shared internet or
   upstream-recursive availability into a VRRP dependency.

The installed destination remains `/etc/scripts/check-dns.sh`, owned by root
and executed as the unprivileged `pi` identity.

### Caddy serving-health helper

Introduce the neutral current source
`Caddy/scripts/check-caddy-serving-health.sh` and install it as
`/usr/local/libexec/check-caddy.sh`. The archived predecessor is not part of
the current behavioral contract. The neutral helper must:

1. Require `caddy.service` active.
2. Require bounded IPv4 and IPv6 loopback Caddy health responses.
3. Provide a backend-independent `/healthz` response on each node-specific
   production site before any reverse-proxy handler.
4. Exercise that node-specific health route through exact physical IPv4 and
   IPv6 `curl --resolve` bindings.
5. Require trusted certificate-chain, hostname, and validity acceptance; the
   production probes must not use `--insecure`.
6. Require the exact bounded health status and reject redirects, backend
   responses, cross-host responses, or unexpected response content.
7. Verify the expected local Caddy TCP and UDP listener inventory without
   requiring the standby node to own a shared VIP.
8. Capture command statuses and bounded safe response metadata without
   credentials, cookies, response bodies, or private certificate material.

The helper must not query lighttpd, FastCGI, PHP, or a Pi-hole application
route. Those components do not decide VRRP eligibility.

Do not run full `caddy validate` in the periodic VRRP helper. Production
evidence showed that validation can exceed the Keepalived execution boundary.
Full configuration validation remains mandatory before installation, release
promotion, and reload.

### Pi-hole web-backend notification monitor

Add a separate systemd timer and static one-shot worker for node-local Pi-hole
web-backend health. This monitor is not referenced by Keepalived and is not an
input to Caddy, lsyncd, reconciliation, DNS, or VRRP acceptance.

Every 30 seconds, the worker must:

1. Check `lighttpd.service` independently from Caddy health.
2. Exercise the node-specific Pi-hole interface through exact physical IPv4
   and IPv6 `curl --resolve` bindings.
3. Accept only the bounded same-origin redirect contract and safe terminal
   login response already established for Pi-hole v5.
4. Classify failures narrowly as service, IPv4 path, IPv6 path, redirect, or
   terminal-response failure without retaining credentials, cookies, or body
   content.
5. Persist its last accepted state atomically beneath a restrictive
   service-owned `/var/lib` directory and keep runtime-only captures beneath
   `/run`.
6. Enqueue exactly one durable Apprise event on a healthy-to-failed transition
   and exactly one recovery event on a failed-to-healthy transition.
7. Suppress duplicate events during a continuing failure, including across a
   reboot, while retaining bounded journald evidence for every check.

The monitor uses the bounded durable-queue source `pihole-web`. Before the
first enqueue attempt for a new failure episode, it must atomically persist a
stable producer-supplied transition identity and a pending-notification state.
It must pass that stable identity to the enqueue helper so the resulting queue
event identity remains constant across time windows, retries, crashes, and
reboots. After atomic enqueue succeeds, it atomically records the transition as
enqueued. A crash after enqueue but before acknowledgement therefore retries
the same queue identity and reconciles against the pending, inflight,
dead-letter, or delivered record rather than creating a duplicate.

If local enqueue fails, the monitor retains the pending transition and retries
local enqueue on its next timer run. The network delivery worker owns retry,
backoff, and dead-letter processing only after a valid queue record exists. On
recovery, any still-pending failure notification is enqueued first, followed by
one recovery notification with its own stable identity; successful recovery
acknowledgement closes the episode.

If Caddy itself is unavailable, the monitor must not misclassify the resulting
route failure as a Pi-hole backend failure; the Caddy serving-health path owns
that event and failover. Local enqueue failure remains non-blocking and retains
pending producer state. The monitor never performs network delivery.

### Keepalived tracking

Both node configurations must define independent unweighted scripts and track
both at the synchronized-group level:

```text
vrrp_sync_group PIHOLE_DUALSTACK {
    group {
        PIHOLE_IPV4
        PIHOLE_IPV6
    }

    track_script {
        check_dns
        check_caddy
    }
}
```

The candidate timing contract is:

- `interval 3`
- `timeout 2`
- `fall 2`
- `rise 3`

Independent probes must finish within the two-second ceiling. Two consecutive
failed runs make the node ineligible in approximately six seconds. Three
successful runs establish recovery before the existing ten-second preferred
owner `preempt_delay` applies. The implementation must regression-test the
actual worst-case helper path and reject a runtime that can overlap the next
scheduled invocation.

The Caddy helper must retain its accepted `keepalived_script:caddy-tls`
execution context. Both Keepalived configurations must preserve identical VRRP
versions, VRIDs, advertised address counts, excluded Caddy VIPs, advertisement
intervals, unicast TTL 255, peer TTL bounds, and source tracking.

## Cross-repository ownership

`homelab-dns` owns:

- `Keepalived/configs/keepalived-pihole0.conf`.
- `Keepalived/configs/keepalived-pihole00.conf`.
- `Keepalived/scripts/dns-check.sh`.
- The Keepalived runbook and DNS-helper tests.

`homelab-server-configs` owns:

- The production Caddy serving-health helper.
- The Pi-hole web-backend monitor, timer, persistent state contract, and
  durable-notification producer.
- Caddy helper tests and production-artifact identity.
- This plan and the current-state Caddy governing plan.
- The dual-repository deployment transaction and workstation evidence.

No separate Caddy VRRP fragment may be introduced. The retired
`CADDY_IPV4`, `CADDY_IPV6`, and `CADDY_DUALSTACK` instances remain obsolete.

The monitor units are named `caddy-pihole-web-health.service` and
`caddy-pihole-web-health.timer`. The service remains static, runs as `pi`, and
uses protected persistent state beneath `/var/lib` plus runtime state beneath
`/run`. It receives only the local IPv4/IPv6 and queue access required for its
checks. The timer is enabled and active. No protected-backend service belongs
to this design.

## Repository implementation gate

Repository work requires no live authorization. It must:

1. Implement the corrected DNS and Caddy helpers and the notification-only
   Pi-hole web-backend monitor in their authoritative repositories.
2. Update both current Keepalived configurations to track both helpers.
3. Update the governing plan to supersede every current statement that Caddy
   health must never move DNS.
4. Update runbooks, production inventories, lifecycle registries, accepted
   source identities, and focused-profile selection without changing accepted
   deployed identities before live acceptance.
5. Add neutral current-production regressions for exact helper behavior,
   timeout and concurrency boundaries, execution identity, both address
   families, Keepalived group wiring, equal advertised-address counts, retained
   TTL controls, and the notification monitor's transition and deduplication
   state machine.
6. Exercise the real helper entry points with accepting and rejecting service,
   DNS, TLS, and listener cases. Independently exercise backend failure,
   repeated failure, reboot-retained failure, recovery, and enqueue-failure
   cases without permitting the monitor to affect VRRP.
7. Add a `current-serving-health` focused profile that executes the neutral
   production entry points and covers DNS A/AAAA through both loopback
   families, trusted Caddy IPv4/IPv6 `/healthz`, the two-second worst-case
   ceiling, `interval 3`, `timeout 2`, `fall 2`, `rise 3`, exact
   `PIHOLE_DUALSTACK` wiring, backend transition and reboot deduplication,
   enqueue failure, and proof that lighttpd failure cannot affect VRRP.
8. Run current focused host validation and one network-disabled Debian 12
   focused batch.

The repository gate for the direct successor stops after reporting its exact
outer SHA-256. No node contact occurs during definition. The consumed Action 35 gate
is not reusable: its tests were invalidated because they fabricated production
results, and its execution failed before SSH or mutation. Its exact files and
authorization provenance are retained by the terminal tag recorded in
`Caddy/HISTORY.md`.

## Action 35c: failed-consumed installation transaction

Action 35c's production-path validation executes the generated SSH transport,
upload, transaction, publisher, acceptance, rollback, and cleanup boundaries.
Remote multi-command Bash is streamed on standard input from `cd /`; remote
Bash `-c` is prohibited. Actions 35a and 35b are consumed only as failure
provenance and are never invoked. Before creating a new upload, Action 35c
must accept an absent Action 35b upload or validate and remove the exact
retained upload matching its recorded payload SHA-256. Partial, extra,
malformed, symlinked, or unsafe retained state is rejected. Current-release
resolution is performed only through streamed privileged Bash.

Live execution requires separate authorization of the definition-complete
outer runner. One transaction must install and accept the corrected health
contract standby first.

### Baseline

- Consume accepted Action 34m without rerunning it.
- Require Node A stable IPv4/IPv6 `MASTER` with all four VIPs.
- Require Node B stable IPv4/IPv6 `BACKUP` with zero shared VIPs.
- Require exact accepted Keepalived, DNS helper, Caddy helper, service,
  release, synchronization, and durable-notification state.
- Require the existing Pi-hole web backend healthy before mutation while
  treating its health as a baseline condition rather than a VRRP input.
- Capture journal cursors and complete original file identities, modes,
  ownership, unit state, VRRP state, and VIP ownership.
- Require both candidate helpers to pass on both nodes before mutation.

### Node B

1. Construct one immutable, validated Node A protocol-v2 release candidate
   containing the backend-independent Caddy health route.
2. Publish that candidate through the normal A-to-B protocol-v2 path and
   require Node B to finalize, reconcile, activate, and independently accept
   the exact revision while Node A remains on the original release.
3. Validate the remaining candidate payload and staged Keepalived
   configuration.
4. Create and verify protected rollback copies.
5. Atomically install the DNS helper, Caddy helper, backend-monitor helper and
   units, and Node B Keepalived configuration. Do not edit Node B's selected
   release outside the accepted protocol-v2 transaction.
6. Perform one bounded Keepalived reload.
7. Permit only the explicitly bounded mixed-policy transition while Node A
   remains the stable owner.
8. Require both tracked scripts healthy, the backend monitor and timer
   accepted, Node B stable `BACKUP`, zero shared VIPs, unchanged
   release/service health, and no parser, script-security, timeout, overlap, or
   new transport failure.

Node A must not be mutated unless Node B is fully eligible to take ownership.

### Node A

1. Repeat candidate validation and protected backup creation.
2. Promote the exact revision already accepted on Node B; do not construct a
   second release or directly edit the selected release.
3. Atomically install the DNS helper, Caddy helper, backend-monitor helper and
   units, and Node A Keepalived configuration.
4. Perform one bounded Keepalived reload, never simultaneous with Node B.
5. Treat a brief Node B ownership transition during reload as observable
   transition state rather than immediate failure.
6. Require bounded convergence to Node A stable dual-stack `MASTER` with all
   four VIPs and Node B stable dual-stack `BACKUP` with zero VIPs.

The generic `install-caddy-ha.sh` Caddy component is prohibited during this
live migration. Action 35c must regression-test that the generic installer
fails closed when `/etc/caddy/current` exists. Rollback restores both original
release selections through the transactional release boundary before restoring
the remaining files in reverse node order.

### Action 35c acceptance

- Both production helpers and Keepalived configurations match exact candidate
  identities, owners, groups, and modes.
- Both backend-monitor workers, timers, persistent-state paths, and durable
  notification boundaries match their exact candidate contracts.
- Both helpers pass repeatedly without overlap or timeout.
- DNS A/AAAA, trusted HTTPS, shared Pi-hole UI, and node-specific interfaces
  remain continuously available.
- No simultaneous, partial, prolonged, or incorrect VIP ownership occurs.
- Caddy, lighttpd, Pi-hole FTL, Unbound, Keepalived, managed lsyncd,
  reconciliation, timers, and durable notification remain healthy.
- Notification delivery failures remain non-blocking.
- No transaction residue remains.

On failure, restore Node A and then Node B in reverse mutation order, reload
Keepalived sequentially, and prove the exact accepted Action 34m state. Return
status `125` only when mutation occurred and recovery cannot be proven.

Action 35c was authorized with outer SHA-256
`eb832297cff590075cc9f70e931cd38f7bbccf7dc594fa1995f59a85d89c525a`
and exited `1` before publication or a live serving mutation. Both nodes
remained on release
`20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04`. Exact evidence is
retained at `/tmp/caddy-ssh-evidence/action35c`. The exact Node A candidate
path `/tmp/caddy-action35c-release` remains for successor disposition.

## Action 35d: direct corrected installation successor

Action 35d consumes Action 35c without rerunning it. Before creating a new
candidate, it must validate and remove only the exact retained
`/tmp/caddy-action35c-release` derived from the accepted release and Action 35c
candidate route. Candidate validation must load and validate the exact
root-owned `/etc/default/caddy-ha` environment. Debian production-path coverage
must invoke the real Caddy parser rather than a success-only substitute.

The continuous availability sampler must retain independent DNS IPv4, DNS
IPv6, HTTPS IPv4, and HTTPS IPv6 statuses and safe classified evidence. Action
35d then resumes the unchanged standby-first transaction and complete embedded
acceptance described above.

Action 35d was authorized with outer SHA-256
`5e131a1a1ec2e95e1bab6b7cc71475f8b4b9281d8789127516a0aa2b05878727`
and exited `1` during exact Node A retained-candidate validation, before upload,
publication, transaction dispatch, service reload, or Keepalived mutation.
Both nodes remained on release
`20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04`. Evidence is retained
at `/tmp/caddy-ssh-evidence/action35d`. The Action 35c candidate remains at
`/tmp/caddy-action35c-release`. Its exact producer applies `cp -a` to the
accepted release and yields a root-owned `0755` candidate root; the Action 35d
test incorrectly forced `0700` after that copy.

## Action 35e: direct retained-mode-corrected installation successor

Action 35e consumes Action 35d without rerunning it. It must reproduce the
actual Action 35c candidate producer in both host and Debian production-path
coverage, accept only the exact root-owned, non-symlink `0755` candidate with
the known route identity and otherwise exact accepted-release semantics, and
remove only that validated path. It retains Action 35d's environment-loaded
real Caddy parser, independent four-family availability evidence, standby-first
transaction, embedded acceptance, reverse rollback, and status-125 controls.

Action 35e was authorized with outer SHA-256
`1ac3ae3dd8ac24938794f2ef9731fc534d0ce164f8b8ae78ee34ae8ac77c1ec1`
and exited `1` during exact Node A retained-candidate validation, before upload,
publication, transaction dispatch, service reload, or Keepalived mutation.
Both nodes remained on release
`20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04`. Evidence is retained
at `/tmp/caddy-ssh-evidence/action35e`. The observed candidate root mode was
`0550`, which is the current protocol-v2 final-directory contract enforced by
the publisher and reconciler. Action 35e's fixture incorrectly created the
accepted source release as `0755`.

## Action 35f: direct protocol-mode-corrected installation successor

Action 35f consumes Action 35e without rerunning it. It must derive its
accepted-release directory and candidate expectations directly from
`synchronization-protocol-v2.yaml` and execute the real Action 35c `cp -a`
producer against an exact `0550` source in both host and Debian coverage. It
may remove only the exact root-owned, non-symlink `0550` retained candidate
after every semantic, path, inventory, and hash check succeeds. It otherwise
retains the unchanged environment-loaded parser, standby-first transaction,
embedded acceptance, reverse rollback, and status-125 controls.

Action 35f was authorized with outer SHA-256
`dd160b4a25c5a94dc7d5ae4c15fc1f7195ee8d95a6fd00df493606efdc683c3f`
and exited `1` during exact Node A retained-candidate validation. It captured
the original release on both nodes and observed the exact retained candidate
as `root:caddy-tls:0550`. Its check correctly derived mode `0550` from the
protocol-v2 manifest but incorrectly required owner `root:root`. No upload,
publication, transaction dispatch, service reload, or Keepalived mutation
began. Evidence is retained at `/tmp/caddy-ssh-evidence/action35f`.

## Action 35g: direct production-ownership-corrected installation successor

Action 35g consumes Action 35f without rerunning it. It must derive both the
directory mode and immutable-release ownership from the current production
reconciler and protocol-v2 contract, accept only the exact non-symlink
`root:caddy-tls:0550` retained candidate after every semantic, path, inventory,
and hash check succeeds, remove only that validated path, and resume the
unchanged standby-first installation. Its host and Debian production-path
coverage must reproduce the real reconciler-owned accepted release and the
real Action 35c `cp -a` producer path.

Action 35g was authorized with outer SHA-256
`2d22ccf81441b159dd99176efd14f7ea3188ca04439903c750ce0eada0eb0ba3`
and exited `1` after publication. It validated and removed the exact retained
Node A candidate, uploaded both transaction payloads, published revision
`20260817T160328Z-472d68b9-2bfb-40f1-8563-0754067182ca`, and Node B reconciled
and selected that revision. Its acceptance poll then repeatedly invoked `jq`
as the unprivileged SSH identity against
`/etc/caddy/current/release-manifest.json` and received `Permission denied`.
The installation transaction never ran. Exact upload and candidate cleanup
succeeded. Read-only post-failure capture proves Node A remains preferred
IPv4/IPv6 `MASTER` with all four VIPs on the accepted Action 32g release, Node
B remains IPv4/IPv6 `BACKUP` with zero VIPs on the exact Action 35g release,
both Caddy and Keepalived services are active, and there is no exact Action 35g
outgoing, incoming, or quarantine residue. Evidence is retained under
`/tmp/caddy-ssh-evidence/action35g` and
`/tmp/caddy-ssh-evidence/action35g-postcheck`.

The workstation availability monitor also proved IPv4 DNS and HTTPS
continuity but could not reach either IPv6 VIP from WSL. Those failures are
workstation-route failures, not node serving-path evidence, and must not be
silently counted as successful IPv6 acceptance. Action 35h must obtain its
continuous IPv6 evidence from a current network path that can actually reach
the ULA VIPs while retaining the workstation files and exact statuses.

## Action 35h: direct post-publication recovery-and-installation successor

Action 35h consumes Action 35g without rerunning it. Before installation, it
must validate the exact split-release baseline through privileged streamed
Bash: Node A on
`20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04` and Node B on
`20260817T160328Z-472d68b9-2bfb-40f1-8563-0754067182ca`. It must validate the
new Node B release's exact revision, Node A source, Action 32g parent, installed
path, `root:caddy-tls:0550` identity, file inventory, per-file hashes, and
normalized manifest identities. It must reject any outgoing, incoming,
quarantine, release, ownership, or service drift.

The Node B current-release acceptance poll must run through privileged streamed
Bash, and host plus Debian production-path coverage must reproduce the real
`pi` traversal boundary around `/etc/caddy/current`. After that correction,
Action 35h resumes the same standby-first installation using the already
validated identical release on Node B; it must not republish or seed production
state. It installs and accepts Node B completely, promotes the identical
revision on Node A through the transaction's defined immutable-release path,
installs Node A, converges ownership, and retains the existing embedded
acceptance, reverse rollback, and status-125 controls.

## Action 35i: controlled serving-failure exercise

Action 35i is separately authorized only after Action 35h is accepted. It does
not reinstall Action 35h and does not create production fixtures. It exercises
real current services and health paths while continuous one-second DNS,
trusted HTTPS, and shared Pi-hole UI probes retain availability evidence. The
planned lighttpd outage is the sole interval in which shared Pi-hole UI failure
is expected; DNS and Caddy-only health must remain available throughout it.

Each scenario starts and ends at Node A preferred `MASTER` with all four VIPs
and Node B `BACKUP` with none:

1. Stop Node A Caddy and require Caddy health failure, Node A `FAULT`, Node B
   takeover, and shared service continuity.
2. Stop Node A lighttpd and require Node A to remain stable `MASTER`, Node B to
   remain `BACKUP`, all four VIPs to remain on Node A, DNS and Caddy-only
   health to remain available, and the shared Pi-hole UI to become unavailable.
   Require exactly one specific backend-failure event, no duplicate event while
   the outage continues, and exactly one recovery event after restoration.
3. Stop Node A Pi-hole FTL and require the DNS probe to cause takeover.
4. Stop Node A Unbound and require its direct DNS probe to cause takeover.
5. Stop Node A Keepalived and require advertisement-loss takeover without
   depending on a local health script.

For each ownership-triggering scenario:

- Capture a journal cursor first.
- Require two bounded consecutive failed health runs where applicable.
- Reject transition on one isolated failed sample.
- Require Node B healthy before and throughout takeover.
- Require Node A to own zero shared VIPs during failover.
- Restore only the intentionally stopped component.
- Require three successful health runs, the existing preemption delay, and
  stable preferred-owner failback.
- Reset only scenario-owned failed unit state.
- Retain notifier enqueue/delivery evidence without using delivery as an
  acceptance input.
- Remove only exact scenario-owned transient state.

The lighttpd scenario uses the same evidence, cleanup, and restoration
boundaries but explicitly rejects any VRRP transition or VIP movement. It must
prove that the notification record is specific to the Pi-hole backend and that
notification delivery status remains irrelevant to service and ownership
acceptance.

Role symmetry is proven by temporarily stopping the Node B Caddy serving path
and then its DNS serving path while Node A remains healthy. Node B must become
or remain ineligible, own zero VIPs, and recover to stable `BACKUP` without
moving ownership. A Node B lighttpd outage must instead retain eligibility and
produce the same single failure and recovery notification contract without VIP
movement. Interface removal, power loss, reboot, and SSH outage are not
repeated; accepted Action 33 already covers node outage and reboot behavior.

## Evidence and recovery contract

- Store node-local bounded evidence beneath `/tmp/caddy-action35f`.
- Store every SSH stdout, stderr, and status independently beneath
  `/tmp/caddy-ssh-evidence/action35f` on the workstation.
- Capture journal evidence with pre-command cursors and `--after-cursor`.
- Record helper duration, exit status, safe answers/response metadata, VRRP
  transitions, VIP ownership, service state, notification events, and rollback
  results.
- Reject binary, control-character, secret-bearing, malformed, unbounded, or
  unsafe captured output.
- Preserve all evidence through the final decision.
- Automatically recover the active scenario before proceeding.
- Stop immediately with status `125` if service restoration, VIP convergence,
  or exact cleanup cannot be proven.

## Corrected-successor validation ratchet

The corrected installation successor must preserve Action 35 unchanged and
replace its invalid validation boundary. Its no-network tests may construct
isolated input state and controlled external-command substitutes, but they must
execute the actual registered outer runner and transaction entrypoints.

The tests must derive results from observable calls and filesystem effects.
They must not pre-create expected upload events, remote commands, statuses,
mutation counts, journal evidence, rollback evidence, or success results. A
summary label is permitted only after independent assertions prove that the
real entrypoint produced the underlying evidence.

The outer path must exercise real payload construction, evidence-parent
creation, remote-path generation, upload preparation and disposition, exact
remote command construction, transaction dispatch, cleanup, and the
pre-mutation failure trap. The transaction path must exercise its actual
baseline, parser, identity, ordering, mutation-boundary, convergence,
acceptance, rollback, and residue branches against isolated current-production
state. Authorization readiness must fail if either registered path can report
success without those paths running.

## Final acceptance

The controlled failure exercise closes the plan only when:

- Every DNS and Caddy serving-path failure produces the expected bounded
  failover behavior.
- Each lighttpd/Pi-hole web-backend failure produces exactly one specific
  failure notification and one recovery notification without a VRRP
  transition.
- Node B never takes ownership while its own serving path is unhealthy.
- Node A returns to stable IPv4/IPv6 `MASTER` with all four VIPs.
- Node B returns to stable IPv4/IPv6 `BACKUP` with zero VIPs.
- Exact accepted releases and all non-serving control-plane services remain
  unchanged and healthy.
- DNS A/AAAA, trusted TLS, shared and node-specific Pi-hole interfaces pass.
- No unexpected quarantine, failed worker, transaction residue, simultaneous
  ownership, or unexplained restart increase remains.
- Production inventories and the governing plan are updated from accepted live
  evidence, and the deployable-successor registry returns to `none`.

No separate diagnostic or read-only post-action is planned. The corrected
installation successor must embed complete installation acceptance. The
controlled failure exercise follows only after that installation is accepted.
