#!/usr/bin/env python3
"""Single-use canary upload records; Ansible owns staging and credential cleanup."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import resource
import stat
import subprocess
import tempfile
import time

LIMIT = 4 * 1024 * 1024


class Blocked(Exception):
    pass


def protected(path, directory=False):
    info = path.lstat()
    if (not (stat.S_ISDIR if directory else stat.S_ISREG)(info.st_mode)
            or info.st_uid != os.getuid()
            or stat.S_IMODE(info.st_mode) != (0o700 if directory else 0o600)):
        raise Blocked('unsafe_metadata')


def record(root, name, data):
    with (root / name).open('x', encoding='utf-8') as stream:
        os.chmod(root / name, 0o600)
        json.dump(data, stream, sort_keys=True)
        stream.flush()
        os.fsync(stream.fileno())
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def invoke(argv, env, timeout=600):
    def limits():
        resource.setrlimit(resource.RLIMIT_FSIZE, (LIMIT, LIMIT))
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        try:
            result = subprocess.run(argv, env=env, stdin=subprocess.DEVNULL,
                                    stdout=out, stderr=err, timeout=timeout,
                                    preexec_fn=limits, check=False)
        except subprocess.TimeoutExpired:
            raise Blocked('command_timeout') from None
        if out.tell() >= LIMIT or err.tell() >= LIMIT:
            raise Blocked('output_limit')
        out.seek(0)
        # Raw output is never persisted in decision records.
        return result.returncode, out.read()


def snapshots(raw):
    data = json.loads(raw)
    if not isinstance(data, list):
        raise Blocked('snapshot_json_invalid')
    found = {}
    for item in data:
        if not isinstance(item, dict) or not re.fullmatch('[0-9a-f]{64}', str(item.get('id', ''))):
            raise Blocked('snapshot_id_invalid')
        if item['id'] in found:
            raise Blocked('duplicate_snapshot_id')
        found[item['id']] = {k: item.get(k) for k in ('id', 'hostname', 'paths', 'tags')}
    return found


def select_snapshot(before, after, source, contract):
    if not set(before).issubset(after):
        raise Blocked('prior_snapshot_missing')
    new = set(after) - set(before)
    if len(new) != 1:
        raise Blocked('new_snapshot_count')
    sid = next(iter(new))
    item = after[sid]
    if (item['hostname'] != contract['hostname'] or item['paths'] != [str(source)]
            or item['tags'] != contract['tags']):
        raise Blocked('snapshot_metadata_mismatch')
    return sid


def ancestry(path):
    for ancestor in (path, *path.parents):
        if ancestor.is_symlink():
            raise Blocked('symlink_ancestor')
        if ancestor.exists() and not ancestor.is_dir():
            raise Blocked('ancestor_not_directory')


def tree(source, contract):
    protected(source, True)
    expected = {'predata', 'predata/canary.txt'}
    actual = {str(p.relative_to(source)) for p in source.rglob('*')}
    if actual != expected:
        raise Blocked('source_paths_mismatch')
    protected(source / 'predata', True)
    file = source / 'predata/canary.txt'
    protected(file)
    content = file.read_bytes()
    fixture = contract['files'][0]
    result = {'path': fixture['path'], 'size': len(content), 'mode': '0600',
              'sha256': hashlib.sha256(content).hexdigest()}
    if (result['size'] != fixture['size_bytes'] or result['sha256'] != fixture['sha256']
            or content != fixture['content_utf8'].encode()):
        raise Blocked('source_content_mismatch')
    return result


def create_source(contract, call):
    parent = Path(contract['source_root_pattern']).parent
    ancestry(parent)
    if not parent.parent.is_dir():
        raise Blocked('source_parent_missing')
    info = parent.parent.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o022:
        raise Blocked('source_parent_ownership_or_write_access')
    probe = parent if parent.exists() else parent.parent
    rc, mount = call(['/usr/bin/findmnt', '--noheadings', '--output', 'SOURCE', '--target', str(probe)])
    if rc or mount.decode().strip() != contract['required_filesystem']:
        raise Blocked('source_mount_mismatch')
    if not parent.exists():
        parent.mkdir(mode=0o700)
    protected(parent, True)
    source = Path(tempfile.mkdtemp(prefix='source.', dir=parent))
    (source / 'predata').mkdir(mode=0o700)
    file = source / 'predata/canary.txt'
    with file.open('xb') as stream:
        os.chmod(file, 0o600)
        stream.write(contract['files'][0]['content_utf8'].encode())
    tree(source, contract)
    return source


def backup(root, contract, runner=invoke, source_factory=create_source):
    protected(root, True)
    for name in ('repository', 'password', 'credentials.json', 'operation.json'):
        protected(root / name)
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
    commands = contract['commands']
    base = ['/usr/bin/restic', '--no-cache', '--repository-file', str(root / 'repository'),
            '--password-file', str(root / 'password')]
    status = {'result': 'blocked', 'upload_attempted': False, 'backup_exit_status': None,
              'integrity_exit_status': None, 'snapshot_id': None}
    record(root, 'started.json', status)
    try:
        rc, output = call(['/usr/bin/restic', 'version'])
        if rc or output.decode().strip() != contract['restic_version']:
            raise Blocked('version_mismatch')
        rc, output = call(base + commands['config'])
        config = json.loads(output) if rc == 0 else {}
        if config.get('id') != contract['repository']['id'] or config.get('version') != 2:
            raise Blocked('repository_identity_mismatch')
        source = source_factory(contract['dataset'], call)
        source_record = tree(source, contract['dataset'])
        record(root, 'source.json', {'root': str(source), 'file': source_record,
                                    'filesystem': contract['dataset']['required_filesystem'],
                                    'owner_uid': os.getuid(), 'directory_mode': '0700'})
        rc, output = call(base + commands['snapshots_before'])
        if rc:
            raise Blocked('before_snapshot_read_failed')
        before = snapshots(output)
        record(root, 'snapshots-before.json', before)
        record(root, 'upload-attempt.json', {'upload_attempted': True})
        status['upload_attempted'] = True
        argv = [str(source) if v == 'SOURCE_ROOT' else v for v in commands['backup']]
        rc, _ = call(base + argv)
        status['backup_exit_status'] = rc
        record(root, 'upload-result.json', {'exit_status': rc})
        after_rc, output = call(base + commands['snapshots_after'])
        if after_rc:
            raise Blocked('after_snapshot_read_failed')
        after = snapshots(output)
        record(root, 'snapshots-after.json', after)
        if rc != 0:
            raise Blocked('backup_failed_no_retry')
        sid = select_snapshot(before, after, source, contract['snapshot_identity'])
        status['snapshot_id'] = sid
        record(root, 'snapshot.json', {'id': sid, 'metadata': after[sid]})
        rc, _ = call(base + commands['integrity'])
        status['integrity_exit_status'] = rc
        record(root, 'integrity.json', {'exit_status': rc, 'full_read_data': True})
        if rc:
            raise Blocked('integrity_failed')
        if tree(source, contract['dataset']) != source_record:
            raise Blocked('source_changed')
        rc, locks = call(base + commands['locks_after'])
        if rc or locks.strip() or (root / '.cache').exists():
            raise Blocked('lock_or_cache_absence_unproved')
        status.update(result='backup_integrity_review_required', source_unchanged=True,
                      locks_empty=True, cache_absent=True)
    except Blocked as exc:
        status['error_class'] = str(exc)
    except Exception:
        status['error_class'] = 'unexpected_failure'
    finally:
        record(root, 'result.json', status)
    return status


def journal(mode, root, contract, runner=invoke, sleeper=time.sleep):
    env = {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'}
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    if mode == 'journal-baseline':
        rc, raw = runner(['/usr/bin/journalctl', '-k', '-n', '1', '-o', 'json', '--no-pager', '--quiet', '--all'], env, 30)
        entries = [json.loads(line) for line in raw.splitlines() if line]
        if rc or len(entries) != 1 or not entries[0].get('__CURSOR'):
            raise Blocked('journal_baseline_missing')
        return {'boot_id': boot, 'cursor': entries[0]['__CURSOR']}
    baseline = json.loads((root / 'journal-baseline.json').read_text())
    start = time.monotonic()
    sleeper(contract['observation']['delayed_seconds'])
    elapsed = time.monotonic() - start
    if elapsed < contract['observation']['delayed_seconds']:
        raise Blocked('observation_incomplete')
    if baseline['boot_id'] != boot or Path('/proc/sys/kernel/random/boot_id').read_text().strip() != boot:
        raise Blocked('boot_changed')
    cursor = baseline['cursor']
    rc, raw = runner(['/usr/bin/journalctl', '-k', '--cursor', cursor, '-n', '+1',
                      '-o', 'json', '--no-pager', '--quiet', '--all'], env, 30)
    entries = [json.loads(line) for line in raw.splitlines() if line]
    if rc or len(entries) != 1 or entries[0].get('__CURSOR') != cursor:
        raise Blocked('journal_cursor_unavailable')
    rc, raw = runner(['/usr/bin/journalctl', '-k', '--after-cursor', cursor,
                      '-o', 'json', '--no-pager', '--quiet', '--all'], env, 30)
    if rc:
        raise Blocked('journal_read_failed')
    entries = [json.loads(line) for line in raw.splitlines() if line]
    if any(not isinstance(e, dict) or not isinstance(e.get('MESSAGE'), str) for e in entries):
        raise Blocked('journal_message_unavailable')
    pattern = contract['observation']['storage_event_pattern']
    matches = sum(bool(re.search(pattern, str(e.get('MESSAGE', '')), re.I)) for e in entries)
    return {'boot_unchanged': True, 'cursor_verified': True, 'entries_reviewed': len(entries),
            'storage_event_count': matches, 'delayed_seconds': elapsed, 'passed': matches == 0}


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['backup', 'journal-baseline', 'journal-review'])
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    if args.root.parent != Path('/tmp') or not re.fullmatch(r'nautobot-canary\.[A-Za-z0-9_]+', args.root.name):
        return 69
    contract = json.loads((args.root / 'operation.json').read_text())
    try:
        if args.mode == 'backup':
            if pwd.getpwuid(os.getuid()).pw_name != 'nautobot':
                raise Blocked('execution_user_mismatch')
            result = backup(args.root, contract)
            return 0 if result['result'] == 'backup_integrity_review_required' else 69
        print(json.dumps(journal(args.mode, args.root, contract)))
        return 0
    except Exception:
        print(json.dumps({'result': 'blocked', 'error_class': 'boundary_failed'}))
        return 69


if __name__ == '__main__':
    raise SystemExit(main())
