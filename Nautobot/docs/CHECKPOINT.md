# Nautobot checkpoint

Recorded September 23, 2026, after the running-baseline review. This is a resume
point; the [master plan](NAUTOBOT_DEPLOYMENT_PLAN.md) governs architecture and
[roadmap](ROADMAP.md) owns current progress.

## Accepted and preserved

- Stage 3 host baseline and stage 4 dual-stack identity are accepted.
- Stage 5 application startup passed all seven acceptance groups. PostgreSQL,
  Redis, web, worker and scheduler remained running at the final review;
  migration completed. Startup is not full platform acceptance.
- Published tag `nautobot-application-startup-v6-accepted` preserves all 48
  consumed inputs and sanitized results at commit
  `6e3069f5466c75d6d8aaab4a4b82181fa8447413`. Its two CI workflows passed.
- Accepted startup identity and history are reconciled. The operation slot is
  clean. Removed consumed files remain intact in the published archive.
- The September 23 04:42–04:44 UTC read-only baseline passed 19 comparisons:
  matching artifacts/configuration/images, unchanged service invocations, zero
  restarts, fresh heartbeats, effective guard, private data-service ports, healthy
  limits and no storage/OOM events since the retained startup cursor.

Private baseline evidence and collection scripts are retained at
`/home/aaron/code/.local-evidence/nautobot-running-baseline-20260923/`.
The FQDN resolved correctly but lacked a known SSH host-key entry. Collection used
the established IP identity with strict checking; no trust configuration changed.

## Resume here

Read applicable `AGENTS.md`, this checkpoint, the roadmap,
[workload and persistence preparation](WORKLOAD_PERSISTENCE_PREPARATION.md), and
`manifests/workload-test.yaml`. Review repository status before editing.

Next implementation: the fixture import/export/audit adapters and bounded
resource sampler, plus the separate persistence operation. Keep the existing
workload contract: real application-backup overlap is required for full workload
acceptance. Review pinned application APIs before implementing adapters. Freeze
and validate concrete execution bundles before requesting live authorization.

Remaining gates are representative workload headroom, logout/reboot persistence,
application-aware backup and isolated full restore, stage 6 Caddy onboarding, and
seven stable pilot days before authority migration or Semaphore. Prior canary
restore does not establish application recovery. Idle memory/temperature samples
do not establish workload capacity or seven-day stability.

Cold recovery copies predate application writes; this baseline checked directory
metadata and retained historical verification, not fresh contents or restore.
Refresh drift and recovery evidence before mutations. Do not rerun initialization,
administrator bootstrap or startup merely to resume work. No new live workload,
logout, reboot, backup, restore or Caddy publication is authorized by this checkpoint.
