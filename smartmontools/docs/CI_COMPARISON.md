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
