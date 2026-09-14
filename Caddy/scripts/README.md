# Caddy scripts

`script-lifecycle.tsv` classifies the complete directory.

Production runtime programs include the protocol-v2 receiver, publisher,
finalizer, reconciler, health helpers, durable notification programs, and
certificate checks. The renderer, installer, validator, and uninstaller are
repository tools.

`prepare-lighttpd-config.sh` is a repository-only migration tool. It consumes
the retained desired-state input when an explicitly scoped migration needs to
prepare a candidate configuration; it is not installed, validated, or
uninstalled as a production-node runtime artifact.

No action-specific transaction is retained after its terminal archive. The
next successor is added only while its deployment window is `defined`. The
generic installer cannot perform a migration of an existing production
deployment.

The installer writes part of the repository-owned Caddy HA filesystem and
identity state. It is not a complete installation, migration, or recovery
interface and must not be presented as one. Package-owned files,
cross-repository configuration, SSH trust, and secrets are inventoried in
`Caddy/docs/REPRODUCIBILITY.md`.

`apply-serving-health-deployment.sh` and
`run-serving-health-deployment-outer.sh` are the single neutral, non-installable
deployment entrypoints. Successors change the small operation specification;
they never copy or rename these implementations.

Run:

```bash
Caddy/tests/deployment-lifecycle-policy.sh --check
Caddy/tests/deployment-lifecycle-regression.sh
```

`prepare-pihole-auth-release.sh` prepares the authentication-resilience
candidate in an empty protected `/tmp` directory using caller-supplied TLS
material. It checks accepted source hashes and validates the full candidate
with Caddy 2.11.4 for both node identities. It never publishes, installs,
reloads, or contacts a node. Failure leaves the caller-owned temporary output
for inspection; no candidate is accepted unless the command exits zero.

`validate-pihole-authentication.py` is the workstation-side Pi-hole Web v5.21
HTTP acceptance workflow. It accepts a protected password descriptor or
`--password-doppler` for the fixed reference shared by both nodes (operator
confirmed), requiring bounded input and
a successful provider exit before HTTP. It keeps sessions in memory, records
sanitized per-request outcomes, and never retries login POSTs. Its real-node execution belongs to the reviewed deployment operation;
it does not install or mutate Caddy configuration. See the authentication
resilience plan for secret input, health/ownership correlation, and limits.

The neutral transaction’s `auth-helper-*` modes implement monitor replacement
and exact rollback on either node. The outer runner’s `--authentication-helper-test`
uses local fixtures and simulated SSH to exercise installation, rollback, upload,
evidence readback, and cleanup without contacting a node.

The accepted standby stage is archived. The current `auth-primary-*` path checks
Node B’s accepted identity and Node A’s retained publication, activates that
publication locally through the installed finalizer/reconciler, and validates
Node A and shared-URL login. Only Node A is mutated; rollback preserves Node B
and the publication. Shared login requires `--shared-owner node-a`, supplied by
the outer after ownership checks and backed by continuous address observations.

`--connectivity-only` checks Node A and shared HTTPS paths before upload or secret
retrieval. `--production-path-test` runs the isolated full-stage qualification.
Execution requires current evidence through `CADDY_AUTH_QUALIFICATION_EVIDENCE`
and exact outer-runner authorization. See
[the authentication plan](../docs/AUTHENTICATION_RESILIENCE_PLAN.md).
