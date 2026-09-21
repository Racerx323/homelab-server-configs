#!/usr/bin/env python3
"""Restore one archived canary subtree; retain all data for independent review."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import pwd
import re
import sys
import tempfile
import time

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('canary_common', Path(__file__).with_name('canary-backup.py'))
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
Blocked = common.Blocked


def destination(contract, source, call):
    parent = Path(contract['root_pattern']).parent
    common.ancestry(parent)
    common.protected(parent, True)
    common.ancestry(source)
    for path in (parent, source):
        rc, mount = call(['/usr/bin/findmnt', '--noheadings', '--output', 'SOURCE', '--target', str(path)])
        if rc or mount.decode().strip() != contract['required_filesystem']:
            raise Blocked('restore_mount_mismatch')
    target = Path(tempfile.mkdtemp(prefix='restore.', dir=parent))
    validate_destination(target, source, parent)
    return target


def validate_destination(target, source, parent):
    common.ancestry(target)
    common.protected(target, True)
    resolved, original = target.resolve(strict=True), source.resolve(strict=True)
    if (target.parent != parent or not re.fullmatch(r'restore\.[A-Za-z0-9_]+', target.name)
            or resolved == original or original in resolved.parents or resolved in original.parents):
        raise Blocked('restore_path_overlap_or_boundary')
    if any(target.iterdir()):
        raise Blocked('restore_destination_not_empty')


def restore(root, contract, runner=common.invoke, target_factory=destination):
    common.protected(root, True)
    for name in ('repository', 'password', 'credentials.json', 'operation.json'):
        common.protected(root / name)
    if (root / 'repository').read_text() != contract['repository']['url']:
        raise Blocked('repository_url_mismatch')
    creds = json.loads((root / 'credentials.json').read_text())
    if set(creds) != {'id', 'key'} or not all(isinstance(v, str) and v and not any(c in v for c in '\r\n\x00') for v in creds.values()):
        raise Blocked('invalid_credentials')
    password = (root / 'password').read_bytes()
    if not password or any(c in password for c in (b'\r', b'\n', b'\x00')):
        raise Blocked('invalid_password')
    env = {'PATH': '/usr/bin:/bin', 'HOME': str(root), 'TMPDIR': str(root), 'LC_ALL': 'C',
           'AWS_EC2_METADATA_DISABLED': 'true', 'AWS_ACCESS_KEY_ID': creds['id'],
           'AWS_SECRET_ACCESS_KEY': creds['key']}
    deadline = time.monotonic() + 1500
    def call(argv):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise Blocked('workload_deadline')
        return runner(argv, env, min(600, remaining))
    base = ['/usr/bin/restic', '--no-cache', '--repository-file', str(root / 'repository'),
            '--password-file', str(root / 'password')]
    commands = contract['commands']
    status = {'result': 'blocked', 'restore_attempted': False, 'restore_exit_status': None,
              'snapshot_id': contract['snapshot']['id']}
    common.record(root, 'started.json', status)
    try:
        rc, output = call(['/usr/bin/restic', 'version'])
        if rc or output.decode().strip() != contract['restic_version']:
            raise Blocked('version_mismatch')
        rc, output = call(base + commands['config'])
        config = json.loads(output) if rc == 0 else {}
        if config.get('id') != contract['repository']['id'] or config.get('version') != 2:
            raise Blocked('repository_identity_mismatch')
        rc, output = call(base + commands['snapshot_metadata'])
        metadata = json.loads(output) if rc == 0 else {}
        # `cat snapshot` does not embed its object ID; the command selects it exactly.
        expected = contract['snapshot']['metadata']
        if any(metadata.get(k) != expected[k] for k in ('hostname', 'paths', 'tags')):
            raise Blocked('snapshot_metadata_mismatch')
        common.record(root, 'snapshot.json', {'id': status['snapshot_id'],
                      'metadata': {k: metadata[k] for k in ('hostname', 'paths', 'tags')}})
        source = Path(contract['snapshot']['source_root'])
        common.ancestry(source)
        before = common.tree(source, contract['expected_tree'])
        common.record(root, 'source.json', {'root': str(source.resolve()), 'file': before})
        target = target_factory(contract['destination'], source, call)
        validate_destination(target, source, Path(contract['destination']['root_pattern']).parent)
        common.record(root, 'destination.json', {'root': str(target.resolve()), 'empty': True,
                      'owner_uid': target.stat().st_uid, 'mode': '0700',
                      'filesystem': contract['destination']['required_filesystem']})
        common.record(root, 'restore-attempt.json', {'restore_attempted': True, 'target': str(target)})
        status['restore_attempted'] = True
        argv = [str(target) if v == 'NEW_EMPTY_RESTORE_ROOT' else v for v in commands['restore']]
        rc, _ = call(base + argv)
        status['restore_exit_status'] = rc
        common.record(root, 'restore-result.json', {'exit_status': rc})
        if rc:
            raise Blocked('restore_failed_no_retry')
        restored = common.tree(target, contract['expected_tree'])
        after = common.tree(source, contract['expected_tree'])
        if after != before:
            raise Blocked('source_changed')
        common.record(root, 'comparison.json', {'expected': contract['expected_tree'],
                      'restored_file': restored, 'source_before': before, 'source_after': after,
                      'exact_tree': True})
        rc, locks = call(base + commands['locks_after'])
        if rc or locks.strip() or (root / '.cache').exists():
            raise Blocked('lock_or_cache_absence_unproved')
        status.update(result='isolated_restore_review_required', source_unchanged=True,
                      exact_tree=True, locks_empty=True, cache_absent=True)
    except Blocked as exc:
        status['error_class'] = str(exc)
    except Exception:
        status['error_class'] = 'unexpected_failure'
    finally:
        common.record(root, 'result.json', status)
    return status


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['restore', 'journal-baseline', 'journal-review'])
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    if args.root.parent != Path('/tmp') or not re.fullmatch(r'nautobot-restore\.[A-Za-z0-9_]+', args.root.name):
        return 69
    try:
        contract = json.loads((args.root / 'operation.json').read_text())
        if args.mode == 'restore':
            if pwd.getpwuid(os.getuid()).pw_name != 'nautobot':
                raise Blocked('execution_user_mismatch')
            result = restore(args.root, contract)
            return 0 if result['result'] == 'isolated_restore_review_required' else 69
        print(json.dumps(common.journal(args.mode, args.root, contract)))
        return 0
    except Exception:
        print(json.dumps({'result': 'blocked', 'error_class': 'boundary_failed'}))
        return 69


if __name__ == '__main__':
    raise SystemExit(main())
