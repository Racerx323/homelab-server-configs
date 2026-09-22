#!/usr/bin/env python3
"""Repeatable native runtime entrypoint; no bootstrap or continuation state."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import time

spec = importlib.util.spec_from_file_location('native', Path(__file__).with_name('startup-command.py'))
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
LIMITS = {'migration': 1536, 'web': 1536, 'worker': 1536, 'scheduler': 384}
COMMANDS = {
    'web': ['nautobot-server', 'start', '--http', '0.0.0.0:8080'],
    'worker': ['nautobot-server', 'celery', 'worker', '--loglevel', 'INFO', '--concurrency', '2'],
    'scheduler': ['nautobot-server', 'celery', 'beat', '--loglevel', 'INFO', '--pidfile', '/tmp/nautobot-beat.pid'],
}


def prepare(role, runner=native.command, inspect=True, report=None):
    if role not in LIMITS:
        raise ValueError('unknown_role')
    if inspect:
        if os.getuid() != 999 or Path('/sys/fs/cgroup/memory.max').read_text().strip() != str(LIMITS[role] * 1024**2):
            raise ValueError('resource_boundary')
        if Path('/sys/fs/cgroup/memory.swap.max').read_text().strip() != '0':
            raise ValueError('swap_boundary')
        if any(key.startswith('DJANGO_SUPERUSER_') for key in os.environ):
            raise ValueError('bootstrap_environment')
        for directory in ('git', 'jobs', 'media', 'static'):
            with tempfile.TemporaryFile(dir='/opt/nautobot/' + directory):
                pass
    steps = [('configuration', ['check'], 120)]
    if role == 'migration':
        steps.append(('post_upgrade', ['post_upgrade'], 1800))
    steps.append(('pending_migrations', ['migrate', '--check'], 120))
    if role == 'web':
        steps.append(('static_collection', ['collectstatic', '--noinput'], 120))
    receipt = {'role': role, 'passed': False, 'steps': {}}
    for name, args, timeout in steps:
        started = time.monotonic()
        if report: report({'role':role,'phase':name,'state':'started','elapsed_seconds':0})
        result = runner(['nautobot-server'] + args, timeout)
        if report: report({'role':role,'phase':name,'state':'completed','elapsed_seconds':round(time.monotonic()-started,3)})
        receipt['steps'][name] = result
        if result.get('exit_status') != 0 or result.get('error') or result.get('output_limited'):
            receipt['failed_phase'] = name
            return receipt
    receipt['passed'] = True
    return receipt


def main():
    role = sys.argv[1] if len(sys.argv) == 2 else ''
    try:
        receipt = prepare(role, report=lambda phase: print('NAUTOBOT_STARTUP_PHASE='+json.dumps(phase), flush=True))
    except Exception:
        print(json.dumps({'passed': False, 'error': 'startup_boundary'}), flush=True)
        return 69
    print('NAUTOBOT_STARTUP_RESULT=' + json.dumps(receipt, sort_keys=True), flush=True)
    if not receipt['passed']:
        return 69
    if role != 'migration':
        os.execvp(COMMANDS[role][0], COMMANDS[role])
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
