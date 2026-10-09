# Terminal repeated-check observation archive

This consumed definition records bounded single-host qualification, accepted by
independent review on October 9, 2026. It is not an executable observation.
The original manifest and nine non-sensitive frozen members are preserved
byte-for-byte. The raw baseline and candidate binary remain private, identified
by their original SHA-256 values. The original consumed execution claim and all
raw evidence remain private and unchanged. Do not replay launch.

`result-manifest.json` records the separate manual decision and sanitized hashes
of all 27 retrieved regular files. Private device filenames are replaced with
neutral aliases; the raw collection manifest preserves their exact mapping.
The original runner retains `accepted=false` and `review_required=true`.
`upstream-results.txt` preserves the approved proposed comment without edits.

Ninety-six monitoring self-test-log reads completed, with no interpreted errors
in the 18 retained entries. All rolling journal checkpoint links, counts and
selected batch hashes matched the still-retained source journal. Production
warnings did not recur: this is non-reproduction, not proof of a fix.
See [the review](../docs/SMARTD_OBSERVATION_REVIEW.md) for coverage limitations.

Preserve this definition and sanitized result in annotated tag
`smartmontools-smartd-observation-v1-accepted`, verify its remote identity, then
remove consumed operation files from main. The incomplete sanitized archive
cannot replace the full private bundle or authorize any new target operation.
