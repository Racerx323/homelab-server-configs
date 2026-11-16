import contextlib
import io
import json
import socket
import sys
import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location(
    'proxy_readiness', Path(__file__).parents[1] / 'scripts/inspect-proxy-readiness.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ProxyReadiness(unittest.TestCase):
    def test_projection_excludes_unselected_credentials(self):
        raw = b'port=10000\npassword=PRIVATE\nkey_passwd=PRIVATE\nssl=0\n'
        self.assertEqual(module.project(raw, module.SETTINGS['/etc/webmin/miniserv.conf']),
                         {'port': '10000', 'ssl': '0'})

    def test_referrer_controls_are_independently_reported(self):
        raw = b'referer=0\nreferers_none=1\nreferers=host.example.test\npassword=PRIVATE\n'
        result = module.project(raw, module.SETTINGS['/etc/webmin/config'])
        self.assertEqual(result, {'referer': '0', 'referers_none': '1', 'referers': 'host.example.test'})

    def test_duplicate_or_control_setting_rejected(self):
        for raw in (b'port=10000\nport=10001\n', b'port=10000\x1b\n'):
            with self.assertRaises(ValueError):
                module.project(raw, {'port'})

    def test_wrong_host_stops_before_config_or_commands(self):
        with mock.patch.object(module.socket, 'gethostname', return_value='other'), \
                mock.patch.object(module, 'inspect_file') as read, \
                mock.patch.object(module, 'command') as command:
            with self.assertRaisesRegex(ValueError, 'hostname_mismatch'):
                module.collect('expected', 'eth0')
            read.assert_not_called()
            command.assert_not_called()

    def run_cli(self, observed, expected='expected'):
        output = io.StringIO()
        with mock.patch.object(module.socket, 'gethostname', return_value=observed), \
                mock.patch.object(module, 'inspect_file') as read, \
                mock.patch.object(module, 'command') as command, \
                mock.patch.object(sys, 'argv', ['inspect', '--expected-hostname', expected,
                                                '--interface', 'eth0']), \
                contextlib.redirect_stdout(output):
            status = module.main()
            read.assert_not_called()
            command.assert_not_called()
        self.assertEqual(status, 1)
        self.assertLess(len(output.getvalue()), 1024)
        return json.loads(output.getvalue())

    def test_cli_reports_exact_names_without_accepting_short_fqdn_alias(self):
        result = self.run_cli('expected', 'expected.example.test')
        self.assertEqual(result['error'], 'hostname_mismatch')
        self.assertEqual(result['hostname_check'], {
            'source': 'socket.gethostname', 'expected': 'expected.example.test',
            'observed': 'expected', 'observed_status': 'reported'})
        self.assertFalse(result['mutation'])

    def test_cli_redacts_invalid_or_overlong_observed_names(self):
        for name in ['PRIVATE\nPASSWORD', 'PRIVATE\x1b[31m', 'x' * 254, '']:
            result = self.run_cli(name)
            self.assertIsNone(result['hostname_check']['observed'])
            self.assertEqual(result['hostname_check']['observed_status'], 'invalid_or_overlong')
            self.assertNotIn('PRIVATE', json.dumps(result))

    def test_actual_cli_mismatch_is_bounded_and_nonmutating(self):
        expected = 'intentional-mismatch' if socket.gethostname() != 'intentional-mismatch' else 'other'
        row = subprocess.run([sys.executable, '-I', '-B', str(Path(module.__file__)),
                              '--expected-hostname', expected, '--interface', 'eth0'],
                             capture_output=True, timeout=5)
        self.assertEqual(row.returncode, 1)
        self.assertEqual(row.stderr, b'')
        self.assertLess(len(row.stdout), 1024)
        result = json.loads(row.stdout)
        self.assertEqual(result['error'], 'hostname_mismatch')
        self.assertEqual(result['hostname_check']['expected'], expected)
        self.assertFalse(result['mutation'])

    def test_invalid_expected_hostname_is_not_echoed(self):
        result = self.run_cli('observed', 'PRIVATE\ninvalid')
        self.assertEqual(result['error'], 'invalid_expected_hostname')
        self.assertNotIn('hostname_check', result)
        self.assertNotIn('PRIVATE', json.dumps(result))

    def test_command_error_never_exposes_stderr(self):
        row = subprocess.CompletedProcess(['fixed'], 1, b'', b'PRIVATE diagnostic')
        with mock.patch.object(module.subprocess, 'run', return_value=row):
            result = module.command(['fixed'])
        self.assertEqual(result['exit'], 1)
        self.assertNotIn('PRIVATE', str(result))
        self.assertEqual(result['stderr_bytes'], 18)

    def test_timeout_and_output_limit_keep_no_raw_content(self):
        with mock.patch.object(module.subprocess, 'run',
                               side_effect=subprocess.TimeoutExpired(['fixed'], 8)):
            self.assertEqual(module.command(['fixed']), {'status': 'timeout'})
        row = subprocess.CompletedProcess(['fixed'], 0, b'x' * 65537, b'')
        with mock.patch.object(module.subprocess, 'run', return_value=row):
            self.assertEqual(module.command(['fixed']), {'status': 'output_limit', 'exit': 0})

    def test_interface_is_explicit_and_validated(self):
        with mock.patch.object(module, 'inspect_file') as read:
            with self.assertRaisesRegex(ValueError, 'invalid_interface'):
                module.collect('expected', '--all')
            read.assert_not_called()

    def test_selected_config_drift_rejects_capture(self):
        with mock.patch.object(module.socket, 'gethostname', return_value='expected'), \
                mock.patch.object(module.os, 'geteuid', return_value=0), \
                mock.patch.object(module.Path, 'read_text', return_value='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), \
                mock.patch.object(module, 'inspect_file', side_effect=[{}, {}, {}, {'changed': True}, {}, {}]), \
                mock.patch.object(module, 'command', return_value={'status': 'complete', 'exit': 0}):
            with self.assertRaisesRegex(ValueError, 'config_changed_during_inspection'):
                module.collect('expected', 'eth0')


class UnitIdentityTests(unittest.TestCase):
    def test_exact_installed_paths_are_hashed_without_content_projection(self):
        service = {'status': 'complete', 'exit': 0, 'stdout':
                   'FragmentPath=/usr/lib/systemd/system/webmin.service\n'
                   'DropInPaths=/etc/systemd/system/webmin.service.d/10-fleet-foundation.conf\n'}
        with mock.patch.object(module, 'inspect_file', return_value={'sha256': 'bound'}) as read:
            result = module.unit_identities(service)
        self.assertEqual(len(result), 2)
        self.assertTrue(all(call.args[1] == set() for call in read.call_args_list))

    def test_unexpected_paths_and_incomplete_properties_stop_before_reads(self):
        for props in ['', 'FragmentPath=/etc/shadow',
                      'FragmentPath=/etc/systemd/system/other.service',
                      'FragmentPath=/etc/systemd/system/webmin.service\nDropInPaths=/etc/webmin/miniserv.pem',
                      'FragmentPath=/etc/systemd/system/webmin.service\nDropInPaths=/etc/systemd/system/webmin.service.d/../private.conf']:
            with mock.patch.object(module, 'inspect_file') as read:
                with self.assertRaises(ValueError):
                    module.unit_identities({'status': 'complete', 'exit': 0, 'stdout': props})
                read.assert_not_called()
        with self.assertRaisesRegex(ValueError, 'unit_properties_unavailable'):
            module.unit_identities({'status': 'timeout'})

    def test_unit_identity_drift_rejects_capture(self):
        with mock.patch.object(module.socket, 'gethostname', return_value='expected'), \
                mock.patch.object(module.os, 'geteuid', return_value=0), \
                mock.patch.object(module.Path, 'read_text', return_value='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), \
                mock.patch.object(module, 'inspect_file', return_value={}), \
                mock.patch.object(module, 'command', return_value={'status': 'complete', 'exit': 0}), \
                mock.patch.object(module, 'unit_identities', side_effect=[{'a': 'old'}, {'a': 'new'}]):
            with self.assertRaisesRegex(ValueError, 'unit_changed_during_inspection'):
                module.collect('expected', 'eth0', True)

    def test_effective_control_change_rejects_capture(self):
        service_reads = 0

        def observation(argv):
            nonlocal service_reads
            if 'webmin.service' in argv:
                service_reads += 1
                return {'status': 'complete', 'exit': 0, 'stdout': f'MemoryMax={service_reads}'}
            return {'status': 'complete', 'exit': 0, 'stdout': ''}

        with mock.patch.object(module.socket, 'gethostname', return_value='expected'), \
                mock.patch.object(module.os, 'geteuid', return_value=0), \
                mock.patch.object(module.Path, 'read_text', return_value='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), \
                mock.patch.object(module, 'inspect_file', return_value={}), \
                mock.patch.object(module, 'command', side_effect=observation), \
                mock.patch.object(module, 'unit_identities', return_value={'a': 'unchanged'}):
            with self.assertRaisesRegex(ValueError, 'service_changed_during_inspection'):
                module.collect('expected', 'eth0', True)


if __name__ == '__main__':
    unittest.main()
