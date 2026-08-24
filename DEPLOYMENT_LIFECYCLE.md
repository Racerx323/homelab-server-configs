# Deployment lifecycle

`deployment-streams.tsv` registers every live deployment stream in this
repository. The data-driven policy in
`Caddy/tests/deployment-window-policy.sh` applies the same lifecycle without
component-specific exceptions.

## Window states

- `clean`: accepted production state only; the neutral deployment implementation
  remains, the operation specification is inactive, and no successor is registered.
- `defined`: exactly one operation specification is registered against the
  stream's neutral transaction and outer runner with real production-path coverage.
- `terminal-pending`: the action ran and reached an accepted,
  `failed-consumed`, or `manual-intervention` result. Its deployable registry is
  already cleared, but its exact operation specification remains for the
  terminal-result commit and annotated archive tag.

Action-numbered implementation, manifest, regression, and fixture filenames are
never retained on the current branch. History belongs in annotated tags.

## Close an action

1. Record the terminal result in the governing plan and component history.
2. Clear the deployable successor and coverage registries.
3. Set the stream to `terminal-pending` with the exact action, result, and
   planned annotated tag.
4. Commit while the executed action files are still present.
5. Create and push the annotated tag for that exact commit.
6. Reset the consumed operation specification and coverage; remove retained
   repository evidence. Keep neutral implementations and regressions.
7. In the next repository commit, either set the stream to `clean` or
   atomically register one already validated replacement operation. Retain the
   latest archive tag in either case.
8. Do not create an otherwise empty clean-state commit between an archived
   terminal operation and its validated replacement.

Git history and annotated tags are the immutable deployment archive. The main
branch contains current production, neutral reusable deployment code, neutral
validation, and at most one defined operation per deployment stream.

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

HA continuity acceptance uses independently retained per-request records from
both nodes plus timestamped kernel address-monitor events covering the complete
mutation and final-convergence window. The workstation outer runner performs
the causal correlation. A primary request failure under settled ownership
always rejects. During a deliberately induced coupled failover or failback, it
may be accepted only when the same shared endpoint and address family succeeds
within 12 seconds and a timestamped kernel address event on either node proves
a VIP transition between failure and recovery. Missing or late recovery,
missing transition evidence, persistent family degradation, ambiguous or
simultaneous ownership, and every settled-owner failure reject; a retry is not
a broad waiver. Evidence that is missing, malformed, duplicated, reordered,
oversized, unsafe, incomplete, or cannot distinguish bounded convergence from
a settled-owner serving failure also rejects. The sampler and observer
lifecycle must prove bounded SIGTERM handling, child termination, timeout
escalation, and zero residue through the real entrypoints.
