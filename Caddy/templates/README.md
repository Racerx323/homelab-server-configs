# Caddy templates

Production templates:

- `authorized-key-receiver-finalized-v2.in` renders the forced SSH receiver
  command.
- `caddy-ha.env-v2.in` renders the three-value node environment.

`reverse-proxy.caddy.example` is an approved future task input. No production
inventory or installer may consume it. A later documentation task will turn it
into a supported application template.

Keepalived templates and generic lsyncd templates are absent. Their current
sources live in `homelab-dns` and `Caddy/configs/lsyncd`.
