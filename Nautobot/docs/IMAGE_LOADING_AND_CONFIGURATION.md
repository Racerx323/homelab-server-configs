# Image loading and application configuration qualification

This is preparation for stage 5, governed by
[the deployment plan](NAUTOBOT_DEPLOYMENT_PLAN.md). It grants no live execution.
The active operation remains clean. Prepare one executable operation at a time:
image loading first, then configuration/authentication qualification. Production
runtime, administrator bootstrap and Restic remain separate stages.

## Bound inputs and retained evidence

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

## First operation: load and verify runtime images

Implement an Ansible playbook with a thin frozen-bundle launcher. The bundle must
include the operation/schema, desired state, qualified image and credential
provenance, accepted host identity, playbook, validators, tests and this procedure.
Bind the exact command and SHA-256 before live approval. No executable load bundle
exists yet; the existing runtime deployment launcher must not be used as a shortcut.

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
3. Load the custom OCI archive into the account's default store. Pull only the
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

Before freezing the bundle, measure archive/pull storage requirements and select
finite per-command timeouts and resource guards using the accepted host headroom.
Reuse the qualified delegated cgroup placement where a scoped service is needed;
do not change the user slice or silently allow unlimited fallback. Test timeout,
wrong architecture, digest mismatch, absent local reference, partial pulls,
existing-object conflict, storage errors and evidence/cleanup failure offline.

On a pre-mutation failure, stop. After a partial load/pull, inventory and retain
images for review; do not retry automatically or prune shared storage. An exact
removal rollback is possible only for newly introduced, unreferenced image IDs
whose before/after ownership is proven and whose removal was included in scope.
Do not delete the qualified archive, build stores or credentials. Acceptance is
image-store readiness only, followed by terminal archival before the next stage.

## Second operation: configuration and authentication checks

Prepare this only after image-load acceptance. Use the real loaded ARM64 images
and production settings template. General `start --help` output from the image
build is not proof that settings, plugins, commands or authentication work.

The proposed qualification environment is disposable: uniquely named rootless
containers and private network, no published ports, no production volume names,
and bounded disposable database/cache storage. Review resource ceilings, maximum
duration and cleanup before activation. The network must provide the `postgresql`
and `redis` aliases expected by the actual settings. No worker, scheduler, Job,
production migration or administrator bootstrap runs here.

| Check | Required evidence |
| --- | --- |
| Settings import | Execute the installed Nautobot configuration loader with the actual injected settings. Check database/cache targets, secret presence, allowed hosts, CSRF/proxy settings and disabled installation metrics using boolean/non-secret output only. |
| Plugin registration | Django setup registers DNS Models at the qualified version without settings/import errors. Report plugin name/version only. |
| PostgreSQL authentication | Using the application's real settings and an explicit TCP connection, the configured role connects to the disposable database and completes a harmless query. A separate incorrect-password attempt is rejected for authentication, not connectivity. Local socket trust and readiness probes alone do not prove this. |
| Redis authentication | The actual mounted Redis configuration requires authentication. The configured application connection succeeds; missing and incorrect passwords fail authentication. Exercise both cache and broker database selections. Never put passwords in argv or reports. |
| Service command contract | Inspect the installed command parser and validate the exact web/worker/scheduler arguments used by templates. Commands that require migrations or running services remain explicitly unproven until their owning stage. |
| Isolation and cleanup | No published ports, production volume/data writes, bootstrap password injection or production service activation. All disposable objects and temporary secret-bearing inputs are accounted for; failure to clean prevents acceptance. |
| Host continuity | Effective resource limits, unchanged boot, no OOM/throttling or storage errors, and at least 75 seconds of post-exit observation with recorded coverage. |

Use private Ansible tasks and bounded private controller capture for credentials;
do not expose environment dumps, Redis configuration, connection URLs, raw
exceptions or logs containing values. The initial administrator password stays
in Doppler throughout. Use operation-owned protected temporary paths or private
stdin as appropriate, with checked cleanup even if an earlier cleanup task fails.

The executable contract must distinguish a settings failure, authentication
rejection, unavailable service, timeout, storage fault and cleanup residue.
Stop further tests on a storage error. Preserve sanitized evidence and restore
only operation-owned disposable objects; never rotate credentials or delete
production state automatically. Test these failure paths before live approval.

## Remaining production gates

Passing these checks does not initialize or accept the production database.
Restic repository initialization and the pre-data backup/integrity/isolated-restore
canary remain required before entrusting application data to storage. Production
deployment still needs its executable stage contract, application firewall
evidence, migration/startup validation, one-time administrator bootstrap, dual-stack
health, effective limits, logout/reboot persistence, workload headroom, full
application recovery and the required stable pilot period. Caddy onboarding is
owned separately. See [the roadmap](ROADMAP.md) for plan-stage numbering.
