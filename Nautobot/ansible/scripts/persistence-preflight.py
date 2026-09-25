#!/usr/bin/env python3
"""Read-only logout-persistence preparation; never close sessions or restart units."""
import importlib.util
import json
from pathlib import Path

source = Path(__file__).with_name('startup-preflight.py')
spec = importlib.util.spec_from_file_location('startup_baseline', source)
baseline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(baseline)
ROLES = ('postgresql', 'redis', 'web', 'worker', 'scheduler')


def pairs(raw):
    return dict(line.split('=', 1) for line in raw.splitlines() if '=' in line)


def assess(data):
    """Readiness only. Sessions require ownership review, not automatic selection."""
    gaps = []
    user = data['persistence_user']
    if user.get('UID') != '999' or user.get('Linger') != 'yes':
        gaps.append('service_user_or_linger')
    for role in ROLES:
        row = data['persistence_services'][role]
        if (row.get('ActiveState') != 'active' or row.get('SubState') != 'running'
                or row.get('Result') != 'success' or not row.get('InvocationID')
                or not row.get('NRestarts', '').isdigit()):
            gaps.append('service_identity_' + role)
    if data['guard'] != {'verified': True}:
        gaps.append('backend_guard')
    return {'preconditions_observed': not gaps, 'gaps': gaps,
            'accepted': False, 'session_ownership_review_required': True,
            'recovery_review_required': True}


def collect():
    data = baseline.collect()
    data['persistence_user'] = pairs(baseline.command([
        '/usr/bin/loginctl', 'show-user', 'nautobot', '--property=UID,Linger,State,Sessions']))
    data['login_sessions'] = baseline.command(['/usr/bin/loginctl', 'list-sessions', '--no-legend', '--no-pager'])
    data['persistence_services'] = {
        role: pairs(baseline.command(baseline.USER + ['/usr/bin/systemctl', '--user', 'show',
            'nautobot-' + role + '.service',
            '--property=ActiveState,SubState,Result,NRestarts,InvocationID,MainPID']))
        for role in ROLES}
    if Path('/proc/sys/kernel/random/boot_id').read_text().strip() != data['boot_id']:
        raise ValueError('boot_changed')
    data['persistence_review'] = assess(data)
    return data


if __name__ == '__main__':
    try:
        print(json.dumps(collect()))
    except Exception:
        print(json.dumps({'accepted': False, 'error': 'persistence_preflight_incomplete'}))
        raise SystemExit(69)
