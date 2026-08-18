# Action 35: Coupled Serving-Health Failover Correction

## Status and scope

The serving-health architecture is approved. Action 35t is archived only at
`caddy-action35t-terminal-2026-08-17` and must not be restored, modified, or
rerun. Its retained workstation evidence is
`/tmp/caddy-ssh-evidence-action35t.68VRV6`. No mutation entrypoint ran. Node
B's candidate checks passed; Node A failed only at
`caddy_serving_health_check_ipv4_https=false`, after the candidate helper had
deleted its temporary curl diagnostics.

Action 35u is accepted and terminal. It was a narrow, dual-node, read-only
completion capture, not the installation successor. It executed the
exact candidate helper under `keepalived_script`, records the exact IPv4 and
IPv6 curl arguments and detailed outcomes independently on each node, captures
Caddy state and listener evidence, and reads bounded evidence back to the
workstation. It changes no configuration, release, service, synchronization,
VRRP, ownership, or production filesystem state. Only its transaction payload
and archive are removed; node evidence is retained. Evidence or readback
failure returns 74 and unproven payload cleanup returns 75. The installation
successor remained undefined until Action 35u identified the exact failure:
Node A's selected older release returns trusted-TLS HTTP 404 from `/healthz`
over both families, while Node B's serving-health release returns HTTP 204.
All listeners and Caddy service state were healthy, all temporary payload
cleanup succeeded, and no production mutation occurred. The capture's curl
proxy retained but did not relay helper stdout, creating an observer-induced
Node B helper-status failure; the independently executed detailed curl results
are authoritative. No further diagnostic or Action 35u rerun is permitted.

Action 35v is failed-consumed. It accepted and installed Node B's candidate,
then sampled ownership immediately after the Keepalived reload and observed
dual-stack `FAULT` with zero VIPs. That assertion ran before `interval 3`,
`rise 3` could establish three successful checks. Candidate DNS and Caddy
helpers had passed under their real identities. Node B rollback succeeded and
returned it to `BACKUP`; Node A was not promoted or mutated. The pre-promotion
Node A availability sampler also repeated the already-proven `/healthz` 404.
Evidence is `/tmp/caddy-ssh-evidence-action35v.Og4PSy`. No Action 35v rerun or
separate diagnostic is permitted.

Action 35w is failed-consumed. It installed Node B, then failed acceptance
because `/run/caddy-serving-health/dns/status` did not yet exist. The
transaction had installed the tmpfiles contract and helper, but reloaded
Keepalived before invoking the installed DNS and Caddy helpers under their real
identities to initialize both production status snapshots. Node B rollback
succeeded and returned it to `BACKUP`; Node A was not promoted or mutated.
Evidence is `/tmp/caddy-ssh-evidence-action35w.XsZ21C`. Action 35w must not be
rerun and no separate diagnostic is required.

Action 35x is failed-consumed. It initialized valid healthy DNS and Proxy
snapshots before reloading Keepalived, but Node B remained dual-stack `Fault`
with zero shared VIPs for all 24 bounded ownership samples. Every retained DNS,
trusted HTTPS, node-interface, and shared Pi-hole UI availability sample passed.
Node B rollback succeeded and returned it to `BACKUP`; Node A was not promoted
or mutated. Evidence is `/tmp/caddy-ssh-evidence-action35x.LPohmq`. Action 35x
must not be rerun and no separate diagnostic is required.

Action 35y is failed-consumed. It installed Node B and successfully executed
the Caddy helper as `keepalived_script:caddy-tls`, then rejected the generated
Proxy status file at `action_35_y_check_proxy_status_metadata=false`. The
helper atomically creates that file with its executing primary group, so the
correct result is `keepalived_script:caddy-tls:0644`; Action 35y still expected
the superseded `keepalived_script:keepalived_script:0644` metadata. Every
retained DNS, trusted HTTPS, node-interface, and shared Pi-hole UI sample
passed. Node B rollback succeeded and returned it to `BACKUP`; Node A was not
promoted or mutated. Evidence is
`/tmp/caddy-ssh-evidence-action35y.DS3AuU`. Action 35y must not be rerun and no
separate diagnostic is required.

Action 35z is failed-consumed. It corrected and accepted the Proxy status-file
metadata, installed and accepted Node B, and then observed both VRRP instances
in `Fault` with zero VIPs for all 24 bounded ownership samples. The retained
operator journal proves that Keepalived's scheduled execution reported
`check-caddy` status 1 immediately and an intermittent `check-dns` status 1
three seconds later. Both direct transaction identity checks passed and every
retained DNS, trusted HTTPS, node-interface, and shared Pi-hole UI sample
returned status 0. The transaction's journal selector omitted the decisive
`Keepalived_vrrp` records. Node B rollback succeeded and returned it to
`BACKUP`; Node A was not promoted or mutated. Evidence is
`/tmp/caddy-ssh-evidence-action35z.riR2sq`. Action 35z must not be rerun.

Action 35aa is failed-consumed. It installed Node B and all five independently
launched DNS and Caddy cycles succeeded under the intended identities. The
daemon's own `check-dns` execution entered FAULT ten seconds before the
candidate reload while that independent schedule was still active. The reload
inherited DNS as unsuccessful and the daemon's immediate `check-caddy`
execution also returned status 1. All 24 bounded ownership samples remained
dual-stack `Fault` with zero VIPs. After the rollback reload, the native DNS
check recovered and Node B returned to `BACKUP`; Node A was not promoted or
mutated. Evidence is
`/tmp/caddy-ssh-evidence-action35aa.o4OC8v`. Action 35aa must not be rerun.
Its terminal commit and annotated tag are synchronized, its consumed machinery
is removed from the current branch, and the deployment stream is clean before
the direct successor is defined.

Action 35ab is failed-consumed. It stopped Keepalived on Node B, installed the
candidate artifacts, captured the activation cursor, and started Keepalived
once. The daemon's first `check-caddy` and `check-dns` executions both returned
status 1, and neither helper produced a classified status transition. The
transaction failed closed at
`action_35_ab_check_keepalived_daemon_journal_no_failure=false`. Node B rollback
succeeded and returned it to `BACKUP`; Node A was not mutated. Evidence is
`/tmp/caddy-ssh-evidence-action35ab.Tjs3z3`. Action 35ab is archived only at
`caddy-action35ab-terminal-2026-08-18`, its consumed machinery is removed, and
it must not be rerun.

Action 35ac is failed-consumed. It installed Node B and observed Keepalived's
real scheduled DNS and Proxy helpers repeatedly exit 1. Both helpers durably
recorded `unclassified-helper-exit`; their direct candidate identity checks and
every retained DNS, trusted HTTPS, node-interface, and shared Pi-hole UI probe
passed. The transaction failed closed at
`action_35_ac_check_keepalived_daemon_status_records_valid=false`. Node B
rollback succeeded and returned it to `BACKUP`; Node A was not promoted or
mutated. Evidence is `/tmp/caddy-ssh-evidence-action35ac.4Yvvp3`. Action 35ac
is archived only at `caddy-action35ac-terminal-2026-08-18`, its consumed
machinery is removed, and it must not be rerun.

Action 35ad is failed-consumed. It installed Node B and Keepalived's real Caddy
helper durably localized the failure to `probe-result` with failure class
`phase-operation-failed` and exit 1. The helper's unchecked read of an IPv4 or
IPv6 probe status/output file can exit under `set -e` before recording the
family and specific curl or HTTP result. The transaction failed closed at
`action_35_ad_check_keepalived_daemon_status_records_valid=false`. Node B
rollback succeeded and returned it to `BACKUP`; Node A was not promoted or
mutated. Evidence is `/tmp/caddy-ssh-evidence-action35ad.gAKDlx`. Action 35ad
is archived only at `caddy-action35ad-terminal-2026-08-18`, its consumed
machinery is removed, and it must not be rerun.

Action 35ae is failed-consumed. It installed Node B, then the real Keepalived
executions returned 1 within milliseconds: Proxy reported a missing IPv4
probe-result record while DNS failed during probe-evidence processing. This was
not the two-second Keepalived timeout. Node B rollback succeeded and returned it
to `BACKUP`; Node A was not mutated. Evidence is
`/tmp/caddy-ssh-evidence-action35ae.vfzh11`. Action 35ae is archived only at
`caddy-action35ae-terminal-2026-08-18` and must not be rerun.

The installation-successor chain is paused. Before another live successor is
defined, the neutral DNS and Proxy tracking probes must be reduced to essential
checks with direct exit status, default bounded SIGTERM behavior, and no
background result-file protocol or diagnostic output in the health decision.

Action 35w also defined one structured notification contract for DNS, Proxy,
Replication, and Notification Delivery events. Caddy is the Proxy serving
component and remains a VRRP eligibility input. Pi-hole/lighttpd backend health
is a separate Proxy alert and remains notification-only. Producers report a
severity icon, node identity, component, exact check, event, transition,
impact, bounded failure class and status, network and HA context, timing,
correlation identity, evidence pointer, and a first troubleshooting command.
Delivery remains non-blocking and outside health and ownership decisions. The
observed fallback `eligibility-fault-unclassified` confirms that a coupled
FAULT cannot identify its originating application until the production DNS
and Proxy status snapshots exist.

The historical narrative below records the baseline that led to this gate;
any older "next action" wording is superseded by this status section.

The serving-health architecture is approved. Action 35j is archived and
removed after failing at a pre-mutation inventory boundary. Its terminal commit,
annotated tag, immediate cleanup commit, and corrected cross-repository
inventory bookkeeping are synchronized. Action 35k is archived and removed
after failing at the corrected Node B local-zone identity boundary. No mutation
entrypoint ran, both exact upload trees were removed, and rollback was not
required. No diagnostic, Action 35j rerun, or Action 35k rerun is permitted.

Every consumed implementation through Action 35i is preserved by the annotated
tags in `Caddy/HISTORY.md`; none is restored, modified, or rerun from the current
branch. Action 35j is preserved only by its annotated tag. Action 35o's terminal
commit and annotated tag are recorded, and its machinery is removed. The Caddy
deployment stream is now defined only at Action 35v. Actions 35o through 35u
are consumed and are not rerunnable.

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
Action 35j consumed that exact baseline. It emitted expected and observed
identities before every inventory equality decision, accepts only the recorded
deployed DNS-helper identity, and installs the desired repository helper during
the unchanged Node B then Node A transaction. No additional diagnostic or
controlled failure exercise was part of Action 35j. Its execution accepted this
corrected identity and every preceding Node B row, then rejected the missing
stale Node B inventory target
`/etc/unbound/unbound.conf.d/pihole0-local-zone.conf` before any mutation
entrypoint ran. The production target is
`/etc/unbound/unbound.conf.d/pihole-local-zone.conf`; at execution time the
`pihole0` name belonged only to the repository source file. The private source
was subsequently renamed to `pihole-local-zone.conf` to match production. Both
exact upload trees were removed successfully, and the current inventory now
uses the same source and installed filename.

On 2026-08-17 the operator made comment-only changes to the production file on
both nodes and copied those exact bytes to the ignored private source. The
canonical deployed and source identity is now
`f1f422d64a55a77af4d77a829ed3360341cf89f5f78c8e87419f01c3e593054d`.
This current-contract correction did not define or execute a deployment action.
Action 35k consumed the corrected path and registered identity, preserved the
standby-first installation logic, and started from Action 35j's proven
pre-mutation state. It did not republish the retained release, seed production
state, or stream Node B configuration to Node A.

Action 35k execution proved the installed Node B file at the corrected path has
SHA-256 `c3cf7224451a17e419cc4f2401d032aca435e6fe6e0ac61d37acb3e48b829dd9`,
not the registered/source identity
`f1f422d64a55a77af4d77a829ed3360341cf89f5f78c8e87419f01c3e593054d`.
The failure occurred before candidate validation, backup, installation,
Keepalived reload, Node A promotion, or any other mutation entrypoint.
After Action 35k, the operator made both node files exact replicas of the
repository source. Action 35l therefore accepts only SHA-256
`f1f422d64a55a77af4d77a829ed3360341cf89f5f78c8e87419f01c3e593054d`
as the current local-zone identity; the former Node B observation is historical
and is not an allowed baseline. Action 35l backs up and atomically reinstalls
the exact repository file on standby Node B and then Node A, validates Unbound,
reloads it sequentially, and includes the file in reverse rollback. It
preserves every remaining Action 35k installation and recovery control and
does not rerun Action 35k.

Action 35l accepted the exact repository local-zone identity on Node B, proving
the manual synchronization. It then failed-consumed because the inventory
incorrectly targeted `/usr/lib/tmpfiles.d/caddy-ha.conf`; operator readback
proved the exact file exists at the installer-owned production path
`/etc/tmpfiles.d/caddy-ha.conf`. This was before candidate validation, backup,
installation, reload, or any mutation entrypoint. Both exact upload trees were
removed and rollback was not required. The current inventory now uses the
production path. A direct successor may consume that correction without a
diagnostic or Action 35l rerun.

Action 35m consumes this corrected current-production inventory and resumes
the unchanged standby-first installation. It requires the exact regular
`/etc/tmpfiles.d/caddy-ha.conf` artifact on each node, never substitutes the
obsolete `/usr/lib/tmpfiles.d/caddy-ha.conf` path, and does not reinstall or
otherwise mutate the accepted tmpfiles artifact. Action 35m retains the exact
local-zone transaction, split-release baseline, Node B then Node A ordering,
continuous acceptance, reverse rollback, and status-125 controls from Action
35l. No diagnostic or Action 35l rerun is permitted.

Action 35m accepted every Node B artifact identity through the corrected
`/etc/tmpfiles.d/caddy-ha.conf` row. It then failed-consumed before candidate
validation or mutation because the baseline required an empty
`incoming/node-a` directory. Bounded completion readback retained on Node B at
`/tmp/caddy-action35m-completion-readback.tsv` proved the sole entry is the
regular historical `action17p-node-a-to-node-b-bootstrap` directory, owned
`caddy-sync:caddy-sync` with mode `0500`. Both exact upload trees were removed,
no mutation entrypoint ran, and rollback was neither required nor attempted.
The entry was not modified or removed. A direct successor must classify this
exact current-production inventory safely rather than imposing a blanket empty
directory assumption; it must not rerun Action 35m or add a separate diagnostic.

Action 35n validates the sole Node B entry at
`incoming/node-a/action17p-node-a-to-node-b-bootstrap` using its exact
`caddy-sync:caddy-sync:0500` metadata, pinned release-manifest and payload-
manifest identities, strict payload verification, safe file types, marker
boundaries, and exact sibling inventory. With reconciliation and managed
lsyncd stopped, it moves only that entry into transaction-owned evidence.
Rollback restores it before services are reaccepted; successful final
acceptance deletes it only when the transaction evidence root is disposed.
Absent, partial, malformed, symlinked, extra-entry, identity-mismatched, or
unsafe states fail closed. The remainder of the standby-first installation is
unchanged. No Action 35m rerun or separate diagnostic is permitted.

Action 35n accepted the entry's exact metadata, pinned manifests, revision,
source, payload hashes, and safe file types, then failed-consumed before any
mutation because its inventory unconditionally required `.finalize-request`
and `.complete`. Bounded read-only completion capture proved the exact retained
tree is marker-free and otherwise contains only `manifest.sha256`,
`release-manifest.json`, and the files named by that manifest. The capture is
retained on Node B and the workstation at
`/tmp/caddy-action35n-retained-inventory.txt`, with SHA-256
`190986c5ca8976ac50729dd5cb040eff4eea9426d17f7e9aa73c1c4c4b170b40`.
Both upload trees were removed, no mutation entrypoint ran, and rollback was
not required. The direct successor must require this exact marker-free state,
disposition only that validated entry, and resume the unchanged installation.

Action 35o implements that direct correction. It requires all three protocol
control paths—`.finalize-request`, `.complete.pending`, and `.complete`—to be
absent from the retained Action 17p entry. Its exact inventory is the two
manifest files plus every file named by `manifest.sha256`; all pinned
identities, payload validation, safe-type, sibling-inventory, reversible
disposition, rollback, and standby-first installation controls remain
unchanged. Action 35n is consumed and must not be rerun.

Action 35o accepted the complete marker-free Action 17p entry, then
failed-consumed before disposition or production mutation. Node B's
role-inapplicable `/var/lib/caddy-sync/incoming/node-b` path is absent, while
the generic empty-directory assertion incorrectly treated absence as an error.
The transaction also imposed an obsolete empty-quarantine prerequisite.
Bounded read-only completion evidence at
`/tmp/caddy-action35o-quarantine-inventory.txt`, SHA-256
`320a6b0718233c69c939f9cd471006f284efcee060cbca7df6b53be2438af7e9`,
classifies the exact existing quarantine as four safe, payload-valid trees:
Action 17p, Action 33k normalized, and two Action 30c Node B outbound releases.
The earlier instruction to preserve these trees was a temporary fail-closed
boundary while the quarantine state was not fully classified. The bounded
capture now proves that all four trees are historical, payload-valid, and
unreferenced by the current release or current incoming/outgoing state. They
have no current production or recovery role.

Action 35p therefore replaces preservation with an exact cleanup disposition.
It accepts the non-applicable incoming path only when absent, validates every
captured quarantine path, type, owner, group, mode, and file SHA-256, validates
each payload manifest and release-manifest schema, and rejects any changed,
additional, missing, symlinked, malformed, unsafe, or referenced entry. With
reconciliation and managed lsyncd stopped, it reversibly moves the whole exact
quarantine root into transaction evidence and recreates an empty protected
root. Rollback restores the exact captured root; successful final acceptance
deletes the staged historical trees when transaction evidence is disposed.
The quarantine directory must be empty after disposition and at final
acceptance. The remainder of the standby-first installation is unchanged.

Action 35p passed Node B preflight, including the exact quarantine inventory,
then failed during Node A production inventory validation at
`artifact_node_a_lighttpd_prepare_helper_regular=false`. No disposition,
candidate validation, installation, reload, or production mutation ran. Both
exact uploaded payloads were removed. The missing Node A path is correct: the
repository `prepare-lighttpd-config.sh` is a migration tool and is not required
at runtime. Node B retains the exact legacy `root:root:0755` copy with SHA-256
`ce9a78aa487ce55c6fbba553b238160687852361d81c9b37179e4def8f83166f`.
After terminal archival, the direct successor must require the path absent on
Node A, validate and remove only that exact Node B legacy copy transactionally,
restore it on rollback, require it absent on both nodes at final acceptance,
and resume the unchanged standby-first installation.

Action 35q implements that correction. The helper remains in the repository as
a non-installable migration tool and is absent from accepted-live and
production runtime inventories. The generic installer, validator, and
uninstaller consume the corrected lifecycle registry and therefore do not
treat it as a node runtime artifact. Action 35q preserves the exact Node B copy
before removal, restores it if rollback runs, and otherwise completes the
unchanged quarantine disposition and standby-first installation.

Action 35q passed Node B preflight and every preceding Node A artifact,
service, enablement, incoming, and helper assertion. It then failed-consumed
during Node A pre-mutation quarantine validation because the transaction
incorrectly required Node A's quarantine to be empty. The exact observed
top-level inventory is:

- `node-b-20260811T174240Z-31d43261-5cd7-44ce-83e5-947927184d29`;
- `node-b-20260811T180716Z-d45a4dc3-64b6-47c5-bebc-02dade4d9ec4`;
- `node_a-outbound-20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63-action30d`;
- `node_a-outbound-action17p-node-a-to-node-b-bootstrap-action30d`.

No retained-entry disposition, helper removal, candidate validation,
installation, reload, or other production mutation entrypoint ran. Both exact
upload trees were removed, failure readback completed on both nodes, rollback
was not required, and the recovered split-release baseline remains unchanged.
The direct successor must validate these four exact Node A revision families
semantically, reject changed, additional, malformed, symlinked, referenced, or
unsafe state, reversibly disposition them like the Node B quarantine, and then
resume the unchanged standby-first installation. No separate diagnostic or
Action 35q rerun is permitted.

Action 35r is that direct successor. It pins the four names, revisions, source
roles, release-manifest identities, payload-manifest identities, normalized
payload hashes, safe file inventory, ownership, and modes. It rejects any
changed or additional entry and any link from current, incoming, or outbound
state. After Node B is completely accepted, it stops Node A synchronization,
moves only the validated quarantine root into transaction-owned evidence,
recreates the protected root empty, restores synchronization, and proceeds
with the existing Node A promotion and installation. Rollback restores the
exact four-family quarantine before service acceptance. Successful completion
deletes the staged historical trees only when bounded transaction evidence is
disposed.

Action 35r execution passed Node B preflight and every Node A baseline check
through the first quarantine family manifests, metadata, revision, source,
payload verification, and empty protocol markers. It then failed closed at
`node_a_quarantine_baseline_..._file_inventory_exact=false`. No quarantine
disposition, helper removal, candidate validation, installation, reload, or
other production mutation entrypoint ran. Failure evidence readback and exact
upload cleanup succeeded on both nodes, so rollback was not required. The
workstation evidence is `/tmp/caddy-ssh-evidence-action35r.QXPhkL`. Action 35r
is archived at annotated tag `caddy-action35r-terminal-2026-08-17`, its
consumed machinery is removed, and it must not be rerun. The Caddy deployment
stream is clean before definition of a direct successor.

Action 35s is the direct successor. It preserves Action 35r's complete
transaction, ordering, identities, disposition, recovery, and acceptance
logic. Its sole live-path correction replaces the newly invented Node A file
inventory representation with the protocol-v2 canonical comparison already
used by the publisher and finalizer: both expected and observed paths retain
their leading `./` from `find .`. Regression construction runs that same
publisher manifest pipeline, including `release-manifest.json`, rather than a
handwritten alternate manifest. Action 35s consumes but does not rerun Action
35r and resumes the unchanged standby-first installation without another
diagnostic or inventory capture.

Action 35s execution proved the canonical Node A quarantine correction: both
node preflights passed, including all four semantic families. It then reached
Node B candidate validation, where the transaction incorrectly invoked the
installed Keepalived `--config-test` parser. That parser is known to be broken
and unsupported on the installed Keepalived version; it terminated with status
143 and empty stdout/stderr. This was an invalid acceptance prerequisite, not
evidence of a candidate-configuration defect. No disposition,
installation, reload, or other mutation entrypoint ran. Failure readback and
exact upload cleanup succeeded on both nodes; rollback was not required. The
workstation evidence is `/tmp/caddy-ssh-evidence-action35s.BCbKva`. Action 35s
is failed-consumed and must not be rerun. A direct successor must remove every
Keepalived parser-mode prerequisite and reuse the otherwise unchanged
standby-first transaction. Before mutation it must verify repository structure
and exact rendered identity; the sequential standby-first reload, bounded
service/VRRP convergence, and rollback path are the authoritative live
acceptance boundary.

Action 35s is archived at tag
`caddy-action35s-terminal-2026-08-17`. Its consumed runner, transaction,
manifest, coverage, and action-specific regression were removed from the main
branch, and the Caddy deployment stream is clean. Any direct installation
successor must start from current neutral production components, consume but
never rerun Action 35s, and retain the explicit parser-mode prohibition.

Action 35t is that direct successor. It is derived mechanically from the
archived Action 35s terminal transaction and changes only the invalid
Keepalived parser prerequisite: the `keepalived --config-test` invocation and
its test substitute dependency are removed. A production-path tripwire fails
if any Keepalived parser command is invoked. All baseline, quarantine,
publication, standby-first installation, convergence, evidence, rollback, and
status-125 behavior remains unchanged.

Action 35t execution removed the parser boundary successfully: both preflights
and Node B candidate validation passed. Node A candidate validation failed
before mutation because the real `keepalived_script`-identity Caddy probe
reported only `caddy_serving_health_check_ipv4_https=false`. Node A DNS
identity and Unbound validation passed. No quarantine disposition,
installation, reload, or other mutation entrypoint ran. Both node failure
readbacks and exact upload cleanup completed successfully; rollback was not
required. Workstation evidence is
`/tmp/caddy-ssh-evidence-action35t.68VRV6`. Action 35t is failed-consumed and
must not be rerun. It is archived at tag
`caddy-action35t-terminal-2026-08-17`; its consumed machinery was removed
from the main branch and the Caddy stream returned to clean.

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

Action 35v starts from the current production
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

Action 35v is one transaction with complete embedded acceptance:

1. Validate exact split releases, outbound/incoming/quarantine inventories,
   artifact identities, permissions, services, unit enablement, synchronization,
   durable notifications, VRRP ownership, and absence of unsafe residue.
2. Verify both candidate Keepalived configurations by repository structure and
   exact rendered identity without invoking a Keepalived parser mode. Execute
   the DNS and Caddy helpers under their real service identities.
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
