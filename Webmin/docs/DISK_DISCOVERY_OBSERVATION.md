# 24-hour passive observation

The September 29 observation stopped with a cache parser error before completing
24 hours. See the [observation record](DISK_DISCOVERY_OBSERVATION_STATUS.md) for
the diagnosis and later baseline review. The repository observer now handles
Webmin's empty-container encoding and retains bounded failure-cache input. A
replacement observation must use a separately reviewed execution bundle; the
original bundle and terminal evidence remain unchanged.

## Scope and evidence

Read metadata once a minute for 24 hours, with an automatic two-hour checkpoint
and a final settling interval. The observer issues no SMART, Parted, fdisk,
self-test or workload command, installs no package, changes no source or polling
configuration, and attaches no tracer. It runs as a bounded transient systemd
service so SSH disconnection does not stop it.

The operation specification is derived from the reviewed host baseline. It
pins source/binary/configuration hashes, boot, kernel, packages, root topology,
Webmin/smartd service identities, the five-minute collection interval and exactly
one expected drive. This preparation does not assert that those facts are still
current. Startup must verify them and stop on drift instead of adopting a new
baseline silently. Initial counter values are sampled afresh; historical nonzero
command-error counts are not themselves a failed startup.

The observer reads existing per-drive health/temperature cache, load/disk/temperature
history, counters and kernel messages. Nested Webmin serialization is decoded
strictly; missing or extra drives, absent health fields, failed health, error
records or invalid temperatures prevent acceptance. History uses at most its
latest 400 records per sample and accumulates unique post-start collection times.
Raw evidence and preserved configuration bytes remain in a root-owned mode-0700
directory, outside Git. During observation, parser or health-validation failure
retains the exact cache input as `failure-cache.bin` (exclusive creation, mode
0600, maximum 2 MB) and records its hash and file metadata before failing the
run. Successful reads do not save raw cache input. Pre-directory startup
preflight is outside this retention path.

## Acceptance and limits

- Sample every 60 seconds. A gap exceeding 90 seconds fails observation.
- Require healthy drive coverage and unchanged protected identities on every
  sample. Cache/history freshness must stay within 390 seconds for the pinned
  five-minute schedule. Temperatures must be finite and between 0 and 80°C,
  retaining the previous observer's validity bound.
- At two and 24 hours, require each history stream to contain at least
  `floor(elapsed / 300) - 1` distinct post-start collections: normally minima
  of 23 and 287. The single-cycle boundary allowance is explicit; freshness
  checks still detect a missed scheduled update.
- Require no timeout/ext4 counter increase or matched kernel storage/power/OOM
  fault. Any command-error counter change stops with **review required for
  attribution**, not a declaration that Webmin caused it.
- After 24 hours, finish only when the latest completed health-cache write is
  at least 75 seconds old and still fresh, with no sampled active SMART/partition
  query or Webmin collector. The qualified source writes that cache
  after collection. This is a conservative scheduled-collection settling marker,
  not an exact trace of the last command from all independent disk callers.
  The observer does not prove absence of every partition-tool invocation; that
  was captured in the bounded deployment pilot.
- Stop if completion/settling is not reached within 24 hours plus 450 seconds.
  Systemd imposes a separate 87,000-second runtime ceiling and 180-second
  watchdog. An interrupted or killed observer cannot become a successful result.

This action does not qualify physical RAID, real hotplug, other hosts or broader
storage reliability. A source-hash change from an upgrade stops this observation
and invalidates its continuity claim.

## Failure handling and review

The selected policy is **stop, retain evidence and request review**. It performs
no automatic source rollback, restart, polling shutoff or smartd change. Failure
writes `ALERT.json` and `result.json`, logs a distinct error to the journal, and
causes the service to fail. `ExecStopPost` records unexpected termination when
there is no terminal result. A counter-only change remains an attribution task.

These are local alerts, not an external notification route. No email, webhook
or existing alert integration is added. The operator must review the two-hour
checkpoint and final result; no automatic human notification is promised.
Existing smartd alerts remain untouched. External notification or automatic
rollback would require an explicit addition to the execution scope.

For failed health, missing collection or storage faults, preserve the alert and
current source hashes, then review recovery promptly. The verified live backups
retained by the pilot support the [existing rollback procedure](DISK_DISCOVERY_DEPLOYMENT.md).
Rollback is not authorized by starting this passive observation. Do not overwrite
source drift or stop monitoring to make the observer quiet.

## Exact preparation and later execution

The local preparer takes a private operation specification and a new output
directory. It checks that the expected sources match the accepted patch manifest
and produces a deterministic `observation.tar` containing the observer, target
entrypoint, specification, this procedure and checksums:

```sh
python3 Webmin/scripts/prepare-disk-discovery-observation.py OPERATION_JSON NEW_OUTPUT
```

The private operation retains the target connection reference. After scoped
execution authorization, verify the approved tar SHA-256, transfer it to a new
private staging directory on that target, extract only its five expected regular
files, and run the reviewed entrypoint as root:

```sh
python3 start.py --execute
```

The entrypoint verifies every input hash, checks for conflicting diagnostic work,
performs fresh metadata preflight and refuses an existing owned operation. It
creates only `/var/lib/webmin-discovery-observation`, preserves exact monitoring
configuration bytes privately, and launches `webmin-discovery-observation.service`.
The runtime evidence directory is its `evidence/` child. No service is enabled
for boot, no existing service is restarted, and no source backup is removed.

At two hours, read `checkpoint-2h.json`, `progress.json`, `result.json`, unit state
and any `ALERT.json`; review coverage and failures together. Repeat after the
final result and `checkpoint-24h.json`. Copy bounded raw evidence privately,
verify its hashes, and record a sanitized result before any retention cleanup.
A checkpoint file alone is not final acceptance; a later alert supersedes it.
If interrupted, do not resume/relabel the old run as an uninterrupted 24 hours.
A fresh run needs a reviewed operation after terminal evidence is preserved.

## Upstream report and package upgrades

After terminal review, extend the unpublished Webmin inquiry with the exact patch,
source versions, reproduction, regression results, single-host pilot and the
observed long-duration outcome. Keep the earlier unexplained invocation and
unrelated smartmontools issue separate. Posting is not part of this action.

Before a future Webmin upgrade, preserve verified current sources/backups and
check whether upstream includes an equivalent fix. Validate a candidate version
against the discovery contracts and inspect any patch rebase. Never automatically
reapply this diff to mismatching sources or alter package policy as part of this
observer. If an upgrade occurs during observation, stop/review and requalify the
new combination; keep independent smartd monitoring intact.
