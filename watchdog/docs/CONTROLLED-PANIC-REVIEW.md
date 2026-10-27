# Single controlled-panic watchdog recovery review

Status: reusable contract for the implemented one-use controller and worker.
An executable operation is sealed separately with its exact inputs and expiry;
repository implementation or local qualification is not execution approval.
See [history](../HISTORY.md) for the active review and qualification results.
No panic or target contact is performed by documentation or local tests.

## Scope and selected mechanism

Select one root write of the single ASCII byte `c` to `/proc/sysrq-trigger` on
j2-svntp1. The guarded worker must open that proc interface once, write once
and never retry, including after an error or lost acknowledgement. This is the
only intentional failure injection. It is specified here for review, not issued
as an execution command. Do not use the consumed inspection runner to perform it.

Keep PID 1/systemd as the existing watchdog0 owner, runtime/reboot settings
60/120 seconds, panic timeout 0, existing debugger configuration and installed
kernel unchanged. Do not open a watchdog device, stop PID 1, install a daemon,
change SysRq policy, invoke reboot, schedule a failure job or enable persistent
journals/pstore. Preserve running NTP, GPSD supervisor, cron and Munin before the
fault. The fault necessarily interrupts them; their ordinary boot activation
must recover service. Existing alerts and boot jobs may run normally. There is
no new test mail, forced report, collection, limits evaluation or retry.

This deliberately crashes the kernel and can lose in-flight writes or expose
filesystem/media damage. A bounded sync before injection reduces dirty data;
it does not make a panic equivalent to a clean shutdown or guarantee recovery.
It tests this keepalive-loss path only, not every userspace hang, power failure,
firmware fault or future fleet host.

Target: `ama@10.1.0.51`, hostname `j2-svntp1`, pinned existing Ed25519 host key
under alias `10.1.0.137`. Client probes use only `10.1.0.51` and
`fd36:5aa8:6971:1::51`, UDP 123. Recheck these against the retained accepted
network capture before producing the executable bundle. No peer, master, DNS,
network-controller or switch API access belongs in this stage.

Authentication is an explicit external Ed25519 private-key reference and public
fingerprint in the sealed specification. The controller validates owner, mode,
link count and noninteractive key availability before consuming an execution
receipt. Private key contents are never bundled, hashed or logged. All SSH calls
use that identity with agent, password and keyboard-interactive authentication
disabled. Local key checks and native SSH configuration parsing do not prove
server acceptance; that remains part of the approved live preflight.

Before sealing a panic operation, assess every newly introduced hard preflight
condition against read-only evidence; a metadata-only baseline cannot qualify
message-content checks. Execution must still recheck changing conditions. Keep
unresolved conditions as explicit preparation gaps rather than assuming they pass.
The journal guard reuses the accepted bounded NTP startup classifier with fresh
child PID, process-start monotonic time and service invocation. Pre-origin or
wrong-invocation entries are rejected, never silently skipped. Duplicate/count,
provenance and value bounds remain; reaching the query cap is incomplete evidence.
Other errors, including unresolved udev-rule messages, block execution. Native
health and authenticated NTP checks remain independent. No audio-rule exception
is implied by a matching upstream bug report. Resolve package-update readiness
before another panic seal; changed kernel/systemd artifacts require renewed
source/reset-path qualification.

On full-preflight failure, the worker emits completed observations and the failure
before exiting nonzero. Failed bounded commands retain their output/status. The
controller saves the transport record before rejecting it; partial capture never
passes preflight. Values not yet collected remain absent. A separate journal-only
inspection uses the same guarded transport but cannot authorize or invoke panic.

## Why this trigger, and what attribution can establish

Use the retained exact-package assessment and accepted focused debugger snapshot
listed in the private evidence manifest. The running release/config match the
assessed Raspberry Pi package. Its SysRq crash handler calls panic; panic=0
excludes the generic timed restart, the matching build excludes crash kexec,
and empty normal kgdboc plus absent selected early options exclude the assessed
configured debugger transports in that snapshot. Fresh preflight must confirm
those inputs before the attempt. Source/package mapping is not running-binary
attestation; the source descriptor signature was not independently verified.

Once the terminal panic path stops normal scheduling, systemd and the kernel
watchdog worker should cease feeding. The BCM2835 hardware counter spans just
under 16 seconds; the worker bridges the exposed 60-second timeout. Therefore
60 seconds is not the expected whole-kernel-panic reset delay. The last feed's
phase, panic processing and firmware/display delay are not measured. No positive
minimum delay or exact 8–16 second interval is claimed.

Attribute recovery to watchdog expiry only through the combined evidence:
qualified fresh owner/configuration, confirmed panic console text, independently
observed reset/boot, exclusion of the assessed competing reset paths, no operator
or external power/reset intervention, changed boot ID and restored health.
Timing, SSH loss, a new boot ID and bootstatus=0 are insufficient individually.
The driver does not provide a usable reset-cause discriminator; this remains a
bounded source-and-observation attribution, not a hardware reset-register proof.
Any contradictory evidence, debugger entry, unexplained power event, missing
panic observation or intervention before reset makes attribution inconclusive.
Do not convert an inconclusive result into a pass because the server returned.

## Fresh preflight and arming

Each executable bundle must pin repository-owned worker/controller/probe bytes,
all non-secret inputs, expected hashes and one absolute approval-expiry epoch.
Give it a 24-hour validity window at sealing; start only with 90 minutes left.
No time is reserved or automatic execution scheduled by this review.

1. Reconfirm Aaron is attending, KVM shows this host on the separately powered
   laptop, working Debian 11 card is at hand, and j2's physical PoE connection
   is identified. Record the fallback card's known hostname/address or mark it
   unknown. Resolve unknown identity before admitting that card to the service
   network; no alternate power or isolated network is assumed. Do not require
   another planning-stage card boot.
2. Aaron confirms j1 still serves time and powers the shared antenna. Keep its
   PoE connection and antenna wiring untouched. Separate ports do not establish
   independent upstream switch power. Abort if node-only recovery is uncertain.
3. Complete bounded preflight within 15 minutes: strict host key/hostname/boot,
   kernel release and complete config hash, package-bound owner/manager settings,
   vendor/config hashes, empty kgdboc and absent selected debugger boot options,
   panic=0, watchdog active with PID 1 sole descriptor owner and no scan gaps.
   Reuse repository inspection primitives in new code; do not replay receipts.
4. Compare the four protected NTP/reporting hashes, actual network addresses,
   source-built ntpq identity, service enablement/state and storage/hardware
   state with accepted inputs. Require writable filesystems, no current storage
   error/undervoltage/thermal fault, at least 10 GiB available and 5% free inodes.
   Historical sticky hardware flags require disposition, not silent clearing.
   Missing facts or material drift stop before injection.
5. Establish three healthy NTP snapshots at least 30 seconds apart using the
   criteria below. Capture core service identity and NRestarts, selected files,
   relevant current-boot error journal and existing maintenance timestamps.
   Do not invoke a producer or clear logs/counters to make a baseline pass.
6. Run one sync with a 30-second controller bound, while normal services remain
   running. Failure/timeout stops the attempt. Recheck critical ownership,
   panic/debugger settings, same boot and health after sync. Final health must
   finish no more than 10 seconds before trigger submission; critical recheck
   must finish within that same 10-second interval. No waiting armed overnight.
7. Save a durable off-node exclusive one-use receipt before any trigger-capable
   session. Save/fsync the final evidence and arm decision before releasing the
   worker. The operator must still be present and independently observing.

Receipt state distinguishes preflight-only, armed, submitted, panic-observed,
reset-observed, health-restored, stable, held and terminal. These are evidence
states, not reasons to automatically repeat a command. Once armed, any ambiguous
transport result consumes the attempt. Restarting the controller must refuse a
second trigger for that operation. No automatic resume/reconnect of a trigger
session. Post-boot read-only sessions are separate from trigger delivery.

## Timing contract

All durations use one off-node monotonic controller clock. Retain UTC correlation
and operator clock disagreement before arming; do not change clocks during test.
H is controller launch time plus worker elapsed time before native health,
minus two seconds uncertainty. SSH startup/transport delay therefore lengthens
the measured bound; it cannot move H later than observed native health. Refuse
the grant if S-H exceeds ten seconds. The notes use controller timestamps where possible. For each manually
observed event retain earliest/latest bounds, not a fabricated exact instant.
Require combined observation-clock uncertainty at most 2 seconds for the reset
criterion; otherwise timing attribution is inconclusive. Uncertainty is always
included in the reported upper bound.

Let H conservatively bound the start of the last healthy pre-trigger sample,
S the first trigger submission, P the independently witnessed panic interval,
R the independently witnessed reset/boot-start interval, and C the completion
of the third consecutive post-boot healthy sample. SSH departure is not P or R.

| Boundary | Exact proposed criterion | Failure response |
| --- | --- | --- |
| Final freshness | 0 <= S-H <= 10 seconds | Abort before submission if stale |
| Reset observation | Upper bound R.latest-P.earliest <= 30 seconds, with confirmed panic and no intervention | Mark reset-timing failure if exceeded; missing P/R is inconclusive, never infer reset from SSH |
| Hardware expectation | Less than 16 seconds from last actual hardware feed to expiry, source-derived | Not a measured deadline from S; 30 seconds allows observation/boot visibility overhead, not a guarantee |
| Escalation | At S+120 seconds without observed reset/boot | End autonomous progression; Aaron assesses KVM and chooses the bounded recovery branch |
| Usable NTP | C-H <= 300 seconds, including uncertainty | Fail five-minute resilience; preserve later recovery separately |
| Recovery sampling | Start after new-boot SSH identity is available; health samples at least 30 seconds apart; 10-second maximum sample duration | Timeout/missing/false sample breaks the consecutive run; never extend five-minute deadline |
| Stability | 30 continuous minutes from C; sample every 60 seconds including the final sample; completed-sample gap <= 75 seconds | Reset, health failure or excess gap prevents stability acceptance |
| Automatic work cap | S+45 minutes | Save terminal result and stop automated reads; no automatic reset, replay or indefinite polling |
| Reserved attendance | 90 minutes available before arming | Do not start without this reservation; extended failed-test hold is a separate operator disposition |

Poll for post-boot SSH at most once per 5 seconds, each connection bounded to
3 seconds, one outstanding connection only. Do not probe old-card identity using
new-card assumptions. Health samples may read node state and send one mode-3 NTP
request per fixed IP family, each bounded to 2 seconds. Fixed cadence observations
are not a retry of the destructive trigger. Retain unsuccessful samples and gaps.

C is deliberately the third qualifying sample, not a backdated first response.
The five-minute bound is therefore conservative. Long deployment-test downtime
is tolerated by Aaron but cannot pass normal-operation resilience. The 30-minute
stability interval is this pilot's proposed acceptance check, not OBS-09.

## Usable service and post-boot checks

Reuse repository-owned NTP native parsing/client packet validation, without
invoking old operation runners or Munin plugins. Pin actual commands and parser
bytes in the executable bundle. Run the repository-owned native `measure-time-service.py` through isolated
system Python against localhost. Reuse `measurement_checks` from the accepted
cutover implementation for system, serial/PPS and all three configured NTS
associations. Hash the installed ntpq/ntpd/gpsd files before and after; do not
invoke a historical operation runner or change native control policy. Require:

- PPS selected using the accepted SHM(2)/PPS classification, serial and PPS
  reachable, leap 0 and stratum 1. Absolute selected PPS offset <= 5 ms and
  jitter <= 1 ms. Do not equate the legacy native `o` tally alone with selection.
- All three configured NTS upstreams authenticated/reachable with cookies;
  distinguish missing acquisition from a parser error. Neither passes.
- Valid synchronized stratum-1 PPS mode-4 client responses on both fixed address
  families, request nonce/originate match and plausible timestamps. No client
  clock adjustment. SSH or ICMP success is not usable NTP.
- Expected NTP/GPSD supervisor credentials, active core services and no supervisor
  restart within the new-boot observation interval. GPS/PPS inputs must be owned
  by the expected running service, not an extra diagnostic reader.

Post-boot reconciliation also requires a new boot ID, same expected host/key,
unchanged protected files/vendor policy/kernel, restored sole PID 1 watchdog
ownership and active runtime policy. Compare network addresses/routes/resolvers,
UDP listeners and retained access policy with accepted values. Send one bounded
administrative READVAR probe per fixed family during final reconciliation and
require denial under the existing client-check semantics. Preserve current-boot
service/storage error entries; unexplained relevant errors prevent acceptance.

Keep cron/Munin and maintenance timers enabled with their expected configuration;
read existing records only. Capture existing leap timer/service records to inform
OBS-06, without claiming a scheduled job ran merely because its timer exists.
Master polling/graphs and independent firewall coverage remain separate scopes.
No master contact or forced job is included. Missing future scheduled records do
not justify forcing them or silently closing their prerequisite gates.

## Independent evidence and interruption

Aaron observes ordinary console identity, panic text (including the crash reason),
reset/boot transition and subsequent console access. Use timestamped notes on the
separately powered laptop plus private controller logs. Video is optional; retain
an optional still only if useful and avoid credentials/unrelated screens. Record
power/console actions and uncertainty immediately. A missing panic message is a
test evidence limitation, not permission to configure the console or panic again.

The controller retains immutable approved inputs, one-use receipt, raw bounded
stdout/stderr/status, wall/monotonic timestamps, preflight and every post-boot
sample, gaps, interventions and terminal disposition. Hash original closed files;
keep raw evidence private. Per command: <= 1 MiB per stream, <= 10 seconds unless
a tighter bound above applies; cap the total capture at 64 MiB. Hitting a bound
stops automatic work and preserves partial evidence. Never overwrite a failed log.

If controller power/network fails after arming, Aaron continues KVM notes against
the saved deadline card. No reinjection, automatic resume or borrowed stopwatch
precision. Recovery can proceed manually within the branch below, but missing
health/timing evidence cannot pass. A single unplanned additional reset fails the
attempt; isolate j2 rather than repeatedly exercising a boot loop.

## Restoration and failed-test handoff

No persistent policy or service change is proposed, so there is no configuration
rollback. Sync and a panic cannot undo in-flight filesystem damage or elapsed
outage. A future worker must run from standard input; do not leave a trigger
script, cron entry, timer or boot action on the node. Retain the controller receipt.

Execution approval must explicitly include these attended contingencies:

1. Before submission: abort cleanly on any failed prerequisite. Leave services
   and policy intact. An armed/uncertain operation remains consumed.
2. After submission: allow automatic boot and health observation to the stated
   deadlines. At S+120 without reset, or H+300 without usable health, stop seeking
   a pass and inspect the KVM. Never type debugger reboot/continue as evidence of
   watchdog expiry. Do not issue another panic or remote restart.
3. If still hung or boot-looping, Aaron may disconnect only j2's identified PoE
   cable/port physically, hold it off for at least 30 seconds, then reconnect
   once with the current card. This is manual recovery, disqualifies expiry
   attribution if it precedes the observed reset, and cannot salvage resilience.
   No switch API or shared power action is included. If identity/isolation is
   uncertain, leave power unchanged and hold.
4. If that one current-card recovery fails, power j2 off and use the confirmed
   working Debian 11 card. Keep Ethernet/PoE disconnected until card placement
   is complete. Before reconnecting PoE, require the original identity and network
   configuration recorded at preflight. If unknown, leave the node powered off
   pending a separate recovery disposition; this review does not assume another
   power source or authorize a switch change. Verify identity on KVM after boot. Do not apply new-image files or guess
   old-card addresses, alter DNAT, or claim current-image acceptance.
5. Do not run fsck repairs, reimage media, change packages, firmware, debugger,
   timeouts or service configuration under this review. Preserve the failed card
   and evidence. Any such repair needs its own defined operation.

At failed-test handoff Aaron owns restoration/hold. Record state, last health,
manual actions and next attended check within 60 minutes; do not install a timer
or silently wait for hours. Longer deployment outage is allowed, not an automatic
acceptance extension. Old-card recovery is a distinct fallback outcome and does
not accept the new deployment. Preserve primary time service and antenna power.

## Qualification and execution-seal boundary

The controller is `watchdog/scripts/run-panic-recovery.py`; its streamed worker
is `watchdog/scripts/panic-worker.py`. Tests exercise actual receipt, archive,
expiry, one-use grant and rejection guards offline. The write primitive is tested
only against a temporary regular file with live prerequisites bypassed; this
neither simulates nor proves a hardware reset. A streamed boot-query payload must
reject the controller's identity before any target-specific collection. No live
inspection or failure injection belongs in local qualification.

The seal includes both scripts, tests, native/read-only dependencies, baseline,
host key, this contract, operator template, notes and generated execution review.
Check verifies exact source and archive bytes. Execute requires a fresh operator
record and creates its durable receipt before target contact. No resume/retry
entrypoint exists. Review generation and check do not contact any target.

Automatic results report service/stability evidence but leave hardware attribution,
network/record reconciliation and final operator acceptance pending. Completion
cannot substitute for KVM panic/reset observations. The executable review names
all exact read scopes and conservative preflight rejection conditions.

Closure records separate preflight, submission, attribution, five-minute service,
stability, restoration/residue and operator acceptance results. Failed or missing
evidence remains failed/inconclusive. This stage cannot close fleet adoption,
all failure modes or overall production acceptance. Qualified OBS-02/D1–D5 and
bounded OBS-04 remain unchanged; OBS-09 is not started.
