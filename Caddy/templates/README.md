# Caddy templates

Production templates:

- `authorized-key-receiver-finalized-v2.in` renders the forced SSH receiver
  command.
- `caddy-ha.env-v2.in` renders the three-value node environment.

The authorized-key template does not provision SSH identity or trust. Private
keys, peer public keys, and `known_hosts` data are external inputs; see
`Caddy/docs/REPRODUCIBILITY.md`.

`reverse-proxy.caddy.example` is a supported, non-deployable documentation
input. [`APPLICATION_ONBOARDING.md`](../docs/APPLICATION_ONBOARDING.md) defines
its tokens, review boundary, validation, publication, and rollback. No
production inventory, installer, or renderer may consume it.

Keepalived templates and generic lsyncd templates are absent. Their current
sources live in `homelab-dns` and `Caddy/configs/lsyncd`.
