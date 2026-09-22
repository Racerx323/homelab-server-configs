# Startup database preservation

This separate operation prepares recovery for the initialized database and admin.
It never starts PostgreSQL, Redis, migration or application services.

Target: `ama@10.1.2.170`. Source volumes are the rootless Nautobot PostgreSQL and
Redis volumes below `/var/lib/nautobot/.local/share/containers/storage/volumes/`.
The new copy is `/var/lib/nautobot/recovery/nautobot-startup-database-preservation-v1/`.
A partial or existing destination stops execution; it is not overwritten or reused.

The playbook stages the existing preservation helpers into a new root-owned
mode-0700 `/tmp/nautobot-inspection.*` directory. The helper verifies boot, image,
configuration, Quadlet and account identities; stopped services; absent containers;
fixed volume paths; no nested mounts or external links; PostgreSQL 17 and no
postmaster PID; and sufficient capacity. It copies both trees preserving metadata,
then compares source-before, source-after and destination manifests including
content hashes, ownership, permissions, timestamps, xattrs and hard-link topology.
It rechecks stopped state and identities before producing a success record.

No deletion, service start, data restore, package update, network change or reboot
is included. Failure retains the incomplete private destination and evidence for
review. Recovery means retaining the original untouched volumes; never delete them
to undo a failed copy. Restoring a preserved copy is a separate reviewed action,
with all services stopped and the existing volume preserved before replacement.
A verified copy is not an exercised restore and does not replace Restic acceptance.

The reviewed definition is `manifests/startup-preservation.yaml`; freeze with
`python3 Nautobot/ansible/scripts/freeze-preservation.py /tmp/NEW_BUNDLE_DIRECTORY`.
The output hash covers the exact playbook, helpers, operation, inventory and review.
After explicit hash approval, execute the frozen `run-preservation.py HASH`.
Keep the preservation result and remote private evidence; archive before advancing
the active operation. Refresh the startup baseline after preservation and before
startup, since the launcher enforces freshness. Startup itself remains unauthorized.
