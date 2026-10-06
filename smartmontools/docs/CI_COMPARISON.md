# Standalone upstream smartctl comparison

This procedure tests an upstream CI executable alongside the packaged smartctl.
It does not replace the package, run candidate smartd, change monitoring policy,
start a self-test or establish storage acceptance. Component ownership remains
in [the architecture](SMARTMONTOOLS_ARCHITECTURE.md).

## Provenance and preparation

The maintainer of [issue 648](https://github.com/smartmontools/smartmontools/issues/648#issuecomment-5798625671)
requested a recent-build comparison. The specified
[run](https://github.com/smartmontools/smartmontools/actions/runs/35888458253)
built commit `06489e03695e0cf0a7366f0d402fbff8763bf3e6`. Artifact 10763334265
is `smartmontools-ubuntu-arm64-gcc-static-link`; the downloaded ZIP matches its
GitHub SHA-256 `ad7d8840f9349e7ab8a04dc8741ad7bf5799cb1cdd712901faba32b1b09bff74`.
The extracted regular-file executable has SHA-256
`0de4a00e9ae4d96ebd21b66142b8e24e495cd48a1f2f854c0458355cb624438c`.
ELF inspection shows static AArch64; the included header identifies
`pre-8.0-583`, emulated SVN r6297. Actual `--version` is an execution precondition.
Digest matching establishes artifact integrity against GitHub metadata, not
independent signature attestation or proof that the bug is fixed.

Only the smartctl executable is staged under a new root-owned mode-0700
`/var/tmp/smartmontools-ci-trial.*` directory. Production executable paths and
configuration remain untouched. Pin the launcher, comparison script, executable,
procedure and specification in the approval manifest. The launcher checks every
file and refuses reuse after its local execution claim is created.

## Execution scope

The prepared target is the qualified pilot at `ama@10.1.2.170`. Preflight verifies
hostname, ARM64, root `/dev/sda2`, JMicron `152d:0583`, usb-storage ancestry,
installed package `7.5-2~bpo13+1`, candidate identity and absence of failed host
units. Drift stops execution. Configuration/binary hashes and smartd/Webmin
service identities are retained before/after and between queries.

Three alternating pairs use exactly this read-only query, first installed,
then the separately staged candidate:

```text
BINARY -d sntjmicron -r nvmeioctl,2 -q noserial -l selftest /dev/sda
```

Both binaries explicitly use the qualified NVMe bridge type `sntjmicron`. The
first candidate attempt rejected ambiguous autodetection between `sat` and
`sntjmicron`; its evidence is retained separately. This comparison does not
change production autodetection or smartd configuration. `-l selftest`
reads prior results and does not start a self-test. The installed binary's
`--version` and the candidate's `--version` are recorded without device access.
Each device command has a 40-second timeout and 4 MiB per-stream bound. Observe
at least 75 seconds after every return, including command failure. Preserve
journal cursor continuity, boot/configuration/service identity, ext4 counters,
command status and decoded exit bits. Any nonzero result, timeout, lost evidence
coverage, storage event or continuity failure stops additional queries. The
remote trial has a 900-second deadline; the controller has a 1020-second bound.
A hard deadline interruption is incomplete, never accepted.

Leave smartd, Webmin and Nautobot running. Existing polling may overlap a query;
do not attribute a SCSI counter increment or journal event solely to the trial.
The known Webmin parted discovery increment is distinct from the self-test-log
anomaly. Do not automatically disable polling or stop services on trial failure.
Preserve evidence and review any necessary recovery separately.

## Evidence and interpretation

Raw stdout/stderr and kernel records remain in the root-owned evidence directory.
Retrieve them into protected private controller storage for review after the run;
retain the remote copy until transfer/hash verification is complete. Neither
`-q noserial` nor a successful exit makes raw debug tails safe for publication.
Capture failures may omit partial command output and must be reported as gaps.
Do not attach raw logs, device identities, unrelated buffer bytes or addresses.

Compare per-read request/return lengths, first-19 versus twentieth record status,
implausible decoded records and tail consistency. Three quiet candidate reads
without the anomaly are a bounded non-reproduction, not proof of permanent
resolution. A standalone smartctl result does not qualify candidate smartd or
resolve the daemon error-count behavior by itself. Retain package, transport and
source-version identity in a sanitized follow-up draft to issue 648.

No rollback of production configuration is needed because none is changed.
Cleanup removes only verified trial-owned files after evidence preservation;
never delete the installed package, monitoring state or device data. Upload and
execution require approval of the exact frozen bundle. Upstream publication is a
later reviewed action; preparation does not publish a report.

## Bounded pilot finding

The explicit-type comparison completed three alternating pairs. Installed 7.5
produced an implausible Unknown self-test record on one of its three reads;
the candidate produced No Self-tests Logged on all three. All commands returned
zero and all six 75-second storage windows were quiet. Candidate diagnostics
reported a request adjustment to `0x0200` with CDW10 `0x007f0006` and truncation
to 18 entries. No permissive override was used.

This is bounded non-reproduction on the candidate while the old behavior
reproduced in the same session, not proof of permanent resolution. Candidate
smartd remains untested. Keep the packaged production policy unchanged pending
separate review. Private field summaries, verified evidence and an unpublished
upstream draft are retained under
`/home/aaron/code/.local-evidence/smartmontools-ci-comparison-20260924/explicit-type/`.

## Candidate device-type compatibility follow-up

The [maintainer's follow-up](https://github.com/smartmontools/smartmontools/issues/648#issuecomment-5833255782)
requests USB bcdDevice and a CI-only `-d sat/sntjmicron` test. The pinned source
`06489e03695e0cf0a7366f0d402fbff8763bf3e6` already implements this experimental
option. It tries ATA identification through SAT before using the NVMe bridge
path. This is distinct from forcing `-d sat` and from the earlier installed-versus-
candidate self-test-log comparison.

Set specification `comparison_mode: candidate_device_types` and
`expected_bcd_device: "0213"`. Preflight resolves the USB ancestor of the root disk,
requires one bridge `152d:0583`, and reads its sysfs bcdDevice descriptor. A changed
or malformed revision stops before device queries. The descriptor is not a verified
firmware release. Successful preflight preserves a separate descriptor receipt.

Use the same verified candidate for three alternating pairs:

```text
CANDIDATE -d sntjmicron -r nvmeioctl,2 -q noserial -l selftest /dev/sda
CANDIDATE -d sat/sntjmicron -r nvmeioctl,2 -q noserial -l selftest /dev/sda
```

The installed executable receives only `--version`, not the experimental option.
Six reads, 75 seconds after every return, 40-second command bounds and the
900-second trial deadline remain unchanged. USB disconnects as well as resets
stop further queries. Keep smartd, Webmin, Nautobot, packages and drive database
unchanged; do not run update-smart-drivedb, restart services or start a self-test.
Readback must establish successful NVMe/log decoding as well as transport stability;
exit zero alone is insufficient. This does not qualify candidate smartd.

Keep controller receipts beside the private approval bundle rather than only in
volatile `/tmp`; remote evidence remains in `/var/tmp`. An interrupted controller
still makes collection incomplete until remote evidence is recovered and reviewed.
The foreground launcher is not a claim of durable controller supervision. Do not
close its execution session or rerun a claimed bundle. Publication remains separate.

## Separating detection errors from scheduled discovery

For a focused follow-up, `comparison_mode: candidate_detection_attribution`
requires exactly two candidate reads: explicit `sntjmicron`, then
`sat/sntjmicron`. It uses `-r ioctl,2` to include ATA and SCSI transactions,
not just the NVMe tunnel. Other command, identity, output, continuity and
75-second delayed-event bounds are unchanged. The installed binary still
receives only `--version`.

Record `scsi_ioerr_before`, `scsi_ioerr_at_return` and `scsi_ioerr_after`;
`returned_epoch` separates the short command interval from the later observation.
Compare rejected SAT commands and sense responses with the immediate delta.
Do not attribute increments arising only during the later observation to the
candidate. A rejected IDENTIFY command followed by successful NVMe fallback is
not itself a USB reset or failed self-test-log read.

Normal monitoring remains active. Immediate sampling narrows, but does not
eliminate, concurrent-process ambiguity. Neither a residual +1 nor source review
alone proves that Webmin ran parted at that instant. If live debug output cannot
separate the causes, report that limit and prepare process/kernel tracing as a
separate scoped operation; do not silently attach to daemons or enable tracefs.
See [the Webmin discovery investigation](../../Webmin/docs/DISK_DISCOVERY_FOLLOW_UP_PROMPT.md)
for the independently reproduced parted increment. Preserve all raw buffers
privately. Freeze and authorize the exact bundle before upload/execution.

## Maintainer clarification and pending autodetection verification

On September 29, 2026, [chrfranke confirmed the detection interpretation](https://github.com/smartmontools/smartmontools/issues/648#issuecomment-5894223773).
The planned drivedb addition matches USB `152d:0583` with descriptor
`bcdDevice=0x0213` to `sntjmicron`. This descriptor is not a verified firmware
version. The maintainer also confirmed that the two rejected ATA identification
probes before successful NVMe fallback are expected with `sat/sntjmicron`.
A separate planned refactoring removes the unnecessary IDENTIFY PACKET DEVICE
probe and is expected to reduce that path to one counter increment per detection.
Neither statement establishes resolution of the self-test-log/smartd anomaly.

The September 29 publication check found upstream `main` at
`06489e03695e0cf0a7366f0d402fbff8763bf3e6`; its
[drivedb entry](https://github.com/smartmontools/smartmontools/blob/06489e03695e0cf0a7366f0d402fbff8763bf3e6/drivedb/drivedb.h)
still contains `0xXXXX`. The announced descriptor match is therefore not present
in that inspected revision. Retain explicit `-d sntjmicron`; no installed database,
package, smartd configuration or Webmin setting was changed by this review.

After publication, pin and review the exact updated database and compatible
binary. Prepare a bounded standalone comparison of automatic detection against
explicit `sntjmicron`, proving the database actually loaded, descriptor identity,
selected transport, command exit mask, immediate/settled counters and 75-second
kernel continuity. Preserve production configuration and do not start a self-test.
Use the existing exact-bundle execution gate before target queries. Do not remove
production device-type selectors merely because upstream adds a match; accept
the target comparison first. No future monitoring or automatic test is scheduled.

The separate Webmin discovery finding is linked in the preceding procedure.
Its reproduced `parted` increment has no identified SCSI opcode/sense response;
the maintainer's explanation of smartctl's SAT probes does not identify it.

## Repository-only local database preparation

The [maintainer's local-database alternative](https://github.com/smartmontools/smartmontools/issues/648#issuecomment-5895877546)
allows testing before the upstream database addition is published.
`configs/jms583-0213.drivedb.h` contains only the proposed USB descriptor match.
It is a review-only input, not an installed override or an executable bundle.

The [pinned candidate manual](https://github.com/smartmontools/smartmontools/blob/06489e03695e0cf0a7366f0d402fbff8763bf3e6/src/smartctl.8.in)
defines `-B +FILE` as prepending entries to the usual databases; `-B FILE`
replaces them for that invocation. Use an explicit absolute path with the additive
form in a later approved comparison. Do not copy this file to a default database
path: doing so could change other smartctl/smartd consumers. Default paths are
build-dependent; the target's installed manual and version remain authoritative.
Local smartctl 7.5 from Debian `7.5-2~bpo13+1` (amd64, extracted without
installation) passed native parsing, exact descriptor matching, wrong-revision
rejection, additive loading and malformed-database rejection on October 6.
Private `smartmontools-drivedb-preparation-20261006/PARSER_RESULT.json` records
identities and limits. These checks opened no device. The exact ARM64 candidate
must repeat parser/matcher preflight before live reads; current installed-version
identity remains an execution precondition.

The [Webmin deployment result](../../Webmin/docs/DISK_DISCOVERY_DEPLOYMENT_RESULT.md)
now records acceptance of the October 4–5 passive observation, reviewed October 6.
The observer is inactive; the earlier incomplete run remains separate. The old
September 30 waiting checkpoint is superseded. No new observation may be running
when the comparison starts; the runner checks observer inactivity before each read.

After that review, prepare a separate bounded bundle binding the exact binary,
override hash, USB descriptor and target identity. First verify database parsing
and matching without device access using the version's documented diagnostic
options. Then compare an explicit `sntjmicron` control with automatic detection
using the additive override. Require the selected type, exit-mask interpretation,
immediate and settled counter deltas, and at least 75 seconds of kernel continuity
after each read. Stop on resets, timeouts or filesystem errors. Do not start a
self-test or qualify smartd by inference. The runner now supports `candidate_local_database`: exactly two candidate reads,
explicit `sntjmicron` followed by `auto` with `-B +FILE`. Only the automatic read
receives the override. Hash-check the database before reads; no default database
installation is permitted. Any immediate or settled counter increase stops this
comparison for review. A completed capture is not automatic acceptance: review
the raw transport diagnostics and selected device type separately. This does not
qualify candidate smartd or authorize removing production selectors.

## October 6 bounded local-database comparison result

The separately authorized two-read comparison completed successfully. The
explicit `sntjmicron` control and automatic detection with the private additive
entry both returned zero and decoded an NVMe self-test log with no test in
progress and no tests logged. Immediate and settled SCSI counter deltas were
zero for each read; both post-return intervals exceeded 75 seconds. No matched
kernel storage fault, ext4 error increase, boot drift, monitored configuration
hash change or service identity change occurred. Eleven retrieved evidence files
matched remote hashes.

The output did not print an explicit device-type label; the verified outcome is
successful automatic NVMe reading with the hash-bound, natively matched entry.
Decoded summaries matched; equality of entire debug buffers is not claimed.
Private `smartmontools-drivedb-preparation-20261006/REVIEW.json` records the
bounded acceptance and retained evidence. The default databases and monitoring
configuration were not changed. Candidate smartd remains unqualified. Do not
replay the consumed bundle. An upstream summary draft is prepared privately;
publication and any persistent local override remain separate actions.

## Candidate-smartd qualification preparation

The October 6 smartctl result does not qualify the daemon's self-test-log
error-count handling. Keep the installed smartd, monitoring configuration and
alert route unchanged. Retain the tested custom database entry as an optional
smartctl input; it is not needed for this explicitly typed daemon comparison.
The bounded smartctl summary was [published upstream](https://github.com/smartmontools/smartmontools/issues/648#issuecomment-6020344626).

Prepare candidate-smartd qualification in two separately reviewed stages:

1. **Single-check admission.** Obtain the smartd ARM64 binary from the reviewed
   upstream build, verify artifact provenance, executable hash and version, and
   confirm that its source includes the daemon code under investigation. The
   existing smartctl binary hash cannot identify or qualify smartd. Review the
   installed daemon's recent error-count transitions and a fresh device/service
   baseline without issuing exploratory disk reads. Confirm no observation or
   other maintenance is active.
2. **Repeated-check observation.** Only after the single check passes, define a
   bounded foreground candidate observation with private persistent state and
   logs. Review the check interval and duration against the historical warning
   cadence; one check cannot demonstrate that intermittent transitions stopped.
   Preserve production monitoring throughout, attribute output to the correct
   process, and stop the candidate on storage faults or unexpected commands.
   Do not infer resolution merely from absence of warnings in a short run.

The review-only input is
`configs/jmicron-nvme.smartd-qualification.conf`: one explicit device and
`-l selftest`, without scanning, blanket checks, self-test schedules or alerts.
Before freezing execution, verify candidate support for that NVMe directive
against its pinned source/manual. Use the candidate's documented one-check exit
mode for stage one; keep the process in the foreground, with a 60-second deadline,
bounded output and at least 75 seconds of post-exit kernel observation. Validate
its exact exit-code convention separately from smartctl's bitmask.

Bind all state, attribute-log and output destinations to a protected trial
directory. Debug mode suppresses PID files; do not supply `-p`, which conflicts
with that mode. Verify the effective compiled defaults and command overrides; refuse
execution if the candidate could write production state or send notifications.
Do not share the live daemon's state files. If baseline state is needed for later
transition comparison, explicitly review a read-only copy and its provenance;
never seed a candidate with mutable live files. Daemon state and logs can contain
serials and remain private. No service registration or package installation is
part of either stage.

Record native configuration registration, the actual self-test-log command/result,
interpreted error count, immediate/settled counters, kernel continuity, and
unchanged installed binary/configuration/service identities. Candidate startup
alone is not acceptance. A clean one-check exit permits preparation of the next
stage, not daemon replacement. Preserve evidence after failure; terminate only
the owned candidate and verify its exit. Production monitoring requires no
rollback because it was not replaced.

The October 6 preparation verified smartd in the same retained CI archive:
SHA-256 `9fa55e0684180152d3c7e8a3a588ab3caea40745b3cecdd8c13179ae21d13221`.
Native, unprivileged `--version` and `--help` ran from an anonymous memory file,
without device access or installation. They identify `pre-8.0-583`, source
`06489e03695e`, and list the output overrides individually; that check did not
validate their combination. The fresh read-only
baseline matches the package, bridge, root device and production service
identities. The observer is inactive; SCSI count is `0x2`, ext4 errors are zero,
and no failed units or pending systemd jobs were found. Recent production logs
still show a self-test error-count increase followed by a decrease. This is the
reason to qualify the daemon separately.

The pinned source confirms that registration reads Identify Controller,
SMART/Health and the self-test log, followed by the single monitoring check.
This is one daemon check, not one device read. An absent self-test schedule
prevents test initiation; absent mail/command directives prevent notifications.
Debug/onecheck mode stays in the foreground and uses stdout rather than syslog.
Private `-s`, `-A` and `-j` paths isolate state, attributes and JSON;
debug mode suppresses PID creation and requires omitting `-p`.
an explicit empty `-B` input bypasses default database files. A minimal environment
also excludes inherited notification variables. State is written after the check
and at exit. The source omits zero-valued state fields, so an absent
`self-test-errors` key means zero only in a verified, newly written state file.

`scripts/qualify-smartd.py` owns the candidate deadline, bounded partial output,
post-exit observation and continuity checks. It reuses the smartctl comparison's
read-only identity/journal helpers, without invoking its query plan. The separate
`scripts/execute-smartd-qualification.py` verifies all manifest members, claims
the bundle once and stages a root-owned mode-0700 trial. A mismatch, active
observer, additional smartd, visible maintenance, expired baseline or changed
counter/service/configuration identity stops before the candidate check.
The baseline is valid for one hour, with five minutes reserved before expiry.
Normal production monitoring remains active, so concurrent polling still limits
attribution. The checks do not certify an exclusive host maintenance lock.

The consumed private bundle is preserved unchanged under
`/home/aaron/code/.local-evidence/smartmontools-smartd-preparation-20261006/bundle/`.
Its `PROCEDURE.md` records the exact command, hash gate, deadlines, evidence
collection and recovery boundary. Local tests cover configuration restrictions,
timeout/output failure handling, inherited environment isolation, admission
evidence, baseline expiry and manifest tampering. They do not qualify live ARM64
registration or device transactions. Native configuration registration, actual
self-test-log results and preserved state remain unqualified. Do not replay the
consumed bundle or edit its frozen inputs.

## October 6 single-check admission failure

The authorized bundle
`ea90fc04b9b950d2a5a5db20752da12e54dd9b08dfa53a062832143e84de922e`
was executed once. Candidate smartd exited 1 after rejecting the simultaneous
`-d` and `-p` options; the controller returned 2 for failed admission. The pinned
source rejects that combination during argument parsing, before device
registration. No candidate device check occurred. The original preparation
incorrectly treated a private PID path as compatible with debug mode.

The post-exit observation lasted 75.000 seconds, with SCSI count unchanged at
`0x2`, ext4 errors zero and no matched kernel storage fault. A separate read-only
post-baseline confirmed unchanged boot, bridge, package, production binary/config
hashes and smartd/Webmin service identities; no failed host units were found.
Five retrieved evidence files matched their remote SHA-256 values. Raw evidence,
the original exit statuses and the consumed bundle remain private and retained.

The reusable command now omits `-p`; its regression rejects any PID-file argument
in foreground mode. This repository correction has not been executed on the
target. The failure archive is published under
`smartmontools-smartd-admission-v1-failed`; see [history](../HISTORY.md) for verified
identities. The retry preparation refreshed the baseline and natively checked
the corrected options without device access: argument parsing reached a
deliberately unreadable configuration and returned exit 6. The empty database's
missing-DEFAULT warning is expected. This does not qualify live registration.
Obtain approval of the replacement bundle's new hash before any retry.
Candidate smartd admission, repeated-check qualification and production
replacement remain unaccepted. No automatic retry or production change occurred.

## October 6 corrected single-check admission result

The separately approved retry bundle
`6c6846d56e66af89f2d2affe2d4125fee70b15bc9fb39a3caa5d2fcff13d3b45`
completed once with candidate and controller exits zero. Manual evidence review
accepted single-check admission. The original runner result retains its
`accepted=false` manual-review gate; the separate private execution review records
the acceptance decision without rewriting raw evidence.

One NVMe device registered. Five diagnostic transactions succeeded: Identify
Controller, SMART/Health and self-test-log registration reads, then SMART/Health
and self-test-log monitoring reads. Both log requests were adjusted to 512 bytes
with the candidate's 18-entry protection. The newly written private daemon state
indicates zero self-test errors; the pinned writer omits zero-valued fields.
The empty database's missing-DEFAULT warning was expected. No self-test started.

The 75.000-second post-exit observation found unchanged SCSI count `0x2`, ext4
errors zero and no matched kernel storage fault. An independent read-only
post-baseline confirmed unchanged production binaries/configuration, service
invocations, package, bridge and boot identity. Eight retrieved evidence files
matched remote SHA-256 values. Private review and original evidence are under
`/home/aaron/code/.local-evidence/smartmontools-smartd-retry-20261006/`.

Archive and reconcile this bounded admission before preparing repeated-check
observation. Choose that later interval/duration from historical warning cadence;
one clean check does not establish intermittent-warning resolution. Production
monitoring remained active and unchanged. No daemon upgrade, repeated observation,
cleanup or upstream publication occurred. Do not replay the consumed bundle.
