#!/usr/bin/env python3
"""Guard owner scans; producer mode retains the scheduled notification behavior."""
import argparse
import fcntl
import json
import os
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


def observe(directory, producer=False):
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
    try:
        before = snapshot()
        result['samples'].append(before)
        if not has_reserve(before, 2 * RESERVE):
            raise ValueError('reserve unavailable before scan: require 96 MiB scan plus 96 MiB reserve after observer startup')
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
            result['samples'].append(sample)
            # Persist samples before each decision, including rejection.
            (directory / 'observation.json').write_text(json.dumps(result, indent=2) + '\n')
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
        result['accepted'] = True
    except Exception as exc:
        result['error'] = type(exc).__name__ + ': ' + str(exc)
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
        (directory / 'observation.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: value for key, value in result.items() if key != 'samples'}))
    return 0 if result['accepted'] else 1


OBSERVER_UNIT = 'kuma-capacity-observer.service'


def guarded(directory, producer=False):
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
        seconds = 440 if producer else 120
        argv = ['systemd-run', '--wait', '--pipe', '--collect', '--unit=' + OBSERVER_UNIT,
                '--property=RuntimeMaxSec=' + str(seconds) + 's', '--property=TimeoutStopSec=5s',
                '--property=KillMode=control-group', '--property=MemoryMax=32M',
                '--property=MemorySwapMax=0', '--property=LimitFSIZE=8M']
        if producer:
            argv += ['--setenv=RECIPIENT=' + os.environ['RECIPIENT']]
        argv += ['/usr/bin/python3', '-I', '-B', str(Path(__file__).resolve()), str(directory)]
        if producer:
            argv += ['--producer']
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
    parser.add_argument('--guard', action='store_true')
    parser.add_argument('--admit-mib', type=int, choices=(160, 416))
    args = parser.parse_args()
    os.umask(0o077)
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
    raise SystemExit(guarded(args.directory, args.producer) if args.guard else observe(args.directory, args.producer))
