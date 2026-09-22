#!/usr/bin/env python3
"""Bounded runtime checks and independent stop guard; no acceptance by labels."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import urllib.request

spec = importlib.util.spec_from_file_location('base', Path(__file__).with_name('runtime-initialization-node.py'))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
ROLES = ('postgresql', 'redis', 'migration', 'web', 'worker', 'scheduler')
STOP = ('scheduler', 'worker', 'web', 'migration', 'redis', 'postgresql')


def service(role, runner=base.call):
    if role not in ROLES:
        raise ValueError('role')
    raw = runner(base.USER + ['/usr/bin/systemctl', '--user', 'show', 'nautobot-' + role + '.service',
                             '--property=ActiveState,SubState,Result,ExecMainStatus,InvocationID,MainPID,ControlPID'])
    return dict(line.split('=', 1) for line in raw.splitlines() if '=' in line)


def healthy(role, value):
    return (value.get('Result') == 'success' and value.get('ExecMainStatus') == '0'
            and value.get('ActiveState') == 'active'
            and value.get('SubState') == ('exited' if role == 'migration' else 'running')
            and bool(value.get('InvocationID')))


def processless(value):
    return ((value.get('ActiveState'), value.get('SubState')) in
            {('inactive', 'dead'), ('failed', 'failed')}
            and value.get('MainPID') == '0' and value.get('ControlPID') == '0')


def baseline_stopped(role, value):
    if not processless(value):
        return False
    if value.get('ActiveState') == 'inactive':
        return True
    # The reviewed configuration failure is retained until a new invocation.
    return (role == 'migration' and value.get('Result') == 'exit-code'
            and value.get('ExecMainStatus') == '69' and bool(value.get('InvocationID')))


def terminal(value):
    return value.get('ActiveState') == 'failed'


def stop_all(runner=base.call, inspect=service):
    result = {}; failed_units = []
    for role in STOP:
        try:
            runner(base.USER + ['/usr/bin/systemctl', '--user', 'stop', 'nautobot-' + role + '.service'], 120)
            value = inspect(role)
            result[role] = processless(value)
            if value.get('ActiveState') == 'failed':
                failed_units.append(role)
        except Exception:
            result[role] = False
    return {'passed': all(result.values()), 'stopped': result, 'failed_units_retained': failed_units}


def http_checks(opener=None):
    # Ignore controller/user proxy variables; never route this loopback check externally.
    opener = opener or urllib.request.build_opener(urllib.request.ProxyHandler({}))
    result = {}
    for path, kind in [('/health/', 'health'), ('/static/admin/css/base.css', 'static')]:
        request = urllib.request.Request('http://127.0.0.1:8080' + path,
                                         headers={'Host': 'j2-svpi4mf.local.theama.co'})
        with opener.open(request, timeout=15) as response:
            payload = response.read(1048577)
            result[kind] = (response.status == 200 and response.geturl() == request.full_url
                            and 0 < len(payload) <= 1048576)
            if kind == 'static':
                result[kind] = result[kind] and response.headers.get_content_type() == 'text/css'
    return {'passed': all(result.values()), 'http': result}


def main():
    if os.geteuid() != 0:
        return 69
    try:
        if len(sys.argv) == 2 and sys.argv[1] == 'stop':
            result = stop_all()
            result['no_containers'] = base.podman('ps', '--all', '--format', 'json') == []
            result['passed'] = result['passed'] and result['no_containers']
        elif len(sys.argv) == 3 and sys.argv[1] == 'baseline':
            if Path('/proc/sys/kernel/random/boot_id').read_text().strip() != sys.argv[2]:
                raise ValueError('boot_changed')
            states = {role: service(role) for role in ROLES}
            stopped = all(baseline_stopped(role, value) for role, value in states.items())
            no_containers = base.podman('ps', '--all', '--format', 'json') == []
            base.call(['/usr/bin/python3', '-I', '/usr/local/lib/nautobot-network/backend_guard.py', 'check'])
            result = {'passed': stopped and no_containers, 'services': states, 'guard_verified': True}
        elif len(sys.argv) == 3 and sys.argv[1] == 'state':
            role = sys.argv[2]
            value = service(role)
            result = {'passed': healthy(role, value), 'terminal': terminal(value), 'state': value}
        elif len(sys.argv) == 2 and sys.argv[1] == 'http':
            result = http_checks()
        else:
            raise ValueError('mode')
        print(json.dumps(result))
        return 0 if result['passed'] else 69
    except Exception:
        print(json.dumps({'passed': False, 'error': 'startup_check_failed'}))
        return 69


if __name__ == '__main__':
    raise SystemExit(main())
