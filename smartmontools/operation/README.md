# Terminal single-check admission archive

This is the failed, consumed definition, not an executable retry. `manifest.json`
is preserved byte-for-byte, with all non-sensitive script/configuration inputs.
The exact original baseline (including raw device identities/journal) and upstream
binary remain private and are referenced by SHA-256 in `result-manifest.json`.
This sanitized archive deliberately cannot be executed on its own. The complete
original bundle remains under the private preparation directory identified in
`PROCEDURE.md`; its original hash and evidence were reverified before archival.

The candidate rejected the original debug/PID-option combination before device
registration. Candidate exit 1 and controller exit 2 remain failure evidence.
No candidate disk check or admission acceptance is claimed. See the result
manifest for bounded observation and independent continuity checks.

Preserve this directory in annotated tag
`smartmontools-smartd-admission-v1-failed` and verify the pushed tag before
removing consumed files from main. The reusable command outside this directory
contains the locally tested correction; it is not part of this consumed payload.
