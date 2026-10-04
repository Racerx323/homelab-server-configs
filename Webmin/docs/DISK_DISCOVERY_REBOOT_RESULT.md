# Reboot and replacement-observer readiness

## Accepted October 4 baseline

The user authorized one controlled reboot and confirmed local recovery access.
Pre-reboot identity, source/configuration, health and storage checks passed.
The host accepted the reboot request; SSH then disconnected. Reconnection
established a new boot identity. The running kernel remains
`6.18.50+rpt-rpi-v8`, and package and protected source/configuration identities
match the qualified combination. Webmin and smartmontools are active.

A forced list-only needrestart audit exited zero with no pending service,
session or container entries, compared with 13 entries before reboot. No
individual monitoring or networking service was restarted manually.

The first postboot collection window was not accepted: wall time changed by
about 15.5 seconds relative to the monotonic clock. The boot journal records
initial clock synchronization; `NTPSynchronized=yes` was confirmed before a
fresh window. The original failed window remains in private evidence. A local
checker JSON timestamp conversion error was also corrected; its retained first
sample was reused without repeating the reboot.

The synchronized window then passed over 429 seconds:

- Two new scheduled collections in each load, disk-used and temperature stream.
- Complete expected drive coverage; final cached temperature 42°C.
- No SCSI command-error, timeout or ext4 counter increase; no matched kernel
  storage/power/OOM faults in the boot journal.
- Protected source/configuration, packages, boot and service identities stable.
- 101 seconds after the final completed health-cache write, with no sampled
  active disk query or collector at acceptance.

The settling check uses the completed health-cache write, not syscall tracing.
This verifies the postboot baseline on one host; it does not complete the new
24-hour observation or qualify other hardware. Polling and smartd remain enabled.
No Webmin source or monitoring configuration was changed during this action.

## Replacement ready for execution review

The corrected observer handles empty containers and retains bounded private
failure-cache input during observation. Twelve observer tests passed; five
replacement fixtures passed with service/transport behavior mocked. The final
bundle's outer members, embedded program syntax, input archive, component
checksums and pinned postboot specification were checked. Vexp verification is
unavailable from the workspace root; repository whitespace and link checks
provide the applicable documentation validation.

Execution bundle SHA-256:
`9479b61efcc35ec9a423b5d3e552de698e86467e6595c9c1893cf7334417d2fd`.

The private review package is
`disk-discovery-follow-up-20260929/observation-replacement-preparation/execution-review.tar`.
Its `REVIEW.md` contains exact scope, preflight, preservation, startup, acceptance
and failure handling. The reviewed command, after separate execution approval:

```sh
cd /home/aaron/code/.local-evidence/disk-discovery-follow-up-20260929/observation-replacement-preparation
python3 execute-replacement.py
```

The action preserves all old terminal evidence by verified rename, then starts
one new bounded observer against the pinned postboot baseline. The old transient
unit is absent after reboot, so it needs no reset. It does not reboot, change
Webmin sources, alter polling/smartd, or issue manual disk queries. If startup
fails or SSH drops, inspect retained evidence and unit state before any retry;
never assume disconnection means startup failed. Automatic source rollback and
external notifications are excluded.

**Subsequent state:** the user authorized this exact bundle, and the replacement
observer started on October 4 at 17:56 CDT. See the
[startup and checkpoint record](DISK_DISCOVERY_OBSERVATION_STATUS.md).
The new 24-hour result remains pending. Raw reboot and qualification
records, error records and their hash manifest remain private under
`disk-discovery-follow-up-20260929/reboot-qualification-20261004`.
