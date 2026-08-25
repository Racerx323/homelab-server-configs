# Caddy deployment lifecycle

[`deployment-streams.tsv`](../manifests/deployment-streams.tsv) registers the
Caddy live deployment stream. The Caddy-specific policy in
[`deployment-window-policy.sh`](../tests/deployment-window-policy.sh) enforces
this lifecycle. Do not use its neutral transaction, outer-runner, successor,
or coverage schema for another component.

[`caddy_plan-v1.1.md`](caddy_plan-v1.1.md) remains the governing Caddy
architecture document. It records accepted architecture and approved deviations,
not individual operation identifiers or terminal outcomes.

## Window states

- `clean`: accepted production state only; the neutral deployment implementation
  remains, the operation specification is inactive, and no successor is
  registered.
- `defined`: exactly one operation specification is registered against the
  stream's neutral transaction and outer runner with real production-path
  coverage.
- `terminal-pending`: the operation ran and reached an `accepted`,
  `failed-consumed`, or `manual-intervention` result. Its deployable registry is
  already cleared, but its exact operation specification remains for the
  terminal-result commit and annotated archive tag.

Action-numbered implementation, manifest, regression, and fixture filenames are
never retained on the current branch. Terminal history belongs in `HISTORY.md`,
Git commits, and annotated tags.

## Close an operation

1. Record the terminal result in `HISTORY.md`; do not record it in the governing
   architecture plan.
2. Clear the deployable successor and coverage registries.
3. Set the stream to `terminal-pending` with the exact operation, result, and
   planned annotated tag.
4. Commit while the executed operation specification and sanitized evidence
   manifest remain present.
5. Create and push the annotated tag for that exact commit.
6. Reset the consumed operation specification and coverage, and remove retained
   repository evidence. Keep neutral implementations and regressions.
7. In the next repository commit, either set the stream to `clean` or
   atomically register one already validated replacement operation. Retain the
   latest archive tag in either case.
8. Do not create an otherwise empty clean-state commit between an archived
   terminal operation and its validated replacement.

Git history and annotated tags are the immutable Caddy deployment archive. The
main branch contains current production, neutral reusable deployment code,
neutral validation, and at most one defined Caddy operation.

## Production-state equivalence

Deployment predicates must distinguish semantic state from one filesystem
representation. If production permits a namespace to be absent or to exist as
a protected empty directory, both states are valid and must be exercised by
the real production-path predicate. Coverage must reject non-empty, symlinked,
malformed, incorrectly owned, and incorrectly mode-set adjacent states. Tests
may construct isolated inputs, but they may not change production merely to
match a narrower test assumption.

## Causal production-path evidence

The neutral outer runner must stream the real transaction for every tested
mode. It may not duplicate transaction behavior or write expected availability,
journal, ownership, mutation, rollback, or acceptance results. Bounded command
substitutes may model unavailable external systems only by changing state in
response to the exact emitted command and returning later observations from
that state. Cursor-based journal coverage must obtain its records from the
service-control events executed after the cursor. A marker, fixed transcript,
or mode-aware result generator cannot authorize a deployment.

An operation that permits bounded convergence must define the window and the
causal event that distinguishes convergence from a settled-state failure.
Acceptance requires independently retained observations across the complete
window. Missing recovery, missing causal evidence, persistent degradation, and
ambiguous ownership reject. Missing, malformed, duplicated, reordered,
oversized, unsafe, or incomplete evidence also rejects. The Caddy architecture
plan defines the endpoints, address families, ownership model, timeout, and
sampler lifecycle.
