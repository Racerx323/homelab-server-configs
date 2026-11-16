# Fleet Webmin onboarding through Caddy

This is the reusable process for providing standard-browser Webmin administration
on fleet hosts. Webmin owns backend configuration and application acceptance;
[Caddy application onboarding](../../Caddy/docs/APPLICATION_ONBOARDING.md) owns
primary activation, replication and secondary acceptance;
[Fleet DNS change entry point](../../../homelab-dns/Unbound/docs/host-record-deployment.md) owns
all DNS additions, updates and deletions. Reuse those implementations. This document grants no live authority.

## Shared contract and per-host inputs

Normal access is `https://webmin-<hostname>.local.theama.co` on port 443. Each
hostname has A/AAAA records for the Proxy VIPs; canonical host and Proxy PTR
records are unchanged. Use one Webmin fragment per target host, not a shared
backend pool across unrelated hosts. Preserve unrelated Caddy routes and TLS.

| Input | Source and rule |
| --- | --- |
| Target identity | Existing SSH key pin and exact native hostname from accepted evidence; keep the DNS FQDN separate. One explicitly selected host per operation. |
| Browser hostname | Approved per-host hostname; `webmin-j2-svpi3bmf.local.theama.co` is approved for the first host. |
| Backend addresses/port | Explicit target addresses and observed Webmin listener; never infer the target from another application's DNS alias. |
| Backend transport | Bind the reviewed HTTP or verified HTTPS contract. Keep the existing fleet LAN trust boundary explicit; never use `tls_insecure_skip_verify` or silently replace certificates. |
| Allowed sources | Exact Caddy node/active-VIP source identities observed for this host, plus loopback recovery; client-network allowlist belongs at Caddy. |
| Account policy | Existing host Webmin/Unix authentication; no new accounts, password collection, root-login assumption or auth bypass. |
| Baseline and recovery | Current selected settings, file identities, service/resource controls, accepted parent release and exact per-host backups. |
| Public certificate | Existing Caddy certificate coverage for the approved name; certificate repair is separate if coverage is missing. |

Place selected host data in inventory; retain operation-specific identities and
private evidence in the existing change record/store. Inventory selection alone
must not deploy or automatically contact other fleet hosts.

## Prepare and qualify once

1. Inspect only the selected host under bounded read-only authority. Use
   `--expected-hostname` for the exact native `socket.gethostname()` value, not an
   assumed DNS FQDN. Preserve strict SSH host-key verification. The collector
   rejects mismatches before configuration reads and reports expected/observed
   names; malformed or overlong observations are redacted. It never resolves DNS,
   accepts short-name aliases automatically or updates the approved expectation. Capture
   current Webmin version, listener, allowlist, selected redirect/referer settings,
   configuration identities and resource controls. Add `--include-unit-identity`
   when preparing the guarded browser transition: it hashes installed unit/drop-in
   paths, checks effective control stability, reports architecture/native module
   availability, and projects only user/sudoenforce from an existing ama terminal
   ACL. That optional ACL projection is scoped to the first selected host/account;
   other fleet accounts require their own reviewed collector scope. No unit bodies,
   environment values or user/password databases are returned. Confirm routing/source identities
   and any backend TLS requirement. Do not collect users/password databases,
   session material, private keys or whole unfiltered configuration files.
2. Reuse `scripts/configure-miniserv.py` for reviewed managed-key changes and
   native service control. Preserve unrelated settings, existing authentication,
   package versions, resource caps and loopback fallback. Backend ingress must be
   restricted to the reviewed proxy sources before a network listener is exposed;
   verify native Webmin access checks and any host-owned firewall on the real path.
3. Prepare one fragment outside Caddy's accepted production tree using its
   supported template. Give Webmin its own hostname at `/`, avoiding subpath
   rewriting. Set the intended Host/forwarded-protocol behavior and Webmin's
   hostname-specific referer/redirect settings. Never disable referer checks
   globally to make the proxy work. Preserve existing legitimate referers.
4. Use focused local correctness checks for the pinned Webmin and Caddy behavior: URL generation,
   cookies, CSRF/referers, login rejection/retry, redirects/assets and the required
   WebSocket UI features. A login page alone does not pass. Derive the health URI
   and exact status from this server; do not copy Kuma's `/dashboard` contract.
5. Present one concrete owner-reviewed operation with changed inputs, preflight,
   change, acceptance and recovery. Do not ask for a separate approval for every
   internal command. Keep platform rebuilds and unrelated maintenance outside it.

Upstream describes dedicated-hostname proxying using `referers` in Webmin's
configuration and `redirect_ssl`/`redirect_host` in miniserv. These settings must
be checked against the installed version and actual native response behavior;
they are not a ready-to-deploy profile by themselves. See the upstream
[hostname proxy guide](https://webmin.com/docs/tutorials/proxying-to-webmin-with-nginx/).

## Required readiness evidence for every host

Before sealing a Webmin backend change, capture and reconcile both prerequisites
under the selected host and Caddy owners' bounded read-only authority. They apply
to every fleet host, not just the first Pi. Retain the evidence and exact bindings
in that host's existing change record; do not create another readiness ledger.

| Prerequisite | Required evidence and use |
| --- | --- |
| Installed Webmin unit and all drop-ins | Discover the effective FragmentPath and complete DropInPaths from the selected host's systemd. Record each installed file's path, SHA-256, ownership and mode, plus effective resource limits, startup/restart controls and dependencies. Reconcile installed identities against owner sources; repository or fixture hashes alone are insufficient. Bind these identities and the exact saved before-state into preflight and recovery. |
| Current source selection from every Caddy node | On each serving/replicating Caddy node, look up the route to every intended backend address in each enabled family. Retain node identity, destination, selected source address, interface, gateway when present and capture time. For the current two-node dual-stack deployment, this means four node/family observations. Account for an active VIP selected as the source; do not assume the source is always the node's permanent address or copy another application's allowlist. |

Use observed source addresses to bind the Webmin allowlist and host ingress guard.
Recheck these bindings at the operation's pre-mutation gate. A changed unit,
drop-in, relevant effective control or route-selected source requires owner
reconciliation before proceeding; do not silently substitute new expectations.
Boot IDs establish continuity within the operation, not a requirement to match
a previous capture after routine maintenance.

A route lookup establishes intended source selection, not successful traffic.
After the authorized guarded-listener change, verify real requests from each
proxy over each intended backend family, target-observed source addresses and
guard counters, plus rejection of an unlisted client. Preserve unrelated routes
and rules. These packet/application checks remain separate from the readiness
capture and are included in the reviewed change's acceptance and recovery scope.

## Execute through existing owners

1. Apply and verify the reviewed backend restriction/settings on the selected host;
   preserve its authentication, loopback recovery and ordinary service controls.
2. Use Caddy's existing primary-first application flow: prepare the immutable
   child, activate and verify the primary, then expose that same child to managed
   replication. Accept the secondary's manifest, activation and route independently.
   Do not add a separate replicator or revive certificate-deployment orchestration.
3. Verify trusted HTTPS to both nodes and the shared endpoint before DNS using
   the approved name for TLS/Host. Preserve existing route checks and bounded
   convergence. Require useful expected/observed failure reports.
4. Complete private operator login, application/session and applicable WebSocket
   acceptance outside a timed human-attendance window. No password/token appears
   in command arguments, evidence or chat. Do not start a root terminal command
   merely to prove a WebSocket; qualify transport without administrative side effects.
5. Deploy DNS through its existing owner sequence. Finish with ordinary-name
   HTTPS and browser access from intended client networks over both families,
   without a tunnel. Record only the actual host/route acceptance in inventory.

## Failure and recovery

A failed prerequisite stops before mutation. A backend change requires exact
saved configuration and native service recovery; preserve data/accounts and
verify the previous access path. Caddy failure follows its existing primary-first
recovery/partial-state rules. DNS proceeds only after application acceptance.
Do not restore other hosts or the accepted Kuma route as a Webmin recovery step.

When writes, identity or recovery are uncertain, stop and retain precise evidence.
Do not replay consumed operations, force failover or automatically weaken source,
TLS or authentication checks. Optional SSH recovery is documented in
[operations](OPERATIONS.md#optional-recovery-access-ssh-tunnel); it is not the
fleet's normal browser-access contract.

## Render the backend profile

Use `scripts/render-proxy-profile.py --review <reviewed-host-input.json>` to render
managed-key policies for miniserv and Webmin configuration. The
[example input](../configs/profiles/caddy-browser.example.json) uses fictional
addresses; it is not a deployable host selection. Populate selected settings
from the approved capture, explicit backend addresses and reviewed proxy source
identities. The renderer performs no target contact or writes.

The output contains separate `miniserv` and `webmin` policies for the existing
atomic configuration helper. Preserve exact originals for recovery, apply each
policy to its corresponding file and verify before the owner-approved restart.
Do not apply the combined output directly as one file's policy. Bind both files
and any required firewall change into the same reviewed backend operation.

The profile retains explicit loopback listeners and adds only selected backend
addresses; its allowlist contains loopback and exact proxy addresses. It preserves
SSL and authentication keys, adds the approved hostname to existing referers,
and selects canonical HTTPS redirects on port 443. Existing non-selected access,
conflicting host/subpath policy, malformed missing-referrer policy or a transport
change stop rendering for owner review. Native access checks supplement the host-owned
ingress guard; this renderer does not install firewall rules or verify routing.
HTTPS backends still require separately qualified certificate verification.

Webmin 2.670 uses `referer=1` for the global referrer-check bypass. The profile
explicitly sets `referer=0` and extends `referers` with the approved hostname.
`referers_none=1` rejects missing referrers on protected actions; it is preserved,
not reset to zero. Index/login pages have native exceptions. An explicit trusted
hostname bridges frontend HTTPS/443 and backend port differences without adding
a wildcard or disabling checks. The collector includes both independent settings;
older captures lacking `referer` do not establish its value. Bind the deliberate
`referer=0` write and exact before-file identity into the reviewed operation.

Use the same renderer with `--format ingress` to produce the Webmin-owned nftables
table. It follows the existing fleet pre-routing guard pattern, permits loopback
and selected proxy source/backend-address pairs, and drops other traffic to this
local backend port. It replaces only `inet webmin`, preserving Kuma, Netavark and
other tables. A missing proxy-source family stops rendering. Apply and verify the
guard before opening network listeners; persistence, boot ordering and restoration
belong to the host owner's reviewed service operation. Native syntax/apply tests
are not packet-path or remote-source acceptance.

Qualification consists of focused renderer/preservation tests and
`tests/qualify-proxy-profile.py --webmin-root <pinned-source-root>` in an offline
container with native Webmin dependencies. It tests actual miniserv dual-stack
redirect construction, selected listener access and rejection of an unlisted
source. The additional `tests/qualify-proxy-referrers.py` runs unmodified native
`init_config` with isolated CGI inputs: trusted/preserved names pass, foreign and
spoofed names fail, missing referrers fail on protected actions, and the login
exception remains. `tests/qualify-proxy-ingress.py --review <input>` requires a
network-none Podman container and checks native guard apply/reapply plus unrelated
table preservation. These tests do not claim authenticated HTTP, cookies, full
CSRF coverage, Caddy TLS/WebSockets, actual network paths or Pi resource acceptance;
those remain required in the full onboarding candidate.

## Current implementation boundary

The existing atomic Webmin configuration helper and Caddy/DNS owner procedures
are reusable. The shared browser backend policy renderer is locally qualified. First-host
binding, health/authentication qualification and live change remain pending. The installed Pi remains on its
previous SSH-loopback profile until the reviewed onboarding operation succeeds.
The owning Uptime Kuma ledger tracks the first-host work; onboarding another host
must bind that host's own baseline and outcome without duplicating this procedure.

The first-host [review input](../configs/hosts/j2-svpi3bmf-proxy.json) is a local
proposal bound to retained inspection evidence in the owning change record.
It is not deployed state or a live operation. Proxy addresses copied from an
accepted peer application's guard still need actual source/path acceptance for
Webmin before production completion.

## Guard lifecycle and recovery qualification

The proposed [guard service](../systemd/webmin-firewall.service) applies only
`inet webmin`. The [Webmin dependency](../systemd/webmin.service.d/30-proxy-ingress.conf)
orders Webmin after it, stops Webmin when the guard service stops, and reapplies
the rules before each Webmin start. Invalid nft input must prevent startup;
a failed reload must leave the last valid table intact. Stopping the guard does
not delete its rules. An external deletion of the table while Webmin is running
is not detected by this oneshot service; native source restrictions remain a
second control. Never describe it as continuous firewall integrity monitoring.

For recovery, stop Webmin; restore the exact saved miniserv/Webmin configuration
and prior unit/drop-in state with ownership and modes preserved. Reload systemd,
start the saved service profile, and verify its intended loopback listeners and
HTTP/HTTPS response before deleting the Webmin-owned table. Preserve every
unrelated table and resource/startup control. If loopback verification fails,
retain the guard and report recovery incomplete. The fixture now uses the package's native unit producer and the exact
foundation-owned drop-in; its result does not establish the current installed Pi
unit identity. Bind and verify that unit and every drop-in before mutation.

`tests/qualify-guard-lifecycle.py` tests actual systemd/nft failure paths in the
isolated fixture. After a deliberate restart of that owned container,
`tests/qualify-guard-recovery.py` checks enabled-service persistence and the ordered
loopback restoration. These checks cannot prove Pi reboot behavior or packets
traversing its real interfaces.

## Browser and actual-path acceptance

### Safe WebSocket method for each host

Define this method during preparation, before sealing the change. Record the
following in the host's existing plan; keep private supporting evidence in its
evidence store. Reuse the procedure, but qualify each host's enabled features and
account policy independently.

| Decision | Required record |
| --- | --- |
| Applicable feature | Name the enabled Webmin feature that uses WebSockets and the native UI path that exercises it. |
| Effective authority | Establish the existing account's effective module permissions, inherited/default ACLs and execution identity. A missing per-user ACL does not establish permissions. |
| Safe action | Specify the exact UI actions and their side effects, including processes started merely by opening the page or connection. Sending no commands does not establish that a terminal check is harmless. |
| Acceptance | Require trusted HTTPS, authenticated upgrade, the feature's expected session/traffic and bounded idle behavior, followed by disconnect, logout and session invalidation. Retain status/timing only, not credentials, cookies, tokens, terminal output or raw frames. |
| Cleanup | State how to verify the connection and any test-created process/session have ended. Scope cleanup to proven test-owned resources; preserve unrelated sessions and services. Include failure/operator-abort cleanup. |
| Applicability gap | If no enabled feature requires WebSockets, record the evidence and reason for not applying this check. If a required feature has no safe method, retain an owner-review gap before sealing; do not silently waive it or claim acceptance. |

Do not create accounts, broaden permissions, change ACLs or open a root terminal
just to test the proxy. Use an existing safe feature/account capability. Any
necessary policy change is a separate owner decision, not implicit test setup.
Confirm operator readiness before the bounded run; credentials remain private.

When already enabled and available to the existing account, Authentic Theme's
real-time System Information graphs are a suitable candidate method. Use their
ordinary UI and native System Status permission check. Confirm an authenticated
`wss` connection and continuing statistics updates for the reviewed interval;
retain only connection status, frame counts and timings. Do not open xterm or
send terminal input. Do not enable graphs or change their interval/history settings
merely to make acceptance possible.

This feature is not side-effect free: its native collector can register a local
WebSocket backend and update statistics caches/history. Include that ordinary
work in host resource observation. Close the test's connection, log out and verify
session invalidation. Do not call the statistics client's global shutdown/disable
controls: the collector may serve other sessions. Record pre-existing versus
test-created worker state; a shared collector remaining under its normal policy
is different from an abandoned test connection. Any required worker removal must
use the reviewed owner recovery, not a broad process kill. Permission denial,
missing graphs or missing authenticated traffic fails this method; it does not
authorize an ACL change or a silent not-applicable result.

### Route and browser checks

The [first-host fragment proposal](../proposals/30-webmin-j2-svpi3bmf.caddy) remains
outside Caddy's accepted configuration tree. It uses the native login-page health
contract, preserves Host, and follows the existing primary-first owner flow.
The isolated proxy fragment substitutes only hostname, addresses/client ranges and
its private test CA; fixture setup also supplies synthetic accounts and an explicit
native service unit. The browser test requires real Chromium and native Webmin/Caddy,
synthetic credentials, normal certificate validation, both frontend families,
rejected/accepted login, assets, Secure/HttpOnly cookies, protected-page referrers,
logout/session invalidation and the native terminal WebSocket without sending
terminal commands. Its terminal account is an unprivileged fixture-only Unix user.
The fixture does not qualify production PAM/sudo or the operator's real account.
A demonstrated configuration or application defect must be corrected before
using the defective path. Fixture resource pressure is a risk to measure on the
selected host, not proof of that host's capacity or a prerequisite that the
fixture must pass before a bounded target trial. Only target measurements accept
or reject the target resource envelope. Preserve failures and do not raise limits,
omit a failing page or extend response deadlines to manufacture a pass.

Before sealing a mutation, satisfy the
[required readiness evidence for every host](#required-readiness-evidence-for-every-host)
and verify native module dependencies using Webmin's own library path. Keep
source addresses provisional until observed. A route lookup alone is not packet
or application acceptance; the existing loopback-only listener cannot accept a
new network path before the authorized backend change.

The reviewed deployment must therefore include staged real-path acceptance after
the guarded listener change and before publication/DNS completion: probe each
backend family from each Caddy node, verify the target-observed source and guard
counters, reject an unlisted client, then verify each node and the VIP through
trusted TLS using the approved hostname. Force each upstream family in bounded
qualification so first-choice IPv4 success cannot mask broken IPv6. Confirm normal
browser login/logout and applicable WebSocket behavior with the existing account,
without collecting credentials or opening a root terminal merely as a probe.
Recheck the selected host's combined resource envelope and unrelated application/proxy routes. Stop
and recover through the existing owners on a failed gate. These acceptance steps
are part of the one reviewed operation, not independent ad hoc retries.

## Keep the fleet procedure repeatable

### Native backend trial and recovery

The [backend trial tasks](../ansible/proxy-trial.yaml) and
[finish tasks](../ansible/proxy-trial-restore.yaml) are includes for a sealed owner
operation, not standalone commands. They support an active, enabled, dual-stack
loopback baseline with no pre-existing Webmin ingress artifacts/table. Other
baselines require owner reconciliation; these tasks must not overwrite a guard
already used by another deployment.

Bind the exact selected configuration identities and all installed unit/drop-ins,
plus effective service controls, in the private binding input. The source of each
identity is the selected host's accepted capture. Recheck before mutation; do not
substitute repository bytes for installed bytes. Stage the rendered policies,
guard and shared configuration producer privately before arming recovery.

The host-side systemd recovery timer is 30 minutes with one-second accuracy;
the measured workload remains bounded separately to ten minutes. All backend
writes run in one native apply service with a 180-second start deadline and
15-second stop deadline. Recovery stops that service before taking its lock and
restoring files, preventing delayed controller work from reopening listeners.
Both helpers have 48 MiB memory limits, no swap and at most 64 tasks. Recovery
has a 300-second deadline. These helper limits do not change Webmin's limits or
establish host capacity. Record their observed cost during target qualification.

Recovery restores exact config bytes and metadata, preserves installed controls,
removes only the added ingress dependency, and verifies both loopback HTTP paths
and the exact listener set before removing the trial guard. Its temporary
systemd ordering edge is accounted for while the guard is loaded; the final
effective controls must match the baseline exactly. Corrupt backups, unrelated
control drift and failed loopback recovery retain protection and reject recovery
acceptance. A garbage-collected transient apply unit is an expected state, not
evidence that recovery failed.

The bounded trial restores loopback after measurement, including a passing trial.
The finish tasks stop the timer only after verified restoration. Caddy route
recovery and DNS remain separately owned and must be included or excluded
explicitly in the reviewed parent operation. Retain private backups and terminal
receipts; never reuse an operation directory. The transient timer survives loss of
the controller, not a reboot/power loss. No reboot is part of this trial; an
unexpected reboot requires owner reconciliation and does not prove recovery.

### Retain reusable findings

For a temporary backend trial, check the Caddy recovery boundary before sealing.
Local primary-activation rollback does not prove restoration after replication.
The parent must bind the child revision and original parent, contain further
transport of that child, restore both nodes through the Caddy owner, verify
existing routes and transport residue, then restore the backend. Keep backend
deadline recovery independent: if Caddy or the controller is unavailable, backend
recovery still runs and the result reports Caddy recovery incomplete. Never
invoke certificate-repair rollback merely because it contains similarly named
release functions. Do not clean up payloads required for the reviewed restoration
before that restoration is complete.

Use one resource-observation owner during the scan. The existing foundation
`guarded-scan.yaml` also installs the scan guard; importing it unchanged is not a
read-only observation of the installed guard. Bind the installed guard identity,
its exact invocation and evidence retention explicitly. Do not copy a consumed
foundation deployment or run another sampler beside its observer. The combined
path must retain Webmin/Kuma/proxy service observations during scan-time reserve
sampling; a scan-only pass does not establish combined workload acceptance.

During each host's preparation and acceptance, record newly discovered prerequisites,
failure diagnostics and recovery requirements in its existing work ledger. Before
closing that item, incorporate the reusable requirement into this procedure or the
owning Caddy/DNS procedure and link it from the ledger. Keep host values, raw
receipts and attempt outcomes out of the shared instructions. Mark unproven paths
as pending; a first-host result does not accept the rest of the fleet. Reuse existing
entrypoints and records instead of adding a parallel checklist or orchestrator.

## Resource evidence boundaries

A systemd OOM result plus a peak at MemoryMax establishes an OOM failure with
that observed peak. Without contemporaneous cgroup/ancestor events and process
samples it does not establish which process allocated the memory, whether the
unit or an ancestor exhausted its allowance, or which browser request caused it.
Do not infer a memory leak, package-query regression, or required cap increase.

Keep the selected host limits and acceptance criteria while collecting causal
evidence locally. Reuse `scripts/diagnose-http.py`'s bounded `sample()` function
for memory categories, limits/events/pressure and selected process RSS/PSS; it
omits command lines, environments and private application data. Retain samples
before the cgroup disappears. Its existing HTTP runner is not passive browser
observation: it adds its own requests. Do not run that runner alongside browser
qualification as if it were measurement-only, or replay the live diagnostic
playbook. A local attribution fixture should call the sampler without its probe
thread and record safe browser phase/timing and unit/container ancestor events.
Unavailable data or omitted processes preclude complete attribution.

Align the fixture's native unit and foundation drop-in with the owner sources
before comparing resource results. Record unavoidable architecture/authentication
and network differences. Keep the proposed proxy health checks and ordinary UI
background work present in the baseline. A controlled comparison may isolate a
suspected contributor, but disabling it is not accepted production remediation.
Do not combine independent configuration changes and attribute a pass to one.

Do not repeat capacity workloads in this substitute fixture to decide whether a
named fleet host can run Webmin. Stop once configuration/defect questions are
answered; use a bounded owner-authorized target observation for host capacity.
Direct tests of cgroup enforcement, resource leaks or comparative implementation
cost remain useful when that mechanism or comparison is the actual question.
State the workload, controlled variables, duration, decision and limits of that
evidence in the existing work record. Neither a fixture pass nor a fixture failure
is target capacity acceptance. Retain the optional resource test tools for such
explicit questions; they are not mandatory onboarding gates.

A larger Webmin cap changes the host budget, not just this application. The
accepted initial startup allowance includes 320 MiB Kuma, 192 MiB Webmin,
16 MiB loopback proxy and 96 MiB reserve. Any capacity change needs explicit host
review and renewed combined-service/scan qualification. Local attribution or
fixture corrections do not authorize a live retry or accept full browser access.
Resource qualification also requires timely responses: a run below MemoryMax can
still fail through MemoryHigh reclaim/throttling. Correlate pressure, process wait
states, browser timing and proxy health failures; no OOM is not a pass. Preserve
startup health failures separately from failures during the measured workload.
Do not extend response deadlines or weaken controls merely to accept a result.

For offline memory attribution, `tests/prepare-browser-fixture.py` requires a fresh
private `/evidence` directory containing `foundation-dropin.conf` and
`owner-binding.json`. Extract the drop-in content unchanged from the owning
`foundation/ansible/prepare.yaml` copy task; record its SHA-256 as
`dropin_sha256`, alongside the owner source path/hash. The fixture verifies that
binding, calls the package's `init/updateboot.pl` producer and checks effective
limits, timeouts and restart controls before startup. Preserve the generated unit
and effective-property receipt. This is local service alignment, not inspection
of the installed target.

`tests/observe-browser-memory.py` runs only inside that network-none fixture.
Its default mode retains the short IPv4 diagnostic. For sustained paired-proxy
qualification, prepare and observe with `--paired`. Preparation creates two
independent Caddy processes bound to separate loopback addresses, preserving the
proposal's TLS, referrer, transport and 30-second health-check settings. The
four sequential browser checks cover each proxy over IPv4 and IPv6; A initially
has only the IPv4 upstream and B only IPv6, so successful requests cannot fall
back to the other backend family. These are isolated fixture paths, not evidence
of production source selection or installed firewall behavior.

The observer then restores both upstreams on each fixture proxy and restarts only
those fixture Caddy processes. Two concurrent authenticated browser workloads
hold native WebSockets open without terminal input for at least 95 seconds.
Protected HTTP/session checks repeat at 0/15/30/45/60/75/95 seconds, spanning three
configured health intervals. This proves the measured workload and retained
connections; it does not log or prove each successful active-health probe, nor
establish long-running capacity.

The observer uses the existing sampler without a separate HTTP probe thread.
After a five-second baseline it samples nominally every 250 ms, retaining actual
gaps, visible ancestor counters, proxy charges, missing process rollups and
observer RSS. Browser phase markers contain no credentials, cookies or page
contents. Short phases can fall between samples. A failed client, hard-limit/OOM
event, disappearing cgroup, 420-second deadline or 24 MiB evidence bound ends the
run; failures are not retried. Record each workload's status and the effective
service state separately from collection completion. The container's 1536 MiB
limit accommodates local Chromium and proxy processes outside Webmin's unchanged
192 MiB cgroup; this does not emulate the Pi's combined workload or reserve.

The observer stops the owned Webmin/Caddy services before browser teardown and
never restarts Webmin. Stop can leave Webmin's unit in failed/exit-code state even
when its process is gone; verify MainPID, listeners and owned browser cleanup
rather than relabeling that state as a runtime OOM. The caller must remove only
the owned container and retain private evidence after collection.

### Temporary paired exposure and one resource observer

Use the Caddy owner's [temporary application trial interface](../../Caddy/docs/APPLICATION_ONBOARDING.md#temporary-application-trials)
and the foundation owner's [combined observation interface](../../foundation/README.md#combined-workload-observation-without-changing-the-installed-guard).
Retain the application recipe's selected fragment, exact prior release inventories,
fresh boot continuity and per-node recovery payloads. Do not implement a second
release publisher in the Webmin parent.

Before sealing, bind the installed scan guard separately from the staged observer
source and private resource profile. Keep the same scan lock, unit names, caps
and reserve. One observer must cover baseline, the existing account's statistics
workload and the list-only scan; do not add a competing memory sampler. The parent
must match the timestamped browser and scan receipts and reject absent overlap.
Stop owned browser load before signaling Caddy to restore, then restore the native
Webmin backend. Report each recovery outcome separately. Controller loss can leave
Caddy recovery incomplete even when the backend's independent timer succeeds.
These reusable interfaces do not seal or authorize a particular host trial.

### Combined parent and browser receipt contract

Use `ansible/proxy-combined-trial.yaml` to join the native backend includes,
existing Caddy owner entrypoint and `ansible/proxy-resource-trial.yaml`. Bind
its reviewed inventory/vars and all non-secret inputs before review. Its
preflight requires the Caddy authorization-ready check, exact input hashes,
installed client module access, native hostname and actual service/cgroup
controls. A preparation-time cgroup path is an admission expectation, not a
new target observation.

`probe-proxy-path.py` records each proxy's route-selected source, connected
socket endpoints and HTTP result. Target-side named counters must increase for
each accepted source/family and for both unlisted-client denial checks. These
receipts establish the actual backend path during the authorized trial; isolated
packet tests only establish collector/guard correctness.

`proxy-statistics-client.cjs` uses the existing account and the theme's native
System Information navigation. It requires the page marker and fresh frames
from an open statistics socket after navigation. Frames from login or closed
sockets cannot satisfy readiness. Run the six frontend paths in three pairs:
A/IPv6 with B/IPv4, both VIP families, then A/IPv4 with B/IPv6. Each path receives
at least 95 seconds; the final pair uses the reviewed longer hold for scan overlap.
Concurrency stays at two owned clients. Preserve the existing trial deadlines;
slow readiness or missing overlap fails instead of extending the operation.

After each path, close the statistics page, log out, and restore only that owned
session cookie in memory to verify rejection on the protected page. Clear it
and close the context afterward. Never export the cookie, private DOM, frames,
credentials or screenshots. Do not enable graphs, alter their settings, open a
terminal or invoke global collector shutdown. The backend's reviewed restoration
still governs shared collector/service cleanup.

`supervise-proxy-workload.py` sends the token-bound scan gate only after both
final clients have fresh sustained heartbeats. The existing locked observer is
the only resource sampler. Match every running scan sample to both browser
intervals using bounded host/workstation monotonic-clock brackets; do not assume
those clocks share an origin. Reject missing per-path duration, session denial,
resource acceptance or cleanup. Stop owned browser load before scan cancellation
and Caddy restoration; preserve incomplete cleanup as a failure.

The `--check` client command checks source/spec/module and executable access;
it does not launch Chromium or establish native UI readiness. Synthetic browser
regressions and parent adapters qualify contracts and recovery ordering only.
The authorized real-host trial must still prove actual UI permissions, statistics
traffic, proxy paths, service responsiveness, scan overlap and capacity. A local
pass does not seal a host operation or grant live authority.

Before presenting the combined trial, define the single Caddy owner candidate
and run its authorization-ready check against qualification for that exact
source graph. A successful temporary restoration expects exit zero; injected
failures must retain their distinct rejection or incomplete-recovery statuses.
Bind the parent inventory, vars, rendered profile, installed-unit expectations,
route/source expectations, resource profile, browser paths, workload commands
and owner qualification inputs in one non-secret manifest. Verify that both
the parent's explicit known-hosts file and Caddy's effective SSH configuration
recognize the accepted target keys; they are separate SSH invocation paths.

Identify credentials only by their external reference and required privacy.
Collect the existing account password privately on the workstation before the
authorized parent starts, with no human-response deadline during exposure.
Use an owner-private runtime file, never overwrite an existing credential file,
and remove only the file created for that invocation after the parent exits.
An explicit operator launch confirms readiness for the bounded automated run;
it does not replace exact-bundle authorization. Preserve the one-attempt marker
and both recovery receipts before considering any further operation.
