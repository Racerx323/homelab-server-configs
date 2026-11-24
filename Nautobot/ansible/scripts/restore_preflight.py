#!/usr/bin/env python3
"""Execution-time read-only host comparison before credentials or restore load."""
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
import importlib.util
import json
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('restore_baseline', Path(__file__).with_name('persistence-preflight.py'))
baseline = importlib.util.module_from_spec(spec); spec.loader.exec_module(baseline)


def assess(current, expected, continuity=False):
    if current['host'] != 'j2-svpi4mf':
        raise ValueError('baseline_identity')
    if continuity and current['boot_id'] != expected['boot_id']:
        raise ValueError('boot_changed')
    if not baseline.assess(current)['preconditions_observed']:
        raise ValueError('runtime_preconditions')
    for role, row in expected['services'].items():
        fields = set(row) if continuity else set(row)-{'InvocationID', 'MainPID', 'NRestarts'}
        if any(current['persistence_services'][role].get(k) != row[k] for k in fields):
            raise ValueError('service_drift')
    observed = {}
    for key, prefix in (('runtime_files','/var/lib/nautobot/runtime/'),
                        ('quadlets','/var/lib/nautobot/.config/containers/systemd/')):
        for name, row in current[key].items():
            if 'sha256' in row:
                if not row['regular'] or row['uid'] != 999 or row['mode'] != ('0o644' if key == 'runtime_files' else '0o600'):
                    raise ValueError('artifact_metadata')
                observed[prefix+name] = row['sha256']
    if observed != expected['artifact_sha256']: raise ValueError('artifact_drift')


def admit_window(window, units, next_trigger, now=None):
    now = now or datetime.now(timezone.utc)
    start, end = (datetime.fromisoformat(window[k]) for k in ('start', 'end'))
    if not start <= now or (end-now).total_seconds() < 4500:
        raise ValueError('attended_window')
    if not 5 <= now.astimezone(ZoneInfo('America/Chicago')).hour < 23:
        raise ValueError('backup_window')
    for name in ('nautobot-protection.service', 'nautobot-protection-recovery.service'):
        if units[name]['ActiveState'] != 'inactive' or units[name]['Result'] != 'success':
            raise ValueError('protection_not_idle')
    timer = units['nautobot-protection.timer']
    if timer['ActiveState'] != 'active' or timer['UnitFileState'] != 'enabled':
        raise ValueError('protection_timer')
    if next_trigger-now.timestamp() <= 4500:
        raise ValueError('protection_overlap')


def main():
    op = json.loads(Path(sys.argv[1]).read_text())
    current = baseline.collect()
    print(json.dumps({'phase':'baseline','observed':{'host':current['host'], 'boot_id':current['boot_id'], 'services':current['persistence_services']}}), flush=True)
    assess(current, op['baseline'])
    command = baseline.baseline.command
    if command(['/usr/bin/uname','-m']).strip() != 'aarch64': raise ValueError('architecture')
    if command(['/usr/bin/restic','version']).strip() != op['restic_version']: raise ValueError('restic_version')
    if command(baseline.baseline.USER+['/usr/bin/podman','--version']).strip() != 'podman version 5.4.2':
        raise ValueError('podman_version')
    units = {}
    for name in ('nautobot-protection.service', 'nautobot-protection-recovery.service', 'nautobot-protection.timer'):
        units[name] = baseline.pairs(command(baseline.baseline.USER+[
            '/usr/bin/systemctl', '--user', 'show', name,
            '--property=ActiveState,Result,UnitFileState,NextElapseUSecRealtime']))
    next_trigger = float(command(['/usr/bin/date', '--date', units['nautobot-protection.timer']['NextElapseUSecRealtime'], '+%s']).strip())
    # Retain bounded observations before evaluating admission, including on refusal.
    observation = {'host': current['host'], 'boot_id': current['boot_id'],
                   'services': current['persistence_services'], 'units': units,
                   'collected_at': current['collected_at'], 'next_trigger': next_trigger}
    print(json.dumps({'phase':'admission','observed':observation}), flush=True)
    admit_window(op['attended_window'], units, next_trigger)
    admission = Path(sys.argv[1]).with_name('admission.json')
    with admission.open('x') as stream: json.dump(observation, stream)
    admission.chmod(0o600)
    print(json.dumps({'preflight_passed':True,'accepted':False,'boot_id':current['boot_id']}))


if __name__ == '__main__':
    try: main()
    except Exception as error:
        print(json.dumps({'preflight_passed':False,'failure_class':type(error).__name__, 'reason':str(error) if isinstance(error, ValueError) else 'measurement_failed'}))
        raise SystemExit(1)
