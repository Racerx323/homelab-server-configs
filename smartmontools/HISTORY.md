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

## Corrected single-check admission: accepted, archival pending

The separately authorized corrected bundle
`6c6846d56e66af89f2d2affe2d4125fee70b15bc9fb39a3caa5d2fcff13d3b45`
ran once on October 6, 2026. Candidate and controller exits were zero. Manual
review accepted registration and one monitoring check, including two successful
self-test-log reads and zero interpreted self-test errors in private state.
The 75-second observation and independent production continuity checks passed;
eight retrieved evidence files matched their remote hashes.

The consumed bundle and original evidence remain private and unchanged, with
the acceptance decision recorded separately in `EXECUTION_REVIEW.json` under
`smartmontools-smartd-retry-20261006`. Terminal archival and reconciliation remain
pending. This is admission only: intermittent-warning resolution, repeated-check
qualification and production replacement remain unaccepted.

The exact non-sensitive consumed definition and sanitized acceptance manifest
are prepared for annotated tag `smartmontools-smartd-admission-v2-accepted`.
Verify its publication before removing consumed operation files or freezing the
repeated-check operation. The full raw baseline, binary and reports remain
private and are identified by their original hashes in the terminal manifest.
