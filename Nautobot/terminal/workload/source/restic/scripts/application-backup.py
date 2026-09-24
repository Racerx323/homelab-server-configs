#!/usr/bin/env python3
"""Bounded application payload production and Restic upload, never init/restore.

The consumer supplies reviewed capture commands and an immutable configuration.
Credentials are separate protected files, never part of that configuration.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import tempfile
import time

SECTIONS = ('postgresql_custom_dump', 'media', 'configuration',
            'image_dependency_manifest', 'quadlet_config_hashes', 'versions_migrations')
LIMIT = 4 * 1024 * 1024


class Blocked(ValueError):
    """Only fixed internal reason codes may be persisted."""


def require(ok, code):
    if not ok:
        raise Blocked(code)


def protected(path, directory=False):
    info = path.lstat()
    require((stat.S_ISDIR if directory else stat.S_ISREG)(info.st_mode)
            and info.st_uid == os.getuid()
            and stat.S_IMODE(info.st_mode) == (0o700 if directory else 0o600), 'unsafe_metadata')
    require(not any(p.is_symlink() for p in path.parents), 'symlink_ancestor')


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def record(path, data):
    raw = json.dumps(data, sort_keys=True).encode() + b'\n'
    require(len(raw) < LIMIT, 'receipt_limit')
    with path.open('xb') as stream:
        os.chmod(path, 0o600)
        stream.write(raw); stream.flush(); os.fsync(stream.fileno())
    fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try: os.fsync(fd)
    finally: os.close(fd)


def invoke(argv, env, deadline, destination=None, maximum=LIMIT, input_path=None):
    """Inherited process group permits the owning workload to stop all children."""
    require(isinstance(argv, list) and argv and all(isinstance(x, str) and '\x00' not in x for x in argv), 'argv')
    require(Path(argv[0]).is_absolute(), 'absolute_executable_required')
    remaining = deadline - time.monotonic()
    require(remaining > 0, 'backup_deadline')
    with tempfile.TemporaryFile() as errors, tempfile.TemporaryFile() as output:
        source = input_path.open('rb') if input_path else open(os.devnull, 'rb')
        target = destination.open('xb') if destination else output
        if destination:
            os.chmod(destination, 0o600)
        try:
            proc = subprocess.Popen(argv,
                                    stdin=source, stdout=target, stderr=errors, env=env, cwd='/')
            try:
                command_deadline = min(deadline, time.monotonic() + 1200)
                while proc.poll() is None:
                    require(time.monotonic() < command_deadline, 'command_timeout')
                    require(target.tell() < maximum and errors.tell() < LIMIT, 'output_limit')
                    time.sleep(0.05)
                rc = proc.returncode
            except BaseException:
                proc.terminate()
                try: proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill(); proc.wait(timeout=5)
                raise
            require(target.tell() < maximum and errors.tell() < LIMIT, 'output_limit')
            if destination:
                return rc, b''
            output.seek(0)
            return rc, output.read()
        finally:
            source.close()
            if destination: target.close()


def validate(spec):
    require(set(spec) == {'schema_version', 'operation_id', 'authorized', 'repository_id',
                         'restic', 'restic_version', 'repository_url', 'hostname', 'captures', 'dump_validator',
                         'source_consistency_reviewed', 'timeout_seconds', 'execution_uid', 'required_filesystem'}, 'contract_fields')
    require(spec['schema_version'] == 1 and spec['authorized'] is True, 'inactive_backup')
    require(type(spec['execution_uid']) is int and spec['execution_uid'] >= 0, 'execution_uid')
    require(isinstance(spec['required_filesystem'], str) and spec['required_filesystem'], 'required_filesystem')
    require(spec['source_consistency_reviewed'] is True, 'source_consistency_unreviewed')
    require(re.fullmatch('[a-z0-9][a-z0-9-]{0,95}', spec['operation_id']), 'operation_identity')
    require(re.fullmatch('[0-9a-f]{64}', spec['repository_id']), 'repository_identity')
    require(type(spec['timeout_seconds']) is int and 0 < spec['timeout_seconds'] <= 1700, 'timeout_bound')
    require(isinstance(spec['restic'], str) and Path(spec['restic']).is_absolute(), 'restic_path')
    require(isinstance(spec['repository_url'], str) and spec['repository_url'] and not any(c in spec['repository_url'] for c in '\r\n\x00'), 'repository_url')
    require(isinstance(spec['hostname'], str) and re.fullmatch('[a-zA-Z0-9_.-]{1,253}', spec['hostname']), 'snapshot_hostname')
    require(isinstance(spec['restic_version'], str) and 0 < len(spec['restic_version']) < 256, 'version_string')
    def argv(value):
        require(isinstance(value, list) and 0 < len(value) <= 64 and all(isinstance(x, str) and len(x) <= 16384 and not any(c in x for c in '\x00\r') for x in value) and Path(value[0]).is_absolute(), 'command_shape')
    argv(spec['dump_validator'])
    require(set(spec['captures']) == set(SECTIONS), 'missing_application_content')
    for capture in spec['captures'].values():
        require(set(capture) == {'argv', 'maximum_bytes'}, 'capture_fields')
        require(isinstance(capture['maximum_bytes'], int) and 0 < capture['maximum_bytes'] <= 1073741824, 'capture_limit')
        argv(capture['argv'])


def snapshot_set(raw):
    values = json.loads(raw)
    require(isinstance(values, list), 'snapshot_response')
    result = {}
    for value in values:
        identity = value.get('id', '')
        require(re.fullmatch('[0-9a-f]{64}', identity) and identity not in result, 'snapshot_identity')
        result[identity] = value
    return result


def run(root, spec, call=invoke):
    validate(spec)
    protected(root, True)
    require(os.getuid() == spec['execution_uid'], 'execution_identity')
    # These transient files must be staged independently, not in a frozen bundle.
    secret_paths = [root/'password', root/'credentials.json']
    for p in [root/'repository', *secret_paths]: protected(p)
    require(not (root/'application-backup-result.json').exists(), 'already_consumed')
    env = {'PATH': '/usr/bin:/bin', 'HOME': str(root), 'TMPDIR': str(root), 'LC_ALL': 'C',
           'AWS_EC2_METADATA_DISABLED': 'true'}
    status = {'kind': 'application_backup', 'operation_id': spec['operation_id'],
              'requested_at': time.time(), 'started': None, 'upload_attempted': False, 'upload_passed': False,
              'integrity_passed': False, 'snapshot_id': None, 'content_sha256': {}}
    record(root/'application-backup-started.json', status)
    deadline = time.monotonic() + spec['timeout_seconds']
    base = [spec['restic'], '--no-cache', '--repository-file', str(root/'repository'),
            '--password-file', str(root/'password')]
    def command(args, **kwargs): return call(args, env, deadline, **kwargs)
    def checked(args, **kwargs):
        rc, raw = command(args, **kwargs)
        require(rc == 0, 'command_failed')
        return raw
    try:
        require((root/'repository').read_text().strip() == spec['repository_url'], 'repository_url_mismatch')
        credentials = json.loads((root/'credentials.json').read_text())
        require(set(credentials) in (set(), {'id', 'key'}), 'credential_fields')
        if credentials:
            require(all(isinstance(v, str) and v and not any(c in v for c in '\x00\r\n') for v in credentials.values()), 'credential_value')
            env.update(AWS_ACCESS_KEY_ID=credentials['id'], AWS_SECRET_ACCESS_KEY=credentials['key'])
        require((root/'password').stat().st_size > 0, 'empty_password')
        require(checked([spec['restic'], 'version']).decode().strip() == spec['restic_version'], 'restic_version')
        config = json.loads(checked(base + ['cat', 'config']))
        require(config.get('id') == spec['repository_id'] and config.get('version') == 2, 'repository_mismatch')
        require(checked(['/usr/bin/findmnt', '--noheadings', '--output', 'SOURCE', '--target', str(root)]).decode().strip() == spec['required_filesystem'], 'source_mount')
        space = os.statvfs(root)
        require(space.f_bavail * space.f_frsize > sum(c['maximum_bytes'] for c in spec['captures'].values()), 'capture_capacity')
        payload = root/'payload'; payload.mkdir(mode=0o700)
        status['started'] = time.time()  # Actual capture/load begins after repository preflight.
        record(root/'application-capture-started.tmp', {'operation_id': spec['operation_id'], 'started': status['started']})
        os.rename(root/'application-capture-started.tmp', root/'application-capture-started.json')
        capture_env = {k: v for k, v in env.items() if not k.startswith('AWS_')}
        for name in SECTIONS:
            status['phase'] = 'capture_' + name
            capture = spec['captures'][name]
            rc, _ = call(capture['argv'], capture_env, deadline, destination=payload/name, maximum=capture['maximum_bytes'])
            require(rc == 0, 'capture_failed_' + name)
            require((payload/name).stat().st_size > 0, 'empty_capture')
            status['content_sha256'][name] = digest(payload/name)
        with (payload/'postgresql_custom_dump').open('rb') as stream:
            require(stream.read(5) == b'PGDMP', 'not_custom_format')
        checked(spec['dump_validator'], input_path=payload/'postgresql_custom_dump')
        status['phase'] = 'snapshot_baseline'
        before = snapshot_set(checked(base + ['snapshots', '--json']))
        record(root/'application-snapshots-before.json', sorted(before))
        status['phase'] = 'upload'
        status['upload_attempted'] = True
        record(root/'application-upload-attempt.json', {'attempted': True})
        rc, _ = command(base + ['backup', '--json', '--host', spec['hostname'], '--tag', spec['operation_id'], str(payload)])
        status['backup_exit_status'] = rc
        # Always retain IDs after a nonzero backup, including incomplete snapshots.
        after = snapshot_set(checked(base + ['snapshots', '--json']))
        record(root/'application-snapshots-after.json', sorted(after))
        new = set(after) - set(before)
        status['new_snapshot_ids'] = sorted(new)
        require(set(before).issubset(after) and len(new) == 1, 'snapshot_difference')
        sid = next(iter(new)); status['snapshot_id'] = sid
        row = after[sid]
        require(row.get('hostname') == spec['hostname'] and row.get('paths') == [str(payload)]
                and row.get('tags') == [spec['operation_id']], 'snapshot_metadata')
        require(rc == 0, 'backup_nonzero_snapshot_retained')
        status['upload_passed'] = True
        status['phase'] = 'integrity'
        rc, _ = command(base + ['check', '--read-data'])
        status['integrity_exit_status'] = rc
        require(rc == 0, 'integrity_failed_snapshot_retained')
        require(all(digest(payload/k) == v for k, v in status['content_sha256'].items()), 'payload_changed')
        require(not checked(base + ['list', 'locks']).strip(), 'locks_remain')
        status['integrity_passed'] = True
    except Exception as error:
        # Never persist command output, exceptions with paths/data or credentials.
        status['failure_class'] = type(error).__name__
        if isinstance(error, Blocked): status['reason'] = str(error)
    finally:
        cleanup = {}
        for path in secret_paths:
            try:
                protected(path); path.unlink(); cleanup[path.name] = not path.exists()
            except Exception: cleanup[path.name] = False
        status.update(finished=time.time(), credential_cleanup=cleanup,
                      accepted=False, restore_verified=False)
        record(root/'application-backup-result.json', status)
    return status


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', required=True, type=Path)
    args = parser.parse_args()
    protected(args.root, True)
    protected(args.root/'application-backup.json')
    # SIGTERM from the owner reaches finally and attempts every credential cleanup.
    def terminated(*_): raise InterruptedError('cancelled')
    signal.signal(signal.SIGTERM, terminated)
    result = run(args.root, json.loads((args.root/'application-backup.json').read_text()))
    return 0 if result['integrity_passed'] and all(result['credential_cleanup'].values()) else 1


if __name__ == '__main__': raise SystemExit(main())
