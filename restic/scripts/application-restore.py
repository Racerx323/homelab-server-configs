#!/usr/bin/env python3
"""Retrieve six hash-bound application files from one exact snapshot into new staging."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import signal
import time

spec = importlib.util.spec_from_file_location('backup', Path(__file__).with_name('application-backup.py'))
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


def retrieve(root, contract):
    backup.protected(root, True)
    result = {'retrieved': False, 'phase': 'preflight', 'credential_cleanup': {}}
    secrets = [root/'password', root/'credentials.json']
    try:
        required = {'snapshot_id', 'repository_id', 'repository_url', 'restic', 'restic_version',
                    'hostname', 'tags', 'payload_path', 'content_sha256', 'maximum_bytes'}
        backup.require(set(contract) == required, 'contract_fields')
        for field in ('snapshot_id', 'repository_id'):
            backup.require(re.fullmatch('[0-9a-f]{64}', contract[field]) is not None, 'exact_identity')
        source = PurePosixPath(contract['payload_path'])
        backup.require(source.is_absolute() and '..' not in source.parts and str(source) == contract['payload_path'], 'payload_path')
        backup.require(set(contract['content_sha256']) == set(backup.SECTIONS)
                       and set(contract['maximum_bytes']) == set(backup.SECTIONS), 'sections')
        for name in backup.SECTIONS:
            backup.require(re.fullmatch('[0-9a-f]{64}', contract['content_sha256'][name]) is not None, 'content_hash')
            backup.require(type(contract['maximum_bytes'][name]) is int
                           and 0 < contract['maximum_bytes'][name] <= 268435456, 'size_bound')
        backup.require(Path(contract['restic']).is_absolute(), 'restic_path')
        for path in [root/'repository', *secrets]: backup.protected(path)
        backup.require((root/'repository').read_text().strip() == contract['repository_url'], 'repository_url')
        credentials = json.loads((root/'credentials.json').read_text())
        backup.require(set(credentials) in (set(), {'id', 'key'}), 'credential_fields')
        env = {'PATH': '/usr/bin:/bin', 'HOME': str(root), 'LC_ALL': 'C'}
        if credentials:
            backup.require(all(isinstance(v, str) and v for v in credentials.values()), 'credentials')
            env.update(AWS_ACCESS_KEY_ID=credentials['id'], AWS_SECRET_ACCESS_KEY=credentials['key'])
        deadline = time.monotonic() + 1200
        def checked(argv, **kwargs):
            rc, out = backup.invoke(argv, env, deadline, **kwargs)
            backup.require(rc == 0, 'retrieval_command_failed')
            return out
        base = [contract['restic'], '--no-cache', '--repository-file', str(root/'repository'),
                '--password-file', str(root/'password')]
        backup.require(checked([contract['restic'], 'version']).decode().strip() == contract['restic_version'], 'restic_version')
        config = json.loads(checked(base + ['cat', 'config']))
        backup.require(config['id'] == contract['repository_id'] and config['version'] == 2, 'repository_identity')
        rows = json.loads(checked(base + ['snapshots', '--json', contract['snapshot_id']]))
        backup.require(len(rows) == 1 and rows[0]['id'] == contract['snapshot_id'], 'snapshot_identity')
        row = rows[0]
        backup.require(row['hostname'] == contract['hostname'] and row['tags'] == contract['tags']
                       and row['paths'] == [str(source)], 'snapshot_metadata')
        backup.require(os.statvfs(root).f_bavail * os.statvfs(root).f_frsize > sum(contract['maximum_bytes'].values()), 'capacity')
        destination = root/'retrieved'
        destination.mkdir(mode=0o700)  # Never overlay an existing restore.
        result['phase'] = 'retrieval'
        for name in backup.SECTIONS:
            target = destination/name
            checked(base + ['dump', contract['snapshot_id'], str(source/name)],
                    destination=target, maximum=contract['maximum_bytes'][name])
            backup.require(backup.digest(target) == contract['content_sha256'][name], 'payload_hash')
        result.update(retrieved=True, snapshot_id=contract['snapshot_id'], phase='complete')
    except Exception as error:
        result['failure_class'] = type(error).__name__
        if isinstance(error, backup.Blocked): result['reason'] = str(error)
    finally:
        for path in secrets:
            try:
                backup.protected(path); path.unlink()
                result['credential_cleanup'][path.name] = not path.exists()
            except Exception:
                result['credential_cleanup'][path.name] = False
        backup.record(root/'retrieval-result.json', result)
    return result


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    def stop(*_): raise InterruptedError('terminated')
    signal.signal(signal.SIGTERM, stop)
    backup.protected(args.root/'restore.json')
    try:
        contract = json.loads((args.root/'restore.json').read_text())
    except (ValueError, UnicodeError):
        contract = {}  # Reject malformed input through the credential-finalizing path.
    result = retrieve(args.root, contract)
    return 0 if result['retrieved'] and all(result['credential_cleanup'].values()) else 1


if __name__ == '__main__': raise SystemExit(main())
