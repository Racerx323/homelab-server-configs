# Action 35 closure: coupled DNS and Caddy serving health

## Status

Action 35 is closed and accepted through Action 35as. The Caddy deployment
stream is `clean`; `deployable-successor.tsv` contains no successor and
`deployable-successor-coverage.tsv` contains its header only.

The accepted terminal checkpoint is preserved by annotated tag
`caddy-action35as-terminal-2026-08-24`. `Caddy/HISTORY.md` indexes the earlier
terminal tags. Do not restore or rerun a consumed Action 35 operation.

## Accepted result

Node A (`j1-svpihole0`) is the preferred dual-stack owner. Node B
(`j1-svpihole00`) is the standby. Keepalived moves four shared addresses as one
sync group:

- DNS: `10.1.0.55` and `fd36:5aa8:6971:1::55`
- Caddy: `10.1.0.56` and `fd36:5aa8:6971:1::56`

Both nodes run the same accepted Caddy release. The accepted payload manifest
SHA-256 is
`2253a491e048c9d670865e3d39efa3c9e9acd92a31ec33219f97ba91428b0133`.
`caddy-release-source.tsv` pins the non-secret repository sources associated
with that immutable release.

Keepalived uses two minimal tracking scripts:

- `check-dns.sh` verifies Pi-hole FTL and Unbound over IPv4 and IPv6.
- `check-caddy.sh` verifies trusted HTTPS serving over IPv4 and IPv6.

Keepalived owns scheduling, timeout, signal handling, and exit-status
interpretation. The probes return zero only after all required checks pass.
Diagnostic publication cannot change the health decision.

Pi-hole/lighttpd web-backend health runs from
`caddy-pihole-web-health.timer`. Its failures create Proxy notifications but do
not change VRRP eligibility.

## Serving boundaries

- Pi-hole FTL serves DNS on port 53.
- Unbound serves the node-local recursive path and the internal authoritative
  zone.
- lighttpd serves each node's Pi-hole web backend.
- Caddy terminates trusted TLS, serves `/healthz`, and proxies the shared and
  node-specific Pi-hole interfaces.
- Keepalived owns the DNS and Caddy VIPs as one dual-stack group.

Caddy active and passive backend checks protect the Pi-hole web proxy. They do
not replace the Keepalived Caddy probe, which tests the node's public serving
boundary.

## Release and synchronization contract

Node A publishes normal protocol-v2 releases. The publisher creates one
immutable revision, records its target, and exposes it to the managed lsyncd
transport. The receiver, finalizer, and reconciler validate the complete
manifest and reject partial, unsafe, ambiguous, or unauthorized candidates.

Node B may publish with `--emergency` only while it owns both address families
and all four shared VIPs. The same-parent conflict rule fails closed.

The accepted protocol namespaces are empty. A namespace may be absent or may
exist as an empty protected directory when its contract permits both forms.
Policies reject non-empty, symlinked, malformed, incorrectly owned, and
incorrectly mode-set adjacent states.

## Durable notifications

All producers atomically enqueue bounded records to the persistent local
queue. The worker retries delivery without affecting DNS, Caddy, Keepalived,
or synchronization decisions. Delivery is at least once. See
`APPRISE_DELIVERY.md` for the queue schema, retry rules, security boundary, and
operator commands.

Notification standardization is complete. Current producers use the shared
multiline format, actual prior-state tracking, planned-maintenance context, and
the Apprise severity icons. Legacy `[Failover Alert] Pi-hole DNS Cluster`
formatting exists only in tagged Git history.

## Accepted failure exercise

The controlled exercise proved these behaviors before Action 35 closed:

- Caddy, Pi-hole FTL, Unbound, and Keepalived failures on the owner caused
  coupled failover with bounded dual-stack continuity evidence.
- lighttpd failure produced one failure and one recovery notification without
  VIP movement.
- Equivalent standby-node failures did not take ownership from a healthy
  preferred node.
- Every scenario restored services, release state, ownership, queues, and
  temporary paths. Action 35as recorded final acceptance.

## Invariants

1. Never restart or reload both HA nodes together.
2. Mutate Node B and accept it before changing Node A.
3. Require stable, repeated ownership samples after a Keepalived transition.
4. Keep DNS and trusted HTTPS evidence separate for IPv4 and IPv6.
5. Roll back Node A and then Node B in reverse mutation order.
6. Return status 125 only after mutation when exact recovery cannot be proven.
7. Keep notification delivery outside serving-health decisions.
8. Preserve executed definitions with annotated tags, then remove their
   operation data from the current branch.

## Current repository contract

The current branch retains one neutral transaction and one neutral outer
runner. `serving-health-operation.yaml` is inactive and hash-pinned to both
entrypoints. A future deployment may change it to `defined-unexecuted` only
after production-path coverage passes.

Current manifests contain accepted production state. They do not carry failed
action baselines, candidate terminology, or historical quarantine trees.

Run clean-state validation with:

```bash
Caddy/tests/run-focused.sh --profile current-repository-policies --phase host --container never
Caddy/tests/run-focused.sh --profile current-serving-health --phase host --container never
Caddy/tests/deployable-successor-policy.sh --check
```

`--authorization-ready` must fail while the stream is clean.

## Next work

Action 35 has no deployment successor. Operator documentation may be improved
from current manifests and neutral implementations without contacting either
node. A future generic durable Apprise package belongs in the separate
`homelab-notification` repository and requires its own plan.
