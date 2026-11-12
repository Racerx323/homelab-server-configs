#!/usr/bin/env python3
"""Failure receipts and finite-parent headroom; native lifecycle tested separately."""
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch
from contextlib import ExitStack

spec = importlib.util.spec_from_file_location('observer', Path(__file__).parents[1] / 'scripts/observe-needrestart.py')
observer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(observer)


def sample(host=800000, parent=None, when=1):
    return {'host_available_kib': host, 'monotonic_seconds': when,
            'ancestors': {'slice': {'headroom_bytes': parent}}}


class ReserveTests(unittest.TestCase):
    def test_large_host_does_not_hide_finite_parent_shortfall(self):
        self.assertFalse(observer.has_reserve(sample(parent=observer.RESERVE - 1)))
        self.assertTrue(observer.has_reserve(sample(parent=observer.RESERVE)))

    def test_unlimited_parent_does_not_hide_host_shortfall(self):
        self.assertFalse(observer.has_reserve(sample(host=98303)))
        self.assertTrue(observer.has_reserve(sample(host=98304)))

    def test_transient_admission_boundaries(self):
        for mib in (160, 416):
            threshold = mib * 1024
            for kib, accepted in ((threshold-1, False), (threshold, True), (threshold+1, True)):
                self.assertEqual(observer.has_reserve(sample(host=kib), mib * 1024 * 1024), accepted)
            self.assertFalse(observer.has_reserve(sample(parent=mib*1024*1024-1), mib*1024*1024))

    def test_existing_unit_is_not_stopped_or_adopted(self):
        with tempfile.TemporaryDirectory() as name:
            with patch.object(Path, 'lstat', return_value=SimpleNamespace(st_mode=0o40700, st_uid=0)), \
                    patch.object(observer, 'properties', return_value={'LoadState': 'loaded'}), \
                    patch.object(observer, 'command') as commands:
                with self.assertRaisesRegex(ValueError, 'already exists'):
                    observer.observe(Path(name))
                commands.assert_not_called()

    def test_pre_scan_gate_includes_scan_cap_after_observer_is_resident(self):
        with tempfile.TemporaryDirectory() as name:
            with patch.object(Path, 'lstat', return_value=SimpleNamespace(st_mode=0o40700, st_uid=0)), \
                    patch.object(observer, 'properties', return_value={'LoadState': 'not-found'}), \
                    patch.object(observer, 'snapshot', return_value=sample(host=196607)), \
                    patch.object(observer, 'command') as commands, patch('builtins.print'):
                self.assertEqual(observer.observe(Path(name)), 1)
                commands.assert_not_called()
            receipt = json.loads((Path(name) / 'observation.json').read_text())
            self.assertIn('96 MiB scan plus 96 MiB reserve', receipt['error'])

    def test_mid_scan_reserve_failure_retains_samples_and_stops_owned_unit(self):
        with tempfile.TemporaryDirectory() as name:
            with patch.object(Path, 'lstat', return_value=SimpleNamespace(st_mode=0o40700, st_uid=0)), \
                    patch.object(observer, 'properties', side_effect=[
                        {'LoadState': 'not-found'}, {'ActiveState': 'activating', 'SubState': 'start'},
                        {'LoadState': 'not-found'}]), \
                    patch.object(observer, 'snapshot', side_effect=[sample(), sample(parent=1, when=2)]), \
                    patch.object(observer, 'command', return_value='') as commands, \
                    patch('builtins.print'):
                self.assertEqual(observer.observe(Path(name)), 1)
            receipt = json.loads((Path(name) / 'observation.json').read_text())
            self.assertFalse(receipt['accepted'])
            self.assertEqual(len(receipt['samples']), 2)
            self.assertIn('reserve below', receipt['error'])
            self.assertIn(unittest.mock.call(['systemctl', 'stop', observer.UNIT]), commands.call_args_list)

    def test_cleanup_failure_cannot_be_reported_as_acceptance(self):
        terminal = {'ActiveState': 'active', 'SubState': 'exited', 'Result': 'success',
                    'ExecMainStatus': '0', 'MemoryPeak': '1000000', 'MemorySwapPeak': '0', 'MainPID': '0'}
        with tempfile.TemporaryDirectory() as name:
            with patch.object(Path, 'lstat', return_value=SimpleNamespace(st_mode=0o40700, st_uid=0)), \
                    patch.object(observer, 'properties', side_effect=[{'LoadState': 'not-found'},
                        {'ActiveState': 'activating', 'SubState': 'start', 'MainPID': '42'}, terminal]), \
                    patch.object(observer, 'snapshot', side_effect=[sample(), sample(when=2), sample(when=3)]), \
                    patch.object(observer, 'command', side_effect=['', TimeoutError('stop timeout')]), \
                    patch('builtins.print'):
                self.assertEqual(observer.observe(Path(name)), 1)
            receipt = json.loads((Path(name) / 'observation.json').read_text())
            self.assertFalse(receipt['accepted'])
            self.assertIn('stop timeout', receipt['cleanup_error'])


class ObserverFailureTests(unittest.TestCase):
    def test_native_failure_delayed_sampling_and_producer_command(self):
        cases = [
            ({'ActiveState': 'failed', 'SubState': 'failed', 'Result': 'timeout'}, 1.2, False, 'native scan failure'),
            ({'ActiveState': 'activating', 'SubState': 'start', 'MainPID': '3'}, 2.1, False, 'sample gap'),
            ({'ActiveState': 'failed', 'SubState': 'failed', 'Result': 'timeout'}, 1.2, True, 'native scan failure'),
        ]
        for state, when, producer, expected in cases:
            with self.subTest(producer=producer, when=when), tempfile.TemporaryDirectory() as name:
                with patch.object(Path, 'lstat', return_value=SimpleNamespace(st_mode=0o40700, st_uid=0)), \
                        patch.object(observer, 'properties', side_effect=[{'LoadState': 'not-found'}, state, {'LoadState': 'not-found'}]), \
                        patch.object(observer, 'snapshot', side_effect=[sample(), sample(when=when)]), \
                        patch.object(observer, 'command', return_value='') as commands, \
                        patch.dict(observer.os.environ, {'RECIPIENT': 'fixture@example.invalid'}), patch('builtins.print'):
                    self.assertEqual(observer.observe(Path(name), producer), 1)
                receipt = json.loads((Path(name) / 'observation.json').read_text())
                self.assertIn(expected, receipt['error'])
                launch = commands.call_args_list[0].args[0]
                self.assertIn('--property=TimeoutStartSec=' + ('420s' if producer else '90s'), launch)
                if producer:
                    self.assertEqual(launch[-2:], ['/bin/bash', '/usr/local/sbin/needrestart.sh'])
                self.assertIn(unittest.mock.call(['systemctl', 'stop', observer.UNIT]), commands.call_args_list)


class GuardTests(unittest.TestCase):
    def run_guard(self, host=800000, parent=None, failure=None, producer=False):
        with tempfile.TemporaryDirectory() as name, ExitStack() as stack:
            directory = Path(name)
            stack.enter_context(patch.object(Path, 'lstat', return_value=SimpleNamespace(st_mode=0o40700, st_uid=0)))
            stack.enter_context(patch.object(observer.os, 'open', return_value=7))
            stack.enter_context(patch.object(observer.os, 'close'))
            stack.enter_context(patch.object(observer.os, 'fstat', return_value=SimpleNamespace(st_mode=0o100600, st_uid=0)))
            stack.enter_context(patch.object(observer.fcntl, 'flock', side_effect=BlockingIOError() if failure == 'overlap' else None))
            stack.enter_context(patch.object(observer, 'snapshot', return_value=sample(host, parent)))
            state = {'LoadState': 'loaded' if failure == 'existing' else 'not-found',
                     'MainPID': '0', 'ActiveState': 'inactive'}
            stack.enter_context(patch.object(observer, 'properties', return_value=state))
            stack.enter_context(patch.object(observer, 'command', return_value=''))
            stack.enter_context(patch.dict(observer.os.environ, {'RECIPIENT': 'fixture@example.invalid'}))
            stack.enter_context(patch('builtins.print'))

            def execute(argv, **kwargs):
                if failure == 'observer_timeout':
                    raise observer.subprocess.TimeoutExpired(argv, 135)
                if failure != 'missing':
                    (directory / 'observation.json').write_text(json.dumps({'accepted': failure != 'observer', 'samples': []}))
                return SimpleNamespace(returncode=1 if failure == 'observer' else 0, stderr='fixture')

            run = stack.enter_context(patch.object(observer.subprocess, 'run', side_effect=execute))
            rc = observer.guarded(directory, producer)
            receipt = json.loads((directory / 'guard.json').read_text())
            return rc, receipt, run.call_args_list

    def test_outer_gate_boundaries(self):
        for kib, expected in [(229375, 1), (229376, 0), (229377, 0)]:
            with self.subTest(kib=kib):
                rc, result, calls = self.run_guard(host=kib)
                self.assertEqual(rc, expected)
                self.assertEqual(bool(calls), not expected)
                self.assertEqual(result['before_observer']['host_available_kib'], kib)

    def test_finite_parent_fails_before_launch(self):
        rc, result, calls = self.run_guard(parent=224 * 1024 * 1024 - 1)
        self.assertEqual(rc, 1)
        self.assertFalse(calls)

    def test_overlap_and_existing_unit_fail_without_launch(self):
        for failure in ['overlap', 'existing']:
            rc, result, calls = self.run_guard(failure=failure)
            self.assertEqual(rc, 1)
            self.assertFalse(calls)
            self.assertNotIn('cleanup', result)

    def test_observer_failure_and_deadline_are_not_accepted(self):
        for failure in ['observer', 'observer_timeout']:
            rc, result, calls = self.run_guard(failure=failure)
            self.assertEqual(rc, 1)
            self.assertFalse(result['accepted'])
            self.assertIn('cleanup', result)

    def test_producer_lifetime_is_not_diagnostic_lifetime(self):
        rc, result, calls = self.run_guard(producer=True)
        self.assertEqual(rc, 0)
        argv = calls[0].args[0]
        self.assertIn('--property=RuntimeMaxSec=440s', argv)
        self.assertIn('--producer', argv)
        self.assertIn('--setenv=RECIPIENT=fixture@example.invalid', argv)

    def test_missing_observation_cannot_pass(self):
        rc, receipt, calls = self.run_guard(failure='missing')
        self.assertEqual(rc, 1)
        self.assertIn('FileNotFoundError', receipt['error'])
        self.assertIn('cleanup', receipt)


if __name__ == '__main__':
    unittest.main()
