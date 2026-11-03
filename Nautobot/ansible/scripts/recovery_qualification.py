#!/usr/bin/env python3
"""Fault injection and evidence for the existing node-local recovery supervisor."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import time
from datetime import datetime
from zoneinfo import ZoneInfo
import capture_qualification
import recurring_node as node
from recurring_protection import atomic, protected, require, in_window


def operation(root):
    protected(root, True)
    op = node.load(root/'operation.json')
    require(op['operation']['execution_enabled'], 'execution_disabled')
    require(os.getuid() == 999 and node.socket.gethostname() == 'j2-svpi4mf', 'target')
    return op


def journal_cursor(output):
    require(isinstance(output, str) and len(output) <= 4096, 'journal_cursor')
    lines = output.splitlines()
    # A zero-entry read may print this banner before the opaque cursor.
    if lines and lines[0] == '-- No entries --':
        lines = lines[1:]
    require(len(lines) == 1 and re.fullmatch(r'-- cursor: [A-Za-z0-9_=;:-]+', lines[0]), 'journal_cursor')
    return lines[0]


def configure(root, case, cursor):
    cursor = journal_cursor(cursor)
    op = operation(root)
    require(case in ('killed', 'deadline'), 'case')
    require(Path('/proc/sys/kernel/random/boot_id').read_text().strip() == op['boot_id'], 'boot_drift')
    trial = op['trials'][case]
    if case == 'killed':
        c = trial['supervisor']; now = datetime.now(ZoneInfo(c['timezone']))
        end = now.replace(hour=c['end_hour'], minute=c['end_minute'], second=0, microsecond=0)
        require(in_window(c, now) and (end-now).total_seconds() >= op['controller_timeout_seconds'], 'insufficient_trial_window')
    # Capture configuration validates native artifacts, packages, media and token metadata.
    directory = root/case
    directory.mkdir(mode=0o700)
    atomic(directory/'journal-cursor.json', {'cursor': cursor})
    atomic(directory/'operation.json', trial)
    capture_qualification.configure(directory)


def prepare(directory, run):
    trial = node.load(directory/'operation.json')
    cfg = node.load(directory/'binding.json')
    node.prepare(directory/'binding.json', cfg, run)
    inputs = node.load(run/'inputs.json')
    require(inputs['application_upload_enabled'] is False, 'upload_scope')
    # Use real preparation, credentials, pause/drain and Ansible async execution.
    # Substitute only capture with the explicitly approved blocking fault.
    inputs['application_producer_argv'] = ['/usr/bin/python3', '-B', str(Path(__file__).resolve()),
                                         'block', str(directory)]
    atomic(run/'inputs.json', inputs)
    require(not trial['supervisor']['dispose_successful_payload'], 'disposal_scope')


def blocked(directory, run):
    protected(run, True)
    trial = node.load(directory/'operation.json')
    from recurring_protection import Supervisor
    supervisor = Supervisor(directory/'supervisor.json')
    supervisor.check()
    node.stopped()
    require(Path(supervisor.state()['root']) == run, 'run_identity')
    atomic(run/'fault-paused.json', {'case': directory.name, 'paused_at': time.time(),
                                  'pid': os.getpid(), 'boot_id': Path('/proc/sys/kernel/random/boot_id').read_text().strip()})
    # The primary cgroup must be terminated by OnFailure injection or the guard.
    time.sleep(trial['supervisor']['run_seconds'])
    raise RuntimeError('fault_survived_deadline')


def state(directory):
    path = directory/'state/state.json'
    return node.load(path) if path.exists() else {'phase': 'idle'}


def wait_paused(directory):
    trial = node.load(directory/'operation.json')
    end = time.monotonic()+trial['supervisor']['capture_seconds']+120
    while time.monotonic() < end:
        current = state(directory)
        require(current['phase'] in ('idle', 'preflight', 'armed'), 'trial_terminated_before_fault')
        if current['phase'] == 'armed' and (Path(current['root'])/'fault-paused.json').is_file():
            node.stopped()
            require(time.monotonic() < current['deadline'], 'deadline_already_due')
            print(json.dumps({'writers_paused': True, 'case': directory.name}))
            return
        time.sleep(1)
    raise RuntimeError('pause_wait_expired')


def inspect(directory):
    trial = node.load(directory/'operation.json')
    end = time.monotonic()+trial['supervisor']['capture_seconds']+trial['supervisor']['recovery_seconds']+60
    while time.monotonic() < end:
        current = state(directory)
        if current['phase'] in ('recovered_failure', 'manual_intervention', 'failed', 'complete'):
            break
        time.sleep(1)
    require(current['phase'] == 'recovered_failure', 'recovery_failed')
    require(current['recovery_trigger'] == ('failure' if directory.name == 'killed' else 'deadline'), 'recovery_trigger')
    require(current['recovery_elapsed_seconds'] <= trial['supervisor']['recovery_seconds'], 'recovery_deadline')
    require(current['resume_statuses'] == [0, 0, 0] and current['health_status'] == 0 and current['credential_cleanup'], 'recovery_outcomes')
    run = Path(current['root']); protected(run, True)
    paused = node.load(run/'fault-paused.json')
    require(paused['case'] == directory.name, 'fault_identity')
    before = node.load(run/'recurring-before.json')
    services = node.health()
    require(before['boot_id'] == Path('/proc/sys/kernel/random/boot_id').read_text().strip(), 'boot_changed')
    require(all(before['services']['nautobot-'+role+'.service']['InvocationID'] == services['nautobot-'+role+'.service']['InvocationID']
                for role in ('postgresql', 'redis')), 'data_service_restart')
    require(not any((run/n).exists() for n in ('password', 'credentials.json', 'source-password', 'source-credentials.json')), 'credential_residue')
    require(not (run/'payload').exists() and not (run/'application-backup-result.json').exists(), 'unexpected_capture_or_upload')
    prefix = trial['supervisor']['unit_prefix']
    require(node.system(['show', prefix+'-guard.timer', '--property=ActiveState', '--value']).strip() == b'inactive', 'guard_active')
    for name in trial['unit_names']:
        end = time.monotonic()+30
        while True:
            row = dict(line.split('=', 1) for line in node.system(['show', name,
                       '--property=ActiveState,MainPID,ControlPID,ControlGroup']).decode().splitlines())
            if row['ActiveState'] in ('inactive', 'failed') and all(row.get(k, '0') == '0' for k in ('MainPID', 'ControlPID')) and not row.get('ControlGroup'):
                break
            require(time.monotonic() < end, 'qualification_process_residue')
            time.sleep(.2)
    atomic(directory/'result.json', {'accepted': False, 'checks_passed': True, 'state': current,
           'paused_seconds_upper_bound': current['finished_at']-paused['paused_at'], 'services': services,
           'credentials_removed': True, 'payload_created': False, 'controller_recovery_used': False})


def timer(root):
    op = operation(root)
    require(in_window(op['trials']['killed']['supervisor'], datetime.now().astimezone()), 'outside_window')
    prefix = 'nautobot-protection-timerqual'
    names = [prefix+'.service', prefix+'.timer']
    for name in names:
        require(node.system(['show', name, '--property=LoadState', '--value']).strip() == b'not-found', 'existing_probe_unit')
    calendar = {}
    for expression in ('*-*-* 03:20:00 America/Chicago', '*-*-* 04:05:00 America/Chicago'):
        for base in ('2026-03-07 12:00:00 UTC', '2026-10-31 12:00:00 UTC'):
            raw = node.bounded(['/usr/bin/systemd-analyze', 'calendar', '--iterations=3', '--base-time='+base, expression])
            calendar[expression+' '+base] = raw.decode()
    directory = root/'timer'; directory.mkdir(mode=0o700)
    service = '[Unit]\nDescription=Nautobot qualification marker only\n[Service]\nType=oneshot\nUMask=0077\nTimeoutStartSec=10\nExecStart=/usr/bin/touch '+str(directory/'fired')+'\n'
    definition = '[Unit]\nDescription=Nautobot bounded timer dispatch qualification\n[Timer]\nOnActiveSec=2s\nAccuracySec=1s\nPersistent=false\nUnit='+prefix+'.service\n'
    for name, text in zip(names, (service, definition)):
        path = directory/name; path.write_text(text); path.chmod(0o600)
    paths = [str(directory/name) for name in names]
    node.bounded(['/usr/bin/systemd-analyze', '--user', 'verify', *paths])
    try:
        node.system(['link', '--runtime', *paths]); node.system(['daemon-reload'])
        node.system(['start', prefix+'.timer'])
        end = time.monotonic()+20
        while time.monotonic() < end and not (directory/'fired').exists(): time.sleep(.2)
        require((directory/'fired').is_file(), 'timer_did_not_fire')
        atomic(directory/'result.json', {'accepted': False, 'dispatched': True, 'calendar': calendar,
                                        'production_timer_enabled': False})
    finally:
        node.system(['stop', *names]); node.system(['disable', '--runtime', *names]); node.system(['daemon-reload'])


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['configure', 'prepare', 'block', 'wait-paused', 'inspect', 'timer'])
    parser.add_argument('root', type=Path); parser.add_argument('argument', nargs='?')
    parser.add_argument('--root', dest='run', type=Path); parser.add_argument('--phase', choices=['capture'])
    parser.add_argument('--journal-cursor')
    a = parser.parse_args()
    if a.action == 'configure': configure(a.root, a.argument, a.journal_cursor)
    elif a.action == 'prepare': prepare(a.root, Path(a.argument))
    elif a.action == 'block': blocked(a.root, a.run)
    elif a.action == 'wait-paused': wait_paused(a.root)
    elif a.action == 'inspect': inspect(a.root)
    else: timer(a.root)
