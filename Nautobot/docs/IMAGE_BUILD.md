# Bounded ARM64 image qualification

This procedure owns image qualification only. The deployment plan remains the
architecture authority; the roadmap records current readiness. Preparation does
not authorize host changes. Execute only after explicit approval of the complete
bundle digest printed by `prepare-image-build.py prepare NEW_DIRECTORY`.

## Scope and entrypoints

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

## Limits, isolation and observation

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

## Image checks and acceptance boundary

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

## Failure, retained state and cleanup

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

## Validation and references

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

## Retrying a mutation-bearing failure

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
