# Application startup execution

This operation starts the single-host pilot using the accepted initialized database
and existing administrator. The master deployment plan still governs workload,
reboot persistence, Caddy onboarding and application-aware backup/restore acceptance.
None of those later stages is accepted by this startup check.

## Preconditions and authorization

Archive preservation first. Review a fresh stopped baseline with unchanged boot,
images, environment-file metadata, configuration, six processless services, no containers
or TCP 8080 listener, verified backend guard and bounded kernel review. The launcher
requires the reviewed baseline to be no more than one hour old at execution. If it
expires, recollect and review it, rebuild the hash and obtain approval of that hash;
do not change the timestamp of old evidence.

The reviewed migration configuration-failure marker may remain `failed/failed`
with `Result=exit-code`, `ExecMainStatus=69`, a retained InvocationID and both
MainPID/ControlPID zero. Reviewed web/worker/scheduler cleanup markers may
remain failed/failed with Result=exit-code, ExecMainStatus=137, a retained
InvocationID and both PIDs zero. Require evidence that these statuses followed
cleanup, not an unexplained crash. PostgreSQL/Redis must be inactive/dead with
both PIDs zero. The live preflight must exactly match the frozen service-state records
before mutation. Do not run `reset-failed` merely to make the baseline pass.
Starting migration creates a new invocation, which must subsequently pass normal
healthy-readiness checks; baseline eligibility is not application acceptance.

The policy's `execution_authorized` flag enables the prepared launcher contract;
it is not user approval. The launcher additionally requires the exact approved
hash, reviewed recovery, active operation, published network evidence and clean Git
source. `assemble-startup.py OUTPUT BASELINE REVIEWED_RECOVERY` renders nonsecret
artifacts and seven concrete checks. `run-startup.py show-hash SPECIFICATION` checks
input hashes. Only `run-startup.py execute SPECIFICATION APPROVED_HASH` contacts the
host. Review the exact specification and all changed artifact destinations first.

## Mutation and checks

Target: `ama@10.1.2.170`. Stage bounded root-owned helpers, capture a journal cursor,
and arm a two-hour independent stop timer. Preserve original artifact backups;
install reviewed runtime code/Quadlets and reload the user manager. Existing
PostgreSQL/Redis units remain byte-identical. Start PostgreSQL, Redis, migration,
web, worker and scheduler serially, requiring new successful invocations.
Migration runs native `post_upgrade` against the initialized database, including
Job discovery. The web role collects static assets. The media volume is new,
durable and owned by container UID/GID 999. The application remains rootless.

The collector requires all seven groups:

1. Native configuration/migration/static receipts from current invocations, plus
   healthy service states and no restarts.
2. HTTP 200 health and nonempty CSS static response through loopback recovery.
3. Administrator form login with a valid CSRF token, existing-session identity,
   logout/session revocation, hostile Host/missing-CSRF rejection, tunnel cleanup.
   The existing Doppler administrator password stays in process memory. This is
   an HTTP session check, not rendered JavaScript or full browser UX acceptance.
4. Both proxy nodes to both backend address families; non-proxy IPv4/IPv6 timeout
   correlated with family-specific deny counters and bracketing positive checks.
   No proxy, DNS, HA or network configuration is changed.
5. One harmless asynchronous Job on the single worker with concurrency two. It
   performs SELECT 1 and deterministic hashing, restores its prior enabled flag,
   and retains its JobResult. This is a queue smoke test; the representative
   workload stage remains separate despite the historical acceptance-group name.
6. Actual container/cgroup limits, no OOM, private database/cache ports, rootless
   read-only application containers and protected credential-file metadata.
7. At least 75 seconds after preceding checks, cursor-bounded kernel review,
   unchanged boot and service invocations. No SMART query or self-test is issued.

## Success, failure and recovery

On success, disarm the unused timer and leave services running pending later
acceptance. Retain the result, lifecycle receipt and backups. On failure, stop all
six services in reverse order and prove no containers remain. Only then disarm the
timer. If stopping cannot be proved, leave the timer armed and report manual
intervention. Never automatically restore or delete data, retry migration, rotate
credentials, reboot, or publish through Caddy.

Recovery copies are verified cold copies, not exercised restores. Restoring one
requires a separate reviewed operation with services stopped, the then-current
volumes preserved, and independent post-restore validation. Artifact backups are
retained for a separately reviewed reversal; stopping services is the automatic
failure action, not a claim that files or database changes were rolled back.

## Failed configuration checks

The startup wrapper retains bounded, redacted stdout/stderr tails when a native
command fails (16 KiB per stream; 4 MiB drain limit per stream). It removes
inherited environment values and common credential forms before emitting the
receipt. Treat retained output as private until reviewed; redaction is not a
license to publish raw logs. Success receipts omit command output.

Readiness stops immediately when systemd reports terminal failure. Cleanup
requires MainPID and ControlPID to be zero, a stopped or failed terminal state,
and no remaining containers. A retained failed marker is not a running process
and must not be cleared merely to make cleanup appear successful. Healthy
readiness still rejects failed units. Journal capture extracts exactly one actual
`-- cursor:` line and rejects missing or ambiguous values.

If an older wrapper discarded the native error, use the separately hash-bound
`diagnose-startup-configuration.yaml` path. Its frozen directory contains the
launcher, playbook, helpers, minimal inventory, Ansible configuration and inputs.
Inputs bind the expected boot, installed nonsecret hashes, image ID/reference,
and prior stop-guard identity. The launcher hashes every execution input.

After exact-bundle authorization, the diagnostic verifies the stopped baseline,
arms its own twenty-minute cleanup timer, starts only PostgreSQL and Redis and
runs only `nautobot-server check` in a disposable rootless container. It uses the
existing protected migration environment and the installed configuration/Job,
with bounded writable directories matching migration. It does not invoke
`post_upgrade`, migrations, bootstrap, web, worker or scheduler. Normal data
service operation can write their volumes; this is not read-only collection.

Ansible always attempts cleanup. Only the identically labeled disposable
container may be removed; production volumes and recovery copies are preserved.
After no-process/no-container proof it disarms the diagnostic and prior startup
timers. The migration failed marker remains. Incomplete cleanup retains the
guard and requires investigation. A captured nonzero native check is diagnostic
success, not configuration acceptance. No startup retry is implied.

## Writable metrics cache

The pinned Nautobot image inherits `prometheus_multiproc_dir=/prom_cache`.
Health-check instrumentation initializes this client during Django startup,
including `nautobot-server check`; this does not require a Prometheus server.
The startup Quadlets for migration, web, worker and scheduler therefore mount
`/prom_cache` as a separate 16 MiB tmpfs with `mode=1777,noexec,nosuid,nodev`.
Both environment-variable spellings explicitly select that path. PostgreSQL and
Redis are unaffected. Root filesystems remain read-only and service memory limits
remain unchanged; the tmpfs maximum is a cap, not a reservation.

The sticky directory permits application UID 999 to write with Podman's supported
tmpfs options. It is isolated per container, never a host/shared durable volume.
A new container gets an empty cache; processes within the same container share
it. No blanket host-directory cleanup is needed. This follows the client library's
[requirement to clear multiprocess files between runs](https://github.com/prometheus/client_python/blob/master/docs/content/multiprocess/_index.md).
This change does not enable metrics exposition, add a scraper or replace Munin.

Run the opt-in mount regression outside the filesystem sandbox against an existing
local image containing a POSIX shell, stat and dd:

```sh
NAUTOBOT_TMPFS_TEST_IMAGE=LOCAL_IMAGE PYTHONDONTWRITEBYTECODE=1 python3 Nautobot/tests/test_metrics_tmpfs.py
```

The test resolves the local image ID without pulling, consumes the rendered mount,
and verifies UID 999 writes, a read-only root, the size cap, and clean recreation.
It does not establish ARM64 Nautobot readiness; the separately approved target
startup must pass native configuration and all existing acceptance checks.

## Initialization and readiness evidence

Systemd `active/running` alone does not establish application readiness. Start
roles sequentially and require the native initialization receipt belonging to
that role's current systemd invocation before advancing. The receipt must show
all required commands completed successfully without truncated output. Web must
also pass loopback health and static-file checks before starting the worker.
A state or invocation change during the probe invalidates that sample.

Retain phase start/completion timings and the final readiness JSON per role,
including when the polling budget is exhausted. Exhaustion still stops progress
and enters cleanup; retaining diagnostics does not waive readiness. Existing
command deadlines, resource limits and outer cleanup guard remain in effect.
HTTP diagnostics retain status and bounded categories (connection refused,
timeout, transport error, redirect, body-size or content-type mismatch), never
response bodies, redirect destinations or exception text. Lifecycle evidence
retains the last readiness/HTTP response even when full acceptance was not reached.
Only separately authorized execution can validate this behavior on the ARM64 host.

## Explicit logging and server configuration

The target's retained preflight reports Podman 5.4.2; the integrity-checked local
Quadlet generator is pinned to the same version. Its
[version-specific reference](https://docs.podman.io/en/v5.4.2/markdown/podman-systemd.unit.5.html#logdriver)
supports `LogDriver=journald` in `[Container]`. All six container roles explicitly
select it, including initialization and migration-continuation variants. `[Service] StandardOutput=journal` alone does not select the container
log driver. Historical archives remain unchanged.

For startup application roles only, pass systemd's `INVOCATION_ID` through Podman's `--env=INVOCATION_ID` option;
never forward the entire host environment. Application phase/result records carry
that identity. Readiness and final acceptance select current-boot journal records
by container name and owning UID, then require exactly one successful receipt for
the current invocation. This excludes prior restarts and attached-output duplicates.
Recheck service state after collection. Log presence alone is not HTTP readiness.

Nautobot 3.2.3 delegates `start` to django-webserver 1.2.0. The retained implementation
adds strict/need-app/module/static arguments but no master flag. Explicit startup
arguments enable uWSGI master, Python threads, a single interpreter and SIGTERM
shutdown. Existing listener, memory limits and default process count are unchanged.
These match the relevant settings in the upstream service configuration guidance.

Two opt-in local regressions complement the normal offline suites:

```sh
NAUTOBOT_JOURNAL_TEST_IMAGE=EXISTING_LOCAL_IMAGE PYTHONDONTWRITEBYTECODE=1 python3 Nautobot/tests/test_startup_journal.py
NAUTOBOT_SERVER_TEST_PYTHON=/PATH/TO/ISOLATED_VENV/bin/python PYTHONDONTWRITEBYTECODE=1 python3 Nautobot/tests/test_startup_server.py
```

Run both outside the filesystem sandbox. The journal test requires local rootless
Podman and user systemd; it creates/removes one uniquely named service/container,
uses an existing image without pulls/network, and tests receipts across restarts.
The server test requires Django 5.2.17, django-webserver 1.2.0 and pyuwsgi
2.0.30.post1 in an isolated virtualenv. It uses real uWSGI with a minimal WSGI
application importing uwsgidecorators: missing master must fail; the corrected
command must serve HTTP and static content. It does not initialize a database or
run the full Nautobot application. Both tests clean up their temporary processes.
Local x86/runtime-version differences do not replace the separately approved
ARM64 trial and full application acceptance checks.

## Session identity timing and failure evidence

The session probe permits 60 seconds for each fresh Django identity check, using
a SIGALRM timer inside the container interpreter. This bounds the actual check
independently of SSH transport; node and controller waits are 70 and 75 seconds.
The session acceptance group permits 240 seconds, keeping all group deadlines
within the collector's 1200-second ceiling. The web application's configuration
and credential policy are unchanged.

Identity failure still attempts logout and revocation verification. Primary,
logout and tunnel-cleanup errors remain separate fixed codes. The collector
retains only allowlisted codes from nonzero probe results; acceptance remains
failed. Never retain cookies, credentials, HTML, stderr or exception messages.
A transport failure does not prove identity rejection or successful revocation.

## Worker heartbeat and resource-command diagnostics

The worker Quadlet explicitly sets
`NAUTOBOT_CELERY_HEALTH_PROBES_AS_FILES=true`. Nautobot's supported worker
liveness producer updates `/tmp/nautobot_celery_worker_heartbeat` every second;
the existing bounded writable `/tmp` holds it. The scheduler independently
updates `/tmp/nautobot_celery_beat_heartbeat` from its scheduler tick. The resource
probe requires both to be regular files with an age of at least zero and less
than 60 seconds. It does not skip an absent file or accept a symlink.

Resource command failures retain only a fixed command identity (`service_state`,
`container_inspect`, or `heartbeat`), role, category (`exit_status`, `timeout`,
`launch_error`, `output_limit`) and return code. Controller and collector retain
these fields on failed acceptance; raw stdout, stderr, inspect environment values
and exception messages are excluded. Heartbeat exit codes are:

| Code | Meaning |
| --- | --- |
| 70 | Missing file |
| 71 | Permission denied |
| 72 | File age at least 60 seconds |
| 73 | Future modification time |
| 74 | Not a regular file |
| 75 | Other filesystem error |

The optional `NAUTOBOT_SOURCE_WHEEL` test input points to the retained pinned
Nautobot wheel. `tests/test_application_startup.py` executes its exact worker
start/update/stop methods with a local timer harness, checks file creation and
removal, and runs the production freshness checker against the resulting file.
This validates the producer/consumer contract locally; the separately authorized
ARM64 startup trial remains the live acceptance gate.
