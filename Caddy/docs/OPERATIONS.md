# Caddy HA operations

This runbook covers the accepted production operating model. Read-only checks
are copyable. Every publication, service change, failover, or rollback requires
a reviewed operation, exact authorization boundary, and retained evidence.

## Authorities

- [`caddy_plan-v1.1.md`](caddy_plan-v1.1.md) owns architecture and lifecycle
  decisions.
- `Caddy/manifests/accepted-live-artifacts.tsv` owns deployed identities.
- `Caddy/manifests/current-live-state.tsv` owns the accepted semantic baseline.
- `Caddy/manifests/synchronization-protocol-v2.yaml` owns release transport and
  reconciliation.
- [`APPRISE_DELIVERY.md`](APPRISE_DELIVERY.md) owns notification delivery.
- [`APPLICATION_ONBOARDING.md`](APPLICATION_ONBOARDING.md) owns the backend
  inventory and reverse-proxy fragment review contract.

Do not treat a newer repository source hash as installed production. Compare
repository and accepted-live identities through
`Caddy/manifests/runtime-production.tsv`.

## Routine inspection

Use [`QUICK_START.md`](QUICK_START.md) for node, endpoint, synchronization,
timer, and queue checks. Require Node A MASTER with four shared VIPs and Node B
BACKUP with none during normal operation.

## Production change gate

Before mutation:

1. require a clean synchronized repository and clean Caddy deployment stream;
2. record the accepted-live and semantic baseline;
3. define one small operation specification against the neutral transaction;
4. run the exact production-path coverage and repository checks;
5. obtain authorization for the reported outer-runner SHA-256; and
6. apply and accept Node B before changing Node A.

The neutral entrypoints are:

```text
Caddy/scripts/apply-serving-health-deployment.sh
Caddy/scripts/run-serving-health-deployment-outer.sh
```

Do not copy or rename them for a new operation. A clean stream rejects live
execution and `--authorization-ready`.

## Normal protocol-v2 publication

Node A is the normal publisher. The installed interface is:

```text
sudo /usr/local/libexec/publish-release-v2.sh \
  --source PREPARED_RELEASE_DIRECTORY --node-role node-a
```

The command shape documents the interface; it does not authorize execution.
The prepared release must contain the exact reviewed Caddy configuration and
TLS inputs. The publisher validates Caddy, certificate, key, path, link, and
manifest safety before exposing an immutable outbound revision.

Managed lsyncd transfers the candidate. Node B's forced-command receiver and
finalizer validate it and create the local completion marker. The reconciler
selects one valid child, activates it atomically, reloads Caddy, and removes the
accepted incoming candidate.

Do not copy files into `/etc/caddy/current`, create completion markers, invoke a
remote finalizer through an ad hoc SSH command, or edit an immutable release.

## Application backends

Use [`APPLICATION_ONBOARDING.md`](APPLICATION_ONBOARDING.md) before preparing a
new application fragment. Obtain approval for the complete backend inventory;
render and validate the supported example; reconcile repository and DNS state;
then define a separate production operation. The example is not deployable and
does not belong in a production release until the operator approves its exact
rendered fragment.

## Emergency Node B publication

Node B may publish only during a separately authorized emergency while it owns
both VRRP families and all four shared VIPs. The installed interface adds
`--emergency`:

```text
sudo /usr/local/libexec/publish-release-v2.sh \
  --source PREPARED_RELEASE_DIRECTORY --node-role node-b --emergency
```

The publisher rejects Node B without coupled MASTER ownership. Emergency
publication retains the same manifest, finalization, reconciliation, evidence,
and rollback rules as normal publication.

## Standby-first maintenance

1. Prove the preferred peer is healthy and owns all four VIPs.
2. Capture service, journal-cursor, endpoint, and ownership baselines.
3. Change one component on Node B.
4. Require repeated healthy service and BACKUP observations on Node B.
5. Change Node A only after Node B acceptance.
6. Require Node A MASTER, Node B BACKUP, dual-stack continuity, and clean
   protocol-v2 residue.

Never restart or reload both nodes together. Planned Keepalived stops require
the accepted maintenance context so notifications do not describe them as
unexpected failures.

## Rollback and status 125

Rollback restores mutations in reverse order and revalidates services,
endpoints, synchronization, and settled ownership. A pre-mutation rejection
uses cleanup only. Status 125 means a mutation occurred and recovery could not
be proven; stop further work and retain all bounded evidence.

## Certificates

The certificate timer checks `/etc/caddy/current/tls/leaf.pem`. Inspect it with:

```bash
systemctl --no-pager --full status caddy-cert-expiry.timer
journalctl -u caddy-cert-expiry.service --since today --no-pager
openssl x509 -in /etc/caddy/current/tls/leaf.pem \
  -noout -subject -issuer -dates
```

Certificate replacement is a new immutable release. Do not overwrite TLS files
inside the active release.

## Synchronization and release retention

```bash
sudo /usr/local/libexec/validate-sync-health.sh
systemctl --no-pager --full status \
  caddy-lsyncd.service caddy-sync-reconcile.path
journalctl -u caddy-lsyncd.service \
  -u caddy-sync-reconcile.service --since today --no-pager
```

Inspect complete incoming, outbound, and quarantine inventories before service
control. Preserve active releases, their ancestors required by policy, queue
records, and failure evidence. Remove only exact validated, unreferenced state
through a reviewed transaction.
