#!/usr/bin/env python3
"""Bounded native backend comparison; target execution requires a sealed approval."""
import argparse
import fcntl
import stat
import importlib.util
import json
import math
import multiprocessing
import os
from pathlib import Path
import signal
import subprocess
import time

_spec = importlib.util.spec_from_file_location('path_probe', Path(__file__).with_name('probe-proxy-path.py'))
probe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(probe)


class GateFailure(ValueError):
    """Only fixed local failure codes may be retained."""


def expired(_signum, _frame):
    raise TimeoutError('request_deadline')


def request_worker(sender, start, address, hostname, source):
    """One owned process, one request, no retry; alarm bounds all blocking reads."""
    try:
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
        signal.signal(signal.SIGALRM, expired)
        if not start.wait(2):
            raise TimeoutError('batch_start')
        signal.setitimer(signal.ITIMER_REAL, 5)
        sender.send(probe.probe(address, hostname, source))
    except Exception as error:
        sender.send({'accepted': False, 'failure': type(error).__name__})
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        sender.close()


def batch(count, address, hostname, source):
    if count not in (1, 3):
        raise GateFailure('batch_count')
    ctx = multiprocessing.get_context('fork')
    start = ctx.Event()
    children, receivers = [], []
    began = time.monotonic()
    old = signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(SystemExit(143)))
    try:
        for _ in range(count):
            receiver, sender = ctx.Pipe(duplex=False)
            child = ctx.Process(target=request_worker, args=(sender, start, address, hostname, source))
            child.start(); sender.close()
            children.append(child); receivers.append(receiver)
        start.set()
        results = []
        for receiver in receivers:
            if not receiver.poll(max(0, began + 7 - time.monotonic())):
                results.append({'accepted': False, 'failure': 'worker_deadline'})
            else:
                try:
                    results.append(receiver.recv())
                except EOFError:
                    results.append({'accepted': False, 'failure': 'worker_exit'})
    finally:
        # Shared cleanup deadline, not one full timeout per child.
        for child in children:
            if child.is_alive(): child.terminate()
        stop = time.monotonic() + 1
        for child in children: child.join(max(0, stop-time.monotonic()))
        for child in children:
            if child.is_alive(): child.kill()
        for child in children: child.join()
        for receiver in receivers: receiver.close()
        signal.signal(signal.SIGTERM, old)
    return {'count': count, 'requests': results, 'owned_clients_reaped': True,
            'accepted': all(r.get('accepted') for r in results),
            'duration_seconds': time.monotonic()-began}


def process_identity(pid):
    raw = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
    if raw[0] == 'Z': raise GateFailure('zombie_process')
    return [pid, int(raw[19])]


def backend_state():
    """Numeric process/socket state only; never command lines or environment."""
    result = probe.snapshot()
    mem = dict(line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines())
    result['available_kib'] = int(mem['MemAvailable'].split()[0])
    result['processes'] = {}
    for unit in ('webmin.service', 'uptime-kuma.service'):
        group = Path('/sys/fs/cgroup/system.slice') / unit
        pids = sorted(int(p) for f in group.rglob('cgroup.procs') for p in f.read_text().split())
        result['processes'][unit] = [process_identity(p) for p in sorted(set(pids))]
        result['cgroups'][unit]['limits'] = {name: (group/name).read_text().strip()
                                           for name in ('memory.high', 'memory.max', 'memory.swap.max')}
    active = 0
    for name in ('tcp', 'tcp6'):
        for line in Path('/proc/net', name).read_text().splitlines()[1:]:
            fields = line.split()
            # LISTEN and TIME_WAIT do not represent an executing connected request.
            if int(fields[1].rsplit(':', 1)[1], 16) == 10000 and fields[3] not in ('0A', '06'):
                active += 1
    result['request_connections'] = active
    return result


def healthy(baseline, current, expected_limits):
    if current['available_kib'] < 96 * 1024:
        raise GateFailure('reserve_below_96_mib')
    for unit, expected in expected_limits.items():
        if current['cgroups'][unit]['limits'] != expected:
            raise GateFailure('service_limit_drift')
    deltas = probe.event_delta(baseline, current)
    for value in deltas.values():
        if value['status'] != 'comparable' or any(value.get('events', {}).get(k, 0) for k in ('high', 'max', 'oom', 'oom_kill')):
            raise GateFailure('resource_event_or_continuity')
    for unit, old in baseline['processes'].items():
        if not old or not all(p in current['processes'][unit] for p in old):
            raise GateFailure('baseline_process_lost')


def quiescent(current, baseline):
    # Conservative: no baseline child is accepted as proof of an idle server.
    return (len(baseline['processes']['webmin.service']) == 1
            and current['processes']['webmin.service'] == baseline['processes']['webmin.service']
            and current['request_connections'] == 0)


def gate(directory, expected_limits, initialize=False):
    directory = Path(directory)
    deadline = time.monotonic()+10
    path = directory/'comparison-baseline.json'
    baseline = backend_state() if initialize else json.loads(path.read_text())
    stable = 0
    while time.monotonic() < deadline:
        if (directory/'comparison-stop').exists(): raise GateFailure('observer_stop')
        current = backend_state(); healthy(baseline, current, expected_limits)
        stable = stable+1 if quiescent(current, baseline) else 0
        if stable >= 2:
            if initialize:
                with path.open('x') as stream: json.dump(baseline, stream)
            return {'accepted': True, 'quiescent_samples': stable, 'state': current}
        time.sleep(1)
    raise GateFailure('backend_not_quiescent')


def observe(directory, expected_limits):
    directory = Path(directory)
    baseline = json.loads((directory/'comparison-baseline.json').read_text())
    if (directory/'resource-stop').exists(): raise GateFailure('observer_already_stopped')
    with (directory/'observer-owner.json').open('x') as stream:
        json.dump({'process': process_identity(os.getpid())}, stream)
    def check(row):
        try:
            state = backend_state()
            healthy(baseline, state, expected_limits)
            row['comparison'] = state
        except Exception as error:
            # Latch the first stop; no private exception text.
            if not (directory/'comparison-stop').exists():
                (directory/'comparison-stop').write_text(json.dumps({'failure': str(error) if isinstance(error, GateFailure) else type(error).__name__}))
            row['comparison_stop'] = True
    result = probe.observe(directory, seconds=240, wire=('10.1.0.53', '10.1.3.75',
                           'webmin-j2-svpi3bmf.local.theama.co'), sample_check=check)
    with (directory/'observer-exited.json').open('x') as stream: json.dump(result, stream)
    return result


def assess_wire(rows, result):
    requests = result['requests']
    markers = [r.get('timing', {}).get('request_id') for r in requests]
    if len(markers) != result['count'] or None in markers or len(set(markers)) != len(markers):
        raise GateFailure('request_markers')
    starts, ends = {}, {}
    if len(rows) > 512: raise GateFailure('wire_event_limit')
    for row in rows:
        if row.get('terminal') and (row.get('issues') or row.get('kernel_drops')):
            raise GateFailure('wire_incomplete')
        if row.get('event') == 'request-headers' and row.get('request_id') in markers:
            if row['request_id'] in starts: raise GateFailure('duplicate_marker')
            starts[row['request_id']] = (row['flow'], row['kernel_epoch'])
        if row.get('event') == 'response-first-byte': ends[row['flow']] = row['kernel_epoch']
    if set(starts) != set(markers): raise GateFailure('wire_requests_missing')
    if result['count'] == 3:
        if any(flow not in ends for flow, _ in starts.values()): raise GateFailure('wire_response_missing')
        if max(stamp for _, stamp in starts.values()) >= min(ends[flow] for flow, _ in starts.values()):
            raise GateFailure('overlap_not_demonstrated')
    return {'accepted': True, 'request_count': len(markers), 'overlap': result['count'] == 3}


def join_observer(directory):
    directory = Path(directory)
    (directory/'resource-stop').touch(mode=0o600, exist_ok=True)
    owner = json.loads((directory/'observer-owner.json').read_text())['process']
    deadline = time.monotonic()+5
    while time.monotonic() < deadline:
        try: current = process_identity(owner[0])
        except (FileNotFoundError, ProcessLookupError): current = None
        if current != owner:
            if not json.loads((directory/'observer-exited.json').read_text()).get('observer_exited'):
                raise GateFailure('observer_failed')
            return {'accepted': True, 'observer_gone': True}
        time.sleep(0.1)
    raise GateFailure('observer_join_deadline')


def terminal_evidence(directory, expected_limits):
    """Accept only complete same-host resource/wire coverage; no cross-host clock assumption."""
    directory = Path(directory)
    def records(name, maximum):
        path = directory/name
        if path.is_symlink() or path.stat().st_size > maximum:
            raise GateFailure('evidence_file')
        return [json.loads(line) for line in path.read_text().splitlines()]
    samples = records('resource-samples.jsonl', 1048576)
    wire = records('backend-wire.jsonl', 1048576)
    if (len(samples) < 3 or not samples[-1].get('terminal') or samples[-1].get('reason') != 'stop'
            or any(r.get('terminal') for r in samples[:-1])
            or not wire or not wire[-1].get('terminal')
            or any(r.get('terminal') for r in wire[:-1])
            or wire[-1].get('issues') != [] or wire[-1].get('kernel_drops') != 0):
        raise GateFailure('observer_terminal_missing_or_failed')
    if (directory/'comparison-stop').exists(): raise GateFailure('observer_stop')
    if not json.loads((directory/'observer-exited.json').read_text()).get('observer_exited'):
        raise GateFailure('observer_exit_missing')
    baseline = json.loads((directory/'comparison-baseline.json').read_text())
    for row in samples:
        if any(not isinstance(row.get(k), (int, float)) or not math.isfinite(row[k]) for k in ('epoch', 'monotonic')):
            raise GateFailure('resource_clock_invalid')
    for row in samples[:-1]:
        if row.get('boot_id') != baseline['boot_id']: raise GateFailure('resource_boot_mismatch')
        if row.get('comparison_stop') or 'comparison' not in row:
            raise GateFailure('resource_sample_missing')
        healthy(baseline, row['comparison'], expected_limits)
    for left, right in zip(samples, samples[1:]):
        dt = right['monotonic']-left['monotonic']
        if not 0 < dt <= 2.5 or abs((right['epoch']-left['epoch'])-dt) > 0.25:
            raise GateFailure('resource_gap_or_clock_step')
    if not quiescent(samples[-2]['comparison'], baseline):
        raise GateFailure('terminal_backend_not_quiescent')
    expected_headers = {'host': 'webmin-j2-svpi3bmf.local.theama.co',
        'x-forwarded-host': 'webmin-j2-svpi3bmf.local.theama.co',
        'x-forwarded-proto': 'https', 'x-forwarded-for': '10.1.0.53',
        'accept': '*/*', 'accept-encoding': 'identity',
        'user-agent': 'homelab-proxy-diagnostic', 'connection': 'close'}
    receipts = []
    missing = False
    for name, count in [('baseline', 1), ('concurrent', 3), ('recovery-control', 1)]:
        path = directory/(name+'.json')
        if not path.exists():
            missing = True
            continue
        if missing or path.stat().st_size > 65536: raise GateFailure('phase_sequence')
        receipt = json.loads(path.read_text())
        if receipt['count'] != count or not receipt.get('owned_clients_reaped'):
            raise GateFailure('client_cleanup_or_count')
        assess_wire(wire, receipt)
        receipts.append(receipt)
    if not receipts: raise GateFailure('no_request_receipts')
    markers = [r['timing']['request_id'] for batch_result in receipts for r in batch_result['requests']]
    if len(markers) != len(set(markers)): raise GateFailure('duplicate_marker')
    marked_flows = set()
    previous_stamp = previous_observed = float('-inf')
    for row in wire[:-1]:
        stamp = row['kernel_epoch']
        observed = row['observed_boottime']
        if any(not isinstance(v, (int, float)) or not math.isfinite(v) for v in (stamp, observed)):
            raise GateFailure('wire_clock_invalid')
        if stamp < previous_stamp or observed < previous_observed:
            raise GateFailure('wire_time_order')
        previous_stamp, previous_observed = stamp, observed
        if not samples[0]['epoch'] <= stamp <= samples[-2]['epoch']:
            raise GateFailure('wire_outside_resource_coverage')
        if not samples[0]['monotonic'] <= observed <= samples[-2]['monotonic']+0.02:
            raise GateFailure('wire_outside_monotonic_coverage')
        # Backend capture and resource samples share a clock; bound delivery lag.
        offset = samples[0]['epoch']-samples[0]['monotonic']
        if not -0.05 <= observed+offset-stamp <= 2.25:
            raise GateFailure('wire_clock_uncertain')
        if row.get('event') == 'request-headers':
            if row.get('request_id') not in markers or row.get('headers') != expected_headers:
                raise GateFailure('unexpected_request_contract_or_background_traffic')
            marked_flows.add(row['flow'])
    if len(marked_flows) != len(markers): raise GateFailure('request_flow_count')
    for row in wire[:-1]:
        if row.get('flow') not in marked_flows and row.get('event') not in ('request-close', 'response-close'):
            raise GateFailure('unassigned_payload')
    return {'evidence_valid': True, 'accepted': len(receipts) == 3 and all(r.get('accepted') for r in receipts),
            'request_count': len(markers), 'resource_samples': len(samples)-1,
            'scope': 'backend comparison only; no historical causal attribution'}


def bounded_command(command, deadline, log):
    """One process group and one absolute deadline, including termination grace."""
    child = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    timed_out = False
    try:
        child.wait(timeout=max(0, deadline-time.monotonic()-2))
    except subprocess.TimeoutExpired:
        timed_out = True
    finally:
        # Include descendants even if their immediate parent exited first.
        try: os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError: pass
        try: child.wait(timeout=max(0, min(1, deadline-time.monotonic())))
        except subprocess.TimeoutExpired: pass
        try: os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError: pass
        child.wait(timeout=max(0.1, deadline-time.monotonic()))
    return {'exit': child.returncode, 'timed_out': timed_out}


def supervise(command, directory, forward_seconds=240, recovery_seconds=840):
    """Forward failure cannot bypass the separate recovery invocation."""
    directory = Path(directory)
    result = {'forward': None, 'recovery': None}
    def interrupted(*_): raise InterruptedError('controller_interrupted')
    old = {s: signal.signal(s, interrupted) for s in (signal.SIGINT, signal.SIGTERM)}
    try:
        with (directory/'forward.log').open('x') as log:
            result['forward'] = bounded_command(command+['--tags', 'comparison-forward'],
                                                 time.monotonic()+forward_seconds, log)
    except Exception as error:
        result['forward'] = {'failure': type(error).__name__}
    finally:
        # A second terminal signal must not interrupt the reserved recovery period.
        for s in old: signal.signal(s, lambda *_: None)
        recovery_deadline = time.monotonic()+recovery_seconds
        try:
            with (directory/'recovery.log').open('x') as log:
                result['recovery'] = bounded_command(command+['--tags', 'comparison-recovery'],
                                                      recovery_deadline, log)
        except Exception as error:
            result['recovery'] = {'failure': type(error).__name__}
        finally:
            for s, handler in old.items(): signal.signal(s, handler)
    result['processes_succeeded'] = all(r and r.get('exit') == 0 and not r.get('timed_out')
                             for r in (result['forward'], result['recovery']))
    result['accepted'] = False
    receipt = directory/'recovery-result.json'
    if receipt.exists():
        recovery = json.loads(receipt.read_text())
        result['accepted'] = (result['processes_succeeded'] and recovery.get('evidence_status') == 0
                              and recovery.get('restoration_verified', False)
                              and not recovery.get('restoration_failed', True)
                              and not recovery.get('observer_failed', True)
                              and recovery.get('client_cleanup', {}).get('rc') == 0)
    with (directory/'controller-result.json').open('x') as stream: json.dump(result, stream)
    return result


def client_control(directory, count=None):
    """The stop latch prevents a delayed dispatch from starting another batch."""
    directory = Path(directory)
    info = directory.lstat()
    if directory.is_symlink() or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077:
        raise GateFailure('client_directory')
    if count is None:
        (directory/'client-stop').touch(mode=0o600, exist_ok=True)
    with (directory/'client.lock').open('a') as lock:
        old = signal.signal(signal.SIGALRM, expired)
        signal.setitimer(signal.ITIMER_REAL, 12)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX)
            if count is None:
                return {'accepted': True, 'owned_clients_reaped': True, 'stop_latched': True}
            if (directory/'client-stop').exists(): raise GateFailure('client_stop_latched')
            return batch(count, '10.1.3.75', 'webmin-j2-svpi3bmf.local.theama.co', '10.1.0.53')
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0)
            signal.signal(signal.SIGALRM, old)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['batch', 'gate', 'observe', 'wire', 'terminal', 'run', 'stop-clients', 'join-observer'])
    parser.add_argument('--count', type=int, choices=[1, 3])
    parser.add_argument('--directory')
    parser.add_argument('--limits')
    parser.add_argument('--initialize', action='store_true')
    parser.add_argument('--receipt')
    parser.add_argument('--inventory')
    parser.add_argument('--variables')
    args = parser.parse_args()
    os.umask(0o077)
    try:
        if args.action == 'run':
            directory = Path(args.directory)
            info = directory.lstat()
            if directory.is_symlink() or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077:
                raise GateFailure('controller_directory')
            if any(directory.iterdir()): raise GateFailure('controller_directory_not_fresh')
            variables = json.loads(Path(args.variables).read_text())
            if variables['operation_evidence_directory'] != str(directory): raise GateFailure('evidence_binding')
            with (directory/'run-started').open('x') as stream: stream.write('consumed\n')
            result = supervise(['ansible-playbook', str(Path(__file__).parents[1]/'ansible/backend-comparison.yaml'),
                                '-i', args.inventory, '-e', '@'+args.variables], args.directory)
        elif args.action == 'terminal':
            result = terminal_evidence(args.directory, json.loads(Path(args.limits).read_text()))
        elif args.action == 'batch':
            result = client_control(args.directory, args.count)
        elif args.action == 'join-observer':
            result = join_observer(args.directory)
        elif args.action == 'stop-clients':
            result = client_control(args.directory)
        elif args.action == 'wire':
            rows = [json.loads(s) for s in (Path(args.directory)/'backend-wire.jsonl').read_text().splitlines()]
            result = assess_wire(rows, json.loads(Path(args.receipt).read_text()))
        else:
            limits = json.loads(Path(args.limits).read_text())
            if set(limits) != {'webmin.service', 'uptime-kuma.service'}: raise GateFailure('limit_units')
            result = gate(args.directory, limits, args.initialize) if args.action == 'gate' else observe(args.directory, limits)
        print(json.dumps(result))
        return 0 if result.get('accepted', result.get('observer_exited', False)) else 1
    except Exception as error:
        print(json.dumps({'accepted': False, 'failure': str(error) if isinstance(error, GateFailure) else type(error).__name__}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
