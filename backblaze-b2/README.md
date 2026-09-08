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

The dedicated private bucket has the reviewed encryption, Object Lock, and
lifecycle settings. The canonical replacement credential passed exact-scope
authentication and the isolated S3 put, readback, delete, and final-absence
transaction. The B2 transport and credential are accepted for the separately
governed Restic repository work. This does not initialize or accept a Restic
repository, backup, or restore.

Terminal results are indexed in [HISTORY.md](HISTORY.md) and preserved by the
annotated tags listed there. The B2 operation stream is clean. Restic
initialization and the consumer-owned isolated backup/restore verification
remain separate operations.

## Layout

- `AGENTS.md`: component editing and live-operation rules;
- `HISTORY.md`: concise terminal-operation index;
- `docs/B2_ARCHITECTURE.md`: governing architecture;
- `docs/CAPABILITY_REMEDIATION_DECISION.md`: reviewed least-privilege key
  replacement decision;
- `docs/CAPABILITY_REMEDIATION_PREFLIGHT.md`: unready read-only API and
  authentication preflight;
- `docs/MANAGEMENT_CREDENTIAL_DECISION.md`: gate for reusing or separately
  creating a management credential;
- `docs/MASTER_KEY_ROTATION.md`: inactive reusable master-rotation, protected
  storage, acceptance, and recovery contract;
- `docs/MASTER_KEY_ROTATION_PREFLIGHT.md`: archived metadata-only console and
  Doppler preflight contract for master rotation;
- `docs/B2_CONFIGURATION.md`: operator decisions and console procedure;
- `docs/READ_ONLY_PREFLIGHT.md`: metadata-only provider and Doppler preflight;
- `docs/S3_COMPATIBILITY_PROBE.md`: reusable isolated S3 object-transaction
  contract for the canonical consumer credential;
- `manifests/desired-state.yaml`: reviewed Phase 1 identifiers and policy;
- `manifests/operation.yaml`: the single B2 operation-state manifest;
- `scripts/capability_remediation_preflight.py`: bounded read-only B2 API and
  Doppler metadata client;
- `scripts/protected_doppler_master_write.py`: FIFO- and stdin-based one-time
  master-credential writer with name-only acceptance;
- `scripts/protected_doppler_candidate_write.py`: FIFO- and stdin-based
  candidate-credential writer that cannot modify canonical names;
- `scripts/replacement_key_creation.py`: exact single-request B2 replacement
  key client with sanitized forward and readback evidence;
- `scripts/s3_compatibility_probe.py`: fail-closed SigV4 client for the exact
  owned-object compatibility transaction; direct execution remains disabled;
- `scripts/run_s3_compatibility_probe.py`: inactive hash-bound launcher owning
  the read-only preflight, live gate, evidence, and terminal classification;
- `scripts/run-replacement-key-creation.sh`: unready hash-bound replacement-key
  launcher and terminal-classification owner;
- `scripts/run-master-key-rotation.sh`: inactive hash-bound outer launcher for
  a separately defined console and Doppler operation;
- `scripts/run-capability-remediation-preflight.sh`: readiness- and hash-gated
  protected credential launcher;
- `schemas/desired-state.schema.json`: desired-state validation; and
- `schemas/operation.schema.json`: operation-state validation;
- `schemas/replacement-key-creation.schema.json`: exact reviewed replacement-key
  operation validation;
- `tests/capability-remediation-preflight-regression.py`: offline transport,
  endpoint, classification, and evidence regressions.
- `tests/protected-doppler-master-write-regression.py`: offline secret
  transport, partial-write, name-only readback, and evidence regressions.
- `tests/master-key-rotation-launcher-regression.py`: offline bundle, readiness,
  mutation-order, cleanup, and terminal-evidence regressions.
- `tests/replacement-key-creation-regression.py`: offline provider request,
  candidate transport, no-retry, unready gate, and evidence regressions.
- `tests/s3-compatibility-probe-regression.py`: offline signing, exact
  transaction, failure cleanup, secret transport, and evidence regressions.
- `tests/s3-compatibility-launcher-regression.py`: offline readiness, bundle,
  preflight, terminal-classification, and protected-evidence regressions.

Add scripts or consumer-specific paths after they contain reviewed
configuration or executable behavior.
