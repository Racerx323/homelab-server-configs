#!/usr/bin/env python3
"""Read-only retention selection followed by exact successful local-payload disposal."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import sys
import time

from capture_retained import verify_tree
from recurring_delivery import resolve
from recurring_disposal import dispose
from recurring_protection import atomic, lock, protected, require

SECRET_FILES = ('source-password', 'source-credentials.json')
POLICY = ['forget', '--dry-run', '--json', '--host', 'j2-svpi4mf', '--tag', 'nautobot-recurring',
          '--group-by', 'host,tags', '--keep-daily', '7', '--keep-weekly', '5', '--keep-monthly', '12']


def load(path):
    protected(path); require(path.stat().st_size < 1048576, 'metadata_size')
    return json.loads(path.read_text())


def producer():
    spec = importlib.util.spec_from_file_location('producer', Path(__file__).with_name('application-backup.py'))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def cleanup(evidence):
    root = evidence/'credentials'
    result = {}
    if root.exists():
        protected(root, True)
        for name in SECRET_FILES:
            path = root/name
            try:
                if os.path.lexists(path):
                    protected(path); path.unlink()
                result[name] = not os.path.lexists(path)
            except Exception:
                result[name] = False
        # Unknown residue is retained for review, never recursively removed.
        result['no_other_residue'] = not list(root.iterdir())
    else:
        result['no_credential_directory'] = True
    atomic(evidence/'cleanup.json', result)
    return all(result.values())


def analyse(op, root, env, call):
    """No lock objects, cache, retagging, removal or prune; all reads are bounded."""
    base = [op['restic']['path'], '--no-lock', '--no-cache', '--repo', op['repository']['url'],
            '--password-file', str(root/'source-password')]
    deadline = time.monotonic()+180
    commands = []
    def checked(args):
        entry = {'arguments': args, 'exit_status': None}
        commands.append(entry); atomic(root.parent/'repository-commands.json', commands)
        try:
            code, raw = call(base+args, env, deadline, maximum=1048576)
            entry['exit_status'] = code
        finally:
            atomic(root.parent/'repository-commands.json', commands)
        require(code == 0, 'repository_read_failed')
        return json.loads(raw)
    repository_id = checked(['cat', 'config'])['id']
    require(repository_id == op['repository']['id'], 'repository_identity')
    before = checked(['snapshots', '--json'])
    require(isinstance(before, list) and len(before) <= 256, 'snapshot_inventory')
    rows = {r['id']: r for r in before}
    require(len(rows) == len(before) and set(rows) == set(op['snapshot_ids']), 'snapshot_inventory_drift')
    eligible = {sid for sid, row in rows.items() if row.get('hostname') == 'j2-svpi4mf'
                and 'nautobot-recurring' in row.get('tags', [])}
    require(eligible == set(op['eligible_snapshot_ids']) and eligible, 'retention_selection')
    require(all(rows[sid].get('tags') == ['nautobot-recurring'] for sid in eligible), 'ambiguous_tags')
    approved = rows[op['snapshot_id']]
    require(approved['paths'] == [op['payload_root']+'/payload'] and op['snapshot_id'] in eligible,
            'snapshot_provenance')
    groups = checked(POLICY)
    require(isinstance(groups, list) and len(groups) == 1, 'retention_groups')
    keep = [r['id'] for r in groups[0].get('keep', []) or []]
    remove = [r['id'] for r in groups[0].get('remove', []) or []]
    require(len(set(keep+remove)) == len(keep+remove) and set(keep+remove) == eligible, 'retention_partition')
    require(op['snapshot_id'] in keep and not set(remove).intersection(op['protected_snapshot_ids']),
            'recovery_reference_selected')
    after = checked(['snapshots', '--json'])
    require(sorted(before, key=lambda r:r['id']) == sorted(after, key=lambda r:r['id']), 'repository_changed')
    return dict(read_only=True, repository_id=repository_id, policy=POLICY, inventory=before,
                inventory_after=after, keep=keep, would_remove=remove,
                excluded=sorted(set(rows)-eligible), repository_unchanged=True, deletion_authorized=False)


def run(op, evidence, health, resolver=resolve, call=None):
    claim = evidence/'claimed.json'
    if os.path.lexists(claim):
        return 1
    with claim.open('x') as stream:
        os.chmod(claim, 0o600); json.dump({'operation_id': op['operation']['id']}, stream)
    result = dict(accepted=False, deletion_started=False, disposal_complete=False, checks_passed=False)
    root = Path(op['payload_root']); capture = Path(op['capture_root'])
    try:
        protected(evidence, True)
        require(os.getuid() == op['target']['uid'] and os.getgid() == op['target']['gid'], 'service_identity')
        require(Path('/proc/sys/kernel/random/boot_id').read_text().strip() == op['boot_id'], 'boot_changed')
        # Existing locks only: no new files inside retained capture evidence.
        for name in ('run.lock', 'state.lock'):
            protected(capture/'state'/name)
        with lock(capture/'state/run.lock', blocking=False), lock(capture/'state/state.lock', blocking=False):
            verify_tree(capture, op['qualification_tree']); verify_tree(root, op['payload_tree'])
            state = load(capture/'state/state.json')
            require(state['phase'] == 'complete' and state['root'] == str(root) and state['exit_status'] == 0,
                    'unresolved_capture')
            require(health() == op['services'], 'service_changed')
            require(not os.path.lexists(root/'payload-disposal.json'), 'disposal_already_attempted')
            require(load(root/'application-backup-result.json')['snapshot_id'] == op['snapshot_id'], 'accepted_snapshot')
            require(not any(os.path.lexists(root/n) for n in (*SECRET_FILES, 'password', 'credentials.json')),
                    'credential_residue')
            for name, identity in op['payload_file_metadata'].items():
                info = (root/'payload'/name).lstat()
                require(dict(bytes=info.st_size, nlink=info.st_nlink, device=info.st_dev, inode=info.st_ino) == identity,
                        'payload_identity_changed')
            for program, digest in ((op['restic']['path'], op['restic']['sha256']),
                                    (op['credentials']['doppler'], op['doppler_sha256'])):
                require(hashlib.sha256(Path(program).read_bytes()).hexdigest() == digest, 'executable_changed')
            creds = evidence/'credentials'; creds.mkdir(mode=0o700)
            try:
                resolver(op['credentials'], creds)
                for name in SECRET_FILES:
                    protected(creds/name)
                keys = load(creds/'source-credentials.json')
                require(set(keys) in ({'id', 'key'}, set()), 'credential_fields')
                env = dict(PATH='/usr/bin:/bin', HOME=str(creds), TMPDIR=str(creds), LC_ALL='C',
                           TZ='America/Chicago', AWS_EC2_METADATA_DISABLED='true')
                if keys:
                    require(all(isinstance(v, str) and v and not any(c in v for c in '\r\n\x00') for v in keys.values()),
                            'credential_value')
                    env.update(AWS_ACCESS_KEY_ID=keys['id'], AWS_SECRET_ACCESS_KEY=keys['key'])
                report = analyse(op, creds, env, call or producer().invoke)
                require(len(json.dumps(report).encode()) < 1048576, 'analysis_receipt_size')
                atomic(evidence/'retention-analysis.json', report)
            finally:
                require(cleanup(evidence), 'credential_cleanup_failed')
            # No secrets or remote subprocesses remain when irreversible local disposal begins.
            verify_tree(root, op['payload_tree'])
            require(health() == op['services'], 'service_changed')
            result['deletion_started'] = True
            atomic(evidence/'result.json', result)
            dispose(root, protected, require, atomic)
            result['disposal_complete'] = True
            require(load(root/'payload-disposal.json')['snapshot_id'] == op['snapshot_id'], 'disposal_snapshot')
            expected = json.loads(json.dumps(op['payload_tree']))
            expected['files'] = {n:r for n,r in expected['files'].items() if not n.startswith('payload/')}
            marker = root/'payload-disposal.json'; info = marker.stat()
            expected['files'][marker.name] = dict(uid=info.st_uid, gid=info.st_gid, mode=info.st_mode & 0o777,
                                                sha256=hashlib.sha256(marker.read_bytes()).hexdigest())
            verify_tree(root, expected); verify_tree(capture, op['qualification_tree'])
            require(health() == op['services'], 'service_changed')
            result['checks_passed'] = True
    except Exception as error:
        result['phase'] = 'manual_intervention' if result['deletion_started'] else 'preflight_failed'
        result['failure_class'] = type(error).__name__
        if isinstance(error, ValueError) and re.fullmatch('[a-z_]{1,80}', str(error)):
            result['reason'] = str(error)
    finally:
        result['credential_cleanup'] = cleanup(evidence)
        atomic(evidence/'result.json', result)
    return 0 if result['checks_passed'] and result['credential_cleanup'] else 1


def main():
    os.umask(0o077); sys.dont_write_bytecode = True
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=('run', 'cleanup')); parser.add_argument('operation', type=Path)
    args = parser.parse_args(); op = load(args.operation); evidence = args.operation.parent
    require(op['operation']['execution_enabled'] is True and evidence == Path(op['evidence_root']), 'execution_disabled')
    if args.action == 'cleanup':
        return 0 if cleanup(evidence) else 1
    capture = Path(op['capture_root']); verify_tree(capture, op['qualification_tree'])
    sys.path.insert(0, str(capture/'scripts'))
    import recurring_node
    def terminated(*_):
        raise InterruptedError('cancelled')
    signal.signal(signal.SIGTERM, terminated)
    return run(op, evidence, recurring_node.health)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception:
        raise SystemExit('disposal_qualification_refused; inspect protected receipts')
