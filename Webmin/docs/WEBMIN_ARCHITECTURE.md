# Webmin architecture

This document governs Webmin-owned configuration and the drive-polling trial.
It does not govern the storage stack, smartmontools packages or daemon,
Munin, Nautobot, or Restic.

## Authorized mitigation design

The trial sets `collect_notemp=1` in Webmin's system-status configuration.
This bypasses scheduled drive-temperature SMART collection for all drives.
Disk-space reporting is a separate collection path. CPU-temperature collection
is also separate, but its availability must be verified on each target.
The setting does not disable manual SMART Drive Status queries or independent
SMART callers.

The existing setting is preferred for this trial because it avoids maintaining
a local Webmin source patch. Losing scheduled drive temperatures is an explicit
tradeoff. Package removal, upgrades, USB-driver changes, and service restarts
are outside this mitigation.

## Execution boundary

The custom runner owns exact configuration comparison, atomic replacement,
backup and rollback, and an observer that survives controller disconnection.
It is a bounded diagnostic operation, not a general Webmin installer. Each
execution uses a reviewed operation specification and hashes of its inputs.
Only one operation may be active; observer repairs remain within that operation
and preserve the invalid evidence they supersede.

The observer collects existing history, kernel messages, filesystem counters,
service identities, and ordinary disk activity. It does not issue SMART requests
or generate storage workloads. A short execution trace verifies the Webmin
query path. Neither successful service status nor missing kernel messages alone
establishes adequate drive-health coverage.

## Review and adoption

Review two-hour and 24-hour checkpoints, including completed collection cycles,
query suppression, storage errors, and the monitoring coverage that remains.
Missing evidence or a failed probe requires review. A quiet checkpoint is an
observation, not proof of hardware reliability.

Only after the full observation and coverage review should the mitigation be
recorded as accepted desired configuration in this component. Storage acceptance
and Restic validation remain separate. Active operation state and raw evidence
stay outside Git; procedures belong in [DRIVE_POLLING_TRIAL.md](DRIVE_POLLING_TRIAL.md).
