# Passive observation startup record

## Observed state

The approved observer started on **September 29, 2026 at 14:31:56 CDT**
(19:31:56 UTC). Startup returned zero after verifying the approved inputs and
current target metadata against the retained pilot identities. The transient
`webmin-discovery-observation.service` was active/running on subsequent status
reads after the launch connection closed. The initial sample and the next
periodic sample passed: one expected drive at 43°C, no command-error counter
increase and no local alert. No new scheduled collection was yet recorded at
this startup check; collection coverage remains a checkpoint requirement.

**State: running at last check; 24-hour acceptance pending.** Unit `Result=success`
while running is not a completed observation result. Startup does not extend
the accepted two-cycle pilot into a longer qualification.

## Review schedule

All times below use America/Chicago (CDT, UTC−05:00).

- Two-hour checkpoint: September 29 at approximately **16:32**.
- 24-hour checkpoint: September 30 at approximately **14:32**, followed by the
  required settling interval. Allow up to 7.5 minutes for completion; review any
  missing terminal result rather than assuming success.

The observer writes checkpoints automatically. An operator must retrieve and
review them; no external notification or automatic assistant follow-up is
scheduled. Use the approved private controller's read-only command:

```sh
cd /home/aaron/code/.local-evidence/disk-discovery-follow-up-20260929/observation-preparation
python3 execute-reviewed.py status
```

Review checkpoint coverage, progress, unit state, terminal result and any alert
together under the [observation procedure](DISK_DISCOVERY_OBSERVATION.md). Keep
raw evidence private. Do not rerun `start` or change the active inputs. A later
alert supersedes an earlier successful checkpoint.

## Authorization and evidence

Execution bundle SHA-256:
`db11bb7803de4838f218743d31b34e67723aa2ba888e8480be17bcde83df4830`.

Inner observation bundle SHA-256:
`4914e1fff3ef40def4bc3def098472938df0d32d2717a7cc3e75d1cc24a4b0ad`.

Both hashes and the controller's equality with the approved outer tar member
were verified before execution. Private startup/status stdout, stderr and exit
status, plus `START_RESULT.json`, are retained under `observation-preparation`
in the private `disk-discovery-follow-up-20260929` archive. Immutable prepared
artifacts retain their original pre-execution wording.

The observer preserves polling, smartd, installed sources and existing alert
routing. It issues no manual disk query and attaches no tracer. Local failure
alerts stop observation for review; automatic source rollback and external
messages are outside this authorization. Source backups from the pilot remain
available under the separately authorized recovery procedure.
