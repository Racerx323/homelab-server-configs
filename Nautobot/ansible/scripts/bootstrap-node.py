#!/usr/bin/env python3
"""Bootstrap-only node boundaries; Ansible owns startup and cleanup ordering."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('continuation', Path(__file__).with_name('continuation-node.py'))
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)
i = c.inspection
r = c.runtime
require = i.require
TRANSIENT = Path('/run/user/999/nautobot-bootstrap')
NAME = 'nautobot-bootstrap'
LABEL = 'homelab.nautobot.bootstrap'
STEPS = ('configuration', 'pending_migrations', 'account_absent', 'creation', 'account_verified')


def preflight(root, op):
    require(os.geteuid() == 0, 'root_required')
    i.identities(op)
    before = i.stopped()
    c.copied_trees(op)
    require(not TRANSIENT.exists() and not TRANSIENT.is_symlink(), 'bootstrap_residue')
    for suffix in ('.timer', '.service'):
        require(i.command(['/usr/bin/systemctl', 'show', op['guard_unit']+suffix, '--property=LoadState', '--value']).strip() == 'not-found', 'existing_guard')
    for role in ('web', 'worker', 'scheduler'):
        require(i.state(role)['ActiveState'] == 'inactive', 'application_active')
    require(i.command(['/usr/bin/findmnt', '--noheadings', '--output', 'SOURCE', '--target', str(c.HOME)]).strip() == '/dev/sda2', 'storage_mount')
    require(shutil.disk_usage(c.HOME).free >= 4*1024**3, 'disk_headroom')
    mem = dict(line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines())
    require(int(mem['MemAvailable'].split()[0])*1024 >= 4*1024**3, 'memory_headroom')
    for role in ('postgresql', 'redis'):
        name = 'nautobot-'+role+'_data'
        v = r.podman('volume', 'inspect', name)[0]
        path = Path(v['Mountpoint'])
        expected = Path('/var/lib/nautobot/.local/share/containers/storage/volumes')/name/'_data'
        require(path == expected and path.resolve() == expected, 'volume_path')
        i.no_submounts(path)
        if role == 'postgresql':
            require((path/'PG_VERSION').read_text().strip() == '17' and not (path/'postmaster.pid').exists(), 'postgres_not_cold')
    value = {'passed': True, 'before': before, 'cold_copies_verified': True}
    r.storage.record(root, 'preflight.json', value)
    return value


def create_args(op):
    home = str(c.HOME)
    args = ['create', '--name', NAME, '--label', LABEL+'='+op['operation']['id'], '--pull=never',
            '--network=nautobot-private', '--image-volume=ignore', '--read-only', '--read-only-tmpfs=false',
            '--memory=1536m', '--memory-swap=1536m', '--cpus=2', '--pids-limit=256', '--timeout=660',
            '--user=999:999', '--security-opt=no-new-privileges', '--cap-drop=ALL', '--log-driver=none',
            '--env-file', home+'/migration.env', '--env', 'NAUTOBOT_CONFIG=/opt/nautobot/nautobot_config.py',
            '--env', 'PYTHONDONTWRITEBYTECODE=1']
    for path, size, mode in [('/tmp', 64, '1777'), ('/run', 16, '0755'), ('/prom_cache', 8, '1777'),
                             ('/opt/nautobot/git', 16, '1777'), ('/opt/nautobot/jobs', 16, '1777'),
                             ('/opt/nautobot/media', 16, '1777'), ('/opt/nautobot/static', 256, '1777')]:
        args += ['--tmpfs', f'{path}:rw,size={size}m,mode={mode}']
    args += ['--volume', home+'/nautobot_config.py:/opt/nautobot/nautobot_config.py:ro']
    for name in ('bootstrap-application.py', 'initialize-application.py', 'input.json'):
        args += ['--volume', str(TRANSIENT/name)+':/run/bootstrap/'+name+':ro']
    return args + ['--entrypoint=/bin/sleep', op['runtime']['images']['custom']['reference'], 'infinity']


def probe_boundary(op):
    v = r.podman('inspect', NAME)[0]
    require(v['Config']['Labels'].get(LABEL) == op['operation']['id'], 'container_owner')
    require(v['State']['Running'] and not v['State'].get('OOMKilled'), 'probe_not_running')
    require(v['Image'].removeprefix('sha256:') == op['runtime']['images']['custom']['id'], 'probe_image')
    require(v['HostConfig']['Memory'] == 1610612736 and v['HostConfig']['MemorySwap'] == 1610612736, 'probe_limits')
    require(v['Config']['User'] == '999:999' and v['HostConfig']['ReadonlyRootfs'], 'probe_user')
    require(not v['HostConfig'].get('PortBindings') and not any((v['NetworkSettings'].get('Ports') or {}).values()), 'published_ports')
    require(set(v['NetworkSettings']['Networks']) == {'nautobot-private'}, 'probe_network')
    require(not any(m['Type'] == 'volume' for m in v['Mounts']), 'probe_durable_mount')
    require(not any('SUPERUSER' in value or 'INITIAL_ADMIN' in value for value in v['Config']['Env']), 'persistent_admin_secret')


def receipt(raw):
    value = json.loads(raw)
    require(set(value) <= {'passed', 'creation_attempted', 'steps', 'failed_phase'}, 'receipt_shape')
    require(type(value['passed']) is bool and type(value['creation_attempted']) is bool, 'receipt_shape')
    require(value.get('failed_phase') in (*STEPS, 'input_or_resource_boundary', None), 'receipt_phase')
    require(isinstance(value['steps'], dict) and set(value['steps']) <= set(STEPS), 'receipt_steps')
    for step in value['steps'].values():
        require(set(step) <= {'exit_status', 'error', 'output_limited'}, 'step_shape')
        require(step.get('exit_status') is None or type(step['exit_status']) is int, 'step_status')
        require(step.get('error') in (None, 'timeout', 'output_limit', 'command_unavailable'), 'step_error')
        require(type(step.get('output_limited', False)) is bool, 'step_output')
    if value['passed']:
        require(value['creation_attempted'] and set(value['steps']) == set(STEPS)
                and all(s.get('exit_status') == 0 and not s.get('error') and not s.get('output_limited') for s in value['steps'].values()), 'receipt_success')
    return value


def run_probe(root, op):
    c.ready(root, op)
    require(i.state('migration')['ActiveState'] == 'inactive', 'migration_active')
    for name in ('bootstrap-application.py', 'initialize-application.py'):
        require(i.file_hash(TRANSIENT/name) == op['bootstrap']['probe_sha256'][name], 'probe_drift')
    i.command(r.USER+['/usr/bin/podman']+create_args(op))
    i.command(r.USER+['/usr/bin/podman', 'start', NAME])
    probe_boundary(op)
    rc, raw = r.storage.invoke(r.USER+['/usr/bin/podman', 'exec', NAME, 'python3', '/run/bootstrap/bootstrap-application.py'],
                               {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C.UTF-8'}, 630)
    value = receipt(raw)
    r.storage.record(root, 'native.json', value)
    require(rc == 0 and value['passed'], 'native_bootstrap_failed')
    i.identities(op)
    c.ready(root, op)
    return value


def cleanup(root, op):
    # Every action is attempted even if another fails; guard uses the same path.
    statuses = {}
    try:
        containers = r.podman('ps', '--all', '--format', 'json')
        present = [v for v in containers if NAME in v.get('Names', [])]
        if present:
            v = r.podman('inspect', NAME)[0]
            require(v['Config']['Labels'].get(LABEL) == op['operation']['id'], 'container_owner')
            i.command(r.USER+['/usr/bin/podman', 'rm', '--force', '--time=10', NAME], 30)
        statuses['probe'] = True
    except Exception:
        statuses['probe'] = False
    for role in ('redis', 'postgresql'):
        try:
            i.command(r.USER+['/usr/bin/systemctl', '--user', 'stop', '--no-block', 'nautobot-'+role+'.service'], 15)
            statuses[role] = True
        except Exception:
            statuses[role] = False
    for name in ('input.json', 'bootstrap-application.py', 'initialize-application.py'):
        try:
            if TRANSIENT.exists():
                s = TRANSIENT.lstat()
                require(stat.S_ISDIR(s.st_mode) and s.st_uid == 999 and stat.S_IMODE(s.st_mode) == 0o700, 'transient_parent')
                (TRANSIENT/name).unlink(missing_ok=True)
            statuses[name] = True
        except Exception:
            statuses[name] = False
    try:
        if TRANSIENT.exists():
            TRANSIENT.rmdir()
        statuses['directory'] = not TRANSIENT.exists() and not TRANSIENT.is_symlink()
    except Exception:
        statuses['directory'] = False
    return {'passed': all(statuses.values()), 'cleanup': statuses}


def stopped(root, op):
    services = i.stopped()
    require(not TRANSIENT.exists() and not TRANSIENT.is_symlink(), 'bootstrap_residue')
    i.identities(op)
    c.copied_trees(op)
    return {'passed': True, 'services': services, 'transient_removed': True, 'cold_copies_verified': True}


def main():
    os.umask(0o077)
    os.chdir('/')
    mode, directory = sys.argv[1:]
    root = Path(directory)
    require(root.parent == Path('/tmp') and re.fullmatch(r'nautobot-runtime\.[A-Za-z0-9_]+', root.name), 'root_boundary')
    op = json.loads((root/'operation.json').read_text())
    try:
        if mode == 'preflight': value = preflight(root, op)
        elif mode == 'ready': value = c.ready(root, op)
        elif mode == 'run': value = run_probe(root, op)
        elif mode == 'cleanup': value = cleanup(root, op)
        elif mode == 'stopped': value = stopped(root, op)
        elif mode == 'evidence': value = receipt((root/'native.json').read_text())
        else: value = r.storage.journal(mode, root, op)
        print(json.dumps(value))
        return 0 if value.get('passed', True) else 69
    except Exception as exc:
        allowed = {'boot_drift','unit_drift','configuration_drift','cold_copy_changed','existing_guard',
                   'bootstrap_residue','native_bootstrap_failed','container_residue','stale_service','probe_drift'}
        code = str(exc) if isinstance(exc, ValueError) and str(exc) in allowed else 'bootstrap_boundary_failed'
        print(json.dumps({'passed': False, 'error': code}))
        return 69


if __name__ == '__main__':
    raise SystemExit(main())
