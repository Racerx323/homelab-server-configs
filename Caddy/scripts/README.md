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

`validate-pihole-authentication.py` is the workstation-side Pi-hole Web v5.21
HTTP acceptance workflow. It accepts a protected password descriptor or
`--password-doppler` for the fixed reference shared by both nodes (operator
confirmed), requiring bounded input and
a successful provider exit before HTTP. It keeps sessions in memory, records
sanitized per-request outcomes, and never retries login POSTs. Its real-node execution belongs to the reviewed deployment operation;
it does not install or mutate Caddy configuration. See the authentication
resilience plan for secret input, health/ownership correlation, and limits.

The completed authentication migration scripts, transaction modes, and deployment
qualification fixtures are archived in the pushed tags in [HISTORY.md](../HISTORY.md).
The current deployment stream contains the defined replacement certificate-inventory repair.
The login validator remains available for
accepted-production validation under the authentication and ownership procedure;
no archived deployment is registered or executable through the outer runner.

The certificate repair uses the same neutral transaction and outer runner. Its
payload contains only the publisher and `certificate-release-inputs.tsv`; TLS
material stays on the nodes. Node A publishes using the uploaded publisher,
Node B is accepted first, and only then are Node A's installed publisher and
serving selection changed. Rollback contains publication before restoring
selections and publishers in reverse order. Status 125 preserves evidence when
restoration cannot be proven. See `manifests/serving-health-operation.yaml` for
the exact scope and `docs/OPERATIONS.md` for qualification.
