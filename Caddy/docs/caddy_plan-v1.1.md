# Caddy HA governing plan

Version: 1.1 current-state edition
Archive boundary: `caddy-pre-cleanup-history-2026-08-16`
Current status: core deployment accepted; Action 35aa archived and cleaned after successful Node B rollback; the Caddy deployment stream is clean; installed Keepalived parser modes are prohibited

Action 35v completely accepted the candidate on Node B, then observed Node B
in dual-stack `FAULT` with zero VIPs less than two seconds after reloading
Keepalived. The transaction incorrectly required immediate `BACKUP` before the
configured `interval 3`, `rise 3` health initialization could converge. It
also sampled Node A's known pre-promotion `/healthz` 404 as a continuity
failure. Node B rollback completed, Node B returned to `BACKUP`, and Node A
was not promoted or mutated. Action 35v is consumed and must not be rerun.

Action 35x initialized healthy DNS and Proxy snapshots before the Node B
Keepalived reload, then observed dual-stack `Fault` with zero VIPs throughout
all 24 bounded ownership samples. All retained service-continuity probes passed.
The candidate helper was accepted through `runuser`, which initializes
supplementary groups, but the Keepalived `check-caddy` declaration specified
only `user keepalived_script` while its protected environment is
`root:caddy-tls:0640`. Node B rollback succeeded and returned it to `BACKUP`;
Node A was not promoted or mutated. Action 35x is consumed and must not be
rerun.

Action 35y installed Node B and successfully executed the Caddy helper as
`keepalived_script:caddy-tls`, then rejected the generated Proxy status file
because acceptance still expected its superseded
`keepalived_script:keepalived_script:0644` metadata. The helper's atomic status
file correctly inherited the explicit `caddy-tls` primary group. All retained
service-continuity probes passed. Node B rollback succeeded and returned it to
`BACKUP`; Node A was not promoted or mutated. Action 35y is consumed and must
not be rerun.

Action 35z corrected and accepted the Proxy status-file metadata, installed
and accepted Node B, and then observed both VRRP instances in `Fault` with zero
VIPs for all 24 bounded samples. The retained operator journal proves that the
real Keepalived schedule reported `check-caddy` status 1 immediately and an
intermittent `check-dns` status 1 three seconds later. Direct identity checks
and every continuity probe passed. The action's journal selector omitted those
decisive `Keepalived_vrrp` records. Node B rollback succeeded and returned it
to `BACKUP`; Node A was not promoted or mutated. Action 35z is consumed and
must not be rerun.

Action 35aa installed Node B and obtained five successful transaction-launched
DNS and Caddy cycles. Keepalived's own DNS execution entered FAULT ten seconds
before the candidate reload while that independent schedule was still active.
The reload inherited DNS as unsuccessful, the daemon's immediate Caddy check
also returned status 1, and all 24 ownership samples remained dual-stack
`Fault` with zero VIPs. The independent schedule perturbed rather than proved
the daemon execution boundary. After rollback reload, native DNS recovered
and Node B returned to `BACKUP`; Node A was not promoted or mutated. Action
35aa is consumed and must not be rerun.

## 1. Purpose

This document governs the as-built Caddy HA deployment on the two Pi-hole
resolver nodes. It records current architecture, live acceptance boundaries,
rollback rules, and approved future work.

The annotated tag in `Caddy/HISTORY.md` preserves the former deployment
journal, full action transcripts, and removed historical artifacts.

## 2. Nodes and addresses

| Role | Host | Node address | Preferred state |
| --- | --- | --- | --- |
| Node A | `j1-svpihole0.local.theama.co` | `10.1.0.53`, `fd36:5aa8:6971:1::53` | MASTER |
| Node B | `j1-svpihole00.local.theama.co` | `10.1.0.54`, `fd36:5aa8:6971:1::54` | BACKUP |

Shared service addresses:

| Service | IPv4 | IPv6 |
| --- | --- | --- |
| DNS | `10.1.0.55` | `fd36:5aa8:6971:1::55` |
| Caddy | `10.1.0.56` | `fd36:5aa8:6971:1::56` |

Node A should own all four VIPs during normal operation. Node B should own none.

## 3. Ownership architecture

Keepalived owns one coupled dual-stack service decision. The IPv4 and IPv6
instances move the DNS and Caddy addresses together.

The coupled design enforces these states:

- normal: Node A MASTER for both families and four VIPs;
- failover: Node B MASTER for both families and four VIPs;
- recovery: Node A resumes preferred ownership after bounded convergence;
- invalid: simultaneous ownership, split-family ownership, or a partial VIP set.

Keepalived uses unicast VRRP with `unicast_ttl 255` and peer
`min_ttl 255 max_ttl 255` on both nodes. Both nodes advertise the same address
count and protocol settings.

## 4. Serving-health policy

Keepalived tracks node-local DNS health and Caddy serving health.

DNS health covers:

- `pihole-FTL` service state;
- `unbound` service state;
- exact local A and AAAA responses;
- Pi-hole and Unbound loopback paths;
- bounded completion that cannot overlap the next scheduled probe.

Caddy health covers:

- `caddy.service` state;
- IPv4 and IPv6 listeners;
- trusted TLS;
- exact `/healthz` status;
- node-specific address binding and hostname handling;
- completion within the Keepalived script timeout.

The pending serving-health migration targets interval 3, timeout 2, fall 2,
rise 3.
Six seconds of sustained serving failure can trigger failover.

Pi-hole/lighttpd web-backend health remains notification-only. A backend
failure does not move DNS or Caddy VIPs. The
`caddy-pihole-web-health.timer` records transitions and enqueues durable
notifications.

These failures remain outside VRRP health:

- lsyncd or reconciliation;
- SSH;
- Apprise delivery;
- certificate-expiry and synchronization timers;
- shared router or internet access;
- monitoring.

## 5. DNS and Pi-hole boundary

The `homelab-dns` repository owns Pi-hole, Unbound, and Keepalived source
configuration.

Pi-hole v5 forwards these namespaces to local Unbound on port 5335:

- `local.theama.co`;
- IPv4 PTR zones for `10.1.0.0/22`;
- the local ULA `ip6.arpa` zone.

Unbound owns authoritative A, AAAA, PTR, and SRV records for the local zone.

The shared Pi-hole management name follows the coupled DNS/Caddy owner.
Node-specific management names remain available through their physical node
addresses when that node and its applications are healthy.

## 6. Caddy routing

The current release contains:

- `Caddyfile`;
- `conf.d/00-health.caddy`;
- `conf.d/10-pihole-admin.caddy`;
- `conf.d/90-default-deny.caddy`;
- `conf.d/91-exact-listener-default-deny.caddy`.

Caddy serves trusted TLS on node-specific and shared addresses. Exact listener
default-deny routes prevent cross-path acceptance. The shared Pi-hole route
selects the backend that belongs to the current coupled owner.

The node environment contains three values:

```text
NODE_FQDN=...
NODE_IPV4=...
NODE_IPV6=...
```

Keepalived priority, peer addresses, transport role, and interface state do not
belong in the Caddy environment.

## 7. Release model

Caddy releases live beneath `/etc/caddy/releases/REVISION`.
`/etc/caddy/current` points to one validated immutable release directory.

A release contains a manifest, payload files, and protocol metadata. Validation
uses per-file identities plus a normalized manifest identity. Caddy validates
the release before selection.

The reconciler owns:

- candidate validation;
- deterministic disposition;
- atomic release installation;
- current-symlink promotion;
- Caddy reload;
- rollback after a failed reload.

No path watcher may race this transaction.

## 8. Protocol-v2 synchronization

Node A publishes normal releases to Node B. Node B rejects normal publication.

Node B may publish to Node A with `--emergency` only while Node B:

- reports MASTER for IPv4;
- reports MASTER for IPv6;
- owns all four shared VIPs;
- passes the guarded publisher preflight.

The transport uses managed lsyncd, a forced SSH receiver, a finalizer, and the
transactional reconciler. Node-specific lsyncd configurations live under
`Caddy/configs/lsyncd/`.

The protocol fails closed on:

- malformed manifests;
- partial transfers;
- invalid hashes;
- unexpected source or parent;
- same-parent ambiguity;
- unsafe metadata;
- unauthorized Node B publication.

## 9. Synchronization service health

`caddy-lsyncd.service` runs lsyncd with `-nodaemon` and journald logging.
The distribution `lsyncd.service` remains masked.

A healthy managed publisher has:

- active/running systemd state;
- positive MainPID;
- successful unit result;
- stable restart count across the acceptance window;
- regular, nonempty, parseable status snapshot;
- no new transport or quarantine failure after the journal cursor.

The status snapshot mtime is not a heartbeat. The minute health timer checks
service state, PID, restart count, snapshot validity, and cursor-bounded errors.

## 10. Durable Apprise delivery

Caddy owns the shared persistent queue and worker. Keepalived and Caddy source
workers act as enqueue-only producers.

Queue data lives beneath `/var/lib/caddy-apprise`. Runtime locks and temporary
state live beneath `/run`. The queue survives reboot.

Producers:

- validate bounded UTF-8 input;
- reject control characters, unsafe paths, malformed records, and secrets;
- persist a stable transition identity;
- atomically enqueue;
- acknowledge the transition after enqueue;
- retry local enqueue on a later timer run if enqueue fails;
- never wait on the Apprise endpoint.

The worker:

- delivers oldest eligible records first;
- uses the IP-based Apprise endpoint;
- applies bounded backoff with jitter;
- deduplicates by stable identity;
- records attempts and dispositions in journald;
- moves exhausted records to the protected dead-letter directory;
- uses locking to prevent path/timer overlap.

Delivery failure cannot change VRRP ownership or source-service health.

## 11. Systemd inventory

Enabled and active:

- `caddy.service`;
- `caddy-lsyncd.service`;
- `caddy-sync-reconcile.path`;
- `caddy-cert-expiry.timer`;
- `caddy-sync-health.timer`;
- `caddy-apprise-worker.path`;
- `caddy-apprise-worker.timer`;
- `caddy-pihole-web-health.timer` after the serving-health migration is accepted.

Static workers:

- `caddy-cert-expiry.service`;
- `caddy-sync-health.service`;
- `caddy-sync-reconcile.service`;
- `caddy-sync-failure@.service`;
- `caddy-apprise-worker.service`;
- `caddy-pihole-web-health.service`.

Static workers must not be enabled directly.

Required masks:

- `caddy-api.service`;
- distribution `lsyncd.service`.

The obsolete Caddy validation path and rejected protected-backend unit are
absent.

## 12. File ownership and modes

Runtime scripts install as root-owned mode 0755.
Systemd units install as root-owned mode 0644.
`/etc/default/caddy-ha` uses root:`caddy-tls` mode 0640.
Release directories and certificate paths restrict access to the Caddy service
identity.

Transactions reject symlinks, broad globs, unresolved paths, unexpected owners,
unexpected modes, unsafe archives, and unbounded output.

## 13. Accepted production contracts

These files define current state:

- `Caddy/manifests/accepted-live-artifacts.tsv`;
- `Caddy/manifests/production-artifacts.tsv`;
- `Caddy/manifests/runtime-production.tsv`;
- `Caddy/manifests/current-live-state.tsv`;
- `Caddy/manifests/deployment.yaml`;
- `Caddy/manifests/synchronization-protocol-v2.yaml`;
- `Caddy/manifests/durable-apprise-production.tsv`;
- `Caddy/manifests/dns-records.yaml`.

Lifecycle registries classify the complete current tree. The main branch does
not retain executed action files.

## 14. Validation model

`Caddy/tests/focused-validation.yaml` selects neutral current tests.

Required properties:

- current tests execute current entrypoints;
- no current profile imports an archived action regression;
- changed-path selection maps each production path;
- Debian-sensitive profiles use one network-disabled Debian 12 batch;
- documentation-only changes remain host-only;
- live successor coverage executes both outer and transaction production paths.

The repository does not carry the former historical full suite. The archive tag
preserves it for explicit reconstruction.

## 15. Live transaction rules

A dual-node mutation follows this order:

1. validate both nodes and capture journal cursors;
2. apply Node B;
3. accept Node B;
4. apply Node A;
5. accept Node A;
6. verify cluster convergence and residue;
7. retain bounded evidence under node and workstation `/tmp` paths.

Reloads remain sequential. Rollback runs in reverse order. A transaction returns
125 if it changed live state and cannot prove recovery. A pre-mutation failure
uses cleanup only.

## 16. Accepted deployment milestones

| Milestone | Terminal result | Archive |
| --- | --- | --- |
| Environment v2, Action 31 | Accepted | pre-cleanup tag |
| Runtime lifecycle, Action 32g | Accepted production baseline | pre-cleanup tag |
| Reliability exercise, Action 33o | Accepted and complete | pre-cleanup tag |
| Durable Apprise, Action 34m | Accepted | pre-cleanup tag |
| Serving-health coupling, Action 35 | Failed-consumed before SSH or mutation | `caddy-action35-terminal-2026-08-16` |
| Corrected serving-health installation, Action 35a | Failed-consumed after Node A SSH preparation contact and before upload or mutation | `caddy-action35a-terminal-2026-08-16` |
| SSH-boundary-corrected serving-health installation, Action 35b | Failed-consumed after exact dual-node upload and before publication or transaction dispatch | `caddy-action35b-terminal-2026-08-16` |
| Privileged-resolution serving-health installation, Action 35c | Failed-consumed during candidate validation and before publication or live serving mutation | `caddy-action35c-terminal-2026-08-16` |
| Environment-complete serving-health installation, Action 35d | Failed-consumed during retained-candidate validation and before upload or live mutation | `caddy-action35d-terminal-2026-08-16` |
| Retained-mode-corrected serving-health installation, Action 35e | Failed-consumed during retained-candidate validation and before upload or live mutation | `caddy-action35e-terminal-2026-08-16` |
| Protocol-mode-corrected serving-health installation, Action 35f | Failed-consumed during retained-candidate ownership validation and before upload or live mutation | `caddy-action35f-terminal-2026-08-17` |
| Production-ownership-corrected serving-health installation, Action 35g | Failed-consumed after Node B selected the published release and before the installation transaction | `caddy-action35g-terminal-2026-08-17` |
| Split-release serving-health installation, Action 35h | Failed-consumed during Node B production-inventory validation and before serving-health mutation | `caddy-action35h-terminal-2026-08-17` |
| Evidence-complete serving-health installation, Action 35i | Failed-consumed during Node B DNS-helper identity validation and before mutation | `caddy-action35i-terminal-2026-08-17` |
| Corrected DNS-consumer serving-health installation, Action 35j | Failed-consumed during Node B Unbound local-zone path validation and before mutation | `caddy-action35j-terminal-2026-08-17` |
| Corrected-production-path serving-health installation, Action 35k | Failed-consumed during Node B Unbound local-zone identity validation and before mutation | `caddy-action35k-terminal-2026-08-17` |
| Exact-local-zone serving-health installation, Action 35l | Failed-consumed at a stale tmpfiles inventory path and before mutation | `caddy-action35l-terminal-2026-08-17` |
| Corrected-inventory serving-health installation, Action 35m | Failed-consumed at the retained Node B incoming inventory and before mutation | `caddy-action35m-terminal-2026-08-17` |
| Exact-retained-entry serving-health installation, Action 35n | Failed-consumed at an incorrect protocol-marker prerequisite and before mutation | `caddy-action35n-terminal-2026-08-17` |
| Marker-free retained-entry serving-health installation, Action 35o | Failed-consumed at role-inapplicable incoming and stale empty-quarantine prerequisites before mutation | `caddy-action35o-terminal-2026-08-17` |
| Quarantine-cleanup serving-health installation, Action 35p | Failed-consumed at the obsolete Node A migration-helper inventory prerequisite before mutation | `caddy-action35p-terminal-2026-08-17` |
| Legacy-helper-cleanup serving-health installation, Action 35q | Failed-consumed at stale Node A quarantine assumptions before mutation | `caddy-action35q-terminal-2026-08-17` |
| Node-A quarantine-cleanup serving-health installation, Action 35r | Failed-consumed at a noncanonical protocol-v2 file-set comparison before mutation | `caddy-action35r-terminal-2026-08-17` |
| Canonical-quarantine serving-health installation, Action 35s | Failed-consumed at the known-broken installed Keepalived parser prerequisite before mutation | `caddy-action35s-terminal-2026-08-17` |
| Parser-free serving-health installation, Action 35t | Failed-consumed at Node A's real-identity Caddy IPv4 HTTPS probe before mutation | `caddy-action35t-terminal-2026-08-17` |
| Post-promotion-health serving-health installation, Action 35v | Failed-consumed after Node B installation at an immediate pre-convergence ownership assertion; Node B rollback succeeded and Node A was not mutated | `caddy-action35v-terminal-2026-08-17` |
| Bounded-convergence and expressive-notification serving-health installation, Action 35w | Failed-consumed after Node B installation because the production DNS status snapshot had not been initialized before Keepalived reload; Node B rollback succeeded and Node A was not mutated | `caddy-action35w-terminal-2026-08-18` |
| Initialization-order serving-health installation, Action 35x | Failed-consumed after Node B installation because the Caddy probe's Keepalived execution group did not reproduce its accepted protected-environment access; Node B rollback succeeded and Node A was not mutated | `caddy-action35x-terminal-2026-08-18` |
| Explicit-group serving-health installation, Action 35y | Failed-consumed after Node B installation because acceptance retained the superseded Proxy status-file group; Node B rollback succeeded and Node A was not mutated | `caddy-action35y-terminal-2026-08-18` |
| Metadata-corrected serving-health installation, Action 35z | Failed-consumed after Node B installation because the real Keepalived schedule returned status 1 for Caddy and intermittently for DNS; Node B rollback succeeded and Node A was not mutated | `caddy-action35z-terminal-2026-08-18` |
| Scheduled-execution-accepted serving-health installation, Action 35aa | Failed-consumed after Node B installation because transaction-launched cycles passed while Keepalived's own DNS and Caddy executions returned status 1; Node B rollback succeeded and Node A was not mutated | `caddy-action35aa-terminal-2026-08-18` |

The archive tag contains the detailed predecessors and failed-consumed
successors.

## 17. Current next gate

Action 35aa is failed-consumed and archived at
`caddy-action35aa-terminal-2026-08-18`. Its retained workstation evidence is
`/tmp/caddy-ssh-evidence-action35aa.o4OC8v`. Action 35aa must not be rerun.
Node B rollback succeeded, Node A was not mutated, and the consumed machinery
was removed before one direct successor is defined.

The recovered production baseline remains:

- Node A is preferred dual-stack `MASTER`, owns all four VIPs, and selects
  `20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04`.
- Node B is dual-stack `BACKUP`, owns no VIP, and selects
  `20260817T160328Z-472d68b9-2bfb-40f1-8563-0754067182ca`.
- Node A retains the finalized outbound candidate for Node B's selected
  serving-health release.
- The direct successor reuses that candidate and does not republish, seed production
  state, or copy Node B configuration to Node A.

The direct successor preserves the remaining standby-first installation while
correcting the daemon-owned execution acceptance boundary:

- do not launch a second DNS or Caddy schedule;
- capture cursor-bounded `Keepalived_vrrp` results and the corresponding
  atomic status-record transitions produced by Keepalived's own executions;
- require repeated daemon-owned successes for both helpers after reload;
- reject missing, stale, nonzero, intermittent, timed-out, signaled, or
  identity-inconsistent daemon evidence;
- retain snapshot initialization, stable Node B `BACKUP` samples,
  split-release continuity endpoints, structured notifications, remaining
  standby-first ordering, and reverse rollback.

This is integrated causal acceptance, not a separate diagnostic. No other
architecture, inventory, publication, convergence, or rollback boundary
changes.

Caddy failures are classified as Proxy serving failures and may change VRRP
eligibility. Pi-hole/lighttpd backend failures are also Proxy alerts, but are
explicitly notification-only. DNS and Replication retain distinct application
classifications. Notification Delivery records its own retry and dead-letter
state in journald without recursively enqueueing another notification.

The installed Keepalived parser interface remains prohibited. Candidate
acceptance uses repository structure, exact rendered identities, real service
identities, standby-first reload, bounded live convergence, and reverse
rollback. Pi-hole/lighttpd backend health remains notification-only.

The registered no-network production-path coverage executes the actual outer
and transaction entrypoints. It observes payload upload boundaries, complete
production-inventory decisions, retained-state rejection and disposition,
Node B installation before Node A promotion, the selected-release transition,
finalizer and reconcile calls, post-promotion IPv4/IPv6 helper success, Node A
installation, reverse rollback, and success/failure evidence readback for both
nodes. Test inputs are isolated; command, mutation, acceptance, rollback, and
success results are produced by the real entrypoints and observable
substitutes, not fabricated markers.

Live execution requires one exact outer-runner SHA-256 authorization after the
current host profiles, one network-disabled Debian 12 batch, the complete
pre-commit suite, and
`Caddy/tests/deployable-successor-policy.sh --authorization-ready` all pass.

## 18. Pending work

After a corrected installation and separately accepted controlled exercise:

1. write operator quick-start, installation, uninstallation, and
   troubleshooting documentation;
2. create the canonical LikeC4 model and generated views;
3. improve the future reverse-proxy application template, using
   `reverse-proxy.caddy.example` as input.

Munin monitoring is canceled. Home Assistant DNS work belongs to a future DNS
change outside this plan.

## 19. Checkpoint procedure

Before a live action:

```bash
git status --short
Caddy/tests/run-focused.sh --profile current-serving-health
Caddy/tests/run-focused-container.sh --profiles current-serving-health
Caddy/tests/deployable-successor-policy.sh --authorization-ready
sha256sum "$(awk -F '\t' 'NR == 2 { print $6 }' \
  Caddy/manifests/deployable-successor.tsv)"
```

Stop after definition and hash reporting. Execute only after the user authorizes
that exact hash.
