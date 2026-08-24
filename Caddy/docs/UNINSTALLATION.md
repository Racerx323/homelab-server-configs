# Caddy HA uninstallation

Uninstallation changes live serving and HA dependencies. It requires a reviewed
standby-first operation and explicit authorization. The repository uninstaller
removes files only; it does not stop, disable, reload, or validate services.

## Ownership boundaries

This repository may remove only paths classified as Caddy-owned in the script
and systemd lifecycle manifests. It must not remove:

- Pi-hole Core, Web, or FTL state;
- Unbound configuration;
- Keepalived configuration or DNS health scripts;
- package-owned base units or application trees;
- network-controller or firewall configuration;
- TLS and SSH recovery sources; or
- persistent notification queue records without a separate purge decision.

[`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) records those owners.

## Required coordination

Keepalived currently depends on Caddy serving health and owns the Proxy VIPs in
the coupled `PIHOLE_DUALSTACK` group. Removing Caddy files while that contract
remains active can force a node into FAULT. Before Caddy removal, a separately
authorized change in `homelab-dns` must remove or replace the Caddy eligibility
and Proxy-VIP contract and prove stable DNS ownership.

Do not improvise that cross-repository change from this runbook.

## Standby-first sequence

For each node, starting with Node B:

1. Prove the peer is healthy and owns every remaining shared service address.
2. Capture a fresh journal cursor, installed-path inventory, queue counts,
   release selection, service state, and ownership state.
3. Stop and disable Caddy-owned timers, paths, and services through the
   authorized transaction.
4. Preserve persistent releases and notification state unless the approved
   scope names an exact disposition.
5. Run the repository uninstaller's dry run and compare every reported path
   with the approved scope.
6. Remove only the approved Caddy-owned files.
7. Run `systemctl daemon-reload`, prove the intended units are absent or
   disabled, and verify the remaining DNS service and peer ownership.
8. Continue to Node A only after Node B acceptance.

Never stop or remove both nodes together.

## Repository uninstaller boundary

The repository tool accepts:

```text
Caddy/scripts/uninstall-caddy-ha.sh \
  --node node-a|node-b --dry-run [--preserve-releases]
```

Remove `--dry-run` only inside the authorized transaction after validating the
reported paths. Use `--preserve-releases` when release retention is required.
Without it, the tool removes `/etc/caddy/current` and the bootstrap release. It
does not remove every immutable production release.

The tool reports `service_mutations: false`. Operators must not treat a zero
exit status as proof that services, timers, HA ownership, endpoints, or
cross-repository dependencies are safe.

## Queue and evidence preservation

The uninstaller removes installed notification programs and units but preserves
`/var/lib/caddy-apprise-queue`. Before removal, record counts for `pending`,
`inflight`, `delivered`, and `dead-letter`, filesystem capacity, owners, modes,
and the worker journal.

Do not delete or edit queued JSON. Purging the queue is a separate destructive
operation with its own evidence and authorization. Follow
[`APPRISE_DELIVERY.md`](APPRISE_DELIVERY.md).

## Acceptance

Require:

- every removed path belonged to the approved Caddy inventory;
- every preserved release and queue record retains its identity and metadata;
- no removed unit remains active or enabled;
- package-owned and externally owned files remain unchanged;
- DNS remains healthy over IPv4 and IPv6;
- the surviving HA ownership contract is settled and unambiguous; and
- no transaction-owned temporary path or process remains.

If a mutation occurred and recovery cannot be proven, return status 125 and
retain the evidence.
