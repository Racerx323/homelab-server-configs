# Caddy test inventory

This directory contains two deliberately separate test surfaces.

## Current production validation

`focused-validation.yaml` maps current production paths to bounded host tests,
Debian-sensitive tests, and named repository policies. Use:

```bash
Caddy/tests/run-focused.sh --changed --base HEAD --explain
Caddy/tests/run-focused.sh --profile current-synchronization
```

Changed-path selection runs Debian only when a changed path matches the
profile's `debian_path_patterns`. Documentation, lifecycle metadata, accepted
hash registries, and workstation-only consumers remain host-only. Debian runs
use one network-disabled container and retain their summary beneath the host
evidence directory reported by the runner.

Neutral current-production regressions may delegate to an immutable accepted
producer regression when the reusable producer still has a historical action
name. The neutral entry point owns current selection; the action file remains
unchanged provenance and is never selected directly by a current profile.

## Historical reconstruction

Action-named tests, `run.sh`, and `integration.sh` preserve deployment history.
They are explicit opt-in reconstruction tools and are not deployment gates.
Use `run-focused.sh --action ID` only when intentionally reconstructing one
historical action. Do not run the complete historical host/Podman suite for
routine development or final deployment acceptance.

## Lifecycle registry

`test-lifecycle.tsv` classifies every tracked entry:

- `production-current`: current runner, policies, reusable tests, and support.
- `historical-preserved`: immutable action and full-suite history.
- `test-fixture`: non-entrypoint input used only by tests.

`test-lifecycle-policy.sh --check` rejects missing, duplicate, extra, malformed,
or incorrectly classified entries. Executed action files remain historical even
when a neutral current regression consumes their accepted producer contract.

## Adding or changing tests

1. Add the path to `test-lifecycle.tsv`.
2. For current behavior, add a neutral regression and select it through the
   appropriate focused profile.
3. Add a Debian path pattern only when the behavior depends on Debian tools,
   packages, identities, permissions, mounts, or runtime semantics.
4. Keep action-specific artifacts out of current profile test arrays.
5. Run the focused manifest, lifecycle, shell-mode, formatting, and relevant
   profile checks. Do not repair preserved historical artifacts in bulk.
