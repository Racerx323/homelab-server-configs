#!/usr/bin/env python3
"""Bounded runtime checks and independent stop guard; no acceptance by labels."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import re
import socket
import urllib.error
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
    # Retain reviewed failure markers; frozen service records must match exactly
    # at live preflight. Eligibility here never establishes application health.
    expected = '69' if role == 'migration' else '137' if role in ('web', 'worker', 'scheduler') else None
    return (expected is not None and value.get('Result') == 'exit-code'
            and value.get('ExecMainStatus') == expected and bool(value.get('InvocationID')))


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


def native_status(role, invocation, runner=base.call):
    if not re.fullmatch('[0-9a-f]{32}', invocation):
        raise ValueError('invalid_invocation')
    raw = runner(['/usr/bin/journalctl', 'CONTAINER_NAME=nautobot-'+role, '_UID=999', '-b',
                  '-o', 'json', '--no-pager', '--quiet', '-n', '1000'])
    receipts = []
    phase = None
    for line in raw.splitlines():
        entry = json.loads(line)
        message = entry.get('MESSAGE', '')
        if message.startswith('NAUTOBOT_STARTUP_PHASE='):
            value = json.loads(message.split('=', 1)[1])
            if value.get('role') == role and value.get('invocation') == invocation:
                phase = {k:value.get(k) for k in ('phase','state','elapsed_seconds')}
        if message.startswith('NAUTOBOT_STARTUP_RESULT='):
            value = json.loads(message.split('=', 1)[1])
            if isinstance(value, dict) and value.get('invocation') == invocation:
                receipts.append(value)
    result = {'passed': False, 'terminal': False, 'phase': phase, 'reason': 'waiting_native_receipt'}
    if not receipts:
        return result
    if len(receipts) != 1:
        return {**result, 'terminal': True, 'reason': 'ambiguous_native_receipt'}
    receipt = receipts[0]
    if not isinstance(receipt, dict) or not isinstance(receipt.get('steps'), dict) or not all(isinstance(v, dict) for v in receipt['steps'].values()):
        return {**result, 'terminal': True, 'reason': 'native_failed_or_invalid'}
    expected = {'configuration', 'pending_migrations'}
    if role == 'migration': expected.add('post_upgrade')
    if role == 'web': expected.add('static_collection')
    valid = (receipt.get('role') == role and receipt.get('passed') is True
             and set(receipt.get('steps', {})) == expected
             and all(type(v.get('exit_status')) is int and v['exit_status'] == 0
                     and not v.get('error') and v.get('output_limited') is False
                     for v in receipt['steps'].values()))
    return {**result, 'passed': valid, 'terminal': not valid,
            'reason': 'native_complete' if valid else 'native_failed_or_invalid'}


def http_checks(opener=None):
    opener = opener or urllib.request.build_opener(urllib.request.ProxyHandler({}))
    result = {}; details = {}
    for path, kind in [('/health/', 'health'), ('/static/admin/css/base.css', 'static')]:
        url = 'http://127.0.0.1:8080' + path
        request = urllib.request.Request(url, headers={'Host': 'j2-svpi4mf.local.theama.co'})
        try:
            with opener.open(request, timeout=15) as response:
                payload = response.read(1048577)
                valid = (response.status == 200 and response.geturl() == url
                         and 0 < len(payload) <= 1048576)
                css = response.headers.get_content_type() == 'text/css'
                if kind == 'static': valid = valid and css
                details[kind] = {'status': response.status, 'redirected': response.geturl() != url,
                                 'empty': not payload, 'oversized': len(payload)>1048576,
                                 'css_content_type': css if kind == 'static' else None}
                result[kind] = valid
        except urllib.error.HTTPError as error:
            result[kind] = False; details[kind] = {'status':error.code,'error':'http_status'}
            error.close()
        except (TimeoutError, socket.timeout):
            result[kind] = False; details[kind] = {'error':'timeout'}
        except urllib.error.URLError as error:
            reason = error.reason
            category = ('connection_refused' if isinstance(reason, ConnectionRefusedError)
                        else 'timeout' if isinstance(reason, (TimeoutError, socket.timeout)) else 'transport_error')
            result[kind] = False; details[kind] = {'error':category}
    return {'passed': all(result.values()), 'http': result, 'details': details}


def readiness(role, inspect=service, native=native_status, http=http_checks):
    value = inspect(role)
    result = {'passed':False, 'terminal':terminal(value), 'state':value}
    if role in ('postgresql', 'redis'):
        result['passed'] = healthy(role, value)
        return result
    invocation = value.get('InvocationID', '')
    if not invocation:
        return result
    receipt = native(role, invocation)
    result['native'] = receipt
    result['terminal'] = result['terminal'] or receipt['terminal']
    result['passed'] = healthy(role, value) and receipt['passed']
    if result['passed'] and role == 'web':
        result['http'] = http()
        result['passed'] = result['http']['passed']
    # Never accept evidence spanning a restart or a service-state transition.
    if inspect(role) != value:
        result.update(passed=False, reason='service_changed_during_probe')
    return result


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
            result = readiness(role)
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
