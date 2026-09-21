# Disposable configuration and authentication qualification

This stage follows archived image-store readiness. Its implementation is prepared for
separate exact-bundle approval. It is
preparation under stage 5 of [the deployment plan](NAUTOBOT_DEPLOYMENT_PLAN.md),
not production deployment or permission to execute containers. The single active
operation slot retains the executed definition pending archival. The first trial
failed at the application-probe step and cleaned up successfully; the terminal
outcome is in `../manifests/authentication-trial-result.json`. The diagnostic retry is prepared as an external candidate while this terminal
definition remains intact; execution requires its annotated published failure tag
and a new exact-bundle approval.

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

The implementation uses `ansible/playbooks/authentication-trial.yaml`, the frozen
launcher `ansible/scripts/authentication-trial.py`, and private node adapters in
`ansible/scripts/auth-trial-node.py`. Ansible sequences creation, readiness and the
probe. The node helper suppresses secret-bearing Podman output and independently
guards health, deadline and cleanup.
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

Enforced ceilings: PostgreSQL 768 MiB, Redis 512 MiB, probe 1536 MiB, two CPUs per
container, no swap, a 15-minute active-trial deadline, followed by bounded teardown and observation. The orchestrator must
prove effective per-container cgroup limits before tests, guard host memory at
1.5 GiB available, temperature below 80 C, zero throttling and quiet storage.
A node-local systemd watchdog starts before runtime objects exist and performs
cleanup on deadline or health failure without the controller. Its 1500-second
RuntimeMaxSec and 360-second stop-handler timeout bound the watchdog; ExecStopPost
attempts cleanup after a killed watchdog. Each container also has a 900-second
Podman timeout. Live deadline enforcement remains a target qualification concern;
a failed teardown requires explicit residue review, never an acceptance claim.

The watchdog samples every five seconds and rejects gaps over 15 seconds, including
teardown. Limits are read from each running container's actual cgroup and ancestors;
missing/unlimited controls fail. No fallback silently removes resource limits.

Mount existing scoped environment files privately: PostgreSQL gets only its own
file plus non-secret user/database settings; Redis gets its existing configuration
secret and health environment; the probe gets one existing application environment
and read-only `nautobot_config.py`. Redis mounts its configuration secret as
container UID/GID 999, mode 0400. The idle probe overrides the image entrypoint with
`/bin/sleep infinity`; only the explicit Django shell probe may execute application
code. Do not distribute the initial-admin credential.
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
case deliberately fails this probe. The node retains only categorical probe
acceptance, not raw exceptions or server logs. A failure requires a separately
reviewed diagnostic approach; neither a generic connection exception nor a matching
message substring proves authentication rejection.

The offline tests cover configuration mismatch, password rejection versus network
failure, PostgreSQL identity, missing/wrong Redis credentials, connection cleanup
failure and missing marker. They do not execute the installed framework or prove
live authentication. `tests/test_authentication_trial.py` additionally exercises
the real frozen producer and actual Ansible partial-startup/always path, simulated
controller loss, deadlines, guard failure, cleanup failure, ownership checks,
mount/port rejection and effective cgroup limits. Local unstarted PostgreSQL and Redis
container inspections confirm the Podman metadata shape; it does not qualify ARM64
startup or the target Podman version. The exact CLI source was inspected in the
pinned image during preparation.

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

## Freeze, review and execute

Prepare and verify locally (no target contact):

```bash
python3 Nautobot/ansible/scripts/authentication-trial.py prepare /tmp/nautobot-authentication-trial-bundle-YYYYMMDD
python3 /tmp/nautobot-authentication-trial-bundle-YYYYMMDD/launcher.py verify /tmp/nautobot-authentication-trial-bundle-YYYYMMDD SHA256
```

After explicit approval of the emitted SHA-256, execute only that frozen launcher:

```bash
python3 /tmp/nautobot-authentication-trial-bundle-YYYYMMDD/launcher.py execute /tmp/nautobot-authentication-trial-bundle-YYYYMMDD SHA256
```

Target: `ama@j2-svpi4mf.local.theama.co`, strict host-key alias `10.1.2.170`.
The rootless account is `nautobot`; systemd hosts only the privileged health and
teardown guard. The controller records private evidence beneath `/tmp`; node
sources and sanitized evidence remain in an owned `/var/tmp/nautobot-auth-*`
directory for recovery. Do not remove that directory while the guard or any
trial object exists. It contains no staged credential values.

Review `controller-result.json`, node `result.json`, `cleanup.json`, the four probe
checks, per-container limits, sample history, execution trace and retained node
location. Ansible failure, missing records, a coverage gap, cleanup residue or
configuration drift prevents acceptance. Inspect the recorded systemd unit and
owned IDs when recovery is needed; reuse the frozen node helper's `emergency`
action only within the authorized trial scope. No broad prune is permitted.

Podman options and inspection expectations follow the official
[create reference](https://docs.podman.io/en/latest/markdown/podman-create.1.html).
The bundle includes the exact code, schema, plan, provenance and non-secret inputs;
changes require a new bundle identity before execution.

## Failure diagnostics and retry preparation

The node writes `diagnostic.json` before each probe substep: guard, inspect,
validate, effective limits, probe identity resolution, Django shell, result parsing
and final guard. It records the container role and only exact allowlisted assertion
categories; unknown exceptions become `unclassified_failure`. The bounded capture
helper can deliver exit status and streams to an in-memory observer even on a
nonzero exit, timeout or output-limit failure. Only strict probe JSON categories
and completed fixed check names are persisted. Raw streams and exception messages
are discarded. A diagnostic report never substitutes for acceptance evidence.

A failure before the probe starts therefore retains its validation stage; a
structured probe rejection retains its settings/PostgreSQL/Redis phase. An
unstructured framework error retains the Django-shell stage and command status,
not an inferred cause. Credentials remain absent from diagnostics and tests include
secret-bearing synthetic output to enforce that boundary.

Prepare a retry candidate outside the active manifest with:

```bash
python3 Nautobot/ansible/scripts/authentication-trial.py prepare /tmp/RETRY_BUNDLE --operation /absolute/private/operation.yaml
```

The retry binds the prior failed result hash. Before any host contact, execution
requires that exact result in an annotated Git tag and verifies the same tag object
on origin. Until terminal archival is authorized and completed, the candidate is
reviewable but blocked from execution. Preserve the active executed definition;
do not replace it with the candidate merely to prepare a bundle.
