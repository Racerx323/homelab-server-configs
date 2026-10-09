# Candidate smartd observation: bounded qualification accepted

Independent review on October 9, 2026 accepts the completed 48-hour observation
for the admitted pilot host, explicit `sntjmicron` selector and restricted private
configuration. The intermittent self-test-log warning did not reproduce in either
the candidate diagnostics or the retained production smartd journal. This is
non-reproduction; it does not establish that the intermittent bug is fixed.
Production smartd and Webmin polling remained active throughout.

## Identity and collection

The frozen manifest SHA-256 is
`089f66b50fef200afe9ce104f5682a4f6af0b647aa0b4e399a7d6f3b95b47867`.
All 11 frozen members matched their admitted hashes. The original launch receipt,
consumed execution claim, supervisor PID/start-time/boot identity and terminal
status agree. Candidate source is `06489e03695e0cf0a7366f0d402fbff8763bf3e6`,
with binary SHA-256
`9fa55e0684180152d3c7e8a3a588ab3caea40745b3cecdd8c13179ae21d13221`.

Read-only collection verified the exact root-owned mode-0700 trial and its parent
directories. It retrieved 27 regular files totaling 12,519,314 bytes, including
the frozen inputs, diagnostics, journal receipts, terminal records and private
state. Exact allowlists, per-file/aggregate bounds, ownership/mode checks and
no-follow opens rejected symlinks and unexpected paths. The first remote
collection rejected smartd's `.state~` backup; bounded filename inspection
confirmed the regular private backup before its exact name was admitted.
Remote Python and `sha256sum` hashes matched independent local Python and
`sha256sum` hashes for every file. Original evidence and the execution claim
remain unchanged; remote cleanup has not occurred.

## Independently reviewed results

- The observation started October 6 at 1:34:30 p.m. CDT and reached terminal
  completion October 8 at 1:35:45 p.m. CDT. The original supervisor reports
  172,875.10 seconds including 75.09 seconds of post-exit observation.
- Diagnostics contain 195 successful NVMe transactions: one identification,
  97 health-log reads and 97 self-test-log reads. One self-test-log read belongs
  to registration; 96 belong to monitoring. There are no unfinished or unexpected
  command transactions. The largest candidate-reported duration is 0.062273 seconds.
- All 97 self-test-log transactions show the protected 512-byte transfer and
  18 unused records. Their first 512 bytes are identical. The 96 attribute CSV
  cycles run from October 6 at 1:34:30 p.m. to October 8 at 1:04:30 p.m. CDT;
  consecutive timestamps differ by 1,799–1,801 seconds, within the 1,920-second
  bound. Ninety-six cycles include the initial check and end at hour 47.5.
- Candidate output has one expected missing-DEFAULT notice for the intentionally
  empty private database and 97 protective self-test-log truncation notices.
  No self-test error-count transition or unexpected diagnostic warning appears;
  stderr is empty. Both private state files contain only the state header and
  `nvme-available-spare = 100`, with no `self-test-errors` key. Raw log decoding
  supports zero interpreted self-test errors; no nonexistent state field is claimed.
- Shutdown output records SIGTERM, private state writing and exit status zero.
  Core result, terminal membership result and status agree. Read-only October 9
  inspection found no owned candidate or supervisor process remaining.
- All 11,391 journal receipts have continuous cursor links and matching selected
  batch hashes. A separate read of the still-retained source journal verified
  every checkpoint cursor, all batch counts and hashes across 2,967 source records.
  There are zero selected kernel and production-smartd records, zero records
  omitted between the final cursor and final receipt, and no source suppression
  indicators. Normal checkpoint gaps are at most 15.279 seconds; the last gap is
  87.873 seconds, bridging shutdown and settling.
- Independent October 9 endpoint checks match the launch boot ID, packaged
  version, production smartctl/smartd/configuration hashes and both service
  invocation IDs, main PIDs, active states and restart counts. SCSI `ioerr_cnt`
  remains `0x2`; ext4 errors remain zero; the root remains the same ext4 filesystem.

The retained historical production warning rise and recovery occurred October 4
at 5:42:04 p.m. and 6:12:20 p.m. CDT, before launch. Neither recurred during the
verified window, so there are no in-window production warning timestamps to
correlate with candidate checks. Simultaneous production polling prevents a
controlled causal comparison.

## Coverage limits and decision boundary

Per-audit counter, configuration, service, clock and private-state snapshots were
not retained. Their historical checks are supported by the verified frozen audit
implementation and successful terminal result; the independent October 9 endpoint
does not reconstruct every sample. Candidate diagnostic receive/completion times
are not absolute timestamps. CSV times establish cycle spacing to one second;
candidate-reported durations are not independent transport latency measurements.

Settling uses a 75-second sleep followed by one final audit, rather than periodic
audits during the sleep. The retained cursor chain and independent source query
cover the final gap, but the exact exit wall time is not independently recorded.
The 48-hour continuous duration is supported by launch/terminal identities,
supervisor monotonic accounting and rolling audits; CSV timestamps alone cover
47.5 hours of check starts. Journald coverage establishes records actually stored
and queried, not that every possible underlying event was emitted or never
dropped. Full historical retention outside this window remains unestablished.

Required bounded evidence is complete and no failure was found. These limitations
do not convert the observed quiet run into proof of elimination. The separate
manual decision accepts bounded single-host qualification only. The original
runner retains `accepted=false` and `review_required=true`; it is not rewritten.
Production replacement, custom-database/autodetection daemon behavior, scheduling,
notification delivery and fleet operation remain unqualified.

## Retained decision and next step

Private collection, verification scripts, analysis, source-journal cross-check,
separate `EXECUTION_REVIEW.json` and sanitized `UPSTREAM_RESULTS_DRAFT.md` are under
`/home/aaron/code/.local-evidence/smartmontools-smartd-observation-preparation-20261006/review-20261009/`.

The separately approved terminal archive is published and verified under annotated
tag `smartmontools-smartd-observation-v1-accepted`; [history](../HISTORY.md) records
the archive commit and remote tag identity. The exact non-sensitive definition and
sanitized evidence manifest are retained in the tag. Consumed repository operation
files were removed from main only after verification. Raw evidence, the complete
private bundle and execution claim remain unchanged.

The exact approved sanitized results were posted once to smartmontools issue #648
as [comment 6085677444](https://github.com/smartmontools/smartmontools/issues/648#issuecomment-6085677444) on October 9, 2026, at 12:13:27 p.m.
CDT. Independent API readback matched the complete approved body; the issue remains
closed. Private `publication/UPSTREAM_PUBLICATION.json` records the payload hash,
destination and verification.

Preserve production policy and both local and remote evidence. No new trial,
SMART query, restart, installation, production change or remote cleanup occurred.
Archive commits, tag creation, repository pushes and the exact upstream comment
were separately authorized after the evidence review.

## Evidence hashes

The following hashes identify the private bounded evidence and separate decision;
raw identities and journals remain outside Git.

| Artifact | SHA-256 |
| --- | --- |
| `evidence/stdout` | `5ec8a0591d8deba3dbabf0a9b3c0ace600f1041c40d27ed644bd466dcdd0e3ba` |
| `evidence/result.json` | `17df4038c4f351477970a11f2eb1f08c3f07c0adbf894b4f02a2196e877cc4f4` |
| `evidence/terminal.json` | `17df4038c4f351477970a11f2eb1f08c3f07c0adbf894b4f02a2196e877cc4f4` |
| `evidence/journal-checkpoints.jsonl` | `08452c2ddbbfae63b94036577fcecb7d4b68b5a2c7880aa1d7ac87d58ed4aef4` |
| `evidence/kernel.jsonl` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `evidence/production-smartd.jsonl` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `status.json` | `7f57b75ad94318dbdb88f11005c940f16e02c554012e49e041400fde36cd414f` |
| `source-journal.stdout` | `fdecd4c181593c6437c62850a1d51390d2d93598d4c1e0f99e8365b083f7bbd3` |
| `EXECUTION_REVIEW.json` | `f5e6b4eee8cd1f283da36ad32dd147cf5261e6f64e09e491abc4a309ec47ad02` |
