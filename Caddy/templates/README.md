# Caddy Template Lifecycle

This directory preserves rendered inputs from both the accepted Caddy HA
architecture and earlier deployment designs. A file's presence here does not
make it deployable. The machine-readable source for these classifications is
`Caddy/manifests/template-lifecycle.tsv`.

## Lifecycle rules

- `production-current` templates may be consumed by current production
  tooling.
- `historical-obsolete` templates preserve a superseded architecture.
- `historical-superseded` templates preserve an earlier implementation whose
  accepted replacement is stored elsewhere.
- `historical-rejected` templates preserve a design that was evaluated and
  rejected.
- `deferred-example` templates are documentation examples, not node payloads.

Historical paths and bytes remain available for executed-action provenance and
regression reconstruction. Production inventory and installation tooling must
not consume them.

## Template catalog

| Repository path | Lifecycle | Current authority or disposition |
| --- | --- | --- |
| `authorized-key-receiver-finalized-v2.in` | `production-current` | Protocol-v2 forced-command authorization contract in `Caddy/manifests/synchronization-protocol-v2.yaml` |
| `caddy-ha.env-v2.in` | `production-current` | Minimal node environment rendered to `/etc/default/caddy-ha` |
| `caddy-ha.env.in` | `historical-superseded` | Ten-variable environment preserved for executed-action provenance |
| `keepalived-caddy-ha.conf.in` | `historical-obsolete` | Separate `CADDY_DUALSTACK` design; current authority is `homelab-dns/Keepalived/configs/` |
| `keepalived-caddy-ha-v2.conf.in` | `historical-obsolete` | Separate `CADDY_DUALSTACK` design; current authority is `homelab-dns/Keepalived/configs/` |
| `lsyncd-caddy.lua.in` | `historical-obsolete` | Original rsyncssh transport |
| `lsyncd-caddy-source-bound.lua.in` | `historical-obsolete` | Intermediate source-bound rsyncssh transport |
| `lsyncd-caddy-receiver-finalized-v2.lua.in` | `historical-superseded` | Replaced by `Caddy/configs/lsyncd/caddy-node-a.lua` and `caddy-node-b.lua` |
| `pihole-admin-backend.Caddyfile.in` | `historical-rejected` | Rejected dedicated mTLS backend from unexecuted Action 28k |
| `pihole-admin-dns-owner.caddy.in` | `historical-rejected` | Rejected dedicated mTLS frontend route from unexecuted Action 28k |
| `reverse-proxy.caddy.example` | `deferred-example` | Future application example; never installed automatically |

## Production boundaries

- Keepalived configuration is owned exclusively by
  `homelab-dns/Keepalived/configs/`. Caddy installation tooling must not render
  or install a Keepalived fragment.
- The canonical lsyncd configurations are
  `Caddy/configs/lsyncd/caddy-node-a.lua` and
  `Caddy/configs/lsyncd/caddy-node-b.lua`.
- `Caddy/scripts/render-node-config.sh` renders only the production environment
  by default. Its historical flag exists solely for offline reconstruction.
- `Caddy/scripts/install-caddy-ha.sh` rejects the externally owned Keepalived
  component and installs only the canonical node-specific lsyncd file.
