# Drive-polling trial

## Scope and prerequisites

`scripts/drive-polling-trial.py` adds `collect_notemp=1` to
`/etc/webmin/system-status/config`. It preserves an exact backup, ownership,
permissions, and original timestamps for rollback. Webmin reads the setting
on subsequent collections; this procedure does not restart Webmin.

This runner is intentionally qualified for the inspected Debian host profile:
five-minute collection, root filesystem on `sda`, config ownership root:bin
(0:2), mode 0600, and active `webmin`, `smartmontools`, and `munin-node` services.
It requires Python 3, systemd, journalctl, findmnt, and an existing strace.
Review another host before adapting those expectations. Do not install missing
dependencies as an implicit part of this operation.

The operation JSON supplies `id`, `host`, `boot_id`,
`expected_config_sha256`, and `script_sha256`. Collect those values independently
before execution, bind the operation and script to the authorized bundle, and
keep host identities and operation state outside Git. Do not reuse an old
operation specification after a reboot or configuration change.

On the reviewed target, with protected inputs already transferred:

```sh
sudo python3 /protected/path/drive-polling-trial.py apply /protected/path/operation.json
```

The runner creates a root-only directory below
`/var/lib/webmin-drive-polling-trial`, starts and checks its transient observer,
then performs the guarded replacement. Configuration conflicts stop execution.
A failed or interrupted apply attempts exact rollback. After a completed apply,
an observer failure leaves polling disabled for review.

## Instrumentation and review

The observer samples every 60 seconds and writes `latest.json` and
`samples.jsonl`. It checks:

- The boot, configuration hash, existing service identities, and root mount.
- Webmin collection and disk-usage history freshness and distinct cycle counts.
- Drive-temperature history stops advancing after a 65-second transition.
- Kernel USB resets and storage errors, plus ext4 error counters.
- Existing `sda` disk statistics for review of ordinary activity.

A 660-second `execve` trace attaches to Webmin's miniserv process and follows new
descendants. It retains only smartctl execution lines; version queries do not
count as drive reads. The trace does not cover independent existing processes
such as smartd. Avoid manually opening SMART Drive Status during the trial:
the setting does not prevent that page from querying the drive.

`trace-result.json` must report a completed trace without read commands or an
error. The initial trace verifies several scheduled opportunities, rather than
providing continuous execution tracing for the whole day. Ongoing history and
configuration checks provide the remaining coverage.

The observer writes `checkpoint-7200.json` and `checkpoint-86400.json` after
two and 24 hours, within approximately one sample interval. A quiet checkpoint
requires a completed clean trace, no latched sample failures, and at least
`floor(elapsed_seconds / 300) - 2` qualifying collection cycles. History older
than 15 minutes, sample gaps over three minutes, changed service identities,
resets after the transition, and storage errors require review. Transition
resets are retained; actual storage errors count immediately.

An example read-only inspection on the target, after setting `trial_state` and
`trial_unit` to the exact recorded values:

```sh
sudo systemctl status "$trial_unit" --no-pager
sudo cat "$trial_state/latest.json"
sudo cat "$trial_state/trace-result.json"
sudo cat "$trial_state/checkpoint-7200.json"
sudo cat "$trial_state/checkpoint-86400.json"
```

A missing future checkpoint is pending. A missing overdue checkpoint requires
investigation. Read the sample history and disk-stat deltas before concluding
ordinary storage activity remained healthy. Active smartd and Munin processes
do not prove device-specific health monitoring is adequate; review their
coverage separately without introducing the suspected SMART query.

The transient unit survives an SSH disconnect, but not reboot. A reboot
invalidates the observation window. At completion the observer leaves the
mitigation in place and writes `complete.json`; it does not accept storage,
restart anything, or automatically restore polling. Invalid observer windows
must be preserved and replaced with a fresh window.

## Exact rollback

Rollback restores the original file bytes, UID, GID, mode, and original mtime,
then stops this operation's observer. It refuses to overwrite configuration
drift. Re-enabling the previous setting also restores the suspected scheduled
query, so rollback is a deliberate operational decision, not the default
reaction to an unhealthy observation.

Use the script and state directory recorded for the current observer:

```sh
sudo python3 "$trial_state/observer.py" rollback "$trial_state"
sudo cat "$trial_state/rollback.json"
```

Verify the restored hash against the independently recorded original hash,
check ownership and mode, and confirm the observer stopped. Retain the backup,
operation definition, and evidence until the terminal review is recorded.

## Upstream context

smartmontools [issue 256](https://github.com/smartmontools/smartmontools/issues/256)
already has a JMS583 self-test-log request-size workaround in commit
`c4a26cba430a4638f7d86ee70363b33e9ea491e0` (r5650). The inspected 7.4/r5530
installation predates that workaround. A package containing the fix is a
separate possible intervention, not part of this trial.

Webmin [issue 2838](https://github.com/webmin/webmin/issues/2838) requests narrower
scheduled temperature queries or a per-drive exclusion. Neither report claims
that this mitigation establishes the underlying hardware cause.
