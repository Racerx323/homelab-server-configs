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
protected `/tmp/nautobot-runtime.*` directory.

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

Initialization success is not administrator login, application runtime,
reboot/logout persistence, full application restore or seven-day pilot acceptance.
No statement here authorizes those later stages.

## Local validation and execution

The test suite exercises the actual native-command helper, selected Quadlets with
the installed generator, strict receipt parser, private-service assertions,
wrong-hash/prerequisite rejection and real Ansible failure/independent-stop tasks.
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
