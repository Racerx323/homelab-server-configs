#!/usr/bin/env python3
"""Observe patched Webmin polling; restore the temperature kill switch on exit."""
import importlib.util
import base64
import json
import os
from pathlib import Path
import re
import selectors
import signal
import stat
import subprocess
import sys
import time

spec = importlib.util.spec_from_file_location(
    'guard', Path(__file__).with_name('drive-polling-trial.py'))
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


def read(root, name):
    return json.loads((root / name).read_text())


def disable(root):
    op = read(root, 'operation.json')
    before = op['disabled_config'].encode()
    after = op['enabled_config'].encode()
    current = guard.CONFIG.read_bytes()
    if current != before:
        guard.guarded_replace(guard.CONFIG, after, before, op['config_metadata'])
    if guard.CONFIG.read_bytes() != before:
        raise RuntimeError('disable_readback_failed')
    guard.write_json(root / 'disabled.json', {'epoch': time.time(), 'sha256': guard.sha(before)})


def apply(payload_path):
    op = read(payload_path.parent, payload_path.name)
    if os.uname().nodename != op['host'] or guard.BOOT.read_text().strip() != op['boot_id']:
        raise RuntimeError('target_or_boot_mismatch')
    if not re.fullmatch(r'[a-z0-9-]{1,60}', op['id']):
        raise RuntimeError('invalid_id')
    if guard.CONFIG.read_bytes() != op['disabled_config'].encode():
        raise RuntimeError('configuration_conflict')
    if guard.run(['dpkg-query', '-W', '-f=${Version}', 'smartmontools']) != '7.4-3':
        raise RuntimeError('package_changed')
    expected_paths = {'/usr/share/webmin/smart-status/smart-status-lib.pl',
                      '/usr/share/webmin/system-status/system-status-lib.pl'}
    if {s['path'] for s in op['sources']} != expected_paths or len(op['sources']) != 2:
        raise RuntimeError('unexpected_patch_scope')
    for source in op['sources']:
        path = Path(source['path'])
        info = path.lstat()
        before, after = base64.b64decode(source['before']), base64.b64decode(source['after'])
        if path.is_symlink() or not stat.S_ISREG(info.st_mode) or path.read_bytes() != before:
            raise RuntimeError('source_conflict')
        if (info.st_uid, info.st_gid, stat.S_IMODE(info.st_mode)) != (0, 0, 0o755):
            raise RuntimeError('source_metadata_conflict')
        if guard.sha(after) != source['after_sha256']:
            raise RuntimeError('source_hash_conflict')
        source['metadata'] = {'uid': info.st_uid, 'gid': info.st_gid,
                              'mode': stat.S_IMODE(info.st_mode),
                              'atime_ns': info.st_atime_ns, 'mtime_ns': info.st_mtime_ns}
    for name, digest in op['unchanged_hashes'].items():
        if guard.sha(Path(name).read_bytes()) != digest:
            raise RuntimeError('monitoring_input_conflict')
    baseline = {'services': parse_services(guard.services()), 'ext4_errors': guard.ext4_errors(),
                'diskstats': guard.diskstats(),
                'root_mount': guard.run(['findmnt', '-n', '-o', 'SOURCE,FSTYPE,OPTIONS', '/']).strip()}
    service_check(baseline['services'], baseline['services'])
    parent = Path('/var/lib/webmin-patched-polling-trial')
    if parent.exists() and (parent.is_symlink() or parent.stat().st_uid != 0 or
                            stat.S_IMODE(parent.stat().st_mode) != 0o700):
        raise RuntimeError('untrusted_state_directory')
    parent.mkdir(mode=0o700, exist_ok=True)
    root = parent / op['id']
    root.mkdir(mode=0o700)
    guard.write_json(root / 'operation.json', op)
    guard.write_json(root / 'baseline.json', baseline)
    (root / 'original-config').write_bytes(guard.CONFIG.read_bytes())
    for name in ['patched-polling-trial.py', 'drive-polling-trial.py']:
        (root / name).write_bytes(Path(__file__).with_name(name).read_bytes())
    unit = 'webmin-patched-polling-' + op['id']
    changed = []
    try:
        for source in op['sources']:
            guard.guarded_replace(Path(source['path']), base64.b64decode(source['before']),
                                  base64.b64decode(source['after']), source['metadata'])
            changed.append(source)
        guard.write_json(root / 'patch-applied.json', {'epoch': time.time(), 'unit': unit})
        script = str(root / 'patched-polling-trial.py')
        result = subprocess.run(['systemd-run', '--quiet', '--unit=' + unit,
                                 '--property=RuntimeMaxSec=90000', '--property=UMask=0077',
                                 '--property=KillMode=mixed',
                                 '--property=ExecStopPost=/usr/bin/python3 ' + script + ' disable ' + str(root),
                                 '/usr/bin/python3', script, 'observe', str(root)],
                                capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise RuntimeError('observer_start_failed')
        deadline = time.monotonic() + 45
        while not (root / 'enabled.json').exists():
            if (root / 'failed.json').exists() or time.monotonic() > deadline:
                raise RuntimeError('observer_enable_failed')
            time.sleep(1)
        print(json.dumps({'state': str(root), 'unit': unit,
                          'enabled': read(root, 'enabled.json')}))
    except Exception:
        disable(root)
        subprocess.run(['systemctl', 'stop', unit], capture_output=True, timeout=30)
        for source in reversed(changed):
            guard.guarded_replace(Path(source['path']), base64.b64decode(source['after']),
                                  base64.b64decode(source['before']), source['metadata'], restore=True)
        guard.write_json(root / 'apply-rollback.json', {'epoch': time.time()})
        raise


def rollback(root):
    disable(root)
    unit = read(root, 'patch-applied.json')['unit']
    guard.run(['systemctl', 'stop', unit])
    for source in reversed(read(root, 'operation.json')['sources']):
        guard.guarded_replace(Path(source['path']), base64.b64decode(source['after']),
                              base64.b64decode(source['before']), source['metadata'], restore=True)
    guard.write_json(root / 'rollback.json', {'epoch': time.time(), 'polling_disabled': True})


def classify(argv):
    if argv == ['--version']:
        return 'version'
    if argv == ['-i', '/dev/sda']:
        return 'identify'
    if argv == ['-H', '/dev/sda']:
        return 'health'
    if argv == ['-A', '-l', 'error', '/dev/sda']:
        return 'attributes'
    raise RuntimeError('unexpected_smart_arguments: ' + repr(argv))


def parse_services(text):
    return {d['Id']: d for block in text.strip().split('\n\n')
            if (d := dict(line.split('=', 1) for line in block.splitlines()))}


def service_check(current, initial):
    events = []
    for name, before in initial.items():
        now = current[name]
        if now['ActiveState'] != 'active' or int(now['MainPID']) < 2:
            raise RuntimeError('monitoring_service_unavailable: ' + name)
        if now['MainPID'] != before['MainPID']:
            if name != 'munin-node.service':
                raise RuntimeError('service_identity_changed: ' + name)
            # Munin's daily log rotation intentionally restarts it. Retain its
            # identity change for review; availability is checked independently.
            events.append({'service': name, 'initial_pid': before['MainPID'],
                           'current_pid': now['MainPID'], 'review': 'restart'})
    return events


def trace_line(line, pending, counts, root):
    line = re.sub(r'^\[pid\s+(\d+)\]\s+', r'\1 ', line)
    if 'execve(' in line and re.search(r'execve\("[^"\n]*/smartctl"', line):
        if 'ENOENT' in line:
            return
        match = re.match(r'(\d+)\s+[0-9.]+\s+execve\("[^"\n]+", (\[.*?\]),', line)
        if not match or not line.rstrip().endswith('= 0'):
            raise RuntimeError('unparsed_smart_execution')
        argv = json.loads(match[2])
        kind = classify(argv[1:])
        pending[match[1]] = {'epoch': time.time(), 'kind': kind, 'argv': argv[1:]}
        with (root / 'smart-executions.jsonl').open('a') as stream:
            stream.write(json.dumps(pending[match[1]]) + '\n')
    match = re.match(r'(\d+)\s+[0-9.]+\s+exit_group\((\d+)\)', line)
    if match and match[1] in pending:
        event = pending.pop(match[1])
        event.update({'exit_epoch': time.time(), 'exit_status': int(match[2])})
        with (root / 'smart-exits.jsonl').open('a') as stream:
            stream.write(json.dumps(event) + '\n')
        if event['exit_status']:
            raise RuntimeError('smart_command_failed')
        counts[event['kind']] += 1


def sample(root, op, start, previous, baseline):
    now = time.time()
    if now - previous > 90 or now < previous - 5:
        raise RuntimeError('observation_gap')
    if guard.BOOT.read_text().strip() != op['boot_id']:
        raise RuntimeError('boot_changed')
    if guard.CONFIG.read_bytes() != op['enabled_config'].encode():
        raise RuntimeError('configuration_drift')
    for source in op['sources']:
        if guard.sha(Path(source['path']).read_bytes()) != source['after_sha256']:
            raise RuntimeError('patched_source_drift')
    for name, digest in op['unchanged_hashes'].items():
        if guard.sha(Path(name).read_bytes()) != digest:
            raise RuntimeError('monitoring_input_drift')
    svc = parse_services(guard.services())
    restarts = service_check(svc, baseline['services'])
    errors = guard.ext4_errors()
    if errors != baseline['ext4_errors']:
        raise RuntimeError('filesystem_error_counter_changed')
    mount = guard.run(['findmnt', '-n', '-o', 'SOURCE,FSTYPE,OPTIONS', '/']).strip()
    if mount != baseline['root_mount']:
        raise RuntimeError('root_mount_changed')
    log = guard.run(['journalctl', '-b', '-k', '--since=@' + str(int(start)),
                     '--grep=reset .*USB device|I/O error|Buffer I/O|EXT4-fs error|uas_eh_|device reset',
                     '--output=json', '--no-pager', '--quiet'], allowed=(0, 1))
    events = [json.loads(line) for line in log.splitlines()]
    if events:
        guard.write_json(root / 'kernel-events.json', events)
        raise RuntimeError('kernel_storage_event')
    histories = {name: guard.history(name) for name in ['load', 'diskused', 'drivetemp']}
    latest = {name: max(values, default=0) for name, values in histories.items()}
    for name in latest:
        if now - start > 900 and now - latest[name] > 900:
            raise RuntimeError('history_stale: ' + name)
    temperatures = []
    for line in (guard.HISTORY / 'drivetemp').read_text().splitlines()[-10:]:
        fields = line.lstrip('\x00').split()
        if fields and re.fullmatch(r'[0-9]{10}', fields[0]) and int(fields[0]) >= start:
            if len(fields) != 2 or not re.fullmatch(r'-?[0-9]+(?:\.[0-9]+)?', fields[1]):
                raise RuntimeError('invalid_temperature_record')
            temperatures.append({'epoch': int(fields[0]), 'celsius': float(fields[1])})
    return {'epoch': now, 'elapsed_seconds': now - start, 'services': svc,
            'service_events': restarts, 'ext4_errors': errors, 'root_mount': mount,
            'diskstats': guard.diskstats(), 'latest_history': latest,
            'temperatures': temperatures, 'collection_count': len(set(
                t for t in histories['load'] if t >= start)),
            'temperature_count': len(set(t for t in histories['drivetemp'] if t >= start))}


def observe(root):
    op = read(root, 'operation.json')
    baseline = read(root, 'baseline.json')
    pid = int(baseline['services']['webmin.service']['MainPID'])
    if guard.CONFIG.read_bytes() != op['disabled_config'].encode():
        raise RuntimeError('unexpected_initial_config')
    proc = subprocess.Popen(['/usr/bin/strace', '-f', '-ttt', '-s', '1024',
                             '-e', 'trace=execve,exit_group', '-p', str(pid)],
                            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                            start_new_session=True)
    selector = selectors.DefaultSelector()
    os.set_blocking(proc.stderr.fileno(), False)
    selector.register(proc.stderr, selectors.EVENT_READ)
    pending, counts, buffer = {}, dict.fromkeys(['version', 'identify', 'health', 'attributes'], 0), b''
    deadline, attached, start = time.monotonic() + 30, False, None
    previous = next_sample = time.time()
    checkpoints = [7200, 86400]
    try:
        while True:
            if proc.poll() is not None:
                raise RuntimeError('trace_exited')
            for key, _ in selector.select(timeout=1):
                chunk = os.read(key.fd, 65536)
                if not chunk:
                    raise RuntimeError('trace_eof')
                buffer += chunk
                if len(buffer) > 1_000_000:
                    raise RuntimeError('trace_output_limit')
                while b'\n' in buffer:
                    raw, buffer = buffer.split(b'\n', 1)
                    line = raw.decode(errors='replace')
                    if 'attached' in line:
                        attached = True
                    if 'Operation not permitted' in line or 'ptrace:' in line:
                        raise RuntimeError('trace_attach_failed')
                    trace_line(line, pending, counts, root)
            if not attached and time.monotonic() > deadline:
                raise RuntimeError('trace_not_attached')
            if attached and start is None:
                # The observer owns enablement, so polling cannot start before
                # the trace and stop-on-failure path are ready.
                guard.guarded_replace(guard.CONFIG, op['disabled_config'].encode(),
                                      op['enabled_config'].encode(), op['config_metadata'])
                start = time.time()
                previous = next_sample = start
                guard.write_json(root / 'enabled.json', {'epoch': start,
                                 'sha256': guard.sha(guard.CONFIG.read_bytes())})
            now = time.time()
            if any(now - e['epoch'] > 60 for e in pending.values()):
                raise RuntimeError('smart_command_timeout')
            if start is not None and now >= next_sample:
                value = sample(root, op, start, previous, baseline)
                value['successful_commands'] = counts.copy()
                value['trace_attached'] = attached
                with (root / 'samples.jsonl').open('a') as stream:
                    stream.write(json.dumps(value) + '\n')
                guard.write_json(root / 'latest.json', value)
                previous, next_sample = now, now + 15
                elapsed = now - start
                if checkpoints and elapsed >= checkpoints[0]:
                    checkpoint = checkpoints.pop(0)
                    required = int(elapsed / 300) - 2
                    if min(value['collection_count'], value['temperature_count'],
                           counts['attributes'], counts['health']) < required:
                        raise RuntimeError('insufficient_verified_cycles')
                    guard.write_json(root / ('checkpoint-' + str(checkpoint) + '.json'),
                                     dict(value, result='quiet', storage_accepted=False))
                if not checkpoints:
                    guard.write_json(root / 'complete.json', {'epoch': now,
                                     'result': 'quiet', 'storage_accepted': False})
                    break
    finally:
        try:
            disable(root)
        finally:
            if proc.poll() is None:
                proc.send_signal(signal.SIGINT)
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=10)
            guard.write_json(root / 'trace-result.json', {'epoch': time.time(),
                             'counts': counts, 'pending': pending, 'attached': attached})


def main():
    os.umask(0o077)
    action, state = sys.argv[1:]
    root = Path(state)
    if os.geteuid() != 0:
        raise RuntimeError('root_required')
    if action == 'apply':
        apply(root)
        return
    if action == 'rollback':
        rollback(root)
        return
    if action == 'disable':
        disable(root)
        return
    if action != 'observe':
        raise RuntimeError('invalid_action')
    def interrupted(signum, frame):
        raise RuntimeError('observer_interrupted')
    for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, interrupted)
    try:
        observe(root)
    except Exception as exc:
        guard.write_json(root / 'failed.json', {'epoch': time.time(), 'reason': str(exc),
                         'storage_accepted': False})
        raise


if __name__ == '__main__':
    main()
