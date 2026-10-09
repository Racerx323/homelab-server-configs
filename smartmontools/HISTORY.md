# smartmontools operation history

## Candidate smartd single-check admission: failed

On October 6, 2026, the approved bundle
`ea90fc04b9b950d2a5a5db20752da12e54dd9b08dfa53a062832143e84de922e`
ran once and failed before device registration. The candidate rejected combined
debug/PID options and exited 1; controller exit 2 records failed admission.
The 75-second observation and independent production continuity checks passed.
No candidate disk check, production change or automatic retry occurred.

The terminal definition and sanitized result manifest are preserved by annotated
tag `smartmontools-smartd-admission-v1-failed`, published and verified at commit
`fba311539820f0eaca03f45f7c8881fc08c756ee`; the remote annotated tag object matches
`502944d850be72e3e8d16ad5356db47dd3a1341f`. The consumed operation is removed
from the current tree after that verification. Raw baseline,
binary and evidence remain private with their original hashes; the sanitized
archive is not a runnable substitute for that complete private bundle.

The reusable runner omits the incompatible `-p` option. Nineteen focused tests
and affected hooks passed. This correction is local qualification only; native
admission, repeated-check qualification and daemon replacement remain unaccepted.

The retry preparation refreshed the read-only baseline without identity/counter
drift. A native unprivileged check of the corrected option combination used an
anonymous-memory binary/database and a deliberately unreadable configuration
path. It reached configuration loading and exited 6 (`ENOTDIR`), rather than
rejecting arguments. No configuration registration or device access occurred.
The initial local assertion expected missing-file exit 5; retained output showed
the correct unreadable-file exit 6, so no repeated probe was needed. The empty
database also emitted its expected missing-DEFAULT warning. This check qualifies
option compatibility only. The retry needs its own hash-bound approval.

## Corrected single-check admission: accepted and archived

The separately authorized corrected bundle
`6c6846d56e66af89f2d2affe2d4125fee70b15bc9fb39a3caa5d2fcff13d3b45`
ran once on October 6, 2026. Candidate and controller exits were zero. Manual
review accepted registration and one monitoring check, including two successful
self-test-log reads and zero interpreted self-test errors in private state.
The 75-second observation and independent production continuity checks passed;
eight retrieved evidence files matched their remote hashes.

The consumed bundle and original evidence remain private and unchanged, with
the acceptance decision recorded separately in `EXECUTION_REVIEW.json` under
`smartmontools-smartd-retry-20261006`. This is admission only:
intermittent-warning resolution, repeated-check
qualification and production replacement remain unaccepted.

The exact non-sensitive consumed definition and sanitized acceptance manifest
are published at commit `3a236a8f00a9689bdd27f2c242d3ff4d531cca99`, annotated tag
`smartmontools-smartd-admission-v2-accepted`. The remote tag object was verified as
`7961f214fafc974cd9cef2ecd424bf8461c26f89`, with the expected peeled commit.
Consumed operation files are removed from the current tree after verification.
The full raw baseline, binary and reports remain private, identified by their
original hashes in the terminal manifest.

The next observation is defined for 48 hours at 30-minute intervals. Its local
supervision and inactive repository configuration are prepared. Detached launch,
read-only status and identity-bound cancellation are locally qualified. Native
option/runtime checks and a fresh authorized baseline passed. Journald uses
volatile storage, so the observation preserves verified incremental journal
evidence privately. The execution bundle requires separate hash approval. See
the repeated-check preparation in
`docs/CI_COMPARISON.md` for evidence, acceptance bounds and remaining work.

The separately approved repeated-check bundle started October 6, 2026, at
1:34:30 p.m. CDT. Its manifest is
`089f66b50fef200afe9ce104f5682a4f6af0b647aa0b4e399a7d6f3b95b47867`.
The controller exited zero; a new SSH connection confirmed supervisor survival
and one completed monitoring check. Private launch/readiness receipts are retained
under `smartmontools-smartd-observation-preparation-20261006`.

## Repeated-check observation: bounded qualification accepted and archived

The observation completed October 8, 2026, at 1:35:45 p.m. CDT. Independent
October 9 review verified the frozen inputs and launch/terminal identities,
matched 27 retrieved regular files against remote hashes, counted 96 monitoring
checks and confirmed shutdown/settling evidence. All 11,391 journal checkpoint
links, batch counts and hashes matched the still-retained source journal.
Independent production boot/service/configuration/counter endpoints match the
launch baseline. See [the terminal review](docs/SMARTD_OBSERVATION_REVIEW.md) for
evidence hashes and limits.

The separate manual decision accepts bounded single-host qualification. Neither
candidate nor production self-test-log warnings recurred; this is non-reproduction,
not demonstrated elimination. Raw counter/service snapshots for every audit and
absolute transaction completion timestamps were not retained. Production polling
remained active. The original runner's `accepted=false` result and consumed
execution claim remain unchanged. A sanitized upstream-results draft is retained
privately and unposted. The separately approved terminal archive is published in
annotated tag `smartmontools-smartd-observation-v1-accepted`, at commit
`af93245e1509c2e5a725c96336d2825933baa21b`. The remote annotated tag object
`05fc866eae01cff2888e1bd19b23abb9c2ead3a5` and its peeled commit were
verified before consumed operation files were removed from main. The exact
non-sensitive frozen definition and sanitized result manifest remain in the tag;
the baseline, candidate binary, execution claim and raw evidence remain private.
The sanitized archive cannot be used to replay launch. Upstream comment publication
remains pending specific payload/destination approval. No production change or
remote evidence cleanup occurred.
