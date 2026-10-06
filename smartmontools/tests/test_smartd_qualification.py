#!/usr/bin/env python3
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]/'scripts'


def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS/(name+'.py'))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


m = load('qualify-smartd')
controller = load('execute-smartd-qualification')


class Qualification(unittest.TestCase):
    def test_exact_config_rejects_schedules_scans_alerts_and_extra_devices(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d)/'config'
            path.write_text('# comment\n/dev/sda -d sntjmicron -l selftest\n')
            m.validate_config(path)
            for extra in [' -s S/../.././02', ' -m root', '\nDEVICESCAN', '\n/dev/sdb -a']:
                path.write_text('/dev/sda -d sntjmicron -l selftest'+extra)
                with self.assertRaises(ValueError):
                    m.validate_config(path)

    def test_foreground_and_all_destinations_are_private(self):
        root = Path('/var/tmp/private')
        args = m.argv_for(root)
        self.assertEqual(args[args.index('-q')+1], 'onecheck')
        self.assertIn('-d', args)
        # Pinned smartd rejects -d with -p; debug mode writes no PID file.
        self.assertNotIn('-p', args)
        self.assertFalse(any(arg.startswith('--pidfile') for arg in args))
        for flag in ('-c', '-B', '-s', '-A', '-j'):
            self.assertTrue(args[args.index(flag)+1].startswith(str(root)+'/'))

    def test_candidate_timeout_preserves_partial_output_and_confirms_exit(self):
        with tempfile.TemporaryDirectory() as d:
            r = m.run_candidate([sys.executable, '-c',
                                 'import time;print("started",flush=True);time.sleep(10)'], Path(d), seconds=.2)
            self.assertIn('candidate_deadline', r['failure'])
            self.assertTrue(r['candidate_exited'])
            self.assertEqual((Path(d)/'stdout').read_text(), 'started\n')

    def test_output_limit_preserves_bounded_diagnostics(self):
        with tempfile.TemporaryDirectory() as d:
            r = m.run_candidate([sys.executable, '-c', 'print("x"*100000)'], Path(d), limit=100)
            self.assertIn('candidate_output_limit', r['failure'])
            self.assertTrue(r['candidate_exited'])
            self.assertEqual((Path(d)/'stdout').stat().st_size, 100)

    def test_closed_streams_do_not_bypass_deadline(self):
        with tempfile.TemporaryDirectory() as d:
            r = m.run_candidate([sys.executable, '-c',
                                 'import os,time;os.close(1);os.close(2);time.sleep(10)'], Path(d), seconds=.2)
            self.assertIn('candidate_deadline', r['failure'])
            self.assertTrue(r['candidate_exited'])

    def test_notifications_environment_is_not_inherited(self):
        with tempfile.TemporaryDirectory() as d, patch.dict('os.environ', {'NOTIFY_SOCKET': '/test', 'SMARTD_ADDRESS': 'bad'}):
            r = m.run_candidate([sys.executable, '-c', 'import os,json;print(json.dumps(dict(os.environ)))'], Path(d))
            self.assertEqual(r['exit_status'], 0)
            env = json.loads((Path(d)/'stdout').read_text())
            self.assertNotIn('NOTIFY_SOCKET', env)
            self.assertNotIn('SMARTD_ADDRESS', env)

    def test_exit_zero_alone_is_not_admission_and_zero_state_is_omitted(self):
        r = {'exit_status': 0, 'candidate_exited': True, 'failure': None}
        text = 'NVMe Adding to "monitor" list. All devices successfully checked once.'
        state = '# smartd state file\ntemperature-min = 30\n'
        self.assertTrue(m.assess(r, text, state))
        for badtext, badstate in [('', state), (text, ''), (text+' Read Self-test Log failed', state),
                                  (text, state+'self-test-errors = 1\n')]:
            self.assertFalse(m.assess(r, badtext, badstate))
        for code in (1, 2, 16, 17, 254, -9):
            self.assertFalse(m.assess(dict(r, exit_status=code), text, state))
        self.assertFalse(m.assess(dict(r, failure='timeout'), text, state))

    def test_expired_or_future_baseline_stops_before_target_inspection(self):
        for now in (99, 3701):
            with self.assertRaisesRegex(ValueError, 'baseline_expired'):
                m.preflight(None, {'epoch': 100}, now=now)

    def test_manifest_authorization_and_payload_tamper_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            names = ['execute-smartd-qualification.py', 'qualify-smartd.py', 'compare-ci-smartctl.py',
                     'smartd', 'smartd.conf', 'empty.drivedb', 'baseline.json', 'specification.json', 'PROCEDURE.md']
            for name in names:
                (root/name).write_text('fixture')
            manifest = {'files': {n: hashlib.sha256((root/n).read_bytes()).hexdigest() for n in names}}
            raw = json.dumps(manifest).encode()
            (root/'manifest.json').write_bytes(raw)
            digest = hashlib.sha256(raw).hexdigest()
            self.assertEqual(len(controller.verify(root, digest)[1]), len(names))
            with patch.object(controller.subprocess, 'run') as run:
                run.return_value.returncode = 0
                self.assertEqual(controller.main(root, digest), 0)
                self.assertEqual(run.call_count, 1)
                self.assertIn('StrictHostKeyChecking=yes', run.call_args.args[0])
                self.assertIn(b'qualify-smartd.py', run.call_args.kwargs['input'])
                with self.assertRaises(FileExistsError):
                    controller.main(root, digest)
                self.assertEqual(run.call_count, 1)
            with self.assertRaisesRegex(ValueError, 'authorization_hash'):
                controller.verify(root, '0'*64)
            (root/'smartd.conf').write_text('changed')
            with self.assertRaisesRegex(ValueError, 'bundle_file'):
                controller.verify(root, digest)

    def test_repeated_dispatch_and_control_are_bound_to_recorded_trial(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            names = ['execute-smartd-qualification.py', 'qualify-smartd.py', 'compare-ci-smartctl.py',
                     'observe-smartd.py', 'smartd-observation-control.py', 'smartd', 'smartd.conf',
                     'empty.drivedb', 'baseline.json', 'specification.json', 'PROCEDURE.md']
            for name in names:
                (root/name).write_text('fixture')
            manifest = {'scope':'candidate_smartd_repeated_checks',
                        'files':{n:hashlib.sha256((root/n).read_bytes()).hexdigest() for n in names}}
            raw = json.dumps(manifest).encode()
            (root/'manifest.json').write_bytes(raw)
            digest = hashlib.sha256(raw).hexdigest()
            with patch.object(controller.subprocess, 'run') as run:
                run.return_value.returncode = 0
                controller.main(root, digest)
                self.assertIn(b'REPEATED=True', run.call_args.kwargs['input'])
                (root/'controller-evidence/stdout').write_text('{"remote_evidence":"/var/tmp/smartd-observation.abcdefgh"}\n')
                run.return_value.stdout = b'{"state":"running"}\n'
                run.return_value.stderr = b''
                self.assertEqual(controller.control(root, digest, 'status', '/var/tmp/smartd-observation.abcdefgh'), 0)
                count = run.call_count
                for action, remote in [('cancel','/var/tmp/smartd-observation.otherone'),
                                       ('status','/var/tmp/smartd-observation.abcdefgh/..'),
                                       ('start','/var/tmp/smartd-observation.abcdefgh')]:
                    with self.assertRaises(ValueError):
                        controller.control(root, digest, action, remote)
                self.assertEqual(run.call_count, count)


if __name__ == '__main__':
    unittest.main()
