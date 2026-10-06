#!/usr/bin/env python3
"""Single-check candidate admission; requires a separately approved frozen bundle."""
import importlib.util
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


def load_helpers(path):
    spec = importlib.util.spec_from_file_location('comparison_helpers', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validate_config(path):
    lines = [line.strip() for line in path.read_text().splitlines()
             if line.strip() and not line.lstrip().startswith('#')]
    if lines != ['/dev/sda -d sntjmicron -l selftest']:
        raise ValueError('unreviewed_config')


def argv_for(root):
    return [str(root/'smartd'), '-d', '-q', 'onecheck',
            '-c', str(root/'smartd.conf'), '-B', str(root/'empty.drivedb'),
            '-s', str(root/'state')+'/', '-A', str(root/'attributes')+'/',
            '-j', str(root/'json')+'/', '-p', str(root/'candidate.pid'),
            '-r', 'nvmeioctl,2']


def run_candidate(argv, directory, seconds=60, limit=4*1024*1024):
    """Capture partial output and kill only the owned process group on a bound."""
    result = {'exit_status': None, 'failure': None, 'candidate_exited': False}
    env = {'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LC_ALL': 'C',
           'HOME': str(directory), 'TMPDIR': str(directory)}
    started = time.monotonic()
    with (directory/'stdout').open('xb') as out, (directory/'stderr').open('xb') as err:
        process = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, start_new_session=True, env=env,
                                   cwd=directory)
        result['pid'] = process.pid
        selector = selectors.DefaultSelector()
        sizes = {process.stdout: 0, process.stderr: 0}
        for pipe, output in ((process.stdout, out), (process.stderr, err)):
            selector.register(pipe, selectors.EVENT_READ, output)
        try:
            while selector.get_map() or process.poll() is None:
                if time.monotonic() - started >= seconds:
                    raise TimeoutError('candidate_deadline')
                for key, _ in selector.select(.1):
                    part = os.read(key.fileobj.fileno(), 65536)
                    if not part:
                        selector.unregister(key.fileobj)
                        continue
                    remaining = limit - sizes[key.fileobj]
                    key.data.write(part[:remaining])
                    sizes[key.fileobj] += len(part)
                    if sizes[key.fileobj] > limit:
                        raise ValueError('candidate_output_limit')
            result['exit_status'] = process.wait(timeout=2)
        except BaseException as exc:
            result['failure'] = type(exc).__name__ + ':' + str(exc)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
            try:
                result['exit_status'] = process.wait(timeout=5)
                result['candidate_exited'] = True
            except subprocess.TimeoutExpired:
                result['failure'] = 'candidate_exit_unconfirmed_manual_intervention'
            selector.close()
            process.stdout.close()
            process.stderr.close()
    result['elapsed_seconds'] = time.monotonic() - started
    return result


def counters():
    return {'ioerr_cnt': Path('/sys/block/sda/device/ioerr_cnt').read_text().strip(),
            'ext4_errors': Path('/sys/fs/ext4/sda2/errors_count').read_text().strip()}


def preflight(h, baseline, now=None):
    now = time.time() if now is None else now
    if not 0 <= now - baseline['epoch'] <= 3600:
        raise ValueError('baseline_expired')
    if os.uname().nodename != 'j2-svpi4mf' or os.uname().machine != 'aarch64':
        raise ValueError('host_identity')
    if Path('/proc/sys/kernel/random/boot_id').read_text().strip() != baseline['boot_id']:
        raise ValueError('boot_changed')
    if h.config_identity() != baseline['hashes']:
        raise ValueError('production_identity_changed')
    services = h.checked(['systemctl', 'show', 'smartmontools.service', 'webmin.service',
                         '--property=Id,ActiveState,InvocationID,NRestarts,MainPID'])
    if services != baseline['services']['stdout'] or services.count('ActiveState=active') != 2:
        raise ValueError('service_identity_changed')
    h.observer_inactive()
    root = json.loads(h.checked(['findmnt', '-J', '/']))['filesystems'][0]
    if root['source'] != '/dev/sda2' or root['fstype'] != 'ext4':
        raise ValueError('root_device_changed')
    p = Path('/sys/class/block/sda/device').resolve()
    ancestry = [p, *p.parents]
    if h.bridge_descriptor(ancestry)['bcdDevice'] != '0213':
        raise ValueError('descriptor_changed')
    if not any((p/'driver').exists() and (p/'driver').resolve().name == 'usb-storage' for p in ancestry):
        raise ValueError('transport_changed')
    if h.checked(['dpkg-query', '-W', '-f=${Version}', 'smartmontools']) != '7.5-2~bpo13+1':
        raise ValueError('package_changed')
    if counters() != {k: baseline[k] for k in ('ioerr_cnt', 'ext4_errors')}:
        raise ValueError('counter_changed')
    for args in (['systemctl', '--failed', '--no-legend', '--no-pager'],
                 ['systemctl', 'list-jobs', '--no-legend', '--no-pager']):
        if h.checked(args).strip():
            raise ValueError('host_jobs_or_failures')
    # Ordinary production smartd remains active; refuse a second candidate or
    # visible maintenance process rather than stopping anything.
    procs = h.checked(['ps', '-eo', 'comm=']).splitlines()
    if procs.count('smartd') != 1 or any(re.fullmatch(
            r'(apt|apt-get|dpkg|restic|parted|fio|badblocks|fsck.*|ansible.*)', p.strip()) for p in procs):
        raise ValueError('concurrent_maintenance')


def assess(result, text, state_text):
    """Admission requires log evidence as well as a normal, unsignalled exit."""
    if (result['failure'] or not result['candidate_exited'] or result['exit_status'] != 0
            or 'All devices successfully checked once.' not in text
            or 'Adding to "monitor" list.' not in text
            or 'NVMe' not in text
            or re.search(r'failed|ignoring|does not support|error count increased', text, re.I)
            or not state_text.startswith('# smartd state file\n')):
        return False
    # The pinned writer omits zero values. Missing key in a valid state file
    # therefore means zero; a missing file is never interpreted as zero.
    values = re.findall(r'^self-test-errors\s*=\s*(\d+)\s*$', state_text, re.M)
    if values not in ([], ['0']):
        return False
    # Transport decoding and returned self-test-log buffers still need human review.
    return True


def main(directory):
    os.umask(0o077)
    root = Path(directory).resolve()
    if os.geteuid() != 0 or root.is_symlink() or root.stat().st_uid != 0 or stat.S_IMODE(root.stat().st_mode) != 0o700:
        raise ValueError('private_root_required')
    h = load_helpers(root/'compare-ci-smartctl.py')
    spec = json.loads((root/'specification.json').read_text())
    for name, expected in spec['inputs'].items():
        path = root/name
        if '/' in name or path.is_symlink() or not path.is_file() or h.digest(path) != expected:
            raise ValueError('input_identity')
    validate_config(root/'smartd.conf')
    baseline = json.loads((root/'baseline.json').read_text())
    preflight(h, baseline)
    if time.time() - baseline['epoch'] > 3300:
        raise ValueError('insufficient_baseline_window')
    evidence = root/'evidence'
    evidence.mkdir(mode=0o700)  # Existing evidence refuses a retry.
    for name in ('state', 'attributes', 'json'):
        (root/name).mkdir(mode=0o700)
    code, out, err = h.run([str(root/'smartd'), '--version'])
    (evidence/'version').write_bytes(out + err)
    if code or err or b'06489e03695e' not in out:
        raise ValueError('candidate_version')
    token = h.cursor()
    before = counters()
    result = {'completed': False, 'accepted': False, 'before': before,
              'journal_cursor': token, 'argv': argv_for(root)}
    try:
        result['candidate'] = run_candidate(result['argv'], evidence)
        returned = time.monotonic()
        try:
            result['immediate'] = counters()
        finally:
            # Observe even if the immediate counter read itself fails.
            while time.monotonic() - returned < 75:
                time.sleep(max(0, min(5, 75 - (time.monotonic() - returned))))
        result['post_exit_observation_seconds'] = time.monotonic() - returned
        result['settled'] = counters()
        kernel, fault = h.storage_since(token)
        (evidence/'kernel.jsonl').write_text(kernel)
        result['kernel_fault'] = fault
        preflight(h, baseline)
        states = list((root/'state').glob('*.nvme.state'))
        state_text = states[0].read_text() if len(states) == 1 else ''
        text = (evidence/'stdout').read_text() + (evidence/'stderr').read_text()
        result['admission_checks_passed'] = (
            assess(result['candidate'], text, state_text) and not fault
            and before == result['immediate'] == result['settled'])
        result['completed'] = True
        result['review_required'] = 'Verify actual self-test-log transactions and interpreted state; no automatic acceptance'
    except BaseException as exc:
        result['failure'] = type(exc).__name__ + ':' + str(exc)
        raise
    finally:
        (evidence/'result.json').write_text(json.dumps(result, indent=2)+'\n')
    return 0 if result.get('admission_checks_passed') else 2


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1]))
