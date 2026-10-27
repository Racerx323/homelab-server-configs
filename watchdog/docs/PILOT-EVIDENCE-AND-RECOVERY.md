# Pilot evidence path, recovery confirmations and deadlines

Status: operator confirmations retained; the
[controlled-panic review](CONTROLLED-PANIC-REVIEW.md) now defines the selected
mechanism and exact proposed deadlines. Historical unset/provisional timing below
is superseded by that review. Its executable runner is locally qualified but unapproved; no trigger
is scheduled. The five-minute usable-NTP requirement remains unchanged.

## Retained facts and confirmation status

The October 26 readiness capture completed at 11:46:49 CDT. It found stable
systemd ownership, a 60-second device timeout, volatile journal configuration and
empty pstore directories. It did not test recovery media, console access,
recording equipment, primary health or physical power isolation.

Aaron confirmed the following on October 26, 2026. These are operator reports,
not additional live inspections or a newly exercised recovery test.

| Requirement | Operator-confirmed information | Remaining execution detail |
| --- | --- | --- |
| j2 console | Workstation SSH available; KVM access available and confirmed if SSH fails | Aaron confirms ordinary KVM display identifies j2-svntp1 on October 26; panic-time visibility remains untested |
| Recovery media | Previous Debian 11 NTP server microSD card works as fallback | Record recovery identity/address and physical card availability at preflight; no new card boot performed |
| Peer NTP | j1-svntp currently serves network time and will continue during j2 outage | Fresh peer health evidence at the approved maintenance preflight |
| Shared antenna | j1-svntp powers the external antenna through its Uputronics HAT | Preserve j1 power and antenna connections throughout the attempt |
| Node power | j1-svntp and j2-svntp1 have separate PoE ports; j2 uses a Raspberry Pi PoE HAT | Identify j2 port before any approved port action; separate ports do not prove independent upstream switch/UPS power |
| Operator | Aaron is available locally; all servers are local to him | Reconfirm attendance at the chosen attempt |
| Independent console evidence | KVM connected to a separately powered laptop; smallest adequate method agreed | Timestamped attended console notes plus off-node controller records; video optional |
| Maintenance window | Any deployment-test window acceptable; test outage may last hours to days | Normal-operation outage must not exceed five minutes; finalize trigger-specific timing |

The broad outage tolerance applies only to deployment testing. Normal-operation
outages must not exceed five minutes. A long test outage cannot pass that resilience
requirement and does not authorize an unattended or unbounded experiment.
Do not require a new media boot merely to restate Aaron's working-card confirmation;
retain the distinction between that confirmation and a dated observed recovery.
Aaron additionally confirmed j1 supplies antenna power and each node has its own
PoE port. This supports node-port separation, not immunity to a common switch or
upstream power failure. A future recovery action must affect only j2.
No peer/controller/switch inspection is authorized by this record.

## Independent evidence path

Use the confirmed KVM connected to a separately powered laptop, with Aaron
observing and writing timestamped notes. Combine those notes with the off-node
controller command/receipt log and approved pre/post checks. Video is optional;
no new recorder or logging installation is required. The
[attribution qualification](PILOT-RESET-ATTRIBUTION.md) defines what these observations
can establish and the remaining source/runtime gaps.

Confirm the console identifies j2 and that notes/controller records survive loss
of its network/power. Do not repurpose the GPS UART, alter boot overlays or shared
power to obtain evidence. If kernel messages are not visible, resolve that gap
before the trigger; a console change or reboot is a separate reviewed action.
Do not rely solely on SSH, notifications, volatile journals or empty pstore.

The controller-side evidence directory must be unique and owner-private. Retain:

- Approved review/specification hashes, host/device identity and one-use receipt.
- Preflight clock comparison and laptop identity/power/storage confirmation.
- Original timestamped operator notes and controller event log, including gaps;
  preserve any optional captures used.
- Separate submission and confirmed-trigger events; never manufacture an exact
  trigger time from a lost SSH session. Unknown submission still consumes the attempt.
- Reset/boot observations, authorized post-boot reason evidence, new boot identity,
  health results and all operator interventions with timestamps.
- Closed-file sizes/hashes and a manifest linking originals to any redacted copies.

Use monotonic controller elapsed time for deadlines and UTC wall time for
correlation. Record clock disagreement; do not adjust clocks during the attempt.
If the console evidence uses a different clock, record a shared visible marker and measured
uncertainty before the trigger. Preserve buffered/partial files after interruption;
do not replace them with a clean replay. Keep raw evidence private and avoid
recording credentials or unrelated screens. No recording has started in this work.

## Attribution rule

Before selecting a trigger, qualify the installed mechanism and a specific
independent attribution method. The later review must establish cessation of
keepalives, distinguish normal reboot/power intervention/other reset paths, and
identify the hardware watchdog's contribution. Console output plus appropriate
reset-reason evidence may support that claim only when the native platform's
semantics are established. Timing alone, panic visibility, SSH loss or a new boot
ID is insufficient. An operator recovery/power action before attribution is
resolved makes hardware-expiry acceptance inconclusive, even if service recovers.

If the available independent path cannot establish attribution, stop and design
an alternative. Do not enable persistent journaling, configure pstore or introduce
an owner-handoff harness without its own reviewed change and restoration plan.

## Proposed deadlines for agreement

These are conservative operational proposals, not measured boot/recovery promises
or an accepted hardware-reset timing specification. Aaron accepts hours to days of outage and any maintenance window. The proposed
short test checkpoints below remain operational acceptance/escalation limits,
not permission to pass a normal-operation outage longer than five minutes; freeze
them in the later execution review.

Define T_submit as the first trigger submission, T_reset as independently observed
reset, and T_healthy as the start of sustained accepted health. Record T_confirmed
only if evidence establishes trigger completion. One deliberate attempt maximum.

| Checkpoint | Proposed limit | Response if not satisfied |
| --- | --- | --- |
| Fresh preflight | Finish within 15 minutes before T_submit; recheck critical ownership and peer/power assertions immediately before submission | Do not trigger on stale/drifted evidence |
| Evidence baseline | Identify console, clocks and healthy service before T_submit | Do not trigger without usable independent notes/controller evidence |
| Hardware expiry acceptance interval | Unset until mechanism, effective timeout and attribution are qualified | Cannot seal a trigger without a justified interval; 60-second device timeout alone is insufficient |
| Reset observation escalation | T_submit + 2 minutes, provisionally | Stop automatic progression; operator assesses via console under the agreed manual-recovery plan; no reinjection |
| Console/boot access | Observe continuously; a console alone is not restored NTP service | Retain timeline; invoke only reviewed recovery if required |
| Usable NTP service | Within 300 seconds of outage onset; conservatively use last confirmed healthy time if onset is uncertain | Five-minute resilience acceptance fails if exceeded or unproved; hand over to attended restoration/hold |
| Stability observation | At least 30 continuous minutes from T_healthy, with no further reset and required health evidence | Any reset or material evidence gap prevents pass; preserve the interval for disposition |
| Maintenance reservation | Propose 90 minutes with an attended recovery margin | If the operator's window cannot cover the attempt and agreed fallback, do not start |
| Failed-test handoff | At the health deadline above, record failure and hand control to the attended recovery/hold plan | Aaron accepts hours to days of outage; name the recovery owner and next check time before any extended hold |

The two-minute escalation proposal is not a claim that the hardware should reset
at two minutes and is not a substitute for the qualified expiry interval. Exact
health probes, thresholds, permissible evidence gaps and restoration bounds must
come from the owning NTP acceptance contract and be frozen with execution inputs.
OBS-09's final observation interval remains separate from this 30-minute proposal.

## Stop, interruption and restoration

Before trigger, any missing operator, peer/power check, evidence path, recovery media,
window or approved deadline stops the attempt. No automatic fallback to another
host, trigger, timeout or recorder. No persistent/repeating failure job.

After submission, a controller or console-evidence interruption does not authorize retry.
Aaron uses the independent console and the pre-reviewed manual-recovery path.
If power isolation is uncertain, do not improvise a power-cycle. Keep primary and
antenna power unchanged. A second reset or suspected boot loop is a failed test,
not another trial; further intervention follows the approved console/media plan.

Old-card recovery must account for its original Debian 11 hostname/configuration
and present hardware. Do not apply new-image files to the old card as an assumed
rollback. Record restored service identity and client health before claiming
recovery. No software rollback can be promised while the node is inaccessible.

## Next decision

Approve the separately sealed executable review recorded in [history](../HISTORY.md)
only after reviewing its exact hash and scope. Complete the fresh operator record
at execution preflight; the prior planning confirmations are retained, not
fabricated as current observations. No live recovery has occurred. No additional
broad discovery or target contact is authorized by preparation. OBS-02/D1–D5 and
bounded OBS-04 remain unchanged; OBS-09 has not started.
