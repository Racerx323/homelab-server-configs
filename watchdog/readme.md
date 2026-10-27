# Watchdog fleet management

`watchdog/` owns the fleet watchdog configuration lifecycle in
`homelab-server-configs`: discovery, per-host policy, reviewed adoption,
configuration changes, recovery qualification and ongoing drift review.
This README is the governing component scope and safety contract. Record dated
observations and operation outcomes in [HISTORY.md](HISTORY.md).

**Status:** fleet policy and pilot contracts are defined. A read-only inspection
controller and guarded one-use pilot panic/recovery runner are implemented.
Fleet deployment automation and live recovery acceptance remain pending.
`configs/` and `templates/` remain scaffolding; no fleet installation command exists.
See the [controlled-panic contract](docs/CONTROLLED-PANIC-REVIEW.md) and
[history](HISTORY.md) for qualification and exact execution-review status.

## Ownership and inventory

Use the [server inventory](../inventory/README.md) for host membership and
host-specific differences. The existing `common_configuration.watchdog: true`
in [production defaults](../inventory/prod/groups/all.yaml) expresses desired
coverage. It does not prove deployment, select a backend, set a timeout or
approve a reset test. Do not turn this flag into an unconditional daemon install.

Fleet management must account for an existing systemd manager owner as well as
any separately installed watchdog daemon. Adopt or change each host only after
observing its device, driver, descriptor holder, effective settings and recovery
constraints. Do not install a second owner or overwrite working policy merely
because a service named `watchdog` is absent.

Keep these responsibilities separate:

- This component owns reusable watchdog configuration and its lifecycle.
- Inventory owns membership and host overrides; it must not contain raw evidence
  or secrets.
- Service repositories own service-specific readiness and acceptance. For the
  NTP pilot, [Phase 3 readiness](../../homelab-ntp/ntpsec/docs/PRODUCTION-READINESS.md)
  retains the recovery gate and shared-antenna constraints.
- Network, cluster and notification owners retain their existing authority.
  Watchdog automation must not change those systems implicitly.

A host may already have an active watchdog without being repository-managed.
Observed ownership, reviewed desired state, configuration adoption and proven
recovery are separate statuses.

## Required per-host record

Before implementation, define and validate a host policy containing:

| Field | Required distinction |
| --- | --- |
| Host and evidence | Inventory key, inspection date, accepted evidence hashes and scope |
| Device and driver | Observed identity; never assume every host has `/dev/watchdog0` |
| Existing owner | Descriptor holder, executable/service or manager identity, scan gaps |
| Effective policy | Runtime/reboot/kexec timeout and pretimeout behavior where supported |
| Configuration source | Vendor defaults, local overrides, precedence and unresolved inputs |
| Proposed management | Adopt observed policy, reviewed override or explicit exception; backend chosen per host |
| Recovery access | Independent console/media path, operator and maintenance boundary |
| Service dependencies | Peer availability, cluster/failover effects and shared power constraints |
| Acceptance | Required observation, controlled recovery test, boot-loop response and evidence |
| Restoration | Exact prior files/metadata, activation requirements and safe recovery sequence |

Do not populate missing values from another host. A vendor drop-in is an observed
input, not automatically an owned repository artifact. Keep reusable examples
separate from exact accepted configuration mirrors. Do not reconstruct a full
production file from an inspection that exported only selected assignments.

## Lifecycle and approval boundaries

1. **Inspect:** obtain a scoped, hash-bound non-mutating capture. Prefer effective
   settings and descriptor metadata; never open a watchdog device to identify it.
   Retain permission, process-race and namespace limitations.
2. **Define:** reconcile observed ownership with intended fleet policy. Qualify
   the installed platform's configuration/activation/restoration behavior before
   preparing deployment. Preserve vendor files; review any local override.
3. **Adopt or change one host:** bind exact inputs, preflight, mutation boundary,
   acceptance and restoration to separate execution approval. Prefer declarative,
   idempotent automation when implemented. Stop on conflicting ownership or
   unexplained drift. Repository-only adoption does not prove recovery.
4. **Qualify recovery:** prepare a separate controlled test only after independent
   recovery, peer service and shared power continuity are established. Define
   trigger, expected reset/recovery interval, stop conditions, interruption and
   boot-loop/manual-recovery handling. Preserve normal production service outside
   the approved maintenance boundary.
5. **Review fleet state:** record accepted configuration and ongoing observation
   responsibilities. Expand only to explicitly selected hosts; no inventory
   event, schedule or Boolean may trigger a reset or unreviewed deployment.

A live stage may combine steps only when its exact approved review explicitly
covers them. Passive inspection does not authorize feeding, device ioctl, service
or manager changes, reboot, failure injection or notifications. Routine resets
are not a substitute for monitoring or service-specific health acceptance.

## Repository layout

| Path | Purpose |
| --- | --- |
| `readme.md` | Governing scope, ownership and lifecycle contract |
| `HISTORY.md` | Dated observations, outcomes and next checkpoint |
| `docs/` | Proposed fleet policy/adoption and pilot recovery contracts |
| `configs/` | Reserved for reviewed configuration and accepted mirrors |
| `templates/` | Reserved for clearly identified reusable examples |
| `scripts/` | Read-only recovery-readiness inspection; deployment automation pending |

Retain raw evidence privately. Commit only sanitized history and evidence
references/hashes. Keep terminal operation definitions immutable and follow the
repository's archival policy before removing consumed operation data. No prior
operation is a reusable authorization.

## Policy and recovery design

The [fleet policy/adoption design](docs/FLEET-POLICY.md) proposes systemd hardware
watchdog ownership on qualified hosts, 60/120-second runtime/reboot settings for
qualification, and explicit function-based host exceptions. It explains why the
historical daemon install, load-reset thresholds, 15-second timeout and manual
sendmail symlink are not fleet defaults. No policy values have been deployed.

The [NTP pilot recovery contract](docs/PILOT-RECOVERY-CONTRACT.md) separates policy
adoption, independent recovery and real hardware-expiry acceptance. It remains
non-executable until native trigger/attribution facts, console/media recovery,
maintenance timing and exact acceptance limits are established.

The [readiness capture outcome](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-recovery-readiness-20261026-v1/outcome.md) accepts the completed passive snapshot.
It confirms the vendor-owned systemd policy, but selected journal storage is
volatile and no pstore records were present. Reset attribution and recovery remain
unproved. The [independent evidence/recovery record](docs/PILOT-EVIDENCE-AND-RECOVERY.md)
defines attended KVM notes plus off-node controller evidence, with optional video.
Aaron confirms local attendance and a separately powered laptop/KVM. Normal-operation
NTP outages must not exceed five minutes; longer deployment-test outages are allowed.
The [native attribution analysis](docs/PILOT-RESET-ATTRIBUTION.md) identifies remaining
source/runtime gaps before trigger selection and final timing.
The capture receipt is consumed; no retry, persistence change or trigger is approved.
The [native-input outcome](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-native-inputs-20261026-v1/outcome.md) accepts the completed passive capture; its
receipt is consumed. The [exact-package assessment](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-package-assessment-20261026-v1/assessment.md) now resolves published
source/config mapping and kexec build exclusion. Ordinary KVM visibility is operator-confirmed. The [debugger outcome](/home/aaron/code/.local-evidence/homelab-server-configs/current/watchdog-debugger-inputs-20261026-v1/outcome.md)
resolves configured normal/early transport for the accepted snapshot. Next prepare
one controlled panic watchdog-expiry execution/recovery review; no failure trigger
is authorized or executed.

Offline qualification from this repository: `python3 -I -B watchdog/tests/test_recovery_readiness.py`.
Preparation/checking requires the sibling `homelab-ntp` checkout because the controller
reuses its repository-owned bounded transport, passive and ownership collectors.
The sealed archive includes and verifies every source input; target execution
imports no historical archive code and needs no repository checkout. No dependency
source was changed. Future fleet deployment automation remains pending.

The pilot observation and its limits are recorded in [HISTORY.md](HISTORY.md).
No fleet deployment, timeout change or recovery test is authorized by this README.
