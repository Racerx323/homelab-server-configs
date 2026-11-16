"""Offline phase-reader bounds; no browser or target contacts."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('observer', Path(__file__).with_name('observe-browser-memory.py'))
observer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(observer)


class PhaseTests(unittest.TestCase):
    def test_safe_last_phase_and_missing_trace(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'trace'
            self.assertEqual(observer.phase(path), 'before-browser')
            path.write_text('{"stage":"launch"}\n{"stage":"trusted-referrer"}\n')
            self.assertEqual(observer.phase(path), 'trusted-referrer')

    def test_unknown_nonstring_and_partial_data_are_not_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'trace'
            for value in ['private-canary', ['login'], None, 7]:
                path.write_text(json.dumps({'stage': value}))
                self.assertEqual(observer.phase(path), 'invalid-phase')
            for raw in ['{"stage":', '[]', 'null']:
                path.write_text(raw)
                self.assertEqual(observer.phase(path), 'before-browser')

    def test_oversize_trace_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'trace'
            path.write_text('x'*20000)
            self.assertEqual(observer.phase(path), 'trace-oversize')


class WorkloadTests(unittest.TestCase):
    def test_paired_matrix_precedes_sustained_concurrency(self):
        batches = observer.workload_batches(True)
        self.assertEqual([args for batch in batches[:4] for _, args in batch],
                         [[family, node, 'short'] for node in ['a', 'b'] for family in ['ipv4', 'ipv6']])
        self.assertIsNone(batches[4][0][1])
        self.assertEqual([args for _, args in batches[-1]],
                         [['ipv4', 'a', 'sustained'], ['ipv6', 'b', 'sustained']])
        self.assertEqual(len({name for batch in batches for name, _ in batch}), 7)
        self.assertEqual(observer.workload_batches(False), [[('ipv4', ['ipv4'])]])

    def test_failed_client_and_limits_contain_without_retry(self):
        sample = {'memory.events.local': 'high 100\nmax 0\noom 0\noom_kill 0\n',
                  'memory.current': '100000', 'ancestors': {}}
        self.assertIsNone(observer.stop_reason(sample, [None, 0], 419, 100))
        self.assertEqual(observer.stop_reason(sample, [1, None], 10, 100), 'workload-failed')
        self.assertEqual(observer.stop_reason(sample, [None], 420, 100), 'deadline')
        self.assertEqual(observer.stop_reason(sample, [], 10, 24*1024*1024+1), 'evidence-bound')
        for event in ['max', 'oom', 'oom_kill', 'oom_group_kill']:
            sample['ancestors'] = {'parent': {'memory.events.local': f'{event} 1\n'}}
            self.assertEqual(observer.stop_reason(sample, [], 10, 100), 'hard-limit-or-oom-event')
        sample['ancestors'] = {}
        sample['memory.current'] = 'unavailable:FileNotFoundError'
        self.assertEqual(observer.stop_reason(sample, [], 10, 100), 'cgroup-disappeared')


if __name__ == '__main__':
    unittest.main()
