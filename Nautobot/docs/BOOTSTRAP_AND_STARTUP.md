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
   Use `nautobot-server shell --interface python --command CODE` for account
   checks. The outer Nautobot CLI reserves `-c` for `--config-path`; the short
   option must not be used for Django shell code. Regression fixtures preserve
   the pinned outer parser and verify that both account expressions reach Django.
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

The implementation bounds each native check/creation command to 120 seconds,
the disposable container to 660 seconds, the independent guard to 15 minutes and
the controller to 20 minutes including cleanup/storage review. Five sequential
native commands fit within the 630-second probe wait. Startup and shutdown each
have a bounded readiness wait; guard activation fails acceptance. Reuse the existing thin bundle launcher and
Ansible lifecycle instead of another attempt-specific transaction framework.

Accept only after successful native creation, exact account/flags verification,
positive authentication, unchanged persistent-service credential scope, complete
transient-secret cleanup, service shutdown and quiet storage review. On failure,
stop services and retain the database. Account creation may already be committed;
report whether creation was attempted and what is proven. Do not automatically
delete an account, restore the old pre-migration cold copy or retry creation.
Cleanup failure is an acceptance failure even if the administrator exists.

The strict bootstrap contract and offline suite cover
existing users, creation failure, success followed by verification failure,
secret-safe output, independent cleanup failures, lost controller/guard expiry,
stale invocations and first-install exclusion. A disposable SQLite fixture exercised native creation
and authentication with the pinned Django source; it does not establish ARM64
Nautobot execution. All non-secret inputs and the published initialization
prerequisite are bound into the exact bundle.

### Execution entrypoint and evidence

`ansible/scripts/run-runtime.py` selects `bootstrap-administrator.yaml` only for
`administrator_bootstrap`; the initialization playbook remains separate. The
bootstrap schema fixes the target, accepted prerequisites, unit/image identities,
credential reference, time bounds and exclusions. The approved username/email
file is bound by hash in the private bundle and rechecked before credential
resolution; its contents and hash remain outside Git. Preparation may calculate a
bundle from reviewed working files; execution additionally requires a clean Git
source tree and the exact approved hash before any credential or host access.

```bash
python3 Nautobot/ansible/scripts/run-runtime.py show-hash
python3 Nautobot/ansible/scripts/run-runtime.py execute APPROVED_SHA256
```

Execution resolves only the initial-admin password. Controller input uses a
protected `/dev/shm/nautobot-bootstrap.*` directory; target input uses
`/run/user/999/nautobot-bootstrap`. The password enters only the native creation
child's environment, never Podman's configured environment or command arguments.
The controller launcher removes its input even when Ansible fails; the target's
independent guard shares the normal cleanup path. If the controller is killed
without running its finalizer, review/remove its recorded tmpfs directory before
retrying. Never publish or hash that input.

Receipts name configuration, pending migrations, account absence, creation and
account verification independently. Child output is discarded. Private evidence
includes preflight, native receipt, cleanup/service/guard statuses and the delayed
storage review. A completed command does not establish acceptance until shutdown,
credential removal, identity continuity and storage checks pass. The existing
pre-migration cold copies remain historical recovery inputs, not an automatic
rollback for the newly initialized database or administrator account.

## Following operation: application startup

Administrator bootstrap must first pass and be archived. The current full runtime
render is a review candidate, not a deployable bundle. Resolve these concrete
implementation gaps before opening any application listener:

| Area | Existing candidate | Required startup preparation |
| --- | --- | --- |
| Migration dependency | Candidate uses a repeatable native wrapper, with configuration and no-pending checks around `post_upgrade` | Qualify the replacement against the initialized database; never reuse continuation ledger/token inputs. |
| Static/startup directories | Candidate supplies bounded writable tmpfs; web collects static assets before executing the server | Verify real CSS/JS responses from the web container. |
| Media | Candidate mounts the planned media volume in migration, web, worker and scheduler; Quadlet declares container UID/GID 999 ownership | Verify effective rootless ownership and include media in application backup. |
| Recovery access | Candidate renders the plan-permitted `127.0.0.1:8080` bind alongside exact IPv4/ULA host binds | Verify SSH-tunnel login/logout and retain no wildcard bind. |
| Backend policy | Machine-readable owner handoff is prepared; no policy has been deployed | Obtain exact source/interface evidence and allowed/denied tests before listeners open. |
| Lifecycle | Candidate starts services serially, checks fresh invocations and includes an independent stop guard | Complete activation and live acceptance evidence; logout/reboot and pilot remain separate. |

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

### Implemented candidate and activation boundary

`manifests/startup-policy.yaml` and its strict schema deliberately require
`execution_authorized: false`. The active operation is clean. Neither the existing
runtime launcher nor this policy authorizes application startup. Do not set an
Ansible extra variable to bypass this boundary.

The candidate implementation consists of:

- `startup-application.py`: resource/UID checks, native configuration and migration
  checks, repeatable `post_upgrade` only for the migration role, web-local
  `collectstatic`, then native web/worker/Beat execution. It never creates an admin.
- Runtime renderer/templates: bounded application memory and zero swap, read-only
  application roots, capped writable directories, shared media and loopback bind.
  Existing PostgreSQL/Redis units remain byte-identical to the accepted archive.
- `start-application.yaml` and `start-service-tasks.yaml`: blocked pre-contact gate,
  reviewed artifact checks/copies with backups, user daemon reload, ordered starts,
  new-invocation checks, local HTTP/static checks, and independent stop-on-failure.
- `startup-node.py`: strict service-state checks, bounded loopback HTTP probes and
  stop attempts that continue after an earlier stop or inspection fails.
- `prepare-startup.py`: offline rendering tied to the accepted bootstrap archive,
  with exact before/after hashes against installed artifacts. It refuses an active
  operation and an existing output directory.

Prepare a fresh review directory locally:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 Nautobot/ansible/scripts/prepare-startup.py \
  --output /tmp/nautobot-startup-review
```

The review is not a deployment bundle. Before activation, the exact-bundle launcher
must supply and verify fresh stopped-state/identity evidence, staged helper hashes,
artifact destinations, the guard identity and protected evidence directories.
The candidate expects those reviewed inputs; it does not manufacture them.
Browser authentication, allowed/denied network probes, representative Job, resource
and storage acceptance still require their live evidence collector and reviewed
contract. The candidate refuses successful completion without that acceptance.
These are explicit remaining activation work, not evidence already obtained.

Native migration commands have 120/1800/120-second bounds, with a 2160-second
systemd start bound; application startup is bounded to 480 seconds per service.
Ansible readiness uses 5-second delays (444 attempts for migration, 108 otherwise).
The candidate guard is two hours to cover serial startup, evidence and cleanup.
Review final aggregate deadlines before activation; the guard is a failure stop,
not the pilot observation window. Migration remains `Restart=no`.

Offline tests exercise actual Ansible failure progression and the inactive gate,
native command ordering/failure, independent cleanup, schema boundaries, rendering
against archived units, and the pinned Quadlet generator. They do not prove live
rootless ownership, boot persistence, browser login or deployed firewall policy.

The pinned Nautobot 3.2.3 source delegates `start` to `django_webserver`'s uWSGI
command, which maps `STATIC_ROOT`; this is why web must collect assets in its own
container. General references: [Nautobot installation](https://docs.nautobot.com/projects/core/en/stable/user-guide/administration/installation/nautobot/)
and [Quadlet volume ownership](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html).

### Concrete preparation sequence

This is repository preparation, not an executable startup operation. Keep the
consumed bootstrap definition until its annotated terminal tag is published and
verified. Then reconcile history and return `operation.yaml` to clean; define a
startup operation only when its implementation and owner prerequisites are ready.

1. Bind the accepted bootstrap result, initialized database, loaded image,
   credential/configuration records and existing stopped-volume identities. Do
   not run administrator bootstrap or first-install deployment again.
2. Update `manifests/desired-state.yaml`, its schema and
   `ansible/scripts/validate-contracts.py` together for shared media consumers,
   the explicit recovery bind and bounded migration resources. Keep the accepted
   service memory ceilings and worker concurrency unchanged.
3. Update `ansible/templates/runtime/container.j2` and
   `ansible/scripts/render-runtime.py`. Render a normal repeatable migration unit
   without continuation token, ledger fixture or initialization helper. Confirm
   writable Git/Jobs/static/process paths from the pinned image; ensure static
   files exist in the actual web container, not only the completed migration
   container. Use the already-planned media volume for approved consumers and
   verify ownership as seen inside each rootless container.
4. Add a separate startup stage contract and Ansible path. The current
   `deploy-runtime.yaml` accepts initialization/continuation only; neither stage
   is an application-startup interface. The thin launcher must reject startup
   until its schema, prerequisites, exact bundle and authorization agree.
5. Prepare the network-owner handoff below and obtain deployed-policy evidence
   before any listener opens. A repository policy declaration is insufficient.
6. Render and compare with the accepted installed artifacts; validate with the
   pinned Quadlet parser. Cover secret exclusion, unintended binds, missing
   media/static paths, migration failure preventing dependents, independent
   service stops, stale invocation evidence and partial installation in focused
   tests. Wire the tests into the existing validation entrypoint and pre-commit.
7. Assemble one reviewable startup bundle with exact artifacts, configuration
   backups/hashes, target, ordered service actions, deadlines, acceptance and
   recovery. No credential lookup or live probe is part of this preparation.

### Network-owner handoff

The machine-readable proposal is `manifests/startup-network-handoff.yaml`.
The repository source is `Caddy/manifests/deployment.yaml` (relative to the
repository root); inventory links the logical proxy names to their management
FQDNs. Its current declarations are:

| Permitted source | IPv4 | Permanent ULA |
| --- | --- | --- |
| pihole0 | 10.1.0.53 | fd36:5aa8:6971:1::53 |
| pihole00 | 10.1.0.54 | fd36:5aa8:6971:1::54 |

These are repository declarations, not newly verified live source addresses.
The Caddy service VIP is not a substitute for proof of the proxies' egress source.
Recheck the owning source and actual route/source selection in the separately
reviewed network operation. Destination is Nautobot TCP 8080 at the two approved
host addresses; local recovery uses `127.0.0.1:8080` through SSH. No wildcard bind,
new DNS publication or Caddy route is included.

`homelab-network` owns the policy. Its [prepared design](../../../homelab-network/Ubiquiti/nautobot-backend-network-design.md)
proposes destination-specific permanent-source routes and a target pre-NAT guard.
The [candidate implementation](../../../homelab-network/host-network/nautobot/README.md)
provides persistence and rollback. Disposable-listener packet qualification is
accepted for the current HA ownership; see the owner result linked below. Web startup
requires the fixed root-owned rule verifier through ExecStartPre. Require enforcement that covers
same-subnet traffic as well as routed traffic, with rollback preserving SSH and
existing monitoring. Do not assume the UniFi gateway sees direct LAN traffic.
The resulting evidence must show installed rules, interface coverage and both
address families. Test allowed access from each proxy and denied access from a
reviewed non-proxy LAN source. Record unavailable vantage points explicitly;
do not manufacture a pass or broaden the backend allowlist to the whole LAN.

### Proposed startup acceptance and recovery contract

Before mutation, require the accepted archives, fresh identity/drift checks,
verified restrictive policy, no unexpected application containers/listeners and
protected copies of every file to be replaced. Preserve existing database/cache
volumes and credentials. Review the need for a fresh application-consistent
recovery capture before repeatable `post_upgrade`: historical pre-migration cold
copies cannot restore the current initialized database and administrator account.
Any backup operation remains under the Restic owner's separate reviewed stage.

Start PostgreSQL/Redis, prove new healthy invocations, run the repeatable migration
prerequisite once, then web, worker and scheduler. A migration failure stops
progression without implicit retries through dependent unit starts. Use bounded
waits and independent cleanup with sanitized phase diagnostics. Select numerical
deadlines and the initial observation duration from reviewed image/startup behavior
when freezing the implementation; these are not yet defined by this document.

The initial startup acceptance must include native no-pending-migration checks,
HTTP `/health/` 200, real CSS/JS delivery, exact listener addresses, permitted and
rejected backend access for both families, SSH-tunnel administrator login/logout,
CSRF/host behavior, authenticated cache/broker connectivity, one worker with
concurrency 2, one Beat scheduler, a completed representative Job, and effective
resource limits. Define the representative Job and its harmless inputs before
execution. Verify secret absence from persistent environments and evidence.

Proposed successful terminal state: all six intended runtime services have their
reviewed systemd state (migration completed successfully; other services running),
with no temporary probe or credential residue. On failure, independently stop
new application services and data services, preserve the database/media, retain
diagnostics and restore only reviewed configuration backups when safe. Do not
claim data rollback from a file restoration. Prove stopped-state or report manual
intervention if a stop fails. Never delete volumes or the administrator account.

Logout persistence can be checked within the startup operation if included in
its frozen contract. Reboot, extended observation, application backup/restore,
Caddy publication and the seven-day pilot remain separate reviewed stages.

## Remaining stage-5 gates

Browser authentication, application startup, logout/reboot persistence, monitoring,
representative workload/headroom checks, application-aware backup, full integrity
check, isolated application restore and the seven-day stable pilot remain separate
acceptance evidence. Caddy publication is stage 6. Authority migration and
Semaphore remain later stages. The initialized database and pre-data canary do not
clear these gates.

## Startup preparation after backend packet qualification

The network owner's [accepted packet result](../../../homelab-network/host-network/nautobot/packet-result.json)
proves access from both proxies over both families, denial from the reviewed
non-proxy source with counter increments, and retained loopback recovery access.
It also proves probe cleanup and unchanged guard configuration. This is evidence
for the disposable listener, not actual application or Caddy acceptance.
The published, remotely verified annotated archive is `nautobot-packet-qualification-accepted`, commit
`48954d2`. The handoff and network history record the verified publication.

Offline startup rendering preserves the PostgreSQL and Redis Quadlets, their
volumes and the private network. It adds the shared media volume, web, worker and
scheduler; the migration Quadlet changes to the repeatable native startup path.
The exact before/after hashes are generated by `prepare-startup.py`, rather than
copied into this procedure. Its generic network blocker remains a requirement
for fresh deployed-policy verification; it does not negate accepted packet evidence.

The next preparation work is bounded to the existing startup playbook:

1. Use the exact-bundle launcher and bounded acceptance collector described in
   [startup preflight and recovery](STARTUP_PREFLIGHT_AND_RECOVERY.md). The playbook
   now stages and verifies stop helpers and invokes collection instead of trusting
   a supplied acceptance boolean. Concrete session, network and Job probes are now implemented. Bind their
   reviewed inputs and collected receipts before activation; local tests alone
   are not live acceptance.
2. Prepare a fresh read-only preflight for host/boot identity, accepted image and
   credential object identities (no values), stopped services, installed artifact
   hashes, current volume identities, free capacity, guard rules and source routes.
   Compare with the accepted bootstrap and network archives. Host contact requires
   scoped authorization; this preparation performs none.
3. Establish a recovery point for the current initialized database and administrator
   before repeating `post_upgrade`. Prefer a separately reviewed stopped-volume
   preservation operation while all services remain stopped, with explicit hashes,
   capacity and recovery instructions. The old pre-migration copies and pre-data
   Restic canary do not provide this recovery point. Application-aware Restic backup
   and restore qualification still follow under their owner.
4. Define the harmless representative Job and exact inputs, then collect the
   application checks listed above through the actual service and guarded addresses.
   Keep Caddy publication, reboot and extended observation outside startup.
5. Freeze the reviewed inputs, deadlines, acceptance and failure actions together;
   request execution approval for that exact bundle only after local validation.

The active operation remains clean and startup policy remains unauthorized.
Preparation or archive publication does not start the application.
