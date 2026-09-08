#!/usr/bin/env python3
"""Apply a guarded Webmin polling mitigation and observe it without SMART reads."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import signal
import stat
import subprocess
import tempfile
import threading
import time

CONFIG = Path('/etc/webmin/system-status/config')
BASE = Path('/var/lib/webmin-drive-polling-trial')
HISTORY = Path('/var/webmin/modules/system-status/history')
BOOT = Path('/proc/sys/kernel/random/boot_id')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    fd, name = tempfile.mkstemp(prefix='.record-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream, sort_keys=True)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def run(args, allowed=(0,)):
    result = subprocess.run(args, capture_output=True, text=True, timeout=30)
    if result.returncode not in allowed or result.stderr or len(result.stdout) > 2_000_000:
        raise RuntimeError('probe_failed: ' + args[0])
    return result.stdout


def guarded_replace(path, before, after, metadata, restore=False):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or path.is_symlink():
        raise RuntimeError('config_not_regular')
    if (info.st_uid, info.st_gid, stat.S_IMODE(info.st_mode)) != (
        metadata['uid'], metadata['gid'], metadata['mode']
    ) or path.read_bytes() != before:
        raise RuntimeError('config_conflict')
    fd, name = tempfile.mkstemp(prefix='.polling-trial-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            os.fchown(stream.fileno(), metadata['uid'], metadata['gid'])
            os.fchmod(stream.fileno(), metadata['mode'])
            stream.write(after)
            stream.flush()
            os.fsync(stream.fileno())
        if restore:
            os.utime(name, ns=(metadata['atime_ns'], metadata['mtime_ns']))
        if path.read_bytes() != before:
            raise RuntimeError('concurrent_config_change')
        os.replace(name, path)
        directory = os.open(path.parent, os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def services():
    return run(['systemctl', 'show', 'webmin.service', 'smartmontools.service',
                'munin-node.service', '--property=Id,ActiveState,MainPID'])


def history(name):
    path = HISTORY / name
    if not path.exists():
        return []
    if path.stat().st_size > 2_000_000:
        raise RuntimeError('history_output_limit')
    # Webmin history may retain a NUL-padded first record after truncation.
    # Keep enough recent records for 24h at five-minute intervals. Invalid
    # timestamps cannot add cycles; freshness and minimum counts fail closed.
    timestamps = []
    for line in path.read_text().splitlines()[-400:]:
        fields = line.lstrip('\x00').split()
        if fields and re.fullmatch(r'[0-9]{10}', fields[0]):
            timestamp = int(fields[0])
            if timestamp <= time.time() + 5:
                timestamps.append(timestamp)
    return timestamps


def ext4_errors():
    return {p.parent.name: int(p.read_text()) for p in Path('/sys/fs/ext4').glob('*/errors_count')}


def diskstats():
    return [line.strip() for line in Path('/proc/diskstats').read_text().splitlines()
            if line.split()[2] == 'sda']


def trace_webmin(root, duration=660):
    """Keep only SMART execution lines; detach when the bounded trace ends."""
    result = {'complete': False, 'read_commands': [], 'error': None}
    proc = None
    try:
        pid = int(run(['systemctl', 'show', 'webmin.service', '--property=MainPID', '--value']))
        if pid <= 1 or Path('/proc', str(pid), 'comm').read_text().strip() != 'miniserv.pl':
            raise RuntimeError('webmin_pid_mismatch')
        proc = subprocess.Popen(['/usr/bin/strace', '-f', '-ttt', '-s', '512',
                                 '-e', 'trace=execve', '-p', str(pid)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                text=True, start_new_session=True)
        selector = selectors.DefaultSelector()
        selector.register(proc.stderr, selectors.EVENT_READ)
        deadline = time.monotonic() + duration
        attached = False
        with (root / 'smart-executions.jsonl').open('a') as output:
            while time.monotonic() < deadline:
                if proc.poll() is not None:
                    raise RuntimeError('trace_exited_early')
                for key, _ in selector.select(timeout=1):
                    line = key.fileobj.readline()
                    if 'attached' in line:
                        attached = True
                    if 'Operation not permitted' in line or 'ptrace:' in line:
                        raise RuntimeError('trace_attach_failed')
                    if re.search(r'execve\("[^"\n]*/smartctl"', line):
                        event = {'epoch': time.time(), 'line': line.strip()}
                        output.write(json.dumps(event) + '\n')
                        output.flush()
                        if '--version' not in line:
                            result['read_commands'].append(event)
                            if len(result['read_commands']) > 100:
                                raise RuntimeError('unexpected_smart_activity_limit')
        result['complete'] = attached
        if not attached:
            result['error'] = 'attachment_not_confirmed'
    except Exception as exc:
        result['error'] = str(exc)
    finally:
        if proc is not None and proc.poll() is None:
            proc.send_signal(signal.SIGINT)
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=10)
        result['finished_epoch'] = time.time()
        write_json(root / 'trace-result.json', result)


def assess(samples, trace, elapsed, cycles):
    reasons = sorted({r for sample in samples for r in sample['reasons']})
    if not trace or not trace.get('complete') or trace.get('error'):
        reasons.append('trace_incomplete')
    if trace and trace.get('read_commands'):
        reasons.append('webmin_smart_reads_observed')
    if cycles < int(elapsed / 300) - 2:
        reasons.append('insufficient_collection_cycles')
    return {'result': 'quiet' if not reasons else 'review_required',
            'reasons': sorted(set(reasons)), 'storage_accepted': False}


def observe(root):
    operation = json.loads((root / 'operation.json').read_text())
    write_json(root / 'ready.json', {'epoch': time.time()})
    deadline = time.monotonic() + 120
    while not (root / 'applied.json').exists():
        if time.monotonic() > deadline:
            # Recover an interrupted apply without re-enabling polling after a
            # completed apply. Only the exact expected trial bytes may revert.
            before = (root / 'original-config').read_bytes()
            metadata = json.loads((root / 'metadata.json').read_text())
            if (root / 'mutation-intent.json').exists() and CONFIG.read_bytes() == before + b'collect_notemp=1\n':
                guarded_replace(CONFIG, before + b'collect_notemp=1\n', before, metadata, restore=True)
                write_json(root / 'abandoned-apply-rollback.json', {'restored': True})
            raise RuntimeError('apply_not_completed')
        time.sleep(1)
    applied = json.loads((root / 'applied.json').read_text())
    trace_thread = threading.Thread(target=trace_webmin, args=(root,), daemon=False)
    trace_thread.start()
    start = applied['epoch']
    monotonic_start = time.monotonic()
    previous = start
    checkpoints = [7200, 86400]
    samples = []
    while True:
        now = time.time()
        elapsed = time.monotonic() - monotonic_start
        reasons = []
        sample = {'epoch': now, 'elapsed_seconds': elapsed, 'reasons': reasons}
        try:
            if BOOT.read_text().strip() != operation['boot_id']:
                reasons.append('boot_changed')
            if sha(CONFIG.read_bytes()) != applied['sha256']:
                reasons.append('configuration_drift')
            if now - previous > 180:
                reasons.append('observation_gap')
            current_services = services()
            sample['services'] = current_services
            if current_services.count('ActiveState=active') != 3:
                reasons.append('service_not_active')
            if current_services != applied['services']:
                reasons.append('service_identity_changed')
            sample['ext4_errors'] = ext4_errors()
            if sample['ext4_errors'] != applied['ext4_errors']:
                reasons.append('filesystem_error_counter_changed')
            sample['diskstats'] = diskstats()
            sample['root_mount'] = run(['findmnt', '-n', '-o', 'SOURCE,FSTYPE,OPTIONS', '/']).strip()
            if sample['root_mount'] != applied['root_mount']:
                reasons.append('root_mount_changed')
            times = history('load')
            sample['collection_count'] = len(set(t for t in times if t >= start + 65))
            sample['latest_collection'] = max(times, default=0)
            sample['latest_disk_usage'] = max(history('diskused'), default=0)
            sample['latest_drive_temperature'] = max(history('drivetemp'), default=0)
            if now - sample['latest_collection'] > 900:
                reasons.append('collector_stale')
            if now - sample['latest_disk_usage'] > 900:
                reasons.append('disk_usage_collection_stale')
            if sample['latest_drive_temperature'] >= start + 65:
                reasons.append('drive_temperature_collection_continues')
            text = run(['journalctl', '--boot=0', '--dmesg', '--since=@' + str(int(start)),
                        '--grep=reset SuperSpeed|I/O error|Buffer I/O|EXT4-fs error|uas_eh_|device reset',
                        '--output=json', '--no-pager', '--quiet'], allowed=(0, 1))
            events = [json.loads(line) for line in text.splitlines()]
            sample['kernel_events'] = [{'epoch': int(e['__REALTIME_TIMESTAMP']) / 1e6,
                                       'message': e['MESSAGE']} for e in events]
            for event in sample['kernel_events']:
                if 'reset SuperSpeed' in event['message']:
                    if event['epoch'] >= start + 65:
                        reasons.append('usb_reset')
                else:
                    reasons.append('storage_error')
        except Exception as exc:
            reasons.append('probe_failed: ' + str(exc))
        samples.append(sample)
        with (root / 'samples.jsonl').open('a') as output:
            output.write(json.dumps(sample) + '\n')
            output.flush()
        write_json(root / 'latest.json', sample)
        previous = now
        if checkpoints and elapsed >= checkpoints[0]:
            checkpoint = checkpoints.pop(0)
            trace_path = root / 'trace-result.json'
            trace = json.loads(trace_path.read_text()) if trace_path.exists() else None
            result = assess(samples, trace, elapsed, sample.get('collection_count', 0))
            result.update({'epoch': now, 'elapsed_seconds': elapsed,
                           'collection_count': sample.get('collection_count', 0)})
            write_json(root / ('checkpoint-' + str(checkpoint) + '.json'), result)
        if not checkpoints:
            write_json(root / 'complete.json', {'epoch': time.time(), 'storage_accepted': False,
                       'configuration_left_disabled': True, 'review': 'checkpoint-86400.json'})
            break
        time.sleep(60)
    trace_thread.join(timeout=20)


def apply(operation_path):
    op = json.loads(operation_path.read_text())
    if os.uname().nodename != op['host'] or BOOT.read_text().strip() != op['boot_id']:
        raise RuntimeError('target_or_boot_mismatch')
    if not re.fullmatch(r'[a-z0-9-]{1,60}', op['id']):
        raise RuntimeError('invalid_operation_id')
    before = CONFIG.read_bytes()
    info = CONFIG.lstat()
    if sha(before) != op['expected_config_sha256'] or b'collect_notemp=' in before:
        raise RuntimeError('unexpected_configuration')
    metadata = {'uid': info.st_uid, 'gid': info.st_gid, 'mode': stat.S_IMODE(info.st_mode),
                'atime_ns': info.st_atime_ns, 'mtime_ns': info.st_mtime_ns}
    if (metadata['uid'], metadata['gid'], metadata['mode']) != (0, 2, 0o600):
        raise RuntimeError('unexpected_config_metadata')
    if CONFIG.is_symlink() or not stat.S_ISREG(info.st_mode):
        raise RuntimeError('config_not_regular')
    if BASE.exists() and (BASE.is_symlink() or BASE.stat().st_uid != 0 or stat.S_IMODE(BASE.stat().st_mode) != 0o700):
        raise RuntimeError('untrusted_state_directory')
    BASE.mkdir(mode=0o700, exist_ok=True)
    if list(BASE.glob('*/applied.json')):
        raise RuntimeError('existing_trial_requires_review')
    root = BASE / op['id']
    root.mkdir(mode=0o700)
    unit = 'webmin-drive-polling-' + op['id']
    after = before + b'collect_notemp=1\n'
    (root / 'original-config').write_bytes(before)
    write_json(root / 'metadata.json', metadata)
    write_json(root / 'operation.json', op)
    script = Path(__file__).read_bytes()
    if sha(script) != op['script_sha256']:
        raise RuntimeError('script_bundle_mismatch')
    (root / 'observer.py').write_bytes(script)
    current_services = services()
    if current_services.count('ActiveState=active') != 3:
        raise RuntimeError('required_service_not_active')
    baseline = {'epoch': time.time(), 'services': current_services,
                'ext4_errors': ext4_errors(), 'diskstats': diskstats(),
                'root_mount': run(['findmnt', '-n', '-o', 'SOURCE,FSTYPE,OPTIONS', '/']).strip()}
    write_json(root / 'before.json', baseline)
    changed = False
    try:
        # Start and verify the observer before changing the configuration.
        result = subprocess.run(['systemd-run', '--quiet', '--unit=' + unit,
                                 '--property=RuntimeMaxSec=90000', '--property=UMask=0077',
                                 '/usr/bin/python3', str(root / 'observer.py'), 'observe', str(root)],
                                capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            raise RuntimeError('observer_start_failed: ' + result.stderr)
        deadline = time.monotonic() + 45
        while not (root / 'ready.json').exists():
            if time.monotonic() > deadline:
                raise RuntimeError('observer_not_ready')
            time.sleep(1)
        write_json(root / 'mutation-intent.json', {'before': sha(before), 'after': sha(after)})
        changed = True
        guarded_replace(CONFIG, before, after, metadata)
        if CONFIG.read_bytes() != after:
            raise RuntimeError('mutation_readback_failed')
        baseline.update({'epoch': time.time(), 'sha256': sha(after), 'unit': unit})
        write_json(root / 'applied.json', baseline)
        print(json.dumps({'state_directory': str(root), 'unit': unit,
                          'applied_epoch': baseline['epoch'], 'sha256': sha(after),
                          'checkpoint_seconds': [7200, 86400]}))
    except Exception:
        if changed and CONFIG.read_bytes() == after:
            guarded_replace(CONFIG, after, before, metadata, restore=True)
            write_json(root / 'apply-rollback.json', {'restored': CONFIG.read_bytes() == before})
        subprocess.run(['systemctl', 'stop', unit], capture_output=True, timeout=30)
        raise


def rollback(root):
    applied = json.loads((root / 'applied.json').read_text())
    before = (root / 'original-config').read_bytes()
    metadata = json.loads((root / 'metadata.json').read_text())
    after = before + b'collect_notemp=1\n'
    if sha(CONFIG.read_bytes()) != applied['sha256']:
        raise RuntimeError('rollback_conflict')
    guarded_replace(CONFIG, after, before, metadata, restore=True)
    write_json(root / 'rollback.json', {'epoch': time.time(), 'sha256': sha(CONFIG.read_bytes())})
    run(['systemctl', 'stop', applied['unit']])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['apply', 'observe', 'rollback'])
    parser.add_argument('path', type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    if os.geteuid() != 0:
        raise RuntimeError('root_required')
    if args.action == 'apply':
        def interrupted(signum, frame):
            raise RuntimeError('apply_interrupted')
        for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
            signal.signal(sig, interrupted)
        apply(args.path)
    elif args.action == 'rollback':
        rollback(args.path)
    else:
        try:
            observe(args.path)
        except Exception as exc:
            write_json(args.path / 'failed.json', {'epoch': time.time(), 'error': str(exc),
                       'storage_accepted': False, 'configuration_not_reenabled': True})
            raise


if __name__ == '__main__':
    main()
