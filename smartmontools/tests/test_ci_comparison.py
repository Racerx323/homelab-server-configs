#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import sys
import unittest

p = Path(__file__).resolve().parents[1] / 'scripts/compare-ci-smartctl.py'
spec = importlib.util.spec_from_file_location('comparison', p)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class Comparison(unittest.TestCase):
    def test_same_explicit_nvme_type_and_read_only_query_for_both_binaries(self):
        commands = [m.query_argv(binary) for binary in
                    ('/usr/sbin/smartctl', '/var/tmp/fixture/smartctl')]
        self.assertEqual(commands[0][1:], commands[1][1:])
        for argv in commands:
            self.assertEqual(argv[argv.index('-d') + 1], 'sntjmicron')
            self.assertEqual(argv[argv.index('-l') + 1], 'selftest')
            self.assertEqual(argv[-1], '/dev/sda')
            self.assertNotIn('-t', argv)
            self.assertNotIn('-X', argv)
            self.assertNotIn('sat', argv)

    def test_candidate_modes_never_send_combined_option_to_installed_binary(self):
        spec = {'queries': 6, 'observation_after_each_seconds': 75,
                'maximum_trial_seconds': 900, 'production_package_or_configuration_changes': False,
                'self_test_start': False, 'comparison_mode': 'candidate_device_types',
                'expected_bcd_device': '0213'}
        plan = m.query_plan(spec, '/candidate/smartctl')
        self.assertEqual(len(plan), 6)
        self.assertEqual([row[2] for row in plan], ['sntjmicron', 'sat/sntjmicron'] * 3)
        for _, binary, mode in plan:
            self.assertEqual(binary, '/candidate/smartctl')
            self.assertNotIn('-t', m.query_argv(binary, mode))
        for key, value in [('queries', 7), ('expected_bcd_device', '9999'),
                           ('observation_after_each_seconds', 30), ('comparison_mode', 'auto'),
                           ('self_test_start', True)]:
            with self.assertRaises(ValueError): m.query_plan(dict(spec, **{key: value}), '/candidate')
        with self.assertRaises(ValueError): m.query_argv('/candidate', 'sat')

    def test_attribution_is_two_candidate_reads_with_all_ioctl_diagnostics(self):
        spec = {'queries': 2, 'observation_after_each_seconds': 75,
                'maximum_trial_seconds': 900, 'production_package_or_configuration_changes': False,
                'self_test_start': False, 'comparison_mode': 'candidate_detection_attribution',
                'expected_bcd_device': '0213'}
        plan = m.query_plan(spec, '/candidate')
        self.assertEqual([row[2] for row in plan], ['sntjmicron', 'sat/sntjmicron'])
        for _, binary, mode in plan:
            argv = m.query_argv(binary, mode, attribution=True)
            self.assertEqual(binary, '/candidate')
            self.assertEqual(argv[argv.index('-r') + 1], 'ioctl,2')
            self.assertNotIn('-t', argv)
            self.assertNotIn('-T', argv)
        with self.assertRaises(ValueError):
            m.query_plan(dict(spec, queries=6), '/candidate')

    def test_descriptor_requires_unique_matching_bridge_and_valid_revision(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)
            for name, value in [('idVendor', '152d'), ('idProduct', '0583'), ('bcdDevice', '0213')]:
                (p/name).write_text(value)
            self.assertEqual(m.bridge_descriptor([p])['bcdDevice'], '0213')
            with self.assertRaises(ValueError): m.bridge_descriptor([p, p])
            (p/'bcdDevice').write_text('unknown')
            with self.assertRaises(ValueError): m.bridge_descriptor([p])

    def test_exit_mask_all_bits_and_combinations(self):
        self.assertEqual(m.exit_bits(0), [])
        for bit, label in enumerate(m.FLAGS):
            self.assertEqual(m.exit_bits(1 << bit), [label])
        self.assertEqual(m.exit_bits(255), m.FLAGS)
        self.assertEqual(m.exit_bits(-9), ['signal_or_timeout'])

    def test_stop_on_any_error_or_drift(self):
        m.require_continue(0, False, True)
        for code, event, unchanged in [(1 << b, False, True) for b in range(8)] + [(0, True, True), (0, False, False)]:
            with self.assertRaises(ValueError):
                m.require_continue(code, event, unchanged)

    def test_command_timeout_and_bounded_capture(self):
        code, out, err = m.run([sys.executable, '-c', 'import sys;print("ok");sys.exit(8)'])
        self.assertEqual((code, out, err), (8, b'ok\n', b''))
        with self.assertRaises(TimeoutError):
            m.run([sys.executable, '-c', 'import time;time.sleep(2)'], seconds=.1)
        with self.assertRaisesRegex(ValueError, 'output_limit'):
            m.run([sys.executable, '-c', 'import sys;sys.stdout.write("x"*5000000)'])

    def test_missing_cursor_and_delayed_error(self):
        from unittest.mock import patch
        token = 'fixture'
        with patch.object(m, 'checked', side_effect=['{"__CURSOR":"other"}\n']):
            with self.assertRaisesRegex(ValueError, 'cursor_coverage_missing'):
                m.storage_since(token)
        with patch.object(m, 'checked', side_effect=['{"__CURSOR":"fixture"}\n', '{"MESSAGE":"reset SuperSpeed USB device"}\n']):
            self.assertTrue(m.storage_since(token)[1])
        with patch.object(m, 'checked', side_effect=['{"__CURSOR":"fixture"}\n', '{"MESSAGE":"usb 2-1: USB disconnect, device number 2"}\n']):
            self.assertTrue(m.storage_since(token)[1])


if __name__ == '__main__':
    unittest.main()
