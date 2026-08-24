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
