# Caddy HA reproducibility boundary

This document identifies what can be rebuilt from source control and what must
be supplied or captured separately. It does not claim that unobserved runtime
state matches a repository file.

## Repository-owned exact state

The current Caddy HA layer is defined by these contracts:

- `Caddy/manifests/production-artifacts.tsv` records accepted deployed
  identities for both nodes.
- `Caddy/manifests/caddy-release-source.tsv` pins the five source files in the
  accepted immutable Caddy release.
- The lifecycle manifests enumerate every current Caddy configuration,
  manifest, script, systemd unit, and template.
- `Caddy/manifests/dependencies.yaml` records package, command, source, and
  external-input dependencies.
- `Caddy/manifests/reproducibility-production.yaml` records the exact package,
  Pi-hole application, lighttpd-tree, Unbound, and public SSH identities
  observed on both nodes on 2026-08-24.
- `homelab-dns` owns Keepalived, Pi-hole, DNS health, notifier, and Unbound
  source files. Paths used by this deployment are listed in
  `dependencies.yaml`.

The generated `/etc/default/caddy-ha` differs by node and is rendered from
`Caddy/templates/caddy-ha.env-v2.in`. The active Caddy tree is built from the
release-source manifest and must be published through protocol v2. Neither
generated file should be copied from another node.

## Package-owned state

Debian packages own the base Caddy, lighttpd, Keepalived, and Unbound units and
application trees. The Pi-hole application manages Pi-hole core, web, and FTL.
This repository owns only the listed drop-ins and HA-specific files. Restore
package-owned files from their packages and Pi-hole-owned files through the
Pi-hole application; do not copy either class into this repository.

The platform is Debian 12 on arm64. Exact installed package versions are pinned
in `reproducibility-production.yaml` and were identical on both nodes. Pi-hole
FTL is managed by the Pi-hole application rather than dpkg; its application
versions and binary identity are recorded separately from Debian packages.

The active lighttpd trees were identical. Their exact identity, package and
Pi-hole versions, desired state, and transformation tool are recorded. The
only full-tree difference was the node-specific
`conf-disabled-by-caddy-ha/external.conf`, which is outside the active
configuration and is not a rebuild input.

## Required Unbound configuration pair

The HA resolver requires both repository-owned Unbound fragments on each node:

- `homelab-dns/Unbound/configs/pihole.conf` at
  `/etc/unbound/unbound.conf.d/pihole.conf` owns resolver behavior.
- `homelab-dns/Unbound/configs/pihole-local-zone.conf` at
  `/etc/unbound/unbound.conf.d/pihole-local-zone.conf` owns the internal zone
  policy and records.

Both files must be installed as `root:root:0644`. The canonical reproducibility
manifest records each source hash, deployed hash, path, mode, and dual-node
identity. A rebuild is incomplete if either fragment is absent or differs from
its accepted identity.

## Required external inputs

These inputs are deliberately absent from Git:

- TLS certificate, chain, and private key material supplied from Doppler.
- The `caddy-sync` SSH private keys, peer public keys, and `known_hosts` trust.
  The repository contains the forced-command template, not key material.
- Apprise API configuration and credentials owned by `homelab-notification`.
- Network and firewall configuration owned by `homelab-network`.

Provision these inputs through their owning systems. Do not add secrets or
private keys to a production manifest.

## Inventory reconciliation

The bounded dual-node inventory on 2026-08-24 proved the installed
`pihole.conf` on both nodes matches the repository SHA-256. The previously
accepted `pihole-local-zone.conf` identity remains identical across both nodes.
Both required fragments are recorded in the accepted-live, production, and
canonical reproducibility inventories.

That inventory also proved identical package sets, Pi-hole application and FTL
identities, identical active lighttpd trees, reciprocal synchronization keys,
and reciprocal Ed25519 host trust. The raw bounded evidence remains under the
workstation `/tmp` path reported with the reconciliation; the durable identity
record is `Caddy/manifests/reproducibility-production.yaml`.

Private keys, TLS private-key bytes, environment secrets, and notification
credentials were neither read nor retained. Restoring those external inputs
from their owning systems remains part of a rebuild.

## Rebuild order

1. Install the recorded Debian package set and verify exact package versions
   against an approved baseline.
2. Restore the externally owned Pi-hole, Unbound, Keepalived, network, Apprise,
   TLS, and SSH trust inputs.
3. Install the Caddy HA runtime with the neutral installer on Node B first.
4. Render Node B's environment locally and publish the accepted immutable
   release through protocol v2.
5. Validate services, node-specific endpoints, and zero shared VIP ownership on
   Node B.
6. Repeat the installation and validation on Node A, then require settled Node
   A MASTER and Node B BACKUP ownership with all four VIPs on Node A.
7. Run the current synchronization and serving-health validation profiles.

Never restart or reload both HA nodes together. A rebuild is complete only when
installed hashes, service state, dual-stack endpoints, synchronization, durable
notifications, and settled VRRP ownership all pass.
