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


if __name__ == '__main__':
    unittest.main()
