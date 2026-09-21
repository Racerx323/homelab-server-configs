# Canary backup and full integrity check

## Prepared scope

The active operation defines the upload/integrity portion of
[isolated pre-data verification](ISOLATED_BACKUP_RESTORE.md). Initialization
is accepted and archived; this definition binds its exact repository ID and
terminal result. It does not initialize a repository or exercise application data.

The Ansible execution path is implemented and locally validated. The operation
is eligible for exact-bundle approval; its readiness booleans do not grant live
authorization. Existing initialization and absence launchers reject its stage.

- Launcher: `Nautobot/ansible/scripts/run-canary-backup.py`.
- Playbook: `Nautobot/ansible/playbooks/backup-canary.yaml`.
- Node boundary: `restic/scripts/canary-backup.py`.
- Tests: `restic/tests/test_canary_backup.py`, run by CI and pre-commit.

The launcher reuses protected credential delivery, bounded capture and cleanup.
It verifies archived initialization bytes and tag, baseline/provider hashes,
clean source and exact approval hash before resolving credentials. Use `show-hash`
to obtain the frozen identity, then `execute APPROVED_SHA256` only after approval.
The private approval packet records the exact reviewed hash and command.

## Execution

Use the existing protected credential-delivery and bounded-output utilities.
Ansible owns target preflight, staging, ordered commands, evidence retention and
independent cleanup attempts. The node helper retains durable upload intent and status across controller
interruption; it never retries upload or deletes repository data.

Target `ama@10.1.2.170`; run Restic as `nautobot`, with the exact accepted version
and existing Doppler references. Verify accepted repository ID/format before any
upload. Verify the source root is on `/dev/sda2`, with no symlink ancestors, and
check existing parent ownership/modes rather than silently changing them.

Create one unique `source.*` directory under
`/var/lib/nautobot/backup-restore-tests/`. Parent creation, when absent, belongs
in the reviewed operation after topology validation. Directories use `0700` and
the sole file uses `0600`. `predata/canary.txt` is exactly 49 bytes, including the
terminal newline; the manifest holds its fixed content and independent SHA-256.
Keep credentials, markers and evidence outside the uploaded source tree.

All Restic commands use `--no-cache` and protected repository/password files.
The command arrays in `manifests/operation.yaml` define the exact CLI shape:

1. Verify config, user/version, source mount and boot ID; capture a kernel journal
   cursor before source creation or workload commands.
2. Create the exact source tree; record independent path, size, mode and hash checks.
3. Capture the complete `snapshots --json` result before backup.
4. Record upload intent, then run one `backup --json --host j2-svpi4mf` with tag
   `nautobot-predata-canary-v1` and the exact source root. Keep normal locking.
5. Persist exit status before assertions. Capture the after snapshot set, including
   after an unsuccessful upload when read-only classification remains possible.
6. Require exit 0, preservation of prior IDs, exactly one new full 64-character ID,
   and matching hostname, exact source path and tag. Backup summary/display order
   is not authoritative. Exit 3 means incomplete backup and blocks acceptance.
7. Run `check --read-data` with normal locking and require exit 0. A default or
   subset check cannot satisfy this gate.
8. Recheck the source tree and boot ID; retain a 75-second delayed observation
   window. Review the complete cursor-bounded kernel storage events. Missing,
   truncated or ambiguous evidence prevents acceptance.
9. Verify empty lock listing and no cache; attempt all credential removals
   independently, verify absence, and retain sanitized evidence.

Command bounds are 600 seconds and 4 MiB per stream, with a 1500-second node
workload deadline and an 1800-second controller limit. Do not increase bounds or retry upload silently. A timeout requires retained
state review, including potentially still-running remote work and cleanup status.

## Acceptance and recovery

Record upload attempted/result, exact new snapshot ID, full integrity result,
storage observations and cleanup separately. Retain source and snapshot for the
next stage. There is no automatic rollback of uploaded repository objects.
Any upload or integrity failure retains evidence; do not delete, forget, prune,
unlock, repair or rerun backup automatically. Do not run integrity checking after
an unsuccessful upload until that outcome has been reviewed.

This stage cannot accept restoration or application recovery. Its successor uses
the accepted full snapshot ID and a new empty `restore.*` directory under the
same approved parent, with separately reviewed authorization and tree comparison.

## Implementation validation

The offline suite exercises the actual helper, launcher gates and Ansible cleanup:

- Reject identity, version, source topology, file-content and bundle mismatch
  before upload or credential access where applicable.
- Handle zero/multiple new snapshots, missing prior IDs, wrong host/path/tag,
  malformed JSON and shortened IDs without selecting a snapshot.
- Treat upload status 3, interrupted upload and failed full check as unaccepted;
  preserve attempted mutation and never retry or delete automatically.
- Exercise cleanup on success, early failure, failure after upload and first-file
  removal failure; later secret removals and evidence retention must still run.
- Reject missing/truncated journal evidence, boot changes, storage errors and
  unavailable cleanup proof. Test delayed-window and command timeout handling.

Tests run through the existing local validation entry point and CI hooks.
Ansible syntax, schemas and secret scanning are checked before freezing inputs.
No live backup or target inspection occurred during implementation. ARM64 Restic
behavior, source-parent permissions and kernel journal access remain live checks
under the approved execution path. Missing evidence cannot be accepted.

CLI references: [snapshot JSON and scripting](https://github.com/restic/restic/blob/master/doc/075_scripting.rst),
[backup flags and exit statuses](https://github.com/restic/restic/blob/master/doc/manual_rest.rst),
[full-data check implementation](https://github.com/restic/restic/blob/master/cmd/restic/cmd_check.go).
The target's accepted 0.18.0 help is the final authority during authorized preflight.
