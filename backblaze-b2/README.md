# Backblaze B2

This directory governs Backblaze B2 account integration, buckets,
application-key policy, cloud lifecycle settings, and sanitized identities for
`homelab-server-configs`.

Read [docs/B2_ARCHITECTURE.md](docs/B2_ARCHITECTURE.md) before defining a
bucket or key. Use [docs/B2_CONFIGURATION.md](docs/B2_CONFIGURATION.md) for the
first configuration walkthrough. Use
[docs/READ_ONLY_PREFLIGHT.md](docs/READ_ONLY_PREFLIGHT.md) before requesting
bootstrap authorization. Read [AGENTS.md](AGENTS.md) before changing this
component.

## Ownership

The B2 component owns bucket identity and settings, endpoint records,
application-key policy, provider lifecycle, and cloud-side acceptance. Backup
tools own repository format and backup execution. Each consumer owns its data,
schedule, retention intent, and restore acceptance.

The approved secrets system owns the application key ID and application key.
Git may store the bucket name, bucket ID, endpoint, region, prefix policy,
capability names, and secret references after an operator verifies them.

## Current state

The dedicated private bucket exists, is empty, and has the reviewed encryption,
Object Lock, and lifecycle settings. The first application key and its Doppler
credentials remain as rejected residue because the provider's console preset
exceeded the reviewed capability scope. The B2 configuration is not accepted
for Restic use.

The terminal result is indexed in [HISTORY.md](HISTORY.md). The unready
[capability-remediation decision](docs/CAPABILITY_REMEDIATION_DECISION.md)
defines the review required before a replacement-key operation. Restic
repository initialization remains separately blocked.

## Layout

- `AGENTS.md`: component editing and live-operation rules;
- `HISTORY.md`: concise terminal-operation index;
- `docs/B2_ARCHITECTURE.md`: governing architecture;
- `docs/CAPABILITY_REMEDIATION_DECISION.md`: unready least-privilege key
  replacement decision;
- `docs/B2_CONFIGURATION.md`: operator decisions and console procedure;
- `docs/READ_ONLY_PREFLIGHT.md`: metadata-only provider and Doppler preflight;
- `manifests/desired-state.yaml`: reviewed Phase 1 identifiers and policy;
- `manifests/operation.yaml`: the single B2 operation-state manifest;
- `schemas/desired-state.schema.json`: desired-state validation; and
- `schemas/operation.schema.json`: operation-state validation.

Add scripts or consumer-specific paths after they contain reviewed
configuration or executable behavior.
