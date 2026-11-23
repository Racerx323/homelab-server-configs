#!/usr/bin/env python3
"""Native backend-trial recovery; invoked by the reviewed host-side systemd timer.

No Caddy/DNS actions. snapshot saves an active loopback baseline; restore returns
that baseline before removing this trial's guard. No acceptance/disarm shortcut.
"""
import argparse
import fcntl
import hashlib
import http.client
import importlib.util
import json
import os
import re
from pathlib import Path
import socket
import stat
import subprocess
import tempfile
import time

CONFIGS = ('/etc/webmin/miniserv.conf', '/etc/webmin/config')
ADDED = ('/etc/webmin/ingress.nft', '/etc/systemd/system/webmin-firewall.service',
         '/etc/systemd/system/webmin.service.d/30-proxy-ingress.conf')
PRESERVED_CONFIG = '/etc/webmin/system-status/config'




class NativeFailure(RuntimeError):
    def __init__(self, argv, status, exit_status=None):
        super().__init__('native_command_failed')
        self.details = {'command': list(argv[:3]), 'status': status,
                        'exit_status': exit_status}


def run(*argv, timeout=10):
    # Never serialize stdout/stderr on failure: native tools may include config.
    try:
        row = subprocess.run(argv, capture_output=True, timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        raise NativeFailure(argv, 'timeout') from None
    if row.returncode or len(row.stdout) > 65536 or len(row.stderr) > 65536:
        raise NativeFailure(argv, 'nonzero_or_output_limit', row.returncode)
    return row.stdout.decode('utf-8')


def stop_apply():
    argv = ('/usr/bin/systemctl', 'show', 'webmin-proxy-apply.service', '-p', 'LoadState', '--value')
    row = subprocess.run(argv, capture_output=True, timeout=10, check=False)
    # A completed transient unit may already have been garbage-collected.
    if row.returncode in (0, 1) and row.stdout == b'not-found\n' and not row.stderr:
        return
    if row.returncode or row.stdout != b'loaded\n' or len(row.stderr) > 65536:
        raise NativeFailure(argv, 'unexpected_apply_unit_state', row.returncode)
    run('/usr/bin/systemctl', 'stop', 'webmin-proxy-apply.service', timeout=30)


def safe_path(path):
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError('symlink_path')


def identity(path):
    safe_path(path)
    info = path.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_size > 262144:
        raise ValueError('unsafe_file')
    raw = path.read_bytes()
    after = path.stat()
    if any(getattr(info, k) != getattr(after, k) for k in
           ('st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_ctime_ns', 'st_mode', 'st_uid', 'st_gid')):
        raise ValueError('file_changed')
    return {'sha256': hashlib.sha256(raw).hexdigest(), 'uid': info.st_uid,
            'gid': info.st_gid, 'mode': stat.S_IMODE(info.st_mode)}


def put(path, raw, metadata):
    safe_path(path)
    fd, name = tempfile.mkstemp(prefix='.webmin-recovery-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            os.fchmod(stream.fileno(), metadata['mode'])
            os.fchown(stream.fileno(), metadata['uid'], metadata['gid'])
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def save(path, value):
    put(path, (json.dumps(value, sort_keys=True) + '\n').encode(),
        {'uid': 0, 'gid': 0, 'mode': 0o600})


def listeners():
    rows = run('/usr/bin/ss', '-H', '-lnt').splitlines()
    return {r.split()[3] for r in rows if len(r.split()) >= 4 and r.split()[3].endswith(':10000')}


def loopback():
    if listeners() != {'127.0.0.1:10000', '[::1]:10000'}:
        raise ValueError('loopback_listeners_differ')
    for host in ('127.0.0.1', '::1'):
        conn = http.client.HTTPConnection(host, 10000, timeout=5)
        try:
            conn.request('GET', '/session_login.cgi')
            if conn.getresponse().status != 200:
                raise ValueError('loopback_http_failed')
        finally:
            conn.close()


class BindingDrift(ValueError):
    def __init__(self, name, expected, observed):
        super().__init__('preserved_file_drift')
        self.details = {'path': name, 'expected': expected, 'observed': observed}


def unchanged(expected):
    for name, metadata in expected.items():
        try:
            observed = identity(Path(name))
        except (OSError, ValueError) as error:
            raise BindingDrift(name, metadata, {'unavailable': type(error).__name__}) from None
        if observed != metadata:
            raise BindingDrift(name, metadata, observed)


CONTROL_FIELDS = ('Type', 'Restart', 'RestartUSec', 'TimeoutStartUSec', 'TimeoutStopUSec',
                  'OOMPolicy', 'CPUQuotaPerSecUSec', 'MemoryHigh', 'MemoryMax',
                  'MemorySwapMax', 'TasksMax', 'KillMode', 'Requires', 'BindsTo', 'After',
                  'ActiveState', 'SubState', 'FragmentPath', 'DropInPaths',
                  'ConditionResult', 'StartLimitIntervalUSec', 'StartLimitBurst')
UNORDERED_FIELDS = {'Requires', 'BindsTo', 'After', 'DropInPaths'}


def controls():
    raw = run('/usr/bin/systemctl', 'show', 'webmin.service', '-p', ','.join(CONTROL_FIELDS))
    result = dict(line.split('=', 1) for line in raw.splitlines() if '=' in line)
    if set(result) != set(CONTROL_FIELDS):
        raise ValueError('missing_service_control')
    return {k: ' '.join(sorted(v.split())) if k in UNORDERED_FIELDS else v
            for k, v in result.items()}


def verify_controls(expected, guard_still_loaded=False):
    observed = controls()
    # The guard unit's Before= adds a reverse After= edge until it is unloaded.
    # Permit only that owned temporary edge while its restriction is retained.
    if guard_still_loaded and 'After' in observed:
        actual_after = set(observed['After'].split())
        expected_after = set(expected.get('After', '').split())
        if actual_after == expected_after | {'webmin-firewall.service'}:
            observed['After'] = expected.get('After', '')
    if observed != expected:
        raise ValueError('effective_service_control_drift')


def guard_absent():
    for name in ADDED:
        safe_path(Path(name))
        if Path(name).exists():
            raise ValueError('preexisting_ingress_artifact')
    tables = json.loads(run('/usr/sbin/nft', '--json', 'list', 'tables'))['nftables']
    if any(r.get('table', {}).get('family') == 'inet' and
           r['table'].get('name') == 'webmin' for r in tables):
        raise ValueError('preexisting_webmin_table')


def preserved_paths(binding):
    observed = binding['controls']
    paths = [observed['FragmentPath']] + observed['DropInPaths'].split()
    if not paths[0] or len(paths) > 17 or len(paths) != len(set(paths)):
        raise ValueError('invalid_installed_unit_set')
    for name in paths:
        if not re.fullmatch(r'/(?:usr/lib|lib|etc|run)/systemd/system/webmin\.service(?:\.d/[A-Za-z0-9_.-]+\.conf)?', name):
            raise ValueError('invalid_installed_unit_path')
    return {*paths, PRESERVED_CONFIG}


def snapshot(work, binding):
    if (work / 'state.json').exists():
        raise ValueError('snapshot_already_exists')
    if socket.gethostname() != binding['hostname']:
        raise ValueError('hostname_mismatch')
    if binding.get('resource_profile') is not None:
        raise ValueError('unsupported_resource_profile')
    if set(binding['files']) != (set(CONFIGS) | preserved_paths(binding)):
        raise ValueError('binding_file_set')
    unchanged(binding['files'])
    verify_controls(binding['controls'])
    guard_absent()
    if run('/usr/bin/systemctl', 'is-active', 'webmin.service').strip() != 'active':
        raise ValueError('webmin_not_active')
    if run('/usr/bin/systemctl', 'is-enabled', 'webmin.service').strip() != 'enabled':
        raise ValueError('webmin_not_enabled')
    loopback()
    for index, name in enumerate(CONFIGS):
        destination = work / f'config-{index}.before'
        if destination.exists():
            raise ValueError('backup_already_exists')
        put(destination, Path(name).read_bytes(), {'uid': 0, 'gid': 0, 'mode': 0o600})
        if identity(destination)['sha256'] != binding['files'][name]['sha256']:
            raise ValueError('backup_identity_mismatch')
    unchanged(binding['files'])
    save(work / 'state.json', {'phase': 'prepared', 'hostname': binding['hostname'],
         'files': binding['files'], 'controls': binding['controls'],
         'resource_profile': binding.get('resource_profile')})


def apply(work):
    state = json.loads((work / 'state.json').read_text())
    if state['phase'] != 'prepared' or state['hostname'] != socket.gethostname():
        raise ValueError('apply_state_mismatch')
    unchanged(state['files'])
    verify_controls(state['controls'])
    if run('/usr/bin/systemctl', 'is-active', 'webmin-proxy-recovery.timer').strip() != 'active':
        raise ValueError('recovery_timer_not_active')
    guard_absent()
    # All mutations execute in one bounded native service. The recovery service
    # stops that service before taking this lock, so late controller writes cannot
    # reopen listeners after restoration.
    state['phase'] = 'mutating'
    save(work / 'state.json', state)
    for source, target, mode in zip(
            ('ingress.nft', 'webmin-firewall.service', '30-proxy-ingress.conf'), ADDED,
            (0o600, 0o644, 0o644)):
        identity(work / source)
        put(Path(target), (work / source).read_bytes(), {'uid': 0, 'gid': 0, 'mode': mode})
    run('/usr/bin/systemctl', 'daemon-reload', timeout=30)
    run('/usr/bin/systemctl', 'enable', '--now', 'webmin-firewall.service', timeout=30)
    spec = importlib.util.spec_from_file_location('webmin_configure', work / 'configure-miniserv.py')
    producer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(producer)
    for name, policy in zip(CONFIGS, ('miniserv.json', 'webmin.json')):
        identity(work / policy)
        producer.configure(Path(name), json.loads((work / policy).read_text()))
    run('/usr/bin/systemctl', 'restart', 'webmin.service', timeout=90)
    state['phase'] = 'applied'
    save(work / 'state.json', state)


def restore(work):
    state = json.loads((work / 'state.json').read_text())
    if state['phase'] in ('prepared', 'cancelled'):
        if state['hostname'] != socket.gethostname():
            raise ValueError('recovery_binding_mismatch')
        unchanged(state['files'])
        verify_controls(state['controls'])
        guard_absent()
        loopback()
        state['phase'] = 'cancelled'
        save(work / 'state.json', state)
        return
    if state['phase'] == 'restored':
        loopback()
        unchanged(state['files'])
        verify_controls(state['controls'])
        return
    if state['phase'] not in ('mutating', 'applied', 'restoring', 'recovery-incomplete'):
        raise ValueError('invalid_recovery_state')
    if state['hostname'] != socket.gethostname() or set(state['files']) != (set(CONFIGS) | preserved_paths(state)):
        raise ValueError('recovery_binding_mismatch')
    # Validate both backups before touching the service. Never remove protection
    # after a missing/corrupt backup or changed preserved control.
    backups = []
    for index, name in enumerate(CONFIGS):
        backup = work / f'config-{index}.before'
        if identity(backup)['sha256'] != state['files'][name]['sha256']:
            raise ValueError('backup_identity_mismatch')
        backups.append(backup.read_bytes())
    unchanged({p: state['files'][p] for p in preserved_paths(state)})
    state['phase'] = 'restoring'
    save(work / 'state.json', state)
    try:
        run('/usr/bin/systemctl', 'stop', 'webmin.service', timeout=30)
        if run('/usr/bin/systemctl', 'show', 'webmin.service', '-p', 'MainPID', '--value').strip() != '0':
            raise ValueError('webmin_still_running')
        for name, raw in zip(CONFIGS, backups):
            put(Path(name), raw, state['files'][name])
        dropin = Path(ADDED[2])
        safe_path(dropin)
        dropin.unlink(missing_ok=True)
        run('/usr/bin/systemctl', 'daemon-reload', timeout=30)
        # Reset only this service's exhausted start-rate budget for exact recovery.
        run('/usr/bin/systemctl', 'reset-failed', 'webmin.service')
        run('/usr/bin/systemctl', 'start', 'webmin.service', timeout=70)
        deadline = time.monotonic() + 30
        while True:
            try:
                loopback()
                break
            except (OSError, ValueError):
                if time.monotonic() >= deadline:
                    raise
                time.sleep(1)
        unchanged(state['files'])
        verify_controls(state['controls'], guard_still_loaded=True)
        # Guard remains until exact loopback files, both HTTP paths and listeners pass.
        if Path(ADDED[1]).exists():
            run('/usr/bin/systemctl', 'disable', '--now', 'webmin-firewall.service', timeout=30)
        tables = json.loads(run('/usr/sbin/nft', '--json', 'list', 'tables'))['nftables']
        if any(r.get('table', {}).get('family') == 'inet' and
               r['table'].get('name') == 'webmin' for r in tables):
            run('/usr/sbin/nft', 'delete', 'table', 'inet', 'webmin')
        for name in ADDED[:2]:
            safe_path(Path(name))
            Path(name).unlink(missing_ok=True)
        run('/usr/bin/systemctl', 'daemon-reload', timeout=30)
        loopback()
        if run('/usr/bin/systemctl', 'is-enabled', 'webmin.service').strip() != 'enabled':
            raise ValueError('enabled_state_drift')
        verify_controls(state['controls'])
        state['phase'] = 'restored'
        save(work / 'state.json', state)
    except Exception:
        state['phase'] = 'recovery-incomplete'
        save(work / 'state.json', state)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['snapshot', 'apply', 'restore'])
    parser.add_argument('--work-directory', type=Path, required=True)
    parser.add_argument('--binding', type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    try:
        if os.geteuid() != 0:
            raise ValueError('root_required')
        work = args.work_directory
        safe_path(work)
        info = work.stat()
        if not work.is_absolute() or work.parent != Path('/run/webmin-proxy-trial') or not work.name.isalnum():
            raise ValueError('invalid_work_directory')
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o700:
            raise ValueError('unsafe_work_directory')
        lockpath = work / 'recovery.lock'
        safe_path(lockpath)
        with lockpath.open('a') as lock:
            for attempt in range(3):
                if args.action == 'restore':
                    # Stop before locking; apply holds the same lock. Recheck if
                    # the single authorized launch raced the first stop/read.
                    stop_apply()
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if args.action != 'restore' or attempt == 2:
                        raise
            if args.action == 'snapshot':
                identity(args.binding)
                snapshot(work, json.loads(args.binding.read_text()))
            else:
                if identity(work / 'state.json')['mode'] != 0o600:
                    raise ValueError('unsafe_state')
                if args.action == 'apply':
                    apply(work)
                else:
                    restore(work)
        print(json.dumps({'action': args.action, 'passed': True}))
        return 0
    except Exception as error:
        report = {'action': args.action, 'passed': False,
                  'error_class': type(error).__name__}
        if isinstance(error, BindingDrift):
            report['file_failure'] = error.details
        elif isinstance(error, NativeFailure):
            report['native_failure'] = error.details
        elif type(error) is ValueError and str(error).replace('_', '').isalnum():
            report['reason'] = str(error)
        print(json.dumps(report))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
