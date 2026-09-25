#!/usr/bin/env python3
"""Bounded standalone smartctl comparison; run only with the reviewed bundle."""
import hashlib
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

FLAGS = ['invocation', 'device_open', 'smart_command', 'health',
         'prefail_current', 'prefail_historical', 'error_log', 'selftest_log']
PATTERN = r'reset.*USB|USB.*(?:reset|disconnect)|I/O error|Buffer I/O|EXT4-fs (?:error|warning)|uas_eh|device offline|timing out command|blk_update_request|out of memory|oom-kill'


def exit_bits(code):
    return [name for bit, name in enumerate(FLAGS) if code & (1 << bit)] if 0 <= code <= 255 else ['signal_or_timeout']


def run(argv, seconds=40):
    process = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    streams = {process.stdout: bytearray(), process.stderr: bytearray()}
    selector = selectors.DefaultSelector()
    for pipe in streams:
        selector.register(pipe, selectors.EVENT_READ)
    started = time.monotonic()
    try:
        while selector.get_map():
            if time.monotonic() - started >= seconds:
                raise TimeoutError('command_deadline')
            for key, _ in selector.select(.2):
                part = os.read(key.fileobj.fileno(), 65536)
                if not part:
                    selector.unregister(key.fileobj)
                else:
                    streams[key.fileobj].extend(part)
                    if len(streams[key.fileobj]) >= 4194304:
                        raise ValueError('output_limit')
        return process.wait(timeout=2), bytes(streams[process.stdout]), bytes(streams[process.stderr])
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        selector.close()
        process.stdout.close()
        process.stderr.close()


def checked(argv):
    code, out, _ = run(argv)
    if code:
        raise ValueError('preflight_command_failed')
    return out.decode()


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def config_identity():
    paths = ['/usr/sbin/smartctl', '/usr/sbin/smartd', '/etc/smartd.conf',
             '/etc/webmin/system-status/config']
    return {p: digest(p) for p in paths}


def service_identity():
    return checked(['systemctl', 'show', 'smartmontools.service', 'webmin.service',
                    '--property=Id,ActiveState,InvocationID,NRestarts'])


def cursor():
    raw = checked(['journalctl', '-n', '0', '--show-cursor', '--no-pager'])
    values = [x.removeprefix('-- cursor: ') for x in raw.splitlines() if x.startswith('-- cursor: ')]
    if len(values) != 1:
        raise ValueError('cursor_missing')
    return values[0]


def storage_since(token):
    args = ['journalctl', '--no-pager', '--quiet', '-o', 'json']
    first = [json.loads(x) for x in checked(args + ['--cursor', token, '-n', '+1']).splitlines()]
    if len(first) != 1 or first[0].get('__CURSOR') != token:
        raise ValueError('cursor_coverage_missing')
    raw = checked(args + ['--after-cursor', token, '_TRANSPORT=kernel'])
    rows = [json.loads(x) for x in raw.splitlines()]
    return raw, any(re.search(PATTERN, x.get('MESSAGE', ''), re.I) for x in rows)


def query_argv(binary, device_type='sntjmicron', attribution=False):
    if device_type not in ('sntjmicron', 'sat/sntjmicron'):
        raise ValueError('unreviewed_device_type')
    return [binary, '-d', device_type, '-r', 'ioctl,2' if attribution else 'nvmeioctl,2',
            '-q', 'noserial', '-l', 'selftest', '/dev/sda']


def query_plan(spec, candidate):
    mode = spec.get('comparison_mode', 'installed_vs_candidate')
    if (spec['queries'] != (2 if mode == 'candidate_detection_attribution' else 6) or spec['observation_after_each_seconds'] != 75
            or spec['maximum_trial_seconds'] != 900
            or spec['production_package_or_configuration_changes'] is not False
            or spec['self_test_start'] is not False):
        raise ValueError('unreviewed_trial_scope')
    if mode in ('candidate_device_types', 'candidate_detection_attribution'):
        if spec.get('expected_bcd_device') != '0213':
            raise ValueError('unreviewed_bridge_revision')
        return [('candidate-explicit', str(candidate), 'sntjmicron'),
                ('candidate-combined', str(candidate), 'sat/sntjmicron')] * (1 if mode == 'candidate_detection_attribution' else 3)
    if mode != 'installed_vs_candidate':
        raise ValueError('unreviewed_comparison_mode')
    return [('installed', '/usr/sbin/smartctl', 'sntjmicron'),
            ('candidate', str(candidate), 'sntjmicron')] * 3


def bridge_descriptor(ancestry):
    matches = [p for p in ancestry if (p/'idVendor').exists()
               and (p/'idVendor').read_text().strip() == '152d'
               and (p/'idProduct').read_text().strip() == '0583']
    if len(matches) != 1:
        raise ValueError('bridge_changed')
    value = (matches[0]/'bcdDevice').read_text().strip().lower()
    if not re.fullmatch(r'[0-9a-f]{4}', value):
        raise ValueError('bridge_revision_invalid')
    return {'idVendor': '152d', 'idProduct': '0583', 'bcdDevice': value}


def require_continue(code, storage_event, unchanged):
    if storage_event or not unchanged or code != 0:
        raise ValueError('stop_further_queries')


def main(bundle):
    os.umask(0o077)
    def deadline(*_):
        raise TimeoutError("trial_deadline")
    signal.signal(signal.SIGALRM, deadline)
    signal.alarm(900)
    if os.geteuid() != 0:
        raise ValueError('root_required')
    bundle = Path(bundle).resolve()
    spec = json.loads((bundle / 'specification.json').read_text())
    candidate = bundle / 'smartctl'
    plan = query_plan(spec, candidate)
    if not stat.S_ISREG(candidate.lstat().st_mode) or candidate.is_symlink() or digest(candidate) != spec['candidate_sha256']:
        raise ValueError('candidate_identity')
    if checked(['hostname']).strip() != spec['host'] or os.uname().machine != 'aarch64':
        raise ValueError('target_identity')
    root = json.loads(checked(['findmnt', '-J', '/']))['filesystems'][0]
    if root['source'] != '/dev/sda2' or root['fstype'] != 'ext4':
        raise ValueError('root_device_changed')
    device = Path('/sys/class/block/sda/device').resolve()
    ancestry = [device, *device.parents]
    descriptor = bridge_descriptor(ancestry)
    if spec.get('expected_bcd_device') and descriptor['bcdDevice'] != spec['expected_bcd_device']:
        raise ValueError('bridge_revision_changed')
    if not any((p/'driver').exists() and (p/'driver').resolve().name == 'usb-storage' for p in ancestry):
        raise ValueError('transport_changed')
    if checked(['dpkg-query', '-W', '-f=${Version}', 'smartmontools']).strip() != spec['installed_package']:
        raise ValueError('installed_package_changed')
    if checked(['systemctl', '--failed', '--no-legend', '--no-pager']).strip():
        raise ValueError('failed_host_units')
    evidence = bundle / 'evidence'
    evidence.mkdir(mode=0o700)  # Refuse replay into existing evidence.
    before = config_identity()
    services = service_identity()
    boot = Path('/proc/sys/kernel/random/boot_id').read_text()
    result = {'completed': False, 'queries': [], 'config_before': before,
              'services_before': services, 'boot_id': boot.strip(), 'scope': 'smartctl_only',
              'bridge_descriptor': descriptor, 'comparison_mode': spec.get('comparison_mode', 'installed_vs_candidate')}
    try:
        for label, binary in [('installed', '/usr/sbin/smartctl'), ('candidate', str(candidate))]:
            code, out, err = run([binary, '--version'])
            (evidence/(label+'-version.txt')).write_bytes(out)
            if code or err:
                raise ValueError('version_read_failed')
            if label == 'candidate' and b'06489e03695e' not in out:
                raise ValueError('candidate_version_mismatch')
        trial_cursor = cursor()
        (evidence/'bridge-descriptor.json').write_text(json.dumps(descriptor, indent=2)+'\n')
        for number, (label, binary, device_type) in enumerate(plan, 1):
            token = cursor()
            prefix = f'{number:02d}-{label}'
            argv = query_argv(binary, device_type, spec.get('comparison_mode') == 'candidate_detection_attribution')
            row = {'number': number, 'binary': label, 'device_type': device_type, 'started_epoch': time.time(),
                   'scsi_ioerr_before': Path('/sys/block/sda/device/ioerr_cnt').read_text().strip(),
                   'ext4_before': Path('/sys/fs/ext4/sda2/errors_count').read_text().strip()}
            result['queries'].append(row)
            code = -1
            try:
                code, out, err = run(argv)
                row['returned_epoch'] = time.time()
                row['scsi_ioerr_at_return'] = Path('/sys/block/sda/device/ioerr_cnt').read_text().strip()
                (evidence/(prefix+'.stdout')).write_bytes(out)
                (evidence/(prefix+'.stderr')).write_bytes(err)
                row.update(exit_status=code, exit_bits=exit_bits(code))
            except (TimeoutError, ValueError) as exc:
                row['capture_error'] = str(exc)
            finally:
                returned = time.monotonic()
                time.sleep(75)
                row['post_return_seconds'] = time.monotonic() - returned
                raw, event = storage_since(token)
                (evidence/(prefix+'-kernel.jsonl')).write_text(raw)
                row['storage_event'] = event
            unchanged = (boot == Path('/proc/sys/kernel/random/boot_id').read_text()
                         and before == config_identity() and services == service_identity())
            row['scsi_ioerr_after'] = Path('/sys/block/sda/device/ioerr_cnt').read_text().strip()
            row['ext4_after'] = Path('/sys/fs/ext4/sda2/errors_count').read_text().strip()
            unchanged = unchanged and row['ext4_before'] == row['ext4_after']
            row['continuity'] = unchanged
            (evidence/'result.json').write_text(json.dumps(result, indent=2)+'\n')
            require_continue(code, event, unchanged)
        raw, event = storage_since(trial_cursor)
        (evidence/'all-kernel.jsonl').write_text(raw)
        if event:
            raise ValueError('storage_event')
        result['completed'] = True
    except Exception as exc:
        result['failure'] = type(exc).__name__ + ':' + str(exc)
        raise
    finally:
        result['config_after'] = config_identity()
        result['services_after'] = service_identity()
        (evidence/'result.json').write_text(json.dumps(result, indent=2)+'\n')
    # Raw traces stay in the protected evidence directory, not terminal output.
    print(json.dumps({'completed': True, 'queries': len(result['queries'])}))


if __name__ == '__main__':
    main(sys.argv[1])
