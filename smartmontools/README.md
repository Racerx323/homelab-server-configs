# smartmontools

This directory owns reusable smartctl and smartd configuration, policy,
validation, scripts, templates, schemas, and sanitized metadata for
`homelab-server-configs`.

Read
[docs/SMARTMONTOOLS_ARCHITECTURE.md](docs/SMARTMONTOOLS_ARCHITECTURE.md) before
adding a device policy or monitoring operation. Read [AGENTS.md](AGENTS.md)
before changing files in this directory.

## Ownership

smartmontools owns shared discovery, health-collection, self-test, smartd, and
exit-status rules. Each consumer owns its device list, workload constraints,
alert policy, operation state, acceptance decision, and history.

The approved mail system owns relay configuration and credentials. Git stores
reviewed non-secret definitions and sanitized evidence manifests. Raw SMART
reports and device identifiers remain outside Git.

## Layout

The component contains:

- `AGENTS.md`: scoped editing and execution rules;
- `docs/SMARTMONTOOLS_ARCHITECTURE.md`: shared architecture authority; and
- `.gitignore`: runtime report, evidence, and local-state exclusions;
- `configs/`: reviewed APT source and explicit-device monitoring template; and
- `docs/JMICRON_NVME_PROFILE.md`: qualification, configuration, and rollout procedure.

Add `configs/`, `scripts/`, `schemas/`, `manifests/`, or consumer-specific
paths only when reviewed content exists.

## Current state

Nautobot's storage diagnostic already uses smartctl for read-only health
collection on `j2-svpi4mf`. That operation remains Nautobot-owned. Future
shared collection and smartd configuration will use this component's rules.

The [JMicron NVMe profile](docs/JMICRON_NVME_PROFILE.md) documents the bridge
workaround, retained pilot configuration, and upgrade/validation procedure.
It includes an [explicit-device template](configs/jmicron-nvme.smartd.conf.example)
and [Debian 13 backports source](configs/trixie-backports.sources).
Render and qualify them for each host; they are not a fleet deployment manifest.
No self-test schedule is configured by this profile.

The [alert delivery procedure](docs/ALERT_DELIVERY.md) records the tested package
additions and versions, Debian's mail frontend requirement, recipient/account
qualification, rollback and end-to-end verification. Fleet msmtp configuration
is owned by `homelab-dns/msmtp`; the pilot's older mail configuration is not the
fleet standard.

For an isolated upstream-build investigation, see the
[standalone CI comparison](docs/CI_COMPARISON.md). This does not replace the
packaged monitoring configuration or authorize fleet changes.
