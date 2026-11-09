#!/usr/bin/env python3
"""Read bounded, nonsecret cycle evidence; never repair, send, or accept a run."""
import argparse
from datetime import datetime, time, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import stat
import subprocess
import sys
from zoneinfo import ZoneInfo

BASE = Path('/var/lib/nautobot/protection')
SECTIONS = {'postgresql_custom_dump', 'media', 'configuration',
            'image_dependency_manifest', 'quadlet_config_hashes', 'versions_migrations'}
CENTRAL = ZoneInfo('America/Chicago')


class Refused(ValueError):
    """Fixed diagnostic codes only; never include receipt or command contents."""


def require(value, code):
    if not value:
        raise Refused(code)


def read(path):
    require(not any(p.is_symlink() for p in (path, *path.parents)), 'symlink')
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, 'rb') as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid()
                and stat.S_IMODE(info.st_mode) == 0o600 and info.st_nlink == 1, 'unsafe_file')
        raw = stream.read(1048577)
    require(len(raw) <= 1048576, 'oversized_file')
    return raw


def inspect_receipts(root, state, day, require_logical=False):
    """Compare actual producer/task receipts, including after successful disposal."""
    hashes = {}
    def receipt(name):
        raw = read(root/name); hashes[name] = hashlib.sha256(raw).hexdigest()
        return json.loads(raw)
    spec = receipt('application-backup.json')
    capture = receipt('application-capture-result.json')
    upload = receipt('application-backup-result.json')
    task = receipt('capture-task-results.json')
    resume = receipt('capture-resume-verification.json')
    disposal = receipt('payload-disposal.json')
    before = receipt('application-snapshots-before.json')
    after = receipt('application-snapshots-after.json')
    identity = hashlib.sha256(json.dumps(spec, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    started = datetime.fromtimestamp(state['started_at'], CENTRAL)
    finished = datetime.fromtimestamp(state['finished_at'], CENTRAL)
    require(state['phase'] == 'complete' and state['exit_status'] == 0, 'incomplete_cycle')
    require(started.date().isoformat() == day and time(3, 20) <= started.time() <= time(3, 22)
            and finished.date() == started.date() and finished.time() < time(4), 'cycle_window')
    require(spec['operation_id'] == 'nautobot-recurring' and set(spec['captures']) == SECTIONS, 'capture_scope')
    for item in (capture, upload):
        require(item['specification_sha256'] == identity and item['capture_passed'] is True
                and set(item['content_sha256']) == SECTIONS
                and all(re.fullmatch('[0-9a-f]{64}', h) for h in item['content_sha256'].values())
                and all(item['credential_cleanup'].get(n) is True for n in ('password', 'credentials.json')), 'capture_receipt')
    require(capture['content_sha256'] == upload['content_sha256'], 'capture_hash_difference')
    require(task['pause_rc'] == [0]*4 and task['resume_rc'] == [0]*3
            and task['capture_rc'] == task['health_rc'] == resume['verification_rc'] == 0
            and task['credential_cleanup_failed'] is False, 'task_failure')
    require(capture['started'] <= capture['finished'] <= state['resumed_at']
            <= upload['requested_at'] <= upload['finished'] <= state['finished_at']
            <= state['last_success'], 'capture_resume_upload_order')
    sid = upload['snapshot_id']
    require(isinstance(sid, str) and re.fullmatch('[0-9a-f]{64}', sid), 'snapshot_id')
    require(upload['upload_passed'] is True and upload['integrity_passed'] is True
            and upload['backup_exit_status'] == upload['integrity_exit_status'] == 0
            and upload['new_snapshot_ids'] == [sid], 'upload_integrity')
    require(isinstance(before, list) and isinstance(after, list)
            and len(set(before)) == len(before) and len(set(after)) == len(after)
            and set(before) <= set(after) and set(after)-set(before) == {sid}, 'snapshot_delta')
    require(disposal == {'phase':'complete', 'snapshot_id':sid, 'files':sorted(SECTIONS)}, 'disposal_receipt')
    payload = root/'payload'
    require(not payload.is_symlink() and payload.is_dir() and not any(payload.iterdir()), 'payload_residue')
    require(not any(os.path.lexists(root/n) for n in ('password', 'credentials.json',
                'source-password', 'source-credentials.json')), 'credential_residue')
    flags = ['--logical-reference' in item.get('argv', []) for item in spec['captures'].values()]
    logical_verified = False
    if require_logical or any(flags):
        require(all(flags), 'logical_capture_not_enabled')
        reference = receipt('logical-reference.json')
        logical = receipt('logical-capture.json')
        logical_before = receipt('logical-before.json')
        require(reference.get('format') == 'postgresql17-logical-v1' and reference.get('tables')
                and logical_before['identity'] == reference, 'independent_logical_reference')
        require(logical['format'] == 'recurring-logical-v1'
                and logical['specification_sha256'] == identity
                and logical['dump_sha256'] == capture['content_sha256']['postgresql_custom_dump']
                and logical['reference_sha256'] == hashes['logical-reference.json']
                and logical['comparison'] == {'equal':True,'changed_sections':[],'writer_control_required':True},
                'logical_capture_binding')
        require(0 <= logical['before_seconds'] <= 35 and 0 <= logical['after_seconds'] <= 35
                and state['resumed_at']-state['started_at'] <= 450, 'logical_capture_deadline')
        logical_verified = True
    return {'snapshot_id':sid, 'content_sha256':capture['content_sha256'],
            'receipt_sha256':hashes, 'started_at':started.isoformat(), 'finished_at':finished.isoformat(),
            'capture_resume_upload_order_verified':True, 'payload_disposal_verified':True,
            'logical_reference_verified':logical_verified}


def command(argv):
    result = subprocess.run(argv, stdin=subprocess.DEVNULL, capture_output=True, timeout=30, check=True)
    require(len(result.stdout) < 65536 and len(result.stderr) < 65536, 'command_output_bound')
    return result.stdout.decode().strip()


def runtime_hashes(runtime, expected):
    paths = list(runtime.rglob('*')); require(len(paths) <= 128, 'runtime_members')
    require(not any(p.is_symlink() for p in [runtime, *paths]), 'runtime_symlink')
    actual, caches = {}, {}
    for path in paths:
        if path.is_dir():
            continue
        name = str(path.relative_to(runtime))
        raw = read(path)  # Cache files retain the same owner, mode, size and link checks.
        if name not in expected:
            match = re.fullmatch(r'scripts/__pycache__/([a-z_]+)\.'
                                + re.escape(sys.implementation.cache_tag) + r'\.pyc', name)
            require(match is not None and 'scripts/'+match[1]+'.py' in expected, 'runtime_extra')
            caches[name] = hashlib.sha256(raw).hexdigest()
        else:
            actual[name] = hashlib.sha256(raw).hexdigest()
    require(actual == expected, 'runtime_drift')
    return actual, caches


def collect(expected, day):
    require(os.getuid() == 999 and socket.gethostname() == 'j2-svpi4mf', 'target_identity')
    require(datetime.now(CENTRAL) >= datetime.combine(datetime.fromisoformat(day).date(), time(4, 5), CENTRAL), 'not_due')
    runtime = BASE/'runtime'; state_path = BASE/'state/state.json'
    if not state_path.exists():
        return {'accepted':False, 'local_checks_passed':False, 'reason':'no_scheduled_cycle'}
    raw = read(state_path); state = json.loads(raw)
    if state.get('phase') != 'complete':
        return {'accepted':False, 'local_checks_passed':False, 'reason':'cycle_not_complete',
                'phase':state.get('phase')}
    actual, caches = runtime_hashes(runtime, expected['runtime_sha256'])
    require(state['configuration_sha256'] == actual['supervisor.json'], 'configuration_drift')
    require(Path('/proc/sys/kernel/random/boot_id').read_text().strip() == expected['boot_id'], 'boot_changed')
    run = Path(state['root'])
    require(run.parent == BASE/'staging' and re.fullmatch(r'nautobot-recurring\.[a-z0-9_]+', run.name)
            and run.is_dir() and not run.is_symlink(), 'run_path')
    binding = json.loads(read(runtime/'binding.json'))
    result = inspect_receipts(run, state, day, require_logical=binding.get('logical_reference', False))
    units = {}
    names = ['nautobot-'+r+'.service' for r in ('postgresql','redis','web','worker','scheduler')]
    names += ['nautobot-protection'+suffix for suffix in ('.service','.timer','-guard.timer',
              '-guard.service','-recovery.service','-freshness.service','-freshness.timer',
              '-notification.service','-notification.timer')]
    for name in names:
        units[name] = dict(line.split('=',1) for line in command(['/usr/bin/systemctl','--user','show',name,
            '--property=ActiveState,SubState,Result,InvocationID,LastTriggerUSec,LastTriggerUSecMonotonic,ExecMainStartTimestamp,ExecMainStartTimestampMonotonic,UnitFileState']).splitlines())
    for name in names[:5]:
        require(units[name]['ActiveState'] == 'active' and units[name]['SubState'] == 'running', 'application_health')
    for name, identity in expected['data_service_invocations'].items():
        require(units[name]['InvocationID'] == identity, 'data_service_restarted')
    for suffix in ('.service','-guard.timer','-guard.service','-recovery.service'):
        require(units['nautobot-protection'+suffix]['ActiveState'] == 'inactive', 'active_recovery')
    for suffix in ('.timer','-freshness.timer','-notification.timer'):
        require(units['nautobot-protection'+suffix]['ActiveState'] == 'active'
                and units['nautobot-protection'+suffix]['UnitFileState'] == 'enabled', 'timer_state')
    health = "import http.client;c=http.client.HTTPConnection('127.0.0.1',8080,timeout=3);c.request('GET','/health/',headers={'Host':'j2-svpi4mf.local.theama.co'});print(c.getresponse().status);c.close()"
    require(command(['/usr/bin/podman','exec','nautobot-web','python3','-c',health]) == '200', 'http_health')
    freshness = json.loads(read(BASE/'state/freshness.json'))
    checked = datetime.fromtimestamp(freshness['checked_at'], CENTRAL)
    require(freshness['fresh'] is True and checked.date().isoformat() == day
            and checked.time() >= time(4,5), 'freshness_not_observed')
    notification = json.loads(read(BASE/'state/notification.json'))
    require(notification.get('acknowledged') == 'recovery' and notification.get('pending') is None, 'notification_pending')
    require(read(state_path) == raw, 'state_changed_during_readback')
    result.update(accepted=False, local_checks_passed=True, run_root=str(run), units=units,
                  derived_python_cache_sha256=caches,
                  notification=notification, collected_at=datetime.now(timezone.utc).isoformat(),
                  remaining_checks=['Correlate timer trigger, primary invocation and bounded journal; no manual-start substitution.',
                    'Compare older retained trees with the approved baseline.',
                    'Independently confirm exact repository/snapshot identity under the approved credential boundary.',
                    'Reconcile actual state-change alerts with delivery evidence; healthy-to-healthy cycles need not send.'])
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--day', required=True)
    parser.add_argument('--expected-json', required=True)
    args = parser.parse_args()
    try:
        result = collect(json.loads(args.expected_json), args.day)
        print(json.dumps(result, sort_keys=True))
        raise SystemExit(0 if result['local_checks_passed'] else 2)
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as error:
        print(json.dumps({'accepted':False,'local_checks_passed':False,
                          'reason':str(error) if isinstance(error, Refused) else type(error).__name__}))
        raise SystemExit(2)
