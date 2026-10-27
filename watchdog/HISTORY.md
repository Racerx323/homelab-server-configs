# Watchdog history

## Native update completed; final timing recovered with an earlier miss — October 27, 2026

The [v5 outcome](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-update-20261027-v5/outcome.md)
records all 22 approved upgrades completed at 12:51:57 CDT, exact inventory/clean
dpkg audit, unchanged protected inputs and verified generated initramfs. The ALSA
override passed native validation and its old errors are absent on the new boot.
One reboot returned both fixed-address PPS/stratum-1 clients within about 99 seconds.
Owned EEPROM/APT controls were removed; original APT timers and firmware policy
were restored. No firmware flash, second reboot, fallback or manual send occurred.

The +5-minute sample failed offset/jitter limits (15.1021 ms / 18.0712 ms).
At 13:25:56 CDT the +30-minute sample passed (-2.0126 ms / 0.0630 ms) with stable
service identities and active PID1 watchdog. Accept the completed package/ALSA
maintenance and final healthy snapshot; retain the failed five-minute precision
criterion and unproved continuous timing stability. Aaron confirmed transport
CRITICAL/OK and timing CRITICAL receipts, later jitter-only, then timing OK
reported at 13:20 CDT. The timer listing records a leap trigger, not
its service result; OBS-06 remains open with partial evidence.

The receipt preserves a controller sequencing deviation: approved read-only
preflight preceded receipt creation after a local manifest-count assertion;
all 70 archive members were verified before mutation. Both bounded evidence
exports, original failures and all consumed stages/backups remain. Earlier
unexecuted and controls-held wording is historical; no replay is permitted.

Next reconcile the new baseline and delayed precision recovery before a watchdog
successor. OBS-02/D1–D5 and bounded OBS-04 remain unchanged; panic/OBS-09 and the
other final-observation requirements remain open.

## Native APT cause reproduced; retained-control continuation sealed — October 27, 2026

The [v5 review](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-update-20261027-v5/review.md)
is sealed and unexecuted, SHA-256
`56590b00c2ba74a2ab7749a01ec934d8f47ac0a0479455c795ecfe318a107be0`. APT 3.0.3's canonical cache-name lookup explains
v4's relative installation pathname: short package.deb names with --no-download
passed simulation but failed the actual install path. Offline same-version APT
reproduced the error. The reviewed tzdata payload then actually installed using
the canonical filename; all 22 exact payloads passed native path processing with
dpkg intentionally suppressed for ARM qualification. No target script/firmware
acceptance is inferred. Package bytes, versions and download prohibition are unchanged.

V5 retains v4's verified controls using frozen ownership records and new
repository-owned check/restoration code. Wrong ownership or republishing is refused.
Its exclusive stage/intent/unit is separate; all consumed evidence is preserved.
Forty-three focused tests and shell/Python/Markdown/integrity checks passed.
No target contact occurred. Next exact-hash approval and fresh attendance within
the original window: latest start 15:42:16 CDT, metadata expiry 17:12:16 CDT.
OBS-02/D1–D5 and bounded OBS-04 unchanged; base OS/ALSA open, panic/OBS-09 held.

## Native update v4 held after APT exit 100 — October 27, 2026

The [v4 outcome](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-update-20261027-v4/outcome.md)
records successful complete baseline health, dual-stack client checks, backup/input
verification, native simulation and owned containment. At 12:13:29 CDT the single
APT job exited 100 because an installation pathname was not absolute, before
unpacking. The successful simulation did not exercise this install-time path.

Held-state checks proved the package inventory, dpkg status, backup/boot and
protected files unchanged. No package job/lock remains; PPS/stratum-1 time service,
cron and Munin continue. EEPROM inhibition and four APT masks remain under the
post-intent failure branch; automatic APT timers are stopped/masked. No retry,
ALSA publication, reboot or fallback occurred. Thirteen stage evidence files were
exported and hashed. Preserve the consumed stage and receipt.

Next assess the native local-file failure and qualify continuation or explicit
owned-control restoration; do not replay v4. Metadata expiry remains 17:12:16 CDT.
Earlier unexecuted wording is historical. OBS-02/D1–D5 and bounded OBS-04 remain
unchanged; base OS/ALSA open and panic/OBS-09 held.

## Native command paths corrected; v4 continuation sealed — October 27, 2026

The [v4 review](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-update-20261027-v4/review.md)
is sealed, unexecuted and awaiting approval, SHA-256
`b4201bcc03a87a86546172b4e662f15dc7e136a1792ceda89007a03b7ba2a951`. The wrong health-script path was a preparation
error: retained successful node evidence already used `/usr/bin/ss`.
The corrected command set checks all 37 native executable paths and completes
baseline health before staging. The consumed v3 stage and partial evidence stay
intact. V4 uses a new stage without changing the package delta, backup or recovery
scope. No target contact occurred during preparation.

Forty-one focused tests and final shell, Python, Markdown, secret and integrity
checks passed. The command audit distinguishes retained native proof from future
runtime checks; it does not claim update/reboot acceptance. Next obtain v4 approval
and fresh attendance within the unchanged window: latest start 15:42:16 CDT,
metadata expiry 17:12:16 CDT. OBS-02/D1–D5 and bounded OBS-04 unchanged;
base OS/ALSA open and panic/OBS-09 held.

## Native update v3 held before containment — October 27, 2026

The approved [v3 attempt](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-update-20261027-v3/outcome.md)
passed cleanup preflight, frozen input/backup checks, native 22-upgrade simulation
and ALSA parsing. Baseline health then exited 127 at the incorrectly authored
`/usr/sbin/ss` path. Partial evidence is retained; later health fields are unproved.
Both fixed-address client probes passed independently.

Only private staging and evidence files were created. No maintenance controls,
packages, ALSA override, reboot or retry occurred. The consumed archive and both
retained stages remain unchanged. Next audit/correct the health paths and qualify
a continuation, with new approval for changed execution bytes. Original metadata
expiry remains 17:12:16 CDT. OBS-02/D1–D5 and bounded OBS-04 unchanged;
base OS/ALSA open and panic/OBS-09 held. Earlier unexecuted wording is historical.

## One attended native maintenance review sealed — October 27, 2026

The [v3 review](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-update-20261027-v3/review.md)
is sealed and unexecuted, bound to
`b981ae109026ad4425f078cfc5aaf89d9ac7415260ba74872a62d7f8ffafc638`.
One scope covers cleanup/state preflight, the fixed native APT transaction, a
conditional reboot, health checks, owned restoration and operator-selected card
fallback. The retained v2 stage stays intact. No old installer is replayed and
no target contact occurred during preparation.

Forty-one focused tests passed. Native local condition JSON and systemd unit
parsing, shell/formatting, Markdown, source/member/package integrity and secret
checks passed. Runtime checks remain mandatory. The new condition parser checks
structured tuples instead of systemctl's unprintable text. APT runs once in a
native transient job with durable output and no automatic retry or kill timeout.

Next obtain exact-hash approval and fresh attendance, then execute the attended
runbook. Latest start is October 27 at 15:42:16 CDT; original metadata expiry is
17:12:16 CDT. No deadline extension is implied. OBS-02/D1–D5 and bounded OBS-04
unchanged; base OS/ALSA open and panic/OBS-09 held pending actual results.

## Local maintenance simplification assessed — October 27, 2026

Aaron approved stepping back from repeated inspection/approval cycles. The
[consolidated plan](../../homelab-ntp/ntpsec/docs/MAINTENANCE-SIMPLIFICATION.md) records the missed base-OS
commissioning gate, the two runner defects and the limits of prior local tests.
It proposes native APT with one bounded update/reboot/verification/recovery scope,
retaining independent backups, exact package policy and EEPROM containment.
Cleanup verification becomes preflight; generated boot hashes are assessed within
the approved operation instead of automatically requiring a new approval.

This is repository-only preparation. No target contact, mutation, notification,
reboot or retry occurred. Consumed stages and raw evidence remain unchanged.
Next qualify the concise runbook, resolve hook/native-condition checks and
metadata freshness, then seal one executable review. A material scope change or
failed recovery predicate still stops execution. OBS-02/D1–D5 and bounded OBS-04
remain unchanged; base OS/ALSA remain open and panic/OBS-09 held.

## Update v2 stopped before package intent — October 27, 2026

The [v2 outcome](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-update-20261027-v2/outcome.md)
records verified independent backups and successful preflight, exact native solver
and ALSA parser checks. Temporary controls were published, but the EEPROM query
returned `Conditions=[unprintable]`. The substring guard rejected that response;
absence of the effective condition is not established. No package installation,
ALSA override publication, firmware invocation, reboot or retry occurred.

Cleanup reported owned controls removed; reload and both APT timer-start commands
returned zero. No independent post-cleanup state/health snapshot exists. The stage
and backups remain, and the receipt is consumed. All 130 exported evidence files
were hash-verified. Earlier sealed/unexecuted wording is historical.

Next prepare a scoped read-only post-cleanup/native-condition inspection. Qualify
the condition representation and explicit stage-preserving continuation before
another update review; reassess metadata freshness. OBS-02/D1–D5 and bounded OBS-04
unchanged; base OS/ALSA open and panic/OBS-09 held.

## Corrected pre-reboot update successor sealed — October 27, 2026

The [v2 review](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-update-20261027-v2/review.md)
is sealed and unexecuted, bound to
`d17188503a2be51dfb250eaba12199b5f98527568ba079c333db24a2efc96112`.
It replaces the incorrect standalone GPSD requirement with the accepted combined
lifecycle and validates both baseline service snapshots during sealing/checking.
Both preflight paths retain completed evidence on failure; the controller saves
failed backup reports before rejecting transport. Incomplete backup cannot reach
installation. Consumed v1 evidence remains unchanged.

All 48 focused tests passed, including contradictory-baseline and partial-evidence
regressions. The retained baseline, 22 payload identities, rendered payloads and
native local mask restoration passed qualification. No target contact occurred.
Next obtain fresh exact-hash approval and current operator confirmation; latest
start remains October 27 at 16:12:16 CDT. No deadline extension, reboot, package
retry or live acceptance is implied. OBS-02/D1–D5 and bounded OBS-04 unchanged;
base OS/ALSA open and panic/OBS-09 held.

## Pre-reboot update stopped at incorrect service guard — October 27, 2026

The approved [v1 attempt](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-update-20261027-v1/outcome.md)
consumed its receipt and stopped during the first read-only connection. The guard
required active gpsd.service although the frozen baseline records it absent and
the accepted design runs GPSD under timeservice.service. Qualification missed
this contradiction. No package-stage connection, backup export, package change,
control installation, ALSA override, reboot or retry occurred.

The raw traceback is retained; partial collector data was not exported. Current
complete health is not established by this attempt. Next correct and qualify the
guard, audit remaining preconditions against the retained baseline, retain partial
failure evidence, and seal a successor for fresh approval after checking metadata
freshness. Do not replay v1. Earlier sealed/unexecuted wording is historical.
OBS-02/D1–D5 and bounded OBS-04 unchanged; base OS/ALSA open, panic/OBS-09 held.

## Guarded pre-reboot update review sealed — October 27, 2026

The [execution review](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-update-20261027-v1/review.md) is sealed and unexecuted, bound to
`6ebba32d31948716ffa77426e3a3bcee6225cafcc4c687f6d61777466b2b5650`. Latest controller start is October 27 at
16:12:16 CDT, with fresh operator confirmation. No new target contact occurred.
The previous input-inspection checkpoint is superseded; its accepted evidence and
consumed receipt remain intact.

The scoped stage verifies independent backups before any package change, binds
all 22 authenticated upgrades, preserves source/key/pin and automatic/manual
package policy, and publishes the native-parser-qualified ALSA override. Persistent
EEPROM and automatic-update controls survive interruption and remain at the
pre-reboot stop. Package failure retains controls; no generic repair, replay,
notification, panic or reboot is included.

Forty-three focused tests passed. Native local persistent-mask/condition checks,
exact retained target solver parsing, payload identity checks, shell policy,
Markdown, whitespace and working-tree secret checks passed. File-level backup and
restoration tests do not prove FAT crash recovery or post-reboot NTP acceptance.
The runner reuses only the qualified durable command primitive, not the consumed
foundation installation.

Next obtain exact-hash approval, execute once and assess the native output. Only
then bind generated initramfs identities into a separate reboot/restoration review.
The skipped EEPROM oneshot may remain inactive after later policy restoration;
never invoke it just to restore a label. OBS-02/D1–D5 and bounded OBS-04 unchanged;
base OS/ALSA acceptance open and panic/OBS-09 held.

## Successor installed-effects inspection accepted — October 27, 2026

The [inspection outcome](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-effects-inspection-20261026-v2/outcome.md)
records one completed read-only execution at 08:57:22 CDT. Protected state and
all five repeated input groups matched; required commands passed and dpkg audit
was empty. The archive and predecessor outcome remain unchanged; the receipt is
consumed. Earlier sealed/unexecuted wording is historical.

Trigger receivers, firmware defaults, full shared initramfs tree, helper
bookkeeping and eight boot hashes are captured. Only ama's user manager was
present; its Connect units were inactive. Initramfs watchdog-disarm and first-
boot/resize paths require explicit command-line disposition in update/reboot
qualification. Hashes do not establish recoverable off-node backups.

Next finish guarded update/recovery qualification and seal a separate execution
review. No package, containment, service, firmware or reboot action occurred.
OBS-02/D1–D5 and bounded OBS-04 unchanged; base OS/ALSA open, panic/OBS-09 held.

## Referenced inputs scoped; containment locally qualified — October 26, 2026

The [successor read-only review](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-effects-inspection-20261026-v2/review.md) is sealed, unexecuted and awaiting
approval bound to `07ffadecf903972bd4abc86dc23cd78aef158edd1b245589f9abe833e739dd29`. Start before October 27, 2026 at 17:55:04 CDT, with transport margin.
It binds the accepted installed-effects capture rather than replaying the
consumed resolution or inspection. No new target contact or mutation occurred.

Coverage includes installed trigger receivers, firmware defaults, full shared
initramfs tree, modprobe/ld.so configuration, helper bookkeeping, boot artifact
hashes and bounded existing user managers. These target facts remain unresolved
until approved execution and assessment; no current-node closure is claimed.

Nine focused and fourteen shared snapshot tests passed. The actual captured
helper, exact vendor unit and real controller systemctl in an isolated root
preserved the inhibit drop-in/marker through helper actions. Native condition
checks proved absent/present/restored eligibility only, not live manager/reboot
behavior. The containment/recovery contract defines durable publication,
interruption handling, independent boot backups and restoration limits, including
the skipped oneshot's potentially inactive state. No updater was invoked.

Next accept the scoped native inputs and finish guarded update/recovery
qualification before sealing update execution. Operator-confirmed old-card
10.1.0.51 remains an exclusive replacement; usable-NTP/firmware restoration is not
proved. OBS-02/D1–D5 and bounded OBS-04 unchanged; base OS/ALSA open, panic/OBS-09 held.

## Installed-effects inspection accepted — October 26, 2026

The [outcome](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-effects-inspection-20261026-v1/outcome.md) records one completed read-only execution at October 26, 2026 at 17:44:52 CDT.
Protected state and collected input records matched before/after; dpkg audit was
empty. No updater, package script, service mutation, notification or reboot ran.
The previous sealed/unexecuted entry below is superseded as current status; the
archive and preparation evidence remain intact and the receipt is consumed.

Running bootloader timestamp matches the September 23 default candidate image;
SPI/configuration identity is not claimed. Ama's Connect units were inactive and
service/path disabled. Installed control files match the inspected candidates,
except one comment-only trigger difference. Two redacted Connect script texts
were resolved by matching their raw-file hashes to authenticated candidate bytes.

Next qualify guarded maintenance/EEPROM containment and exact restoration,
including the remaining initramfs/firmware-default/trigger-receiver references and
other affected user-manager scope. Automatic initramfs .bak retention is disabled;
independent recovery is required. Old-card address 10.1.0.51 is operator-confirmed
for exclusive replacement, not proof of usable-NTP or firmware recovery.
OBS-02/D1–D5 and bounded OBS-04 unchanged; base OS/ALSA open, panic/OBS-09 held.

## Installed-effects inspection sealed; recovery address confirmed — October 26, 2026

The [read-only inspection review](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-effects-inspection-20261026-v1/review.md) is sealed and unexecuted,
bound to [SHA-256](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-effects-inspection-20261026-v1/sealing.json) `85477914fad8e40e237bfc07fb6aee7ef6f271d812f4e4a9e271083e0005bc96`.
Scope approval is recorded; this newly frozen bundle requires exact-hash execution
approval. Start before October 27, 2026 at 17:36:16 CDT, with transport margin.
No target contact, service change, package action, reboot or notification occurred.

Seven focused tests plus fourteen shared snapshot tests passed. The new collector
retains partial evidence, forbids credential content reads, rejects indirect paths,
and compares collected inputs and protected state before/after. Native controller
condition evaluation proves only marker-condition rejection and restoration of
eligibility; full target containment/restoration is not yet qualified.

Aaron confirms the prior card uses 10.1.0.51, the same address as the rebuilt node.
Its previously reported hostname is j1-svntp1. The card must replace the current
node exclusively; never run both at that address. Address discovery is resolved
by operator attestation, not independent network verification. DHCP/static mode,
usable-NTP recovery and firmware restoration remain separate unknowns.

Next execute the approved-hash inspection, assess installed helpers/hook references,
then qualify containment through package configuration/reboot and exact restoration.
OBS-02/D1–D5 and bounded OBS-04 unchanged; base OS/ALSA completion open, panic/OBS-09 held.

## Exact package effects assessed — October 26, 2026

The [controller-only assessment](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-payload-assessment-20261026-v1/assessment.md) covers all 22 hash-bound candidate
payloads; 20 control scripts passed syntax-only checks. Public downloads were
retained privately. No node contact, package code execution, installation or
reboot occurred. Old EEPROM updater/config/default/unit members match captured
installed hashes; the old package is a comparison reference, not rollback proof.

EEPROM postinst requests updater restart during configuration. The Pi 4 default
firmware files are unchanged, but actual running EEPROM state is not established.
The updater may remove/stage boot files; its new pending-state path also disables
suspend until reboot. ntfs-3g triggers initramfs regeneration and Connect requests
user-service restarts, independently of list-only needrestart policy.

Next prepare the scoped installed-script/hook, firmware-state and user-unit
inspection, then qualify containment/restoration and resolve recovery-media
identity before sealing update execution. Base OS/ALSA completion stays open;
OBS-02/D1–D5 and bounded OBS-04 unchanged; panic and OBS-09 remain held.

## Isolated metadata resolution accepted — October 26, 2026

The [accepted outcome](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-metadata-resolution-20261026-v1/outcome.md) records completion at October 26, 2026, 17:12:16 CDT.
Five signed Release records and 19 Packages indexes passed validation. Native and
Python APT agree on 22 upgrades, with zero additions/removals/downgrades, holds or
kept-back candidates. Webmin source/key/pin remain intact; Webmin is not selected.
The plan includes `rpi-eeprom` 28.33-1 to 28.34-1, requiring package-script,
firmware and update-on-boot recovery assessment before update/reboot approval.

Protected configuration/package state, live APT lists, services/runtime and boot
identity remained unchanged; owned scratch was removed. No package installation,
service change, reboot or retry occurred. The prior sealed/unexecuted entry below
is preparation history, superseded by this accepted execution outcome.

Next prepare payload/script/hook assessment and explicit EEPROM/recovery controls,
then a guarded update/ALSA correction/post-update verification review. This is not
base OS completion. OBS-02/D1–D5 and bounded OBS-04 unchanged; panic/OBS-09 held.

## Isolated full-update metadata resolution sealed — October 26, 2026

The [execution review](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-metadata-resolution-20261026-v1/review.md) is bound to
[SHA-256](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-metadata-resolution-20261026-v1/sealing.json)
`a10bafed79bf099de75ac7739dc2198d1a15dcda88e6d362d4dc5325b88c7ee4`. Sealed, unexecuted and awaiting separate approval.
Start before October 27, 2026, at 16:21:11 CDT, with transport margin. No target
contact, remote repository access, package action or firmware/service change.

The dedicated resolver reuses authenticated-metadata primitives while preserving
the captured Webmin source/keyring and package-only origin pin. It compares native
full-update simulation with Python APT, records exact provenance and kept-back
candidates, and flags removals/additions/downgrades, NTP/GPSD conflicts and kernel/
firmware effects. Owned scratch cleanup and unchanged live state are acceptance
gates. Neither the consumed foundation installer nor snapshot is replayed.

Forty-two focused tests passed, including real local GPG/APT signature rejection,
solver agreement, pinning and package-change classifications; shell, Markdown,
whitespace and NTP working-tree secret checks passed. Native local APT 2.8.3 evidence
is partial for target APT 3.0.3; execution must establish target agreement.

The snapshot's broad sanitizer redacted four package-name rows. The accepted
journal-inputs predecessor retains unredacted inventory/selections and has the
identical before/after dpkg-status hash, also equal to the fresh snapshot. Both
records are frozen into this review, preserving package/hold evidence without a
new node inspection. One retained controller log was tightened from 0644 to 0600;
its bytes/hash are unchanged. Original executed archives remain intact.

Next approve and execute only this isolated resolution, then assess payload and
EEPROM update-on-boot/recovery effects before any update/reboot review. The EEPROM
boot unit is not changed here. OBS-02/D1–D5 and bounded OBS-04 unchanged; ALSA/base
OS completion, panic testing and OBS-09 remain open/held.

## Maintenance snapshot and native parser accepted — October 26, 2026

The approved [snapshot/parser stage](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-maintenance-snapshot-20261026-v1/review.md)
completed at 16:37:12 CDT. [Accepted outcome](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-maintenance-snapshot-20261026-v1/outcome.md)
binds the receipt/capture/transport hashes to archive
`ee1cf2b99ad83ee94e19f1375ebd259f3709cec8230c9523206675c69e5d936d`.
The one-use attempt is consumed; no replay. Original frozen artifacts and the
preparation outcome remain intact.

Native udev 257 rejected the baseline's two missing-label references and accepted
the candidate; exact scratch cleanup passed. Boot, selected configuration/package
state, APT-list metadata and service/process identities were unchanged. Package
locks were unheld at both samples and dpkg audit was empty. No metadata refresh,
package/configuration publication, service action, reboot, panic or notification.
This accepts a bounded snapshot and syntax check, not a maintenance transaction.

The capture identifies a separate reviewed Webmin source/keyring and origin pin,
arm64/armhf, no held selections, list-only needrestart with notifications disabled,
and an EEPROM update-on-boot unit. Exact package/hook/firmware effects remain open.
Next qualify and seal isolated signed-metadata/full-update resolution with these
inputs; do not substitute the old pinned-foundation solver or drop Webmin silently.
Resolution needs separate approval. OBS-02/D1–D5 and bounded OBS-04 unchanged;
ALSA deployment, base OS completion, panic testing and OBS-09 remain open/held.

## Maintenance snapshot/parser qualified and sealed — October 26, 2026

The [executable snapshot review](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-maintenance-snapshot-20261026-v1/review.md) is bound to
[SHA-256](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-maintenance-snapshot-20261026-v1/sealing.json)
`ee1cf2b99ad83ee94e19f1375ebd259f3709cec8230c9523206675c69e5d936d`. Sealed, unexecuted and awaiting its own scoped
execution approval. This is preparation only; no target contact or metadata
refresh occurred. The earlier maintenance draft remains review-only.

The dedicated collector covers bounded package/configuration/hook/firmware-policy
inputs, package concurrency, protected service processes and native static ALSA
parsing in exclusive private scratch. Exact-inode cleanup, interruption/partial
retention, wrong-hash rejection, strict authentication and one-use receipts were
qualified locally. The exact baseline fails controller udevadm 255 and the exact
candidate passes; target-version compatibility remains unproved. Four focused
suites passed 78 tests; shell syntax, ShellCheck and canonical shfmt passed.

Next execute only after approval, review capture/cleanup and resolve missing inputs,
then qualify/seal isolated signed-metadata resolution against that accepted fresh
snapshot. Existing foundation resolution selects pinned additions; its 20 passing
regressions do not qualify a full-OS-upgrade solver. No fresh package plan is claimed.
Package scripts/firmware effects, exact maintenance recovery and affected watchdog
proofs remain later gates. OBS-02/D1–D5 and bounded OBS-04 unchanged; panic and
OBS-09 remain held. Prior entries' implementation checkpoints are superseded here.

## Base OS maintenance review prepared — October 26, 2026

The [review-only packet](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-maintenance-review-20261026-v1/review.md) is bound to [SHA-256](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-maintenance-review-20261026-v1/sealing.json)
`84d716745b6e87a15502d67d2d1916d7c0413e0799be87d8b37da074827a57df`. It explicitly has execution_ready=false and cannot authorize
an upgrade, metadata refresh, rule publication or reboot. No target contact occurred.

The packet binds the cached 22-upgrade simulation and retained inputs, exact
one-line ALSA candidate/diff, local native-parser comparison, recovery and
post-update acceptance. Controller udevadm 255 rejects the retained baseline
and accepts the candidate; node udev 257 validation is still required. Prefer a
verified fixed package; otherwise review a managed override with exact restoration
and later retirement. No package/firmware rollback is inferred from file backups.

[Prerequisites](/home/aaron/code/.local-evidence/homelab-ntp/current/base-os-maintenance-review-20261026-v1/prerequisites.md) specify the next bounded maintenance snapshot
and native-parser qualification, followed by separately approved isolated signed
metadata resolution. Effective hooks, firmware effects, exact payloads and usable
recovery-media identity remain blockers to an executable maintenance seal.
Next implement and qualify that prerequisite stage; do not request execution of
the non-executable draft. The reusable procedure is BASE-OS-MAINTENANCE.md.
OBS-02/D1–D5 and bounded OBS-04 remain unchanged; panic testing and OBS-09 held.

## Package inputs accepted; base OS maintenance remains open — October 26, 2026

The [approved read-only capture](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-journal-inputs-20261026-v2/outcome.md) completed once at 15:51:33 CDT with
stable boot, NTP process/start/invocation and package metadata. Cached-index
simulation proposes 22 upgrades, no additions/removals/kept-back packages and
no held selections. It includes security-origin packages and rpi-eeprom, but
not alsa-utils. No index refresh, installation, notification, panic or retry occurred.
The capture does not establish current repository freshness or update history.

Seven NTP startup entries pass the bounded policy with captured live provenance.
The two remaining errors are explained by the installed alsa-utils 1.2.14-1+rpt1
rule: two GOTO references to a missing alsa_restore_std label and duplicate
alsa_restore_go labels. Same-named /etc and /run overrides are absent. Do not
claim vendor-byte integrity or harmless device impact from this scope. Correct
the defect through a reviewed fixed package or minimal maintained override;
no journal exemption was applied and pending upgrades do not inherently fix it.

Next prepare reviewed base OS maintenance with fresh signed metadata, exact
transaction/hooks/firmware impact, recovery, reboot and post-update acceptance,
plus explicit ALSA correction. The governing update gate remains open; panic
qualification stays held. Requalify affected proofs after maintenance. Preserve
OBS-02/D1–D5 and bounded OBS-04; OBS-09 unstarted. The inspection is consumed.

## Base OS update requirement approved; inspection export corrected — October 26, 2026

Aaron identified the missing commissioning update requirement and approved its
addition to the governing plan. The Trixie rebuild contract now requires verified
fresh repository metadata, reviewed application of applicable base OS updates,
explicit dispositions for deferrals, required reboot and installed/running
baseline acceptance before service deployment/recovery qualification. Existing
nodes lacking this evidence require reviewed maintenance and affected-proof
requalification; historical acceptance is not rewritten. This requirement does
not authorize package changes by itself.

The [approved journal/package inspection](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-journal-inputs-20261026-v1/outcome.md) failed final JSON
export because APT-list metadata keys were Path objects. No usable structured
observation was exported; package/udev assessment remains pending. No update,
metadata refresh, panic or retry occurred. The receipt is consumed.

The one-line string-key correction and real-Path JSON regression passed with
56 focused tests. The [successor read-only review](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-journal-inputs-20261026-v2/review.md) is sealed,
unexecuted and requires fresh approval bound to [SHA-256](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-journal-inputs-20261026-v2/sealing.json):
`4c03e7e8e023efa94797a4ce272dc338a5f114bf4e77bf9b7994c49625024d28`. Scope is unchanged; consumed evidence remains intact. Read-only
package/rule inputs must be assessed before maintenance or another panic review.
OBS-02/D1–D5 and bounded OBS-04 remain unchanged; OBS-09 unstarted.

## Journal policy reconciled; update readiness inspection prepared — October 26, 2026

The reusable watchdog guard now delegates NTP startup classification to the
existing accepted classifier, with fresh current-child PID, process-start
monotonic time and service invocation. It rejects pre-origin records instead
of allowing the cutover classifier to skip them, requires context continuity,
and rejects a reached journal cap. All non-NTP errors remain blocking; no
udev exception was added. Independent native/client health gates are unchanged.
Fifty-five focused tests pass (32 guards and 23 readiness).

The [read-only inputs review](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-journal-inputs-20261026-v1/review.md) is sealed and unexecuted, bound to
[SHA-256](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-journal-inputs-20261026-v1/sealing.json)
`a18b2b7b00f4f0398cfe331e679fb84ce9499f3918e40e30508b91d8aa4471f6`. It covers exact ALSA rule/override contents and package ownership,
NTP startup provenance, the bounded journal, installed package/held selections,
a cached-index upgrade simulation, and package/list/history metadata continuity.
It performs no index refresh, installation, udev action, notification or panic.
Fresh execution approval is required; no target contact occurred in preparation.

Aaron reports many pending updates in Webmin. The October 12 foundation record
accepted seven additions and no upgrades; it does not establish a fully updated
base OS. Whether current updates were available then remains unknown. The retained
package manifest lists alsa-utils 1.2.14-1+rpt1; this is historical evidence, not
fresh installed state. Debian bug 1104719 documents matching missing-label errors
and a fix in 1.2.14-2, but the Raspberry Pi derivative and live rule bytes require
confirmation. Disposition: unresolved package-rule defect; investigate/correct or
review a narrow evidenced exception, never declare harmless from matching text.

Pause new panic sealing pending package-update and udev disposition. Any accepted
kernel/systemd update invalidates the corresponding old source/reset-path proof
and needs renewed qualification. Do not treat simulation as an upgrade approval
or fresh repository metadata. Preserve OBS-02/D1–D5 and bounded OBS-04; OBS-09
has not started. Frozen consumed attempts remain intact.

## Watchdog journal capture accepted; policy reconciliation pending — October 26, 2026

The [approved capture](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-error-journal-20261026-v1/outcome.md) completed once at 15:06:35 CDT, with matching
accepted boot and nine retained error-priority entries from the first 65 seconds
of the October 15 boot. Two concern invalid ALSA udev-rule GOTO labels. Seven
NTP messages match formats already covered by the accepted bounded minsane/NTS
startup policy in OPERATIONS. This capture does not establish the rule's device
impact, fresh NTP health, complete retention or full classifier acceptance.

The blanket watchdog journal guard overlooked existing NTP policy and was not
qualified by the metadata-only baseline. Next reconcile the bounded policy and
explicitly disposition the two udev errors before another panic seal. Preserve
provenance, timing, duplicate/count and independent health gates. No exception,
remediation, panic, notification or retry occurred. The inspection is consumed.
OBS-02/D1–D5 and bounded OBS-04 remain unchanged; OBS-09 unstarted.

## Journal inspection sealed; partial evidence retained — October 26, 2026

The [journal-only review](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-error-journal-20261026-v1/review.md) is sealed, unexecuted and awaits
[exact-hash approval](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-error-journal-20261026-v1/sealing.json):
`4a57c68bc79298d9147cf34449665385591bab0e3d46fbc9e07d89aa5fc180d9`. It reads only target identity/boot and up to 200 current-boot
priority 0–3 journal entries, with boot continuity and existing stream/time bounds.
The inspect entrypoint rejects panic purpose; panic execution rejects inspection
purpose. No target contact, notification, failure injection or retry occurred.
No new panic execution review is sealed pending assessment of the actual entries.

The prior readiness scope explicitly excluded journal message bodies and collected
configuration/storage metadata. Phase 3 collected only leap-service journal entries.
Adding a strict zero-error condition without evaluating it in that baseline was
a preparation gap. The v2 exception also discarded completed observations. The
reusable worker now exports completed full-preflight fields and failed bounded
command output before rejecting; uncollected data remains absent and partial
capture cannot pass. The zero-error guard remains unchanged pending disposition.

All 52 focused tests pass: 29 panic/inspection/retention guards and 23 readiness
tests. These are offline checks, not journal assessment or recovery proof. Before
another panic seal, newly introduced hard preflight conditions must be evaluated
against read-only evidence and unresolved conditions explicitly dispositioned.
Frozen v1/v2 artifacts are preserved. OBS-02/D1–D5, bounded OBS-04 and five-minute
usable-NTP recovery remain unchanged; OBS-09 has not started.

## Panic preflight held on current-boot errors — October 26, 2026

At 14:56:51 CDT, the approved v2 attempt authenticated successfully and ran its
read-only worker. Preflight stopped at `current boot errors require review`:
the bounded current-boot journal query at priorities 0–3 returned nonempty
output. The worker raised before emitting its accumulated capture, so the
entries and their cause/severity cannot be assessed from retained output.
The traceback establishes the failed guard, not a diagnosis of the host.

No panic was armed or submitted, no configuration change or recovery action
occurred, and no retry was performed. The execution receipt is consumed;
armed/submitted receipts are absent. Aaron was told to stand down from console
timing. The [outcome](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-panic-recovery-20261026-v2/outcome.md) preserves this hold and the earlier preparation record.

Next: prepare a scoped read-only current-boot error-journal inspection with
boot continuity, then assess the actual entries before proposing any correction
or successor. Preserve frozen artifacts and the guard; do not replay v2 or
infer that the error is harmless. Retaining partial preflight evidence should
be addressed in reusable automation before another execution review is sealed.
Watchdog recovery remains unproved. OBS-02/D1–D5 and bounded OBS-04 are unchanged;
OBS-09 has not started.

## Explicit SSH identity qualified; successor sealed — October 26, 2026

The [successor review](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-panic-recovery-20261026-v2/review.md) is sealed and unexecuted, bound to
[SHA-256](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-panic-recovery-20261026-v2/sealing.json)
`127ef29a3ec44112a04b13180f6768dbc89adc6242e0727b33d06d3710391164`. Fresh exact-hash approval and attended operator confirmation are
required. The consumed v1 archive and rejection evidence are preserved.

The controller's key has a non-default filename. The earlier runner supplied
neither an explicit identity nor the agent environment. The successor binds the
external private-key path and public fingerprint, validates owner/mode/link count
and noninteractive availability locally, and uses only that identity for every
SSH channel. Agent, password and keyboard-interactive authentication are disabled.
No private key content is bundled, hashed or logged. Native local SSH configuration
parsing passed; server acceptance remains unproved until approved live preflight.

All 74 offline tests passed (23 panic guards, 23 readiness, 13 ownership and
15 Phase 3). No target contact, panic, notification or retry occurred during
preparation. The one-use receipts, panic grant, independent KVM evidence,
five-minute usable-NTP requirement and restoration controls are unchanged.
OBS-02/D1–D5 and bounded OBS-04 remain unchanged; OBS-09 has not started.

## Approved attempt held before remote execution — October 26, 2026

At 14:41:54 CDT, the approved one-use runner attempted its first read-only SSH
observation. Authentication was rejected; the retained stderr reports
`Permission denied (publickey,password)` and the controller reports a broken
pipe. No remote worker ran, no panic was armed or submitted, and no recovery,
configuration change or retry occurred. The execution receipt is consumed;
armed/submitted receipts are absent. Current target health was not established.

The [retained outcome](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-panic-recovery-20261026-v1/outcome.md)
records the hold. Next: resolve the controller's SSH authentication inputs
locally, qualify any correction, then seal a successor for fresh approval and
attended preflight. Do not replay this attempt. The runner's restricted
environment omits SSH_AUTH_SOCK; this is a source observation, not proof of the
authentication failure's cause. Preserve OBS-02/D1–D5 and bounded OBS-04;
OBS-09 remains unstarted and watchdog recovery remains unproved.

## Guarded single-panic runner qualified and sealed — October 26, 2026

The [executable review](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-panic-recovery-20261026-v1/review.md)
is bound to [SHA-256](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-panic-recovery-20261026-v1/sealing.json)
`1bd175809c19d572137a9c1aa244ad2b47acf03fb9dc9c9a3bcb8eaf62050659`. It
contains the repository-owned one-use controller/worker, exact read-only/native
probe dependencies, accepted baseline, host pin, operator template and recovery
contract. Preparation is complete; no target contact, sync, panic, recovery,
notification or retry occurred. The former review-only archive remains intact.

Twenty new offline guard tests and 23 existing inspection tests pass locally.
Tests exercise exclusive durable receipts, archive/source/expiry rejection,
nonce/deadline controls, identity rejection through the actual streamed payload,
and a single write to a temporary regular file. They do not simulate or prove
hardware recovery. CI/pre-commit now cover the local guards; CI without the
sibling NTP checkout explicitly skips two cross-repository payload checks.

Execution still needs separate approval of the new archive's exact SHA-256 and
fresh attended preflight. Automated results leave KVM attribution, network/record
reconciliation and operator acceptance pending. Preserve five-minute usable-NTP
acceptance, qualified OBS-02/D1–D5 and bounded OBS-04; OBS-09 remains unstarted.

## Controlled-panic recovery review prepared — October 26, 2026

The [review](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-panic-recovery-review-20261026-v1/review.md)
selects one SysRq panic with unchanged systemd watchdog ownership and policy.
It defines 30-second reset observation, 120-second escalation, conservative
300-second usable-NTP recovery and 30-minute stability; precise event bounds,
one-use/interruption handling, attended KVM/controller evidence and node-only
recovery are recorded. These are proposed acceptance limits, not measured results.

Preparation is complete; the seal covers a review-only design, not an executable
operation. Implement and qualify the guarded controller/worker and health checks
before sealing executable inputs for approval. No target contact, mutation,
trigger, notification or retry occurred. Earlier native-gap/unselected-trigger
handoffs are superseded by the accepted snapshot and this design. OBS-02/D1–D5,
bounded OBS-04 and the five-minute requirement remain unchanged; OBS-09 unstarted.

## Debugger transport snapshot accepted — October 26, 2026

The approved [capture](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-debugger-inputs-20261026-v1/outcome.md) completed October 26, 2026 at 01:35:55 PM CDT, once with protected/native
continuity. Normal kgdboc is empty; selected normal/early debugger boot options are
absent; panic remains 0. Exact-package registration-path assessment resolves the
configured transport question for this snapshot, without reading kernel memory.
Aaron's ordinary KVM identification remains separate from panic-time evidence.

Next prepare one controlled panic watchdog-expiry execution/recovery review with
fresh preflight, exact reset timing, attended evidence and restoration boundaries.
No further broad discovery is needed. No trigger is authorized/executed. The capture
receipt is consumed; no device access, change, notification or retry occurred.
Five-minute usable-NTP acceptance, OBS-02/D1–D5 and bounded OBS-04 remain unchanged;
OBS-09 is unstarted. Historical unexecuted wording is superseded by this outcome.

## Focused debugger confirmation sealed — October 26, 2026

Aaron confirms ordinary KVM visibility: the displayed host is j2-svntp1.
This closes ordinary-console identification, not panic-time output or reset proof.
The [focused read-only review](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-debugger-inputs-20261026-v1/review.md) is sealed/unexecuted, bound to
[SHA-256](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-debugger-inputs-20261026-v1/sealing.json) `0bdf7809714dd9b966004d8be602c68b2fa955c8430b0f2954e104c254ce95b9`.
Start before October 27, 2026, 01:04:54 PM CDT, after separate exact-hash approval.

The existing one-use runner adds only debugger transport parameter, allowlisted
normal/early debugger-console boot tokens, panic timeout and release reads to
its ownership/protected continuity checks. No broad package/module rediscovery.
Twenty-three focused tests pass. Missing, empty and error states remain distinct;
malformed selected tokens fail rather than being silently omitted.

The prior local outcome.json/controller.log permissions were narrowed from 0644
to 0600 to satisfy the existing input guard; bytes and evidence hashes are unchanged.
No target contact, console interaction, debugger change, trigger or notification
occurred. Next execute only after approval, assess transport registration paths,
then select a trigger only if justified. Preserve five-minute usable-NTP acceptance,
OBS-02/D1–D5 and bounded OBS-04; OBS-09 remains unstarted.

## Exact package reset paths assessed — October 26, 2026

The [offline assessment](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-package-assessment-20261026-v1/assessment.md) maps linux 1:6.18.50-1+rpt1 through its descriptor,
verified source archives and 32 applied quilt patches. The exact binary package's
full config matches the retained target config hash. No package installation,
rebuild or node contact occurred; running-binary attestation and independently
trusted descriptor signature verification are not claimed.

Matched config/source resolves the absent kexec interfaces as a built-out path.
Panic=0 excludes the generic timed reboot. KGDB can intercept panic if I/O is
registered; ordinary/KDB reboot can use the same hardware reset mechanism. Narrow
remaining facts are normal/early kgdboc configuration and ordinary KVM visibility.
The consumed capture filtered out debugger boot keys, so it cannot establish their
absence. Next prepare only that focused non-mutating confirmation before selecting
a trigger. Preserve five-minute usable-NTP acceptance, OBS-02/D1–D5 and OBS-04;
OBS-09 remains unstarted. No trigger selected or execution authorized.

## Native-input snapshot accepted — October 26, 2026

The approved [inspection](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-native-inputs-20261026-v1/outcome.md) completed October 26, 2026 at 12:41:01 PM CDT, once with protected and native
continuity. Source package linux 1:6.18.50-1+rpt1 is identified; tty1 is the
configured console. Package query's nonzero status reflects absent legacy
raspberrypi-kernel, not transport failure. Crash-status paths are absent and
selected crash units are not found. Built-in KGDB/KDB support was observed, but
runtime debugger involvement and actual KVM visibility remain unproved.

Next map exact package source/patches and assess panic/debugger/reset paths offline;
only then identify any essential residual runtime scope. No trigger is selected.
Receipt consumed; prior sealed/unexecuted wording is historical. No target change,
reset, recording, send or retry occurred. Five-minute usable-NTP acceptance and
OBS-02/D1–D5/OBS-04 remain unchanged; OBS-09 is unstarted.

## Native-input inspection sealed — October 26, 2026

Prepared the [read-only review](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-native-inputs-20261026-v1/review.md) and [integrity record](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-native-inputs-20261026-v1/sealing.json).
Archive SHA-256: `744a60a44bb6cfdb0673ba5d74887d0c4931cb8da13c7a48bc89ce4ae8bd1f71`.
Start before October 27, 2026, 12:29:46 PM CDT, after separate exact-hash execution approval.
Sealed/unexecuted: preparation approval did not authorize target contact.

The existing collector now has a closed native-input scope bound to the accepted
recovery-readiness snapshot and kernel release. It captures package/source metadata,
crash-kernel/panic policy, selected console configuration, module names and relevant
unit properties, twice with continuity checks. It never reads a device or crash
payload, changes the console, loads a module, triggers failure or sends a message.
Nineteen focused tests and 28 dependency tests pass, including native scope/filtering,
release drift, snapshot drift, archive/source binding and one-use interruption.

Next execute only after approval, then assess provenance, competing reset paths
and console configuration. Actual KVM visibility and source/binary equivalence are
not automatically established. No trigger is selected. The five-minute usable-NTP
resilience requirement remains; extended testing does not count as a pass.
OBS-02/D1–D5 and OBS-04 remain unchanged; OBS-09 remains unstarted.

## Resilience requirement and attribution analysis — October 26, 2026

Aaron confirms local attendance and KVM on a separately powered laptop. The agreed
smallest adequate evidence approach is timestamped attended console notes plus
off-node controller records; video is optional. Normal-operation outages must not
exceed five minutes. Longer deployment-test downtime is permitted, but does not
pass resilience acceptance. Earlier longer boot/health proposals are superseded.

The [source analysis](docs/PILOT-RESET-ATTRIBUTION.md) distinguishes the exposed
60-second timeout from the shorter hardware countdown bridged by kernel workers.
Pinned Linux 6.18.50 reference source does not supply a usable bootstatus reset-cause
indicator. Panic is only a candidate; exact downstream provenance, competing
crash/reset paths and console visibility remain to qualify. No node contact,
recording, failure injection or reset occurred. Next resolve those narrow native
inputs before selecting the trigger and freezing a guarded review. OBS-02/D1–D5,
OBS-04 and the unstarted OBS-09 status are unchanged.

## Independent evidence and deadline proposals defined — October 26, 2026

Added the [pilot evidence/recovery record](docs/PILOT-EVIDENCE-AND-RECOVERY.md):
independently powered external console recording plus off-node controller records,
monotonic timing, uncertainty/gap retention and qualified reset-attribution rules.
No recording, target contact, persistence change or trigger occurred.

Aaron confirmed workstation SSH, available/confirmed fallback KVM, a working
previous Debian 11 NTP microSD card, j1-svntp serving the network, j2 PoE HAT power
and Uputronics HAT antenna power. Any window and hours to days of outage are
acceptable. These are operator reports; no new recovery test occurred. Recorder,
attendance and recorder independence remain unresolved. Aaron additionally
confirmed j1 powers the antenna and the nodes use separate PoE ports; upstream
switch/power independence was not claimed.
The plan's j1 primary/antenna-power role is a design constraint, not a fresh live
confirmation. svmf console access does not establish j2 recovery.

Proposed fresh preflight/recording gates, two-minute reset escalation, five-minute
boot access, twenty-minute health and thirty-minute stability intervals, with a
ninety-minute maintenance reservation. These are proposals, not native guarantees;
qualified hardware-expiry tolerance remains unset. The broad accepted outage
budget does not extend the proposed test acceptance deadlines.
Next reconcile remaining operator details and qualify the identified evidence/attribution
method before selecting a trigger. OBS-02/D1–D5/OBS-04 are unchanged; OBS-09 is unstarted.

## Recovery-readiness snapshot accepted within scope — October 26, 2026

The approved [capture](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-recovery-readiness-20261026-v1/outcome.md) executed once, completing at 11:46:49.422 CDT.
PID 1/systemd ownership and 60/120-second effective policy remain stable. The
vendor watchdog drop-in is owned by raspberrypi-sys-mods; systemd 257.13-1~deb13u1
and built-in bcm2835_wdt on kernel 6.18.50+rpt-rpi-v8 were observed. Protected
baseline and within-capture continuity passed. No live mutation or retry occurred.

Selected journald configuration is Storage=volatile; only the current boot is
listed. Both pstore directories are empty, so neither journal survival nor reset
attribution is established. Runtime panic values and selected kernel configuration
were retained, but no trigger was selected. Missing optional paths, the absent
watchdog package and empty selected service-manual excerpt remain documented gaps.

Next define independent evidence/attribution and resolve j2 console/media, operator
attendance, peer/shared-power prerequisites, native trigger qualification and
exact deadlines. Do not silently change journal persistence. Recovery remains
unready; no failure injection is authorized. The prior sealed/unexecuted entry
is historical preparation; its one-use receipt is now consumed. OBS-02/D1–D5,
bounded OBS-04 and the unstarted OBS-09 status are unchanged.

## Recovery-readiness inspection sealed — October 26, 2026

Prepared the [read-only pilot review](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-recovery-readiness-20261026-v1/review.md) and
[SHA-256](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-recovery-readiness-20261026-v1/sealing.json) under fleet component ownership. Archive:
`8c741ccc9a1343f6a2526d50a02f16660d331bfe72e76d13a82624d55b538ea2`. Sealed and unexecuted; no target contact occurred.
Start before October 27, 2026, 11:36:57 CDT after separate exact-hash approval.

The repository-owned controller reuses unchanged NTP passive/ownership/transport
sources, frozen into the bundle. The new scope adds installed versions/manual
excerpts, vendor-file ownership and exact hash-matched contents, filtered kernel
configuration and panic policy, selected journald configuration, persistence
metadata and boot/media identifiers. It never opens a watchdog device or reads
crash/journal payloads, and it cannot trigger recovery or change settings.

Eleven focused tests and 28 dependency tests pass. Qualified content filters,
gzip bounds, remote namespace initialization, sealed inputs, expiry, one-use
receipts and timeout handling. These are local safety checks, not live findings.
Operator console/media, peer/shared-power, trigger/attribution and timing decisions
remain open. No recovery or final-observation acceptance is inferred.

Next review/approve this capture and assess retained results before choosing a
failure mechanism. OBS-02/D1–D5 and bounded OBS-04 are unchanged; OBS-09 is unstarted.

## Fleet policy and pilot recovery contract drafted — October 26, 2026

Aaron approved defining fleet policy/adoption and the pilot recovery contract,
and supplied a historical standalone-daemon configuration as reference rather
than a baseline or instruction. Defined a proposed shared systemd hardware-watchdog
standard with explicit function-based host exceptions. The 60/120-second
runtime/reboot proposal preserves the observed pilot settings pending qualification;
no inventory default, owner, package or target configuration was changed.

The [policy](docs/FLEET-POLICY.md) excludes load-reset thresholds and automatic
adoption of the historical 15-second timeout. It keeps application monitoring and
mail ownership separate, preserves vendor policy, and requires explicit handling
of conflicting roles and unsupported hardware. Existing fleet inventory determines
membership; the role matrix does not invent live configuration for other hosts.

Reviewed primary systemd, Debian Trixie watchdog and Linux watchdog API references.
Upstream documentation supports the mechanism comparison; installed/native behavior
still governs qualification. The [pilot contract](docs/PILOT-RECOVERY-CONTRACT.md)
is a review draft, not an executable test: trigger selection and reset attribution
need native facts, node-specific console/media confirmation and approved deadlines.
No synthetic success, normal reboot or service-only test may close hardware expiry.

Next prepare the scoped non-mutating recovery-readiness inspection and resolve
operator prerequisites before selecting a trigger or sealing a disruptive test.
No target contact, package install, device open, send, reset or retry occurred.
OBS-02/D1–D5 and bounded OBS-04 remain unchanged; OBS-09 remains unstarted.

## Fleet ownership documented; NTP pilot inspected — October 26, 2026

Aaron identified watchdog as a fleet-managed application owned by this component.
Added [readme.md](readme.md) as the governing scope/lifecycle document. Existing
production inventory intent remains unchanged. No installer, template, host
policy, timeout override or fleet deployment was introduced.

The separately approved NTP-owned inspection
`watchdog-ownership-20261026-v1` executed once on j2-svntp1 at
11:08:00–11:08:01 CDT. Approved archive SHA-256:
`193718779b73bb9363d64b13d483605274c15ed11b71b88d682173cf0d1f6a70`.
Its private outcome/evidence remains with the originating NTP operation.

The bounded snapshot found PID 1, executable `/usr/lib/systemd/systemd`, holding
file descriptor 10 for `/dev/watchdog0` with a stable recheck. The scan covered
152 visible process leaders and 459 descriptors, reporting no gaps. This is
snapshot attribution; it does not prove exclusivity across every namespace,
unshared thread table or time interval.

Effective manager properties reported runtime watchdog 1 minute, reboot watchdog
2 minutes, pretimeout 0 and kexec watchdog 0. Selected assignments from
`/usr/lib/systemd/system.conf.d/40-rpi-enable-watchdog.conf` were
`RuntimeWatchdogSec=1m` and `RebootWatchdogSec=2m`; these agree with the queried
manager values. Package ownership was not inspected. The selected assignments
are not a full production configuration mirror.

Watchdog0 reported active, timeout 60, nowayout 0 and bootstatus 0. Boot, core
services, protected files, configuration records and manager properties were
stable. No device was opened, no configuration changed and no retry occurred.
Feeding cadence, reset behavior, boot-loop handling and recovery remain untested.
This observation does not establish fleet deployment or fleet acceptance.

Next: prepare fleet policy/adoption and pilot recovery contracts using this
existing systemd owner. Decide host selection, supported backend, override
ownership, management mechanism and restoration before implementation. Any
further target inspection, mutation or recovery test needs its own scoped approval.
The NTP Phase 3 recovery gate remains open; OBS-02/D1–D5 and bounded OBS-04 are
unchanged, and OBS-09 remains unstarted.
