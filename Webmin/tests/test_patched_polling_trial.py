import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'patched', Path(__file__).parents[1] / 'scripts/patched-polling-trial.py')
trial = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trial)


class PatchedTrialTests(unittest.TestCase):
    def test_retained_profile_requires_exact_version_kernel_and_unchanged_source(self):
        op = {'package_version': '7.5-test', 'kernel': 'test-kernel',
              'sources': [{'before': 'bytes', 'after': 'bytes'}]}
        trial.retained_profile(op, '7.5-test', 'test-kernel')
        for package, kernel in [('7.4-test', 'test-kernel'), ('7.5-test', 'other-kernel')]:
            with self.assertRaises(RuntimeError):
                trial.retained_profile(op, package, kernel)
        op['sources'][0]['after'] = 'changed'
        with self.assertRaisesRegex(RuntimeError, 'retained_source_mutation_forbidden'):
            trial.retained_profile(op, '7.5-test', 'test-kernel')

    def test_only_reviewed_smart_queries_allowed(self):
        self.assertEqual(trial.classify(['-A', '-l', 'error', '/dev/sda']), 'attributes')
        for argv in [['-a', '/dev/sda'], ['-x', '/dev/sda'],
                     ['-A', '-l', 'selftest', '/dev/sda'], ['-H', '/dev/sdb']]:
            with self.assertRaisesRegex(RuntimeError, 'unexpected_smart_arguments'):
                trial.classify(argv)

    def test_trace_success_requires_actual_zero_exit(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            pending, counts = {}, dict.fromkeys(['attributes'], 0)
            trial.trace_line('[pid 123] 1780000000.0 execve("/usr/sbin/smartctl", '
                             '["smartctl", "-A", "-l", "error", "/dev/sda"], 0) = 0',
                             pending, counts, root)
            self.assertEqual(counts['attributes'], 0)
            trial.trace_line('[pid 123] 1780000000.1 exit_group(0) = ?', pending, counts, root)
            self.assertEqual(counts['attributes'], 1)
            self.assertEqual(pending, {})

    def test_munin_pid_change_recorded_but_outage_rejected(self):
        before = {'munin-node.service': {'ActiveState': 'active', 'MainPID': '12'}}
        after = {'munin-node.service': {'ActiveState': 'active', 'MainPID': '13'}}
        self.assertEqual(len(trial.service_check(after, before)), 1)
        after['munin-node.service']['ActiveState'] = 'failed'
        with self.assertRaisesRegex(RuntimeError, 'monitoring_service_unavailable'):
            trial.service_check(after, before)

    def test_shutoff_restores_override_and_refuses_unrelated_edit(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            config = root / 'config'
            enabled = 'collect_interval=5\n'
            disabled = enabled + 'collect_notemp=1\n'
            config.write_text(enabled)
            config.chmod(0o600)
            info = config.stat()
            (root / 'operation.json').write_text(json.dumps({
                'disabled_config': disabled, 'enabled_config': enabled,
                'config_metadata': {'uid': info.st_uid, 'gid': info.st_gid, 'mode': 0o600}}))
            with patch.object(trial.guard, 'CONFIG', config):
                trial.disable(root)
                self.assertEqual(config.read_text(), disabled)
                trial.disable(root)
                config.write_text(enabled + 'unrelated=1\n')
                with self.assertRaisesRegex(RuntimeError, 'config_conflict'):
                    trial.disable(root)
                self.assertIn('unrelated=1', config.read_text())


if __name__ == '__main__':
    unittest.main()
