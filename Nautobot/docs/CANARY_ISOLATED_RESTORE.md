# Isolated canary restore

## Prepared scope

This is the restore portion of [pre-data verification](ISOLATED_BACKUP_RESTORE.md).
The single active operation binds the accepted canary archive, repository ID and
full snapshot ID. The implementation is locally qualified; live execution still requires the
exact frozen bundle hash. No live restore has run.

The operation uses the recorded full snapshot ID and its exact source directory,
never `latest`, a shortened ID or a tag filter as a substitute for identity.
Before restoration, read repository config and exact snapshot metadata; compare
repository ID/format, hostname, paths and tags with the archived acceptance.
Use existing credential references, with no secret creation or rotation.

## Destination and command

Ansible will create a new empty directory named `restore.*` beneath the existing
`/var/lib/nautobot/backup-restore-tests/` parent. Require `nautobot` ownership,
mode `0700`, no symlink ancestors and filesystem `/dev/sda2`. Verify resolved
paths cannot overlap the original source or any live-data path. Never reuse an
existing destination, even after a failed attempt.

The command is defined as an argument array in `manifests/operation.yaml`:

```text
restic --no-cache --repository-file PROTECTED_REPOSITORY_FILE \
  --password-file PROTECTED_PASSWORD_FILE \
  restore FULL_SNAPSHOT_ID:EXACT_ARCHIVED_SOURCE_ROOT \
  --target NEW_EMPTY_RESTORE_ROOT
```

`FULL_SNAPSHOT_ID` and `EXACT_ARCHIVED_SOURCE_ROOT` are immutable operation values;
only the unique destination is allocated during execution. The subdirectory
selector restores its contents directly beneath the destination, avoiding an
extra absolute-path hierarchy. It selects the entire backed-up canary source;
no include/exclude filters are needed. Keep ordinary restore locking enabled.

Record restore intent before invocation and exit status before comparison.
Do not pass `--delete`, restore into the original source, or clean up repository
objects. An earlier successful backup/integrity check does not prove restoration.

## Independent comparison and observation

Require exactly this destination tree:

| Relative path | Type | Mode | Size/content |
| --- | --- | --- | --- |
| `predata` | Directory | `0700` | No extra descendants |
| `predata/canary.txt` | Regular file | `0600` | 49 bytes including the final newline |

All restored objects must belong to `nautobot`; reject extra paths, symlinks and
special files. The file must equal the fixed manifest content and SHA-256
`0b8fefbdc586f053d6e69ee230d119d668e2dc7f4739fe61a334227d61142de2`.
Derive these expectations from the reviewed definition, not the restored output.
Also verify the retained original source before and after; source equality alone
is insufficient if both copies differ from the independent fixture.

Capture the boot ID and kernel journal cursor before the workload. Preserve the
existing 75-second delayed storage observation, cursor availability and complete
bounded event review. Require no storage errors, unchanged boot/source, empty
final locks and no cache. Reuse the canary journal and protected-file routines
where practical; do not duplicate another deployment framework.

## Failure, cleanup and acceptance

Use Ansible for staging, commands, evidence and cleanup. A small helper may own
durable restore-attempt/status and exact tree comparison. Bound commands to
600 seconds, streams to 4 MiB and controller work to 1800 seconds. The helper
limits its command sequence to 1500 seconds; a command timeout terminates and
waits for that child. A controller interruption cannot prove remote termination:
retain the intent and node evidence, classify the outcome as unknown, and inspect
the remote process before any separately authorized retry.

Remove each transient credential independently on success or failure and verify
absence. Retain the source, snapshot, partial or complete restore directory and
sanitized records. Failed restore/comparison, interruption or unknown cleanup
requires review; never retry automatically into the same or a new destination.
No rollback deletes repository objects or live data.

Acceptance requires successful restore, exact independent tree comparison,
source/boot continuity, quiet storage observation and proven credential cleanup.
Combined with the archived upload/full-data check, it can satisfy the pre-data
canary gate. It cannot accept application recovery, PostgreSQL restore, runtime
persistence, resource headroom or authority migration.

## Implementation and local validation

The reusable playbook is `../ansible/playbooks/restore-canary.yaml`; its launcher
is `../ansible/scripts/run-canary-restore.py`. The launcher verifies both terminal
archives, source cleanliness and the approved hash before secret resolution.
`restic/scripts/restore-canary.py` reuses the existing canary journal, protected
file and comparison routines. Offline tests exercise:

- Wrong repository/snapshot identity, missing predecessor or unapproved hash.
- Existing/nonempty targets, symlink ancestors, source overlap and wrong mount,
  owner or modes; each must stop before restore.
- Failed/interrupted restore and missing exit evidence, retaining partial data.
- Missing/extra paths, corrupt bytes, wrong modes, owners, symlinks and special
  files; no comparison may derive expectations from its own output.
- First credential-removal failure, later cleanup continuation, evidence retention,
  journal gaps/truncation, boot changes, storage errors and timeout handling.

Tests are wired into the existing validation entry point and pre-commit hooks. Validate target
Restic CLI behavior through the separately authorized execution preflight.
No target contact, restore or repository mutation occurred during preparation.

Reference: [Restic subdirectory restore](https://github.com/restic/restic/blob/master/doc/050_restore.rst).

## Execution approval

From the server repository, the separate live command is:

```sh
python3 Nautobot/ansible/scripts/run-canary-restore.py execute APPROVED_SHA256
```

`show-hash` checks the clean definition and predecessor archives without remote
access. Manifest readiness and `mutation_authorized: true` describe the eligible
execution path; `approval_record` remains ungranted until the operator approves
that exact digest. Neither field grants authorization on its own.

The authorized mutation is one isolated restore plus ordinary transient Restic
locks and protected evidence/credential staging on the single target. No backup,
repository initialization, destructive cleanup or application deployment is
included. Success still requires review of node records, delayed storage review
and controller/remote credential absence before recording acceptance.
