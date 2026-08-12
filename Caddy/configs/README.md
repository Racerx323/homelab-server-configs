# Caddy Configuration Inventory

This directory contains configuration payloads associated with the Caddy HA
service. It is not a general archive: every tracked component below has an
explicit lifecycle classification.

## Lifecycle classifications

- `production-current`: accepted configuration used by the HA nodes.
- `deferred`: intended component configuration outside core deployment
  acceptance.
- `workstation`: operator-workstation configuration that is never installed on
  an HA node.
- `historical`: retained only because an immutable action or regression depends
  on its exact path. Historical files are not deployment sources.

Only `production-current` entries belong in a production-node payload.

## Component catalog

| Repository path | Lifecycle | Installed or consumed as | Notes |
| --- | --- | --- | --- |
| `caddy/Caddyfile` | `production-current` | `/etc/caddy/releases/REVISION/Caddyfile` | Root of each validated release |
| `caddy/conf.d/00-health.caddy` | `production-current` | Release `conf.d/00-health.caddy` | Loopback and shared-VIP health endpoints |
| `caddy/conf.d/10-pihole-admin.caddy` | `production-current` | Release `conf.d/10-pihole-admin.caddy` | Shared-owner and node-specific Pi-hole routes |
| `caddy/conf.d/90-default-deny.caddy` | `production-current` | Release `conf.d/90-default-deny.caddy` | Catch-all HTTP and HTTPS rejection |
| `caddy/conf.d/91-exact-listener-default-deny.caddy` | `production-current` | Release `conf.d/91-exact-listener-default-deny.caddy` | Exact-address HTTPS rejection |
| `lighttpd/desired-state.conf` | `production-current` | Staged lighttpd transformation input | Never include this record directly from lighttpd |
| `lsyncd/caddy-node-a.lua` | `production-current` | `/etc/lsyncd/caddy.lua` on Node A | Normal A-to-B protocol-v2 transport |
| `lsyncd/caddy-node-b.lua` | `production-current` | `/etc/lsyncd/caddy.lua` on Node B | Guarded emergency B-to-A transport |
| `munin/caddy-ha` | `deferred` | Future `/etc/munin/plugin-conf.d/caddy-ha` | Monitoring deployment is a separate post-deployment scope |
| `sysctl/70-caddy-ha.conf` | `production-current` | `/etc/sysctl.d/70-caddy-ha.conf` | Permits binding inactive floating addresses |
| `tmpfiles.d/caddy-ha.conf` | `production-current` | `/etc/tmpfiles.d/caddy-ha.conf` | Recreates service-owned runtime directories |
| `wsl/.wslconfig` | `workstation` | Windows `%UserProfile%\.wslconfig` | Retained at this path for immutable Actions 26c-26e; never install on an HA node |

## External ownership

Production Keepalived configuration is intentionally absent. The authoritative
Node A and Node B files are maintained in
`homelab-dns/Keepalived/configs/`. Pi-hole and Unbound configuration likewise
belongs to `homelab-dns`; network address allocation and firewall policy belong
to `homelab-network`.

Systemd units belong in `Caddy/systemd/`, rendered inputs in
`Caddy/templates/` and are governed by `Caddy/templates/README.md`, executable
programs in `Caddy/scripts/`, workstation tools in `Caddy/tools/`, and contracts
or accepted identities in `Caddy/manifests/`.

## Retired and relocated entries

- `ssh/authorized_keys.options` was retired because it selected the obsolete
  `caddy-sync-rsync-receiver`. Current authorization is rendered from
  `Caddy/templates/authorized-key-receiver-finalized-v2.in`.
- `unifi/firewall-state-summary.jq` moved to
  `Caddy/tools/unifi/firewall-state-summary.jq`; it summarizes audit output and
  is not node configuration.
- Empty `keepalived/.gitkeep` and `lsyncd/.gitkeep` placeholders were removed.
  Keepalived has an external source of truth, and lsyncd now contains tracked
  production files.
