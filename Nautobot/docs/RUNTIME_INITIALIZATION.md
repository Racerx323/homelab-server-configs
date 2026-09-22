# Private runtime initialization

This procedure implements only PostgreSQL, Redis and the migration stage from
[the governing plan](NAUTOBOT_DEPLOYMENT_PLAN.md). The active operation binds the
accepted host, images, credentials, positive configuration readiness, repository
initialization and completed canary backup/integrity/restore archives. No new
negative authentication or SQLSTATE requirement is introduced.

## Scope and inputs

`run-runtime.py` verifies the strict initialization schema, all terminal records
against their annotated tags, accepted input hashes, clean source, six rendered
artifacts and the exact approved bundle. `deploy-runtime.yaml` installs only:

- the private network and PostgreSQL/Redis named volumes;
- PostgreSQL and Redis Quadlets, with 1536 MiB and 512 MiB ceilings;
- the one-shot migration Quadlet and a non-secret native-command helper.

The existing protected environment files and Redis Podman secret are reused.
No Doppler access, secret creation or rotation is needed. No web, worker,
scheduler, administrator bootstrap, TCP 8080 binding, Caddy publication, reboot
or Restic operation is included. Database and cache ports remain unpublished.

Before mutation, verify the canonical account, no prior runtime units/objects,
configuration ownership/mode/hash, environment consistency, exact local ARM64
image IDs, root filesystem `/dev/sda2`, at least 4 GiB available RAM and 4 GiB
free storage. Existing objects or partial initialization require review rather
than replacement. The evidence helper stages only non-secret files in a new
protected `/tmp/nautobot-runtime.*` directory. All host command modules explicitly
start in `/`; the node helper also changes to `/` before spawning children.
Changing identity with `runuser` alone does not change the inherited working
directory and can fail when the service account cannot traverse the SSH home.

## Native initialization and resource bounds

Start PostgreSQL and Redis using their health-gated units, then run these native
commands sequentially inside the pinned Nautobot image:

```text
nautobot-server check
nautobot-server post_upgrade
nautobot-server check
nautobot-server migrate --check
```

Stop immediately on nonzero status, timeout or excessive output. The pinned
3.2.3 `post_upgrade` source uses noninteractive migrations and static collection;
no self-authored password-rejection test is inserted. The helper records a safe
step name and exit status, never command output or credentials.

Migration uses the qualified application's 1536 MiB ceiling, zero additional
swap, a 900-second unit startup limit and an 840-second native-command budget.
The helper independently checks its cgroup memory/swap limits and non-root UID.
Its Jobs, Git and media startup paths use separate 16 MiB temporary filesystems;
static collection uses a 256 MiB temporary filesystem. These mounts do not cover
application dependencies or the read-only configuration. Static output is derived
and temporary; later web startup must regenerate or supply its own reviewed
static assets. No application files or Jobs are imported by this stage.

Native output is drained and discarded with a 4 MiB limit per stream. This does
not impose a file-size limit on collected static assets. The container emits only
its structured receipt. The postcondition helper reads that receipt from the
cursor-bounded user-unit journal; missing, duplicate or malformed receipts block
acceptance. Failed migration receipts are collected as well as successful ones.

## Acceptance and recovery

Require native-command success, no pending migrations, successful one-shot unit
state, healthy running PostgreSQL/Redis, exact images, durable volume mounts,
private networking and inspected effective memory limits. Recheck protected
configuration and environment consistency. Capture boot ID and journal cursor
before mutation; require the existing 75-second delayed storage review with
cursor availability, unchanged boot and no storage events.

On a task failure, attempt to stop each operation-owned service independently.
Retain volumes, installed units, helper and sanitized evidence. Do not delete
volumes, reverse migrations, downgrade images or automatically retry. The stage
record distinguishes unattempted steps from failures and records each stop
status. If transport/controller timeout interrupts execution, remote state is
unknown: inspect it read-only before proposing recovery. The outer controller
is bounded to 1800 seconds and never marks the runtime accepted automatically.

The controller retains `ansible-progress.jsonl` even before the first remote
evidence record. A bundle-bound aggregate callback records only approved static
task names, start/failure/unreachable/completion events and integer return codes
when `no_log` permits them. It never serializes result text, arguments, loop items,
host identities or exception messages. Unknown task names are replaced with a
fixed label. Capture is capped at 512 events and 128 KiB in a protected file.
The launcher reports incomplete diagnostics explicitly; a missing completion
event cannot produce a successful launcher result. Task failures may include
handled rescue events and must be interpreted alongside stage evidence.

Initialization success is not administrator login, application runtime,
reboot/logout persistence, full application restore or seven-day pilot acceptance.
No statement here authorizes those later stages.

## Local validation and execution

The test suite exercises the actual native-command helper, selected Quadlets with
the installed generator, strict receipt parser, private-service assertions,
wrong-hash/prerequisite rejection, real Ansible failure/independent-stop tasks,
command working-directory defaults, nested execution from an inaccessible
inherited directory, and secret-safe task diagnostics including `no_log` failures.
Target ARM64 execution, rootless user-systemd behavior, first database creation,
actual migration duration and storage health remain live acceptance checks.

```sh
python3 Nautobot/ansible/scripts/run-runtime.py show-hash
python3 Nautobot/ansible/scripts/run-runtime.py execute APPROVED_SHA256
```

Only the separately approved hash authorizes execution. Readiness fields describe
an eligible implementation; `approval_record` remains ungranted in the definition.

Sources: [Nautobot 3.2.3 post_upgrade](https://github.com/nautobot/nautobot/blob/v3.2.3/nautobot/core/management/commands/post_upgrade.py),
[Quadlet service types](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html).

## Recovery from partial initialization

A timeout after native work begins leaves potentially partially migrated data.
Do not run the first-install bundle again, remove named volumes, fake migrations
or infer database completeness from unit exit status or volume size.

Prepare recovery in two separately reviewed operations under this component:

1. **Preserve and inspect.** Verify the exact retained volumes, installed image
   and configuration identities, stopped units, absence of container writers,
   boot identity and free space. Make a protected cold copy of both named-volume
   trees before starting a database; preserve numeric ownership, modes, links
   and contents, reject unexpected mounts, and independently verify the copy.
   Keep this local recovery safeguard separate from Restic/application acceptance.
   Start only the existing private PostgreSQL unit with its pinned image and
   credentials. In a read-only SQL transaction with a statement timeout, inspect
   the database identity, server version and `django_migrations` relation.
   If present, retain only public app/migration identifiers and application
   timestamps; if absent, report that fact without creating the table.
   Compare applied migrations with the pinned application and installed Apps.
   Stop PostgreSQL in an always/finally path, verify no container writers remain,
   preserve both originals and cold copies, and complete a delayed storage review.
   Do not launch migration, Redis or application services in this operation.
2. **Continue with evidence.** Review the ledger and any inconsistent or
   non-atomic migration before selecting a continuation. Keep the same accepted
   images/configuration and all native post-upgrade semantics. Retain bounded,
   flushed phase identifiers, migration identifiers and elapsed times from an
   exact allowlist tied to the pinned source; discard other output. Record
   unknown progress explicitly, not as success. Recalculate a justified bounded
   duration; preserve memory/swap limits. Submit startup without holding one
   synchronous service command open, then poll a new systemd invocation with
   bounded commands, recording native progress and terminal status. A prior
   success/failed state is not evidence for the new invocation. On failure,
   attempt each owned stop independently and retain volumes and diagnostics.

The inspection SQL is scoped to metadata, for example:

```sql
BEGIN READ ONLY;
SET LOCAL statement_timeout = '10s';
SELECT current_database(), current_setting('server_version');
SELECT to_regclass('public.django_migrations');
-- Only if the relation exists:
SELECT app, name, applied FROM public.django_migrations ORDER BY applied, app, name;
COMMIT;
```

PostgreSQL startup can perform WAL recovery and writes even when later SQL is
read-only, so preservation/start/inspection requires its own exact-bundle approval.
Capture permission/ownership metadata privately without credentials or application
row contents. No automatic restoration of the cold copy is authorized: if startup
fails, stop, retain both trees and prepare a separate reviewed restoration.

Before freezing either operation, test actual execution paths for existing-volume
identity, preservation failure, absent migration ledger, secret-safe progress,
stale invocation state, delayed command failure, transport timeout and independent
failure stops. Archive the consumed definition and terminal result before replacing
the active operation. Keep the master plan's application, backup, restore and
pilot acceptance gates unchanged.

## Retained-database inspection bundle

The executable inspection path is `run-database-inspection.py` with
`inspect-retained-database.yaml`. It uses the existing six installed Quadlets and
pinned images; it does not reinstall runtime artifacts or bypass first-install
checks in the old launcher. The active strict inspection schema binds the
failed predecessor archive and all accepted prerequisites. Native migration and
Redis startup are excluded.

Cold copies are created once beneath the root-owned mode-0700
`/var/lib/nautobot/recovery/<operation-id>/` parent. Existing or partial copy
paths stop execution. Both volumes are copied in full with numeric ownership,
permissions, timestamps, internal symbolic links, hard links and extended
attributes preserved. The helper rejects external links, special files, nested
mounts, unexpected Podman volume paths and active container residue. Each tree
is limited to 100,000 entries and 2 GiB of apparent regular-file content; at least
4 GiB free is required. Independent source-before/source-after/destination
comparisons must pass before startup. Copies contain database data and remain
private on the host; they are never fetched into Git or controller logs.

An eight-minute root systemd timer requests PostgreSQL stop if the controller is
lost. Existing guard units block preservation. The timer must be active before
startup is submitted with `--no-block`. Readiness polling requires a different
invocation ID from the stopped predecessor, healthy private networking, correct
image, configured memory limit and expected named volume. Redis and migration
must remain stopped. No backend ports are published.

A local `psql -X -qAt` session uses the existing PostgreSQL Unix-socket access
policy as the container's postgres user and database role nautobot; no password
is placed in arguments or evidence. Authentication failure stops inspection
without modifying policy. A read-only transaction uses a 10-second statement
limit, 30-second client limit, 10,000-row ledger bound and 2 MiB output ceiling.
It returns database identity, numeric PostgreSQL version, read-only state,
ledger presence and migration identifiers/timestamps. A missing ledger is a
valid observed result, not permission to create it or accept initialization.
The subsequent review compares these identifiers with the pinned core/App
migration graph before selecting continuation.

The always path submits PostgreSQL stop, polls for stopped units and no remaining
containers, and disarms the timer only after stopped state is proven. It retains
cold copies and original volumes even on failure, then performs the 75-second
cursor-bounded storage review. Failed stop, transport loss, guard activation or
missing evidence requires read-only investigation; no automatic restoration or
retry is performed. The controller has a 20-minute outer bound. Node and
controller evidence remain under separate protected `/tmp/nautobot-inspection.*`
directories, with bounded static task events and sanitized status records.

```sh
python3 Nautobot/ansible/scripts/run-database-inspection.py show-hash
python3 Nautobot/ansible/scripts/run-database-inspection.py execute APPROVED_SHA256
```

Execution requires approval of that exact hash. Successful inspection is neither
successful migration nor application acceptance. Preservation failure cannot
start PostgreSQL; shutdown failure cannot be reported as successful inspection.
The filesystem-copy requirements follow
[PostgreSQL 17 filesystem backup guidance](https://www.postgresql.org/docs/17/backup-file.html).

## Prepared continuation of retained migrations

The continuation is implemented as an explicit branch of `run-runtime.py` and
`deploy-runtime.yaml`, with `continue-runtime-tasks.yaml` owning orchestration.
The strict `runtime-continuation.schema.json` binds the active candidate.
Preparation and tests are local; execution still requires its exact bundle approval.
Use the accepted inspection in [history](../HISTORY.md) and its tagged result as
the prerequisite; do not infer initialization acceptance from that result.

### Inputs and preservation

Bind the existing accepted image IDs, configuration, secret references, installed
unit hashes, named-volume paths and original boot identity. Retain the original
PostgreSQL and Redis volumes and the independently verified protected cold copies.
Before any startup, verify both services and migration are stopped, no container
writers exist, and the cold-copy content/metadata still match the inspection
record. Original PostgreSQL files can legitimately differ from the pre-start copy
after the inspection startup; do not require original/copy equality now.
Unexpected writers, changed identity, a missing copy or a changed copy stop work.
No fresh database, volume replacement, secret rotation or automatic restore.

### Native sequence and progress

Use the existing Ansible runtime path with an explicit continuation branch;
retain the first-install guard for first installations. Reuse the inspection's
bounded node-local stop guard and nonblocking startup/polling pattern. Do not
create a parallel attempt-numbered orchestration path.

1. Arm and verify an independent stop guard for migration, Redis and PostgreSQL.
   Start the two existing data services without blocking the controller for their
   full startup. Require new invocation identities, healthy private networking,
   accepted images, existing volumes and unchanged resource limits.
2. In the pinned application container, run native configuration checking and
   inspect the native forward migration plan before allowing mutation. Bind
   allowed app/migration names to pinned installed sources. Reject inconsistent
   history, backwards operations, unknown identifiers or unexpected graph changes.
   Compare with the recorded ledger; account for third-party and dynamic
   dependencies omitted by the earlier static file comparison. Review any
   pending non-atomic migration before freezing the bundle. A graph conflict
   stops this operation; it does not authorize faking or editing the ledger.
3. Run native `post_upgrade` with all existing semantics, followed by native
   configuration and pending-migration checks. Do not replace `post_upgrade`
   with only `migrate`, skip maintenance phases, or add negative-authentication
   tests. Preserve the configured installation-metrics behavior.
4. Stop migration, Redis and PostgreSQL independently, prove no container writers
   remain, disarm the guard only after stopped-state proof, and review at least
   75 seconds of cursor-bounded kernel/storage evidence with boot continuity.

The retained 3.2.3 source runs migrations, cache clearing, path tracing, static
collection, stale-content-type cleanup, session cleanup, configured installation
metrics, content-type-cache refresh and dynamic-group-cache refresh. Use this
pinned implementation to build phase identifiers rather than assuming current
online documentation exactly matches the image. The native entrypoint is also
documented in the [Nautobot command reference](https://docs.nautobot.com/projects/core/en/stable/user-guide/administration/tools/nautobot-server/).

Replace output-discard-only diagnostics with incremental, flushed, bounded events:
step start/end, exact known phase, allowlisted migration start/completion, elapsed
time and exit status. Set unbuffered child output and disable ANSI color. The pinned migrate command
truncates names to 50 characters; resolve only unique matches against the reviewed
plan, otherwise retain unknown progress. Preserve incomplete lines across
reads and test split tokens. Never retain arbitrary stdout/stderr, SQL, connection
strings, values, tracebacks or model-row details. Unknown output contributes only
byte counts; lack of a recognized event is explicitly unknown progress. Store
node-local evidence before fetching it so controller loss cannot erase progress.
Bind receipts to the new invocation and bundle; a prior receipt cannot pass.

### Bounds, acceptance and recovery

The prior 840-second budget was exhausted while migrations were still being
recorded. A proposed continuation envelope is 30 minutes for native commands,
a 35-minute independent stop guard, and a 40-minute controller envelope including
bounded shutdown and delayed observation. These are proposed ceilings, not a
prediction or permission to execute. Before freezing, inspect remaining pinned
migration operations and verify all deadlines fit these nested bounds. Keep the
1536 MiB migration memory ceiling, zero swap and existing data-service limits;
do not increase resource limits to hide a stalled operation. Poll in bounded
intervals and retain latest phase and elapsed time. Do not automatically extend
the deadline or retry on timeout.

Accept initialization only when all native steps succeed, no migrations remain,
expected private data-service identity/health and effective limits are proven,
shutdown and evidence completeness pass, and the delayed storage review is quiet.
Administrator bootstrap, web/worker/scheduler startup, published ports, Caddy,
reboot, application backup and workload acceptance remain separate stages.

On error, stop each owned service independently and preserve the progressed
original database plus unchanged cold copies. Report partial state and the last
known native progress. This is recovery containment, not transactional rollback
of already committed migrations. Restoring a copy requires a separate reviewed
operation and authorization; never delete, overwrite or automatically restore.

### Implementation and validation before approval

The continuation uses `migration-continuation.py` and `continuation-node.py`
together. The original `initialize-application.py` remains installed unchanged
for configuration rollback; the continuation replaces only the migration Quadlet
and adds its helper, source/ledger contract and bounded progress directory.
Bind the archived inspection result and preserved-copy hashes as prerequisites.
Exercise the real progress parser and producer with split lines, secret-bearing
unknown output, output saturation, child timeout and nonzero exit. Test native
plan conflicts, stale invocation/receipt rejection, changed-copy rejection,
controller loss, guard expiry, and a failed first stop with later independent
stops still attempted. Ensure first-install behavior still rejects existing data.
Render and validate the changed migration unit/helper; record their exact diff
and retain the old files for configuration rollback. Changing helper diagnostics
must not imply a new image or package upgrade.

Only after these checks pass, populate one active continuation operation and
freeze its exact SHA-256 bundle with target, command, timings, stop behavior and
acceptance boundaries. Execution requires approval of that concrete bundle.

### Candidate execution and residual files

The active candidate uses the 1800-second native, 1860-second migration-unit,
2100-second guard and 2400-second controller limits. It changes no image, package,
credential, memory ceiling, network or published port. Only the migration Quadlet
changes; the other five retained Quadlets remain byte-identical. Source hashes
for 493 retained migration modules and the 423-row ledger are bound in
`manifests/migration-continuation-inputs.json`. Django's actual loader checks
history consistency and its full forward plan on the host. The only explicit
non-atomic declaration found in those sources is the already-recorded Constance
migration; no pending non-atomic migration is approved.

Progress and receipt files are written under the existing protected runtime
parent in `continuation-evidence`, whose ownership is mapped through rootless
Podman to the pinned container UID 999. Files are mode 0600; the node validator
resolves the UID mapping and validates identities, sizes and allowed fields.
They remain locally on the host after shutdown, alongside the retained originals
and cold copies. They are not raw application logs. Missing or malformed evidence
cannot count as successful continuation.

Before unit replacement, its exact old file is copied to the protected node
operation directory. Configuration rollback requires stopped services, restoring
that verified unit, removing only proven operation-created helper/contract files,
and a user daemon reload. It does not undo applied database migrations and must
not be followed by rerunning the first-install launcher. No automatic database
restore, volume deletion or retry is implemented. Terminal review determines the
next action from the receipt, native progress, shutdown and storage records.
