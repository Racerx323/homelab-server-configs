# Caddy production configuration

This directory contains node-deployable desired state.

| Path | Purpose |
| --- | --- |
| `caddy/` | Current immutable-release Caddy configuration |
| `lighttpd/desired-state.conf` | Input to the bounded Pi-hole v5 lighttpd transformer |
| `lsyncd/caddy-node-a.lua` | Normal A to B protocol-v2 publisher |
| `lsyncd/caddy-node-b.lua` | Guarded emergency B to A publisher |
| `sysctl/70-caddy-ha.conf` | Nonlocal VIP binding settings |
| `tmpfiles.d/caddy-ha.conf` | Runtime and durable notification directories |

Keepalived, Pi-hole, and Unbound configuration belongs to
`homelab-dns`. Network-controller configuration belongs to
`homelab-network`. The production installer must not consume configuration
from any other Caddy subdirectory.
