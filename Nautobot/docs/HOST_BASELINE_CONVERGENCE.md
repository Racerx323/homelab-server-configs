# Retained host-baseline convergence and acceptance

> **Post-cleanup read-only preflight passed all 59 checks.** Host acceptance remains pending. Separate authorized
> preparation observations and a separately authorized boot-file correction exist.
> The authorized corrective reboot passed bounded checks; host acceptance,
> Restic initialization and terminal reconciliation remain pending. The deployment plan remains the sole
> architecture authority.

See [the roadmap](ROADMAP.md) for the current acceptance map and inactive
workload and Restic drafts. Current status belongs here and in the operation
manifest, not in the governing deployment plan.

## Historical evidence and gaps

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
completed the isolated restore gate. The later authorized preparation verified a different boot from that
old soak, corroborating the operator-reported reboot. Retain
the old soak as historical evidence. Fresh current-boot storage validation and
continuity review are required before convergence acceptance. The reviewed
current boot ID and evidence reference were unresolved at preparation time;
the authorized current-boot review below supplies their replacement.
The preflight must start and end on that newly validated boot. Review whether
the reboot circumstances or fresh findings require another observation window;
do not silently reuse the old soak or automatically prescribe another reboot.

The active manifest retains the v3 expectations except for the separately
authorized smartmontools upgrade to `7.5-2~bpo13+1` and mail frontend additions:
`bsd-mailx` `8.1.2-0.20220412cvs-1.1`, `liblockfile-bin` `1.17-2`, and
`liblockfile1:arm64` `1.17-2`. These reconcile approved changes, not a new package
installation request. The post-cleanup preflight compared all required package expectations successfully.
The current plan additionally requires `needrestart`. Its owning repository component is
[`Needrestart/`](../../Needrestart/README.md); Nautobot observes the required
package version, while package and notification integration changes require
owner review. The owner documentation gives an unpinned Debian installation
procedure, not an accepted exact version for this host. Its stated Debian 12
requirements and Pi 5 kernel-filter example do not establish this Debian 13,
Pi 4 host's configuration. Do not run the owner installer, notification script,
mail test or copy its active Pi 5 kernel filter during this preflight.
The separately authorized preparation collection established needrestart `3.11-1`,
matching the cached official trixie candidate. The intended account decision is to
retain the existing canonical nologin account (UID 999, GID 985), corroborated by
home ownership, exact subordinate ranges and lingering. These reviewed expectations
precede the separate full convergence preflight; this collection is not that
acceptance run. Needrestart notification deployment or delivery was not tested.

The listener allowlist retains only the required SSH, Webmin and Munin services:
TCP 22 and 10000 on IPv4/IPv6, Webmin UDP 10000 on IPv4, optional loopback-only TCP 555
(Webmin stats process verified in webmin.service), and Munin TCP 4949 wildcard.
Service configuration and process ownership corroborate these endpoints. Allowing
these baseline listeners does not accept Internet/IPv6 exposure; authoritative
firewall and reachability checks remain separately required. No additional
application, PostgreSQL or Redis listeners are permitted.

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

## Historical preparation scope and retained evidence

Earlier discussion used local gate shorthand, not the deployment plan stage numbers.
That preparation covered Gate 2 (host-baseline convergence definition), with
review of its Gate 1 (storage qualification) dependency. It accepts neither gate
and does not activate Gates 3–6, Restic, application deployment, Caddy or fleet work.
The active manifest's `preparation_review` records the dispositions. The frozen
schema binds the reviewed definition; readiness and execution were explicitly
transitioned for the authorized preflight, then closed after its blocked result.
Acceptance remains false.

The later combined Webmin/smartmontools observation passed its bounded transport
checks, but its expanded review failed because of smartd log warnings and failed
alerts. Subsequent mail frontend/recipient repair has confirmed downstream receipt;
the changing trailing self-test-log record remains unresolved. Neither result
retroactively accepts the historical baseline or the failed expanded review.

Private retained sources on the controller are:

- `/home/aaron/code/.local-evidence/smartmontools-upgrade-20260915/CHECKPOINT_REVIEW.md`
  and its preserved observer evidence: bounded transport result and wider gaps;
- `/home/aaron/code/.local-evidence/smartd-investigation-20260916/RESULT.md`,
  package/recipient bundle records and `receipt.json`: repair and log analysis;
- the corresponding SHA-256 manifests: verify before relying on raw observations.

The older `/tmp/nautobot-authorized-observation.hcqaw7ra` directory was unavailable
during this preparation. Do not invent its package, account or listener findings.
The authorized replacement collection now provides those facts; its raw evidence is
under `/home/aaron/code/.local-evidence/nautobot-acceptance-review-20260916/`.

The following table records the earlier preparation gaps. The acceptance map
above records which checks the later 59/59 preflight satisfied.

| Earlier check | Evidence required at preparation time |
| --- | --- |
| SMART log disposition | Working health telemetry qualified separately; self-test-log capability remains unreliable and tracked in smartmontools #648. No warning suppression. |
| SMART probe safety | Reduced query followed by 75-second settling and kernel read is defined and must pass the full convergence preflight. |
| Current boot and filesystem | Review root/USB binding, ext4 metadata and counters, kernel events, power/throttling and temperature, with boot continuity. |
| Required package versions | Needrestart and approved changes reconciled; the full preflight must compare all retained package expectations. |
| Service identity | Retain reviewed UID 999 / GID 985; independently recheck identity, home, subordinate ranges and lingering in the full preflight. |
| Listener policy | Required-service allowlist reviewed; compare exact endpoints during the full preflight and separately prove network access restrictions. |
| Baseline execution | Validate services, rootless capability, residue and all collector results under a separately reviewed read-only bundle. |
| Terminal acceptance | Independent evidence review and explicit acceptance; separate authorization for terminal commit/tag/push. |

At that preparation point, `current_boot_validation` remained unresolved until
the complete storage review passed. It now records the bounded current-boot
validation; this does not grant terminal acceptance.
A known recent boot ID is not equivalent to an accepted current-boot baseline.
The SMART decision is limited: recorded working health telemetry can satisfy the
plan's SMART-health requirement without a new code patch or a drive self-test.
The self-test log cannot establish either media failure or health clearance on
this path. This does not invoke a blanket exception for failed SMART access and
waives no kernel, filesystem, power, backup or restore requirement. Preserve
smartd monitoring and upstream investigation; do not suppress warnings globally.

A fresh reduced query returned zero critical warnings, media errors and error-log
entries at 44 C, with 75 seconds of quiet kernel evidence. Ext4 was clean, its
live error count zero and throttling zero. The boot still contains 172 historical
USB-reset entries from September 7–8. Retain them as pre-mitigation history rather
than forcing a reboot to clear the journal. Both pre/post SMART kernel probes use
the reviewed combined-observation boundary `2026-09-15T15:33:26+00:00`, tied to boot
`fef03fd9-32ce-4807-92f8-acd7c72a07f1`. Any different boot invalidates that window.
The event matcher now includes the actual `reset ... USB` spelling. A new event
within that window blocks acceptance. Original full-boot output is preserved.

The Webmin stats process used a deleted Perl executable at observation time; this
is a separate maintenance finding, not proof of a storage fault. No restart was
performed. Assess it through the owning maintenance procedure before terminal
acceptance; the listener remains attributed to webmin.service.

The launcher exposes a local command preview:

```bash
python3 Nautobot/ansible/scripts/run-host-convergence.py show-command
```

Its `execute AUTHORIZED_SHA256` path requires a clean repository. For authorized
read-only work while unrelated edits must remain uncommitted, use the reviewed
`execute-snapshot AUTHORIZED_SHA256` path from a protected source snapshot.
The snapshot must be directly under `/tmp/nautobot-convergence-source.*`, owned
by the current user, with mode-0500 directories and exactly the bundle's input
files at mode 0400, with no symlinks or extra files. Copy inputs preserving their
relative paths and invoke the launcher from that snapshot. Compute its existing
bundle-v1 SHA-256 over the ordered `BUNDLE_FILES` hashes; readiness, frozen schema,
exact hash and mutation-prohibition checks still apply. Both paths use the
repository Ansible wrapper and disable implicit Ansible configuration loading.
Keep the snapshot and evidence for review; never use this as production mutation
authorization or a substitute for terminal archival.

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

After any separately authorized correction, refresh changed observations, review
the next read-only bundle and frozen schema transition, and rerun the owning
preflight. No failed check authorizes automatic repair, reboot or Restic action.
The self-test-log issue stays open independently of qualified health telemetry.

## Current-boot readiness review

The retained reduced-query and filesystem evidence was checked against its
hash manifest. Root `/dev/sda2` is ext4 on the verified `152d:0583` USB ancestry,
bound to usb-storage at 5000 Mbps with the quirk exactly once. The current boot
matches the combined observation. Host throttling flags remain zero; temperature
was 50.6 C at the supplemental read. These readings do not establish negotiated
PoE class or allocation. The host exposes no `/sys/class/power_supply` nodes;
switch-port evidence must come from the network owner/controller.
Cloud reads using the Site Manager audit reference returned HTTP 403. After the
controller trust update, local reads succeeded using `AUDIT_LOCAL` with a trusted
certificate chain and the covered TLS name `local.theama.co`, connecting directly
to `10.1.0.1`. The certificate does not cover the IP itself; do not disable TLS
verification. The operator subsequently identified `udmbt.local.theama.co` as the
controller FQDN; DNS resolves it to `10.1.0.1` and normal HTTPS certificate
verification succeeds. Follow the network-owned [UniFi access procedure](../../../homelab-network/Ubiquiti/UNIFI_ACCESS.md).
Use `https://udmbt.local.theama.co` for future queries,
without a TLS-name override. The client MAC maps to J2-SW48POE port 3, reporting Class 4,
poe_good=true, 5.90 W at 53.64 V and a 1000 Mbps link. This closes negotiated-supply
evidence collection. An explicit per-port allocated-watt field was not exposed;
do not equate observed draw with allocation or a rated adapter limit. Workload
power headroom remains part of representative application testing.

Before the correction, active cgroup controllers were `cpuset cpu io pids`:
`memory` was absent and the boot command line included `cgroup_disable=memory`.
The full
preflight now reads the cgroup-v2 controller list and rejects missing memory
control even when rootless Podman itself works. Actual per-service limit
enforcement remains an application-runtime acceptance check.

Read-only diagnosis established that the disabling argument comes from the
firmware/device-tree default, not the on-disk command-line file. The kernel has
`CONFIG_MEMCG=y`; its missing `CONFIG_MEMCG_V1` means `/proc/cgroups` is not a
valid test of memory-controller availability on cgroup v2. Check
`/sys/fs/cgroup/cgroup.controllers` instead.

The authorized boot-file correction appended only `cgroup_enable=memory` to
`/boot/firmware/cmdline.txt`, preserving the USB quirk and every other original
byte. The exact backup and independent hash readback passed. The subsequently
authorized reboot activated kernel `6.18.50+rpt-rpi-v8` (previously
`6.18.39+rpt-rpi-v8`) and produced a new boot identity. Memory control is now
available at the root cgroup and the delegated Nautobot user manager. This
validates the resulting configuration, not attribution to the command-line
change alone, because a pending kernel update also took effect.

Independent postboot samples verified unchanged root UUID/ext4 mount, JMicron
ancestry and usb-storage binding at 5000 Mbps, unchanged boot/monitoring hashes,
zero throttling, recovered services and no failed units. No matching USB resets
or filesystem/I/O errors appeared through the bounded review. Webmin retains
`collect_notemp=1`; no new manual SMART query or self-test was issued.

The kernel logged one `mmc1` inhibit warning followed by SDIO-card and wireless
firmware initialization. It was not an error on the USB root device. The old boot
journal is no longer available on the host, so whether this warning predates the
kernel update remains unverified. Preserve it for the next host-baseline review.
Smartd resumed monitoring and reported its previously unreliable self-test-log
count decreased to zero; that does not resolve the upstream anomaly or establish
drive-health acceptance. No new alert delivery was tested.
See [memory-controller correction](MEMORY_CONTROLLER.md) for the reusable
procedure, rollback boundary and postboot checks.
The old boot-bound observation cannot be carried forward automatically. Complete
fresh storage/health validation and actual per-service memory-limit enforcement
under their owning acceptance stages. Private reboot evidence is retained beside
the memory-controller correction evidence.

## Authorized current-boot preflight

The operator authorized fresh current-boot storage/health validation and the
complete read-only preflight. Reduced SMART health returned zero critical/media/
error-log counts at 44 C, followed by 75 seconds without focused kernel events.
Ext4 metadata and live error counters, root transport, boot continuity and power
flags passed. This closes the current-boot evidence dependency, not terminal
storage acceptance. The frozen definition was deliberately updated for this boot
and read-only scope. Both kernel probes now cover the entire current boot without
a historical `--since` cutoff. Prior observation windows remain historical.

MMC review independently maps `mmc1` to `wlan0`/brcmfmac through sysfs; the root
disk has a separate USB ancestry. The single inhibit error was followed by SDIO
initialization and did not recur during review. The default route uses eth0;
NetworkManager reports Wi-Fi unavailable; rfkill confirms software blocking with
no hardware block. No wireless traffic test was performed,
so this is not Wi-Fi acceptance or proof of harmlessness in every context. It
does not currently establish a USB-root-storage fault. Preserve the warning and
investigate further if it recurs or Wi-Fi becomes a required service.

Webmin polling remains disabled during the baseline checks. The patched code and
smartmontools 7.5 previously passed bounded scheduled polling on the older kernel.
If current checks remain quiet, enabling it for a separately authorized new-kernel
observation is reasonable; an unchecked permanent restoration is not yet supported
by the new-boot evidence. Keep immediate disable-on-error behavior and review
actual scheduled queries, temperatures, gaps and configuration integrity.

## Initial full preflight result and correction

All required package versions, account/subordinate IDs, lingering, rootless
Podman with memory control, unit states, permanent ULA, root transport, SMART
health, ext4 checks, temperature/throttling and boot continuity passed review.
The complete observation is retained privately under
`nautobot-current-boot-preflight-20260916`, including its exact source snapshot.

The initial evaluator rejected an empty `systemctl list-unit-files` result with
exit 1. That no-match case is now accepted only with empty stdout/stderr and the
independent package/process/unit/config absence checks still required. Retained
observations were re-evaluated offline; no evidence was edited or recollected to
obtain a favorable result.

Installed Authentic Theme source shows `stats.cgi` launches `stats.pl` on demand
and the latter binds loopback, times out without a connection and can shut down
when clients disconnect. The historical TCP 555 listener is therefore optional,
with only its exact loopback endpoint allowed; required listeners and rejection
of unexpected/wildcard endpoints remain intact. No service restart was needed.

Two residue gates initially failed: five dpkg config-files records and six obsolete
6.12.62 kernel/header/build packages proposed by simulated autoremove. A combined
purge/autoremove simulation lists exactly eleven entries, with no installations
or upgrades. It retains the running 6.18.50 and prior 6.18.39 kernel packages.
At that initial preflight, no purge or removal had been executed. The later
authorized cleanup and repeat preflight below supersede those residue blockers. This is Gate 2 baseline housekeeping, not a renewed USB-storage fault.

Host acceptance, representative application memory enforcement, network exposure,
backup/restore and Restic remain separate gates. Renew patched Webmin polling
under a guarded observation using current smartmontools/kernel identities after
the configuration is stable; do not reuse the original 7.4-only patch installer.

## Authorized cleanup and fresh preflight

The separately authorized [package cleanup](PACKAGE_CLEANUP.md) preserved exact
recovery packages, configuration/package metadata and boot archives, then purged
the eleven named entries without autoremove. Independent checks found no
residual configuration or autoremove candidates, a clean dpkg audit, no failed
units, unchanged boot identity and all 49 protected firmware hashes unchanged.
Running 6.18.50 and fallback 6.18.39 kernel packages remain installed.

A fresh full preflight passed all 59 checks with the current evaluator and
reviewed optional-listener policy. Its source snapshot, command outputs and
cleanup evidence remain under private `nautobot-cleanup-polling-20260916` evidence.
This supersedes the initial residue blockers without rewriting their original
result. Preflight execution authorization is closed after this completed run.

The separately authorized Webmin-owned new-kernel polling observation is now
running, retaining the installed patch and smartmontools version. The observer
owns enablement, continuous tracing, two-hour/24-hour checkpoints and automatic
disable on failure or completion. Review its actual records before judging the
observation complete. Passing preflight is not terminal host/storage acceptance;
Restic and later application/backup/restore gates remain pending.
