# Candidate smartd production transition plan

Status: waiting for a suitable Debian package, approved October 14, 2026.
Retain production unchanged and preserve existing monitoring and alerts.
Custom-package preparation is not selected. The separately authorized read-only
baseline and package-source review are complete; see the
[findings and package decision](PRODUCTION_BASELINE_REVIEW.md).
No deployment bundle is ready. This document does not authorize a package
transaction, restart or notification. This is the next-stage plan for the existing pilot
`j2-svpi4mf`, not a fleet rollout or a second observation definition.

## Evidence and intended scope

The [observation review](SMARTD_OBSERVATION_REVIEW.md) accepts bounded operation
of source `06489e03695e0cf0a7366f0d402fbff8763bf3e6` with explicit
`sntjmicron`, a private empty database and `-l selftest`. The October 14
revalidation confirmed the retained evidence. Ninety-six monitoring checks
completed without reproducing the original warning. This does not prove a fix.

That trial did not qualify Debian package installation, the production service
unit, full monitoring policy, production state migration, alert delivery or
candidate daemon autodetection. The existing
[explicit-device template](../configs/jmicron-nvme.smartd.conf.example) also
changes device discovery and monitoring policy; it is not the trial configuration
and must not be installed as an incidental part of a package upgrade.

The proposed pilot changes only the reviewed smartmontools package and the
service transition required by that package. Preserve verified production
device membership, monitoring options, recipient, mail hooks, state paths,
interval and Webmin behavior. Database files shipped by a package are part of
its reviewed payload; preserving configuration alone does not preserve
autodetection. Any required policy or database override is a separately reviewed
scope change, not an automatic fallback.

## Future baseline refresh and package review procedure

The initial baseline and package-source review completed October 14. The current
action is to wait and perform the October 28 package/upstream follow-up below.
Use this procedure when a suitable package or new evidence warrants resuming
deployment planning; it does not require another host inspection now.

For that future stage, prepare a bounded read-only inspection for separate authorization. Collect
package architecture/version/ownership, executable and database hashes,
configuration bytes and metadata, systemd unit/drop-ins and service identity,
device topology and stable selector mapping, USB descriptor and transport,
state-file locations, counters, journal availability and active observers.
Inspect the mail frontend/hook and routing references without collecting secrets
or sending a message. Keep serials, raw configurations and journals private.

Use operating-system metadata for identity first. Do not run `smartctl --scan`,
SMART reads, foreground smartd or service reloads under this baseline: they can
issue device commands. Inventory the effective production policy rather than
copying the historical DEVICESCAN line from the profile. Confirm consumer
workload constraints and the permitted monitoring interruption before planning
execution. Detect drift against historical evidence and assess it; do not force
the host back to the October 6 baseline.

Resolve available distribution packages and upstream source evidence at that
stage. The October 14 availability findings are recorded in the baseline review;
they are not a future deployment version pin.
Prefer an authenticated distribution package containing the reviewed transport
and parser behavior. Compare its source and defaults against the admitted
candidate; a newer version number alone is not equivalence evidence. A different
source revision requires assessment and relevant qualification before rollout.

Do not install the private CI executable over package-managed binaries. If no
suitable distribution package exists, stop at a packaging decision: either wait,
or propose a separately approved maintained package with pinned source, build
inputs, provenance, package lifecycle and update ownership. The selected decision
is to wait for a distribution package; custom packaging requires a new decision.

Stage selected package archives locally, verify origin/hashes, inspect file and
maintainer-script changes, and review the exact dependency transaction and
database matching behavior. Identify an obtainable rollback package before
deployment. Any target APT refresh/download/simulation must be explicitly
included in a later authorized preparation scope; this plan does not run it.

## Qualification before deployment approval

Exercise the selected package's configuration parser, service integration and
install/downgrade lifecycle in a disposable compatible environment. Separate
disk-free checks from device-facing tests. Capture package scripts' restart
behavior and state-format compatibility; never call a foreground daemon a
syntax-only test without proving it cannot access a device.

Determine which production behaviors remain untested: device selection using
the package's actual databases, full enabled monitoring, state loading and
mail-hook compatibility. Define an exact bounded qualification for those gaps.
Do not assume the private `-l selftest` trial covers them or start another daemon
alongside production without a new approved scope. Notification delivery requires
its own explicit send authorization and downstream receipt evidence under
[alert delivery](ALERT_DELIVERY.md).

Only after these inputs are resolved, freeze one operation bundle containing
the specification, reviewed package hashes, configuration/database decisions,
scripts, freshness limits, exact commands, acceptance criteria and recovery.
Require separate approval of that hash and the monitoring interruption before
any production transaction. Keep unrelated Webmin, transport, reboot, mail-route
and application changes outside this pilot.

## Proposed live acceptance and recovery

The future approved operation must preserve the old package, conffiles and
metadata, database identities, service unit/drop-ins, runtime state and package
inventory before mutation. Confirm no active observer or conflicting maintenance
operation. Bind a fresh baseline and stop on unreviewed drift.

After the package transaction, verify the exact package delta, executable and
database identities, expected service transition, device coverage, retained
policy and state handling. Capture candidate warnings, production journals,
storage counters and kernel events with explicit coverage receipts. Define
observation duration and checkpoints in the bundle; use a 48-hour/30-minute
window as the planning baseline, subject to verified production cadence and
consumer constraints. This is a proposal, not a launched or frozen observation.

Acceptance requires expected monitoring cycles, no unexplained warnings or
storage regression, unchanged unrelated production artifacts, documented alert
coverage and a reviewed terminal result. Retain the original trial's limits:
quiet operation means non-reproduction, not demonstrated elimination. Capture
per-audit counter/service snapshots and timestamped completion evidence in the
new operation if those stronger claims are required; the old trial cannot be
retroactively strengthened.

Rollback must name the exact old package and guarded configuration/state
restoration, expected service restart, monitored-device checks and evidence to
retain. Prove state compatibility before using old binaries with new state.
Do not purge or autoremove packages, blindly overwrite changed files, or replay
the transaction after a partial failure. Storage faults or an uncertain rollback
require stopping further device queries and escalation to the consumer's recovery
procedure. Host transport and boot recovery remain owned by `host-storage/`.

## Readiness checklist

- Current host baseline: reviewed October 14; permitted interruption unresolved.
- Package/source review: installed distribution archive verified; no suitable
  distribution upgrade identified in the reviewed suites. Package choice pending.
- Package lifecycle, production-policy and state compatibility: unqualified.
- Rollback artifact: exact installed archive verified locally; recovery checks pending.
- Alert route and any required send approval: not established by this trial.
- Execution bundle/hash and deployment authorization: absent.

The selected path is to wait for a suitable distribution package. Retain the
completed observation and its published results; no duplicate upstream report
is needed. The gates above apply if a suitable package becomes available.

## Follow-up action: package and upstream status

- [ ] Due October 28, 2026 (America/Chicago): review Debian package availability
  and upstream issue #648. This is an operator follow-up recorded in the repository,
  not an automated reminder or a target-side scheduled task.

Use the October 14 [baseline review](PRODUCTION_BASELINE_REVIEW.md) as the
comparison point. Check official trixie and trixie-backports ARM64 package/source
metadata, upstream releases and
[smartmontools issue #648](https://github.com/smartmontools/smartmontools/issues/648).
Verify source or backport evidence for the qualified 512-byte/18-record handling;
a newer version number, drive-database update or closed issue is insufficient.

Record the check date, exact versions, source evidence and decision here. If no
suitable package is available, retain production unchanged and set the next
review for two weeks later. If a suitable package exists, resume local package
and lifecycle review under this plan; deployment still requires a fresh authorized
host baseline and an approved execution bundle.

Check sooner if the existing monitoring reports renewed self-test-log warnings
or storage symptoms. Preserve that evidence and scope any host investigation
separately. This follow-up does not authorize SMART queries, a new trial, target
APT refresh, installation, restart, notification sending or upstream publication.
