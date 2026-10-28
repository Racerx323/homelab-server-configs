# Pilot reset attribution qualification

Status: repository/source analysis, October 26, 2026. No target contact, device
access, failure injection or trigger selection. This is not an executable review.

## Retained target facts

The accepted recovery-readiness capture found PID 1 owning watchdog0, active
BCM2835 watchdog identity, a 60-second exposed timeout and bootstatus 0. Kernel
release is 6.18.50+rpt-rpi-v8; systemd is 257.13-1~deb13u1. Kernel panic timeout
is 0; selected configuration enables SysRq. Journals are volatile and pstore
is empty. These are snapshot facts, not proof of a future reset cause.

## Exact-package assessment

The [package assessment](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-package-assessment-20261026-v1/assessment.md) supersedes the earlier vanilla-release/moving-branch
comparison. Exact linux 1:6.18.50-1+rpt1 source archives match their publisher
descriptor checksums; 32 package patches were applied offline. Changelog records
Raspberry Pi commit cff533aec2fa601846766b32ff57204e0a61bed7. The matching published
binary package's complete kernel configuration hashes identically to the captured
node config. This establishes package/source/config mapping, not running-binary
attestation; descriptor signature verification was not performed.

| Path | Assessed result | Remaining boundary |
| --- | --- | --- |
| Timed panic reboot | Retained panic=0 excludes the generic timed emergency_restart branch | Recheck at execution preflight; do not introduce a nonzero panic timer |
| Crash kexec | Matching full config omits KEXEC_CORE; source compiles __crash_kexec as a no-op | The missing interfaces are explained by build configuration; no repeated loaded-state inspection needed for this package/config |
| KGDB/KDB | Panic enters debugger only with registered I/O and zero panic timeout, before stopping other CPUs | Need normal/early kgdboc transport configuration; built-in support alone is inconclusive |
| Explicit reboot | Ordinary restart and KDB reboot can program the same hardware reset mechanism | They cannot count as expiry after lost keepalives |
| Watchdog timing/status | Short hardware countdown is bridged by kernel workers; driver provides no usable bootstatus cause | Qualify timing from the actual mechanism; no 60-second whole-kernel assumption or reset-cause flag claim |
| Other reviewed hooks | Applicable ARM64/RCU/hung-task/trace/LED hooks report or mark panic; reviewed alternative platform reset hooks are excluded by matching config | No direct competing reset found in this bounded source review; firmware/external power and runtime intervention remain separate |

The exact-file hashes, patch impact and detailed source symbols are retained in the
assessment manifest. Historical reference downloads remain intact as preparation
history; they are no longer the package-provenance gap.

A candidate panic should cease ordinary PID 1 and kernel-worker keepalives if it
reaches the terminal panic path without an alternative reset/boot handler. This
is a conditional source-derived expectation, not a target-qualified guarantee.
Do not freeze an exact reset tolerance from the nominal 60 seconds or infer a
measured 8–16 second bound: worker phase, panic processing, clock uncertainty and
firmware startup visibility are not measured here.

An ordinary reboot, service restart, network disconnect, or manual power cycle
cannot by itself demonstrate expiry after lost keepalives. Do not add a second
watchdog owner or a PID 1 manipulation harness merely to manufacture a test.
A panic test would deliberately interrupt writes; the later review must define
storage preparation and recovery without disabling normal reporting or time
service before the single controlled fault.

## Smallest adequate evidence

Use Aaron's confirmed KVM on a separately powered laptop, attended throughout the
attempt and initial recovery. No video requirement. Keep timestamped operator
notes of the identified console, trigger/panic text, reset/boot transitions and
any intervention, alongside an off-node controller command/receipt log. A still
image or existing KVM capture is optional if a message would otherwise be lost.
Do not capture credentials. Preserve ambiguity and time uncertainty rather than
inventing a precise trigger timestamp from SSH loss.

Combine these observations with approved pre/post boot identity, owner/config
continuity and NTP health checks. A video, new boot ID or successful return alone
is insufficient. If competing reset mechanisms remain unresolved or Aaron must
intervene first, record recovery separately and mark watchdog attribution
inconclusive. No extra recording hardware or persistent logging change is required
by this proposal.

## Remaining native qualification

Before an executable trigger review, resolve only the remaining debugger and
console facts through a separately approved scope where target reads are needed:

- Current kgdboc parameter and selected normal/early debugger boot options. The
  consumed collector's command-line allowlist omitted those keys; absence from
  its output is not proof of absence from the running command line.
- Interpret configuration against normal and early-console registration. Do not
  change debugger settings or read kernel memory to manufacture qualification.
- Aaron confirmed on October 26 that the ordinary KVM display identifies
  j2-svntp1. This closes ordinary visibility; panic-time output remains untested.

Exact package mapping and kexec build exclusion are now assessed offline. Do not
repeat broad package/ownership discovery. Source analysis does not prove a future
panic or post-reset health result.

Then establish the candidate-specific reset interval and uncertainty, retain
exclusions of alternate reset paths, and prepare one exact guarded attempt with
fresh ownership/panic/peer checks. If evidence cannot distinguish the cause,
qualify only observed recovery and leave hardware attribution open. Do not claim
that the source analysis has completed live qualification.

## Availability and precision requirements

Use the separate stages in the [current recovery contract](CONTROLLED-PANIC-REVIEW.md#timing-contract):
boot/network <=60 seconds; synchronized dual-stack NTP availability <=five minutes;
up to 30 minutes for precision convergence, then 30 minutes of stability. The
five-minute availability requirement does not include steady-state offset/jitter.
Keep native source evidence and direct client replies; SSH alone is insufficient.

Record off-node monotonic intervals, last healthy observation, first independently
qualifying availability pair, precision confirmation, gaps and uncertainty. Do not
backdate convergence or availability from later samples. These service results do
not prove hardware expiry; retain the independent attribution requirements above.
On availability failure, use the reviewed attended hold/recovery plan. A precision
failure alone does not justify shutdown, media swap or reinjection. Preserve the
serving peer, antenna power, OBS-02/D1–D5 and bounded OBS-04; OBS-09 remains separate.

The [focused confirmation review](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-debugger-inputs-20261026-v1/review.md) is now sealed/unexecuted. Its scope
requires separate exact-hash execution approval; ordinary KVM confirmation did not
authorize a debugger read, configuration change or failure injection.

## Accepted debugger confirmation — October 26, 2026

The [approved snapshot](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-debugger-inputs-20261026-v1/outcome.md) captured empty normal kgdboc and no selected
normal/early debugger boot options, with panic=0 and continuity intact. Against
the exact-package registration paths, this resolves the configured transport gap
for that snapshot; no registration memory flag was directly read. Earlier pending
inspection wording above is historical. Its receipt is consumed. Ordinary KVM
identification is operator-confirmed; panic-time output remains test evidence.
Next prepare the one-use controlled-panic expiry/recovery review with fresh
preflight and timing. No trigger is authorized or recovery accepted here.
