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

The current files establish policy before implementation:

- `AGENTS.md`: scoped editing and execution rules;
- `docs/SMARTMONTOOLS_ARCHITECTURE.md`: shared architecture authority; and
- `.gitignore`: runtime report, evidence, and local-state exclusions.

Add `configs/`, `scripts/`, `schemas/`, `manifests/`, or consumer-specific
paths only when reviewed content exists.

## Current state

Nautobot's storage diagnostic already uses smartctl for read-only health
collection on `j2-svpi4mf`. That operation remains Nautobot-owned. Future
shared collection and smartd configuration will use this component's rules.

No live smartd configuration or self-test operation exists in this directory.
