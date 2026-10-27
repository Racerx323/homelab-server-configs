# NTP pilot watchdog adoption and recovery contract

Status: implemented pilot controls; live recovery unaccepted. The
[single controlled-panic contract](CONTROLLED-PANIC-REVIEW.md) defines timing,
evidence and restoration. The guarded runner is locally qualified; its sealed
executable review requires separate exact-hash approval. Earlier unselected-trigger
and implementation-pending handoffs below are historical; see [history](../HISTORY.md).

Owner: Aaron. Component: fleet [watchdog](../readme.md). Pilot: inventory host
`j2-svntp1` only. Other hosts, controller policy, shared antenna power and primary
DNAT remain outside the operation. Follow the NTP
[readiness checklist](../../../homelab-ntp/ntpsec/docs/PRODUCTION-READINESS.md)
and [governing plan](../../../homelab-ntp/ntpsec/docs/ntp-architecture-deployment-plan-v1.0.md).

## Baseline and adoption boundary

The October 26 accepted passive snapshot identifies PID 1/systemd holding
watchdog0, with runtime/reboot values 60/120 seconds and matching selected
vendor-path assignments. See [history](../HISTORY.md) for provenance and limits.
No standalone daemon or changed timeout is proposed. Preserve this owner while
qualifying adoption; the platform's already-active watchdog is an observed fact,
not a newly approved enablement or recovery result.

Repository-only adoption may record intended policy and compare retained facts.
It cannot claim full-file mirroring, feeding cadence, persistence or reset
acceptance. The first ownership inspection exported selected assignments only. The later
readiness capture retained exact hash-matched vendor bytes and package ownership;
that still does not prove restoration or recovery. Any later local override remains a separate
reviewed change with exact restoration inputs.

## Acceptance objective

Distinguish three claims:

1. **Policy/ownership:** the intended owner and effective timeout agree with the
   qualified per-host policy, with no conflicting owner.
2. **Independent recovery:** the operator can restore access using a verified
   node-specific console/media path without relying on this node or interrupting
   primary/shared-antenna power.
3. **Hardware expiry and service recovery:** one intentional, approved keepalive
   loss produces a hardware-watchdog-attributable reset and the node returns to
   accepted NTP/GPSD/network/monitoring health without repeat resets.

An ordinary reboot proves neither watchdog expiry nor recovery from a stalled
owner. A per-service watchdog test proves only that service's recovery path.
Loss of SSH or a changed boot ID alone cannot attribute a reset to the hardware
watchdog. Bootstatus=0 is not proof of a watchdog reset.

## Facts required before selecting the trigger

The [recovery-readiness capture](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-recovery-readiness-20261026-v1/outcome.md) completed on October 26; its receipt is
consumed. Installed versions, vendor ownership, panic policy and selected kernel
configuration are now retained. Volatile journal configuration and empty pstore
leave evidence survival/reset attribution unproved. The later accepted debugger snapshot closes the configured transport gap.
Operator recovery confirmations and the independent evidence plan are retained;
the controlled-panic design now supplies the selected trigger and deadlines.
Further target inspection requires a new scoped approval. Reuse retained evidence
where sufficient. The following list defines relevant evidence categories; it
is not a request to repeat the completed capture. Any remaining inspection must
specify exact paths, bounds, fields and sensitive-data exclusions:

- Installed systemd/kernel/driver versions and documentation; package ownership
  and exact relevant configuration inputs, including effective overrides and
  whether retained settings remain current.
- Watchdog capabilities and observed close/nowayout behavior from documentation
  and existing metadata, without opening a device or exercising an ioctl.
- Existing panic/reboot policies and kernel configuration relevant to a candidate
  failure mechanism; evidence that an alternative automatic reset would not make
  the result ambiguous. No sysctl writes, SysRq, panic or signal during inspection.
- Boot/reset-reason and journal persistence facilities, including whether the
  reset source can be distinguished after failure. Preserve selected evidence
  off-node before disruption; do not assume all journals survive a reset.
- Host-local service/boot/media recovery inputs required by the NTP procedure.
  Inspections of a peer, master, controller or switch need separate scopes.

Operator prerequisites are separate from target metadata. Aaron confirms local
attendance, KVM access through a separately powered laptop, a working previous
Debian 11 card, j1 serving time/powering the antenna and separate node PoE ports.
Recheck availability at execution preflight. Use timestamped attended console notes
and controller evidence; video is optional. See the
[attribution analysis](PILOT-RESET-ATTRIBUTION.md) for remaining technical inputs.
Normal-operation NTP outages must not exceed five minutes; hours-to-days tolerance
applies only to deployment testing and cannot count as a resilience pass.

## Trigger-selection gate

Prefer a documented native mechanism that proves loss of hardware keepalive while
preserving the qualified owner and avoiding a new daemon/ownership handoff.
Select it only after the installed platform's behavior and evidence path are
understood. Do not use a CPU-load threshold as a proxy for a stalled watchdog.
Do not assume killing/stopping PID 1, opening a second descriptor, closing the
owner or inducing a kernel panic has a safe or diagnostic result.

The controlled-panic review now carries the selected native mechanism,
off-node evidence, crash/write risk and attribution controls. It remains
**unexecuted and unauthorized**; selection does not establish live recovery. If no supported unambiguous mechanism
is available, record that blocker and propose a dedicated maintenance/lab path.
Do not substitute a successful reboot or synthetic fixture for hardware acceptance.

## Required executable-review fields

All rows must have concrete reviewed values before sealing execution:

| Field | Requirement | Current disposition |
| --- | --- | --- |
| Scope and artifact | Exact host identity, executable/configuration bytes and approved SHA-256 | Pilot identified; exact executable artifact recorded in history |
| Preconditions | Fresh ownership/timeout, stable services/files, operator access and peer/power checks | Retained baseline only; fresh confirmation still required at execution preflight |
| Trigger | Exact one-use command, mechanism, permissions and attribution rationale | Single SysRq panic selected in linked review; guarded worker implemented; live approval pending |
| Timing | Earliest start, expiry, hardware-reset tolerance, boot/access/health deadlines and observation duration | Normal-operation outage must not exceed 300 seconds; deployment testing may take longer; 30-second observed-reset criterion and 120-second escalation proposed in linked review |
| Abort | Checks that stop before injection, operator stop path and post-trigger contingency | No blind retry; post-trigger SSH loss is expected, not a reason to reinject |
| Interruption | Durable consumed receipt and armed/triggered state; controller-loss/manual-recovery instructions | Receipt must precede trigger; uncertain submission consumes the attempt |
| Restoration | Exact original files/metadata and safe application method for any temporary setting | No permanent change proposed; any required temporary input must be bound and restored |
| Evidence | Independent timestamps, trigger record, owner/timeout, reset attribution, new boot and health | Attended KVM notes and controller records defined; unknown attribution cannot pass |
| Communications | Planned outage contacts and exact approved messages if any | No new sends approved; disclose possible existing monitoring alerts in the live review |
| Completion | Post-recovery observation interval, no repeated resets, residue checks and operator decision | Recovery acceptance remains pending |

One deliberate trigger maximum. Do not schedule a repeating job or boot-persistent
failure trigger. Before trigger, a failed preflight stops without changing policy.
After trigger, cancellation cannot be assumed possible: use the reviewed console
and media recovery path. Do not automatically rerun on timeout, lost connection,
missing evidence or a controller restart. Any unplanned subsequent reset ends
acceptance and invokes the reviewed manual recovery path.

## Health, restoration and closure

After the reset, collect authorized independent evidence of watchdog attribution,
new boot and stable ownership/timeout. Verify the owning NTP acceptance criteria:
GPS/PPS/source selection and timing, IPv4/IPv6 client responses and access policy,
service startup, network persistence, reporting/retention and Munin collection.
Exact probes, thresholds and duration must be carried into the executable review;
existing NTP acceptance is not permission to contact every client or master.

Restore only operation-owned temporary changes, verifying prior bytes, metadata,
effective settings and absence of trigger residue. A failure may require console
recovery or the preserved-media path; no generic remote rollback is promised.
No power-cycle instruction may affect shared antenna equipment or the primary.

Close only after the full evidence/deadline/health contract and operator acceptance.
If attribution, recovery or restoration cannot be proved, retain an incomplete or
failed outcome and stop further rollout. Keep policy adoption, independent recovery
and controlled expiry acceptance separate. OBS-02/D1–D5 and bounded OBS-04 remain
unchanged. Final OBS-09 observation does not begin automatically after this test.
