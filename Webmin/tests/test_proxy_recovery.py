"""Recovery correctness only: temporary files and injected native-command results."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('recovery', Path(__file__).parents[1] / 'scripts/recover-proxy.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class Recovery(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.work = self.root / 'work'
        self.work.mkdir()
        self.configs = tuple(str(self.root / n) for n in ['miniserv', 'config'])
        self.added = tuple(str(self.root / n) for n in ['ingress', 'guard-unit', 'dropin'])
        self.preserved = (str(self.root / 'foundation'),)
        self.events = []
        for name in self.configs + self.preserved:
            Path(name).write_text('before-' + Path(name).name)
            Path(name).chmod(0o600)
        for key, value in [('CONFIGS', self.configs), ('ADDED', self.added)]:
            patch = mock.patch.object(m, key, value)
            patch.start(); self.addCleanup(patch.stop)
        # Simulate root ownership only; real bytes/modes and atomic replacement run.
        def identity(path):
            m.safe_path(path)
            return {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                    'uid': 0, 'gid': 0, 'mode': path.stat().st_mode & 0o777}
        for patch in [mock.patch.object(m, 'identity', side_effect=identity),
                      mock.patch.object(m.os, 'fchown'),
                      mock.patch.object(m.socket, 'gethostname', return_value='target'),
                      mock.patch.object(m, 'run', side_effect=self.run_native),
                      mock.patch.object(m, 'controls', return_value={'test': 'unchanged'}),
                      mock.patch.object(m, 'preserved_paths', return_value=set(self.preserved)),
                      mock.patch.object(m, 'loopback', side_effect=lambda: self.events.append('loopback'))]:
            patch.start(); self.addCleanup(patch.stop)
        self.binding = {'hostname': 'target', 'controls': {'test': 'unchanged'}, 'files': {p: identity(Path(p)) for p in self.configs + self.preserved}}
        self.table = False

    def run_native(self, *args, **kwargs):
        self.events.append(args)
        if args[0].endswith('nft') and args[-2:] == ('list', 'tables'):
            return json.dumps({'nftables': [{'table': {'family': 'inet', 'name': 'webmin'}}] if self.table else []})
        if 'delete' in args:
            self.table = False
        if 'is-active' in args:
            return 'active\n'
        if 'is-enabled' in args:
            return 'enabled\n'
        if 'MainPID' in args:
            return '0\n'
        return ''

    def prepare_mutation(self):
        m.snapshot(self.work, self.binding)
        state = json.loads((self.work / 'state.json').read_text())
        state['phase'] = 'mutating'
        m.save(self.work / 'state.json', state)
        for p in self.configs + self.added:
            Path(p).write_text('trial')
        self.table = True
        self.events.clear()

    def test_restore_before_guard_removal_preserves_controls(self):
        self.prepare_mutation()
        m.restore(self.work)
        first_probe = self.events.index('loopback')
        deletion = self.events.index(('/usr/sbin/nft', 'delete', 'table', 'inet', 'webmin'))
        self.assertLess(first_probe, deletion)
        self.assertEqual(self.events[0], ('/usr/bin/systemctl', 'stop', 'webmin.service'))
        for name in self.configs + self.preserved:
            self.assertEqual(m.identity(Path(name)), self.binding['files'][name])
        self.assertFalse(any(Path(p).exists() for p in self.added))
        self.assertEqual(json.loads((self.work / 'state.json').read_text())['phase'], 'restored')
        self.assertFalse(any('uptime' in str(row) or 'flush' in str(row) for row in self.events))

    def test_bad_backup_never_stops_service_or_removes_guard(self):
        self.prepare_mutation()
        (self.work / 'config-0.before').write_text('corrupt')
        with self.assertRaisesRegex(ValueError, 'backup_identity_mismatch'):
            m.restore(self.work)
        self.assertEqual(self.events, [])
        self.assertTrue(self.table)

    def test_failed_loopback_retains_guard_and_incomplete_state(self):
        self.prepare_mutation()
        with mock.patch.object(m, 'loopback', side_effect=ValueError('loopback_http_failed')), \
                mock.patch.object(m.time, 'monotonic', side_effect=[0, 31]):
            with self.assertRaisesRegex(ValueError, 'loopback_http_failed'):
                m.restore(self.work)
        self.assertTrue(self.table)
        self.assertTrue(Path(self.added[0]).exists())
        self.assertEqual(json.loads((self.work / 'state.json').read_text())['phase'], 'recovery-incomplete')
        self.assertNotIn(('/usr/sbin/nft', 'delete', 'table', 'inet', 'webmin'), self.events)

    def test_preserved_control_drift_stops_before_recovery(self):
        self.prepare_mutation()
        Path(self.preserved[0]).write_text('other owner changed control')
        with self.assertRaisesRegex(ValueError, 'preserved_file_drift') as caught:
            m.restore(self.work)
        self.assertEqual(caught.exception.details['path'], self.preserved[0])
        self.assertNotEqual(caught.exception.details['expected']['sha256'], caught.exception.details['observed']['sha256'])
        self.assertEqual(self.events, [])
        self.assertTrue(self.table)

    def test_prepared_without_mutation_does_not_restart(self):
        m.snapshot(self.work, self.binding)
        self.events.clear()
        m.restore(self.work)
        self.assertEqual(self.events, [('/usr/sbin/nft', '--json', 'list', 'tables'), 'loopback'])

    def test_preexisting_guard_and_reused_snapshot_are_rejected(self):
        self.table = True
        with self.assertRaisesRegex(ValueError, 'preexisting_webmin_table'):
            m.snapshot(self.work, self.binding)
        self.table = False
        m.snapshot(self.work, self.binding)
        with self.assertRaisesRegex(ValueError, 'snapshot_already_exists'):
            m.snapshot(self.work, self.binding)

    def test_symlink_backup_rejected_before_native_actions(self):
        self.prepare_mutation()
        path = self.work / 'config-0.before'
        path.unlink(); path.symlink_to(self.configs[0])
        with self.assertRaisesRegex(ValueError, 'symlink_path'):
            m.restore(self.work)
        self.assertEqual(self.events, [])

    def test_cancel_before_mutation_verifies_baseline_and_rejects_later_drift(self):
        m.snapshot(self.work, self.binding)
        m.restore(self.work)
        self.assertEqual(json.loads((self.work/'state.json').read_text())['phase'], 'cancelled')
        self.assertIn('loopback', self.events)
        Path(self.configs[0]).write_text('drift')
        with self.assertRaisesRegex(ValueError, 'preserved_file_drift'):
            m.restore(self.work)

    def test_cancelled_or_restored_trial_cannot_apply_late(self):
        m.snapshot(self.work, self.binding)
        m.restore(self.work)
        self.assertEqual(json.loads((self.work / 'state.json').read_text())['phase'], 'cancelled')
        self.events.clear()
        with self.assertRaisesRegex(ValueError, 'apply_state_mismatch'):
            m.apply(self.work)
        self.assertEqual(self.events, [])

    def test_restored_receipt_does_not_mask_later_drift(self):
        self.prepare_mutation()
        m.restore(self.work)
        Path(self.configs[0]).write_text('later drift')
        with self.assertRaisesRegex(ValueError, 'preserved_file_drift'):
            m.restore(self.work)

    def test_effective_control_drift_rejects_even_when_files_match(self):
        with mock.patch.object(m, 'controls', return_value={'test': 'drift'}):
            with self.assertRaisesRegex(ValueError, 'effective_service_control_drift'):
                m.snapshot(self.work, self.binding)
        self.assertFalse((self.work / 'state.json').exists())

    def test_absent_transient_apply_unit_is_not_a_recovery_failure(self):
        row = subprocess.CompletedProcess(['systemctl'], 1, b'not-found\n', b'')
        with mock.patch.object(m.subprocess, 'run', return_value=row):
            m.stop_apply()
        self.assertEqual(self.events, [])

    def test_unknown_transient_unit_state_does_not_silently_pass(self):
        row = subprocess.CompletedProcess(['systemctl'], 1, b'loaded\n', b'PRIVATE')
        with mock.patch.object(m.subprocess, 'run', return_value=row):
            with self.assertRaises(m.NativeFailure):
                m.stop_apply()
        self.assertEqual(self.events, [])

    def test_guard_reverse_ordering_edge_is_temporary_not_general_drift(self):
        expected = {'After': 'base.service', 'MemoryMax': '192'}
        with mock.patch.object(m, 'controls', return_value={
                'After': 'base.service webmin-firewall.service', 'MemoryMax': '192'}):
            m.verify_controls(expected, guard_still_loaded=True)
        with mock.patch.object(m, 'controls', return_value={
                'After': 'base.service other.service', 'MemoryMax': '192'}):
            with self.assertRaises(ValueError):
                m.verify_controls(expected, guard_still_loaded=True)

    def test_native_failure_contains_no_output(self):
        # The source function is retained separately below from the patched fixture.
        row = subprocess.CompletedProcess(['systemctl'], 1, b'PRIVATE', b'SECRET')
        with mock.patch.object(m.subprocess, 'run', return_value=row):
            with self.assertRaises(m.NativeFailure) as caught:
                original_run('/usr/bin/systemctl', 'start', 'webmin.service')
        self.assertEqual(caught.exception.details['exit_status'], 1)
        self.assertNotIn('PRIVATE', str(caught.exception.details))
        self.assertNotIn('SECRET', str(caught.exception.details))


original_run = m.run

if __name__ == '__main__':
    unittest.main()
