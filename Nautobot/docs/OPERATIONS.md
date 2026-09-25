# Nautobot operator procedures

The [deployment plan](NAUTOBOT_DEPLOYMENT_PLAN.md) owns architecture and the
[roadmap](ROADMAP.md) owns progress and stage readiness. These procedures do not
authorize execution. This manual owns reusable execution and recovery procedures. Current deployment
status belongs only in the roadmap and manifests; terminal results belong in HISTORY.
A procedure does not activate an archived operation. New bundles must bind this
manual and current code; historical bundles and terminal tags remain unchanged.

## Record interpretation and validation limits

`operation.yaml` is the only active operation slot. A policy enabling an
implementation is not authorization and a retained preparation document is not
a second operation. Read accepted records by stage and observation date:

- `accepted-live-state.yaml` retains stage-3 boundaries and stage-specific acceptance;
  the newer synthetic-workload section does not retroactively rewrite older receipts.
- `deferred-restic-initialization.yaml` is an inactive historical template. Its old
  repository-absence and implementation fields must not be read as current state.
  Its old document paths, and matching legacy schema constants, resolve at the
  pre-consolidation snapshot indexed in HISTORY. The preservation regression
  requires its exact original bytes; new bundles use this manual.
- Image/authentication failure records are retained diagnostic provenance, not
  blockers after a separately accepted successor. The terminal tags in HISTORY
  establish their order. Keep them until a separately reviewed archive cleanup
  proves every dependent reference and original byte identity.
- `startup-preservation-result.json` is a verified-copy receipt, not proof of a
  current or exercised application restore.

Offline CI covers schemas, bundle references, renderers and failure-path contracts.
The native uWSGI test (`test_startup_server.py`), bounded metrics tmpfs test
(`test_metrics_tmpfs.py`) and journal test (`test_startup_journal.py`) are explicit
local-runtime qualifications. They require their documented opt-in environment
inputs and are not counted as passing live checks merely because CI passed.
Likewise, disposable workload scripts require separate local container execution;
CI does not establish ARM64 performance, reboot survival or successful restore.

For long operations, use the [controller supervision procedure](#workload-controller-supervision).
A manager exit receipt is not remote acceptance. Controller restart never grants
permission to replay a workload; retain node evidence and review cleanup first.

## Procedure index

- [Retained host-baseline convergence and acceptance](#retained-host-baseline-convergence-and-acceptance)
- [Raspberry Pi memory-controller correction](#raspberry-pi-memory-controller-correction)
- [Reviewed baseline package cleanup](#reviewed-baseline-package-cleanup)
- [Nautobot storage-remediation decision](#nautobot-storage-remediation-decision)
- [Bounded ARM64 image qualification](#bounded-arm64-image-qualification)
- [Application credential preparation](#application-credential-preparation)
- [Credential provisioning and injection operation](#credential-provisioning-and-injection-operation)
- [Image loading and application configuration qualification](#image-loading-and-application-configuration-qualification)
- [Disposable configuration and authentication qualification](#disposable-configuration-and-authentication-qualification)
- [Isolated pre-data backup and restore verification](#isolated-pre-data-backup-and-restore-verification)
- [Canary backup and full integrity check](#canary-backup-and-full-integrity-check)
- [Isolated canary restore](#isolated-canary-restore)
- [Private runtime initialization](#private-runtime-initialization)
- [Administrator bootstrap and application startup preparation](#administrator-bootstrap-and-application-startup-preparation)
- [Startup baseline and recovery preparation](#startup-baseline-and-recovery-preparation)
- [Startup database preservation](#startup-database-preservation)
- [Application startup execution](#application-startup-execution)

## Runtime preparation

The local renderer is `ansible/scripts/render-runtime.py`. It reads the existing
schema-validated desired state and requires a JSON file containing only:

- `custom_image`: the reviewed immutable ARM64 custom-image reference, including
  its SHA-256 digest; and
- `recovery_host`: the approved recovery DNS name or IPv4 address.

Use `manifests/runtime-inputs.json` for the prepared qualified image and recovery
identity. The CLI verifies these against `manifests/qualified-image.json`, its
annotated terminal archive and accepted host identity. Local rendering does not
prove that the archive has been loaded into the runtime account's default store.
See [credential preparation](OPERATIONS.md#application-credential-preparation) for the selected Doppler
references and protected bootstrap boundary.

Do not invent a production digest or treat a test fixture as a deployable image.
Rendering creates a new output directory and refuses an existing destination:

```bash
python3 Nautobot/ansible/scripts/render-runtime.py \
  --inputs /PROTECTED/REVIEWED/runtime-inputs.json \
  --output /NEW/REVIEWED/runtime-render
```

Output includes six containers, one network, three volumes, a non-secret
configuration contract and artifact hashes. The renderer does not resolve secrets,
pull/build images, create containers, or contact the target. The network is a
private application bridge with no database/cache publication; it is not an
`Internal=true` egress restriction. Jobs and backups need reviewed outbound
connectivity. No change to owner firewall policy is implicit.

Database and Redis health checks gate migration through `Notify=healthy`.
Applications require the successful one-shot migration. Startup commands execute
sequentially and stop at the first failure; a loop must not retry migration
indirectly by starting more dependent services after failure. `Pull=never` requires
all reviewed images to be provisioned separately. Container memory limits come
from desired state; effective target cgroups still require verification.

Nautobot units explicitly replace the inherited image entrypoint with
`nautobot-server`, so the image's default entrypoint cannot independently run
migrations. Validate executable resolution, configuration loading and service
commands against the actual pinned custom image before pilot readiness. Local template validation alone does not establish ARM64 runtime behavior.

## Protected configuration contract

Provision these inputs through a separately reviewed secret/configuration stage,
not by copying fixture values or putting credentials in a bundle:

| Input beneath `/var/lib/nautobot/runtime/` | Contract |
| --- | --- |
| `postgresql.env` | Mode 0600, nautobot owner; approved database password. User/database are `nautobot`. |
| `redis.env` | Mode 0600, nautobot owner; `REDISCLI_AUTH` matches the Redis configuration secret. |
| `migration.env`, `web.env`, `worker.env`, `scheduler.env` | Mode 0600, nautobot owner; only the reviewed variables needed by each service. No initial-admin credentials distributed to persistent services. |
| `nautobot_config.py` | Non-secret, mode 0644 and nautobot owner, under a protected parent; readable by the container user. Exact configuration hash is reviewed. Secret values are read from approved injected inputs. |

The named Podman secret `nautobot-redis-config` supplies Redis authentication,
`appendonly yes`, `appendfsync everysec`, `maxmemory 384mb` and
`maxmemory-policy noeviction`. Its mount uses UID/GID 999 and mode 0400; verify
the pinned Redis image identity and access before readiness. The Redis password
is never supplied as a command-line argument. Matching health credentials,
configuration syntax and policy must be checked without printing secret values.

The application configuration must use network aliases `postgresql` and `redis`,
approved database/cache credentials, DNS Models activation, shared media path,
ALLOWED_HOSTS including the reviewed recovery identity, the intended CSRF origin,
secure proxy header and production settings. The generated
`configuration-contract.json` is a review input, not an application settings file.
The pinned-image configuration/API check remains required; rendering alone cannot
prove that an injected settings file is correct.

## Application startup candidate

Use `ansible/scripts/prepare-startup.py --output NEW_PRIVATE_DIRECTORY` to render
and compare startup artifacts with the accepted bootstrap archive. See
[bootstrap/startup preparation](OPERATIONS.md#administrator-bootstrap-and-application-startup-preparation) for implementation,
the separate bootstrap and network-owner boundaries. The startup policy is a definition; only the dedicated startup launcher and
exact authorized operation can execute it. Do not use
initialization or bootstrap as a substitute startup command.

## Runtime deployment boundary

`ansible/playbooks/deploy-runtime.yaml` and `ansible/scripts/run-runtime.py` now
implement only the [private initialization stage](OPERATIONS.md#private-runtime-initialization):
PostgreSQL, Redis and migration. The active strict contract binds terminal
prerequisite records and exact rendered artifacts. It requires separate approval
of the final bundle hash before any target command. Do not bypass that gate with
manually asserted Ansible variables.

The path verifies current identities and first-install absence, starts only the
selected services, performs native migration checks and preserves sanitized
stage and journal evidence. It excludes web, worker, scheduler, administrator
bootstrap and host-published ports. Full application startup uses a separate operation with its own exposure and recovery criteria.
[Administrator bootstrap and application startup](OPERATIONS.md#administrator-bootstrap-and-application-startup-preparation)
specifies the native account-creation path, transient credential cleanup, runtime
filesystem and migration-unit changes, and required backend access controls.

The first-install path is not an upgrade or resumable migration procedure.
After failure it attempts independent stops of operation-owned units and retains
volumes and evidence. Inspect partial state before another operation; never
reverse migrations, downgrade images or delete volumes automatically. A missing
receipt or interrupted transport leaves acceptance unresolved. Reboot/logout
persistence and application recovery remain separately reviewed.

## Local validation

Use a Podman 5.4.2 Quadlet generator matching the target. The workstation's 4.9.3
generator rejects the newer `NetworkAlias` key and is insufficient. An official
5.4.2 generator built under `/tmp` can validate without invoking the container
engine or pulling images. Set its path explicitly:

```bash
python3 Nautobot/tests/quadlet_tool.py --prepare
PYTHONDONTWRITEBYTECODE=1 python3 Nautobot/tests/test_runtime.py
/bin/bash tests/repository/run-with-ansible-local-temp.sh \
  ansible-playbook --syntax-check --inventory inventory/prod/hosts.yaml \
  Nautobot/ansible/playbooks/deploy-runtime.yaml
```

Tests use synthetic immutable image references for parsing only. Run the generator
and the localhost Ansible fixture outside the filesystem sandbox if runtime/socket
access is restricted. They do not start containers. Local passing results do not
prove ARM64 image behavior, rootless target networking, secret access, application
startup or logout/reboot survival. Those remain live-stage acceptance checks.

## Source references

- [Podman 5.4.2 Quadlet reference](https://github.com/containers/podman/blob/v5.4.2/docs/source/markdown/podman-systemd.unit.5.md)
- [Nautobot service commands](https://github.com/nautobot/nautobot/blob/develop/nautobot/docs/user-guide/administration/installation/services.md)

The Nautobot reference is current upstream documentation, not execution evidence
for the pinned image; verify the image-specific contract before deployment.

### Candidate contract validation

Run `python3 Nautobot/tests/run-validation.py` from the repository root. This runs
all Nautobot schema/launcher hooks, cross-artifact checks, boot/package regressions,
runtime rendering and localhost assertions, and Restic failure-injection tests.
Prepare it once per checkout with `python3 Nautobot/tests/quadlet_tool.py --prepare`
(Python 3.12+, Go and network access required). This verifies the pinned Podman 5.4.2
archive checksum and builds only the parser using vendored dependencies. The parser
and its integrity receipt live under `.git/nautobot-tools/`, outside tracked files.
An existing archive can be supplied with `--archive`; the same checksum is required.
Hooks and CI use this same helper and verify the cached binary before execution.
Hooks never download tools, fall back to the workstation parser, or skip validation.
Missing or modified caches produce the exact preparation command. No environment
variable override is required; CI prepares a fresh cache before validation.

The renderer rejects mismatched manifest/image digests, secret mappings, and build
inputs. The workload manifest is schema-validated and drives fixture cardinality;
schema validation alone does not qualify the implemented Jobs, sampler or live workload. Any contract
change must keep the manifest, schema, implementation and negative tests aligned.

Runtime first-install preflight rejects existing Nautobot container, network or
volume metadata, including residue left after unit removal. It never deletes those
objects; recovery or reuse requires a separately reviewed operation. Redis secret
metadata uses JSON, not nested template expansion. Secret contents are not read.

The legacy combined backup/restore branch remains definition-only. Executable
initialization, canary upload and canary restore are separate contracts. Each new
operation must verify terminal prerequisite identities, exact ordered actions,
acceptance, recovery and frozen inputs. Never activate a consumed definition or
infer fresh acceptance from an old preparation snapshot.

### Definition prerequisites and status provenance

The inactive backup/restore schema requires two independent terminal proofs:
accepted host baseline and accepted repository initialization. Each proof is either
explicitly unverified with no evidence, or carries a terminal tag, archive commit,
bundle hash, evidence-record hash, accepted-identity hash, target and acceptance
timestamp. A syntactically valid proof is not verified evidence: future executable
preflight must read the archived records and match the target, repository ID,
endpoint, bucket and prefix against current read-only observations. Storage-soak
success cannot substitute for either terminal proof.

Ordered workflow, acceptance requirements, boundaries and evidence records are exact
schema contracts. Upload/integrity and isolated restore retain separate authorization
boundaries. Definition state, null command and false mutation authorization remain
mandatory. The obsolete pending transition was removed; no executable operation is
created by this schema correction.

`preparation_review` is a retained evidence snapshot, not a live status API. It names
plan stage 3. Historical authorizations have explicit historical names and are not
reusable. Known observation timestamps carry a source reference; unknown timestamps
are null with an explicit reason. The date of documenting a record is not its event
time. Do not infer missing times from file modification times, current time or due
checkpoints. The Webmin launch time and retained readback time are distinct; neither
proves the later observation completed. Preserve source evidence unchanged and update
current observations only after separately authorized collection and review.

## Image qualification before runtime activation

Use [the bounded image-build procedure](OPERATIONS.md#bounded-arm64-image-qualification) and its exact bundle
launcher. It stages one rootless build in an isolated store, under a delegated
limited service and independent watchdog. It does not activate runtime deployment
or production credential delivery. The single operation slot holds its definition;
external exact-hash approval is still required to execute. Keep the resulting OCI
manifest digest, archive checksum and image ID distinct. Loading into the runtime
store, settings/database qualification and runtime startup require later review.

## After credential injection

Use [image loading and configuration qualification](OPERATIONS.md#image-loading-and-application-configuration-qualification)
for the next bounded stages. Published credential provenance is in
`manifests/provisioned-credentials.json`. Image loading, disposable authentication
checks, production deployment and administrator bootstrap are distinct results.

The archived image-store identity is in `manifests/runtime-image-store.json`.
Use [configuration and authentication qualification](OPERATIONS.md#disposable-configuration-and-authentication-qualification)
for the frozen Ansible disposable-trial procedure, exact-hash approval, independent
guard, cleanup and acceptance requirements.

## Workload and persistence qualification

The [master plan](NAUTOBOT_DEPLOYMENT_PLAN.md#stage-5-workload-and-persistence-qualification)
owns the sequence and acceptance criteria. Workload parameters remain in
`manifests/workload-test.yaml`; progress and qualification results are recorded in
[ROADMAP.md](ROADMAP.md). This procedure is not a live authorization.

### Adapter and sampler procedure

- [workload_adapter.py](../ansible/scripts/workload_adapter.py) builds native
  model operations and uses `validated_save()` in one database transaction.
  It creates dedicated support records, then Locations, Devices, Interfaces,
  Prefixes, IPAddresses and IPAddressToInterface assignments. Existing global
  names are refused without the exact previously retained object-ID receipt.
  Repeat imports make no writes and refuse missing objects or drift. Import
  errors roll back the transaction; there is no automatic fixture deletion.
- [workload_jobs.py](../ansible/scripts/workload_jobs.py) defines import, export
  and read-only audit Jobs with 840-second soft / 900-second hard timeouts.
  The adapter must be loaded alongside the Jobs module. The candidate Ansible playbook installs these modules into the existing
  web/worker Jobs tmpfs only during an approved workload stage. It does not change
  Quadlets or restart production services. Preserve the first import's returned
  ownership receipt before a second import. A lost receipt requires review;
  matching names never authorize adopting existing records.
- Export is a verified projection of fixture fields and natural references,
  sorted by key, excluding database IDs/timestamps. Audit also checks fixture
  membership and detects additional assignments involving owned interfaces.
  These are fixture checks, not a full database export or backup.
- [workload_sampler.py](../ansible/scripts/workload_sampler.py) reads selected
  systemd/Podman metadata, cgroups, proc/sys counters and cursor-bounded kernel
  messages. It records no environment or raw journal text. Samples are private,
  exclusive-create files, limited to 4 MiB; subprocesses have three-second and
  4 MiB limits. It retains a failing sample before stopping. Missing journal
  continuity, metrics or command results are incomplete, never success.
  `review_samples()` verifies ordered minimum-duration phases, initial/final
  coverage, gaps, resource criteria and swap behavior. It explicitly does not
  accept Jobs, backup overlap or the whole workload.

Reviewed source: PyPI `nautobot-3.2.3-py3-none-any.whl`, SHA-256
`a00573a5f304687d8c42680d79955cb5e5c040c0185ecaba24c9d18c1d9aba47`,
verified against versioned package metadata before local static inspection.
Relevant paths: `nautobot/dcim/models/{locations,devices,device_components}.py`,
`nautobot/ipam/models.py`, `nautobot/extras/models/{statuses,roles}.py`,
`nautobot/core/models/__init__.py` and `nautobot/extras/jobs.py`.
LocationType permits Device content; Status permits each status-bearing model;
Role permits Device. IPAM requires parent prefixes in the dedicated Namespace.
Prefix/address constructors populate derived network fields before validation.
Context7's general Nautobot examples supplement this review but do not establish
compatibility with the pinned version.

### Qualification and deployment procedure

1. Exercise the real adapter in a disposable Nautobot 3.2.3/PostgreSQL environment
   with the deployed app set: initial import, exact second import, three exports,
   concurrent audits, collision/drift refusal and a mid-import rollback. Offline
   MemoryStore tests exercise the production decision loop but do not substitute
   for native model constraints, signals or database transactions. Keep this
   qualification away from the production database.
2. Bind dataset hash, Job inputs and receipt to an operation; review fixture size
   against intended inventory. Do not accept an arbitrary user-provided dataset
   merely because the candidate parser accepts its shape.
3. Qualify `ansible/playbooks/run-workload.yaml` and `workload_session.py` for
   registration, phase control, exact Job-ID collection, timeouts, sampler
   supervision and stop-load cleanup in a disposable environment.
   Concurrent audits must have evidence of actual overlap at concurrency two.
   Killing the sampler does not stop Jobs; orchestration must stop only the
   operation-owned load, preserve records, and independently verify termination.
   Never stop production services as an automatic workload cleanup action.
4. Preserve actual phase boundaries and results, including first/last samples.
   Treat a sampler nonzero exit, interruption or missing terminal receipt as
   incomplete. The frozen node input is a JSON rendering of the validated YAML contract,
   keeping the sampler standard-library-only. Before activation, validate the
   contract schema and expected
   baseline identities independently. Current reader paths are pilot-specific
   (`sda`, `sda2`, service account UID 999), not fleet defaults.
5. Review and authorize the real application-aware backup through its owner.
   Record actual overlap with Jobs; successful sampling alone cannot satisfy it.
   Keep isolated full restore as a separate stage. Freeze a workload bundle only
   when these prerequisites and tested failure handling are concrete.

### Workload controller supervision

Ansible remains the orchestration owner. `workload_controller.py` only renders a
controller-side systemd user service and records its exit; rendering does not
install or start it. Freeze the helper with the workload sources. Preserve the
rendered unit with the reviewed execution command and paths. Use a stable checkout
and frozen bundle until the operation is archived; do not edit their sources
while execution or exit handling is pending.

Before execution, verify the controller's user manager, `Linger=yes`, systemd
parser compatibility, persistent filesystem/capacity and SSH-agent availability
for the full window. The launcher refuses a missing service invocation, missing
linger or non-tmpfs runtime storage before resolving secrets or contacting the
host. Do not enable linger, change authentication or install units implicitly.
An agent tied to the disappearing login session is insufficient. Doppler must
work noninteractively through the existing local authentication context; do not
put tokens in the unit or manager environment. The target's service-account
linger is a separate persistence prerequisite.

Render with the reviewed approval digest and absolute paths:

```sh
python3 Nautobot/ansible/scripts/workload_controller.py \
  --bundle /absolute/frozen/bundle --approve SHA256 \
  --evidence /absolute/private/persistent/evidence/new-operation \
  --ssh-socket /absolute/reviewed/agent/socket
```

The existing evidence parent must be owned by the controller user and mode 0700,
with no symlinks. Evidence must be outside Git and outside `/tmp`, `/var/tmp` and
`/run`; additionally verify its backing filesystem survives workstation restart.
The new operation directory must not exist. The unit uses `Type=exec`,
`Restart=no`, `KillMode=control-group`, a 12000-second deadline and 45-second stop
bound. There is no boot enablement or automatic replay. Its unit name must match
`nautobot-workload-` plus the first 24 approval-hash characters. Validate the
rendered unit with `systemd-analyze verify` before separately authorized linking
and starting through the controller user's service manager.

Secrets are resolved inside the service into its mode-0700 `RuntimeDirectory`
beneath `/run/user/UID`, with mode-0600 files. Normal failure attempts each file's
cleanup independently. `RuntimeDirectoryPreserve=no` lets the service manager
remove the directory even when Python cannot finalize; reboot clears its tmpfs.
The `ExecStopPost` receipt deliberately does not claim that directory removal has
already happened. Verify absence independently after the unit stops. Never copy
runtime credentials into durable evidence.

Retain `controller-started.json` (approval, boot, invocation and remote root),
`controller-result.json`, `controller-stop.json`, controller cleanup receipt,
private Ansible inputs/output and fetched node evidence. Output is limited to
16 MiB per stream and never inherited by the terminal or journal. Start/result
receipts are exclusive and fsynced. A prior evidence directory is not reused.
`collected` means Ansible returned zero and normal credential cleanup finished;
it does not accept the workload. An interrupted or missing exit/finalizer record
means incomplete controller coverage, even if node execution subsequently passes.

After controller loss, inspect the unit and exact remote operation read-only.
Do not restart the service or rerun the workload. Independently verify node
process termination, exact owned Jobs/registration state, credential absence,
module residue and all required receipts. Only then prepare scoped recovery of
owned residue. Node-local deadlines continue to bound load, but controller
supervision does not guarantee node-side Ansible finalization after workstation
power loss. Preserve that distinction in the terminal review.

Offline regressions cover rendering, service-parser validation, normal failure,
timeout, credential cleanup, duplicate receipt refusal and missing-finalizer
classification. Before a new long live operation, qualify the rendered service
with a disposable local payload: detach its terminal, kill its main process,
allow the deadline to expire and independently verify descendant termination,
runtime removal and retained evidence. These checks must not invoke the real
workload or production credentials. A workstation reboot is not automatically
part of this qualification. Neither offline tests nor rendering prove live
manager/logout survival.

Reference semantics: [systemd service lifecycle](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
and [runtime directory lifecycle](https://www.freedesktop.org/software/systemd/man/systemd.exec.html).

### Persistence procedure

Prepare logout and reboot as separate bounded stages, each with its own exact
inputs. No active operation is opened by this document.

| Stage | Required preparation | Acceptance and failure boundary |
| --- | --- | --- |
| Logout | Enumerate only operation-owned test login sessions; independent administrator connection; current user-manager/linger, unit invocation and restart baseline | Close only those sessions; observe five minutes from the independent connection with continued health, unchanged invocations/restarts and no collection gaps. Preserve evidence and stop if continuity fails. |
| Reboot | Confirm console recovery; fresh baseline; record pending kernel; freeze reconnect/readiness deadlines; preserve reviewed current database/media recovery inputs and a quiesced logical comparison | One authorized reboot; new boot ID, automatic service activation, matching persistent artifact identities, healthy logical data, limits, guard, both backend families and management/Munin access. Observe at least 75 seconds after readiness. No automatic repeated reboot or destructive restore. |

`ansible/scripts/persistence-preflight.py` extends the existing read-only startup
collector with the service account's UID/linger, login-session inventory, and the
five running services' invocation IDs, restart counters and PIDs. Freeze it with
`startup-preflight.py` for the separately authorized bounded collection. It never
selects or terminates sessions, enables linger, starts units or accepts persistence.
Compare returned artifacts with accepted state and review current recovery inputs.
A collection result is readiness evidence, not a persistence pass.

For the logout definition, identify every service-account session and its class.
Preserve the account's `Service=systemd-user`, `Class=manager` or `manager-early`
session: that represents the user manager, not an ordinary login. Prove the
ownership of any other session before closing it. Confirm the independent administrator connection
uses a different account and cannot hold the service user's manager alive. Do not
close an existing or unowned session. If other ordinary login sessions exist for the service
account, defer the test; ending only a test session while another remains would
not prove survival after its last logout. Record the account's session list both
before and after closing only the owned sessions.

Prepare a five-minute observer from that independent connection, sampling every
five seconds with an explicit maximum ten-second gap. Bind boot ID, the five
service invocations/restart counts, backend guard and image/configuration hashes
to the fresh baseline. Require no remaining ordinary service-account login sessions,
continued healthy application responses, unchanged invocations/restarts and no
new storage errors. Run the application request through the already approved
proxy-source path; do not bypass backend enforcement or introduce Caddy onboarding.
Freeze exact session IDs, collection commands, observation deadlines and recovery
inputs before requesting execution authorization. On a gap, service change or
failed health read, preserve evidence and classify the test incomplete/failed;
do not restart services or restore data automatically.

For an account with a `nologin` shell, prepare one transient system service using
`User=nautobot`, `PAMName=login`, `Type=exec`, `Restart=no`, `RuntimeMaxSec=120`,
`TimeoutStopSec=10`, and `/usr/bin/sleep 90`. Do not change the account shell,
password, SSH policy or existing PAM files. Validate the installed PAM stack and
systemd version first. Record the service MainPID and require exactly one new
session for UID 999 whose Leader equals that PID and whose Service is `login`;
exclude the pre-existing manager session. A unit name or username alone is not
ownership proof. If registration is absent, ambiguous or inconsistent, stop the
owned transient unit and report incomplete; do not terminate an arbitrary session.

Once ownership is independently established, stop only the named transient unit,
verify its PAM session disappeared, then begin the 300-second observation from
`ama`. The sleep and runtime deadlines also bound an abandoned test session.
The observer must not run inside the test session. Capture every sample locally
on the node and collect it afterward; controller disconnect alone must not erase
coverage. Use a 420-second observer deadline with no automatic retry. Starting
and stopping this test session, staging its observer, and any proxy health probes
must be included explicitly in the execution bundle and authorization.

This tests PAM-session closure, not an interactive SSH login; retain that scope
in acceptance. [The systemd 257 PAMName contract](https://github.com/systemd/systemd/blob/v257/man/systemd.exec.xml)
notes that PAM processes can move into a session scope. Verify both transient-unit
and owned-session absence; do not assume a cgroup name proves cleanup. If either
remains, preserve evidence and require scoped recovery. Never use `terminate-user`.

The logout session lifecycle/observer and reboot execution bundle remain separate
preparation. Reboot must also prove logical data persistence. No read-only
preflight authorizes logout, reboot, service changes or restore.

### Local qualification and bundle interface

`tests/qualify-workload-local.py` accepts immutable local application, PostgreSQL
and Redis image IDs and a new private output directory. Build the application
image from the pinned Nautobot release with the hash-verified DNS Models wheel
in `container/requirements.lock`. The runner uses an internal Podman network,
no published ports, disposable database storage and scoped cleanup. It never
uses SSH or production credentials. The default fixture matches the workload
contract; `--small` is only for native bridge regressions. Preserve image IDs,
input hashes, native output and cleanup receipts; do not call this an ARM64 or
production acceptance run.

`ansible/scripts/run-workload.py` is the workload service entrypoint. It requires
a reviewed bundle, systemd invocation and private runtime directory; direct
interactive execution and caller-owned credential files are no longer supported.
`bundle.json` maps flat inputs and repository sources to SHA-256 values, including
`workload_controller.py`. Its exact bytes define the approval hash. It binds the
strict `workload-execution.schema.json`, validated contract, deterministic
dataset, Ansible playbook and helpers.
The launcher rechecks source hashes, schema, backup authorization, fixture and
paths before invoking Ansible. No executable workload instance is supplied now.

The Restic owner must supply a separately reviewed, frozen
`application-backup.py` entrypoint and its dependencies. It writes a fresh
`application-backup-result.json` beneath the operation directory. Required fields
are `kind: application_backup`, the exact `operation_id`, `upload_passed`,
`integrity_passed`, full `snapshot_id`, UTC epoch `started`/`finished`, and
`content_sha256` entries for `postgresql_custom_dump`, `media`, `configuration`,
`image_dependency_manifest`, `quadlet_config_hashes`, and `versions_migrations`.
These must come from actual backup/integrity verification, not constructed labels.
Never substitute the existing canary helper. Credential resolution and cleanup
remain Restic-owned inputs; secret values never enter bundle arguments or JSON.

The node boundary enforces phase and Job deadlines independently of the Ansible
connection, records Job IDs before dispatch and checks sampler failure while
Jobs run. Audit pairs are enqueued together. On failure it cancels only recorded
IDs and distinguishes terminal database state from confirmed worker absence.
Unknown cancellation means manual review, not successful cleanup. Interrupted
backup processes retain uploaded snapshots and evidence; no automatic unlock,
prune, fixture deletion or data restore is permitted. Collection and cleanup
failures remain visible in `orchestration.json`. Missing receipts are incomplete;
reviewer acceptance remains separate from an exit-zero process result.

### Application-backup producer

The reusable Restic entrypoint is `restic/scripts/application-backup.py --root
PROTECTED_DIRECTORY`. Freeze its exact bytes as `application-backup.py` plus a
non-secret `application-backup.json` in the workload bundle. The latter binds the
operation ID, execution UID, required staging filesystem, exact Restic
version/repository URL and ID, snapshot hostname, deadline,
six bounded capture commands and the PostgreSQL archive-list validator. The
launcher rejects a substituted producer or a mismatched operation ID.

Nautobot owns the capture commands and their application meaning:

- `postgresql_custom_dump`: the installed PostgreSQL client's `pg_dump -Fc`,
  using the rootless database container and existing local authentication;
  require custom-format magic and successful `pg_restore --list` on its bytes.
- `media`: a complete archive of the reviewed application media tree.
- `configuration`: reviewed recovery configuration, excluding injected passwords,
  secret-bearing environment files and Podman secret content. Preserve external
  secret references and independent password/key recovery instructions.
- `image_dependency_manifest`: immutable image identities and dependency lock.
- `quadlet_config_hashes`: hashes and recoverable definitions of the actual
  reviewed Quadlets and non-secret application configuration.
- `versions_migrations`: native installed core/App versions and database migration
  ledger. Do not substitute desired-state labels for installed observations.

Before freezing a live contract, review source paths, mount/capacity, executable
identities, maximum capture sizes, and the database/media consistency boundary.
`source_consistency_reviewed` is an authorization input, not a measured guarantee.
A logical PostgreSQL dump is transactionally consistent within PostgreSQL; it
cannot by itself synchronize media changes. The workload's import phase must
finish before backup and the overlap Jobs must remain read-only. Any other
application writer needs a reviewed exclusion/quiescence or snapshot strategy.
No automatic service stop or new maintenance-mode change is hidden in this helper.

The pilot capture helper is `workload_capture.py --root DIRECTORY SECTION`.
Freeze it with `backup-sources.json`, the desired-state manifest, qualified-image
manifest and dependency lock. The source map permits only the reviewed
`nautobot_config.py` and current `.container`, `.volume` and `.network` definitions;
exclude environment/secret files and Ansible backup copies. It checks their hashes
before and after capture. The launcher binds all execution helpers to repository
bytes as well as binding bundle contents to their approval hash.

For this pilot, use the confirmed quiet application window: no manual/API writes
or media uploads, completed synthetic imports, and read-only overlap audits.
`consistency: quiet_pilot_empty_media` requires a directory-only media tree before
and after every capture. Any file or symlink rejects capture. Preserve the directory
layout in the media archive; this is not qualification of populated media backup.
PostgreSQL uses `pg_dump --no-password -U nautobot -d nautobot --format=custom`
as the container's postgres user, with a 600-second container-side timeout.
Validate the dump with the same container's `pg_restore --list`. Native version
metadata and the ordered migration ledger are read separately; do not migrate
during the window. PostgreSQL snapshot consistency does not extend to media.
See [PostgreSQL 17 pg_dump](https://www.postgresql.org/docs/17/app-pgdump.html).

Before workload execution, the temporary capture qualification playbook stages
and hashes the actual helpers, captures all six categories, checks the dump and
samples host health between captures. Bound the dump to 256 MiB and each other
category to 16 MiB. Require 384 MiB spare staging capacity above the normal memory
headroom floor because this pilot's `/tmp` is tmpfs. The qualification does not
claim continuous sampling across captures or exercise workload Jobs, B2 upload,
reboot, or restore. It fetches only the result and removes raw captures independently
on success/failure. Retain the mode-0700 staging directory and receipt for review.
If the controller/target is lost or forcibly terminated, raw residue is possible;
inspect that exact directory before recovery, never repeat or recursively clean
an unverified operation path. This qualification itself requires a reviewed
mutation approval for temporary target files. Do not call it complete from syntax
checks or from the earlier disposable-container qualification.

Resolve `repository`, `password` and `credentials.json` outside the bundle into a
new owner-only directory (0700, regular files 0600). The credentials JSON contains
only `id`/`key` for S3; `{}` is reserved for disposable local-repository tests.
Pass that directory to `run-workload.py --backup-secrets DIRECTORY`. Ansible stages
these files with `no_log`; no secret is included in the approval hash. The
credential-resolving controller operation owns removal of its local copies. The
producer attempts both remote credential removals independently; Ansible also
attempts both in `always` and checks absence even after producer failure. A
successful backup receipt requires both cleanup flags true.

Capture output is protected and size/deadline bounded. Available staging space
must exceed the sum of the reviewed capture limits. The helper checks repository
identity without initializing, derives the full snapshot ID from before/after
sets, rejects nonzero upload status including partial snapshots, runs full
`check --read-data`, verifies payload hashes remain unchanged and checks lock
absence. It retains payload and snapshot IDs on failure. It never initializes,
restores, forgets, prunes, unlocks or repairs a production repository. A successful
receipt remains `accepted: false` and `restore_verified: false`; application
recovery is a separate exact-snapshot stage.

`tests/qualify-workload-session-local.py` exercises the real Session engine,
native asynchronous Celery Jobs and the producer against an internal Podman
network and disposable local Restic repository. It uses accelerated phase lengths;
it does not qualify ARM64 headroom, the production durations, Pi hardware sampling,
SSH staging or user-systemd behavior. Preserve those as explicit live checks.
The existing offline tests exercise inactive Ansible gating and failure decisions;
they do not substitute for successful staging/cleanup on the target.

Cancellation kills the operation-owned backup process group and retains its
receipts. A lost Podman exec transport is not proof that a process inside a
container stopped: the live capture definition must bound its server-side work
and the failure review must verify no operation-owned dump/query remains. An
absent producer completion record or unresolved child activity prevents acceptance.

The scoped Job stop path sends terminate+revoke for the recorded task ID and
requires a positive acknowledgment. It waits boundedly for a responding pilot
worker to report that ID absent and for native JobResult state to settle. A
revocation label or missing worker reply alone is insufficient. Only after
positive absence may the native reaper settle a remaining nonterminal row.
The disposable test checks REVOKED before the Job's own lock timeout, avoiding
a false pass caused by a task naturally failing while cancellation is checked.

### Freezing and running the workload bundle

The single operation manifest must name `workload_qualification`, the exact
execution input, governing-plan hash, source base commit and reviewed baseline
hash/time. The launcher rejects an inactive or different operation, source drift,
substituted helpers and changed baseline service invocations. The bundle's file
hashes identify the prepared revision in addition to its source base commit.
Definition flags express the candidate scope; only approval of the final bundle
hash authorizes execution. Publish the implementation and verify CI before use.

Use `run-workload.py --bundle DIRECTORY --approve SHA256 --evidence NEW_DIRECTORY
--resolve-doppler` for the reviewed pilot. The controller resolves only
`homelab-dev/prd_restic/NAUTOBOT_RESTIC_REPOSITORY_PASSWORD` and
`homelab-dev/prd_b2/NAUTOBOT_RESTIC_B2_APPLICATION_KEY_ID` plus
`NAUTOBOT_RESTIC_B2_APPLICATION_KEY`, through the existing bounded reader.
It removes all controller copies independently even after partial resolution or
execution failure, and records cleanup booleans without values. The alternative
`--backup-secrets` accepts caller-managed files; the caller owns their cleanup.
No secret resolution occurs while preparing or verifying a bundle.

Ansible stages the private capture under root-owned `/tmp`; application commands
still execute in the existing rootless containers. This does not change the
installed Restic policy or schedule. Retained payloads are root-only and bounded
by the six capture limits. On this tmpfs host, reserve their capacity in memory
headroom. Never treat the historical cold-copy metadata as a current restore.

Dispatch the first audit pair before backup and require native STARTED state for
both Jobs before launching capture. If either finishes before that observation,
fail coordination without starting backup. Acceptance still compares actual Job
timestamps against the completed backup interval; running-state observation alone
is not overlap proof. Status checks are batched into one native shell call. Stop
reconciliation uses one batch and retains its result across failure handlers;
unknown worker replies stay unresolved. Dispatch, running observation, backup
launch and stop timestamps are retained in `timing.json`.

For an explicitly reviewed repeat trial, `execution.resume` binds the source
operation, ownership-file SHA-256 and all three registration UUIDs. Freeze
`retained-ownership.json`; its fixture digest must match the generated dataset.
The adapter still verifies every object UUID and refuses drift or adoption by
name. Existing registrations must match their exact module/class/UUID and be
disabled; activation is atomic. An unexpectedly enabled row is not disabled as
cleanup of failed reuse. A lost activation response remains an unresolved state
for inspection. Repeat-fixture imports are labelled separately from first-import
qualification. Do not delete fixtures or registrations as implicit retry cleanup. Evidence allows
8 MiB for samples across the three-hour maximum, with the existing five-second
sampling and 15-second maximum gap. Successful minimum coverage is 4,575 seconds.

On failure, stop only owned Jobs and the backup process group; preserve fixtures,
snapshots, payload and receipts. Check remote and controller credential removal,
Job-file cleanup, remaining native Job activity and any container-side dump.
Missing cleanup or collection evidence leaves the outcome unresolved. Do not
restart services, delete snapshots, restore data or remove fixtures automatically.
Full application restore, reboot/logout persistence, Caddy and pilot acceptance
remain separate stages.

## Retained host-baseline convergence and acceptance

Use accepted-live-state and HISTORY for results. A new baseline is a separate read-only operation.

### Retained host-baseline convergence and acceptance — Preflight execution contract

The collector is `../ansible/playbooks/preflight-host-convergence.yaml`; every
remote command uses the exact ordered argv catalog in the active manifest.
Noninteractive sudo, a 30-second command timeout and a five-second forced-stop
bound apply to ordinary probes. The explicit 75-second SMART settling probe has
a 90-second timeout, followed by a second kernel-event read. Commands never run through a shell. Literal dpkg
format variables are protected by `expand_argument_vars: false`.

Rootless Podman runs through runuser as nautobot, then `env --chdir` enters
`/var/lib/nautobot` before `podman info`. This queries existing runtime state;
no build, pull, container start, system migration or reset is permitted. Ansible
transport may create its normal transient module files, and Podman may touch
its existing runtime bookkeeping. These are read-only inspection mechanics,
not authorization for persistent configuration changes. Any unexpected runtime
initialization requirement stops this operation.

The collector records complete command observations before the offline evaluator
asserts anything. Malformed, missing, duplicate, reordered, oversized, skipped,
unreachable, unexpected-status or stderr-bearing results block. Package residue
checks reject Keepalived records (including residual configuration), dpkg
config-files records, and simulated autoremove candidates. Simulation never
runs APT removal. Listener comparison includes protocol, state and both local
and peer endpoints; it also prohibits backend, PostgreSQL and Redis ports.

Storage checks bind `/dev/sda2` ext4 to its `/dev/sda` USB attribute chain,
require the sole exact quirk token, JMicron identity and 5 Gbps usb-storage,
post-mitigation focused faults absent on the reviewed boot, SMART zero
warning/media/error counters,
clean ext4 metadata, zero live ext4 errors, temperature below 80 C and zero
throttling. Generic USB initialization and loading the UAS module are not faults.
SMART health or error-log failure remains blocking. The reviewed query now requests
health, identity, attributes and the error log, excluding the unreliable self-test
log. smartd policy remains unchanged and its warnings remain available for review.

### Retained host-baseline convergence and acceptance — Terminal reconciliation and accepted identity

A preflight result of `preflight_passed_review_required` is not acceptance.
Review every recorded observation, command status, no-drift decision, protected
path mode, local/remote transient cleanup and historical continuity. Retain
forward evidence before the decision, including on timeout or privilege failure.

Only after all applicable baseline requirements pass may terminal reconciliation
create `../manifests/accepted-live-state.yaml` using
`../schemas/accepted-host-baseline.schema.json`. Record host and service-account
identity, observed boot, semantic identity hash, raw observation hash, exact
operation/bundle/definition provenance, terminal evidence hash and explicit
operator acceptance. Define the semantic identity as SHA-256 of canonical JSON
(`sort_keys=True`, separators `(',', ':')`, UTF-8, no trailing newline) of the
reviewed `expected` mapping; retain that mapping in the terminal archive. This
hash contains only non-secret host requirements and is not live authorization.

Terminal evidence must distinguish preflight pass, mutation not attempted,
convergence of retained state, rollback not attempted, cleanup, and acceptance.
Preserve the exact terminal operation and sanitized evidence in an annotated,
pushed tag before removing consumed operation data. Add one concise HISTORY
entry and reconcile the accepted identity; then return the active slot to clean.
Commit, tag and push require separate authorization. Do not rewrite v3's manual
intervention result or claim that it was retroactively accepted.

The accepted identity covers host baseline only. Isolated backup/restore,
Nautobot runtime, application logout/reboot survival, representative memory,
swap and workload temperature, application-backend firewall acceptance, stage-4
DNS/routing acceptance, Caddy onboarding,
authority migration and Semaphore remain separately gated. Baseline management
and monitoring firewall evidence is required before this host identity is accepted,
as specified below; it is not deferred with the application tests.

If drift appears, preserve evidence, stop, and define only the exact required
correction under separate authorization. No automatic full baseline replay,
package reinstall, rollback, service transition or reboot is present.

### Retained host-baseline convergence and acceptance — Baseline firewall evidence required for terminal acceptance

The existing 59-check preflight establishes listener identity, not access-control
acceptance. Stage 3 additionally requires a network-owner-reviewed evidence matrix.
Follow the [UniFi access procedure](https://github.com/Racerx323/homelab-network/blob/main/Ubiquiti/UNIFI_ACCESS.md)
for separately authorized controller reads. Any correction follows homelab-network's
own operation, rollback and authorization process. This checklist authorizes no
controller access, remote probe or policy change.

#### Retained host-baseline convergence and acceptance — Define expected access before probing

| Service | Destination and protocol | Expected permitted source | Required denied coverage |
| --- | --- | --- | --- |
| SSH | TCP 22 on observed IPv4/IPv6 addresses | Explicit approved administration addresses or policy groups | Unapproved routed client and external IPv6 source |
| Webmin | TCP 10000; separately account for observed UDP 10000 | Explicit approved administration sources; decide UDP discovery necessity separately | Unapproved routed client and external IPv6 source |
| Munin | TCP 4949 on observed IPv4/IPv6 addresses | Exact monitoring poller identities from owning configuration | Non-poller client and external IPv6 source |
| Webmin stats | Optional TCP 555 | Host loopback only | Confirm no non-loopback binding; absence is allowed |
| Other listeners | Every additional observed endpoint | No implicit permission | Resolve unexpected endpoints before acceptance |

Source identities, membership of policy groups, destination addresses and rule IDs
must be resolved from owning inventory/configuration and current readback. They
are currently missing acceptance inputs, not assumed trusted subnets. Do not
invent a permit policy from existing connectivity. Record both permitted and denied
cases for each applicable address family. A missing vantage point or absent service
means incomplete coverage, not a successful firewall denial.

#### Retained host-baseline convergence and acceptance — Retain independent policy and path evidence

- Timestamped host identity, boot ID, interfaces, IPv4, permanent/SLAAC ULA and
  current global IPv6 addresses, routes and listening sockets. Do not publish
  temporary global addresses as stable DNS identities.
- Sanitized controller readback identifying the applicable policy revision,
  rule IDs/order, enabled state, source/destination groups and their resolved
  membership, protocol/ports, direction/zones and default treatment. Include
  relevant IPv4 NAT/port-forward exposure. Determine whether traffic crosses
  the gateway; same-segment traffic can bypass a routed firewall policy.
- For each approved probe, timestamp, actual source address/interface and zone,
  destination address/family/port, expected result, observed result and bounded
  evidence reference/hash. Demonstrate source routing works and the destination
  service is listening during negative tests. A timeout by itself cannot
  distinguish firewall denial from a broken route or stopped service.
- Correlate denied tests with the applicable policy and available counters/logs.
  If that correlation is unavailable, record the uncertainty and obtain a
  network-owner disposition; do not silently classify a timeout as proof.
  A successful TCP connection verifies reachability only, not authentication.
- Record the network owner's review, exceptions and unresolved rows. Keep raw
  controller data, addresses and probe logs private; retain sanitized decisions
  and evidence hashes in the terminal acceptance record. Never include credentials.

Terminal baseline acceptance requires all required rows resolved, management and
monitoring restricted to approved sources, and no unintended global-IPv6 access.
If a source group, rule scope or vantage point is unavailable, keep the gate open.
No exposure test may widen rules or stop services to manufacture a passing result.
The Webmin observation and SMART limitation review remain independent prerequisites.
Application TCP 8080, unpublished PostgreSQL/Redis, Caddy publication and full
application dual-stack health remain stage-5/6 checks. Later address, firewall or
runtime changes require reassessing the affected baseline evidence.

## Raspberry Pi memory-controller correction

Nautobot's host baseline requires cgroup-v2 memory control before application
memory ceilings can be accepted. This correction enables that runtime capability;
it does not alter the host-storage transport profile or qualify other hosts.

### Raspberry Pi memory-controller correction — Diagnose

Read the running kernel configuration, `/proc/cmdline`, the actual firmware
command-line file and `/sys/fs/cgroup/cgroup.controllers`. Raspberry Pi firmware
can prepend `cgroup_disable=memory` from its device-tree defaults even though
that token is absent from `/boot/firmware/cmdline.txt`. With `CONFIG_MEMCG=y`,
append `cgroup_enable=memory` to override that earlier default. Do not add the
obsolete `cgroup_memory=1` token. A build without `CONFIG_MEMCG_V1` can omit memory
from `/proc/cgroups` even when the v2 controller works.
See the [Raspberry Pi maintainer explanation](https://github.com/raspberrypi/linux/issues/6980#issuecomment-3149752155).

### Raspberry Pi memory-controller correction — Stage

Use `ansible/scripts/plan-memory-controller.py` to render exact original bytes
to a separate private candidate. It preserves line endings and unrelated
arguments and refuses conflicting settings. The current implementation is scoped
to the reviewed Raspberry Pi/JMicron host; it is not a fleet deployment entrypoint.

Prepare a protected JSON plan with a `memory_correction` object containing
`stage: boot_file_only`, `reboot_authorized: false`, `boot_path`,
`backup_directory`, `boot_id`, `before_sha256`, `after_sha256` and exact `content`.
Review the byte diff, preserve original bytes locally, and bind the plan,
playbook, renderer, validators, wrapper and non-secret inventory inputs in the
operation's SHA-256 bundle before authorized execution.

From the repository root, use the repository Ansible wrapper:

```bash
/bin/bash tests/repository/run-with-ansible-local-temp.sh \
  ansible-playbook --inventory inventory/prod/hosts.yaml \
  --limit j2-svpi4mf --user ama \
  Nautobot/ansible/playbooks/stage-memory-controller.yaml \
  --extra-vars memory_controller_plan=/absolute/private/stage-plan.json
```

The playbook verifies the current boot, file identity and reviewed hashes,
preserves `cmdline.before` in a root-only backup directory, verifies its hash,
rechecks drift, stages the candidate and verifies unchanged boot identity.
It performs no reboot. Independently read back the candidate and backup hashes,
firmware configuration hash, boot identity and current controller list. Preserve
stdout, stderr and exit status separately. A partial mutation must be investigated
and either verified or rolled back; do not blindly replay after drift.

### Raspberry Pi memory-controller correction — Rollback and reboot boundary

Before restoring, require the live command-line hash to equal the reviewed
candidate hash and the backup hash to equal the original hash. Stop on mismatch.
Use Ansible `copy` with `remote_src: true` to restore the exact backup to the
reviewed boot path with its original ownership and mode, then independently
verify the original hash. A rollback before reboot does not require reboot.

Reboot is a separate authorized stage. Confirm physical/console recovery access
and preserve the exact original locally before proceeding. If SSH does not
return, restore the original command-line bytes on the boot partition through
that recovery path, preserving root identity and the USB transport quirk.
Postboot rollback requires another explicitly scoped reboot.

After reboot, verify a new boot identity, root-device continuity, expected USB
binding and quirk, memory-controller availability and user-manager delegation.
Review kernel/storage/power health under a new boot-bound window. Verify actual
per-service memory-limit enforcement during bounded runtime acceptance; controller
availability alone is insufficient. Storage acceptance and Restic remain separate.

Use `ansible/playbooks/reboot-memory-controller.yaml` for the separately
authorized single-host reboot. Its protected `memory_reboot_plan` JSON input
contains `memory_reboot.stage: reboot_and_validate`, boolean `authorized` and
`recovery_confirmed`, `old_boot_id`, and an `expected_hashes` map of absolute
paths to SHA-256 values. Include the staged command line, original backup,
firmware config and monitoring inputs. Bind the plan, playbook, wrapper,
inventory and exact command before execution. The playbook refuses boot/file
drift, captures a journal cursor, reboots once, and checks new boot identity,
memory-controller availability and file integrity. Collect independent host and
storage evidence afterward; a successful playbook alone does not accept storage.

Record the running kernel before and after reboot. A pending installed kernel
may activate at the same time; verify its configuration and USB behavior rather
than assuming the old kernel remains active. Preserve relevant previous-boot
logs locally before reboot because the host journal may not persist them.

## Reviewed baseline package cleanup

This procedure removes an explicitly reviewed set of obsolete packages and
residual configuration records after host-baseline preflight. It is not a
general autoremove policy and does not authorize package upgrades or reboot.

### Reviewed baseline package cleanup — Prepare and review

Record exact package names, versions and dpkg states, running kernel and boot
identity in a protected `cleanup_plan` JSON. Its `cleanup` object contains
`host`, `boot_id`, `kernel`, `directory`, and `packages`, keyed by package name
with `version` and `state` values. The current purge playbook is intentionally
limited to the reviewed eleven-entry cleanup on `j2-svpi4mf`; review another
scope before changing that guard.

Run `ansible/playbooks/prepare-package-cleanup.yaml` using the repository Ansible
wrapper, explicit inventory/host limit, `cleanup_plan`, and protected controller
`cleanup_evidence` path. It requires a new protected remote evidence directory.
The helper compares exact package state, simulates only the named purge, obtains
the exact recovery `.deb` files from cache or the configured package sources,
and verifies package/version metadata. It archives affected conffiles, package
metadata, APT marks and boot files; its recovery index records hashes. Treat the
archive as private configuration data. No purge occurs in preparation.

Review the recovery index, actual simulation and running/fallback kernel
retention. Bind the plan, recovery index, playbook, helper, wrapper and inventory
to the authorized bundle. Preserve the exact command and raw streams privately.

### Reviewed baseline package cleanup — Execute and verify

Use `ansible/playbooks/purge-reviewed-packages.yaml` through the same wrapper.
It checks boot identity, unchanged package database, recovery archive/packages,
and firmware hashes. It then re-simulates and requires precisely the named
removal set with no installs/upgrades before issuing `apt-get --assume-yes purge`
with those explicit names. It does not use `autoremove`. Needrestart runs in
list-only mode; unrelated service restarts are not requested.

The command result is retained before assertions. Verify firmware bytes and boot
identity after execution, independently inspect installed/residual package state
and a new autoremove simulation, and rerun the full read-only host preflight.
Successful purge is not host acceptance. Preserve failed pre-mutation attempts
and do not obscure a mutation-bearing failure with an automatic retry.

### Reviewed baseline package cleanup — Recovery

Retain exact recovery packages and the original archive. After a partial package
transaction, inspect dpkg state and define the smallest recovery; do not restore
the complete package database over unrelated changes. Previously installed
packages can be reinstalled from the exact preserved `.deb` files after a
dependency simulation. Previously removed packages with residual configuration
must not be blindly reinstalled or started: restore only reviewed original paths
and separately review any package-state reconstruction. Restore package marks
through `apt-mark` using retained evidence.

Unexpected boot-file changes require comparison with the exact backup and
manual review. A recovery reboot is separately authorized. Never remove the
running kernel or an explicitly retained fallback to satisfy a cleanup gate.

## Nautobot storage-remediation decision

The accepted transport profile and ownership are defined in the master plan's
host transport section and the shared host-storage component. The earlier
physical-path, power, bridge and UAS alternatives are historical investigation,
not current deployment blockers or permission to change the host.

The retained `run-storage-diagnostic.sh`, `run-uas-quirk.sh` and
`run-host-baseline-rollback.sh` reproduce narrowly scoped historical contracts.
Do not use them for a new fleet change; use host-storage's reviewed profile and
operation lifecycle. Diagnose read-only first, preserve boot/transport identities,
keep at least 75 seconds delayed-event observation after drive reads, and stop
on reset, timeout or filesystem error. SMART limitations belong to smartmontools.

Any recovery must bind the exact currently installed state, retained backups,
console access and rollback boundary before separate authorization. Never apply
an old baseline rollback or storage quirk simply because an archived command exists.
Historical decision text is preserved in the documentation snapshot indexed by
HISTORY; published terminal tags remain the execution evidence authority.

## Bounded ARM64 image qualification

This procedure owns image qualification only. The deployment plan remains the
architecture authority; the roadmap records current readiness. Preparation does
not authorize host changes. Execute only after explicit approval of the complete
bundle digest printed by `prepare-image-build.py prepare NEW_DIRECTORY`.

### Bounded ARM64 image qualification — Scope and entrypoints

Run from the server repository:

```text
python3 Nautobot/ansible/scripts/prepare-image-build.py prepare /tmp/NEW_BUNDLE
python3 /tmp/NEW_BUNDLE/launcher.py verify /tmp/NEW_BUNDLE EXACT_SHA256
python3 /tmp/NEW_BUNDLE/launcher.py execute /tmp/NEW_BUNDLE EXACT_SHA256
```

Only the last command contacts the target. The digest covers the Ansible playbook,
node worker/watchdog, unit templates, Containerfile/lock, operation and its schema,
accepted/desired records, inventory, configuration, procedure and launcher.
Preparation verifies the stage-4 terminal evidence. Keep the frozen bundle intact.
Use the bundled launcher for execution, not an unrelated checkout's launcher.
A hash mismatch, changed member, symlink or missing input stops before Ansible.
Execution makes and re-verifies a private snapshot to avoid source edits mid-run.

Ansible targets only the approved host as ama with strict host keys against its
accepted identity. It rechecks host/boot/architecture/account/Podman/user-manager
identity and refuses existing operation paths or unit names. The build is rootless
UID 999/GID 985. Root is used for protected staging, systemd units and the watchdog,
not to run Podman. No Doppler values are read or transferred.

### Bounded ARM64 image qualification — Limits, isolation and observation

The operation exclusively creates `/var/tmp/nautobot-image-ID`, with root-owned
inputs and evidence and a nautobot-owned work directory. Its Podman graph/run
stores and temporary files are separate from the runtime account's existing store.
An empty operation-owned auth file prevents registry credential reuse. Public
pinned-registry/wheel downloads are permitted only during authorized execution.
TLS verification and pip hash verification remain enabled.

The worker is a delegated system service with CPUQuota=200%, MemoryHigh=2.5 GiB,
MemoryMax=3 GiB, MemorySwapMax=0, TasksMax=512, RuntimeMaxSec=2700 and control-group
termination. It verifies actual kernel limit files before pulling anything. It
moves into an owned child cgroup, enables the delegated controllers, and gives OCI
build steps a distinct `/build` leaf below the service parent with the cgroupfs
manager. The parent remains process-free; its aggregate limits cover both the
worker and build leaf. Before pulling, the worker rejects a populated parent or
pre-existing build leaf and records the intended layout. Failure to use
that delegation stops execution; there is no unlimited fallback. Test containers
use disabled cgroup creation so they inherit the worker service's limit hierarchy.
No persistent runtime-user slice limits are changed.

A separate root watchdog checks host identity, MemAvailable >=1.5 GiB, temperature
<=80 C, zero throttling, zero/new ext4 errors, failed units, cursor-scoped kernel
storage/OOM events, work disk growth <=30 GiB and filesystem free >=20 GiB. Samples
are nominally five seconds apart; a gap over 15 seconds or a 45-minute deadline
fails qualification. Per-command time/output bounds also fail closed. Disk growth
is a sampled stop threshold, not a hard quota; one interval's writes can overshoot.
The large observed headroom supports this bounded proposal, not arbitrary builds.

The watchdog starts the worker only after a successful health sample. It kills
and verifies the worker stopped on failure and retains a terminal result. Worker
BindsTo and watchdog ExecStopPost stop the worker if the watchdog exits or fails;
independent RuntimeMaxSec limits also cover controller loss. Result absence means
incomplete/manual review, never success. No new run is started automatically.
The final success path observes another 75 seconds for delayed storage events.

### Bounded ARM64 image qualification — Image checks and acceptance boundary

The Containerfile and lock retain the existing approved base and wheel hashes.
The build uses one stage/job, no cache, OCI isolation, private build networking
and no proxy/environment passthrough. The worker checks ARM64/Linux image identity,
exact Nautobot/DNS Models installed versions, `pip check`, and bounded CLI help
for main/start/Celery commands. These test containers have no network, no published
ports, no privileges, no production mounts and read-only roots.

The worker exports an OCI archive, verifies every referenced config/layer digest,
and records image ID, OCI manifest digest and archive checksum separately. A local
image ID is not a registry manifest digest. Nothing is loaded into the runtime
store or pushed to a registry. A later reviewed load must verify those identities
before runtime rendering/deployment. Full settings loading, database-backed plugin
behavior, migration, health serving and application acceptance remain later checks;
CLI help and installed metadata do not prove them.

### Bounded ARM64 image qualification — Failure, retained state and cleanup

Protected `evidence/result.json` records monitored pass/fail and stop confirmation.
Worker output includes the immutable OCI archive and `worker-result.json` on
success. Bounded command streams, timestamps and samples remain on the node;
Ansible collects the terminal result. Controller timeout or SSH loss does not
cancel node supervision. Reconnect read-only to review the retained node evidence.

On any failure, stop and retain the operation directory/store, failed/intermediate
images, units and evidence. There is no prune, image deletion, production rollback,
service re-enable or automatic retry. The runtime units are not enabled and live
under `/run/systemd/system`; successful runs leave them inactive for review.
After terminal archival, separately review stopping/verifying the exact unit names,
removing those two owned runtime unit files, daemon reload and removal of the exact
owned operation tree only after preserving any accepted OCI archive and evidence.
Do not remove anything when ownership, process termination or archive retention
cannot be proved. No existing production configuration or volumes are replaced.

### Bounded ARM64 image qualification — Validation and references

Run the offline regression suite and Ansible syntax check before bundling:

```text
python3 Nautobot/tests/test_image_build.py
/bin/bash tests/repository/run-with-ansible-local-temp.sh ansible-playbook --syntax-check -i localhost, Nautobot/ansible/playbooks/qualify-image.yaml
```

Offline tests must exercise bad hashes, controller no-contact gates, limit mismatch,
watchdog failure/deadline/success paths, command timeout/output overflow and unit
contracts. They do not claim live ARM64/cgroup enforcement. The authorized worker
must pass its real kernel/delegation checks before starting the build.

- [Podman 5.4.2 build options](https://docs.podman.io/en/v5.4.2/markdown/podman-build.1.html)
- [systemd resource control](https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html)

### Bounded ARM64 image qualification — Retrying a mutation-bearing failure

Preserve the consumed operation definition and its evidence. `prepare-retry`
produces a private, unactivated candidate with fresh operation paths; it does not
replace the active manifest or authorize host contact:

```text
python3 Nautobot/ansible/scripts/prepare-image-build.py prepare-retry /tmp/NEW_RETRY_BUNDLE
```

The retained predecessor inputs and stopped-failure result are hash-checked during
preparation. The candidate carries that provenance and its own exact schema.
Before execution can stage anything, its launcher requires the annotated,
published `nautobot-image-qualification-v1-failed` tag containing the exact
consumed operation definition. Terminal archival also requires the sanitized
execution evidence manifest under the repository lifecycle. Git publication is
a separate authorization; preparation does not create or push a tag.

The retry playbook verifies the predecessor result hash, both failed unit states,
zero main PIDs, exit status 1 and absence of both old control groups before new
staging. Only after those checks does it reset those two failed-state markers so
the unchanged zero-failed-unit health guard can run. It does not delete old units,
old stores or evidence, and does not ignore unrelated failed services. Partial
retry staging is retained on failure; do not rerun it blindly.

The cgroup correction follows the kernel's no-internal-process rule. Buildah's
`addCommonOptsToSpec` places CgroupParent directly into OCI linux.cgroupsPath;
passing the controller-distributing parent therefore asks the runtime to put a
process at an invalid level. The corrected path names a leaf. Fixture tests model
that kernel rejection, but native build acceptance is still required.

- [Linux cgroup-v2 process placement](https://docs.kernel.org/admin-guide/cgroup-v2.html#no-internal-process-constraint)
- [Buildah OCI path assignment](https://github.com/containers/buildah/blob/v1.39.3/run_linux.go#L607-L610)

## Application credential preparation

The selected references are recorded in
[credential-preparation.json](../manifests/credential-preparation.json).
This document records the preparation contract. The completed provisioning
outcome is recorded separately in [credential-result.json](../manifests/credential-result.json). Use Doppler project `homelab-dev`,
environment `prd`, config `prd_nautobot`; use administrator `admin`. The approved
email is retained in private bootstrap inputs. Do not copy the email or passwords
into public execution evidence. No production values are present in this repo.

### Application credential preparation — Exact provisioning scope

1. Recheck the exact project/environment and config list using the authenticated
   controller session and TLS-verified `https://api.doppler.com`. Read names only
   for absence/inheritance checks. Unknown response shapes, permission failures
   or timeouts do not prove absence. Do not reuse a historical absence observation as current preflight evidence.
2. Create only `prd_nautobot` in existing `prd`; do not create projects, tokens,
   integrations, environments or modify shared `prd`. Intended CLI:
   `doppler configs create prd_nautobot --project homelab-dev --environment prd`.
3. Refuse if any of the four application keys already exists, including inherited
   keys. Review an existing config instead of replacing it. Generate independent
   cryptographically random values: 64 random bytes encoded as hex for Django,
   32 bytes each for PostgreSQL, Redis and the one-time administrator password.
4. Write only the four exact keys from the manifest. Supply values through a
   protected anonymous descriptor or explicitly cleaned 0600 temporary input,
   never command arguments, environment dumps, shell tracing or build files.
   Suppress and boundedly discard CLI response bodies: write APIs can return
   secret values even when the requested operation is just storage. Do not rely
   on `--silent` as secret redaction.
5. Verify the four names and privately compare returned values with generated
   values in memory. Persist only success/failure and non-secret operation
   metadata; no values or password hashes. Inspect name/response shapes explicitly.
6. On an ambiguous write, preserve the config and investigate. Do not regenerate,
   rotate or delete automatically. Once verified, Doppler is the recovery source.
   A separately reviewed rollback may delete only newly created keys/config after
   establishing no consumer uses them. Never delete the shared environment.

The [provisioning implementation](#credential-provisioning-and-injection-operation) and its
failure/secret-cleanup tests require exact-bundle review before a new live operation. The repository AGENTS.md requires scoped
exact-bundle authorization for live mutation.

### Application credential preparation — Runtime delivery contract

The persistent services consume only the first three logical credentials; the
administrator password is consumed by one-time bootstrap only. Use the manifest's
consumer lists to prevent cross-service distribution. Keep existing B2/Restic
credentials with their owning configuration.

The existing runtime candidate expects protected service environment files owned
by UID 999, mode 0600, a non-secret settings file owned by UID 999, mode 0644, and
Podman secret `nautobot-redis-config`. PostgreSQL requires POSTGRES_PASSWORD; Redis
requires an authenticated health probe (REDISCLI_AUTH) and a protected requirepass
configuration. App database/cache settings must resolve the same passwords and
Django key without embedded values. Final variable names and settings must be
verified against the qualified Nautobot version before injection; generating
Quadlets alone does not validate those settings.

Review each generated environment file and Redis secret for escaping and newline
handling using disposable fixture values. Validate configuration loading, plugin
enablement and bootstrap behavior in a separately scoped environment. Bootstrap
must refuse an existing administrator rather than reset it, avoid outputting the
password, and remove transient bootstrap inputs even after failure. Do not leave
bootstrap credentials in web/worker/scheduler environments.

### Application credential preparation — Runtime image prerequisites

[Runtime inputs](../manifests/runtime-inputs.json) use the qualified OCI manifest
digest, not the local image ID or a mutable tag. Load the independently verified
archive into the runtime account's store only in a separate operation, then verify
its manifest identity and local digest reference before `Pull=never` startup.
If Podman cannot resolve that exact local reference after load, stop and reconcile
it; do not substitute a tag or silently pull from a registry. Data-service images
also require their pinned ARM64 identity checks. Image retention and old build
store cleanup remain separate from runtime installation.

Actual settings, executable stage schema, secret injection, backend firewall
checks and pre-data backup/restore gates must be verified for each new deployment. No DB migration, administrator creation,
Caddy publication or Restic initialization is authorized by this document.

Reference: [Doppler CLI commands](https://github.com/DopplerHQ/cli/blob/master/_autodocs/api-reference/cmd.md).

## Credential provisioning and injection operation

This operation creates one Doppler config and four application credentials, then
injects protected inputs on j2-svpi4mf. It does not start containers, load images,
initialize databases, create the administrator or change Restic/network/Caddy.
The bootstrap password stays only in Doppler until its separate one-time operation.

Do not rerun a consumed create-only bundle. Apply this procedure only after
reviewing a new operation and its prerequisites; completed results belong in HISTORY.

### Credential provisioning and injection operation — Bundle and execution

```text
python3 Nautobot/ansible/scripts/provision-credentials.py prepare /tmp/NEW_BUNDLE
python3 /tmp/NEW_BUNDLE/launcher.py verify /tmp/NEW_BUNDLE EXACT_SHA256
python3 /tmp/NEW_BUNDLE/launcher.py execute /tmp/NEW_BUNDLE EXACT_SHA256
```

Only execute contacts Doppler and the host. Obtain approval for the exact hash;
preparation approval is not authorization to run an unseen bundle. The digest
covers the controller, Ansible playbook, settings, operation/schema, selected
credential policy, accepted host/image inputs, inventory, tests and procedure.
Ansible handles the host; the controller owns secret generation, bounded private
CLI output, frozen-input verification and inter-system failure accounting.

Preflight checks the accepted boot/account, active user manager, zero failed
units, absent runtime directory, and empty rootless container/secret lists.
Commands use `/` as their working directory so rootless queries never inherit
the SSH user's private home. A successful empty secret-list response is treated
as an empty list; failed commands and malformed nonempty JSON still stop.
Unknown command/JSON results stop the operation. Doppler must report existing prd,
absent prd_nautobot and only three metadata names in the parent. Create only that
config, verify it starts empty, generate independent hex credentials, and write
only the four policy keys. Refuse existing configs; never auto-rotate or overwrite.
There is no conditional-create API for individual secrets in this implementation:
the newly created config must remain exclusively owned by this operation until
verification. Concurrent writers are outside its contract.

Doppler uses the existing controller authentication context and explicit
`https://api.doppler.com` with TLS verification. Do not supply tokens on the command
line. Private command stdout/stderr live in anonymous descriptors with 1 MiB output
and bounded execution time; they are never copied into evidence. API write retries
are disabled. Secret-bearing uploads and injection payloads use an exclusive
0700 controller directory and 0600 files, removed on success and ordinary failure.
Cleanup is checked; failures retain the path and fail acceptance. No secret values
or hashes enter evidence. Ansible secret tasks use no_log and diff=false.

### Credential provisioning and injection operation — Injection and verification

Create /var/lib/nautobot/runtime exclusively, owned 999:985, mode 0700. Install six
0600 service environments and 0644 non-secret nautobot_config.py. Create rootless
Podman secret nautobot-redis-config via stdin. Compare environment and Redis-secret
contents privately, and verify environment modes/owners. No bootstrap password is
sent to the host. Redis health receives REDISCLI_AUTH; applications receive
NAUTOBOT_SECRET_KEY, NAUTOBOT_DB_PASSWORD and NAUTOBOT_REDIS_PASSWORD with matching
service endpoints. These names and inherited settings were inspected in the
qualified Nautobot 3.2.3 image. DNS Models is enabled in the settings file.

This verifies stored inputs, not application operation. Full settings import,
database/cache authentication, migrations, plugin behavior and bootstrap remain
runtime qualification checks. No live configuration check is claimed by the
fixture tests. The image's general CLI help is not a substitute for those checks.

### Credential provisioning and injection operation — Failure and recovery

A stage checkpoint is written before cloud or host mutation. Any ambiguous write
stops without automatic retry, deletion, rotation or rollback. Cloud credentials
already created remain the recovery source. A partial host injection remains
protected and is reported as requiring review; no services are started from it.
After an interruption, inspect the fixed config, exact runtime directory and
Redis secret before deciding how to resume. Do not rerun this create-only bundle.
Controller loss can leave an SSH-initiated task finishing remotely; inspect before
retrying. Never infer absence from a failed query.

Separately scoped rollback can remove only this operation's verified unused
runtime directory and Redis secret, and its unused new Doppler config/keys. First
prove no consumer was started and preserve required evidence. Do not delete shared
prd, unrelated credentials or the initial-administrator secret merely because it
has not yet been consumed. Secret cleanup failure is manual intervention.

The controller result distinguishes Doppler state, host injection state, overall
acceptance and temporary-payload cleanup. No accepted-runtime identity changes.

## Image loading and application configuration qualification

This is preparation for stage 5, governed by
[the deployment plan](NAUTOBOT_DEPLOYMENT_PLAN.md). It grants no live execution.
Image loading is archived and the active operation slot is clean. Prepare one executable operation at a time:
image loading first, then configuration/authentication qualification. Production
runtime, administrator bootstrap and Restic remain separate stages.

### Image loading and application configuration qualification — Bound inputs and retained evidence

| Input | Source and interpretation |
| --- | --- |
| Target and account | Accepted host `j2-svpi4mf`; rootless `nautobot`, UID 999, GID 985, home `/var/lib/nautobot`. Revalidate before mutation. |
| Host and DNS provenance | `manifests/accepted-live-state.yaml`; stage-3 and stage-4 terminal tags. |
| Custom image | `manifests/qualified-image.json`; verify the annotated tag, peeled commit, terminal evidence and OCI archive hashes. |
| Runtime reference | `manifests/runtime-inputs.json`; immutable local repository/manifest-digest reference, not merely an image ID. |
| Database/cache images | The exact PostgreSQL and Redis references in `manifests/desired-state.yaml`; no mutable tags or automatic upgrades. |
| Credential provenance | `manifests/provisioned-credentials.json` and its archived `credential-result.json`; injection passed, authentication remains untested. |
| Secret source | Doppler `homelab-dev/prd_nautobot`; reference names in `credential-preparation.json`. No values or value hashes in bundles/evidence. |
| Settings and runtime definitions | `ansible/templates/runtime/nautobot_config.py`, runtime templates and `ansible/scripts/render-runtime.py`. |

The qualified OCI archive is currently retained at
`/var/tmp/nautobot-image-fac478c529ba/work/image.oci.tar` on the target, with a
controller copy under
`/home/aaron/code/.local-evidence/nautobot-image-retry-20260921/execution/`.
Its expected size is 348927488 bytes; obtain its expected digest from the
qualified-image manifest rather than duplicating it in an execution script.
Neither archive presence nor the isolated build store proves runtime-store loading.

### Image loading and application configuration qualification — First operation: load and verify runtime images

The implementation is `ansible/playbooks/load-images.yaml`, with the thin
`ansible/scripts/load-images.py` frozen-bundle launcher and node watchdog. The bundle must
include the operation/schema, desired state, qualified image and credential
provenance, accepted host identity, playbook, validators, tests and this procedure.
Bind the exact command and SHA-256 before live approval. The runtime deployment
launcher is not part of this image-only operation. Preparation and verification
are local; only execute contacts the target.

```text
python3 Nautobot/ansible/scripts/load-images.py prepare /tmp/NEW_BUNDLE
python3 /tmp/NEW_BUNDLE/launcher.py verify /tmp/NEW_BUNDLE EXACT_SHA256
python3 /tmp/NEW_BUNDLE/launcher.py execute /tmp/NEW_BUNDLE EXACT_SHA256
```

1. Verify Git provenance and render the current runtime inputs locally. Recheck
   target boot, account, home, user manager, storage health, free space and absence
   of application containers, Quadlets, networks and durable volumes. Expect the
   already-provisioned Redis secret and seven runtime files; their existence is
   required, not a first-install conflict. Verify their permissions and settings
   hash without printing secret content. Record the existing image inventory.
2. Verify the remote archive is a regular readable file with the exact size and
   SHA-256. Stop on changed boot, identity, conflicting objects or integrity drift.
   Run rootless commands from `/`, with the approved account HOME and runtime
   directory. Do not inherit the SSH user's private working directory.
3. Load the custom OCI archive into the account's default store. Independently
   verify its config ID, manifest digest and ARM64 platform, then assign
   `localhost/nautobot-homelab:qualified` as the local repository alias. The alias
   enables lookup by the existing immutable Quadlet reference; deployment never
   uses the tag. Pull only the
   two immutable PostgreSQL and Redis references selected by desired state.
   No container, database, migration or application service starts in this stage.
4. Independently inspect all three images: Linux/ARM64, expected image/config
   identity and manifest digest. Prove that the exact references rendered into
   the Quadlets resolve in the default store with pulling disabled. If the loaded
   archive lacks the expected local digest reference, stop and investigate;
   substituting an image ID or mutable tag is not an accepted repair.
5. Compare before/after inventory, prove no application containers/services or
   credential changes, and review cursor-bounded storage/kernel events through
   at least 75 seconds after the final image operation. Command success alone
   does not pass storage stability. Preserve stage outcomes and evidence hashes.

Each image command runs as UID 999/GID 985 in its own system service, with
2 CPUs, 3 GiB memory, no swap and a 900-second maximum runtime. Before Podman
executes, the child verifies its actual cgroup limits. Image transfer starts no
container and needs no Buildah child-cgroup layout. The root watchdog samples
every five seconds; a gap over 15 seconds, temperature at 80 C, nonzero throttling,
less than 1.5 GiB available memory, less than 20 GiB free storage, changed boot
or a new storage/OOM event stops the unit and fails the stage. Every command,
including alias assignment, has at least 75 seconds of post-exit observation.
There are no automatic pull retries; the target must still report Podman 5.4.2.
See the [version-specific pull options](https://docs.podman.io/en/v5.4.2/markdown/podman-pull.1.html).

Local qualification loaded the actual ARM64 OCI archive into an isolated VFS
store and verified the alias plus exact digest lookup without running containers.
The measured image sizes are 932916896 bytes (custom), 483627015 bytes
(PostgreSQL) and 138656332 bytes (Redis), about 1.45 GiB combined before
layer sharing.
The archive has 932898304 bytes of uncompressed layer tar data. Local dependency
pulls measure the selected immutable images; the 20 GiB floor deliberately
reserves ample room for extraction and partial-transfer residue. The workstation
Podman is older and lacks the retry option: its local qualification omits that
flag, while target execution explicitly disables retries. This local test does
not qualify target overlay storage, user/systemd behavior or current host health.
Those are fail-closed live preconditions/postconditions.

On a pre-mutation failure, stop. After a partial load/pull, inventory and retain
images for review; do not retry automatically or prune shared storage. An exact
removal rollback is possible only for newly introduced, unreferenced image IDs
whose before/after ownership is proven and whose removal was included in scope.
The implementation performs no image removal. Retain the operation-owned source
and evidence directory and inactive/failed transient units for review; this
explicit residue is not claimed as cleanup. The private controller snapshot is
removed after collection, and cleanup failure prevents acceptance. Do not delete
the qualified archive, build stores or credentials. Acceptance is
image-store readiness only, followed by terminal archival before the next stage.

### Image loading and application configuration qualification — Qualification handoff

After image-store acceptance and archival, use the disposable configuration and
authentication procedure below. Image loading alone proves neither application
readiness nor any later pilot acceptance gate. Consult the roadmap for current
progress rather than interpreting this operation's limited acceptance as absence
of separately accepted later work.

### Image loading and application configuration qualification — Metadata compatibility

The existing secret is enumerated by the explicit Go name template, then inspected
as JSON without secret contents. `secret ls --format json` is not a JSON shortcut
on the target: it emits the literal template text for each existing secret.
Malformed results and extra/missing secret names stop the operation.

The unused default Podman network reports a newly synthesized `created` timestamp
on repeated read-only queries. Continuity compares every returned configuration
field except that timestamp. Subnets, IDs, interfaces and flags remain checked.
Preflight failures retain a bounded error-code record without raw private output.

## Disposable configuration and authentication qualification

This stage follows archived image-store readiness and qualifies native
configuration plus positive PostgreSQL/Redis connections in a disposable scope.
It requires separate exact-bundle authorization. Negative security checks do not
gate positive readiness and remain separately scoped. Current outcomes and their
terminal identities belong in manifests and HISTORY, not this procedure.

### Disposable configuration and authentication qualification — Prepared checks and provenance

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

### Disposable configuration and authentication qualification — Isolated execution design

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

### Disposable configuration and authentication qualification — Acceptance matrix

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

### Disposable configuration and authentication qualification — Completion and recovery boundary

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

### Disposable configuration and authentication qualification — Freeze, review and execute

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

### Disposable configuration and authentication qualification — Failure diagnostics and retry preparation

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

### Disposable configuration and authentication qualification — PostgreSQL socket mount and Podman inspect

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

### Disposable configuration and authentication qualification — Initialization prerequisites and safe startup diagnostics

The pinned Nautobot CLI calls `_preprocess_settings()` before handing off to
Django. This creates GIT_ROOT, JOBS_ROOT, MEDIA_ROOT (and two subdirectories),
and STATIC_ROOT. Those default directories under `/opt/nautobot` are absent from
the pinned image. A read-only container root requires the bounded disposable mounts described below;
do not introduce production volumes or cover the entire application home, including
its user-installed dependencies, with an empty mount.

This is a source-established prerequisite. [Django initialization](https://docs.djangoproject.com/en/5.2/ref/applications/#initialization-process)
then loads settings/logging and populates the application registry before shell
execution. Successful container readiness does not prove those stages completed.

The stderr observer retains only allowlisted exception classes, fixed traceback
source labels with line numbers, and fixed filesystem errno categories. Unknown
paths, source lines and exception messages are discarded. Output remains bounded;
no traceback locals, credentials, connection URLs or arbitrary exception text
are saved. The diagnostics distinguish framework startup from structured probe
rejection but never substitute for authentication or cleanup acceptance.

### Disposable configuration and authentication qualification — Bounded startup-directory mounts

The trial mounts `/opt/nautobot/git`, `/opt/nautobot/jobs`,
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

### Disposable configuration and authentication qualification — PostgreSQL attempt diagnostics

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

## Isolated pre-data backup and restore verification

### Isolated pre-data backup and restore verification — Status and purpose

This is the reviewed successor contract after the Nautobot Restic repository
has been initialized and accepted. It is not an active operation and grants no
authorization. See [next-stage preparation](ROADMAP.md) for
separately reviewed upload/integrity and isolated-restore execution stages;
the [upload/integrity procedure](OPERATIONS.md#canary-backup-and-full-integrity-check) and
[isolated-restore preparation](OPERATIONS.md#isolated-canary-restore) retain this contract.
Current acceptance and the sole active operation are indexed in the roadmap.

The verification uses a deterministic canary beneath an operation-owned source
directory on `j2-svpi4mf`. It proves upload, full repository data checking,
exact-snapshot selection, and restoration into a new empty directory before
Nautobot data is entrusted to the storage path. It does not prove recovery of
PostgreSQL, media, application configuration, or a running Nautobot instance.

### Isolated pre-data backup and restore verification — Required predecessor state

Do not activate this contract until a terminal repository-initialization record
provides the exact repository ID, format version, initializer identity, and
accepted secret references. The independent repository-password recovery
location must remain confirmed.

The future operation must also retain the accepted Backblaze B2 S3 transport
identity from tag `backblaze-b2-s3-compatibility-v1-completed` and use the
shared Restic procedures.

### Isolated pre-data backup and restore verification — Dataset and workflow

Create unique source and restore roots beneath
`/var/lib/nautobot/backup-restore-tests/`, owned by the `nautobot` execution
user with directory mode `0700` and file mode `0600`. Require the source and
restore roots to reside on `/dev/sda2`.

The deterministic file is `predata/canary.txt`, containing exactly:

```text
nautobot isolated backup restore verification v1
```

Its SHA-256 is
`0b8fefbdc586f053d6e69ee230d119d668e2dc7f4739fe61a334227d61142de2`.

The operation must:

1. verify the exact repository ID, Restic version, execution identity, and
   secret references;
2. record source-tree hashes and the pre-backup snapshot-ID set as JSON;
3. create one backup tagged `nautobot-predata-canary-v1`;
4. record the post-backup snapshot-ID set and require exactly one new matching
   full snapshot ID;
5. run `restic check --read-data`;
6. restore that exact snapshot ID into a new empty owned directory;
7. compare the restored tree with independently defined paths, modes, and
   hashes; and
8. inspect cursor-bounded focused storage events and preserve bounded sanitized
   evidence.

Do not select `latest`. Do not restore over the source or a live path. Do not
automatically forget, prune, repair, unlock, delete, or clean up the remote
snapshot. Retain it and the evidence for review after any post-upload failure.

### Isolated pre-data backup and restore verification — Acceptance boundary

Acceptance proves only the pre-data storage gate. The Nautobot pilot must later
perform an isolated restore of the real PostgreSQL dump, media, configuration,
image and dependency manifests, Quadlets, and migration state before platform
or authority acceptance.

## Canary backup and full integrity check

### Canary backup and full integrity check — Prepared scope

The active operation defines the upload/integrity portion of
[isolated pre-data verification](OPERATIONS.md#isolated-pre-data-backup-and-restore-verification). Initialization
is accepted and archived; this definition binds its exact repository ID and
terminal result. It does not initialize a repository or exercise application data.

The Ansible execution path is implemented and locally validated. The operation
is eligible for exact-bundle approval; its readiness booleans do not grant live
authorization. Existing initialization and absence launchers reject its stage.

- Launcher: `Nautobot/ansible/scripts/run-canary-backup.py`.
- Playbook: `Nautobot/ansible/playbooks/backup-canary.yaml`.
- Node boundary: `restic/scripts/canary-backup.py`.
- Tests: `restic/tests/test_canary_backup.py`, run by CI and pre-commit.

The launcher reuses protected credential delivery, bounded capture and cleanup.
It verifies archived initialization bytes and tag, baseline/provider hashes,
clean source and exact approval hash before resolving credentials. Use `show-hash`
to obtain the frozen identity, then `execute APPROVED_SHA256` only after approval.
The private approval packet records the exact reviewed hash and command.

### Canary backup and full integrity check — Execution

Use the existing protected credential-delivery and bounded-output utilities.
Ansible owns target preflight, staging, ordered commands, evidence retention and
independent cleanup attempts. The node helper retains durable upload intent and status across controller
interruption; it never retries upload or deletes repository data.

Target `ama@10.1.2.170`; run Restic as `nautobot`, with the exact accepted version
and existing Doppler references. Verify accepted repository ID/format before any
upload. Verify the source root is on `/dev/sda2`, with no symlink ancestors, and
check existing parent ownership/modes rather than silently changing them.

Create one unique `source.*` directory under
`/var/lib/nautobot/backup-restore-tests/`. Parent creation, when absent, belongs
in the reviewed operation after topology validation. Directories use `0700` and
the sole file uses `0600`. `predata/canary.txt` is exactly 49 bytes, including the
terminal newline; the manifest holds its fixed content and independent SHA-256.
Keep credentials, markers and evidence outside the uploaded source tree.

All Restic commands use `--no-cache` and protected repository/password files.
The command arrays in `manifests/operation.yaml` define the exact CLI shape:

1. Verify config, user/version, source mount and boot ID; capture a kernel journal
   cursor before source creation or workload commands.
2. Create the exact source tree; record independent path, size, mode and hash checks.
3. Capture the complete `snapshots --json` result before backup.
4. Record upload intent, then run one `backup --json --host j2-svpi4mf` with tag
   `nautobot-predata-canary-v1` and the exact source root. Keep normal locking.
5. Persist exit status before assertions. Capture the after snapshot set, including
   after an unsuccessful upload when read-only classification remains possible.
6. Require exit 0, preservation of prior IDs, exactly one new full 64-character ID,
   and matching hostname, exact source path and tag. Backup summary/display order
   is not authoritative. Exit 3 means incomplete backup and blocks acceptance.
7. Run `check --read-data` with normal locking and require exit 0. A default or
   subset check cannot satisfy this gate.
8. Recheck the source tree and boot ID; retain a 75-second delayed observation
   window. Review the complete cursor-bounded kernel storage events. Missing,
   truncated or ambiguous evidence prevents acceptance.
9. Verify empty lock listing and no cache; attempt all credential removals
   independently, verify absence, and retain sanitized evidence.

Command bounds are 600 seconds and 4 MiB per stream, with a 1500-second node
workload deadline and an 1800-second controller limit. Do not increase bounds or retry upload silently. A timeout requires retained
state review, including potentially still-running remote work and cleanup status.

### Canary backup and full integrity check — Acceptance and recovery

Record upload attempted/result, exact new snapshot ID, full integrity result,
storage observations and cleanup separately. Retain source and snapshot for the
next stage. There is no automatic rollback of uploaded repository objects.
Any upload or integrity failure retains evidence; do not delete, forget, prune,
unlock, repair or rerun backup automatically. Do not run integrity checking after
an unsuccessful upload until that outcome has been reviewed.

This stage cannot accept restoration or application recovery. Its successor uses
the accepted full snapshot ID and a new empty `restore.*` directory under the
same approved parent, with separately reviewed authorization and tree comparison.

### Canary backup and full integrity check — Implementation validation

The offline suite exercises the actual helper, launcher gates and Ansible cleanup:

- Reject identity, version, source topology, file-content and bundle mismatch
  before upload or credential access where applicable.
- Handle zero/multiple new snapshots, missing prior IDs, wrong host/path/tag,
  malformed JSON and shortened IDs without selecting a snapshot.
- Treat upload status 3, interrupted upload and failed full check as unaccepted;
  preserve attempted mutation and never retry or delete automatically.
- Exercise cleanup on success, early failure, failure after upload and first-file
  removal failure; later secret removals and evidence retention must still run.
- Reject missing/truncated journal evidence, boot changes, storage errors and
  unavailable cleanup proof. Test delayed-window and command timeout handling.

Tests run through the existing local validation entry point and CI hooks.
Ansible syntax, schemas and secret scanning are checked before freezing inputs.
No live backup or target inspection occurred during implementation. ARM64 Restic
behavior, source-parent permissions and kernel journal access remain live checks
under the approved execution path. Missing evidence cannot be accepted.

CLI references: [snapshot JSON and scripting](https://github.com/restic/restic/blob/master/doc/075_scripting.rst),
[backup flags and exit statuses](https://github.com/restic/restic/blob/master/doc/manual_rest.rst),
[full-data check implementation](https://github.com/restic/restic/blob/master/cmd/restic/cmd_check.go).
The target's accepted 0.18.0 help is the final authority during authorized preflight.

## Isolated canary restore

### Isolated canary restore — Prepared scope

This is the restore portion of [pre-data verification](OPERATIONS.md#isolated-pre-data-backup-and-restore-verification).
The single active operation binds the accepted canary archive, repository ID and
full snapshot ID. The implementation is locally qualified; live execution still requires the
exact frozen bundle hash. No live restore has run.

The operation uses the recorded full snapshot ID and its exact source directory,
never `latest`, a shortened ID or a tag filter as a substitute for identity.
Before restoration, read repository config and exact snapshot metadata; compare
repository ID/format, hostname, paths and tags with the archived acceptance.
Use existing credential references, with no secret creation or rotation.

### Isolated canary restore — Destination and command

Ansible will create a new empty directory named `restore.*` beneath the existing
`/var/lib/nautobot/backup-restore-tests/` parent. Require `nautobot` ownership,
mode `0700`, no symlink ancestors and filesystem `/dev/sda2`. Verify resolved
paths cannot overlap the original source or any live-data path. Never reuse an
existing destination, even after a failed attempt.

The command is defined as an argument array in `manifests/operation.yaml`:

```text
restic --no-cache --repository-file PROTECTED_REPOSITORY_FILE \
  --password-file PROTECTED_PASSWORD_FILE \
  restore FULL_SNAPSHOT_ID:EXACT_ARCHIVED_SOURCE_ROOT \
  --target NEW_EMPTY_RESTORE_ROOT
```

`FULL_SNAPSHOT_ID` and `EXACT_ARCHIVED_SOURCE_ROOT` are immutable operation values;
only the unique destination is allocated during execution. The subdirectory
selector restores its contents directly beneath the destination, avoiding an
extra absolute-path hierarchy. It selects the entire backed-up canary source;
no include/exclude filters are needed. Keep ordinary restore locking enabled.

Record restore intent before invocation and exit status before comparison.
Do not pass `--delete`, restore into the original source, or clean up repository
objects. An earlier successful backup/integrity check does not prove restoration.

### Isolated canary restore — Independent comparison and observation

Require exactly this destination tree:

| Relative path | Type | Mode | Size/content |
| --- | --- | --- | --- |
| `predata` | Directory | `0700` | No extra descendants |
| `predata/canary.txt` | Regular file | `0600` | 49 bytes including the final newline |

All restored objects must belong to `nautobot`; reject extra paths, symlinks and
special files. The file must equal the fixed manifest content and SHA-256
`0b8fefbdc586f053d6e69ee230d119d668e2dc7f4739fe61a334227d61142de2`.
Derive these expectations from the reviewed definition, not the restored output.
Also verify the retained original source before and after; source equality alone
is insufficient if both copies differ from the independent fixture.

Capture the boot ID and kernel journal cursor before the workload. Preserve the
existing 75-second delayed storage observation, cursor availability and complete
bounded event review. Require no storage errors, unchanged boot/source, empty
final locks and no cache. Reuse the canary journal and protected-file routines
where practical; do not duplicate another deployment framework.

### Isolated canary restore — Failure, cleanup and acceptance

Use Ansible for staging, commands, evidence and cleanup. A small helper may own
durable restore-attempt/status and exact tree comparison. Bound commands to
600 seconds, streams to 4 MiB and controller work to 1800 seconds. The helper
limits its command sequence to 1500 seconds; a command timeout terminates and
waits for that child. A controller interruption cannot prove remote termination:
retain the intent and node evidence, classify the outcome as unknown, and inspect
the remote process before any separately authorized retry.

Remove each transient credential independently on success or failure and verify
absence. Retain the source, snapshot, partial or complete restore directory and
sanitized records. Failed restore/comparison, interruption or unknown cleanup
requires review; never retry automatically into the same or a new destination.
No rollback deletes repository objects or live data.

Acceptance requires successful restore, exact independent tree comparison,
source/boot continuity, quiet storage observation and proven credential cleanup.
Combined with the archived upload/full-data check, it can satisfy the pre-data
canary gate. It cannot accept application recovery, PostgreSQL restore, runtime
persistence, resource headroom or authority migration.

### Isolated canary restore — Implementation and local validation

The reusable playbook is `../ansible/playbooks/restore-canary.yaml`; its launcher
is `../ansible/scripts/run-canary-restore.py`. The launcher verifies both terminal
archives, source cleanliness and the approved hash before secret resolution.
`restic/scripts/restore-canary.py` reuses the existing canary journal, protected
file and comparison routines. Offline tests exercise:

- Wrong repository/snapshot identity, missing predecessor or unapproved hash.
- Existing/nonempty targets, symlink ancestors, source overlap and wrong mount,
  owner or modes; each must stop before restore.
- Failed/interrupted restore and missing exit evidence, retaining partial data.
- Missing/extra paths, corrupt bytes, wrong modes, owners, symlinks and special
  files; no comparison may derive expectations from its own output.
- First credential-removal failure, later cleanup continuation, evidence retention,
  journal gaps/truncation, boot changes, storage errors and timeout handling.

Tests are wired into the existing validation entry point and pre-commit hooks. Validate target
Restic CLI behavior through the separately authorized execution preflight.
No target contact, restore or repository mutation occurred during preparation.

Reference: [Restic subdirectory restore](https://github.com/restic/restic/blob/master/doc/050_restore.rst).

### Isolated canary restore — Execution approval

From the server repository, the separate live command is:

```sh
python3 Nautobot/ansible/scripts/run-canary-restore.py execute APPROVED_SHA256
```

`show-hash` checks the clean definition and predecessor archives without remote
access. Manifest readiness and `mutation_authorized: true` describe the eligible
execution path; `approval_record` remains ungranted until the operator approves
that exact digest. Neither field grants authorization on its own.

The authorized mutation is one isolated restore plus ordinary transient Restic
locks and protected evidence/credential staging on the single target. No backup,
repository initialization, destructive cleanup or application deployment is
included. Success still requires review of node records, delayed storage review
and controller/remote credential absence before recording acceptance.

## Private runtime initialization

This procedure implements only PostgreSQL, Redis and the migration stage from
[the governing plan](NAUTOBOT_DEPLOYMENT_PLAN.md). The active operation binds the
accepted host, images, credentials, positive configuration readiness, repository
initialization and completed canary backup/integrity/restore archives. No new
negative authentication or SQLSTATE requirement is introduced.

### Private runtime initialization — Scope and inputs

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

### Private runtime initialization — Native initialization and resource bounds

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

### Private runtime initialization — Acceptance and recovery

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

### Private runtime initialization — Local validation and execution

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

### Private runtime initialization — Recovery from partial initialization

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

### Private runtime initialization — Retained-database inspection bundle

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

### Private runtime initialization — Prepared continuation of retained migrations

The continuation is implemented as an explicit branch of `run-runtime.py` and
`deploy-runtime.yaml`, with `continue-runtime-tasks.yaml` owning orchestration.
The strict `runtime-continuation.schema.json` binds the active candidate.
Preparation and tests are local; execution still requires its exact bundle approval.
Use the accepted inspection in [history](../HISTORY.md) and its tagged result as
the prerequisite; do not infer initialization acceptance from that result.

#### Private runtime initialization — Inputs and preservation

Bind the existing accepted image IDs, configuration, secret references, installed
unit hashes, named-volume paths and original boot identity. Retain the original
PostgreSQL and Redis volumes and the independently verified protected cold copies.
Before any startup, verify both services and migration are stopped, no container
writers exist, and the cold-copy content/metadata still match the inspection
record. Original PostgreSQL files can legitimately differ from the pre-start copy
after the inspection startup; do not require original/copy equality now.
Unexpected writers, changed identity, a missing copy or a changed copy stop work.
No fresh database, volume replacement, secret rotation or automatic restore.

#### Private runtime initialization — Native sequence and progress

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

#### Private runtime initialization — Bounds, acceptance and recovery

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

#### Private runtime initialization — Implementation and validation before approval

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

#### Private runtime initialization — Candidate execution and residual files

The retained continuation implementation uses the 1800-second native, 1860-second migration-unit,
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

## Administrator bootstrap and application startup preparation

The [deployment plan](NAUTOBOT_DEPLOYMENT_PLAN.md) owns the stage-5 architecture.
This specification prepares two sequential operations. It does not authorize host
contact, credential resolution, administrator creation, application startup or
network changes. Preserve the consumed operation until terminal publication is
verified; then keep the slot clean until the next implementation and exact bundle
are ready. Archive each completed operation before defining the next. The [roadmap](ROADMAP.md) and [history](../HISTORY.md) own current results.

### Administrator bootstrap and application startup preparation — Administrator bootstrap prerequisite

#### Administrator bootstrap and application startup preparation — Prerequisites and scope

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

#### Administrator bootstrap and application startup preparation — Native sequence

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

#### Administrator bootstrap and application startup preparation — Bounds, failure and acceptance

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

#### Administrator bootstrap and application startup preparation — Execution entrypoint and evidence

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

### Administrator bootstrap and application startup preparation — Application startup handoff

After bootstrap is accepted and archived, use the startup baseline, preservation
and execution procedures below. Verify the network-owner handoff and effective
backend guard before opening a listener. Startup uses its own launcher and exact
bundle, not the initialization or bootstrap launcher. Remaining pilot gates are
owned by the master plan and current roadmap.

## Startup baseline and recovery preparation

This procedure defines bounded read-only review for `ama@10.1.2.170`. Use HISTORY and accepted manifests for prior baseline and preservation results. A newly prepared startup operation requires separate exact-bundle execution approval.

### Startup baseline and recovery preparation — Baseline collection

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

### Startup baseline and recovery preparation — Recovery review

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

### Startup baseline and recovery preparation — Startup execution inputs and evidence

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

### Startup baseline and recovery preparation — Concrete probe implementations

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

Use terminal preservation records and a freshly reviewed baseline; old baseline
hashes and observed capacity are historical inputs, not current recovery proof.
See [startup execution](#application-startup-execution) for the assembled contract.

## Startup database preservation

This separate operation prepares recovery for the initialized database and admin.
It never starts PostgreSQL, Redis, migration or application services.

Target: `ama@10.1.2.170`. Source volumes are the rootless Nautobot PostgreSQL and
Redis volumes below `/var/lib/nautobot/.local/share/containers/storage/volumes/`.
The new copy is `/var/lib/nautobot/recovery/nautobot-startup-database-preservation-v1/`.
A partial or existing destination stops execution; it is not overwritten or reused.

The playbook stages the existing preservation helpers into a new root-owned
mode-0700 `/tmp/nautobot-inspection.*` directory. The helper verifies boot, image,
configuration, Quadlet and account identities; stopped services; absent containers;
fixed volume paths; no nested mounts or external links; PostgreSQL 17 and no
postmaster PID; and sufficient capacity. It copies both trees preserving metadata,
then compares source-before, source-after and destination manifests including
content hashes, ownership, permissions, timestamps, xattrs and hard-link topology.
It rechecks stopped state and identities before producing a success record.

No deletion, service start, data restore, package update, network change or reboot
is included. Failure retains the incomplete private destination and evidence for
review. Recovery means retaining the original untouched volumes; never delete them
to undo a failed copy. Restoring a preserved copy is a separate reviewed action,
with all services stopped and the existing volume preserved before replacement.
A verified copy is not an exercised restore and does not replace Restic acceptance.

The reviewed definition is `manifests/startup-preservation.yaml`; freeze with
`python3 Nautobot/ansible/scripts/freeze-preservation.py /tmp/NEW_BUNDLE_DIRECTORY`.
The output hash covers the exact playbook, helpers, operation, inventory and review.
After explicit hash approval, execute the frozen `run-preservation.py HASH`.
Keep the preservation result and remote private evidence; archive before advancing
the active operation. Refresh the startup baseline after preservation and before
startup, since the launcher enforces freshness. Startup itself remains unauthorized.

## Application startup execution

This operation starts the single-host pilot using the accepted initialized database
and existing administrator. The master deployment plan still governs workload,
reboot persistence, Caddy onboarding and application-aware backup/restore acceptance.
None of those later stages is accepted by this startup check.

### Application startup execution — Preconditions and authorization

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

### Application startup execution — Mutation and checks

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

### Application startup execution — Success, failure and recovery

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

### Application startup execution — Failed configuration checks

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

### Application startup execution — Writable metrics cache

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

### Application startup execution — Initialization and readiness evidence

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

### Application startup execution — Explicit logging and server configuration

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

### Application startup execution — Session identity timing and failure evidence

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

### Application startup execution — Worker heartbeat and resource-command diagnostics

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
