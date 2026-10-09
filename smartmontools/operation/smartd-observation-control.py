#!/usr/bin/env python3
"""Host-local launch, status and identity-bound cancellation for a frozen trial."""
import importlib.util
import json
import os
from pathlib import Path
import hashlib
import re
import signal
import stat
import time


class Cancelled(Exception):
    pass


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def identity(pid):
    fields = (Path('/proc')/str(pid)/'stat').read_text().rsplit(') ', 1)[1].split()
    if fields[0] == 'Z':
        raise ProcessLookupError('zombie_supervisor')
    return {'pid': pid, 'start_ticks': fields[19],
            'boot_id': Path('/proc/sys/kernel/random/boot_id').read_text().strip()}


def private_root(root):
    root = Path(root)
    s = root.lstat()
    if not stat.S_ISDIR(s.st_mode) or s.st_uid != os.geteuid() or stat.S_IMODE(s.st_mode) != 0o700:
        raise ValueError('unsafe_trial_root')
    return root


def atomic(root, value):
    temp = root/'status.json.tmp'
    with temp.open('w') as stream:
        json.dump(value, stream)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    temp.replace(root/'status.json')


def status(root):
    root = private_root(root)
    result = json.loads((root/'status.json').read_text())
    if result['state'] in ('running', 'stopping'):
        try:
            live = identity(result['supervisor']['pid']) == result['supervisor']
        except (FileNotFoundError, ProcessLookupError):
            live = False
        result['supervisor_alive'] = live
        if not live:
            result['state'] = 'lost_supervisor'
        progress = root/'evidence/progress.json'
        if progress.exists():
            result['progress'] = json.loads(progress.read_text())
    return result


def cancel(root):
    root = private_root(root)
    record = status(root)
    if record['state'] not in ('running', 'stopping'):
        raise ValueError('no_owned_running_supervisor')
    if not hasattr(os, 'pidfd_open') or not hasattr(signal, 'pidfd_send_signal'):
        raise ValueError('pidfd_required')
    fd = os.pidfd_open(record['supervisor']['pid'])
    try:
        if identity(record['supervisor']['pid']) != record['supervisor']:
            raise ValueError('supervisor_identity_changed')
        signal.pidfd_send_signal(fd, signal.SIGTERM)
    finally:
        os.close(fd)
    return {'cancellation_requested': True, 'terminal': False}


def detach(root, worker):
    """The worker owns only this trial; no service or login-session dependency."""
    root = private_root(root)
    os.umask(0o077)
    with (root/'launch.claim').open('x') as claim:
        claim.write('single launch\n')
    atomic(root, {'state': 'submitted'})
    pid = os.fork()
    if pid:
        until = time.monotonic() + 5
        while time.monotonic() < until:
            record = status(root)
            if record['state'] != 'submitted':
                return record
            time.sleep(.02)
        return {'state': 'submitted', 'pid': pid, 'review_required': True}
    os.setsid()
    os.chdir(root)
    null = os.open('/dev/null', os.O_RDONLY)
    log = os.open(root/'supervisor.log', os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.dup2(null, 0)
    os.dup2(log, 1)
    os.dup2(log, 2)
    if null > 2:
        os.close(null)
    if log > 2:
        os.close(log)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    signal.signal(signal.SIGALRM, signal.SIG_DFL)
    signal.alarm(0)
    record = {'state': 'running', 'supervisor': identity(os.getpid()),
              'started_epoch': time.time()}
    def stop(*_):
        record['state'] = 'stopping'
        atomic(root, record)
        # A second cancel must not interrupt the candidate's shutdown/settling.
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        raise Cancelled('operator_cancel_requested')
    signal.signal(signal.SIGTERM, stop)
    atomic(root, record)
    try:
        result = worker()
        record['result'] = result
        record['state'] = ('complete' if result.get('completed') else
                           'cancelled' if 'cancel' in str(result.get('failure', '')).lower() else 'failed')
    except BaseException as exc:
        record['state'] = 'cancelled' if isinstance(exc, Cancelled) else 'failed'
        record['failure'] = type(exc).__name__ + ':' + str(exc)
    record['finished_epoch'] = time.time()
    atomic(root, record)
    os._exit(0 if record['state'] == 'complete' else 2)


def make_audit(root, baseline, helpers, candidate, inputs=()):
    token = helpers.cursor()
    def fingerprint(path):
        s = path.lstat()
        return (s.st_dev, s.st_ino, s.st_mode, s.st_uid, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
    frozen = {name:fingerprint(root/name) for name in inputs}
    wall, mono = time.time(), time.monotonic()
    expected_counts = {k: baseline[k] for k in ('ioerr_cnt', 'ext4_errors')}
    def inspect():
        nonlocal token
        if any(fingerprint(root/name) != value for name,value in frozen.items()):
            raise ValueError('private_input_changed')
        space = os.statvfs(root)
        if space.f_bavail * space.f_frsize < 64*1024*1024:
            raise ValueError('trial_space_low')
        if abs((time.time()-wall)-(time.monotonic()-mono)) > 5:
            raise ValueError('clock_discontinuity')
        if Path('/proc/sys/kernel/random/boot_id').read_text().strip() != baseline['boot_id']:
            raise ValueError('boot_changed')
        if helpers.config_identity() != baseline['hashes']:
            raise ValueError('production_files_changed')
        services = helpers.checked(['systemctl', 'show', 'smartmontools.service', 'webmin.service',
                                    '--property=Id,ActiveState,InvocationID,NRestarts,MainPID'])
        if services != baseline['services']['stdout']:
            raise ValueError('production_services_changed')
        helpers.observer_inactive()
        token, fault = capture_journal(root/'evidence', token, helpers)
        if candidate.counters() != expected_counts:
            raise ValueError('storage_counters_changed')
        if fault:
            raise ValueError('kernel_storage_fault')
        states = list((root/'state').glob('*.nvme.state'))
        if len(states) > 1:
            raise ValueError('unexpected_state_membership')
        if states:
            value = states[0].read_text()
            if not value.startswith('# smartd state file\n'):
                raise ValueError('invalid_private_state')
            for line in value.splitlines():
                if line.startswith('self-test-errors') and line.split('=', 1)[1].strip() != '0':
                    raise ValueError('candidate_selftest_errors')
    def audit():
        def deadline(*_):
            raise TimeoutError('audit_deadline')
        previous = signal.signal(signal.SIGALRM, deadline)
        signal.setitimer(signal.ITIMER_REAL, 5)
        try:
            inspect()
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0)
            signal.signal(signal.SIGALRM, previous)
    return audit


def append_bounded(path, data, limit):
    size = path.stat().st_size if path.exists() else 0
    if size + len(data) > limit:
        raise ValueError('journal_evidence_limit')
    with path.open('ab') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())


def capture_journal(directory, token, helpers):
    """Advance only to a cursor in the captured batch, after durable evidence."""
    args = ['journalctl', '--no-pager', '--quiet', '-o', 'json']
    first = [json.loads(x) for x in helpers.checked(args+['--cursor', token, '-n', '+1']).splitlines()]
    if len(first) != 1 or first[0].get('__CURSOR') != token:
        raise ValueError('journal_cursor_gap')
    raw = helpers.checked(args+['--after-cursor', token])
    rows = [json.loads(x) for x in raw.splitlines()]
    kernel = [x for x in rows if x.get('_TRANSPORT') == 'kernel']
    daemon = [x for x in rows if x.get('_SYSTEMD_UNIT') == 'smartmontools.service'
              or x.get('SYSLOG_IDENTIFIER') == 'smartd']
    next_token = rows[-1]['__CURSOR'] if rows else token
    encoded = {}
    for name, selected in [('kernel.jsonl', kernel), ('production-smartd.jsonl', daemon)]:
        data = ''.join(json.dumps(x)+'\n' for x in selected).encode()
        append_bounded(directory/name, data, 32*1024*1024)
        encoded[name] = hashlib.sha256(data).hexdigest()
    receipt = {'from': token, 'to': next_token, 'rows_seen': len(rows),
               'kernel_rows': len(kernel), 'production_rows': len(daemon),
               'batch_hashes': encoded, 'epoch': time.time()}
    append_bounded(directory/'journal-checkpoints.jsonl',
                   (json.dumps(receipt)+'\n').encode(), 16*1024*1024)
    fault = any(re.search(helpers.PATTERN, x.get('MESSAGE', ''), re.I) for x in kernel)
    return next_token, fault


def start(root):
    root = private_root(root)
    if os.geteuid() != 0:
        raise ValueError('root_required')
    if not hasattr(os, 'pidfd_open') or not hasattr(signal, 'pidfd_send_signal'):
        raise ValueError('pidfd_required')
    fd = os.pidfd_open(os.getpid())
    os.close(fd)
    spec = json.loads((root/'specification.json').read_text())
    expected = {'execution_ready': True, 'scope': 'candidate_smartd_repeated_checks',
                'duration_seconds': 172800, 'interval_seconds': 1800,
                'minimum_completed_checks': 96, 'command_deadline_seconds': 60,
                'maximum_check_gap_seconds': 1920, 'audit_interval_seconds': 15,
                'post_exit_observation_seconds': 75, 'stream_limit_bytes': 16777216,
                'self_test_start': False, 'production_changes': False,
                'notification_delivery': False, 'persistent_service_registration': False}
    if spec.get('observation') != expected:
        raise ValueError('unreviewed_observation_scope')
    h = load('comparison', root/'compare-ci-smartctl.py')
    for name, digest in spec['inputs'].items():
        path = root/name
        if '/' in name or path.is_symlink() or not path.is_file() or h.digest(path) != digest:
            raise ValueError('input_identity')
    admission = load('admission', root/'qualify-smartd.py')
    observation = load('observation', root/'observe-smartd.py')
    admission.validate_config(root/'smartd.conf')
    baseline = json.loads((root/'baseline.json').read_text())
    admission.preflight(h, baseline)
    space = os.statvfs(root)
    if space.f_bavail * space.f_frsize < 256*1024*1024:
        raise ValueError('insufficient_trial_space')
    if time.time()-baseline['epoch'] > 3300:
        raise ValueError('insufficient_baseline_window')
    for name in ('evidence', 'state', 'attributes', 'json'):
        (root/name).mkdir(mode=0o700)
    code, out, err = h.run([str(root/'smartd'), '--version'])
    (root/'evidence/version').write_bytes(out + err)
    if code or err or b'06489e03695e' not in out:
        raise ValueError('candidate_version')
    audit = make_audit(root, baseline, h, admission, spec['inputs'])
    def worker():
        result = observation.supervise(observation.argv_for(root), root/'evidence', audit)
        if result.get('completed'):
            try:
                for directory, suffix in [('state', '*.nvme.state'), ('attributes', '*.nvme.csv'), ('json', '*.nvme.json')]:
                    members = list((root/directory).glob(suffix))
                    if len(members) != 1:
                        raise ValueError('terminal_state_membership')
                    s = members[0].lstat()
                    if not stat.S_ISREG(s.st_mode) or s.st_uid != 0 or s.st_size > 1048576:
                        raise ValueError('terminal_state_identity')
            except Exception as exc:
                result['completed'] = False
                result['failure'] = str(exc)
        # Preserve the core result independently from final membership checks.
        (root/'evidence/terminal.json').write_text(json.dumps(result, indent=2)+'\n')
        return result
    return detach(root, worker)
