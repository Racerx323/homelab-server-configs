# Administrator bootstrap and application startup preparation

The [deployment plan](NAUTOBOT_DEPLOYMENT_PLAN.md) owns the stage-5 architecture.
This specification prepares two sequential operations. It does not authorize host
contact, credential resolution, administrator creation, application startup or
network changes. Preserve the consumed operation until terminal publication is
verified; then keep the slot clean until the next implementation and exact bundle
are ready. Archive each completed operation before defining the next. The [roadmap](ROADMAP.md) and [history](../HISTORY.md) own current results.

## Next operation: administrator bootstrap

### Prerequisites and scope

Bind the accepted runtime-initialization result and published terminal archive,
accepted image-store and credential records, current configuration/unit hashes,
boot identity and retained volume identities. The initialized database is the
input; neither first installation nor the consumed continuation may be rerun.
Pre-data Restic initialization, canary backup and isolated restore are accepted;
they do not establish application recovery acceptance.

Use only the existing private PostgreSQL/Redis services and a disposable pinned
application container. Publish no ports. Start and stop through bounded Ansible
tasks with an independent stop guard and new-invocation checks. Preserve existing
1536 MiB PostgreSQL and 512 MiB Redis limits; use the qualified 1536 MiB/no-swap
application-check boundary. Provide bounded writable startup directories as in
the successful configuration and initialization trials. Do not start the retained
migration service as an implicit dependency of bootstrap.

Resolve `NAUTOBOT_INITIAL_ADMIN_PASSWORD` from Doppler project `homelab-dev`,
config `prd_nautobot` only during authorized execution. The approved username is
`admin`; the approved email is in the protected existing bootstrap input,
`/home/aaron/code/.local-evidence/nautobot-runtime-preparation-20260921/bootstrap-inputs.json`.
Use references only in Git and public review. Do not fetch or print credential
values during preparation. Never hash passwords into evidence.

### Native sequence

1. Verify stopped-state baseline, exact images/configuration, original volumes and
   retained recovery copies. Refuse unexpected containers, application services,
   bootstrap residue or drift. Record a kernel cursor before startup.
2. Start private data services under the guard and prove healthy new invocations.
   Perform native configuration and no-pending-migrations checks using the pinned
   application. No migration is authorized by this operation.
3. Use Nautobot's configured user model to check whether `admin` exists. Existing
   identity stops creation and requires review; never reset or promote it silently.
4. Run native `nautobot-server createsuperuser --noinput`. The pinned Django
   implementation accepts `DJANGO_SUPERUSER_USERNAME`, `DJANGO_SUPERUSER_EMAIL`
   and `DJANGO_SUPERUSER_PASSWORD`. Load these inside the disposable process from
   protected transient input; do not place values in command arguments, persistent
   container configuration or web/worker/scheduler environment files. The default
   image entrypoint must not run migrations or automatic user creation.
5. Verify the exact username/email privately, active/staff/superuser flags and
   successful authentication using the configured native backend. Record only
   booleans and the created non-secret user identity. Do not add SQLSTATE or other
   negative-authentication tests as new readiness prerequisites.
6. Independently stop/remove the disposable bootstrap container, stop the data
   services, remove each transient credential input and verify removal even if a
   preceding cleanup fails. Preserve sanitized records first. Prove no container
   writers remain, disarm the guard, and review at least 75 seconds of delayed
   cursor-bounded storage evidence with boot continuity.

The native command is documented in the
[Nautobot installation guide](https://docs.nautobot.com/projects/core/en/stable/user-guide/administration/installation/nautobot/).
Its noninteractive environment handling was checked against the retained pinned
image's Django command source; it must also be exercised by implementation tests.
Native account authentication is not yet proof of browser login or logout.

### Bounds, failure and acceptance

Propose a 120-second ceiling for each native check/creation command, a 15-minute
independent guard and a 20-minute controller envelope including cleanup/storage
review. These are proposed execution limits; confirm the actual task budget and
failure tests before freezing. Reuse the existing thin bundle launcher and
Ansible lifecycle instead of another attempt-specific transaction framework.

Accept only after successful native creation, exact account/flags verification,
positive authentication, unchanged persistent-service credential scope, complete
transient-secret cleanup, service shutdown and quiet storage review. On failure,
stop services and retain the database. Account creation may already be committed;
report whether creation was attempted and what is proven. Do not automatically
delete an account, restore the old pre-migration cold copy or retry creation.
Cleanup failure is an acceptance failure even if the administrator exists.

Before execution approval, implement a strict bootstrap contract and tests for
existing users, creation failure, success followed by verification failure,
secret-safe output, independent cleanup failures, lost controller/guard expiry,
stale invocations and first-install exclusion. Exercise the actual native command
and secret handoff with a disposable fixture when available; distinguish local
fixtures from pinned ARM64 execution. Bind all non-secret inputs and the published
initialization prerequisite into the exact bundle.

## Following operation: application startup

Administrator bootstrap must first pass and be archived. The current full runtime
render is a review candidate, not a deployable bundle. Resolve these concrete
implementation gaps before opening any application listener:

| Area | Existing candidate | Required startup preparation |
| --- | --- | --- |
| Migration dependency | Web/worker/scheduler require the migration service; the installed unit is the consumed continuation | Replace it with a reviewed repeatable native `post_upgrade` unit; never reuse the continuation's one-use ledger/receipt contract. Preserve native checks, resource limits and progress. |
| Static/startup directories | Writable Git/Jobs/static tmpfs exists only in the initialization render | Supply writable runtime paths and regenerate static assets for the serving container. Initialization's temporary static files are gone. Verify real CSS/JS responses. |
| Media | Only web mounts the desired-state media volume | Reconcile the shared-media requirement for web and task consumers, numeric ownership and backup inclusion. Do not introduce unreviewed durable volumes. |
| Recovery access | Renderer permits only the LAN IPv4 and permanent ULA backend binds | Add the plan-permitted `127.0.0.1:8080` recovery bind and matching renderer/schema tests for an SSH tunnel; no wildcard bind. |
| Backend policy | Baseline LAN management acceptance is broader than the application policy | Verify and, through its owner, implement TCP 8080 access only from the exact pihole0/pihole00 IPv4/ULA sources plus local recovery. Same-subnet access must be covered, not merely routed UniFi traffic. |
| Lifecycle | Units use `WantedBy=default.target`, and Beat is configured with Nautobot's database scheduler | Qualify a single worker (concurrency 2), one scheduler, dependencies, writable process paths, logout and separately authorized reboot persistence. |

Use current inventory references for both proxy nodes; do not infer IPv6 addresses
from their IPv4 addresses. Network/firewall changes require the owning component's
reviewed operation. An unavailable external IPv6 vantage remains a stated limit;
it does not substitute for allowed/disallowed internal IPv6 backend tests.

Prepare the runtime unit diff against the accepted installed set. Preserve the
existing PostgreSQL/Redis volumes, configuration and credentials; introduce only
reviewed runtime artifacts and the existing desired media volume. Verify the
initial-admin credential is absent from persistent environments and secrets.
The backend must remain unavailable until the restrictive policy is effective.

Start the data services, then the repeatable native migration prerequisite, then
web, worker and scheduler sequentially; stop progression on the first failure.
Do not accidentally retry a failed migration by starting another dependent unit.
Acceptance includes `/health/` HTTP 200, static assets, SSH-tunnel login/logout,
correct CSRF/host behavior, one worker/Beat instance, completed representative
Job, queue/cache authentication, effective limits and headroom, exact listeners,
and permitted/rejected IPv4/IPv6 access. Preserve boot/storage continuity and
bounded observation. No Caddy route or DNS publication is included.

On failure, stop newly activated application units independently, preserve data
and diagnostics, and restore only reviewed prior configuration where safe.
Database writes are not reversed by restoring a Quadlet. Do not prune volumes or
restore the pre-migration cold copy automatically. The startup bundle must state
which services remain running on success and stopped on failure.

## Remaining stage-5 gates

Browser authentication, application startup, logout/reboot persistence, monitoring,
representative workload/headroom checks, application-aware backup, full integrity
check, isolated application restore and the seven-day stable pilot remain separate
acceptance evidence. Caddy publication is stage 6. Authority migration and
Semaphore remain later stages. The initialized database and pre-data canary do not
clear these gates.
