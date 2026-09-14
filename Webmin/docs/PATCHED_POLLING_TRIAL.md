# Patched Webmin temperature-polling trial

## Scope

The upstream patch is Webmin commit
`725362b9f0e26a2f88f81dd36d4bfbd784166cf3`, linked from
[issue 2838](https://github.com/webmin/webmin/issues/2838).
It changes `smart-status/smart-status-lib.pl` and
`system-status/system-status-lib.pl`. For smartmontools 7.4, scheduled temperature
collection uses `-A -l error` instead of `-a`; separate `-i` and `-H` calls remain.
Manual full SMART queries and independent callers are unaffected.

Keep smartmontools 7.4 unchanged for this trial. The target profile and helper
requirements from [DRIVE_POLLING_TRIAL.md](DRIVE_POLLING_TRIAL.md) apply. This is
not a generic installer. It is a guarded two-file patch with a bounded polling
experiment and a configuration shutoff owned by its observer.

## Apply and enable

Prepare an operation JSON with target/boot identity, unique operation ID, exact
before/after source bytes encoded as base64, expected after hashes, configuration
bytes and metadata, and unchanged smartctl/smartd/configuration hashes. Preserve
the upstream patch and verified local applicability check. Bind these inputs and
both Python scripts to an exact SHA-256 deployment bundle outside Git.

The disabled configuration contains `collect_notemp=1`. The enabled configuration
removes only that override, preserving the existing package and interval settings.
This restores default temperature collection; it does not reset all Webmin settings.

With protected inputs on the authorized target:

```sh
sudo python3 /protected/path/patched-polling-trial.py apply /protected/path/operation.json
```

The runner validates source bytes/metadata and package identity, stores backups
and the baseline under `/var/lib/webmin-patched-polling-trial`, atomically replaces
the two files, and starts a transient systemd observer. The observer attaches its
trace before removing the override. No disabled-polling functional trial is run.
The first actual scheduled command sequence verifies loaded behavior.

## Observation and automatic shutoff

The observer samples every 15 seconds. It checks the boot, patched source hashes,
monitoring binaries/configurations, root mount, ext4 errors, service availability,
kernel storage events, and load/disk-space/temperature history. It records actual
temperature values and disk counters without generating synthetic I/O.

Continuous strace follows Webmin and its descendants, retaining only smartctl
execution and exit records. Allowed commands are `--version`, `-i /dev/sda`,
`-H /dev/sda`, and `-A -l error /dev/sda`. Unknown arguments, an unparseable SMART
execution, nonzero exit, a command outstanding for 60 seconds, or trace loss
stops the observation. Manual full SMART status queries during the trial will
therefore cause a shutoff if captured. Independent smartd execution is outside
this trace; its existing monitoring continues.

The observer disables temperature polling on failure, interrupt, or normal
24-hour completion. Systemd ExecStopPost provides a second disable path. The
guard refuses to overwrite unexpected configuration drift; inspect `failed.json`,
`disabled.json`, and unit status if that happens. A running SMART command cannot
be undone by disabling later scheduled polling.

Webmin/smartd PID changes fail the trial. Munin PID changes are recorded as review
events, accounting for its known logrotate restart; loss of active service at a
sample still fails. Review the actual restart journal at checkpoints. This rule
does not certify continuous availability between samples.

Checkpoints at 7,200 and 86,400 seconds require at least
`floor(elapsed_seconds / 300) - 2` completed collections, temperature records,
successful attributes queries, and successful health queries. Missing required
counts fail closed. History freshness is enforced after a 15-minute startup
allowance. Kernel events are checked from enablement with no reset grace period.
Observe at least 70 seconds after a scheduled query before judging its immediate
result, because earlier resets occurred about 31 seconds after command return.

Read the exact recorded state directory and unit on the target:

```sh
sudo cat "$trial_state/latest.json"
sudo cat "$trial_state/checkpoint-7200.json"
sudo cat "$trial_state/checkpoint-86400.json"
sudo systemctl status "$trial_unit" --no-pager
```

The observer survives SSH disconnection but is not a reboot-persistent service.
An unexpected power loss cannot guarantee execution of its shutoff handler.
Any reboot requires inspecting the configuration before restarting this trial.

## Stop and rollback

To stop the bounded trial and disable temperature polling:

```sh
sudo systemctl stop "$trial_unit"
sudo cat "$trial_state/disabled.json"
```

For an explicitly selected source rollback:

```sh
sudo python3 "$trial_state/patched-polling-trial.py" rollback "$trial_state"
```

Rollback disables collection first, stops the observer, then restores the exact
original source bytes and metadata. It refuses source/configuration conflicts.
Verify hashes against the retained inputs and preserve the operation evidence.

## Reporting

Report verified results to Webmin issue 2838: exact commit and installed package,
observed reduced commands, exit results, temperature values, cycle count and
duration, and any resets or errors. Label early results as preliminary; do not
claim the full observation passed before reviewing its checkpoint and evidence.
Exclude host identities, addresses, serials, credentials, and raw journals.

Review and report the patch trial before changing smartmontools. Storage and
Restic acceptance and restoration of indefinite polling remain separate decisions.
