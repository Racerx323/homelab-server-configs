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

## Accepted-production authentication validation

The `authentication-resilience` profile validates the current Pi-hole proxy source
with real Caddy and a causal local HTTP backend in a network-disabled container:

```bash
/bin/bash Caddy/tests/run-focused-container.sh --profiles authentication-resilience
```

It validates the complete configuration for both node identities, then projects
only test listeners and synthetic TLS. The production proxy snippet is unchanged.
It checks incorrect-password rejection, immediate successful login, dashboard,
logout, denied access after logout, and concurrent IPv4/IPv6 requests. A deliberately
closed upstream POST must yield one 502 without replay, followed by an immediately
successful GET. A sustained backend outage must trigger active-health exclusion
and recover when the backend returns. The test does not recreate the obsolete
passive-exclusion configuration.

`authentication-secret-regression.sh` tests the login validator's bounded password
input, provider failure/timeout handling, and sanitized diagnostics. Test secrets
and certificates are synthetic and remain inside the fixture.

Completed migration publication, activation, rollback, outer-runner qualification,
and evidence-policy tests are available only through the pushed archive tags.
Current tests do not replay those operations. The neutral deployment policy checks
that the registered stream and operation specification agree.

`certificate-release` runs in the Python-enabled Debian validation image. It
executes the real outer runner, payload upload/readback helpers, transaction,
publisher, finalizer, reconciler and expiry checker against synthetic node
filesystems. Transport switches node filesystems; service-manager responses and
journals follow the commands that change their state. The suite checks normal
acceptance, preflight rejection, failed worker/reload paths, evidence corruption,
ownership transitions and unproven rollback. It retains command streams and node
snapshots for independent qualification verification. The HTTPS substitute reads
the `/healthz` response from each selected production fragment; workstation,
node and readback acceptance require HTTP 204.

For this scope, `deployable-successor-policy.sh --check` checks the definition.
`--authorization-ready` additionally requires `CADDY_CERTIFICATE_QUALIFICATION_ROOT`
to identify the retained `certificate-release` evidence directory. It verifies
that evidence against the current source graph, node snapshots, readback hashes
and coverage decisions. A host-only deferral is not qualification.
