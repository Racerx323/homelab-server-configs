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
