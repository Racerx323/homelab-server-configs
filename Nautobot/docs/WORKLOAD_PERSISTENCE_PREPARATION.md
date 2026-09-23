# Workload and persistence preparation

Scope: remaining stage-5 checks after accepted application startup. This is a
preparation document, not a live operation or authorization. The startup archive
must be published and accepted identity reconciled before opening a successor.
The [master plan](NAUTOBOT_DEPLOYMENT_PLAN.md) governs acceptance;
[workload-test.yaml](../manifests/workload-test.yaml) owns workload parameters.

## Immediate next operation

Prepare a bounded read-only running-baseline collection: unit states, restart
counts, boot identity, installed artifact/image identities, effective resource
limits, worker/scheduler heartbeat freshness, failed system/user units, free disk
and memory, storage journal since startup, and backup/recovery-copy identities.
Compare with archived startup evidence; missing data or unexplained drift blocks
mutation readiness. Do not rerun initialization or administrator bootstrap.
Live collection requires approval; no host was contacted for this preparation.

## Workload implementation and acceptance

Implement the pinned-version import/export/audit adapters and sampler against the
existing fixture contract. Review required model references, namespace ownership
and collision handling before creating records. Offline tests must cover
idempotent second import, unowned-object refusal, deterministic exports, sampling
gaps, stop thresholds and failure cleanup. Review fixture size against intended
production scale; synthetic success alone cannot establish representativeness.

Retain the existing contract: 10 locations, 500 devices, four interfaces per
device and 500 IP assignments; two imports, three matching normalized exports
and ten read-only audits at concurrency two. No fixture addresses become network
configuration, DNS records or external probe targets.

Collect every five seconds; maximum gap 15 seconds. Minimum phases are 15 minutes
idle, 15 minutes import/export, 30 minutes Jobs with real application backup,
15 minutes recovery and 75 seconds delayed-error observation. Individual Jobs
are bounded at 15 minutes and the whole test at three hours. Stop load on missing
coverage, unexpected boot/service failure, Job failure, new storage/ext4 errors,
OOM, throttling, available memory below 1.5 GiB or temperature above 80 C. Apply
the contract's swap-growth and recovery comparisons without retuning afterward.
Preserve phase timestamps, sample history, Job identities, normalized hashes and
owned-object manifest. Partial coverage is incomplete, not a pass.

The overlap phase requires a separately reviewed application-aware backup using
Restic-owned tooling and consistent database/media recovery inputs. The prior
canary restore does not satisfy application recovery. Prepare backup and isolated
full restore as distinct operations; do not substitute another canary. Without
backup readiness, prepare the workload implementation but leave full execution
blocked. Cleanup deletes only proven fixture-owned objects under explicit scope;
retain data and evidence on failure. Never automatically restore the database.

## Persistence operation

After a fresh running baseline and reviewed recovery inputs, define a separate
bounded logout test and controlled reboot operation. Reconfirm console recovery
and record pending kernel/package changes before freezing the reboot bundle.
Do not add package updates to that operation. Identify the exact running services,
boot ID, root device, network/guard identities, data hashes and restart counts.

For logout, close the test account's login sessions and prove from an independent
administrative connection that the user manager and services stay active without
restarts for a proposed five-minute window. Linger configuration alone is not
proof. Do not disrupt other operators' sessions without explicit scope.

For reboot, require a changed boot ID, automatic startup without a manual start,
completed migration unit, all five services healthy, fresh worker/scheduler
heartbeats, no failed required units, private PostgreSQL/Redis, unchanged durable
data and effective limits. Recheck both backend families, proxy-only access and
management/monitoring continuity. Observe at least 75 seconds after successful
readiness and retain boot-bounded storage/OOM evidence. Freeze concrete readiness
and reconnect deadlines in the operation after reviewing the baseline.

If readiness or reachability fails, stop progression, preserve evidence and use
confirmed console recovery when SSH is unavailable. Do not repeatedly reboot or
run destructive restore. A separate reviewed recovery action must specify any
service stop, artifact rollback or data restore; prior cold-copy presence alone
is not proof that a current restore is safe.

## Remaining gates and authorization

Publish the startup archive, reconcile accepted identity/history, and clear only
its consumed operation data. Then implement and locally test workload adapters
and persistence collection before freezing any live bundle. Each live stage
needs its exact scope and bundle approval; this preparation authorizes no load,
logout, reboot, backup, restore, Caddy change or deletion.

Seven stable pilot days need recorded start/end times and monitoring coverage;
elapsed time alone is insufficient. Caddy stage 6 separately proves trusted HTTPS
through both Proxy VIP families, expected denial/unknown-host behavior and access
restrictions. Application-aware backup/full isolated restore, reconciliation and
seven-day stability remain prerequisites to authority migration or Semaphore.
