#!/usr/bin/env python3
"""Read-only installation guards. Ansible owns all filesystem/unit mutations."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import socket
import stat
import subprocess
import shutil
from zoneinfo import ZoneInfo


class Refused(ValueError):
    """Fixed diagnostic codes safe for the controller receipt."""


def require(ok, reason):
    if not ok:
        raise Refused(reason)


def command(argv):
    result = subprocess.run(argv, stdin=subprocess.DEVNULL, capture_output=True,
                            timeout=30, cwd='/')
    require(result.returncode == 0 and len(result.stdout) < 1048576
            and len(result.stderr) < 1048576, 'native_command_failed')
    return result.stdout.decode().strip()


def system(*args):
    return command(['/usr/bin/systemctl', '--user', *args])


def metadata(path, directory=False):
    info = path.lstat()
    require((stat.S_ISDIR if directory else stat.S_ISREG)(info.st_mode)
            and info.st_uid == 999 and info.st_gid == 985
            and stat.S_IMODE(info.st_mode) == (0o700 if directory else 0o600)
            and not any(p.is_symlink() for p in path.parents), 'unsafe_metadata')


def services():
    names = ['nautobot-'+r+'.service' for r in ('postgresql', 'redis', 'web', 'worker', 'scheduler')]
    rows = {}
    for name in names:
        values = dict(x.split('=', 1) for x in system('show', name,
            '--property=ActiveState,SubState,InvocationID').splitlines())
        require(values['ActiveState'] == 'active' and values['SubState'] == 'running', 'service_health')
        rows[name] = values['InvocationID']
    code = "import http.client;c=http.client.HTTPConnection('127.0.0.1',8080,timeout=3);c.request('GET','/health/',headers={'Host':'j2-svpi4mf.local.theama.co'});print(c.getresponse().status);c.close()"
    require(command(['/usr/bin/podman', 'exec', 'nautobot-web', 'python3', '-c', code]) == '200', 'http_health')
    return rows


def runtime_files(root, expected):
    metadata(root, True)
    actual = set()
    for path in root.rglob('*'):
        if path.is_dir() and not path.is_symlink():
            metadata(path, True)
        else:
            metadata(path)
            name = str(path.relative_to(root)); actual.add(name)
            require(name in expected and hashlib.sha256(path.read_bytes()).hexdigest() == expected[name], 'runtime_drift')
    require(actual == set(expected), 'runtime_members')


def unit_links(op, required):
    directory = Path(op['unit_directory'])
    for name in op['unit_names']:
        path = directory/name
        if os.path.lexists(path):
            require(path.is_symlink() and os.readlink(path) == op['runtime_directory']+'/units/'+name, 'unit_link_drift')
        else:
            require(not required, 'unit_link_missing')


def check(op, expected, action):
    require(os.getuid() == 999 and socket.gethostname() == op['target']['host'], 'target_identity')
    require(Path('/proc/sys/kernel/random/boot_id').read_text().strip() == op['boot_id'], 'boot_drift')
    root = Path(op['runtime_directory']); state = Path(op['state_directory'])
    before = services()
    require(all(before[n] == v for n, v in op['baseline']['service_invocations'].items()), 'service_drift')
    for name, digest in {**op['baseline']['artifact_sha256'], **op['baseline']['binding_artifact_sha256']}.items():
        require(hashlib.sha256(Path(name).read_bytes()).hexdigest() == digest, 'artifact_drift')
    for row in op['packages']:
        require(command(['/usr/bin/dpkg-query', '-W', '-f=${Version} ${Architecture}', row['name']])
                == row['version']+' '+row['architecture'], 'package_drift')
    credentials = op['binding']['credentials']
    token = Path(credentials['token_file']); metadata(token)
    meta = Path(credentials['metadata_file']); metadata(meta)
    actual = json.loads(meta.read_text())
    require(all(actual.get(k) == v for k, v in op['credential_identity'].items()), 'credential_metadata_drift')
    require(datetime.fromisoformat(actual['expires_at']) > datetime.now(timezone.utc), 'credential_expired')
    staging = Path(op['supervisor']['staging_directory']); metadata(staging, True)
    require(command(['/usr/bin/findmnt', '-no', 'FSTYPE', '-T', str(staging)]) == 'ext4', 'staging_filesystem')
    require(shutil.disk_usage(staging).free >= op['binding']['minimum_free_bytes']
            + sum(op['binding']['capture_limits'].values()), 'staging_capacity')
    require(command(['/usr/bin/systemctl', 'show', 'e2scrub_all.service', '--property=ActiveState', '--value']) == 'inactive', 'scrub_active')
    media = '/var/lib/nautobot/.local/share/containers/storage/volumes/nautobot-nautobot_media/_data'
    command(['/usr/bin/podman', 'unshare', '/usr/bin/python3', '-B', '-c',
             'from pathlib import Path;p=Path('+repr(media)+');assert not any(x.is_symlink() for x in (p,*p.parents))'])
    entries = command(['/usr/bin/podman', 'unshare', '/usr/bin/find', media, '-printf', '%y|%P\\n']).splitlines()
    require(entries and all(x.startswith('d|') for x in entries), 'populated_or_unsafe_media')
    require(sorted(x[2:] for x in entries if x[2:]) == op['baseline']['media_directories'], 'media_drift')
    if action == 'preflight':
        now = datetime.now(ZoneInfo('America/Chicago'))
        require(now.hour != 3, 'installation_overlaps_backup_window')
        age = datetime.now(timezone.utc)-datetime.fromisoformat(op['baseline']['collected_at'])
        require(0 <= age.total_seconds() <= 86400, 'baseline_expired')
        require(not any(p.is_symlink() for p in (root, state, *root.parents, *state.parents)), 'path_symlink')
        if not os.path.lexists(root):
            require(not os.path.lexists(state), 'existing_state')
            for name in op['unit_names']:
                require(not os.path.lexists(Path(op['unit_directory'])/name), 'existing_unit_path')
                require(system('show', name, '--property=LoadState', '--value') == 'not-found', 'existing_unit')
                require(not system('show', name, '--property=DropInPaths', '--value'), 'unit_dropins')
            unit_directory = Path(op['unit_directory'])
            require(not any(p.is_symlink() for p in (unit_directory, *unit_directory.parents)), 'unit_parent_symlink')
            if unit_directory.exists(): metadata(unit_directory, True)
            return {'fresh': True, 'services': before}
    runtime_files(root, expected)
    metadata(state, True)
    phase = 'idle'
    if (state/'state.json').exists():
        metadata(state/'state.json'); phase = json.loads((state/'state.json').read_text())['phase']
    require(phase in ('idle', 'complete'), 'unresolved_runtime_state')
    unit_links(op, True)
    metadata(Path(op['unit_directory']), True)
    for name in op['unit_names']:
        require(not system('show', name, '--property=DropInPaths', '--value'), 'unit_dropins')
        require(system('show', name, '--property=FragmentPath', '--value') in (
            op['unit_directory']+'/'+name, op['runtime_directory']+'/units/'+name), 'foreign_unit_fragment')
    for name in op['enabled_timers']:
        require(system('is-enabled', name) == 'enabled', 'timer_not_enabled')
        require(system('show', name, '--property=ActiveState', '--value') == 'active', 'timer_not_active')
    return {'fresh': False, 'installed': True, 'scheduled_cycle_accepted': False, 'services': before,
            'timers': {n: system('show', n, '--property=TimersCalendar,NextElapseUSecRealtime,ActiveState,UnitFileState')
                       for n in op['enabled_timers']}}


def rollback_guard(op, expected):
    """Never stop an unrelated unit or remove recovery while writers may be paused."""
    require(os.getuid() == 999 and socket.gethostname() == op['target']['host'], 'target_identity')
    unit_links(op, False)
    for name in op['unit_names']:
        require(not system('show', name, '--property=DropInPaths', '--value'), 'unit_dropins')
        fragment = system('show', name, '--property=FragmentPath', '--value')
        require(not fragment or fragment in (op['unit_directory']+'/'+name,
                op['runtime_directory']+'/units/'+name), 'foreign_unit_fragment')
    state = Path(op['state_directory'])/'state.json'
    if state.exists():
        metadata(state)
        require(json.loads(state.read_text())['phase'] in ('idle', 'complete'), 'manual_recovery_required')
    for path in Path(op['runtime_directory']).rglob('*'):
        if path.is_dir() and not path.is_symlink():
            metadata(path, True)
        else:
            metadata(path)
            name = str(path.relative_to(op['runtime_directory']))
            require(not path.is_symlink() and name in expected
                    and hashlib.sha256(path.read_bytes()).hexdigest() == expected[name], 'rollback_drift')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['preflight', 'verify', 'files', 'rollback-guard', 'rollback-disabled'])
    parser.add_argument('operation'); parser.add_argument('expected')
    args = parser.parse_args()
    op = json.loads(args.operation); expected = json.loads(args.expected)
    try:
        if args.action == 'files':
            result = runtime_files(Path(op['runtime_directory']), expected)
        elif args.action.startswith('rollback-'):
            result = rollback_guard(op, expected)
            if args.action == 'rollback-disabled':
                for name in op['enabled_timers']:
                    require(system('show', name, '--property=ActiveState', '--value') != 'active', 'rollback_timer_active')
                    require(system('show', name, '--property=UnitFileState', '--value') not in ('enabled', 'enabled-runtime'), 'rollback_timer_enabled')
        else:
            result = check(op, expected, args.action)
        print(json.dumps(result or {'rollback_safe': True}))
    except Exception as exc:
        raise SystemExit('schedule_install_refused:'+(str(exc) if isinstance(exc, Refused) else type(exc).__name__))
