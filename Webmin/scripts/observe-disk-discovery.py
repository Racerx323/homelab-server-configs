#!/usr/bin/env python3
"""Bounded passive observation; no disk queries, source changes or rollback."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import time
from urllib.parse import unquote

FAULTS = 'reset.*USB|USB.*reset|I/O error|Buffer I/O|EXT4-fs error|uas_eh_|device reset|timed out|abort|Out of memory|oom-kill|under-voltage|over-current'


def write(path, value):
    tmp = path.with_suffix(path.suffix + '.tmp')
    with tmp.open('w') as stream:
        json.dump(value, stream, sort_keys=True)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(tmp, path)


def read(path, limit=2_000_000):
    with Path(path).open('rb') as stream:
        data = stream.read(limit + 1)
    if len(data) > limit:
        raise RuntimeError('read_bound: ' + str(path))
    return data


def run(args, allowed=(0,)):
    p = subprocess.run(args, stdin=subprocess.DEVNULL, capture_output=True,
                       timeout=20, env=dict(os.environ, LC_ALL='C'))
    if p.returncode not in allowed or p.stderr or len(p.stdout) > 2_000_000:
        raise RuntimeError('metadata_command_failed: ' + args[0])
    return p.stdout.decode()


def deserialize(value, depth=0):
    """Decode Webmin's nested percent-escaped variable format, one layer at a time."""
    if depth > 32:
        raise ValueError('cache_depth')
    kind, *parts = value.split(',')
    if kind == 'UNDEF' and not parts:
        return None
    if kind == 'VAL' and len(parts) == 1:
        return unquote(parts[0], errors='strict')
    if kind not in ('HASH', 'ARRAY') or len(parts) > 10000:
        raise ValueError('cache_encoding')
    values = [deserialize(unquote(p, errors='strict'), depth + 1) for p in parts]
    if kind == 'ARRAY':
        return values
    if len(values) % 2 or any(not isinstance(k, str) for k in values[::2]):
        raise ValueError('cache_hash')
    if len(set(values[::2])) != len(values[::2]):
        raise ValueError('cache_duplicate_key')
    return dict(zip(values[::2], values[1::2]))


def drive_health(data, expected):
    info = deserialize(data.decode().rstrip('\n'))
    drives = info.get('drivetemps') if isinstance(info, dict) else None
    if not isinstance(drives, list):
        raise ValueError('missing_drive_health')
    found = []
    for drive in drives:
        if not isinstance(drive, dict) or not {'device', 'temp', 'failed', 'errors'} <= drive.keys():
            raise ValueError('incomplete_drive_health')
        if drive['failed'] not in ('', '0') or drive['errors'] not in (None, [], '', '0'):
            raise ValueError('failed_drive_health')
        temperature = float(drive['temp'])
        if not math.isfinite(temperature) or not 0 < temperature < 80:
            raise ValueError('invalid_drive_temperature')
        found.append(drive['device'])
    if sorted(found) != sorted(expected):
        raise ValueError('drive_coverage_changed')
    return [{'device': d['device'], 'temp': float(d['temp'])} for d in drives]


def history(data, now, temperature=False):
    records = {}
    for line in data.decode().splitlines()[-400:]:
        fields = line.lstrip('\0').split()
        if not fields:
            continue
        if not re.fullmatch(r'\d{10}', fields[0]):
            raise ValueError('invalid_history_timestamp')
        stamp = int(fields[0])
        if stamp > now + 5:
            raise ValueError('future_history_timestamp')
        if temperature:
            if len(fields) != 2:
                raise ValueError('invalid_temperature_history')
            value = float(fields[1])
            if not math.isfinite(value) or not 0 < value < 80:
                raise ValueError('invalid_temperature_history')
        else:
            value = fields[1:]
        if stamp in records and records[stamp] != value:
            raise ValueError('conflicting_history_timestamp')
        records[stamp] = value
    return records


def collect(spec, since):
    now, mono = time.time(), time.monotonic()
    paths = spec['files']
    files = {p: hashlib.sha256(read(p)).hexdigest() for p in paths}
    cache = Path(spec['cache'])
    # A Webmin atomic replacement can race this read; retry an unstable snapshot.
    for _ in range(3):
        before = cache.stat()
        data = read(cache)
        after = cache.stat()
        if (before.st_ino, before.st_mtime_ns) == (after.st_ino, after.st_mtime_ns):
            break
    else:
        raise RuntimeError('unstable_health_cache')
    histories = {name: history(read(path), now, name == 'drivetemp')
                 for name, path in spec['history'].items()}
    log = run(['journalctl', '-k', '-b', '--since=@' + str(int(since)),
               '--grep=' + FAULTS, '--output=json', '--no-pager', '--quiet', '-n', '2001'], (0, 1))
    events = [json.loads(line) for line in log.splitlines()]
    if len(events) >= 2001:
        raise RuntimeError('journal_truncated')
    processes = run(['ps', '-eo', 'comm,args'])
    busy = any(line.split()[0] in ('smartctl', 'parted', 'fdisk') or '/webmincron/' in line
               or '/system-status/' in line for line in processes.splitlines()[1:] if line.split())
    packages = run(['dpkg-query', '-W', '-f=${binary:Package} ${Version}\n', *spec['packages']])
    return {'wall': time.time(), 'mono': time.monotonic(), 'boot': read('/proc/sys/kernel/random/boot_id').decode().strip(),
            'kernel': os.uname().release, 'root': run(['findmnt', '-n', '-o', 'SOURCE,FSTYPE', '/']).strip(),
            'topology': str(Path('/sys/block/sda/device').resolve()), 'files': files,
            'packages': dict(line.split(' ', 1) for line in packages.splitlines()),
            'services': run(['systemctl', 'show', 'webmin.service', 'smartmontools.service', '-p', 'Id', '-p', 'ActiveState', '-p', 'MainPID']),
            'counters': {name: int(read(path), base) for name, (path, base) in spec['counters'].items()},
            'health': drive_health(data, spec['expected_devices']), 'cache_mtime': after.st_mtime,
            'history': histories, 'kernel_events': events, 'busy': busy}


def validate(spec, baseline, sample):
    for key in ['boot', 'kernel', 'root', 'topology', 'files', 'packages', 'services']:
        if sample[key] != spec[key]:
            raise RuntimeError('identity_or_configuration_drift: ' + key)
    if sample['kernel_events']:
        raise RuntimeError('kernel_fault')
    if sample['counters']['iotmo'] != baseline['counters']['iotmo'] or sample['counters']['ext4'] != baseline['counters']['ext4']:
        raise RuntimeError('storage_counter_change')
    if sample['counters']['ioerr'] != baseline['counters']['ioerr']:
        raise RuntimeError('counter_change_requires_attribution')
    if abs((sample['wall'] - baseline['wall']) - (sample['mono'] - baseline['mono'])) > 5:
        raise RuntimeError('clock_discontinuity')
    age_limit = spec['interval_seconds'] + spec['sample_seconds'] + 30
    if not 0 <= sample['wall'] - sample['cache_mtime'] <= age_limit:
        raise RuntimeError('health_cache_stale_or_future')
    for name, records in sample['history'].items():
        if not records or not 0 <= sample['wall'] - max(records) <= age_limit:
            raise RuntimeError('history_stale_or_future: ' + name)


def checkpoint(spec, start, sample, seen):
    elapsed = sample['mono'] - start['mono']
    minimum = max(0, int(elapsed // spec['interval_seconds']) - 1)
    counts = {name: len(stamps) for name, stamps in seen.items()}
    if any(count < minimum for count in counts.values()):
        raise RuntimeError('insufficient_completed_collections')
    return {'elapsed_seconds': elapsed, 'minimum_cycles': minimum, 'counts': counts,
            'health': sample['health'], 'counter_delta': sample['counters']['ioerr'] - start['counters']['ioerr']}


def notify(message):
    address = os.environ.get('NOTIFY_SOCKET')
    if not address:
        return
    if address.startswith('@'):
        address = '\0' + address[1:]
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sock:
        sock.connect(address)
        sock.sendall(message.encode())


def alert(root, reason):
    value = {'state': 'review_required', 'reason': reason, 'wall': time.time(),
             'rollback_performed': False, 'monitoring_changed': False}
    write(root / 'ALERT.json', value)
    write(root / 'result.json', value)
    print('WEBMIN_DISCOVERY_OBSERVATION_REQUIRES_REVIEW: ' + reason, file=sys.stderr, flush=True)


def observe(spec_path, root):
    spec = json.loads(read(spec_path))
    root = Path(root)
    if root.is_symlink() or root.stat().st_uid != 0 or root.stat().st_mode & 0o777 != 0o700:
        raise RuntimeError('unsafe_evidence_directory')
    def interrupted(signum, frame):
        raise RuntimeError('observer_interrupted: ' + str(signum))
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        baseline = collect(spec, time.time() - spec['interval_seconds'])
        write(root / 'baseline.json', baseline)
        validate(spec, baseline, baseline)
        seen = {name: set() for name in spec['history']}
        last = baseline
        made_two_hour = False
        notify('READY=1\nSTATUS=Passive observation running')
        write(root / 'result.json', {'state': 'observing', 'start_wall': baseline['wall']})
        with (root / 'samples.jsonl').open('x') as stream:
            while True:
                sample = collect(spec, last['wall'] - 2)
                # Retain failed raw evidence before evaluating it.
                stream.write(json.dumps(sample, sort_keys=True) + '\n')
                stream.flush()
                if stream.tell() > 128 * 1024 * 1024:
                    raise RuntimeError('evidence_size_bound')
                if sample['mono'] - last['mono'] > spec['sample_seconds'] + 30:
                    raise RuntimeError('sample_gap')
                validate(spec, baseline, sample)
                for name, records in sample['history'].items():
                    seen[name].update(t for t in records if t >= baseline['wall'])
                summary = checkpoint(spec, baseline, sample, seen)
                write(root / 'progress.json', summary)
                if not made_two_hour and summary['elapsed_seconds'] >= 7200:
                    write(root / 'checkpoint-2h.json', summary)
                    made_two_hour = True
                if summary['elapsed_seconds'] >= 86400:
                    write(root / 'checkpoint-24h.json', summary)
                    if sample['wall'] - sample['cache_mtime'] >= 75 and not sample['busy']:
                        summary.update(state='complete', settling_basis='completed_health_cache_write',
                                       settled_seconds=sample['wall'] - sample['cache_mtime'],
                                       rollback_performed=False, monitoring_changed=False)
                        write(root / 'result.json', summary)
                        notify('STATUS=24-hour passive observation complete')
                        return
                if summary['elapsed_seconds'] > 86850:
                    raise RuntimeError('final_settling_deadline')
                last = sample
                notify('WATCHDOG=1')
                time.sleep(spec['sample_seconds'])
    except Exception as exc:
        alert(root, str(exc))
        raise


def finalize(root):
    root = Path(root)
    try:
        result = json.loads(read(root / 'result.json'))
    except (OSError, ValueError):
        result = {}
    if result.get('state') not in ('complete', 'review_required'):
        alert(root, 'observer_terminated_without_terminal_result')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('observe')
    p.add_argument('spec', type=Path)
    p.add_argument('root', type=Path)
    p = sub.add_parser('finalize')
    p.add_argument('root', type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    if args.command == 'observe':
        observe(args.spec, args.root)
    else:
        finalize(args.root)


if __name__ == '__main__':
    main()
