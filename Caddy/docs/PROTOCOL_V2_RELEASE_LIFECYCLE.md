# Protocol-v2 Caddy release lifecycle

This document explains how the accepted Caddy/DNS platform constructs,
transfers, validates, activates, and records an immutable Caddy release. It
describes the current implementation. It does not authorize publication or
node contact.

[`caddy_plan-v1.1.md`](caddy_plan-v1.1.md) owns architecture and authorization
rules. [`OPERATIONS.md`](OPERATIONS.md) owns operator gates, maintenance, and
rollback. The protocol contract lives in
[`synchronization-protocol-v2.yaml`](../manifests/synchronization-protocol-v2.yaml).

## 1. Prepare the complete release input

A reviewed deployment operation assembles a protected temporary directory:

```text
PREPARED_RELEASE/
├── Caddyfile
├── conf.d/
│   ├── 00-health.caddy
│   ├── 10-pihole-admin.caddy
│   ├── 20-application.caddy
│   ├── 90-default-deny.caddy
│   └── 91-exact-listener-default-deny.caddy
├── tls/
│   ├── fullchain.pem
│   └── privkey.pem
└── trust/
    └── optional-backend-ca.pem
```

The operation combines reviewed repository configuration with protected TLS
material and any approved release-local backend CA. The directory must contain
the complete release, not a partial overlay. The current repository has no
generic command that assembles an arbitrary application release.

The operation validates the proposed application, repository and DNS changes,
source hashes, operation specification, phase order, rollback, and evidence
contract before requesting live authorization. The normal publisher runs on
Node A. Node B may publish only through the guarded emergency path.

## 2. Validate publisher input

The installed
[`publish-release-v2.sh`](../scripts/publish-release-v2.sh) requires:

- `Caddyfile`;
- `conf.d`;
- `tls/fullchain.pem`; and
- `tls/privkey.pem`.

The publisher rejects symbolic links, multiply linked files, nested protocol
markers, a pending completion marker, and missing required paths. It sets
`CADDY_CONFIG_ROOT` to the prepared directory and runs Caddy validation. It
also parses the certificate and private key before copying payload bytes.

Normal publication requires `--node-role node-a`. Node B requires
`--node-role node-b --emergency` and must own both VRRP families plus all four
DNS and Proxy VIPs.

## 3. Construct the revision

The publisher generates a revision from a UTC timestamp and UUID. It reads the
active release's `release-manifest.json` and records that revision as the new
parent.

The publisher creates a protected staging directory beneath:

```text
/var/lib/caddy-sync/outbound/.publish-v2.*
```

It copies the prepared release, then removes caller-supplied
`manifest.sha256`, `release-manifest.json`, `.finalize-request`, `.complete`,
and `.complete.pending`. The publisher owns every protocol control file.

## 4. Create metadata and expose outbound state

The publisher writes `release-manifest.json` with:

```json
{
  "revision": "generated-revision",
  "parent_revision": "current-active-revision",
  "source_node": "node-a",
  "created_at": "timestamp"
}
```

It constructs `manifest.sha256` from the canonical sorted payload file set,
including `release-manifest.json`. The hash manifest excludes itself and these
markers:

- `.finalize-request`;
- `.complete`; and
- `.complete.pending`.

The publisher creates an empty `.finalize-request`, assigns
`caddy-sync:caddy-sync`, changes directory modes to `0550`, and changes file
modes to `0440`. It then atomically renames staging to:

```text
/var/lib/caddy-sync/outbound/REVISION
```

The publisher does not create `.complete`. Atomic visibility prevents lsyncd
from observing a partially constructed outbound revision.

## 5. Transfer through managed lsyncd

Managed lsyncd watches `/var/lib/caddy-sync/outbound/`. It sends the candidate
through the restricted `caddy-sync` SSH identity and forced rsync receiver.
The configuration:

- excludes `.complete` and `.complete.pending`;
- prohibits remote deletion;
- preserves partial transfer state without presenting it as finalized; and
- scopes received data beneath `incoming/<source-role>`.

A Node A candidate arrives on Node B beneath:

```text
/var/lib/caddy-sync/incoming/node-a/REVISION
```

Standalone SSH copies and ad hoc finalizer calls do not satisfy the protocol.

## 6. Finalize on the receiver

The forced
[`caddy-sync-release-receiver-v2`](../scripts/caddy-sync-release-receiver-v2)
runs rsync inside the source-role boundary and invokes
[`finalize-incoming-release-v2.sh`](../scripts/finalize-incoming-release-v2.sh).

The finalizer verifies:

- source role, revision, parent shape, and release-manifest schema;
- regular files and directories with no symbolic, hard, or special files;
- an exact payload file set matching `manifest.sha256`;
- safe manifest paths and every payload hash;
- certificate and private-key parsing plus public-key equality; and
- Caddy validation with the receiving node's protected environment.

The finalizer creates `.complete.pending`, changes it atomically to `.complete`,
locks the candidate to `0550` directories and `0440` files, and touches the
protected reconciliation trigger. It repeats validation for an idempotent
replay before accepting an existing completion marker.

## 7. Reconcile and activate

[`reconcile-release-v2.sh`](../scripts/reconcile-release-v2.sh) processes
finalized incoming candidates. It requires empty, regular
`.finalize-request` and `.complete` markers and rejects `.complete.pending`.

The reconciler selects candidates in this order:

1. an exact replay of the active revision; or
2. exactly one child of the active revision.

It fails closed on ambiguous children. It removes an exact replay and
quarantines a divergent parent unless an existing exact quarantine payload
proves a replay.

For one valid child, the reconciler repeats file-set, hash, marker, and Caddy
validation. It copies the candidate into a protected staging directory beneath
`/etc/caddy/releases`, assigns `root:caddy-tls`, locks modes, and atomically
renames the staged directory to the revision path.

The reconciler atomically replaces `/etc/caddy/current`, then reloads
`caddy.service`. A reload failure restores the previous selection and reloads
the previous release. Failure to prove restoration returns status `125`.
After successful activation, the reconciler removes the accepted incoming
candidate and drains the remaining queue.

## 8. Accept the live release

The authorized deployment transaction verifies the active revision and
payload identity, services, Caddy and DNS health, dual-stack endpoints, settled
VIP ownership, synchronization state, journals, and protocol residue. Node B
must pass its standby-first acceptance before the operation changes Node A.

Application acceptance must prove the new hostname with `curl --resolve`
before relying on DNS. DNS acceptance then proves the exact A and AAAA answers
for the application, the canonical `proxy.local.theama.co.` PTR for each Proxy
VIP, and the canonical name's matching A and AAAA answers. Prove these from
both nodes and through the shared DNS VIPs. See
[`APPLICATION_ONBOARDING.md`](APPLICATION_ONBOARDING.md).

Rollback restores mutations in reverse order and repeats service, endpoint,
ownership, DNS, and residue checks. The operation preserves the previous
immutable release and bounded evidence.

## 9. Reconcile repository records

`Caddy/manifests/caddy-release-source.tsv` does not create a release. After
live acceptance, it records each accepted repository source, release path,
source SHA-256, and accepted payload-manifest SHA-256.

The terminal bookkeeping change also reconciles:

- `config-lifecycle.tsv` for the accepted configuration tree;
- `accepted-live-artifacts.tsv` and `production-artifacts.tsv` for installed
  identities;
- `current-live-state.tsv` for the accepted semantic state; and
- DNS and reproducibility manifests affected by the application.

A prepared directory, outbound revision, or successful Caddy reload does not
authorize those records to claim acceptance. The transaction must complete all
live checks first.

## Privileged drift boundary

Release modes prevent ordinary service identities from modifying the active
tree. Root can bypass those modes. A direct change beneath `/etc/caddy/current`
does not update `manifest.sha256`, the repository, or accepted-live records and
may alter routing after a reload.

No daemon continuously compares the active release with its manifest. A
bounded audit must compare the exact active file set and every payload hash
with `manifest.sha256`, then compare the manifest identity with accepted-live
records. Operators must treat any mismatch as production drift and must not
normalize it through an in-place edit.
