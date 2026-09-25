#!/usr/bin/env python3
"""Offline controller lifecycle and logout-preparation boundaries."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT/'Nautobot/ansible/scripts'
sys.path.insert(0, str(SCRIPTS))
import workload_controller as controller


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS/filename)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


launcher = load('launcher', 'run-workload.py')
persistence = load('persistence', 'persistence-preflight.py')


class Controller(unittest.TestCase):
    def test_unit_parser_and_no_automatic_replay(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            # Test the authoritative service parser while keeping fixture files
            # temporary. Production renderer rejects volatile evidence paths.
            with patch.object(controller, 'persistent_path', side_effect=controller.safe_path):
                unit = controller.render(root, 'a'*64, root/'evidence', root/'agent')
            path = root/'test.service'; path.write_text(unit)
            result = subprocess.run(['systemd-analyze', 'verify', str(path)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            for expected in ('Restart=no', 'RuntimeMaxSec=12000', 'KillMode=control-group',
                             'RuntimeDirectoryPreserve=no', 'ExecStopPost=', 'ConditionPathExists=!',
                             'StandardOutput=null', 'StandardError=null'):
                self.assertIn(expected, unit)
            self.assertNotIn('[Install]', unit)

    def test_volatile_and_unsafe_evidence_rejected(self):
        for path in ('/tmp/evidence', '/run/user/1000/evidence', '/var/tmp/evidence'):
            with self.assertRaisesRegex(ValueError, 'volatile_evidence'):
                controller.persistent_path(Path(path))
        for path in ('relative', '/home/user/%h', '/home/user/$HOME', '/home/user/../evidence'):
            with self.assertRaises(ValueError): controller.safe_path(Path(path))
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, 'supervised_controller_required'):
                controller.runtime('a'*64)

    def test_missing_linger_refuses_before_credentials(self):
        expected = Path('/run/user')/str(os.getuid())/controller.identity('a'*64)
        with patch.dict(os.environ, {'RUNTIME_DIRECTORY':str(expected),'INVOCATION_ID':'b'*32}), patch.object(controller,'private_directory'), patch.object(controller.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'no\n','')):
            with self.assertRaisesRegex(ValueError,'controller_linger_or_runtime_filesystem'):
                controller.runtime('a'*64)

    def test_exit_failure_cleanup_and_durable_receipts(self):
        for code in (0, 2, None):
            with self.subTest(code=code), tempfile.TemporaryDirectory() as temp:
                root = Path(temp); evidence = root/'evidence'; runtime = root/'runtime'; runtime.mkdir(mode=0o700)
                bundle = root/'bundle'; bundle.mkdir()
                (bundle/'application-backup.json').write_text(json.dumps({'repository_url': '/fixture'}))
                values = []
                def reader(*args):
                    value = bytearray(b'private-fixture'); values.append(value); return value
                original = launcher.resolved_credentials
                def credentials(bundle, evidence, runtime=None):
                    return original(bundle, evidence, reader, runtime)
                def execute(*args):
                    self.assertEqual(len(list(runtime.iterdir())), 1)
                    if code is None: raise TimeoutError('must not be stored')
                    return code
                argv = ['run-workload.py','--bundle',str(bundle),'--approve','a'*64,
                        '--evidence',str(evidence),'--resolve-doppler']
                with patch.object(sys,'argv',argv), patch.object(launcher,'verify',return_value=({}, {'operation_id':'fixture','root':'/tmp/fixture'})), patch.object(controller,'runtime',return_value=runtime), patch.object(controller,'persistent_path',side_effect=controller.safe_path), patch.dict(os.environ,{'INVOCATION_ID':'b'*32}), patch.object(launcher,'resolved_credentials',side_effect=credentials), patch.object(launcher,'execute',side_effect=execute):
                    if code is None:
                        with self.assertRaises(TimeoutError): launcher.main()
                    else: self.assertEqual(launcher.main(), code)
                    record = json.loads((evidence/'controller-result.json').read_text())
                    self.assertEqual(record['status'], 'incomplete' if code is None else 'collected' if code == 0 else 'failed')
                    self.assertEqual(record['acceptance'], 'requires_independent_review')
                    controller.record_stop('a'*64, evidence)
                    with self.assertRaises(FileExistsError): controller.record_stop('a'*64, evidence)
                self.assertEqual(list(runtime.iterdir()), [])
                self.assertTrue(all(not any(value) for value in values))
                for path in evidence.iterdir():
                    self.assertEqual(path.stat().st_mode & 0o777, 0o600)
                    self.assertNotIn('private-fixture', path.read_text())
                    self.assertNotIn('must not be stored', path.read_text())

    def test_manager_receipt_after_missing_finalizer_does_not_claim_cleanup(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            controller.receipt(root/'controller-started.json', {'approval':'a'*64,'invocation_id':'b'*32})
            with patch.object(controller,'persistent_path',side_effect=controller.safe_path), patch.dict(os.environ,{'INVOCATION_ID':'b'*32,'SERVICE_RESULT':'signal','EXIT_CODE':'killed','EXIT_STATUS':'KILL'}):
                controller.record_stop('a'*64, root)
            result = json.loads((root/'controller-stop.json').read_text())
            self.assertEqual(result['service_result'], 'signal')
            self.assertEqual(result['runtime_cleanup'], 'verify_absence_after_unit_stops')
            self.assertFalse((root/'controller-result.json').exists())


class Persistence(unittest.TestCase):
    def test_linger_service_drift_and_manual_session_gate(self):
        data = {'persistence_user':{'UID':'999','Linger':'yes'}, 'guard':{'verified':True},
                'persistence_services':{role:{'ActiveState':'active','SubState':'running','Result':'success',
                                             'InvocationID':'fixture','NRestarts':'0'} for role in persistence.ROLES}}
        result = persistence.assess(data)
        self.assertTrue(result['preconditions_observed'])
        self.assertFalse(result['accepted'])
        self.assertTrue(result['session_ownership_review_required'])
        data['persistence_user']['Linger']='no'
        data['persistence_services']['web']['InvocationID']=''
        self.assertEqual(persistence.assess(data)['gaps'], ['service_user_or_linger','service_identity_web'])


if __name__ == '__main__': unittest.main()
