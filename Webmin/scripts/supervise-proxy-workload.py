#!/usr/bin/env python3
"""Supervise only the browser/scan overlap inside the existing owner trial.

No publisher, backend mutation or credentials in receipts. The parent owns Caddy
and backend recovery; this helper owns its child processes and workload evidence.
"""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import time
import tempfile


def private(path, maximum=8 * 1024 * 1024):
    info = path.lstat()
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or
            stat.S_IMODE(info.st_mode) != 0o600 or info.st_size > maximum or
            any(p.is_symlink() for p in (path, *path.parents))):
        raise ValueError('private_file_required')
    return path.read_text()


def atomic_text(path, content):
    fd, temporary = tempfile.mkstemp(prefix='.trial-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream: stream.write(content)
        os.link(temporary, path)  # Exclusive publication of a complete receipt.
    finally:
        os.unlink(temporary)


def write(path, value):
    atomic_text(path, json.dumps(value) + '\n')


def control(directory, action, token):
    """Root-side liveness/gate only; no additional resource sampler."""
    if os.geteuid() != 0 or not re.fullmatch(r'/run/needrestart-acceptance-[a-z0-9]{16,64}', str(directory)):
        raise ValueError('control_directory')
    if not re.fullmatch(r'[0-9a-f]{64}', token):
        raise ValueError('control_token')
    result = {'host_monotonic_seconds': time.monotonic(), 'boot_id': Path('/proc/sys/kernel/random/boot_id').read_text().strip(), 'token': token, 'ready': False, 'failed': False}
    if not directory.exists():
        if action != 'state': raise ValueError('control_directory_absent')
        return result
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o700 or directory.is_symlink():
        raise ValueError('control_directory_metadata')
    if action in ('ready', 'cancel'):
        name = 'workload-ready.json' if action == 'ready' else 'workload-cancelled.json'
        if action == 'ready' and not (directory / 'trial-ready.json').exists():
            raise ValueError('observer_not_ready')
        write(directory / name, {'token': token})
    result['ready'] = (directory / 'trial-ready.json').exists()
    receipt = directory / 'observation.json'
    if receipt.exists():
        # Atomic publication by the observer prevents reading a half-written row.
        row = json.loads(private(receipt))
        result['failed'] = any(k in row for k in ('error', 'cleanup_error', 'sampling_error'))
    return result


def rows(path):
    return [json.loads(line) for line in private(path).splitlines()]


def accept(browser, samples, summary, observation, clocks, token):
    if not summary['resource_scan_accepted'] or not observation['accepted']:
        raise ValueError('resource_acceptance_missing')
    if summary['profile'].get('workload_token') != token:
        raise ValueError('resource_token_mismatch')
    if not browser or any(r.get('token') != token for r in browser):
        raise ValueError('browser_token_mismatch')
    ids = {'a-ipv4', 'a-ipv6', 'b-ipv4', 'b-ipv6', 'vip-ipv4', 'vip-ipv6'}
    if {r['id'] for r in browser if r['kind'] == 'path-complete' and r.get('logout') and r.get('old_session_denied')} != ids:
        raise ValueError('browser_paths_incomplete')
    paths = [r for r in browser if r['kind'] == 'path']
    if {r['id'] for r in paths} != ids or any(not r['trusted_tls'] or not r['login'] or r['port'] != 443 or r['statistics_frames'] < 1 for r in paths):
        raise ValueError('browser_path_acceptance')
    if not any(r['kind'] == 'accepted' for r in browser) or not any(r['kind'] == 'cleanup' and r.get('passed') for r in browser):
        raise ValueError('browser_or_cleanup_failed')
    if any(r['kind'] == 'failed' for r in browser):
        raise ValueError('browser_failed')
    active = {}
    for identity in ids:
        events = [r for r in browser if r['kind'] == 'active' and r['id'] == identity]
        times = [r['monotonic_seconds'] for r in events]
        if len(times) < 2 or times[-1] - times[0] < 94 or any(not 0 < b-a <= 1.5 for a, b in zip(times, times[1:])):
            raise ValueError('browser_continuity')
        ends = [r['monotonic_seconds'] for r in browser if r['kind'] == 'workload-end' and r['id'] == identity]
        if len(ends) != 1 or ends[0] - times[0] < 95 or not 0 < ends[0] - times[-1] <= 1.5:
            raise ValueError('browser_duration')
        if identity in ('a-ipv4', 'b-ipv6'):
            active[identity] = (times[0], times[-1])
    if not clocks or any(c.get('token') != token for c in clocks) or len({c.get('boot_id') for c in clocks}) != 1 or not clocks[0].get('boot_id'):
        raise ValueError('clock_identity_mismatch')
    running = [r for r in samples if r['phase'] == 'scan' and int(r.get('scan_state', {}).get('MainPID', '0')) > 0]
    if not running: raise ValueError('no_running_scan_sample')
    # Host and workstation monotonic clocks are unrelated. Use ordering brackets,
    # not wall-clock equality or an assumed NTP offset, for every running sample.
    for row in running:
        stamp = row['monotonic_seconds']
        before = [c for c in clocks if c['host_monotonic_seconds'] <= stamp]
        after = [c for c in clocks if c['host_monotonic_seconds'] >= stamp]
        if not before or not after: raise ValueError('clock_bracket_missing')
        left, right = before[-1], after[0]
        lo, hi = left['controller_begin'], right['controller_end']
        if not 0 <= hi-lo <= 6: raise ValueError('clock_bracket_too_wide')
        if any(not start <= lo <= hi <= end for start, end in active.values()):
            raise ValueError('scan_outside_paired_browser_interval')
    return {'accepted': True, 'running_scan_samples_with_paired_browser': len(running)}


def stop_owned(child, grace=15):
    """Give the owned client time to close pages/logout; bound the process group."""
    if child is None: return {'started': False, 'group_gone': True}
    if child.poll() is None:
        child.terminate()
        try: child.wait(timeout=grace)
        except subprocess.TimeoutExpired: pass
    forced = False
    try:
        os.killpg(child.pid, 0)
        os.killpg(child.pid, signal.SIGKILL); forced = True
    except ProcessLookupError: pass
    child.wait(timeout=5)
    return {'exit': child.returncode, 'forced': forced, 'group_gone': not forced}


def supervise(spec, credentials):
    directory = Path(spec['evidence_directory'])
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700 or directory.is_symlink():
        raise ValueError('evidence_directory')
    token = spec['token']
    if not re.fullmatch(r'[0-9a-f]{64}', token): raise ValueError('operation_token')
    for key in ('observer_argv', 'state_argv', 'ready_argv', 'cancel_argv', 'browser_argv'):
        if not isinstance(spec[key], list) or not spec[key] or not spec[key][0].startswith('/') or any(not isinstance(x, str) or '\x00' in x for x in spec[key]):
            raise ValueError('exact_owner_argv_required')
    for key in ('browser_receipt', 'samples', 'summary', 'observation'):
        if Path(spec[key]).exists() or Path(spec[key]).is_symlink(): raise ValueError('reused_output')
    result = {'accepted': False}; observer = browser = None; clocks = []; files = []
    def interrupted(signum, frame):
        raise InterruptedError('parent signal')
    previous_signals = {sig: signal.signal(sig, interrupted) for sig in (signal.SIGTERM, signal.SIGINT)}
    started = time.monotonic(); gate_sent = False; normal_observer = False
    def remote(key):
        begin = time.monotonic()
        run = subprocess.run(spec[key], input=Path(__file__).read_text(), capture_output=True, text=True, timeout=4)
        if run.returncode or len(run.stdout) > 4096:
            write(directory / 'control-failure.json', {'action': key, 'expected_exit': 0, 'observed_exit': run.returncode,
                  'stdout_bytes': len(run.stdout.encode()), 'stderr_excerpt': ''.join(c for c in run.stderr[:1024] if c in '\n\t' or 32 <= ord(c) < 127)})
            raise ValueError('control_' + key + '_failed')
        row = json.loads(run.stdout)
        row.update(controller_begin=begin, controller_end=time.monotonic())
        clocks.append(row)
        return row
    def launch(key):
        out = (directory / (key + '.stdout')).open('x'); err = (directory / (key + '.stderr')).open('x')
        files.extend([out, err])
        return subprocess.Popen(spec[key], stdin=subprocess.PIPE if key == 'browser_argv' else subprocess.DEVNULL,
                                stdout=out, stderr=err, start_new_session=True)
    try:
        observer = launch('observer_argv')
        while time.monotonic() - started < 645:
            if spec.get('caddy_exit_file') and Path(spec['caddy_exit_file']).exists():
                raise ValueError('caddy_owner_ended_during_workload')
            state = remote('state_argv')
            if len({c['boot_id'] for c in clocks}) != 1: raise ValueError('boot_changed')
            if state['failed']: raise ValueError('resource_failure')
            if observer.poll() is not None:
                normal_observer = observer.returncode == 0
                if not normal_observer: raise ValueError('observer_failed')
                break
            if browser is None and state['ready']:
                browser = launch('browser_argv')
                browser.stdin.write(credentials); browser.stdin.close(); credentials = b''
            if browser is not None:
                if browser.poll() is not None and browser.returncode != 0: raise ValueError('browser_failed')
                path = Path(spec['browser_receipt'])
                if path.exists():
                    # Ignore only a partially appended final row; never accept it.
                    content = private(path)
                    events = [json.loads(x) for x in content[:content.rfind('\n')+1].splitlines()]
                    active = {r['id']: r['monotonic_seconds'] for r in events if r['kind'] == 'active' and r.get('token') == token}
                    pair = ('a-ipv4', 'b-ipv6')
                    ended = {r['id'] for r in events if r['kind'] == 'workload-end'}
                    first = {k: min((r['monotonic_seconds'] for r in events if r['kind'] == 'active' and r['id'] == k), default=1e99) for k in pair}
                    if gate_sent and browser.poll() is None and any(k not in ended and time.monotonic()-active.get(k, -1e9) >= 2 for k in pair):
                        raise ValueError('browser_heartbeat_lost')
                    if not gate_sent and all(time.monotonic()-active.get(k, -1e9) < 2 and time.monotonic()-first[k] >= 6 for k in pair):
                        remote('ready_argv'); gate_sent = True
            time.sleep(.5)
        else: raise TimeoutError('workload_deadline')
        if browser is None: raise ValueError('browser_not_started')
        browser.wait(timeout=15)
        if browser.returncode != 0: raise ValueError('browser_failed')
        result.update(accept(rows(Path(spec['browser_receipt'])), rows(Path(spec['samples'])),
                             json.loads(private(Path(spec['summary']))), json.loads(private(Path(spec['observation']))), clocks, token))
    except Exception as error:
        result['failure'] = type(error).__name__ + ': ' + str(error)[:160]
    finally:
        # Load ends before asking the remote scan to stop or letting the parent restore.
        for sig in previous_signals: signal.signal(sig, signal.SIG_IGN)
        try:
            result['browser_cleanup'] = stop_owned(browser)
        except Exception:
            result['browser_cleanup'] = {'group_gone': False, 'error': 'cleanup_unverified'}
        if observer is not None and observer.poll() is None:
            try:
                remote('cancel_argv'); observer.wait(timeout=30)
            except Exception:
                result['observer_cleanup_incomplete'] = True
                try: stop_owned(observer, grace=1)
                except Exception: pass
        if not result['browser_cleanup']['group_gone'] or result.get('observer_cleanup_incomplete'):
            result['accepted'] = False
        result['observer_exit'] = None if observer is None else observer.returncode
        for file in files: file.close()
        write(directory / 'clock-brackets.json', clocks)
        write(directory / 'workload-result.json', result)
        for sig, handler in previous_signals.items(): signal.signal(sig, handler)
    return 0 if result['accepted'] else 1


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--control', type=Path)
    parser.add_argument('--action', choices=['state', 'ready', 'cancel'], default='state')
    parser.add_argument('--token')
    parser.add_argument('--spec', type=Path)
    args = parser.parse_args()
    if args.control:
        print(json.dumps(control(args.control, args.action, args.token)))
    else:
        if not args.spec: parser.error('--spec required')
        spec = json.loads(private(args.spec, 65536))
        credentials = sys.stdin.buffer.read(4097)
        if not 0 < len(credentials) <= 4096: parser.error('private credential input required')
        raise SystemExit(supervise(spec, credentials))
