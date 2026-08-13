# Highly Available Caddy Reverse Proxy

This directory contains the production configuration, synchronization tooling,
systemd units, manifests, tests, and retained deployment history for the
dual-node Caddy service on the Pi-hole DNS pair.

Core deployment was accepted on 2026-08-11 by Actions 28ah, 29k, and 30e. Node
A is the preferred owner, Node B is the standby, and both nodes have validated
boot-persistent Caddy and synchronization services. The detailed evidence and
authorization history remain in
[`docs/caddy_plan-v1.1.md`](docs/caddy_plan-v1.1.md).

Durable notification queue ownership, retry semantics, and operator commands
are documented in
[`docs/APPRISE_DELIVERY.md`](docs/APPRISE_DELIVERY.md).

## Production architecture

Keepalived's `PIHOLE_DUALSTACK` synchronization group is the single ownership
authority for DNS and Caddy. Its `PIHOLE_IPV4` and `PIHOLE_IPV6` instances own
the DNS VIPs and install the corresponding Caddy VIPs as excluded addresses.
All four shared addresses therefore move together.

Caddy health does not participate in DNS VRRP health. A Caddy failure must not
remove or move DNS service. The historical separate `CADDY_IPV4`,
`CADDY_IPV6`, and `CADDY_DUALSTACK` model is obsolete and must not be used for
new deployment work.

| Role | Inventory host | System hostname | Management endpoint | Publishing |
| --- | --- | --- | --- | --- |
| Preferred | `pihole0` | `j1-svpihole0` | `pihole0.local.theama.co` | Normal protocol-v2 source |
| Standby | `pihole00` | `j1-svpihole00` | `pihole00.local.theama.co` | Guarded emergency source only |

The roles describe preference, not permanent runtime state. During a validated
failover Node B may become MASTER and own every shared VIP.

## Endpoints

| Endpoint | Purpose | Address ownership |
| --- | --- | --- |
| `proxy.local.theama.co` | Shared reverse-proxy endpoint | Caddy IPv4 and IPv6 VIPs |
| `pihole-admin.local.theama.co` | Pi-hole interface on the current DNS owner | Caddy IPv4 and IPv6 VIPs |
| `pihole0.local.theama.co` | Node A Pi-hole interface and management | Node A physical addresses |
| `pihole00.local.theama.co` | Node B Pi-hole interface and management | Node B physical addresses |

The shared Pi-hole endpoint follows the host holding the DNS VIPs. The two
node-specific endpoints remain independently accessible whenever their host,
Pi-hole, lighttpd, and Caddy services are available.

Authoritative DNS records and production Keepalived ownership configuration
belong to `homelab-dns`. Address allocation, subnets, and firewall policy
belong to `homelab-network`. The application values retained here are
summarized in [`manifests/deployment.yaml`](manifests/deployment.yaml) and
[`manifests/dns-records.yaml`](manifests/dns-records.yaml). Obsolete separate
Caddy VRRP values remain only in immutable historical action definitions;
`production_ownership` records the active coupled model without copying the
authoritative Keepalived configuration.

## Release synchronization

Configuration is distributed as validated protocol-v2 releases rather than as
an in-place writable configuration tree:

1. Node A normally publishes a complete candidate to Node B.
2. The restricted receiver validates source role, manifests, file types,
   certificate material, and Caddy configuration before creating completion
   state.
3. The reconciler consumes exact active replays first, then exactly one child
   of the active revision. It drains every safely ordered candidate, stages,
   promotes, and reloads atomically, and restores the previous selection if
   validation or reload fails.
4. Divergent candidates are quarantined instead of overwriting the active
   release. Competing children or an ambiguous queue fail closed.

Node B publication is rejected during normal operation. It is allowed only
through the guarded `--emergency` path while Node B is MASTER for both
`PIHOLE_IPV4` and `PIHOLE_IPV6`. lsyncd and reconciliation are operational
dependencies but are deliberately not VRRP health dependencies. The canonical
contract is [`manifests/synchronization-protocol-v2.yaml`](manifests/synchronization-protocol-v2.yaml).

## Systemd lifecycle

These persistent units must be enabled and active on both nodes:

- `caddy.service`
- `caddy-lsyncd.service`
- `caddy-sync-reconcile.path`
- `caddy-cert-expiry.timer`
- `caddy-sync-health.timer`

The timer- and path-triggered workers remain static and are not enabled
directly. `caddy-api.service` remains masked and inactive. The distribution
`lsyncd.service` also remains masked and inactive so only the managed
`caddy-lsyncd.service` can run. The obsolete `caddy-validate-reload.path` and
`caddy-validate-reload.service` remain absent because the reconciler owns
validation, promotion, reload, and rollback.

`caddy.service` requires `/etc/default/caddy-ha`; a missing environment file is
a startup failure. Managed lsyncd reads `/etc/lsyncd` and
`/var/lib/caddy-sync` but can write only its service-owned
`/run/caddy-lsyncd` directory. Worker scripts emit their exact failure reason,
and systemd `OnFailure` is the sole notification owner, preventing duplicate
delivery attempts. Current services use strict filesystem protection and a
private temporary directory.

The synchronization health timer runs every minute. It checks managed service
state, PID, restart count, the parseable lsyncd status snapshot, and new
cursor-bounded transport or quarantine failures. The status snapshot's age or
modification time is not a heartbeat.
Because the health timer is monotonic, it intentionally has no `Persistent=`
setting; missed calendar catch-up semantics do not apply.

## Repository layout

| Path | Contents |
| --- | --- |
| `configs/` | Lifecycle-classified production, deferred, and workstation configuration |
| `manifests/` | [Lifecycle-classified](manifests/README.md) current contracts, accepted identities, and immutable action definitions |
| `scripts/` | [Lifecycle-classified](scripts/README.md) production tools and preserved action artifacts |
| `systemd/` | Managed services, timers, paths, and drop-ins |
| `templates/` | [Lifecycle-classified](templates/README.md) production inputs, historical artifacts, and deferred examples |
| `tests/` | Current focused validation and preserved historical reconstruction tests |
| `tools/` | Workstation protocol probes and audit-output utilities |
| `docs/caddy_plan-v1.1.md` | Governing plan, decisions, deviations, execution evidence, and authorization provenance |

Production host membership and role differences are maintained under
[`../inventory/prod/`](../inventory/prod/).
The complete component lifecycle catalog is
[`configs/README.md`](configs/README.md).

## Validation

Use the manifest-driven focused runner from the repository root. It selects
current production tests and policies without replaying the complete historical
deployment suite.

```bash
Caddy/tests/run-focused.sh --changed --base origin/main --explain
Caddy/tests/run-focused.sh --changed --base origin/main
```

Use a named profile when validating one current boundary directly:

```bash
Caddy/tests/run-focused.sh --profile current-synchronization
Caddy/tests/run-focused.sh --profile current-systemd-boot-persistence
```

`Caddy/tests/run.sh` and `Caddy/tests/integration.sh` are opt-in historical
reconstruction entry points. They are not current deployment or acceptance
gates.

## Operational boundaries

- Do not rerun consumed deployment actions.
- Require exact authorization for live mutation, transfer, failover, or service
  transition actions.
- Keep node-local and workstation evidence beneath protected `/tmp`
  directories during live actions.
- Preserve executed runners, authorization hashes, and retained evidence.
- Treat notification delivery as best effort; delivery failure must not block
  a VRRP transition.
- Use the governing plan for recovery details and accepted deviations until the
  dedicated installation, removal, and troubleshooting documents are created.
