#!/usr/bin/env python3
"""Read-only runtime acceptance on the node; streamed over SSH, never installed."""
import json
import os
from pathlib import Path
import re
import resource
import stat
import subprocess
import tempfile
import time
import urllib.request

USER = ['/usr/sbin/runuser', '--user', 'nautobot', '--', '/usr/bin/env',
        'XDG_RUNTIME_DIR=/run/user/999', 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus']
ROLES = ('postgresql', 'redis', 'migration', 'web', 'worker', 'scheduler')
ERROR_CODES = frozenset(['boot', 'bootstrap_secret', 'cgroup_path', 'command_or_output_boundary', 'container_state', 'credential_metadata', 'cursor_unavailable', 'effective_memory', 'http', 'image', 'invocation', 'kernel_message', 'memory_config', 'mode', 'native_failure', 'native_receipt_count', 'native_receipt_shape', 'network', 'observation_short', 'oom', 'pid', 'private_ports', 'process_changed', 'root_required', 'runtime_probe_failed', 'service_state', 'static_type', 'storage_event', 'swap', 'unexpected_runtime_failure', 'unprivileged_readonly'])


def require(value, code):
    if not value:
        raise ValueError(code)


def run(argv):
    def limit():
        resource.setrlimit(resource.RLIMIT_FSIZE, (4194304, 4194304))
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        p = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=out, stderr=err,
                           cwd='/', timeout=40, preexec_fn=limit)
        out.seek(0); data = out.read(4194304)
    require(p.returncode == 0 and len(data) < 4194304, 'command_or_output_boundary')
    return data.decode()


def states():
    result = {}
    for role in ROLES:
        raw = run(USER + ['/usr/bin/systemctl', '--user', 'show', 'nautobot-'+role+'.service',
                         '--property=ActiveState,SubState,Result,ExecMainStatus,InvocationID,NRestarts'])
        row = dict(line.split('=', 1) for line in raw.splitlines() if '=' in line)
        require(row['ActiveState'] == 'active' and row['SubState'] == ('exited' if role == 'migration' else 'running')
                and row['Result'] == 'success' and row['ExecMainStatus'] == '0' and row['NRestarts'] == '0', 'service_state')
        result[role] = row
    return result


def native_receipt(entries, role):
    values = [json.loads(e['MESSAGE'].split('=', 1)[1]) for e in entries
              if isinstance(e.get('MESSAGE'), str) and e['MESSAGE'].startswith('NAUTOBOT_STARTUP_RESULT=')]
    require(len(values) == 1, 'native_receipt_count')
    value = values[0]
    expected = {'configuration', 'pending_migrations'}
    if role == 'migration': expected.add('post_upgrade')
    if role == 'web': expected.add('static_collection')
    require(value.get('passed') is True and value.get('role') == role and set(value.get('steps', {})) == expected, 'native_receipt_shape')
    require(all(v.get('exit_status') == 0 and not v.get('output_limited') and not v.get('error')
                for v in value['steps'].values()), 'native_failure')


def native():
    current = states()
    for role in ('migration', 'web', 'worker', 'scheduler'):
        invocation = current[role]['InvocationID']
        require(re.fullmatch('[0-9a-f]{32}', invocation), 'invocation')
        raw = run(['/usr/bin/journalctl', '_SYSTEMD_INVOCATION_ID='+invocation, '-o', 'json', '--no-pager', '--quiet'])
        native_receipt([json.loads(line) for line in raw.splitlines()], role)
    return {'native_checks_passed': True, 'all_services_healthy_without_restarts': True}


def http():
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    for path, mime in [('/health/', None), ('/static/admin/css/base.css', 'text/css')]:
        req = urllib.request.Request('http://127.0.0.1:8080'+path, headers={'Host': 'j2-svpi4mf.local.theama.co'})
        with opener.open(req, timeout=15) as response:
            require(response.status == 200 and response.geturl() == req.full_url and 0 < len(response.read(1048577)) <= 1048576, 'http')
            require(mime is None or response.headers.get_content_type() == mime, 'static_type')
    return {'health_and_static_passed': True}


def cgroup_evidence(pid, limit, no_swap, proc=Path('/proc'), cgroups=Path('/sys/fs/cgroup')):
    require(type(pid) is int and pid > 1, 'pid')
    cg = (proc/str(pid)/'cgroup').read_text().strip()
    require(cg.startswith('0::/') and '\n' not in cg, 'cgroup_v2')
    root = cgroups/cg[3:].lstrip('/')
    require(root.resolve().is_relative_to(cgroups.resolve()), 'cgroup_path')
    require((root/'memory.max').read_text().strip() == str(limit*1024**2), 'effective_memory')
    events = dict(line.split() for line in (root/'memory.events').read_text().splitlines())
    require(events['oom'] == '0' and events['oom_kill'] == '0', 'oom')
    if no_swap:
        require((root/'memory.swap.max').read_text().strip() == '0', 'swap')


def resources(expected):
    states()
    for role, limit in expected['limits_mib'].items():
        if role == 'migration': continue  # Exited oneshot proven by native receipt.
        v = json.loads(run(USER + ['/usr/bin/podman', 'inspect', 'nautobot-'+role]))[0]
        require(v['State']['Running'] and not v['State'].get('OOMKilled'), 'container_state')
        require(v['Image'].removeprefix('sha256:') == expected['images'][role].removeprefix('sha256:'), 'image')
        require(v['HostConfig']['Memory'] == limit*1024**2, 'memory_config')
        require(set(v['NetworkSettings']['Networks']) == {'nautobot-private'}, 'network')
        if role != 'web':
            require(not v['HostConfig'].get('PortBindings') and not any((v['NetworkSettings'].get('Ports') or {}).values()), 'private_ports')
        if role in ('web', 'worker', 'scheduler'):
            require(str(v['Config']['User']).split(':')[0] == '999' and v['HostConfig']['ReadonlyRootfs'], 'unprivileged_readonly')
            require(not any(e.startswith('DJANGO_SUPERUSER_') for e in v['Config']['Env']), 'bootstrap_secret')
        cgroup_evidence(v['State']['Pid'], limit, role in ('web', 'worker', 'scheduler'))
    for role in ('worker', 'scheduler'):
        heartbeat = '/tmp/nautobot_celery_' + ('beat' if role == 'scheduler' else 'worker') + '_heartbeat'
        code = 'import os,time;assert 0 <= time.time()-os.stat(' + repr(heartbeat) + ').st_mtime < 60'
        run(USER + ['/usr/bin/podman', 'exec', 'nautobot-'+role, 'python3', '-c', code])
    for role in ROLES:
        p = Path('/var/lib/nautobot/runtime')/(role+'.env'); s = p.lstat()
        require(stat.S_ISREG(s.st_mode) and s.st_uid == 999 and s.st_gid == 985 and stat.S_IMODE(s.st_mode) == 0o600, 'credential_metadata')
    return {'resources_and_secret_metadata_passed': True}


def storage(expected):
    before = states(); started = time.monotonic(); time.sleep(75)
    require(time.monotonic()-started >= 75, 'observation_short')
    require(Path('/proc/sys/kernel/random/boot_id').read_text().strip() == expected['boot_id'], 'boot')
    cursor = expected['journal_cursor']
    raw = run(['/usr/bin/journalctl', '--cursor', cursor, '-n', '+1', '-o', 'json', '--no-pager', '--quiet'])
    rows = [json.loads(line) for line in raw.splitlines()]
    require(len(rows) == 1 and rows[0]['__CURSOR'] == cursor, 'cursor_unavailable')
    raw = run(['/usr/bin/journalctl', '--after-cursor', cursor, '_TRANSPORT=kernel', '-o', 'json', '--no-pager', '--quiet'])
    rows = [json.loads(line) for line in raw.splitlines()]
    require(all(isinstance(row.get('MESSAGE'), str) for row in rows), 'kernel_message')
    require(not any(re.search(expected['storage_pattern'], row['MESSAGE'], re.I) for row in rows), 'storage_event')
    after = states()
    require(all(before[r]['InvocationID'] == after[r]['InvocationID'] for r in ROLES), 'process_changed')
    return {'delayed_storage_review_passed': True, 'boot_and_processes_continuous': True}


def main(mode, expected):
    require(os.geteuid() == 0, 'root_required')
    if mode == 'native': return native()
    if mode == 'http': return http()
    if mode == 'resources': return resources(expected)
    if mode == 'storage': return storage(expected)
    raise ValueError('mode')
