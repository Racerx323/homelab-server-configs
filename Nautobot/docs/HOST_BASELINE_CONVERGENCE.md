# Retained host-baseline convergence and acceptance

> **Definition only.** The active operation is unready. No live observations,
> host acceptance, correction, Restic initialization, or authorization hash have
> been produced by this definition. The deployment plan remains the sole
> architecture authority.

## Reviewed evidence and gaps

The annotated `nautobot-host-baseline-v3-manual-intervention` tag preserves
`Nautobot/manifests/terminal-evidence.yaml`: mutation converged, reboot occurred,
acceptance failed on privilege escalation after reboot, rollback did not run,
and lingering acceptance was not proved. Its post-failure qualification passed
package and unit checks, but storage failed. Never retry that operation.

The immediate diagnostic tag
`nautobot-storage-diagnostic-v2-baseline-healthy-soak-pending` and the subsequent
`nautobot-storage-soak-verification-v1-passed` tag preserve successful quirk,
USB-storage, SMART, ext4, power and 24-hour soak observations. The soak boot was
`af1ed3ab-0bdc-422a-b893-bc3ccd924fde`. Neither tag accepted the host baseline or
completed the isolated restore gate. The operator reports a reboot since that
validation; this is an operator statement, not a fresh live observation. Retain
the old soak as historical evidence. Fresh current-boot storage validation and
continuity review are required before convergence acceptance. The reviewed
current boot ID and evidence reference remain unresolved in the active manifest.
The preflight must start and end on that newly validated boot. Review whether
the reboot circumstances or fresh findings require another observation window;
do not silently reuse the old soak or automatically prescribe another reboot.

The active manifest carries the eleven exact v3 package versions. The current
plan additionally requires `needrestart`. Its owning repository component is
[`Needrestart/`](../../Needrestart/README.md); Nautobot observes the required
package version, while package and notification integration changes require
owner review. The owner documentation gives an unpinned Debian installation
procedure, not an accepted exact version for this host. Its stated Debian 12
requirements and Pi 5 kernel-filter example do not establish this Debian 13,
Pi 4 host's configuration. Do not run the owner installer, notification script,
mail test or copy its active Pi 5 kernel filter during this preflight.
The exact installed version remains unestablished by the reviewed records. The numeric account UID/GID and complete
listener endpoint allowlist are also unresolved. Null expectations deliberately
fail evaluation. Never derive an expected identity from the observation being
judged. Resolve these from independent retained evidence or a separately
approved collection followed by definition review. Missing packages or drift
do not authorize installation, downgrade, removal, or automatic repair.

Home must have the expected numeric owner, be a directory at
`/var/lib/nautobot`, and use mode 0700, 0750 or 0755 (no group/other writes).
The service account must have no supplementary groups, the nologin shell,
exact non-overlapping subordinate ranges, and lingering enabled. The collector
requires loginctl state `lingering`, so an active login session blocks the
logout-survival observation. No test container or user service is created.
Reviewed current-boot storage evidence plus the within-preflight boot check and
current rootless execution prove
only the retained baseline runtime capability. Future application services must
separately prove logout/reboot survival and representative resource criteria.

## Inactive Restic contract

`../manifests/deferred-restic-initialization.yaml` is a byte-for-byte copy of the
reviewed initialization definition at checkpoint
`c7bff00f5af7bb4c42a8d20dbf1d1152047d4a55`. It is an inactive dependency contract,
not a second pending operation. Its accepted B2 identity, seven-capability
provider reference, secret references, independent recovery locator, exact
Restic version, exit-status-10 absence result and evidence hashes remain intact.
The future restore operation schema now requires the same exact seven provider
capabilities, correcting its former generic four-action list.
The original bundle input paths are historical provenance; moving the contract
does not rebind that passed result to a new bundle.

The Restic execution launcher continues to load only `operation.yaml`. Its
active-operation gate rejects convergence before credential access. Offline
Restic validators use the inactive contract so they still exercise the reviewed
implementation. After terminal host acceptance and archival, explicitly review
reactivation into the one active slot, bind the accepted host identity, and
review fresh absence evidence before any separately authorized initialization.
Never treat the old absence observation as proof of current absence.

## Preflight execution contract

The collector is `../ansible/playbooks/preflight-host-convergence.yaml`; every
remote command uses the exact ordered argv catalog in the active manifest.
Noninteractive sudo, a 30-second command timeout and a five-second forced-stop
bound apply to each probe. Commands never run through a shell. Literal dpkg
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
current-boot focused faults absent, SMART zero warning/media/error counters,
clean ext4 metadata, zero live ext4 errors, temperature below 80 C and zero
throttling. Generic USB initialization and loading the UAS module are not faults.
SMART failure is blocking here because the retained bridge passed; accepting a
new bridge limitation would require explicit definition review.

The launcher exposes a local command preview:

```bash
python3 Nautobot/ansible/scripts/run-host-convergence.py show-command
```

Its `execute AUTHORIZED_SHA256` path rejects the present unready state before
hashing, evidence creation or transport. The frozen definition schema also
rejects readiness or acceptance edits until that schema is deliberately reviewed.
Before live execution, resolve expectations, review the complete execution
bundle and schema transition, checkpoint, then obtain separate read-only
approval. This document provides no live hash.

The launcher owns one mode-0700 `/tmp/nautobot-host-convergence.*` directory,
mode-0600 evidence and a mode-0700 `ansible-local` child. It bounds each process
stream to 4 MiB and total runtime to 20 minutes, records partial output on
failure, and removes only its verified temporary child. Raw observations stay
outside Git. An unreachable host leaves remote transport cleanup unproved and
cannot pass. Review module cleanup and Podman inspection side effects in the
live evidence; the launcher cannot prove remote cleanup merely from its own
local deletion. No cleanup removes retained evidence or baseline state.

## Terminal reconciliation and accepted identity

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
swap and workload temperature, network/firewall acceptance, Caddy onboarding,
authority migration and Semaphore remain separately gated. The plan is unchanged.

If drift appears, preserve evidence, stop, and define only the exact required
correction under separate authorization. No automatic full baseline replay,
package reinstall, rollback, service transition or reboot is present.

## Offline validation and next action

```bash
/bin/bash tests/repository/run-with-ansible-local-temp.sh \
  python3 Nautobot/ansible/scripts/validate-host-convergence.py
/bin/bash tests/repository/run-with-ansible-local-temp.sh \
  ansible-playbook --syntax-check --inventory inventory/prod/hosts.yaml \
  Nautobot/ansible/playbooks/preflight-host-convergence.yaml
check-jsonschema --schemafile Nautobot/schemas/operation.schema.json \
  Nautobot/manifests/operation.yaml
check-jsonschema --schemafile Nautobot/schemas/repository-initialization.schema.json \
  Nautobot/manifests/deferred-restic-initialization.yaml
```

The next separately authorizable read-only action is a fresh current-boot
storage diagnostic on `j2-svpi4mf`, including boot identity, quirk and root-device
binding, focused kernel faults, SMART, ext4, temperature and throttling. Include
bounded collection of the unresolved `needrestart` version, numeric account
identity and exact listeners. No correction, notification or acceptance is
authorized. Review storage continuity and any required observation window;
record the newly validated boot and evidence reference only after that review
passes. Review package expectations with `Needrestart/` and the other observations
against independent intended-state decisions, complete the definition and its
read-only authorization gates, then authorize the full convergence preflight.
