# Caddy HA installation boundary

This document records the current installation boundary. It does not provide a
clean-node installation or disaster-recovery procedure. No current repository
entrypoint installs and configures the complete Caddy/DNS HA environment.

## Authority

| Area | Authority |
| --- | --- |
| Accepted deployed identities | `Caddy/manifests/accepted-live-artifacts.tsv` |
| Source-to-installed mapping | `Caddy/manifests/production-artifacts.tsv` |
| Runtime source/deployed boundary | `Caddy/manifests/runtime-production.tsv` |
| Rebuild inputs and external recovery | [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) |
| Architecture and authorization | [`caddy_plan-v1.1.md`](caddy_plan-v1.1.md) |
| DNS, Unbound, Pi-hole, and Keepalived source | `homelab-dns` |
| Network and firewall source | `homelab-network` |

The accepted-live hash is production truth. A different repository-source hash
does not prove production drift and does not authorize installation. Deploying
newer source requires a reviewed operation and a new accepted-live record.

## Required facts

Before anyone designs or authorizes installation work, establish:

- Debian 12 arm64 package identities and package-owned service files;
- Pi-hole Core, Web, and FTL versions and Pi-hole-owned state;
- both required Unbound fragments and their installed identities;
- node-specific Keepalived configuration and DNS health scripts;
- Node A and Node B hostnames, addresses, roles, and generated Caddy
  environments;
- Caddy, lighttpd, lsyncd, sysctl, tmpfiles, and systemd inputs;
- `caddy`, `caddy-sync`, `caddy-tls`, and `keepalived_script` identity and group
  requirements;
- Doppler-managed TLS inputs;
- reciprocal SSH keys, host trust, and forced-command authorization;
- firewall and routing policy; and
- the external Apprise API plus persistent local queue state.

`Caddy/manifests/dependencies.yaml` and
`Caddy/manifests/reproducibility-production.yaml` record the current known
inputs. They are inventories, not an installer.

## Partial repository tools

`Caddy/scripts/install-caddy-ha.sh` installs part of the repository-owned
filesystem and identity state. It does not install or reconcile the complete
package, Pi-hole, DNS, network, secret, SSH-trust, activation, or HA ownership
contract. Its Caddy component refuses an existing `/etc/caddy/current` and is
not a production installation, migration, or recovery interface.

`Caddy/scripts/render-node-config.sh` renders node-specific repository inputs.
Never copy a rendered Node A environment to Node B or the reverse.

`Caddy/scripts/validate-caddy-ha.sh` checks installed repository-owned files and
Caddy parsing. It does not prove package completeness, service continuity,
protocol-v2 synchronization, notification delivery, or settled VRRP ownership.

Do not combine these tools into an improvised clean-node procedure.

## Current production-change path

Routine production changes use the neutral transaction and outer runner:

- `Caddy/scripts/apply-serving-health-deployment.sh`
- `Caddy/scripts/run-serving-health-deployment-outer.sh`

They become usable only when one reviewed operation specification is registered
and production-path validation passes. The clean stream has no authorized
operation. Caddy configuration moves through the immutable protocol-v2
publisher, receiver, finalizer, and reconciler. See
[`OPERATIONS.md`](OPERATIONS.md).

## Installation acceptance boundary

An installation claim requires all of these results from one approved process:

- exact expected installed hashes, owners, groups, and modes;
- active required services, paths, and timers;
- identical accepted immutable release on both nodes;
- clean incoming, outbound, and quarantine protocol-v2 namespaces;
- healthy managed lsyncd and reconciliation;
- successful IPv4 and IPv6 DNS and trusted HTTPS checks;
- functioning durable enqueue and delivery recovery;
- Node A settled as MASTER with four VIPs; and
- Node B settled as BACKUP with zero VIPs.

Current repository tools do not implement that complete process.
