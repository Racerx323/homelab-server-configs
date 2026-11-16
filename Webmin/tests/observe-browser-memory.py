#!/usr/bin/env python3
"""One bounded offline browser diagnostic; no service restart or HTTP probe thread."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import shutil
import sys
from contextlib import ExitStack
import subprocess
import time


def run(*args):
    return subprocess.check_output(args, text=True, timeout=10)


def phase(path):
    try:
        with path.open('rb') as stream:
            raw = stream.read(16385)
        if len(raw) > 16384:
            return 'trace-oversize'
        row = json.loads(raw.splitlines()[-1])
        value = row['stage']
        allowed = {'launch', 'trusted-login-page', 'rejected-login', 'login', 'assets',
                   'trusted-referrer', 'foreign-referrer', 'missing-referrer',
                   'native-websocket', 'sustained', 'logout', 'cleanup'}
        return value if isinstance(value, str) and value in allowed else 'invalid-phase'
    except (OSError, ValueError, KeyError, IndexError, TypeError):
        return 'before-browser'


def workload_batches(paired):
    if not paired:
        return [[('ipv4', ['ipv4'])]]
    return [[(f'{node}-{family}-short', [family, node, 'short'])]
            for node in ['a', 'b'] for family in ['ipv4', 'ipv6']] + [
                [('paired-proxy-start', None)],
                [('a-ipv4-sustained', ['ipv4', 'a', 'sustained']),
                 ('b-ipv6-sustained', ['ipv6', 'b', 'sustained'])]]


def stop_reason(sample, exits, elapsed, size):
    if size > 24 * 1024 * 1024:
        return 'evidence-bound'
    for scope in [sample, *sample['ancestors'].values()]:
        counts = dict(line.split() for line in scope['memory.events.local'].splitlines()
                      if len(line.split()) == 2)
        if any(int(counts.get(key, '0')) for key in ['max', 'oom', 'oom_kill', 'oom_group_kill']):
            return 'hard-limit-or-oom-event'
    if sample['memory.current'].startswith('unavailable'):
        return 'cgroup-disappeared'
    if any(status not in (None, 0) for status in exits):
        return 'workload-failed'
    if elapsed >= 420:
        return 'deadline'
    return None

def main():
    os.umask(0o077)
    assert Path('/run/.containerenv').is_file()
    assert {r['ifname'] for r in json.loads(run('ip', '-j', 'link'))} == {'lo'}
    spec = importlib.util.spec_from_file_location('diagnostic', '/work/Webmin/scripts/diagnose-http.py')
    diagnostic = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(diagnostic)
    group = Path('/sys/fs/cgroup/system.slice/webmin.service')
    assert group.is_dir() and (group/'memory.max').read_text().strip() == '201326592'
    assert '/system.slice/webmin.service' not in Path('/proc/self/cgroup').read_text()
    props = '--property=ActiveState,SubState,Result,MainPID,NRestarts,MemoryCurrent,MemoryPeak,MemoryHigh,MemoryMax,ControlGroup'
    assert 'ActiveState=active' in run('systemctl', 'show', 'webmin.service', props).splitlines()
    evidence = Path('/evidence')
    paired = sys.argv[1:] == ['--paired']
    assert not sys.argv[1:] or paired
    fixture = json.loads((evidence/'fixture-mode.json').read_text())
    assert fixture['paired'] == paired
    units = fixture['units']
    expected_units = (['webmin-fixture-caddy-a.service', 'webmin-fixture-caddy-b.service']
                      if paired else ['webmin-fixture-caddy.service'])
    assert units == expected_units
    batches = workload_batches(paired)
    assert not any((evidence/f'browser-phases-{label}.jsonl').exists()
                   for batch in batches for label, _ in batch)
    start = time.monotonic()
    children = []
    active = []
    batch_index = 0
    result = {'kind': 'offline-resource-qualification-not-production-acceptance',
              'paired': paired, 'samples': 0, 'stop_reason': None, 'workloads': {}, 'passed': False}
    try:
        with ExitStack() as stack:
            output = stack.enter_context((evidence/'memory-phases.jsonl').open('x'))
            last = start
            while True:
                now = time.monotonic()
                sample = diagnostic.sample(group, start)
                sample['monotonic_ns'] = time.monotonic_ns()
                sample['sample_gap_seconds'] = round(now-last, 4)
                last = now
                sample['phases'] = {label: phase(evidence/f'browser-phases-{label}.jsonl')
                                    for label, child in active}
                sample['ancestors'] = {}
                for parent in [group.parent, group.parent.parent]:
                    sample['ancestors'][str(parent)] = {name: diagnostic.read_small(parent/name, 8192).strip()
                        for name in ['memory.current', 'memory.peak', 'memory.max', 'memory.events', 'memory.events.local', 'memory.pressure']}
                sample['proxy_memory'] = {unit: {name: diagnostic.read_small(group.parent/unit/name, 8192).strip()
                    for name in ['memory.current', 'memory.peak', 'memory.events.local']} for unit in units}
                sample['observer'] = {line.split(':', 1)[0]: line.split(':', 1)[1].strip()
                    for line in Path('/proc/self/status').read_text().splitlines() if line.startswith(('VmRSS:', 'Threads:'))}
                output.write(json.dumps(sample) + '\n')
                output.flush()
                result['samples'] += 1
                exits = [child.poll() for _, child in active]
                result['stop_reason'] = stop_reason(sample, exits, now-start, output.tell())
                if result['stop_reason']:
                    break
                if active and all(status == 0 for status in exits):
                    for label, child in active:
                        result['workloads'][label] = child.returncode
                    active = []
                if not active and batch_index == len(batches):
                    result['stop_reason'] = 'workloads-complete'
                    break
                if not active and now-start >= 5:
                    for label, args in batches[batch_index]:
                        log = stack.enter_context((evidence/(label+'.log')).open('x'))
                        if args is None:
                            for node in ['a', 'b']:
                                shutil.copy2(evidence/f'Caddyfile-{node}-paired', evidence/f'Caddyfile-{node}')
                            command = ['systemctl', 'restart', *units]
                        else:
                            command = ['node', '/work/Webmin/tests/qualify-proxy-browser.cjs', *args]
                        child = subprocess.Popen(command, env={**os.environ, 'NODE_PATH': '/tooling'},
                                                 stdout=log, stderr=log, start_new_session=True)
                        children.append((label, child))
                        active.append((label, child))
                    batch_index += 1
                time.sleep(0.25)
    finally:
        result['unit_before_containment'] = run('systemctl', 'show', 'webmin.service', props).splitlines()
        result['proxy_units_before_containment'] = run('systemctl', 'show', *units, props).splitlines()
        # Stop the service before waiting for browser teardown; preserve native restart policy.
        run('systemctl', 'stop', 'webmin.service', *units)
        for label, child in children:
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGTERM)
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait(timeout=5)
            result['workloads'][label] = child.returncode
        result['unit_after_containment'] = run('systemctl', 'show', 'webmin.service', props).splitlines()
        result['elapsed_seconds'] = round(time.monotonic()-start, 3)
        result['passed'] = (result['stop_reason'] == 'workloads-complete'
                            and set(result['workloads'].values()) == {0}
                            and {'ActiveState=active', 'NRestarts=0'} <= set(result['unit_before_containment']))
        (evidence/'attribution-result.json').write_text(json.dumps(result, indent=2)+'\n')
        print(json.dumps(result))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
