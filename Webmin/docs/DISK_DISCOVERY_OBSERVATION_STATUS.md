# Passive observation startup record

Latest: the replacement observer started on October 4 at 17:56 CDT, following
the [accepted reboot baseline](DISK_DISCOVERY_REBOOT_RESULT.md). Its new 24-hour
outcome is pending; the previous run remains archived and incomplete.

## October 4 replacement startup

The user authorized execution bundle SHA-256
`9479b61efcc35ec9a423b5d3e552de698e86467e6595c9c1893cf7334417d2fd`.
The outer hash and all review members matched immediately before execution.
The controller ran once and returned zero. Startup gates passed against the
pinned postboot baseline, including synchronized time and clear needrestart.

The original operation directory was preserved as
`/var/lib/webmin-discovery-observation-terminal-20260929`. Independent readback
verified all 16 file hashes and the original terminal-result hash; the archive
remains root-owned, mode 0700. Current observer inputs and protected production
files match their expected hashes. Temporary input staging is absent.

The new transient observer started at **October 4, 2026, 17:56:26 CDT**
(22:56:26 UTC). The service was active/running after launch disconnection. Initial and subsequent
periodic samples reported 42°C with no counter increase or alert.
Source files, polling and smartd configuration were not changed by replacement.
This is startup evidence, not completed long-duration qualification.

Review checkpoints in America/Chicago (CDT, UTC−05:00):

- Two hours: **October 4 at 19:56**.
- 24 hours: **October 5 at 17:56**, followed by final settling.

Checkpoint files are automatic; operator review and external notifications are
not scheduled. Use the existing read-only status controller shown below. Do not
run either startup controller again. Any later alert supersedes initial success.
Private execution and readback evidence are retained under
`observation-replacement-preparation`, including `start-verification`.

## October 4 diagnosis

The observer stopped on September 29 at 16:42 CDT with `cache_encoding` after
about 2 hours 10 minutes. Its two-hour checkpoint recorded 24 collections with
no counter increase. The last successful sample recorded 25 collections and
43°C. The service is failed/inactive; no 24-hour checkpoint exists. The alert
reports no rollback or monitoring change. **The 24-hour qualification failed to
complete; the two-cycle pilot remains the accepted qualification.**

Read-only inspection on October 4 retrieved the observer journal, retained
samples, current cache and installed serialization source. The journal confirms
the parser exception. The failing September 29 cache was not retained:
`collect()` parses health before returning, so its exception bypassed the
sample writer. No exact historical input can be reconstructed from these files.

The current cache reproduces `cache_encoding` in the original observer. It
contains `ARRAY,`, the installed Webmin serializer's representation of an empty
array. The observer treated its empty suffix as another serialized value. The
Python fixture instead emitted `ARRAY`, hiding this incompatibility. This
proves a parser defect and a current reproduction, but does not prove that the
same field caused the September 29 exception.

The repository-only correction handles empty `ARRAY,` and `HASH,` containers.
The fixture now emits Webmin's empty-array form. Ten observer tests passed,
including literal empty containers, nested empty health errors and rejection of
malformed children. The retrieved current cache passes the corrected parser
with one drive at 42°C. This one cache read is not a new health query or a
long-duration acceptance result. Vexp verification was unavailable; the
focused tests and whitespace check provide local validation.

Raw evidence and its hash manifest are private under
`disk-discovery-follow-up-20260929/cache-diagnosis-20261004`. No deployed source,
observer inputs, polling, service configuration or packages were changed, and
no observer was restarted.

Before another observation, preserve the bounded failing cache bytes when
parsing fails, review fresh target identities and prepare a new immutable
execution bundle. Retain the old terminal evidence. Starting a replacement
observer requires separate authorization; the original bundle remains unchanged.

## Historical startup state

The approved observer started on **September 29, 2026 at 14:31:56 CDT**
(19:31:56 UTC). Startup returned zero after verifying the approved inputs and
current target metadata against the retained pilot identities. The transient
`webmin-discovery-observation.service` was active/running on subsequent status
reads after the launch connection closed. The initial sample and the next
periodic sample passed: one expected drive at 43°C, no command-error counter
increase and no local alert. No new scheduled collection was yet recorded at
this startup check; collection coverage remains a checkpoint requirement.

**Historical startup state: running; later terminated as recorded above.** Unit `Result=success`
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

## Replacement preparation and restart audit, October 4

Failure-cache retention is implemented in the repository observer. It saves the
exact bounded parser input on failure under the private evidence directory,
with exclusive creation, mode 0600, SHA-256 and cache metadata. Successful reads
are not saved. Errors still terminate the run. Pre-directory startup preflight
is outside this retention path. Twelve observer tests passed, including private
retention, size bounds, no overwrite and malformed-input rejection.

A forced list-only needrestart audit exited zero and reported 13 pending
service/manager entries: cron, D-Bus, NetworkManager, smartmontools, SSH,
systemd-journald, systemd-logind, systemd-manager, systemd-timesyncd,
systemd-udevd, systemd-user, Webmin and wpa_supplicant. The absent reboot marker
and matching installed/running kernel did not establish userspace readiness.
NetworkManager reports CanStop=yes and RefuseManualStop=no; no unit-level
reboot-only restriction was observed. No restart was attempted.

Recommend a separately authorized controlled reboot with recovery access,
followed by baseline and normal scheduled-collection verification before the
next observation. The provisional replacement review bundle remains private
under `observation-replacement-preparation`; it contains the tested observer,
terminal-evidence preservation procedure, controller and review instructions.
It is not ready for live execution: a reboot changes boot/service identities,
which must be reviewed and pinned in a newly frozen bundle. No live source,
service or monitoring changes were made during preparation.
