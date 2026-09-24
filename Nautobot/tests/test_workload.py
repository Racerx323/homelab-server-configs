#!/usr/bin/env python3
"""Offline behavior tests. MemoryStore does not qualify Nautobot/PostgreSQL."""
import copy
from contextlib import contextmanager
import importlib.util
import io
import json
import tempfile
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
import yaml

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / 'Nautobot/ansible/scripts'


def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


adapter = load('workload_adapter')
sampler = load('workload_sampler')
generator = load('make-workload-fixture')
CONTRACT = yaml.safe_load((ROOT / 'Nautobot/manifests/workload-test.yaml').read_text())


class MemoryStore:
    def __init__(self):
        self.rows = []
        self.writes = 0
        self.fail_after = None

    @contextmanager
    def transaction(self, write):
        prior = copy.deepcopy(self.rows)
        try:
            yield
        except Exception:
            self.rows = prior
            raise

    def identity(self, obj):
        return obj['id']

    def find(self, model, lookup):
        return [r for r in self.rows if r['model'] == model and all(r['fields'].get(k) == v for k, v in lookup.items())]

    def create(self, model, fields, content_types):
        self.writes += 1
        if self.fail_after == self.writes:
            raise RuntimeError('injected_save_failure')
        obj = {'id': str(len(self.rows) + 1), 'model': model, 'fields': fields, 'content_types': content_types}
        self.rows.append(obj)
        return obj

    def matches(self, obj, fields, content_types):
        return obj['fields'] == fields and obj['content_types'] == content_types

    def check_membership(self, objects, nodes):
        adapter.require({o['id'] for o in objects.values()} == {o['id'] for o in self.rows}, 'fixture_membership')


def dataset():
    contract = copy.deepcopy(CONTRACT)
    contract['fixture'].update(locations=2, devices=3, interfaces_per_device=2, ip_assignments=3)
    return generator.dataset(contract)


def sample(t=0):
    return {'start': t, 'end': t + 1, 'boot_id': 'same-boot', 'mem_available_bytes': 2**32,
            'swap_used_bytes': 0, 'swap_in_out_counters': [0, 0], 'cpu_temperature_celsius': 50,
            'throttling_flags': 0, 'ext4_error_count': 0, 'diskstats': [0]*11,
            'kernel_storage_errors_since_cursor': 0, 'journal_cursor': 'cursor',
            'services': {r: {'pid': 100 + i, 'cgroup': '/test/' + r, 'memory_current': 100,
                            'memory_max': 1000, 'events': {'oom': 0, 'oom_kill': 0},
                            'unit': {'ActiveState': 'active', 'SubState': 'running', 'Result': 'success',
                                     'InvocationID': r, 'NRestarts': '0'}} for i, r in enumerate(sampler.ROLES)}}


class AdapterTests(unittest.TestCase):
    def test_default_dataset_plan_counts(self):
        nodes = adapter.plan(generator.dataset())
        self.assertEqual(sum(n['model'] == 'dcim.device' for n in nodes), CONTRACT['fixture']['devices'])
        self.assertEqual(sum(n['model'] == 'dcim.interface' for n in nodes), 2000)
        self.assertEqual(sum(n['model'] == 'ipam.ipaddresstointerface' for n in nodes), 500)

    def test_second_import_no_writes_and_three_exports_match(self):
        store = MemoryStore()
        first = adapter.apply(dataset(), store, write=True)
        writes = store.writes
        second = adapter.apply(dataset(), store, first['receipt'], write=True)
        self.assertEqual(first, second)
        self.assertEqual(writes, store.writes)
        for _ in range(3):
            self.assertEqual(adapter.apply(dataset(), store, first['receipt']), first)
        self.assertEqual(writes, store.writes)

    def test_unowned_collision_rolls_back_support_objects(self):
        store = MemoryStore()
        store.create('dcim.device', {'name': 'pilot-device-0001'}, None)
        before = copy.deepcopy(store.rows)
        with self.assertRaisesRegex(ValueError, 'unowned_object'):
            adapter.apply(dataset(), store, write=True)
        self.assertEqual(store.rows, before)

    def test_partial_failure_rolls_back(self):
        store = MemoryStore()
        store.fail_after = 10
        with self.assertRaises(RuntimeError):
            adapter.apply(dataset(), store, write=True)
        self.assertEqual(store.rows, [])

    def test_drift_missing_and_receipt_tampering_rejected(self):
        for mutation in ('drift', 'missing', 'receipt', 'extra'):
            with self.subTest(mutation=mutation):
                store = MemoryStore()
                first = adapter.apply(dataset(), store, write=True)
                if mutation == 'drift': store.rows[-2]['fields']['mask_length'] = 32
                if mutation == 'missing': store.rows.pop()
                if mutation == 'receipt': first['receipt']['objects']['namespace'] = 'unrelated'
                if mutation == 'extra': store.create('ipam.ipaddress', {'host': '198.18.2.1'}, None)
                writes = store.writes
                with self.assertRaises(ValueError):
                    adapter.apply(dataset(), store, first['receipt'])
                self.assertEqual(writes, store.writes)

    def test_fixture_scope_and_duplicates(self):
        for mutate in (lambda d: d['ip_assignments'][0].update(address='10.1.0.1/24'),
                       lambda d: d['devices'].append(d['devices'][0]),
                       lambda d: d['devices'][0].update(location='real-inventory'),
                       lambda d: d.update(namespace='Global')):
            value = dataset(); mutate(value)
            with self.assertRaises(ValueError): adapter.plan(value)


class SamplingTests(unittest.TestCase):
    def test_boundaries_and_each_stop_signal(self):
        first = sample()
        sampler.validate(first, first, None, CONTRACT)
        mutations = [lambda s: s.update(boot_id='other'), lambda s: s.update(start=16, end=17),
                     lambda s: s.update(end=21), lambda s: s.update(mem_available_bytes=1610612735),
                     lambda s: s.update(cpu_temperature_celsius=80.1), lambda s: s.update(throttling_flags=1),
                     lambda s: s.update(ext4_error_count=1), lambda s: s.update(kernel_storage_errors_since_cursor=1),
                     lambda s: s['services']['web']['events'].update(oom_kill=1),
                     lambda s: s['services']['web']['unit'].update(InvocationID='other'),
                     lambda s: s['services']['web']['unit'].update(ActiveState='failed'),
                     lambda s: s['services'].pop('worker'), lambda s: s.update(diskstats=[]),
                     lambda s: s.update(cpu_temperature_celsius=float('nan'))]
        for mutate in mutations:
            later = sample(5); mutate(later)
            with self.subTest(sample=later):
                with self.assertRaises(ValueError): sampler.validate(later, first, first, CONTRACT)
        edge = sample(15); edge.update(mem_available_bytes=1610612736, cpu_temperature_celsius=80)
        sampler.validate(edge, first, first, CONTRACT)

    def test_missing_metric_is_not_success(self):
        s = sample(); del s['services']['web']['events']['oom']
        with self.assertRaises(KeyError): sampler.validate(s, s, None, CONTRACT)

    def test_swap_growth_and_recovery(self):
        samples = [sample(t) for t in range(0, 1801, 5)]
        for s in samples:
            if 900 <= s['start'] < 1080:
                s['swap_used_bytes'] = (1 + (s['start'] - 900)//60) * 40 * 1024**2
        result = sampler.swap_review(samples, 900, 1800, CONTRACT)
        self.assertTrue(result['growth_failed']); self.assertTrue(result['recovered'])
        for s in samples:
            if s['start'] >= 1500: s['swap_used_bytes'] = 100 * 1024**2
        self.assertFalse(sampler.swap_review(samples, 900, 1800, CONTRACT)['recovered'])

    def test_collection_stops_on_failure_and_preserves_output(self):
        class Reader:
            def __init__(self): self.t = -5
            def sample(self):
                self.t += 5
                s = sample(self.t)
                if self.t == 10: s['kernel_storage_errors_since_cursor'] = 1
                return s
        reader, out = Reader(), io.BytesIO()
        with self.assertRaisesRegex(ValueError, 'storage_error'):
            sampler.collect(reader, CONTRACT, 20, out, clock=lambda: max(0, reader.t), sleep=lambda _: None)
        self.assertEqual(reader.t, 10)
        self.assertEqual(len(out.getvalue().splitlines()), 3)

    def test_reader_collects_selected_metrics_and_rejects_lost_cursor(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def put(path, value):
                p = root / path; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(value)
            put('proc/meminfo', 'MemAvailable: 4194304 kB\nSwapTotal: 1024 kB\nSwapFree: 1024 kB\n')
            put('proc/vmstat', 'pswpin 0\npswpout 0\n')
            put('proc/sys/kernel/random/boot_id', 'same-boot')
            put('proc/diskstats', '8 0 sda ' + ' '.join(['0']*11))
            put('sys/class/thermal/thermal_zone0/temp', '50000')
            put('sys/fs/ext4/sda2/errors_count', '0')
            for i, role in enumerate(sampler.ROLES):
                put(f'proc/{100+i}/cgroup', '0::/test/' + role)
                for file, value in [('memory.current', '100'), ('memory.max', '1000'), ('memory.events', 'oom 0\noom_kill 0\n')]:
                    put(f'sys/fs/cgroup/test/{role}/{file}', value)
            calls = []
            missing = False
            def runner(argv):
                calls.append(argv)
                if 'get_throttled' in argv: return 'throttled=0x0'
                if 'show' in argv:
                    return '\n\n'.join('\n'.join(k+'='+v for k, v in dict(Id='nautobot-'+r+'.service', **sample()['services'][r]['unit']).items()) for r in sampler.ROLES)
                if 'inspect' in argv:
                    self.assertIn('{{.Name}} {{.State.Pid}}', argv)
                    return '\n'.join('nautobot-'+r+' '+str(100+i) for i, r in enumerate(sampler.ROLES))
                if '--cursor' in argv:
                    return json.dumps({'__CURSOR': 'missing' if missing else 'cursor'})
                return json.dumps({'__CURSOR': 'next', 'MESSAGE': 'usb 2-1: reset SuperSpeed USB device'})
            reader = sampler.Reader('cursor', runner, root/'proc', root/'sys')
            result = reader.sample()
            self.assertEqual(result['kernel_storage_errors_since_cursor'], 1)
            self.assertEqual(result['services']['web']['memory_current'], 100)
            self.assertNotIn('SuperSpeed', json.dumps(result))
            self.assertEqual(reader.cursor, 'next')
            missing = True
            with self.assertRaisesRegex(ValueError, 'journal_coverage_gap'): reader.sample()

    def test_complete_coverage_is_not_whole_workload_acceptance(self):
        phases, end = [], 0
        for phase in CONTRACT['phases']:
            phases.append({'id': phase['id'], 'start': end, 'end': end + phase['minimum_seconds']})
            end = phases[-1]['end']
        samples = [sample(t) for t in range(0, end, 5)]
        result = sampler.review_samples(samples, phases, CONTRACT)
        self.assertTrue(result['resource_coverage_passed'])
        self.assertFalse(result['workload_accepted'])
        for partial in (samples[10:], samples[:-10], samples[:10] + samples[15:]):
            with self.assertRaises(ValueError): sampler.review_samples(partial, phases, CONTRACT)
        bad = copy.deepcopy(phases); bad[1]['start'] += 1
        with self.assertRaises(ValueError): sampler.review_samples(samples, bad, CONTRACT)

    def test_command_timeout_identifies_branch_without_exception_output(self):
        with patch.object(sampler.subprocess, 'run', side_effect=sampler.subprocess.TimeoutExpired('sensitive-command', 3, output=b'secret')):
            with self.assertRaises(sampler.CollectionFailure) as error:
                sampler.run(['/usr/bin/journalctl', '--after-cursor', 'private-cursor'])
        receipt = sampler.failure_receipt(error.exception)
        self.assertEqual(receipt['command_failure']['command'], 'kernel_window')
        self.assertEqual(receipt['command_failure']['category'], 'timeout')
        self.assertNotIn('secret', json.dumps(receipt))
        self.assertNotIn('private-cursor', json.dumps(receipt))

    def test_unexpected_exception_text_is_not_published(self):
        receipt = sampler.failure_receipt(RuntimeError('secret value'))
        self.assertEqual(receipt['reason'], 'collection_unavailable')
        self.assertNotIn('secret value', json.dumps(receipt))

    def test_output_cap_stops(self):
        c = copy.deepcopy(CONTRACT); c['limits']['collection_stream_bytes'] = 10
        class Reader:
            def sample(self): return sample()
        with self.assertRaisesRegex(ValueError, 'sample_output_limit'):
            sampler.collect(Reader(), c, 10, io.BytesIO(), clock=lambda: 0)


if __name__ == '__main__':
    unittest.main()
