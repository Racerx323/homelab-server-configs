# Future complete-installation project prompt

Resume from the accepted Caddy/DNS production architecture documented in
`Caddy/docs/caddy_plan-v1.1.md`. This task plans a reproducible clean-node
installation. It does not authorize implementation, node contact, production
mutation, or a Caddy deployment successor.

## Objective

Define an ordered, idempotent installation and configuration contract that can
reproduce the accepted dual-node Caddy/DNS environment from a clean compatible
operating-system baseline. Do not build an installer until the operator accepts
the dependency map and ownership model.

## Required discovery

Map every required artifact, service, identity, permission, input, and
configuration owner across:

- `homelab-server-configs`;
- `homelab-dns`;
- `homelab-network`;
- Pi-hole-managed application state;
- Debian packages and package-owned units;
- local users, groups, supplementary groups, directories, and modes;
- TLS certificates, private keys, and secret retrieval;
- SSH keys, host trust, authorized commands, and synchronization access;
- firewall and routing policy; and
- the Apprise API and durable notification client.

Identify every shared value and node-specific customization. Include hostnames,
addresses, roles, paths, ports, package versions, service enablement, timers,
VRRP ownership, DNS data, TLS names, external credentials, and recovery inputs.
Label each item as repository-owned, package-owned, Pi-hole-owned,
network-owned, secret/external, generated, or runtime state.

## Design requirements

Produce a decision-complete installation design that:

1. establishes prerequisites and external inputs before filesystem mutation;
2. installs and validates one standby node before changing the preferred node;
3. creates identities, directories, configuration, units, secrets, and trust in
   a deterministic order;
4. initializes immutable protocol-v2 publication, transfer, finalization,
   reconciliation, and activation without bypassing their contracts;
5. separates idempotent installation from production upgrades;
6. defines interruption recovery and reverse-order rollback at every mutation
   boundary;
7. preserves releases, notification queues, dead letters, and evidence unless a
   separately approved purge contract applies; and
8. defines safe uninstall from the same lifecycle and ownership model.

Evaluate `Caddy/scripts/install-caddy-ha.sh` against the accepted design and
recommend one disposition: replace it, absorb its safe primitives into the new
implementation, or retire it. Do not assume that its current bootstrap behavior
is the future interface.

## Validation design

Specify validation against a clean Debian 12 arm64 or Raspberry Pi-compatible
environment before any HA-node use. The future implementation must prove:

- exact repository and accepted-live hashes;
- package and Pi-hole application prerequisites;
- users, groups, ownership, modes, and systemd dependencies;
- successful service, path, and timer behavior;
- protocol-v2 publication and synchronization;
- trusted IPv4 and IPv6 DNS and HTTPS service;
- Node A preferred MASTER ownership of all four VIPs;
- Node B BACKUP ownership of zero VIPs;
- durable notification enqueue, retry, and recovery; and
- zero unexpected residue after rollback, interrupted installation, and
  uninstall tests.

Use causal production-path tests for installation, activation, rollback, and
recovery. Do not treat emitted labels, prewritten fixture results, or current
production state as proof of a clean installation.

## Required deliverables

Stop after producing:

- the complete dependency and ownership inventory;
- the shared and node-specific input schema;
- the ordered installation and configuration lifecycle;
- the upgrade, interruption-recovery, rollback, and uninstall contracts;
- the proposed installer interface and disposition of
  `install-caddy-ha.sh`;
- the clean-environment test and acceptance design; and
- explicit implementation and live-authorization boundaries.

Do not write the installer, contact either HA node, register a deployment
successor, or mutate production during this planning project.
