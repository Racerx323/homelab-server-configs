# Startup baseline and recovery preparation

This procedure defines bounded read-only review for `ama@10.1.2.170`. The
September 22 refresh and stopped-volume preservation passed; evidence and archive
identities are recorded in the roadmap and history. The prepared startup operation
requires separate exact-bundle execution approval.

## Baseline collection

During an authorized read-only visit, collect one timestamped record containing:

- Hostname, boot ID, UID/GID, mount identity, available memory and filesystem space.
- All six user service states and invocation IDs, full container inventory and
  listeners. Require stopped services, no leftover containers and no TCP 8080
  listener. Unexpected residue is a review finding, not permission to delete it.
- Installed image IDs, ARM64 architecture, volume identities and mount paths;
  compare images with `runtime-inputs.json` and accepted initialization records.
- Hashes and metadata of installed runtime code, configuration and Quadlets;
  compare against the accepted bootstrap archive. Inspect credential file/object
  presence, ownership and permissions without retaining values or secret hashes.
- The root-owned backend verifier result, its installed artifact identities and
  network-owner accepted packet archive. Preserve packet qualification scope:
  current HA ownership and a disposable listener, not Caddy application traffic.
- Bounded current-boot kernel/storage errors and journal cursor. Existing SMART
  reporting limitations remain documented; do not issue new SMART commands.

The prepared collector is `ansible/scripts/startup-preflight.py`. After host-contact
authorization, stream it to the fixed target with strict host-key checking:

```sh
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes ama@10.1.2.170 \
  'cd / && sudo -n /usr/bin/python3 -' < Nautobot/ansible/scripts/startup-preflight.py
```

Redirect stdout/stderr to separate protected evidence files and retain SSH status.
The collector always emits `accepted: false`; review must compare its output with
the accepted archives. Collect the bounded kernel history and volume sizing
separately during the same authorization; the collector does not claim those checks.

Use fixed `sudo -n` commands through strict host-key SSH. Store raw readbacks in a
new mode-0700 private evidence directory, retain exit codes and bounded outputs,
and write a sanitized baseline receipt only after reviewing every comparison.
The receipt has `host`, UTC `collected_at`, `boot_id`, `services` (each including
`ActiveState`, `SubState`, `InvocationID`) and `accepted`. The startup launcher
requires a baseline no older than one hour and rechecks boot, stopped services,
container absence and the installed guard before service mutation. Refresh rather
than changing its timestamp if the receipt expires.

## Recovery review

Read-only checks determine the exact PostgreSQL volume path, size, free capacity,
ownership and existing recovery artifacts. Do not copy a live database or start
services during this review. The earlier pre-data Restic canary and historical
pre-migration copies cannot restore the current database and administrator.

Prepare a separate stopped-volume preservation operation: verify PostgreSQL remains
stopped and no process holds the data directory; preserve the identified volume
with numeric ownership and permissions into a new private destination; verify a
complete file manifest and hashes, capacity and source consistency before/after.
Record exact source/destination and recovery commands. Never overwrite the source
or label a copy an exercised restore. Starting services, writing this copy or
performing a restore requires its own scoped authorization.

The reviewed recovery receipt includes `host`, `boot_id`, `accepted`, `verified`,
`scope: initialized_database_and_administrator`, capture timestamp, evidence hashes,
and exact recovery location. The operation reviewer must establish that no database
writes occurred between capture and startup. The startup launcher requires the
scope, verification and matching boot; it does not independently qualify a restore.
Application-aware Restic backup and isolated restore remain later owner stages.

## Startup execution inputs and evidence

`run-startup.py show-hash SPECIFICATION.json` validates nonsecret inputs against
`startup-execution.schema.json` and hashes the playbook, launcher, helpers, policy,
inventory, rendered files, baseline/recovery receipts and all probe files. Execution
uses `run-startup.py execute SPECIFICATION.json AUTHORIZED_SHA256`, only after the
separate operation activation and exact-bundle authorization. A clean source tree
is required. The current policy deliberately prevents execution.

The acceptance collector executes ordered, frozen Python probes, with deadlines,
through `collect-startup.py`. Each probe returns exactly one bounded JSON object;
expected fields are compared with exact types and values. Nonzero status,
truncation, malformed output or a mismatch stops collection and triggers Ansible
recovery. Raw stdout, stderr, credential values and browser cookies are not retained.
Command arguments must contain references only, never passwords or tokens. Secret
resolution and cleanup belong inside the reviewed probe, including failure paths.

Before freezing, assemble probes for all of these existing acceptance criteria:

| Group | Required observations |
| --- | --- |
| Native configuration/migrations | Native `check` and `migrate --check` succeed against the running initialized application. |
| HTTP/static | `/health/` is 200; actual CSS and JavaScript responses have expected types/content; redirects do not substitute for success. |
| Administrator | Login, authenticated identity, logout and rejected session reuse over retained loopback SSH; valid and invalid Host/CSRF behavior. |
| Network | Both proxies reach both permanent backend families; reviewed non-proxy denies have corresponding guard counters and allowed probes before/after; exact binds. |
| Worker/scheduler/Job | One worker at concurrency 2, one scheduler, broker/cache authentication and a bounded harmless asynchronous Job with recorded completion. |
| Resource/secrets | Actual cgroup limits, swap prohibition and absence of bootstrap credentials/temporary credential residue. |
| Cleanup/storage | Probe cleanup, unchanged boot, at least 75 seconds of cursor-bounded storage observation without new reset/I/O errors. |

Group coverage alone is not adequate contract review: inspect the probe code,
expectations, dependency files and evidence provenance for every row. The generic
collector cannot infer that a probe labelled as an administrator check actually
performs browser authentication. The native HTTP/service probes are joined by the concrete session, network and
Job probes listed below. Assemble their frozen paths and expected fields with the
runtime/resource/storage checks through `assemble-startup.py`. No receipt may be
substituted with a hand-authored success value or old packet-trial result.

The workload manifest's import/export/audit adapters remain unqualified. A startup
smoke Job can prove worker dispatch but must not be called representative workload
acceptance. Select and review harmless inputs before execution; retain workload
qualification as its existing later gate.

Ansible stages and verifies the independent stop helpers before arming the timer,
starts services in order, invokes the collector, and only disarms the guard after
success. Failure attempts all service stops and preserves data. Controller loss
leaves the independent guard armed. Original files are backed up; data rollback is
not automatic. Review node evidence and stopped state before any retry.

## Concrete probe implementations

- `startup-browser-probe.py` drives the actual login form and cookies through a
  retained loopback SSH tunnel. It checks missing-CSRF and invalid-Host rejection,
  verifies the authenticated admin from the server session, then invokes the
  pinned GET logout endpoint and proves that session is no longer authenticated.
  It resolves the existing Doppler reference only during authorized execution;
  credentials and cookies remain in memory. This is HTTP-session verification,
  not a claim of rendered JavaScript/UI coverage.
- `startup-network-probe.py` uses `startup-network-client.py` on both proxy nodes
  and the approved Munin vantage. It requires HTTP 200, permanent source addresses,
  paired allowed probes and family-specific drop-counter increments for denials.
  Refusal or a closed port cannot count as successful denial. It changes no rules.
- `startup-job-controller.py` invokes `startup-job-probe.py` through the running
  web container. The probe requires one worker at concurrency 2, temporarily
  enables only the installed `startup_readiness.StartupReadiness` Job, dispatches
  asynchronously, checks the completed result and restores the prior enabled flag
  even on failure. Framework JobResult/log records remain for audit.
- `startup-job.py` contains the mounted Job: `SELECT 1` and a fixed 16-KiB SHA-256
  calculation, with 20-second soft and 30-second hard limits. There is no external
  request or inventory mutation. This smoke check does not satisfy the later
  representative workload/headroom gate.

The session and Job APIs were checked against the pinned
[Nautobot 3.2.3 login/logout source](https://github.com/nautobot/nautobot/blob/v3.2.3/nautobot/users/views.py)
and [Job implementation](https://github.com/nautobot/nautobot/blob/v3.2.3/nautobot/extras/models/jobs.py).
Local tests cover the HTTP flow, redirect restrictions, deny classification and
restoration of the Job flag on dispatch failure. ARM64 runtime behavior is still
an explicit live startup acceptance check, not a result of those fixtures.

The September 22 read-only baseline and hashes are retained privately in
`/home/aaron/code/.local-evidence/nautobot-startup-preflight-20260922/REVIEW.json`.
The separate [preservation operation](STARTUP_PRESERVATION.md) has a verified
recovery receipt and published archive. The refreshed baseline is retained in
`/home/aaron/code/.local-evidence/nautobot-startup-assembly-20260922/`.
See [startup execution](STARTUP_EXECUTION.md) for the assembled contract.
