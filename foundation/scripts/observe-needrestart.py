#!/usr/bin/env python3
"""Guard owner scans; producer mode retains the scheduled notification behavior."""
import argparse
import fcntl
import json
import os
import re
import signal
import shutil
from pathlib import Path
import stat
import sys
import tempfile
import subprocess
import time


UNIT = 'needrestart-capacity-measurement.service'
RESERVE = 96 * 1024 * 1024


def command(argv, timeout=10):
    return subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=True).stdout


def properties(unit=UNIT):
    return dict(line.split('=', 1) for line in command([
        'systemctl', 'show', unit,
        '--property=LoadState,ActiveState,SubState,MainPID,Result,ExecMainCode,ExecMainStatus,MemoryPeak,MemorySwapPeak,ControlGroup',
    ]).splitlines())


def number(path):
    value = path.read_text().strip()
    return None if value == 'max' else int(value)


def ancestor_headroom():
    # Exclude the observer's own cap, include every containing slice/root cap.
    relative = next(line[3:] for line in Path('/proc/self/cgroup').read_text().splitlines()
                    if line.startswith('0::'))
    root = Path('/sys/fs/cgroup')
    group = root / relative.lstrip('/')
    if '..' in group.parts:
        raise ValueError('unexpected cgroup namespace path')
    parents = list(group.parents) if group != root else [root]
    result = {}
    for parent in parents:
        if parent != root and root not in parent.parents:
            continue
        maximum_path = parent / 'memory.max'
        if not maximum_path.exists():
            continue
        maximum = number(maximum_path)
        current = number(parent / 'memory.current')
        result[str(parent.relative_to(root))] = {
            'current_bytes': current, 'max_bytes': maximum,
            'headroom_bytes': None if maximum is None else maximum - current,
        }
    return result


def snapshot():
    available = int(next(line.split()[1] for line in Path('/proc/meminfo').read_text().splitlines()
                         if line.startswith('MemAvailable:')))
    return {'monotonic_seconds': time.monotonic(), 'host_available_kib': available,
            'ancestors': ancestor_headroom()}


def has_reserve(sample, required=RESERVE):
    return sample['host_available_kib'] * 1024 >= required and all(
        item['headroom_bytes'] is None or item['headroom_bytes'] >= required
        for item in sample['ancestors'].values())


def atomic_receipt(path, value):
    fd, temporary = tempfile.mkstemp(prefix='.observation-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream, indent=2); stream.write('\n')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


def trial_profile(path):
    info = path.lstat()
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o600
            or info.st_size > 16384 or any(p.is_symlink() for p in (path, *path.parents))):
        raise ValueError('trial profile must be root-owned private regular file')
    profile = json.loads(path.read_text())
    if set(profile) not in ({'duration_seconds', 'scan_after_seconds', 'services'}, {'duration_seconds', 'scan_after_seconds', 'services', 'workload_token'}):
        raise ValueError('unexpected trial profile fields')
    if 'workload_token' in profile and not re.fullmatch(r'[0-9a-f]{64}', profile['workload_token']):
        raise ValueError('invalid workload operation token')
    duration, scan_after = profile['duration_seconds'], profile['scan_after_seconds']
    if type(duration) is not int or type(scan_after) is not int or not 150 <= duration <= 600 or not 30 <= scan_after <= duration - 100:
        raise ValueError('trial requires baseline, scan and bounded post-scan observation')
    if not isinstance(profile['services'], dict) or not 1 <= len(profile['services']) <= 8:
        raise ValueError('explicit bounded service set required')
    for unit, values in profile['services'].items():
        if not re.fullmatch(r'[a-zA-Z0-9@_.-]+\.service', unit) or set(values) != {'cgroup', 'memory.high', 'memory.max', 'memory.swap.max'}:
            raise ValueError('invalid service binding')
        group = values['cgroup']
        if not isinstance(group, str) or not re.fullmatch(r'/[a-zA-Z0-9@_./:-]+', group) or any(p in ('.', '..', '') for p in group[1:].split('/')):
            raise ValueError('invalid cgroup binding')
        for key in ('memory.high', 'memory.max', 'memory.swap.max'):
            if not isinstance(values[key], str) or not re.fullmatch(r'[0-9]+|max', values[key]):
                raise ValueError('invalid resource control binding')
        if values['memory.max'] == 'max' or values['memory.swap.max'] != '0':
            raise ValueError('bounded no-swap service required')
    return profile


class TrialObservation:
    """Service samples in the scan's sole observer, never an additional sampler."""
    def __init__(self, directory, profile):
        self.directory, self.profile = directory, profile
        self.started = time.monotonic()
        self.previous = None
        self.baseline = {}
        self.samples = self.bytes = 0
        self.minimum_available = None
        self.maximum_gap = 0
        self.stream = (directory / 'trial-samples.jsonl').open('x')

    def record(self, sample, phase):
        if (self.directory / 'workload-cancelled.json').exists():
            raise InterruptedError('parent cancelled owned workload')
        row = dict(sample, phase=phase, realtime_ns=time.time_ns(), services={})
        failures = []
        for unit, expected in self.profile['services'].items():
            props = dict(line.split('=', 1) for line in command([
                'systemctl', 'show', unit,
                '--property=ActiveState,ControlGroup,MainPID,NRestarts,ActiveEnterTimestampMonotonic',
            ], timeout=2).splitlines())
            if props.get('ActiveState') != 'active' or not props.get('MainPID', '').isdecimal() or int(props['MainPID']) <= 0 or props.get('ControlGroup') != expected['cgroup']:
                raise ValueError('trial service state mismatch: ' + json.dumps({'unit': unit, 'expected': {'ActiveState': 'active', 'ControlGroup': expected['cgroup'], 'MainPID': 'positive'}, 'observed': {k: props.get(k, 'missing')[:256] for k in ('ActiveState', 'ControlGroup', 'MainPID')}}))
            group = Path('/sys/fs/cgroup') / expected['cgroup'].lstrip('/')
            if group.resolve() != group:
                raise ValueError('trial cgroup symlink: ' + unit)
            values = {}
            for key in ('memory.current', 'memory.high', 'memory.max', 'memory.swap.max', 'memory.swap.current', 'memory.events', 'memory.pressure', 'cpu.pressure'):
                with (group / key).open() as stream:
                    value = stream.read(2049)
                if len(value) > 2048:
                    raise ValueError('oversize cgroup observation: ' + unit)
                values[key] = value.strip()
            identity = (group.stat().st_ino, props['MainPID'], props['NRestarts'], props['ActiveEnterTimestampMonotonic'])
            counts = {k: int(v) for k, v in (line.split() for line in values['memory.events'].splitlines())}
            for key in ('max', 'oom', 'oom_kill'):
                if key not in counts:
                    raise ValueError('missing memory event: ' + unit)
            row['services'][unit] = {'properties': props, 'cgroup_inode': identity[0], **values}
            initial = self.baseline.setdefault(unit, (identity, counts))
            if identity != initial[0] or any(counts[k] != initial[1][k] for k in ('max', 'oom', 'oom_kill')):
                failures.append({'unit': unit, 'check': 'identity-or-hard-event', 'expected_identity': initial[0], 'observed_identity': identity, 'expected_events': initial[1], 'observed_events': counts})
            if any(values[k] != expected[k] for k in ('memory.high', 'memory.max', 'memory.swap.max')) or values['memory.swap.current'] != '0':
                failures.append({'unit': unit, 'check': 'controls-or-swap', 'expected': expected, 'observed': {k: values[k] for k in ('memory.high', 'memory.max', 'memory.swap.max', 'memory.swap.current')}})
            int(values['memory.current'])
        # Include the observer's resident cgroup cost rather than adding back a guess.
        relative = next(line[3:] for line in Path('/proc/self/cgroup').read_text().splitlines() if line.startswith('0::'))
        group = Path('/sys/fs/cgroup') / relative.lstrip('/')
        row['observer_current_bytes'] = number(group / 'memory.current')
        row['observer_peak_bytes'] = number(group / 'memory.peak')
        stamp = sample['monotonic_seconds']
        gap = 0 if self.previous is None else stamp - self.previous
        self.maximum_gap = max(self.maximum_gap, gap)
        self.previous = stamp
        self.minimum_available = min(self.minimum_available or sample['host_available_kib'], sample['host_available_kib'])
        row['failures'] = failures
        encoded = json.dumps(row, separators=(',', ':')) + '\n'
        self.bytes += len(encoded.encode())
        if self.bytes > 6 * 1024 * 1024:
            raise ValueError('trial evidence bound exceeded')
        self.stream.write(encoded); self.stream.flush()
        self.samples += 1
        if failures:
            raise ValueError('trial service identity/events/controls failed; see retained sample')
        if time.monotonic() - stamp > 1:
            raise ValueError('trial sample acquisition exceeded one second')
        if not 0 <= gap <= 1:
            raise ValueError('trial sample gap exceeded one second')
        if not has_reserve(sample):
            raise ValueError('trial host or ancestor reserve below 96 MiB')

    def until(self, seconds, phase=None):
        while time.monotonic() - self.started < seconds:
            elapsed = time.monotonic() - self.started
            self.record(snapshot(), phase or ('baseline' if elapsed < 30 else 'workload'))
            if elapsed >= 30 and not (self.directory / 'trial-ready.json').exists():
                (self.directory / 'trial-ready.json').write_text(json.dumps({'realtime_ns': time.time_ns(), 'monotonic_seconds': time.monotonic()}) + '\n')
            time.sleep(.5)
        if seconds >= 30 and not (self.directory / 'trial-ready.json').exists():
            (self.directory / 'trial-ready.json').write_text(json.dumps({'realtime_ns': time.time_ns(), 'monotonic_seconds': time.monotonic()}) + '\n')

    def wait_workload(self):
        self.until(30)
        gate = self.directory / 'workload-ready.json'
        while time.monotonic() - self.started < self.profile['scan_after_seconds']:
            self.record(snapshot(), 'await-workload')
            if gate.exists():
                info = gate.lstat()
                if (not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or
                        stat.S_IMODE(info.st_mode) != 0o600 or info.st_size > 256):
                    raise ValueError('unsafe workload gate')
                if json.loads(gate.read_text()) != {'token': self.profile['workload_token']}:
                    raise ValueError('workload gate token mismatch')
                return
            time.sleep(.5)
        raise TimeoutError('paired browser readiness deadline; scan not started')

    def close(self, accepted):
        self.stream.close()
        (self.directory / 'trial-summary.json').write_text(json.dumps({
            'resource_scan_accepted': accepted, 'application_acceptance': 'separate browser/path/overlap receipts required',
            'samples': self.samples, 'maximum_sample_gap_seconds': self.maximum_gap,
            'minimum_host_available_kib': self.minimum_available,
            'duration_seconds': time.monotonic() - self.started,
            'profile': self.profile,
        }, indent=2) + '\n')


def observe(directory, producer=False, profile=None):
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError('observation directory must be root-owned mode 0700')
    if any(parent.is_symlink() for parent in (directory, *directory.parents)):
        raise ValueError('symlink in observation directory')
    if properties()['LoadState'] != 'not-found':
        raise ValueError('measurement unit already exists; no takeover')
    result = {'accepted': False, 'scope': 'needrestart scan only; not combined application acceptance',
              'sample_interval_seconds': 0.2, 'reserve_bytes': RESERVE, 'samples': []}
    scan_seconds = 420 if producer else 90
    result['producer'] = producer
    attempted = False
    trial = None
    try:
        before = snapshot()
        result['samples'].append(before)
        if not has_reserve(before, 2 * RESERVE):
            raise ValueError('reserve unavailable before scan: require 96 MiB scan plus 96 MiB reserve after observer startup')
        if profile is not None:
            if producer:
                raise ValueError('trial cannot submit scheduled notifications')
            trial = TrialObservation(directory, profile)
            if 'workload_token' in profile:
                trial.wait_workload()
            else:
                trial.until(profile['scan_after_seconds'])
            before = snapshot()
            result['samples'] = [before]
            if not has_reserve(before, 2 * RESERVE):
                raise ValueError('fresh 192 MiB scan admission failed after trial baseline')
            result['scope'] = 'combined service resources and list-only scan; application acceptance separate'
        # Exclusive files prevent truncating or following pre-existing outputs.
        for name in ('scan.stdout', 'scan.stderr'):
            with (directory / name).open('x'):
                pass
        attempted = True
        command([
            'systemd-run', '--no-block', '--unit=' + UNIT, '--service-type=oneshot',
            '--remain-after-exit', '--property=TimeoutStartSec=' + str(scan_seconds) + 's', '--property=TimeoutStopSec=5s',
            '--property=KillMode=control-group', '--property=SendSIGKILL=yes',
            '--property=MemoryAccounting=yes', '--property=MemoryMax=96M', '--property=MemorySwapMax=0',
            '--property=CPUQuota=100%', '--property=LimitFSIZE=64K', '--property=UMask=0077',
            '--property=StandardOutput=append:' + str(directory / 'scan.stdout'),
            '--property=StandardError=append:' + str(directory / 'scan.stderr'),
            '--setenv=NEEDRESTART_MODE=l',
        ] + (['--setenv=RECIPIENT=' + os.environ['RECIPIENT'], '/bin/bash',
              '/usr/local/sbin/needrestart.sh'] if producer else ['/usr/sbin/needrestart', '-bkl']))
        deadline = time.monotonic() + scan_seconds + 10
        while time.monotonic() < deadline:
            sample = snapshot()
            state = properties()
            sample['scan_state'] = state
            if state.get('ControlGroup'):
                group = Path('/sys/fs/cgroup') / state['ControlGroup'].lstrip('/')
                sample['scan_cgroup'] = {}
                for key in ('memory.current', 'memory.peak', 'memory.max', 'memory.swap.max', 'memory.events'):
                    try:
                        sample['scan_cgroup'][key] = (group / key).read_text().strip()
                    except FileNotFoundError:
                        sample['scan_cgroup'][key] = 'removed during exit'
            if trial:
                trial.record(sample, 'scan')
            result['samples'].append(sample)
            # Persist samples before each decision, including rejection.
            atomic_receipt(directory / 'observation.json', result)
            if len(result['samples']) > 1 and (sample['monotonic_seconds'] - result['samples'][-2]['monotonic_seconds']) > 1:
                raise ValueError('sample gap exceeded one second')
            if not has_reserve(sample):
                raise ValueError('host or finite ancestor reserve below 96 MiB during scan')
            events = sample.get('scan_cgroup', {}).get('memory.events')
            if events and events != 'removed during exit':
                values = dict(line.split() for line in events.splitlines())
                if any(int(values[k]) != 0 for k in ('max', 'oom', 'oom_kill')):
                    raise ValueError('scan memory limit/OOM event observed')
            if state['ActiveState'] == 'failed':
                raise ValueError('native scan failure: ' + state.get('Result', 'unknown'))
            if state['SubState'] == 'exited':
                peak = int(state['MemoryPeak'])
                if state['Result'] != 'success' or state['ExecMainStatus'] != '0':
                    raise ValueError('scan exit was unsuccessful')
                if not 0 < peak <= RESERVE or state['MemorySwapPeak'] != '0':
                    raise ValueError('missing or invalid native scan peak/no-swap evidence')
                result['scan_peak_bytes'] = peak
                result['scan_terminal'] = state
                during = [s for s in result['samples'] if int(s.get('scan_state', {}).get('MainPID', '0')) > 0]
                result['samples_with_scan_running'] = len(during)
                if not during:
                    raise ValueError('no headroom sample observed with a running scan')
                result['minimum_host_available_during_scan_kib'] = min(s['host_available_kib'] for s in during)
                break
            time.sleep(0.2)
        else:
            raise TimeoutError('scan observation deadline exceeded')
        if trial:
            trial.until(profile['duration_seconds'], phase='post-scan')
        result['accepted'] = True
    except Exception as exc:
        result['error'] = type(exc).__name__ + ': ' + str(exc)
        atomic_receipt(directory / 'observation.json', result)
    finally:
        if attempted:
            try:
                command(['systemctl', 'stop', UNIT])
                state = properties()
                if state['LoadState'] != 'not-found' and state['ActiveState'] not in ('inactive', 'failed'):
                    raise ValueError('scan still active after stop')
                result['cleanup'] = state
                if state['LoadState'] != 'not-found':
                    command(['systemctl', 'reset-failed', UNIT])
            except Exception as exc:
                result['accepted'] = False
                result['cleanup_error'] = type(exc).__name__ + ': ' + str(exc)
        result['minimum_host_available_kib'] = min(s['host_available_kib'] for s in result['samples']) if result['samples'] else None
        result['maximum_sample_gap_seconds'] = max(
            (b['monotonic_seconds'] - a['monotonic_seconds'] for a, b in zip(result['samples'], result['samples'][1:])),
            default=0)
        if result['maximum_sample_gap_seconds'] > 1:
            result['accepted'] = False
            result['sampling_error'] = 'sample gap exceeded one second; timing is insufficient for acceptance'
        result['limitations'] = ['Discrete samples cannot exclude dips between samples.',
                                'Observer/SSH/Ansible overhead is included, not subtracted.',
                                'Native MemoryPeak is retained before stopping the exited unit.']
        if trial:
            trial.close(result['accepted'])
        atomic_receipt(directory / 'observation.json', result)
    print(json.dumps({key: value for key, value in result.items() if key != 'samples'}))
    return 0 if result['accepted'] else 1


OBSERVER_UNIT = 'kuma-capacity-observer.service'


def guarded(directory, producer=False, profile_path=None):
    """One 224 MiB admission and one supervised observation; never retry."""
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError('guard directory must be root-owned mode 0700')
    if any(p.is_symlink() for p in (directory, *directory.parents)) or any(directory.iterdir()):
        raise ValueError('guard directory must be empty with no symlink ancestors')
    result = {'accepted': False, 'minimum_available_kib': 229376, 'producer': producer}
    launched = False
    lock = None
    try:
        lock = os.open('/run/lock/needrestart-capacity.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        info = os.fstat(lock)
        if info.st_uid != 0 or not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600:
            raise ValueError('unsafe scan lock')
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for unit in (UNIT, OBSERVER_UNIT):
            if properties(unit)['LoadState'] != 'not-found':
                raise ValueError('existing unit; no takeover: ' + unit)
        if producer and (not os.environ.get('RECIPIENT') or any(c in os.environ['RECIPIENT'] for c in '\r\n\x00')):
            raise ValueError('scheduled producer requires a valid RECIPIENT')
        result['before_observer'] = snapshot()
        (directory / 'admission.json').write_text(json.dumps(result, indent=2) + '\n')
        if not has_reserve(result['before_observer'], 224 * 1024 * 1024):
            raise ValueError('scan skipped: less than 224 MiB before observer; no retry')
        profile = trial_profile(profile_path) if profile_path is not None else None
        if producer and profile is not None:
            raise ValueError('trial cannot use the scheduled notification producer')
        seconds = profile['duration_seconds'] + 45 if profile else (440 if producer else 120)
        argv = ['systemd-run', '--wait', '--pipe', '--collect', '--unit=' + OBSERVER_UNIT,
                '--property=RuntimeMaxSec=' + str(seconds) + 's', '--property=TimeoutStopSec=5s',
                '--property=KillMode=control-group', '--property=MemoryMax=32M',
                '--property=MemorySwapMax=0', '--property=LimitFSIZE=8M']
        if producer:
            argv += ['--setenv=RECIPIENT=' + os.environ['RECIPIENT']]
        argv += ['/usr/bin/python3', '-I', '-B', str(Path(__file__).resolve()), str(directory)]
        if producer:
            argv += ['--producer']
        if profile_path is not None:
            argv += ['--trial-profile', str(profile_path)]
        launched = True
        run = subprocess.run(argv, capture_output=True, text=True, timeout=seconds + 15)
        result['observer_rc'] = run.returncode
        result['observer_stderr'] = run.stderr
        observation = json.loads((directory / 'observation.json').read_text())
        result['observation'] = {k: v for k, v in observation.items() if k != 'samples'}
        if run.returncode != 0 or not observation['accepted']:
            raise ValueError('scan/observer did not pass; see retained observation')
        result['accepted'] = True
    except Exception as exc:
        result['error'] = type(exc).__name__ + ': ' + str(exc)
    finally:
        if launched:
            try:
                # The observer owns the scan. Stop both only after unused-name preflight
                # and our launch; the common lock excludes another guarded invocation.
                for unit in (OBSERVER_UNIT, UNIT):
                    if properties(unit)['LoadState'] != 'not-found':
                        command(['systemctl', 'stop', unit])
                result['cleanup'] = {unit: properties(unit) for unit in (OBSERVER_UNIT, UNIT)}
                for unit, state in result['cleanup'].items():
                    if state.get('MainPID') != '0' or state['ActiveState'] not in ('inactive', 'failed'):
                        raise ValueError('owned process remains: ' + unit)
                    if state['LoadState'] != 'not-found':
                        command(['systemctl', 'reset-failed', unit])
            except Exception as exc:
                result['accepted'] = False
                result['cleanup_error'] = str(exc)
        (directory / 'guard.json').write_text(json.dumps(result, indent=2) + '\n')
        if lock is not None:
            os.close(lock)
    print(json.dumps(result))
    if not result['accepted']:
        for name in ('scan.stdout', 'scan.stderr'):
            path = directory / name
            if path.exists():
                print(path.read_text()[:65536], file=sys.stderr)
    return 0 if result['accepted'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, nargs='?')
    parser.add_argument('--producer', action='store_true')
    parser.add_argument('--trial-profile', type=Path)
    parser.add_argument('--guard', action='store_true')
    parser.add_argument('--admit-mib', type=int, choices=(160, 416))
    args = parser.parse_args()
    os.umask(0o077)
    def interrupted(signum, frame):
        raise InterruptedError('observer interrupted')
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    if args.trial_profile is not None and (args.producer or args.admit_mib is not None or args.directory is None):
        parser.error('trial requires an explicit directory and no producer/admission mode')
    if args.admit_mib is not None:
        if args.guard or args.producer or args.directory is not None:
            parser.error('transient admission cannot be combined with a scan')
        reading = snapshot()
        accepted = has_reserve(reading, args.admit_mib * 1024 * 1024)
        print(json.dumps({'accepted': accepted, 'required_mib': args.admit_mib, 'reading': reading}))
        raise SystemExit(0 if accepted else 1)
    if args.directory is None:
        if not args.guard or not args.producer:
            parser.error('directory is required except for guarded scheduled producer')
        # Cron retains failure stdout/stderr; no unbounded per-run disk accumulation.
        directory = Path(tempfile.mkdtemp(prefix='needrestart-guard-', dir='/run'))
        rc = guarded(directory, producer=True)
        receipt = json.loads((directory / 'guard.json').read_text())
        if 'cleanup_error' in receipt:
            print('Cleanup unverified; private evidence retained at ' + str(directory), file=sys.stderr)
        else:
            shutil.rmtree(directory)
        raise SystemExit(rc)
    raise SystemExit(guarded(args.directory, args.producer, args.trial_profile) if args.guard else observe(args.directory, args.producer, trial_profile(args.trial_profile) if args.trial_profile else None))
