#!/usr/bin/env python3
"""Bounded repeated-check supervisor, launched by smartd-observation-control."""
import ctypes
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import time


def argv_for(root):
    root = Path(root)
    return [str(root/'smartd'), '-d', '-q', 'errors', '-i', '1800',
            '-c', str(root/'smartd.conf'), '-B', str(root/'empty.drivedb'),
            '-s', str(root/'state')+'/', '-A', str(root/'attributes')+'/',
            '-j', str(root/'json')+'/', '-r', 'nvmeioctl,2']


def parent_death_guard(parent):
    # Linux PR_SET_PDEATHSIG: kill the foreground candidate if its supervisor
    # dies. The parent identity check closes the fork-to-prctl race.
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(1, signal.SIGKILL, 0, 0, 0) != 0:
        raise OSError(ctypes.get_errno(), 'PR_SET_PDEATHSIG')
    if os.getppid() != parent:
        os.kill(os.getpid(), signal.SIGKILL)


class Transactions:
    """Track completed monitoring reads, excluding the registration read."""
    def __init__(self):
        self.pending = ''
        self.call_started = None
        self.selftest = False
        self.monitoring = False
        self.completed = 0
        self.last_completed = None

    def feed(self, data, now):
        self.pending += data.decode('utf-8', errors='replace')
        while '\n' in self.pending:
            line, self.pending = self.pending.split('\n', 1)
            if len(line) > 4096:
                raise ValueError('diagnostic_line_limit')
            if re.search(r'failed|ignoring|does not support|error count (increased|decreased)', line, re.I):
                raise ValueError('candidate_warning_or_failure')
            if 'Monitoring 0 ATA/SATA, 0 SCSI/SAS and 1 NVMe devices' in line:
                self.monitoring = True
            if '[NVMe call:' in line:
                if self.call_started is not None:
                    raise ValueError('missing_transaction_result')
                match = re.search(r'opcode=(0x[0-9a-f]+).*cdw10=(0x[0-9a-f]+)', line)
                if not match or match.groups() not in {
                        ('0x06', '0x00000001'), ('0x02', '0x007f0002'), ('0x02', '0x008c0006')}:
                    raise ValueError('unexpected_device_command')
                self.call_started = now
                self.selftest = match.group(2) == '0x008c0006'
            if 'NVMe call succeeded:' in line:
                if self.call_started is None or 'result=0x00000000' not in line:
                    raise ValueError('unexpected_transaction_result')
                if self.monitoring and self.selftest:
                    self.completed += 1
                    self.last_completed = now
                self.call_started = None
                self.selftest = False
        if len(self.pending) > 4096:
            raise ValueError('diagnostic_line_limit')

    def deadline(self, now, started, command_seconds, gap_seconds):
        if self.call_started is not None and now - self.call_started > command_seconds:
            raise TimeoutError('device_command_deadline')
        if self.last_completed is None:
            if now - started > command_seconds:
                raise TimeoutError('first_check_deadline')
        elif now - self.last_completed > gap_seconds:
            raise TimeoutError('check_gap')


def supervise(argv, directory, audit, *, duration=172800, minimum_checks=96,
              command_seconds=60, gap_seconds=1920, audit_seconds=15,
              settle_seconds=75, limit=16777216):
    """Own one process, bounded diagnostics, periodic audits and final settling.

    The launcher must validate inputs and supply an independent audit
    callback that raises on counter, kernel, identity or observer drift. This
    core deliberately has no live CLI or implicit target access.
    """
    directory = Path(directory)
    tracker = Transactions()
    result = {'accepted': False, 'completed': False, 'failure': None,
              'candidate_exited': False}
    env = {'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LC_ALL': 'C',
           'HOME': str(directory), 'TMPDIR': str(directory)}
    audit()
    parent = os.getpid()
    with (directory/'stdout').open('xb') as out, (directory/'stderr').open('xb') as err:
        process = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, cwd=directory, env=env,
                                   start_new_session=True,
                                   preexec_fn=lambda: parent_death_guard(parent))
        started = time.monotonic()
        next_audit = started + audit_seconds
        selector = selectors.DefaultSelector()
        sizes = {process.stdout: 0, process.stderr: 0}
        for pipe, output in ((process.stdout, out), (process.stderr, err)):
            selector.register(pipe, selectors.EVENT_READ, output)
        try:
            while time.monotonic() - started < duration:
                now = time.monotonic()
                if process.poll() is not None:
                    raise ValueError('early_candidate_exit')
                tracker.deadline(now, started, command_seconds, gap_seconds)
                if now >= next_audit:
                    audit()
                    next_audit = time.monotonic() + audit_seconds
                    snapshot = {'pid': process.pid, 'elapsed_seconds': now-started,
                                'completed_checks': tracker.completed}
                    temp = directory/'progress.json.tmp'
                    temp.write_text(json.dumps(snapshot)+'\n')
                    temp.replace(directory/'progress.json')
                for key, _ in selector.select(.05):
                    data = os.read(key.fileobj.fileno(), 65536)
                    if not data:
                        selector.unregister(key.fileobj)
                        continue
                    remaining = limit - sizes[key.fileobj]
                    key.data.write(data[:remaining])
                    sizes[key.fileobj] += len(data)
                    if sizes[key.fileobj] > limit:
                        raise ValueError('output_limit')
                    if key.fileobj is process.stdout:
                        tracker.feed(data, time.monotonic())
                    elif data.strip():
                        raise ValueError('unexpected_stderr')
            if tracker.call_started is not None or tracker.completed < minimum_checks:
                raise ValueError('insufficient_complete_checks')
            result['completed'] = True
        except BaseException as exc:
            result['failure'] = type(exc).__name__ + ':' + str(exc)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
            # Continue draining exit-time output; do not lose state-write errors.
            end = time.monotonic() + 10
            try:
                while selector.get_map() and time.monotonic() < end:
                    for key, _ in selector.select(.05):
                        data = os.read(key.fileobj.fileno(), 65536)
                        if not data:
                            selector.unregister(key.fileobj)
                            continue
                        remaining = limit - sizes[key.fileobj]
                        key.data.write(data[:max(0, remaining)])
                        sizes[key.fileobj] += len(data)
                        if sizes[key.fileobj] > limit:
                            raise ValueError('exit_output_limit')
                        if key.fileobj is process.stdout:
                            tracker.feed(data, time.monotonic())
                        elif data.strip():
                            raise ValueError('exit_stderr')
            except Exception as exc:
                result['failure'] = str(exc)
            if process.poll() is None:
                try:
                    process.wait(timeout=max(.01, end-time.monotonic()))
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    result['failure'] = 'forced_candidate_kill'
            try:
                result['candidate_exit_status'] = process.wait(timeout=5)
                result['candidate_exited'] = True
            except subprocess.TimeoutExpired:
                result['failure'] = 'candidate_exit_unconfirmed'
            selector.close()
            process.stdout.close()
            process.stderr.close()
            returned = time.monotonic()
            while time.monotonic() - returned < settle_seconds:
                time.sleep(max(0, min(.25, settle_seconds-(time.monotonic()-returned))))
            try:
                audit()
            except Exception as exc:
                result['failure'] = 'post_exit_audit:' + str(exc)
            result['post_exit_observation_seconds'] = time.monotonic()-returned
            result['completed_checks'] = tracker.completed
            result['elapsed_seconds'] = time.monotonic()-started
            if result['failure'] or not result['candidate_exited'] or result.get('candidate_exit_status') != 0:
                result['completed'] = False
            result['review_required'] = True
            (directory/'result.json').write_text(json.dumps(result, indent=2)+'\n')
    return result
