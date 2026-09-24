# Nautobot operator procedures

The [deployment plan](NAUTOBOT_DEPLOYMENT_PLAN.md) owns architecture and the
[roadmap](ROADMAP.md) owns progress and stage readiness. These procedures do not
authorize execution. Host convergence, boot recovery and package cleanup retain
their detailed procedures; this document covers runtime preparation and workload
qualification without duplicating their evidence.

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
See [credential preparation](CREDENTIAL_PREPARATION.md) for the selected Doppler
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
commands against the actual pinned custom image before pilot readiness. No image
build or ARM64 execution occurred during local template validation.

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
[bootstrap/startup preparation](BOOTSTRAP_AND_STARTUP.md) for implementation,
remaining activation work and the network-owner handoff. The startup policy is
inactive and the current runtime launcher does not accept this stage. Do not use
initialization or bootstrap as a substitute startup command.

## Runtime deployment boundary

`ansible/playbooks/deploy-runtime.yaml` and `ansible/scripts/run-runtime.py` now
implement only the [private initialization stage](RUNTIME_INITIALIZATION.md):
PostgreSQL, Redis and migration. The active strict contract binds terminal
prerequisite records and exact rendered artifacts. It requires separate approval
of the final bundle hash before any target command. Do not bypass that gate with
manually asserted Ansible variables.

The path verifies current identities and first-install absence, starts only the
selected services, performs native migration checks and preserves sanitized
stage and journal evidence. It excludes web, worker, scheduler, administrator
bootstrap and host-published ports. Full application startup remains a separate
future operation with its own exposure and recovery criteria.
[Administrator bootstrap and application startup](BOOTSTRAP_AND_STARTUP.md)
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

## Workload qualification contract

`manifests/workload-test.yaml` defines an inactive stage-5 test, not a new operation.
`ansible/scripts/make-workload-fixture.py` produces deterministic JSON with ten
locations, 500 devices, four interfaces per device and 500 unique synthetic IP
assignments. The benchmark addresses are data only and must never be configured
on interfaces, exported to live DNS or used for network probes.

Before live readiness, implement/review import adapters and Job classes against
the pinned Nautobot API and required model references (location types, statuses,
roles, manufacturers/device types and namespace). The fixture is an intermediate
contract, not a claim of directly importable Nautobot API JSON. Use only a dedicated
fixture namespace and reject collisions with unowned data. Compare these counts
and the chosen Job cost with expected production scale; until then this is a
bounded synthetic test, not proven representative capacity.

Run two imports (second must be idempotent), three canonical exports with identical
hashes, and ten read-only audits at worker concurrency two. Audits check counts,
interface ownership and assignments, with no external network calls or writes.
Exports omit generated IDs/timestamps and sort by natural keys. Preserve the
created-object ownership manifest for separately authorized cleanup.

The workload phases are 15 minutes idle baseline, at least 15 minutes import/export,
at least 30 minutes Jobs overlapping a separately authorized real application
backup, 15 minutes idle recovery and 75 seconds of final delayed-error observation.
Minimum total coverage is 76 minutes 15 seconds; unfinished work extends phases,
subject to the three-hour total bound and 15-minute individual Job timeout.
Absent backup authorization makes the overlap phase incomplete; do not silently
replace it with a canary or accept the whole workload without it.

Sample every five seconds. A gap above 15 seconds or a boot change invalidates
continuity and stops test load. Preserve local evidence before collecting bounded
readback. Do not issue SMART/self-test commands as part of the sampler. Stop load
on any new storage reset/error, ext4 increment, OOM event, throttling, unexpected
service failure, Job error/timeout, MemAvailable below 1.5 GiB or temperature above
80 C. The first-temperature-sample stop is deliberately stricter than the plan's
sustained-temperature criterion.

The YAML defines swap-growth detection using 60-second medians and a 64 MiB noise
tolerance, plus a final five-minute recovery comparison. Treat missing metrics,
missing phase coverage or failed comparisons as incomplete/failed, never as zero.
Do not retune thresholds after seeing an unfavorable result without a reviewed
reason and a new comparison. Restore, direct-access restrictions, service
persistence and seven stable pilot days remain separate acceptance evidence.

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
this does not implement Jobs, sampling or live workload acceptance. Any contract
change must keep the manifest, schema, implementation and negative tests aligned.

Runtime first-install preflight rejects existing Nautobot container, network or
volume metadata, including residue left after unit removal. It never deletes those
objects; recovery or reuse requires a separately reviewed operation. Redis secret
metadata uses JSON, not nested template expansion. Secret contents are not read.

The historical backup/restore branch is now schema-enforced definition-only.
Its terminal prerequisites are defined below; they are not yet live accepted records.
Runtime activation still requires a reviewed stage schema; initialization still
requires reactivation of its frozen definition. Do not relax either gate merely to
make a launcher run. Future activation must encode terminal accepted host-baseline
and repository identities, exact ordered actions, acceptance criteria, rollback,
and all execution inputs in the bundle. No live authority is granted by these fixes.

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

Use [the bounded image-build procedure](IMAGE_BUILD.md) and its exact bundle
launcher. It stages one rootless build in an isolated store, under a delegated
limited service and independent watchdog. It does not activate runtime deployment
or production credential delivery. The single operation slot holds its definition;
external exact-hash approval is still required to execute. Keep the resulting OCI
manifest digest, archive checksum and image ID distinct. Loading into the runtime
store, settings/database qualification and runtime startup require later review.

## After credential injection

Use [image loading and configuration qualification](IMAGE_LOADING_AND_CONFIGURATION.md)
for the next bounded stages. Published credential provenance is in
`manifests/provisioned-credentials.json`. Image loading, disposable authentication
checks, production deployment and administrator bootstrap are distinct results.

The archived image-store identity is in `manifests/runtime-image-store.json`.
Use [configuration and authentication qualification](CONFIGURATION_AUTHENTICATION.md)
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

### Persistence procedure

Prepare logout and reboot as separate bounded stages, each with its own exact
inputs. No active operation is opened by this document.

| Stage | Required preparation | Acceptance and failure boundary |
| --- | --- | --- |
| Logout | Enumerate only operation-owned test login sessions; independent administrator connection; current user-manager/linger, unit invocation and restart baseline | Close only those sessions; observe five minutes from the independent connection with continued health, unchanged invocations/restarts and no collection gaps. Preserve evidence and stop if continuity fails. |
| Reboot | Confirm console recovery; fresh baseline; record pending kernel; freeze reconnect/readiness deadlines; preserve reviewed current database/media recovery inputs and a quiesced logical comparison | One authorized reboot; new boot ID, automatic service activation, matching persistent artifact identities, healthy logical data, limits, guard, both backend families and management/Munin access. Observe at least 75 seconds after readiness. No automatic repeated reboot or destructive restore. |

The concrete collector, session identities, readiness deadlines and current
recovery evidence still need preparation before either persistence bundle can be
frozen. Stage acceptance must distinguish daemon activation from proven data
persistence and must retain collection gaps or unexpected service restarts.

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

`ansible/scripts/run-workload.py --bundle DIRECTORY --approve SHA256 --evidence
NEW_DIRECTORY --backup-secrets PROTECTED_CREDENTIAL_DIRECTORY` is the candidate live entrypoint. Do not execute it without a
reviewed bundle and live authorization. `bundle.json` maps flat input filenames
and required repository-source paths to SHA-256 values; its exact bytes define
the approval hash. It binds the strict `workload-execution.schema.json` input,
validated contract JSON, deterministic dataset, Ansible playbook and all helpers.
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
