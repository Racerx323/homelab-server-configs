#!/usr/bin/env python3
"""Read-only node baseline collector; run only during authorized target contact."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess

USER = ['/usr/sbin/runuser', '--user', 'nautobot', '--', '/usr/bin/env',
        'XDG_RUNTIME_DIR=/run/user/999', 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus']
ROLES = ('postgresql', 'redis', 'migration', 'web', 'worker', 'scheduler')


def command(argv):
    # Temporary regular output files bound both retained output and producer size.
    import resource
    import tempfile
    def limit():
        resource.setrlimit(resource.RLIMIT_FSIZE, (1048576, 1048576))
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        result = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=out, stderr=err,
                                cwd='/', timeout=60, env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C.UTF-8'},
                                preexec_fn=limit)
        out.seek(0)
        data = out.read(1048577)
    if result.returncode or len(data) > 1048576:
        raise ValueError('read_only_command_failed')
    return data.decode()


def files(directory):
    result = {}
    for path in sorted(directory.iterdir()):
        info = path.lstat()
        if not stat.S_ISREG(info.st_mode):
            result[path.name] = {'regular': False}
            continue
        row = {'regular': True, 'uid': info.st_uid, 'gid': info.st_gid,
               'mode': oct(stat.S_IMODE(info.st_mode)), 'size': info.st_size}
        # Never hash or print credential contents, environment files or secret objects.
        if path.suffix in ('.py', '.container', '.network', '.volume'):
            if info.st_size > 1048576:
                raise ValueError('oversized_artifact')
            row['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        result[path.name] = row
    return result


def collect():
    if os.geteuid() != 0 or command(['/usr/bin/hostname']).strip() != 'j2-svpi4mf':
        raise ValueError('target_identity')
    result = {'schema_version': 1, 'host': 'j2-svpi4mf', 'accepted': False,
              'collected_at': datetime.now(timezone.utc).isoformat(),
              'boot_id': Path('/proc/sys/kernel/random/boot_id').read_text().strip()}
    result['services'] = {}
    for role in ROLES:
        raw = command(USER + ['/usr/bin/systemctl', '--user', 'show', 'nautobot-' + role + '.service',
                              '--property=ActiveState,SubState,InvocationID,Result,ExecMainStatus,MainPID,ControlPID'])
        result['services'][role] = dict(line.split('=', 1) for line in raw.splitlines() if '=' in line)
    result['containers'] = json.loads(command(USER + ['/usr/bin/podman', 'ps', '--all', '--format', 'json']))
    result['images'] = json.loads(command(USER + ['/usr/bin/podman', 'images', '--format', 'json']))
    result['volumes'] = json.loads(command(USER + ['/usr/bin/podman', 'volume', 'ls', '--format', 'json']))
    result['listeners'] = command(['/usr/bin/ss', '-H', '-ltn'])
    result['mount'] = command(['/usr/bin/findmnt', '--json', '--target', '/var/lib/nautobot'])
    result['free_bytes'] = shutil.disk_usage('/var/lib/nautobot').free
    result['memory'] = Path('/proc/meminfo').read_text()
    result['runtime_files'] = files(Path('/var/lib/nautobot/runtime'))
    result['quadlets'] = files(Path('/var/lib/nautobot/.config/containers/systemd'))
    command(['/usr/bin/python3', '-I', '/usr/local/lib/nautobot-network/backend_guard.py', 'check'])
    result['guard'] = {'verified': True}
    result['journal_cursor'] = command(['/usr/bin/journalctl', '-n', '0', '--show-cursor', '--no-pager'])
    if Path('/proc/sys/kernel/random/boot_id').read_text().strip() != result['boot_id']:
        raise ValueError('boot_changed')
    # A reviewer must compare retained identities and storage history; this is
    # collection, not acceptance, and cannot activate the startup launcher.
    return result


if __name__ == '__main__':
    try:
        print(json.dumps(collect()))
    except Exception:
        print(json.dumps({'accepted': False, 'error': 'baseline_collection_incomplete'}))
        raise SystemExit(69)
