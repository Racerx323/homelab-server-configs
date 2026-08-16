# Deployment lifecycle

`deployment-streams.tsv` registers every live deployment stream in this
repository. The data-driven policy in
`Caddy/tests/deployment-window-policy.sh` applies the same lifecycle without
component-specific exceptions.

## Window states

- `clean`: accepted production state only; no action-numbered implementation
  files and no deployable successor.
- `defined`: exactly one registered successor with real production-path
  coverage. Only that action's numbered implementation files may exist.
- `terminal-pending`: the action ran and reached an accepted,
  `failed-consumed`, or `manual-intervention` result. Its deployable registry is
  already cleared, but its exact files remain for the terminal-result commit
  and annotated archive tag.

## Close an action

1. Record the terminal result in the governing plan and component history.
2. Clear the deployable successor and coverage registries.
3. Set the stream to `terminal-pending` with the exact action, result, and
   planned annotated tag.
4. Commit while the executed action files are still present.
5. Create and push the annotated tag for that exact commit.
6. Remove the consumed action files and retained repository evidence.
7. Set the stream to `clean`, retaining the latest archive tag.
8. Commit and push the cleanup before defining another action.

Git history and annotated tags are the immutable deployment archive. The main
branch contains current production, neutral validation, and at most one
defined successor per deployment stream.
