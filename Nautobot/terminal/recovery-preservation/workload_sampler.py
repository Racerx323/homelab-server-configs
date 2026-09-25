"""Bounded node-local read-only sampler; no load, service or recovery actions.

The workload session monitors this reader and stops operation-owned load on
failed or missing coverage. Live use requires a separately approved bundle.
"""
import argparse
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess
import tempfile
import time

ERROR_CODES = frozenset(('collection_command_failed', 'collection_output_limit', 'throttling_unavailable',
    'container_pid', 'cgroup_v2', 'cgroup_path', 'unbounded_memory', 'journal_coverage_gap',
    'kernel_message_unavailable', 'boot_changed', 'sample_duration', 'sample_gap', 'metric_invalid',
    'memory_headroom', 'temperature', 'throttling', 'storage_error', 'diskstats_missing',
    'swap_counters', 'service_coverage', 'service_state', 'service_changed', 'memory_limit',
    'oom_increment', 'swap_window_missing', 'phase_coverage', 'phase_short', 'phase_gap',
    'initial_coverage', 'final_coverage', 'swap_acceptance', 'duration', 'sample_output_limit', 'root_required'))
ROLES = ('postgresql', 'redis', 'web', 'worker', 'scheduler')
USER = ['/usr/sbin/runuser', '--user', 'nautobot', '--', '/usr/bin/env',
        'XDG_RUNTIME_DIR=/run/user/999', 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus']
ERRORS = re.compile(r'reset.*USB|USB.*reset|I/O error|EXT4-fs (?:error|warning)|Buffer I/O|uas.*(?:abort|error)|device offline|timing out command|blk_update_request|under.voltage|out of memory|oom-kill', re.I)


def require(value, code):
    if not value:
        raise ValueError(code)


class CollectionFailure(ValueError):
    def __init__(self, command, category, status=None):
        super().__init__('collection_command_failed')
        self.diagnostic = {'command': command, 'category': category, 'exit_status': status}


def failure_receipt(error):
    code = str(error) if isinstance(error, ValueError) and str(error) in ERROR_CODES else 'collection_unavailable'
    result = {'status': 'incomplete', 'reason': code, 'action': 'stop_test_load_and_preserve_evidence'}
    if isinstance(error, CollectionFailure):
        result['command_failure'] = error.diagnostic
    return result


def run(argv):
    command = ('throttling' if 'get_throttled' in argv else
               'service_state' if '/usr/bin/systemctl' in argv else
               'container_pid' if '/usr/bin/podman' in argv else
               'kernel_window' if '--after-cursor' in argv else
               'journal_cursor' if '--cursor' in argv else 'unknown')

    try:
        with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
            result = subprocess.run(['/usr/bin/prlimit', '--fsize=4194304:4194304', '--', *argv],
                                    stdin=subprocess.DEVNULL, stdout=out, stderr=err, cwd='/', timeout=3)
            if out.tell() >= 4194304 or err.tell() >= 4194304:
                raise CollectionFailure(command, 'output_limit', result.returncode)
            if result.returncode != 0:
                raise CollectionFailure(command, 'exit_status', result.returncode)
            out.seek(0)
            return out.read().decode()
    except subprocess.TimeoutExpired:
        raise CollectionFailure(command, 'timeout') from None
    except OSError:
        raise CollectionFailure(command, 'launch_error') from None


def pairs(text):
    return {line.split()[0].rstrip(':'): int(line.split()[1]) for line in text.splitlines()}


class Reader:
    def __init__(self, cursor, runner=run, proc=Path('/proc'), sys=Path('/sys'), roles=ROLES):
        self.cursor, self.run, self.proc, self.sys = cursor, runner, proc, sys
        self.roles = tuple(roles)
        require(bool(self.roles) and set(self.roles) <= set(ROLES), 'service_coverage')

    def sample(self):
        start = time.monotonic()
        mem = pairs((self.proc / 'meminfo').read_text())
        vm = pairs((self.proc / 'vmstat').read_text())
        sample = {'start': start, 'utc_seconds': time.time(), 'boot_id': (self.proc / 'sys/kernel/random/boot_id').read_text().strip(),
                  'mem_available_bytes': mem['MemAvailable'] * 1024,
                  'swap_used_bytes': (mem['SwapTotal'] - mem['SwapFree']) * 1024,
                  'swap_in_out_counters': [vm['pswpin'], vm['pswpout']],
                  'cpu_temperature_celsius': int((self.sys / 'class/thermal/thermal_zone0/temp').read_text()) / 1000,
                  'ext4_error_count': int((self.sys / 'fs/ext4/sda2/errors_count').read_text()),
                  'diskstats': [int(x) for line in (self.proc / 'diskstats').read_text().splitlines()
                                if line.split()[2] == 'sda' for x in line.split()[3:]], 'services': {}}
        throttle = self.run(['/usr/bin/vcgencmd', 'get_throttled']).strip()
        require(re.fullmatch(r'throttled=0x[0-9a-fA-F]+', throttle), 'throttling_unavailable')
        sample['throttling_flags'] = int(throttle.split('=')[1], 16)
        raw = self.run(USER + ['/usr/bin/systemctl', '--user', 'show',
                       *['nautobot-' + r + '.service' for r in self.roles],
                       '--property=Id,ActiveState,SubState,Result,NRestarts,InvocationID'])
        units = {row['Id']: row for block in raw.strip().split('\n\n')
                 if (row := dict(line.split('=', 1) for line in block.splitlines()))}
        # Format selection avoids reading Config.Env, labels or secrets.
        raw = self.run(USER + ['/usr/bin/podman', 'inspect', '--format',
                              '{{.Name}} {{.State.Pid}}', *['nautobot-' + r for r in self.roles]])
        pids = dict(line.split() for line in raw.splitlines())
        for role in self.roles:
            pid = int(pids['nautobot-' + role])
            require(pid > 1, 'container_pid')
            path = (self.proc / str(pid) / 'cgroup').read_text().strip()
            require(path.startswith('0::/') and '\n' not in path, 'cgroup_v2')
            cg = self.sys / 'fs/cgroup' / path[4:]
            require(cg.resolve().is_relative_to((self.sys / 'fs/cgroup').resolve()), 'cgroup_path')
            maximum = (cg / 'memory.max').read_text().strip()
            require(maximum.isdigit(), 'unbounded_memory')
            sample['services'][role] = {'unit': units['nautobot-' + role + '.service'], 'pid': pid,
                'cgroup': path[3:], 'memory_current': int((cg / 'memory.current').read_text()),
                'memory_max': int(maximum), 'events': pairs((cg / 'memory.events').read_text())}
        raw = self.run(['/usr/bin/journalctl', '--cursor', self.cursor, '-n', '+1', '-o', 'json',
                        '--output-fields=__CURSOR', '--no-pager', '--quiet'])
        rows = [json.loads(line) for line in raw.splitlines()]
        require(len(rows) == 1 and rows[0]['__CURSOR'] == self.cursor, 'journal_coverage_gap')
        raw = self.run(['/usr/bin/journalctl', '--after-cursor', self.cursor, '_TRANSPORT=kernel',
                        '-o', 'json', '--output-fields=__CURSOR,MESSAGE', '--no-pager', '--quiet'])
        rows = [json.loads(line) for line in raw.splitlines()]
        require(all(isinstance(row.get('MESSAGE'), str) for row in rows), 'kernel_message_unavailable')
        sample['kernel_storage_errors_since_cursor'] = sum(bool(ERRORS.search(row['MESSAGE'])) for row in rows)
        if rows:
            self.cursor = rows[-1]['__CURSOR']
        sample['journal_cursor'] = self.cursor
        sample['end'] = time.monotonic()
        return sample


def validate(sample, first, previous, contract, roles=ROLES):
    """One bad/missing sample stops collection. No implicit success for absent data."""
    stop = contract['stop_criteria']
    require(sample['boot_id'] == first['boot_id'], 'boot_changed')
    require(0 <= sample['end'] - sample['start'] <= contract['sampling']['maximum_gap_seconds'], 'sample_duration')
    if previous is not None:
        require(0 < sample['start'] - previous['start'] <= contract['sampling']['maximum_gap_seconds'], 'sample_gap')
    for key in ('mem_available_bytes', 'swap_used_bytes', 'cpu_temperature_celsius', 'ext4_error_count', 'throttling_flags', 'kernel_storage_errors_since_cursor'):
        require(type(sample[key]) in (int, float) and math.isfinite(sample[key]) and sample[key] >= 0, 'metric_invalid')
    require(sample['mem_available_bytes'] >= stop['mem_available_below_bytes'], 'memory_headroom')
    require(sample['cpu_temperature_celsius'] <= stop['temperature_above_celsius'], 'temperature')
    require(sample['throttling_flags'] == 0, 'throttling')
    require(sample['ext4_error_count'] == first['ext4_error_count'] and sample['kernel_storage_errors_since_cursor'] == 0, 'storage_error')
    require(len(sample['diskstats']) >= 11 and all(type(n) is int and n >= 0 for n in sample['diskstats']), 'diskstats_missing')
    require(len(sample['swap_in_out_counters']) == 2 and all(type(n) is int and n >= 0 for n in sample['swap_in_out_counters']), 'swap_counters')
    require(set(sample['services']) == set(roles), 'service_coverage')
    for role in roles:
        row, base = sample['services'][role], first['services'][role]
        unit = row['unit']
        require(unit['ActiveState'] == 'active' and unit['SubState'] == 'running' and unit['Result'] == 'success', 'service_state')
        require(row['pid'] == base['pid'] and row['cgroup'] == base['cgroup']
                and unit['InvocationID'] == base['unit']['InvocationID'] and unit['NRestarts'] == base['unit']['NRestarts'], 'service_changed')
        require(0 <= row['memory_current'] <= row['memory_max'] and row['memory_max'] == base['memory_max'], 'memory_limit')
        for event in ('oom', 'oom_kill'):
            require(row['events'][event] == base['events'][event], 'oom_increment')


def swap_review(samples, idle_end, recovery_end, contract):
    """Call only after full sampling coverage and phase chronology are verified."""
    def median(start, end):
        values = [s['swap_used_bytes'] for s in samples if start <= s['start'] < end]
        require(len(values) >= 2, 'swap_window_missing')
        return statistics.median(values)
    baseline = median(idle_end - 300, idle_end)
    tolerance = contract['swap_acceptance']['tolerance_bytes']
    windows = [median(t, t + 60) for t in range(int(idle_end), int(recovery_end) - 59, 60)]
    growth = any(a < b < c and c - baseline > tolerance for a, b, c in zip(windows, windows[1:], windows[2:]))
    recovered = median(recovery_end - 300, recovery_end) <= baseline + tolerance
    return {'baseline_bytes': baseline, 'growth_failed': growth, 'recovered': recovered}


def review_samples(samples, phases, contract):
    """Coverage/resource review only; no Job, backup or persistence acceptance."""
    require(bool(samples) and len(phases) == len(contract['phases']), 'phase_coverage')
    previous_end = None
    for observed, expected in zip(phases, contract['phases']):
        require(set(observed) == {'id', 'start', 'end'} and observed['id'] == expected['id'], 'phase_coverage')
        require(observed['end'] - observed['start'] >= expected['minimum_seconds'], 'phase_short')
        require(previous_end is None or observed['start'] == previous_end, 'phase_gap')
        previous_end = observed['end']
    first, last = samples[0], samples[-1]
    maximum_gap = contract['sampling']['maximum_gap_seconds']
    require(abs(first['start'] - phases[0]['start']) <= maximum_gap, 'initial_coverage')
    require(0 <= phases[-1]['end'] - last['end'] <= maximum_gap, 'final_coverage')
    require(phases[-1]['end'] - phases[0]['start'] <= contract['limits']['whole_workload_timeout_seconds'], 'duration')
    for i, sample in enumerate(samples):
        validate(sample, first, samples[i-1] if i else None, contract)
    result = swap_review(samples, phases[0]['end'], phases[-2]['end'], contract)
    require(not result['growth_failed'] and result['recovered'], 'swap_acceptance')
    return {'resource_coverage_passed': True, 'swap': result, 'workload_accepted': False,
            'remaining_evidence': ['job_results', 'real_application_backup_overlap', 'fixture_representativeness']}


def collect(reader, contract, duration, output, clock=time.monotonic, sleep=time.sleep):
    require(0 < duration <= contract['limits']['whole_workload_timeout_seconds'], 'duration')
    started, previous, first, written = clock(), None, None, 0
    while True:
        sample = reader.sample()
        if first is None:
            first = sample
        payload = (json.dumps(sample, sort_keys=True, separators=(',', ':')) + '\n').encode()
        written += len(payload)
        require(written <= contract['limits']['collection_stream_bytes'], 'sample_output_limit')
        output.write(payload)
        output.flush()
        validate(sample, first, previous, contract)
        previous = sample
        if clock() - started >= duration:
            return  # Collection completion is NOT workload acceptance.
        sleep(max(0, sample['start'] + contract['sampling']['interval_seconds'] - clock()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--contract', type=Path, required=True)
    parser.add_argument('--cursor', required=True)
    parser.add_argument('--duration', type=int, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    contract = json.loads(args.contract.read_text())
    require(os.geteuid() == 0, 'root_required')
    # The bundle must validate this contract against workload-test.schema.json.
    fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as output:
        collect(Reader(args.cursor), contract, args.duration, output)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # No exception text, raw journal messages or command output in receipts.
        print(json.dumps(failure_receipt(error)))
        raise SystemExit(1)
