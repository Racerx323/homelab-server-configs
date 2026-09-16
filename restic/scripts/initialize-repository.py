#!/usr/bin/env python3
"""Single-use initialization boundary; Ansible owns staging and secret cleanup."""
import argparse
import json
import os
from pathlib import Path
import pwd
import re
import stat
import subprocess
import tempfile

LIMIT = 65536


class Blocked(Exception):
    pass


def protected(path, directory=False):
    info = path.lstat()
    kind = stat.S_ISDIR if directory else stat.S_ISREG
    if not kind(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != (0o700 if directory else 0o600):
        raise Blocked('unsafe_input_metadata')


def record(root, name, data):
    # Exclusive records prohibit replay; never retain command output or secrets.
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


def invoke(argv, environment):
    # File-backed capture bounds memory; RLIMIT_FSIZE bounds retained output.
    import resource
    def limits():
        resource.setrlimit(resource.RLIMIT_FSIZE, (LIMIT, LIMIT))
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        try:
            result = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=out, stderr=err,
                                    env=environment, timeout=120, check=False, preexec_fn=limits)
        except subprocess.TimeoutExpired:
            raise Blocked('command_timeout') from None
        if out.tell() >= LIMIT or err.tell() >= LIMIT:
            raise Blocked('command_output_limit')
        out.seek(0)
        return result.returncode, out.read()


def initialize(root, expected_url, expected_version, runner=invoke, executable='/usr/bin/restic'):
    protected(root, True)
    for name in ('repository', 'password', 'credentials.json'):
        protected(root / name)
    if (root / 'repository').read_text() != expected_url:
        raise Blocked('repository_mismatch')
    credentials = json.loads((root / 'credentials.json').read_text())
    if set(credentials) != {'id', 'key'} or not all(isinstance(v, str) and v and not any(c in v for c in '\r\n\x00') for v in credentials.values()):
        raise Blocked('invalid_credentials')
    password = (root / 'password').read_bytes()
    if not password or any(c in password for c in (b'\n', b'\r', b'\x00')):
        raise Blocked('invalid_password')
    env = {'PATH': '/usr/bin:/bin', 'HOME': str(root), 'LC_ALL': 'C',
           'AWS_ACCESS_KEY_ID': credentials['id'], 'AWS_SECRET_ACCESS_KEY': credentials['key'],
           'AWS_EC2_METADATA_DISABLED': 'true', 'TMPDIR': str(root)}
    record(root, 'started.json', {'stage': 'initialization', 'mutation_attempted': False})
    status = {'result': 'blocked', 'mutation_attempted': False, 'init_exit_status': None}
    try:
        rc, output = runner([executable, 'version'], env)
        if rc != 0 or output.decode().strip() != expected_version:
            raise Blocked('version_mismatch')
        base = [executable, '--no-cache', '--repository-file', str(root / 'repository'),
                '--password-file', str(root / 'password')]
        read = base + ['--no-lock', 'cat', 'config']
        rc, _ = runner(read, env)
        record(root, 'absence.json', {'exit_status': rc, 'absent': rc == 10})
        if rc != 10:
            raise Blocked('absence_not_proven')
        # Durable intent precedes mutation. Interruption after this point is unknown,
        # never grounds for an automatic retry, even if no exit result exists.
        record(root, 'init-attempt.json', {'mutation_attempted': True})
        status['mutation_attempted'] = True
        rc, _ = runner(base + ['init', '--repository-version', 'stable'], env)
        status['init_exit_status'] = rc
        record(root, 'init-result.json', {'exit_status': rc})
        if rc != 0:
            raise Blocked('initialization_failed_state_requires_review')
        rc, output = runner(read, env)
        if rc != 0:
            raise Blocked('readback_failed')
        config = json.loads(output)
        if config.get('version') != 2 or not isinstance(config.get('id'), str) or not re.fullmatch('[0-9a-f]{64}', config['id']):
            raise Blocked('readback_invalid')
        # Explicit no-cache on every access; enumerate remote lock objects read-only.
        rc, output = runner(base + ['--no-lock', 'list', 'locks'], env)
        if rc != 0 or output.strip() or (root / '.cache').exists():
            raise Blocked('cache_or_lock_absence_unproved')
        status.update(result='initialized_review_required', repository_id=config['id'], format_version=2)
    except Blocked as exc:
        status['error_class'] = str(exc)
    except Exception:
        status['error_class'] = 'unexpected_failure'
    finally:
        record(root, 'result.json', status)
    return status


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    parser.add_argument('repository_url')
    parser.add_argument('version')
    args = parser.parse_args()
    if pwd.getpwuid(os.getuid()).pw_name != 'nautobot':
        return 69
    if args.root.parent != Path('/tmp') or not re.fullmatch(r'nautobot-restic-init\.[A-Za-z0-9_]+', args.root.name):
        return 69
    try:
        result = initialize(args.root, args.repository_url, args.version)
        return 0 if result['result'] == 'initialized_review_required' else 69
    except Exception:
        return 69


if __name__ == '__main__':
    raise SystemExit(main())
