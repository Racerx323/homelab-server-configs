# smartmontools operation history

## Candidate smartd single-check admission: failed

On October 6, 2026, the approved bundle
`ea90fc04b9b950d2a5a5db20752da12e54dd9b08dfa53a062832143e84de922e`
ran once and failed before device registration. The candidate rejected combined
debug/PID options and exited 1; controller exit 2 records failed admission.
The 75-second observation and independent production continuity checks passed.
No candidate disk check, production change or automatic retry occurred.

The terminal definition and sanitized result manifest are preserved by annotated
tag `smartmontools-smartd-admission-v1-failed`. Publication must be verified before
the consumed operation is removed or a replacement bundle is frozen. Raw baseline,
binary and evidence remain private with their original hashes; the sanitized
archive is not a runnable substitute for that complete private bundle.

The reusable runner omits the incompatible `-p` option. Nineteen focused tests
and affected hooks passed. This correction is local qualification only; native
admission, repeated-check qualification and daemon replacement remain unaccepted.
