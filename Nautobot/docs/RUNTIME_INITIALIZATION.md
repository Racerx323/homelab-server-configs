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
