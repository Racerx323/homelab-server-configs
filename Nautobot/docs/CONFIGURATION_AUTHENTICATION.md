# Disposable configuration and authentication qualification

This stage follows archived image-store readiness and remains inactive. It is
preparation under stage 5 of [the deployment plan](NAUTOBOT_DEPLOYMENT_PLAN.md),
not production deployment or permission to execute containers. The single active
operation slot is clean.

## Prepared checks and provenance

The candidate in-container probe is
`ansible/scripts/configuration-auth-probe.py`; its offline suite is
`tests/test_configuration_auth.py`, wired into pre-commit and the existing CI
validation runner. The probe runs only after Nautobot initializes Django and
requires an explicitly mounted disposable-trial marker. The marker is an
accidental-invocation guard, not authorization or proof of isolation.

Bind these inputs when preparing the execution bundle:

- `runtime-image-store.json`: published image-load tag, peeled commit and result
  hash. Resolve all three immutable references from the archived result and
  compare fresh local-store inspection before starting any container.
- `qualified-image.json`, `runtime-inputs.json` and `desired-state.yaml`: original
  image qualification, application/recovery identity, version and service policy.
- `provisioned-credentials.json` and archived credential result: existing injection
  identity. Do not create, retrieve bootstrap credentials, rotate or overwrite.
- The exact seven protected runtime inputs, the Redis Podman secret metadata,
  non-secret settings template and accepted host/boot identity. Compare metadata
  and the settings hash before and after; do not hash secret values into evidence.

The image-store tag is `nautobot-image-load-v1-ready`, peeled commit
`0dd657bc6f7c1a5c742bc8e07e64e3ab6d50d27b`. Its readiness result does not prove
application settings, authentication or successful startup.

## Isolated execution design

Implement the next operation with Ansible plus the existing frozen-bundle and
bounded-watchdog conventions. No executable trial launcher/bundle is prepared yet.
Use a unique operation-owned private network and three disposable containers.
Require absence of all selected names before creation and record exact object IDs.
Never attach to `nautobot-private` or use production container/volume names.

Use only already-loaded images with pulling disabled, no published ports, no host
networking, and no production data mounts. Provide network aliases `postgresql`
and `redis` for the disposable services. PostgreSQL uses an explicitly sized
512 MiB tmpfs at its data path; Redis uses 128 MiB tmpfs at `/data`. No named or
anonymous persistent data volume is allowed: inspect the actual mounts before
running the probe. Fail if image-declared volumes create unreviewed durable storage.
PostgreSQL initializes a disposable database with the intended user/database and
password; this is an authorized-test prerequisite only after bundle approval,
not production database initialization or a Nautobot schema migration.

Proposed ceilings: PostgreSQL 768 MiB, Redis 512 MiB, probe 1536 MiB, two CPUs per
container, no swap, maximum 15 minutes for the whole trial. The orchestrator must
prove effective per-container cgroup limits before tests, guard host memory at
1.5 GiB available, temperature below 80 C, zero throttling and quiet storage.
Prove all trial workers stop at the deadline even if the controller disconnects.
Cgroup placement and timeout teardown require implementation and failure tests;
reuse qualified mechanisms without assuming image-transfer units alone contain
container payloads.

Mount existing scoped environment files privately: PostgreSQL gets only its own
file plus non-secret user/database settings; Redis gets its existing configuration
secret and health environment; the probe gets one existing application environment
and read-only `nautobot_config.py`. Do not distribute the initial-admin credential.
Start no application web, worker, scheduler, Job or production migration.

Use the installed Nautobot command path to initialize settings and Django, then
invoke the probe through the Python shell. Candidate command inside the reviewed
probe container (not a workstation or host execution command):

```text
nautobot-server shell --interface python --command "exec(compile(open('/run/nautobot-qualification/probe.py').read(), '/run/nautobot-qualification/probe.py', 'exec'), {'__name__': '__main__'})"
```

Set `NAUTOBOT_CONFIG=/opt/nautobot/nautobot_config.py` and mount the read-only marker
`/run/nautobot-qualification/isolated-trial` with content
`disposable-configuration-authentication`. The pinned OCI archive's CLI and Django shell source confirm these options and
command dispatch. Explicit `__name__` is necessary because Django executes the
command in its own module namespace. Actual settings and authentication behavior
remain live qualification checks. See
[Nautobot configuration guidance](https://docs.nautobot.com/projects/core/en/stable/user-guide/administration/configuration/).

## Acceptance matrix

| Check | Required result |
| --- | --- |
| Configuration | Exact mounted settings path, DEBUG/installation metrics off, approved hosts/CSRF/proxy header, injected secret matches in memory only, no bootstrap credential. |
| Plugin | DNS Models registered in Django; actual installed Nautobot and plugin versions match the pinned inputs. |
| PostgreSQL | Explicit TCP connection using the application backend/settings succeeds; `SELECT current_user, current_database()` matches intended identities. Wrong password returns SQLSTATE `28P01`. Timeout, refusal or another SQLSTATE fails qualification. |
| Redis cache | Clone the actual Django cache connection parameters with five-second socket/connect timeouts. Correct credentials return PONG on database 1; missing and wrong credentials raise authentication errors. |
| Redis broker | Apply the same tests to the actual Celery broker connection on database 0. A network failure never counts as password rejection. |
| Cleanup | Close/disconnect every probe connection. Stop and remove only operation-owned container IDs and network; attempt remaining cleanup after any failure. No persistent trial volume or worker may remain. |
| Host continuity | Accepted boot, effective limits, unchanged credential metadata/settings and no kernel/storage/OOM event; at least 75 seconds of sampled observation after teardown. |

Probe output contains only acceptance, fixed check names and categorical failed
phase. Exceptions, settings, environment dumps, connection URLs and passwords must
remain out of reports. Capture all container/CLI streams privately with output and
time limits: framework startup itself can emit errors before the probe runs.
Parse the final JSON result strictly; require successful exit status, all four
check names and no missing phase. Probe acceptance alone cannot override failed
or missing cleanup, host observation or isolation evidence.

PostgreSQL clients may omit SQLSTATE on connection-establishment failures. That
case deliberately fails this probe; the execution design must preserve private
disposable-server evidence for review rather than treating a generic connection
exception or a matching message substring as proven authentication rejection.

The offline tests cover configuration mismatch, password rejection versus network
failure, PostgreSQL identity, missing/wrong Redis credentials, connection cleanup
failure and missing marker. They do not execute the installed framework or prove
live authentication. Before freezing a live bundle, add actual Ansible sequence,
partial-startup, timeout/controller-loss, cleanup-failure and mount/port rejection
fixtures. Verify the exact CLI path against the pinned image; general help output
is insufficient.

## Completion and recovery boundary

On a failed check, stop later provocative tests and tear down only proven owned
objects. Keep bounded sanitized evidence. If object ownership is ambiguous, stop
with explicit manual intervention; never prune, remove shared images, delete
production volumes or rotate credentials. Attempt all independent cleanup steps
and report each residue. A failed cleanup prevents acceptance even if every probe
passed. Temporary PostgreSQL/Redis data is discarded only within the reviewed
explicitly disposable scope.

On success, archive this qualification before starting another operation. Runtime
command startup, migrations, administrator bootstrap, firewall/backend exposure,
Restic pre-data gates, deployment persistence, workload, application recovery and
pilot soak remain separate. This check does not bypass the Restic gate before
entrusting production application data to storage.
