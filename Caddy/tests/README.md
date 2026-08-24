# Caddy current-production validation

This directory contains neutral tests and policies for the current production
tree. The archive tag in `Caddy/HISTORY.md` preserves action-specific and
historical tests.

`focused-validation.yaml` maps current paths to host tests, Debian-sensitive
tests, and named policies.

```bash
Caddy/tests/run-focused.sh --list
Caddy/tests/run-focused.sh --profile current-synchronization --phase host --container never
Caddy/tests/run-focused.sh --changed --base HEAD --explain
```

The explicit `--phase host --container never` pair is required for a host-only
run. Without it, the runner's default `all/auto` mode continues into Podman.

Use one network-disabled Debian batch when Debian behavior is in scope. Run
this wrapper outside the filesystem sandbox on its first attempt:

```bash
Caddy/tests/run-focused-container.sh --profiles current-synchronization
```

Current tests must execute current entrypoints. They cannot delegate behavior to
an archived action regression. Register every test in
`test-lifecycle.tsv`.

Policy files own their focused negative controls through a no-argument
self-test mode; pre-commit invokes the same files with `--check`. Do not add a
separate regression or pre-commit adapter when the policy can exercise the
case directly.

`operator-documentation-policy.sh` enforces the six-document operator set,
authority links, current entrypoints, accepted-live boundary, and isolation of
future-project prompts from current runbooks.
