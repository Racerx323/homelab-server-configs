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

## Authentication resilience integration

Build the dedicated local image from the cached Caddy 2.11.4 validation image:

```bash
podman build -f Caddy/tests/Containerfile.authentication \
    -t localhost/caddy-auth-validation:latest .
podman run --rm --network none \
    --env CADDY_VALIDATION_CONTAINER=1 \
    --volume /home/aaron/code:/workspace:ro \
    localhost/caddy-auth-validation:latest -lc \
    'cd /workspace/homelab-server-configs && /bin/bash Caddy/tests/run-focused.sh --profile authentication-resilience --phase container --container never'
```

The dedicated image adds Python to the existing Debian image. The regression
runs real Caddy with the exact accepted and prepared proxy snippets, a local
causal HTTP backend, and a temporary trusted certificate. Full candidate
adaptation/validation precedes the isolated listener projection. It tests
connection failure amplification, no POST replay, rejected login and immediate
retry, separate clients, logout, both families, no backend connection reuse,
and real active-health exclusion/recovery. It also exercises the real
`validate-pihole-authentication.py` workflow and rejects an incorrect supplied
valid password. It is not real Pi-hole acceptance
and makes no claim about production VIP ownership. Node B is the designated
real-application acceptance target, subject to the deployment authorization.

The `authentication-resilience` host phase runs
`authentication-secret-regression.sh`. It exercises real isolated secret
producer processes, including failure after nonempty output, timeout, invalid
input, descriptor cleanup, and error redaction. It never retrieves a real
Doppler secret or contacts a node. The dedicated container phase runs this
boundary regression before the real-Caddy fixture.

The `authentication-deployment` profile exercises the actual neutral transaction
and outer runner for atomic web-monitor replacement and rollback. It tests
fourteen filesystem state variants over an isolated SSH transport that preserves
remote-shell parsing. Run the host profile with `--phase host --container never`
and the Debian batch with `run-focused-container.sh --profiles authentication-deployment`.
The same regression now constructs and transfers the real minimal payload,
checks deterministic output, and rejects altered validator, missing config,
symlink, and hardlink inputs before archive creation. Coordinator preflight and interruption coverage belongs to the full container
profile below; host helper tests never invoke its network-dependent path. Helper
coverage alone is not full release or login acceptance. No real node or secret
provider is contacted.

The dedicated `authentication-resilience` container profile also runs
`authentication-release-regression.sh`. Its seven scenarios execute the real
publisher, finalizer, accepted deployed reconciler, and transaction release modes, including
publication-reply failure, failed reloads, restoration retry, candidate tamper
rejection, and successful retention of Node B's candidate and Node A's
publication. The acceptance case rejects inactive application services and
unexpected peer incoming residue. Only systemd/ownership queries and the
lsyncd transfer are substituted. This fixture requires the disposable root
container and never changes workstation or production service state. It is
release-phase coverage, not complete outer-runner or real-login acceptance.

The accepted reconciler fixture is loaded by Git blob ID and checked against its
accepted SHA-256 before execution. Its difference from current source is confined
to a self-test fixture name. This tests the installed runtime identity without
changing accepted production files or executing an archived deployment transaction.

## Full authentication outer-stage qualification

After building the authentication image above, run the complete isolated stage:

```bash
/bin/bash Caddy/tests/run-focused-container.sh --profiles authentication-outer
```

The wrapper selects `localhost/caddy-auth-validation:latest`, retains
`--network none`, and adds `--init`, `--cap-add NET_ADMIN`, and `--cap-add SYS_ADMIN`.
Fixture addresses exist only in the container; private mount namespaces give Node A
a separate filesystem for the unmodified finalizer/reconciler and Caddy process.
The init process reaps observer children. It
retains bounded evidence in the directory printed at completion. The test must
not be run directly on a workstation or production host.

`authentication-outer-regression.sh` runs sixteen scenarios through the real neutral
outer entrypoint: missing IPv6 connectivity, untrusted TLS, HTTP 503, inactive
backend preflight, retained-publication drift, interrupted preflight, success,
node login failure, shared login failure, restoration failure, interruption after
monitor installation, evidence-readback failure, DNS degradation, lost activation
reply, failed reconciliation reload, and reordered evidence. It executes actual
Caddy reloads, publisher/finalizer/reconciler programs, HTTP login validation,
web-monitor checks, samplers, and release/helper restoration. The fixture models
SSH transport, systemd, DNS, HA ownership, and journal collection; it does not
replace transaction modes or pre-write successful observations. Corruption tests
modify actual producer output. Assertions inspect actual filesystem state and
return status independently of the runner labels. They also validate emitted
phase order, the actual login HTTP outcomes, and absence of sampler or kernel
address-monitor processes after the stage. The DNS-failure case covers scenario
changes during retries; a primary and its retry retain the same scenario label.

These are full-stage fixture results, not real Pi-hole or production acceptance.
The accepted Node B operation is archived. Its primary-activation replacement
starts from an independently produced standby candidate and retained publication. `authentication-deployment-policy.py` checks
the pinned source graph and validates the retained per-scenario decisions against
actual producer streams, statuses, command order, and independent state. Run the
registered outer runner with `--production-path-test`, then pass its reported
evidence directory through `CADDY_AUTH_QUALIFICATION_EVIDENCE` when running
`deployable-successor-policy.sh --authorization-ready`. Missing, changed, or stale
evidence fails the gate; `--check` validates only the repository definition.

With `CADDY_AUTH_QUALIFICATION_EVIDENCE` set to a completed qualification directory,
`deployable-successor-policy-regression.sh` also verifies evidence rejection for
missing files, unsafe modes, symlinks, changed streams, stale source graphs, and
rehashed duplicate commands. It modifies only temporary copies of the evidence.

The workstation connectivity checks use real HTTPS through the same validator
client as login acceptance. Negative fixtures remove Node A's IPv6 address,
select an untrusted CA store, or return HTTP 503. Each must reject before any
SSH/SCP or Doppler invocation and preserve the original Node A and accepted Node B release/monitor identities.
The full fixture also covers pre-mutation service rejection and interruption;
host helper tests do not invoke the network-dependent coordinator.
