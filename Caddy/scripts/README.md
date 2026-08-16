# Caddy script lifecycle

`Caddy/scripts/` contains a small production surface and a large immutable
deployment journal. A filename that sounds generic is not evidence that it is
current. The canonical machine-readable disposition is
[`../manifests/script-lifecycle.tsv`](../manifests/script-lifecycle.tsv).

## Lifecycle values

| Lifecycle | Meaning |
| --- | --- |
| `production-current` | Current runtime source or reusable repository tool |
| `historical-action` | Action-scoped artifact retained for authorization and execution provenance |
| `historical-superseded` | Older generic implementation retained for reconstruction only |
| `workstation-only` | Workstation or WSL artifact; never install on an HA node |
| `rejected` | Explicitly rejected implementation |
| `deferred` | Retained work outside the production deployment boundary |

Only a `production-current` row with `node-installable=yes` may enter the node
installer. The registry gives its exact repository source, installed path, and
mode. Production-current repository tools use `node-installable=no`.

The accepted protocol-v2 implementations deliberately differ from several
older generic filenames. In particular, the current receiver, serving-health helper,
publisher, reconciler, and finalizer must be selected from the registry rather
than inferred from a basename.

The current VRRP-facing Caddy probe is
`check-caddy-serving-health.sh`. The Action 20-named helper is historical and
non-installable. Pi-hole/lighttpd application health is monitored separately by
`check-pihole-web-health.sh`; that monitor can enqueue durable notifications but
cannot influence VRRP ownership.

Executed action artifacts remain byte-for-byte historical evidence. Lifecycle
corrections belong in the registry and must not rewrite those files.

Run the focused lifecycle checks from the repository root:

```bash
Caddy/tests/deployment-lifecycle-policy.sh --check
Caddy/tests/deployment-lifecycle-regression.sh
```

The current notification programs are `caddy-apprise-enqueue.sh` and
`caddy-apprise-delivery-worker.sh`. Producers use only the enqueue helper; the
worker exclusively owns the IP-based HTTP transport, retry schedule,
deduplication receipts, and dead-letter disposition. See
[`../docs/APPRISE_DELIVERY.md`](../docs/APPRISE_DELIVERY.md).
