# Action 35: Coupled Serving-Health Failover Correction

## Status and scope

The serving-health architecture is approved. Action 35i is failed-consumed
before mutation and awaits its terminal archive boundary. No controlled failure
exercise or replacement successor is currently defined.

Every consumed implementation through Action 35h is preserved by the annotated
tags in `Caddy/HISTORY.md`; none is restored, modified, or rerun from the current
branch. The current branch contains only the production contract and future
work. The Caddy deployment stream is `terminal-pending`; the deployable
successor and causal-coverage registries are cleared.

Action 35g published one immutable serving-health Caddy release and Node B
selected it. Node A remains on the accepted Action 32g release and retains the
matching finalized outbound candidate. Action 35h validated that split-release
state and failed before serving-health mutation during Node B production
inventory validation. A bounded completion readback proved all preceding
baseline checks and all 384 node-local availability samples passed. The next
decision, `node_b_dns_health_helper`, retained its expected SHA-256 but no
observed SHA-256. Action 35h is failed-consumed.

Action 35i validated the split revision and the preceding Node B inventory rows,
then rejected the stale registered DNS-helper identity before any candidate
check or mutation. Bounded readback proved both nodes currently have exact
`root:root:0755` helper identity `4972282ef0a0bed1bc2edec941125b2b3275812445039eede3a720099b95f33d`.
The desired repository identity remains `294afb4db26a3ccac454636efe091b872724e648c901b467142b31fae489e8aa`.
The next direct installation successor must consume that exact baseline.

## Architecture decision

`PIHOLE_DUALSTACK` remains the sole ownership authority for:

- DNS IPv4 VIP `10.1.0.55`;
- DNS IPv6 VIP `fd36:5aa8:6971:1::55`;
- Caddy IPv4 VIP `10.1.0.56`;
- Caddy IPv6 VIP `fd36:5aa8:6971:1::56`.

All four VIPs move together. Sustained node-local DNS-serving or Caddy-serving
failure makes that node ineligible. This supersedes the older rule that Caddy
health could never move DNS: after coupling the VIPs, that rule could leave the
shared Caddy service down while a healthy redundant node remained idle.

Pi-hole/lighttpd web-backend failure is notification-only. It must not affect
VRRP eligibility or move otherwise healthy DNS and Caddy service.

## Serving dependency boundary

Failover-triggering node-local dependencies are:

- Keepalived, its tracked interface, and configured source addresses;
- `pihole-FTL.service` and exact Pi-hole DNS responses;
- `unbound.service` and exact direct Unbound responses;
- authoritative A and AAAA answers for the shared DNS name;
- `caddy.service`, its IPv4 and IPv6 listeners, and trusted-TLS `/healthz`.

The following remain observable but cannot influence VRRP eligibility:

- lighttpd, PHP, and the Pi-hole web backend;
- lsyncd, publication, finalization, and reconciliation;
- SSH, Apprise delivery, Keepalived DBus, monitoring, and timers;
- external internet, router, and public-recursive dependencies.

An invalid or expired served certificate is a Caddy serving failure. Failure of
the certificate-expiry worker alone is not.

## Health contracts

### DNS

The neutral DNS helper must:

1. Require Pi-hole FTL and Unbound active.
2. Query Pi-hole on port 53 through IPv4 and IPv6 loopback.
3. Query Unbound on port 5335 through IPv4 and IPv6 loopback.
4. Require exact A `10.1.0.55` and AAAA `fd36:5aa8:6971:1::55` answers.
5. Run independent queries concurrently and retain every command status and
   bounded safe observed answer.
6. Reject empty, duplicate, extra, malformed, cross-family, public, or
   node-specific answers.
7. Test only the authoritative local zone, never shared upstream availability.

The installed path remains `/etc/scripts/check-dns.sh`, owned by root and
executed as `pi`.

### Caddy

`Caddy/scripts/check-caddy-serving-health.sh` is the neutral current source and
installs as `/usr/local/libexec/check-caddy.sh`. It must:

1. Require `caddy.service` active.
2. Exercise exact node-specific physical IPv4 and IPv6 bindings.
3. Require trusted certificate chain, hostname, validity, and exact `/healthz`
   status without `--insecure` or redirect acceptance.
4. Verify expected local TCP and UDP listeners without requiring shared VIP
   ownership.
5. Complete within the Keepalived timeout and retain only bounded safe metadata.

The helper must not query lighttpd, PHP, FastCGI, or a Pi-hole application
route. Full `caddy validate` remains mandatory for release installation and
reload, but is too expensive for the periodic VRRP probe.

### Pi-hole web notification monitor

`caddy-pihole-web-health.service` is a static one-shot run as `pi`;
`caddy-pihole-web-health.timer` is enabled and active. Every 30 seconds the
worker checks lighttpd and the node-specific Pi-hole IPv4/IPv6 route.

The monitor persists a stable transition identity and pending state before
enqueue. It acknowledges the transition only after atomic local enqueue. A
crash after enqueue but before acknowledgement retries the same identity and
reconciles against queued, inflight, delivered, or dead-letter state. Failed
local enqueue remains pending for the next timer run. Network retry begins only
after a valid queue record exists. One failure and one recovery event are
emitted per episode, including across reboot. The monitor never delivers over
the network and never affects VRRP.

## Keepalived coupling

Both node configurations track independent unweighted `check_dns` and
`check_caddy` scripts at the `PIHOLE_DUALSTACK` group. The timing contract is:

- `interval 3`;
- `timeout 2`;
- `fall 2`;
- `rise 3`.

Two failed runs make the node ineligible in approximately six seconds. Three
successful runs establish recovery before the existing ten-second preemption
delay. Both configurations retain identical VRRP version, VRIDs, advertised
addresses, advertisement interval, unicast TTL 255, peer TTL bounds, and source
tracking. The Caddy helper retains its accepted
`keepalived_script:caddy-tls` execution context.

## Ownership and deployment ratchets

`homelab-dns` owns the two Keepalived configurations, the DNS helper, and their
runbook/tests. `homelab-server-configs` owns the Caddy helper, backend monitor,
systemd units, notification producer, production inventories, this plan, and
the dual-repository transaction.

No separate Caddy VRRP fragment or retired `CADDY_DUALSTACK` instance may be
introduced. The generic installer must not modify an existing production
deployment. The migration uses a bounded standby-first transaction and an
immutable protocol-v2 release.

## Actual split-release baseline

The next direct installation successor starts from the current production
state, not a historical fixture:

- Node A is preferred dual-stack `MASTER`, owns all four VIPs, and selects
  `20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04`.
- Node B is dual-stack `BACKUP`, owns no VIP, and selects
  `20260817T160328Z-472d68b9-2bfb-40f1-8563-0754067182ca`.
- Node A retains the exact `caddy-sync:caddy-sync:0550` finalized outbound
  candidate for Node B's `root:caddy-tls:0550` installed release.
- Matching incoming and quarantine entries are absent.
- Neither node has received the serving-health helper, Keepalived, or backend
  monitor mutation.

The successor independently inventories every current production artifact
with expected and observed identities. It reuses the existing Node A outbound
candidate and Node B installed release; it does not republish, seed state,
reconstruct a historical fixture, or copy Node B configuration to Node A.

## Direct installation successor contract

The next direct successor is one transaction with complete embedded acceptance:

1. Validate exact split releases, outbound/incoming/quarantine inventories,
   artifact identities, permissions, services, unit enablement, synchronization,
   durable notifications, VRRP ownership, and absence of unsafe residue.
2. Parser-test both candidate Keepalived configurations and execute the DNS and
   Caddy helpers under their real service identities.
3. Start continuous node-local DNS, trusted-HTTPS, shared Pi-hole UI, and
   node-specific Pi-hole UI IPv4/IPv6 probes. Capture pre-mutation journal
   cursors and bounded post-mutation service and notifier journals, then read
   all node `/tmp` evidence back to the workstation on success and failure.
4. Install and completely accept Node B's release, helpers, monitor, units, and
   Keepalived configuration before changing Node A.
5. Promote Node A's own validated outbound candidate through the installed
   local finalizer and reconciler. Require both nodes to select the same
   revision before installing Node A.
6. Install Node A sequentially. Never reload both nodes simultaneously. Permit
   only a bounded sampled mixed-policy interval.
7. Require Node A stable IPv4/IPv6 `MASTER` with all four VIPs, Node B stable
   `BACKUP` with none, healthy DNS/TLS/UI, healthy control plane, complete
   installed-candidate inventories, and independently verified zero incoming,
   outgoing, or quarantine residue.
8. On failure, reverse Node A then Node B and restore the exact split baseline.
   Return `125` only when mutation occurred and recovery cannot be proven.

Current-release inspection uses privileged streamed Bash. Service behavior is
still exercised under its intended unprivileged identity. Notification delivery
failure remains recorded and non-blocking. No separate diagnostic or post-action
acceptance is planned.

## Authorization-framework gate

Before the successor is defined, the neutral framework must enforce:

- complete coverage of every `production-artifacts.tsv` key;
- expected and observed values plus status for every baseline decision;
- a SHA-256 link from every decision to its bounded raw evidence;
- actual Node A and Node B evidence readback on success and failure;
- separate outer-runner and transaction evidence roots;
- rejection of missing, extra, symlinked, malformed, oversized, or mismatched
  decision and raw-evidence files;
- rejection of stdout markers, marker counting, and fixture-authored production
  results as authorization evidence;
- execution of the actual registered outer and transaction state machines in
  no-network production-path mode.

Isolated tests may construct input state and bounded command substitutes. The
substitutes must receive the exact commands produced by the entrypoints, and
assertions must derive from observable calls and filesystem effects. They may
not prewrite command, transport, journal, status, mutation, acceptance,
rollback, or success results.

Run the repository-policy and current-serving-health host profiles, one
network-disabled Debian 12 focused batch, the complete pre-commit suite, and
`deployable-successor-policy.sh --authorization-ready`. Authorization readiness
must reject while the registry is `none`; a future hash may be reported only
after one successor is defined and the causal evidence contract passes.

## Deferred controlled serving-failure exercise

The controlled exercise is not assigned an action number until installation is
accepted. It uses current services and no production fixtures. Each scenario
starts and ends with Node A owning all four VIPs and Node B owning none:

1. Stop Node A Caddy; require bounded failover and continuous shared service.
2. Stop Node A lighttpd; require no VIP movement, one backend-failure event, no
   duplicate during the outage, and one recovery event.
3. Stop Node A Pi-hole FTL; require DNS-health failover.
4. Stop Node A Unbound; require DNS-health failover.
5. Stop Node A Keepalived; require advertisement-loss failover.
6. Repeat Caddy, DNS, and notification-only lighttpd eligibility checks on Node
   B while Node A remains healthy.

One isolated failed sample must not move ownership. Each triggering scenario
requires two failed probes, healthy Node B before takeover, zero Node A VIPs
during failover, three successful recovery probes, preferred-owner failback,
exact restoration, cursor-based journals, and no scenario residue. Accepted
Action 33 already covers interface, SSH, reboot, and whole-node outage; those
tests are not repeated.

The plan closes only after installation and this controlled exercise prove the
coupled DNS/Caddy failover contract, notification-only backend behavior, stable
preferred ownership, exact releases, healthy synchronization and notification
systems, and zero unsafe residue.
