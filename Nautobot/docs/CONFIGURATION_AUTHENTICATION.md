# Disposable configuration and authentication qualification

This stage follows archived image-store readiness. Its implementation is prepared for
separate exact-bundle approval. It is
preparation under stage 5 of [the deployment plan](NAUTOBOT_DEPLOYMENT_PLAN.md),
not production deployment or permission to execute containers. The single active
operation slot is clean after readiness archival. All five
readiness checks passed, including native configuration and positive PostgreSQL/Redis
connections. Cleanup and delayed health observation passed. The terminal result is
`manifests/configuration-readiness-result.json`; its published identity is in
`manifests/configuration-readiness.json`. Negative security tests remain
unresolved; production runtime and administrator login are not accepted by this trial.

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
| Native configuration | Nautobot-initialized Django management `check` completes without an error; invoked through `call_command`. This is the same command as `nautobot-server check`, not a migration or deployment-security audit. |
| Plugin | DNS Models registered in Django; actual installed Nautobot and plugin versions match the pinned inputs. |
| PostgreSQL | Explicit TCP connection using the application backend/settings succeeds; `SELECT current_user, current_database(), inet_server_port()` matches intended identities and port 5432. Connection or query failure prevents readiness acceptance. Negative password testing is separate. |
| Redis cache | Clone the actual Django cache connection parameters with five-second socket/connect timeouts. Correct application credentials return PONG on database 1; connection, authentication or cleanup failures prevent acceptance. |
| Redis broker | The actual Celery broker connection returns PONG using its configured credentials on database 0. Failures prevent acceptance. |
| Cleanup | Close/disconnect every probe connection. Stop and remove only operation-owned container IDs and network; attempt remaining cleanup after any failure. No persistent trial volume or worker may remain. |
| Host continuity | Accepted boot, effective limits, unchanged credential metadata/settings and no kernel/storage/OOM event; at least 75 seconds of sampled observation after teardown. |

The pinned settings default the database port to an empty string, which Django
omits from its connection parameters. Accept that default or explicit 5432, reject
conflicting `PGPORT`, and independently verify the connected server port. An empty
setting alone is not evidence of the endpoint actually reached.

Probe output contains only acceptance, fixed check names, categorical failed
phase, allowlisted `failure_code` and `exception_category`. Exception messages,
settings, environment dumps, connection URLs and passwords must
remain out of reports. Capture all container/CLI streams privately with output and
time limits: framework startup itself can emit errors before the probe runs.
Parse the final JSON result strictly; require successful exit status, all five
check names and no missing phase. Probe acceptance alone cannot override failed
or missing cleanup, host observation or isolation evidence.

PostgreSQL clients may omit SQLSTATE on connection-establishment failures. The
previous wrong-password contract required `28P01`; v6 could not establish it. That
negative-test result stays inconclusive. Readiness now verifies the actual positive
application connection independently; it does not claim password rejection is
proven. Effective authentication policy and private network requirements remain.

Negative PostgreSQL and Redis tests are retained only behind explicit
`include_negative=True` helper calls for separately reviewed testing. The live
readiness entrypoint never enables them. No server-log correlation is a prerequisite
for the positive readiness stage. The native `check` uses its default error threshold;
passing it is not a claim that deployment warnings or all production checks are clear.
Raw command output is discarded to avoid exposing configuration values; a fixed
native-check failure code identifies that step. Review failures before proceeding.

Tests cover native-command invocation/failure, the five-check readiness entrypoint,
positive-only connection selection, positive errors, cleanup failures, diagnostic
redaction and retained separately invoked negative semantics. Offline mocks establish
orchestration contracts, not actual driver/server behavior. The isolated Ansible
suite exercises partial startup, always-cleanup, ownership, guard and limit failures.
Authoritative ARM64 application behavior is verified only in the approved live stage.

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

Review `controller-result.json`, node `result.json`, `cleanup.json`, the five probe
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
structured probe rejection retains its settings/PostgreSQL/Redis phase and exact
allowlisted assertion code. Database engine, host, name, user, password and port
checks have separate codes without exposing their values. Unknown errors use
`unclassified_failure`; the node rejects codes outside the shared vocabulary.
Tests exercise the actual probe entrypoint and node parser, including secret
suppression and vocabulary parity. An
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

## PostgreSQL socket mount and Podman inspect

Use the canonical `/run/postgresql` destination for the 16 MiB socket tmpfs,
mode 3775. The pinned PostgreSQL filesystem links `/var/run` to `/run`.
Requesting `/var/run/postgresql` can produce an inspect key before startup that
is absent afterward: Podman matches configured user-volume paths to runtime
specification destinations by exact spelling. See the version-specific
[volume selection source](https://github.com/containers/podman/blob/v5.4.2/libpod/container_internal.go#L2566)
and [inspect source](https://github.com/containers/podman/blob/v5.4.2/libpod/container_inspect.go#L605).

Local bounded rootless tests reproduced the disappearance and confirmed stable
metadata with the canonical path. Captured before/after metadata is retained in
`tests/fixtures/tmpfs-symlink.json` and `tmpfs-canonical.json`; the authentication
trial suite consumes both. Exact mount-set and size checks remain enforced, with
regressions for missing, extra and oversized tmpfs mounts. The failed host trial's
individual mount keys were not captured; corrected target acceptance remains a
separate live stage. Do not accept arbitrary additional or missing mounts as a
compatibility workaround.

## Initialization prerequisites and safe startup diagnostics

The pinned Nautobot CLI calls `_preprocess_settings()` before handing off to
Django. This creates GIT_ROOT, JOBS_ROOT, MEDIA_ROOT (and two subdirectories),
and STATIC_ROOT. Those default directories under `/opt/nautobot` are absent from
the pinned image. The current trial's read-only root does not provide writable
storage there. A successor needs a reviewed, bounded disposable directory policy;
do not introduce production volumes or cover the entire application home, including
its user-installed dependencies, with an empty mount.

This is a source-established prerequisite, not recovery of the discarded v3
exception. [Django initialization](https://docs.djangoproject.com/en/5.2/ref/applications/#initialization-process)
then loads settings/logging and populates the application registry before shell
execution. Successful container readiness does not prove those stages completed.

The stderr observer retains only allowlisted exception classes, fixed traceback
source labels with line numbers, and fixed filesystem errno categories. Unknown
paths, source lines and exception messages are discarded. Output remains bounded;
no traceback locals, credentials, connection URLs or arbitrary exception text
are saved. The diagnostics distinguish framework startup from structured probe
rejection but never substitute for authentication or cleanup acceptance.

## Bounded startup-directory mounts

The successor mounts `/opt/nautobot/git`, `/opt/nautobot/jobs`,
`/opt/nautobot/media` and `/opt/nautobot/static` as four separate 16 MiB tmpfs
filesystems. Mode 1777 permits the non-root application user to create the required
subdirectories without a privileged initialization command. These directories are
private to the disposable container and disappear at teardown. Its 1536 MiB
memory and zero-swap limits still bound aggregate usage. No Jobs, media imports or
static collection are performed by this authentication trial.

The application home and `.local` dependencies remain visible; settings retain
their existing read-only bind. Exact destination, size and writable sticky-mode
checks fail closed. Local rootless tests exercise the same generated mount options
with a non-root UID, directory creation, read-only settings and dependency visibility.
Target ARM64 framework initialization and authentication remain live acceptance
checks, not outcomes of that local filesystem fixture.

## PostgreSQL attempt diagnostics

A PostgreSQL rejection includes a strictly validated `postgres_diagnostic` with
`attempt` (positive/negative), `step` (construct/cursor/query/fetch/close),
allowlisted `exception_category` and `sqlstate`. Absent SQLSTATE is `absent`;
unknown values become `other`. Raw messages and connection values are excluded.
Distinct assertion codes identify positive failures, negative missing/unexpected
SQLSTATE and cleanup failures. A cleanup failure is fatal even after otherwise
successful authentication. Tests exercise producer JSON and node readback.

Django's cursor acquisition includes driver connection and backend initialization;
a cursor-stage error does not by itself establish password rejection. Retain the
strict SQLSTATE `28P01` criterion only within separately invoked negative tests.
It no longer gates positive readiness. Current diagnostics do not establish the
cause of a previously recorded aggregate rejection.

## Requirement provenance and approved revision

Commit `0317261804d153ddf0b54f3ae5a6eca9af74d23d` on September 21, 2026 at
14:57:11 CDT introduced the exact SQLSTATE negative requirement in this procedure,
the probe and tests. It was an assistant-authored qualification requirement, not an
explicit master-plan or upstream installation requirement. The master plan was not
modified by that commit. The user subsequently approved replacing that readiness
gate with native configuration and positive PostgreSQL/Redis verification. Historical
failed contracts and their archives remain intact.

After the revised qualification passes, prepare the planned initialization/runtime
operation: satisfy the Restic pre-data prerequisite before durable application data,
then use the migration unit's `post_upgrade`, administrator bootstrap and application
health/login validation. Preserve the rootless Quadlet model, private services,
resource limits, controlled exposure and recovery requirements. These are future
scoped operations, not commands authorized by this procedure or readiness success.
