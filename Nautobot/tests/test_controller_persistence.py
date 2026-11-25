#!/usr/bin/env python3
"""Offline controller lifecycle and logout-preparation boundaries."""
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import shutil
import time
import uuid
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
    def test_explicit_ansible_identity_and_drift(self):
        with tempfile.TemporaryDirectory() as temporary:
            executable = Path(temporary)/'executable'
            executable.write_text('#!/bin/sh\nexit 0\n'); executable.chmod(0o700)
            binding = {'path':str(executable), 'sha256':hashlib.sha256(executable.read_bytes()).hexdigest()}
            self.assertEqual(controller.ansible_executable(binding), str(executable))
            with self.assertRaisesRegex(ValueError, 'controller_ansible_identity'):
                controller.ansible_executable(dict(binding, sha256='0'*64))

    @unittest.skipUnless(os.environ.get('NAUTOBOT_CONTROLLER_SYSTEMD_TEST') == '1',
                         'opt-in local user-systemd qualification; no target contact')
    def test_real_service_wrapper_and_ansible(self):
        evidence_root = Path(os.environ['NAUTOBOT_CONTROLLER_EVIDENCE'])
        evidence_root.mkdir(mode=0o700, exist_ok=False)
        executable = Path(shutil.which('ansible-playbook')).resolve()
        binding = {'path':str(executable), 'sha256':hashlib.sha256(executable.read_bytes()).hexdigest()}
        for case, expected in [('success', 0), ('ansible_failure', 2), ('binary_drift', 43)]:
            with self.subTest(case=case), tempfile.TemporaryDirectory(prefix='nautobot-controller-local-') as temporary:
                work = Path(temporary)
                approval = hashlib.sha256(uuid.uuid4().bytes).hexdigest()
                name = controller.identity(approval)+'.service'
                evidence = evidence_root/case
                tree = work/'tree'
                (tree/'inventory/prod').mkdir(parents=True)
                (tree/'inventory/prod/hosts.yaml').write_text('all:\n  hosts:\n    j2-svpi4mf:\n      ansible_connection: local\n      ansible_python_interpreter: /usr/bin/python3\n')
                (tree/'Nautobot/ansible').mkdir(parents=True)
                shutil.copyfile(ROOT/'Nautobot/ansible/ansible.cfg', tree/'Nautobot/ansible/ansible.cfg')
                (tree/'tests/repository').mkdir(parents=True)
                shutil.copyfile(ROOT/'tests/repository/run-with-ansible-local-temp.sh', tree/'tests/repository/run-with-ansible-local-temp.sh')
                bundle = work/'bundle'; bundle.mkdir()
                task = ('ansible.builtin.fail:\n        msg: qualification_expected_failure' if case == 'ansible_failure'
                        else "ansible.builtin.command:\n        argv: ['/usr/bin/true']")
                (bundle/'run-workload.yaml').write_text('- hosts: all\n  gather_facts: false\n  tasks:\n    - ansible.builtin.assert:\n        that: ansible_connection == "local"\n    - '+task+'\n')
                selected = dict(binding, sha256='0'*64) if case == 'binary_drift' else binding
                probe = work/'probe.py'
                probe.write_text(f'''import sys, os, json, importlib.util
from pathlib import Path
from types import SimpleNamespace
sys.path.insert(0, {str(SCRIPTS)!r})
import workload_controller as controller
spec = importlib.util.spec_from_file_location('launcher', {str(SCRIPTS/'run-workload.py')!r})
launcher = importlib.util.module_from_spec(spec); spec.loader.exec_module(launcher)
launcher.ROOT = Path({str(tree)!r})
evidence = Path({str(evidence)!r}); evidence.mkdir(mode=0o700)
runtime = controller.runtime({approval!r})
controller.receipt(evidence/'controller-started.json', {{'approval':{approval!r}, 'invocation_id':os.environ['INVOCATION_ID']}})
secrets = runtime/'disposable'; secrets.mkdir(mode=0o700)
for name in ('repository','password','credentials.json'):
    path=secrets/name; path.write_text('disposable-local-input'); path.chmod(0o600)
code = 43
try:
    code = launcher.execute(SimpleNamespace(bundle=Path({str(bundle)!r}), evidence=evidence, backup_secrets=secrets),
        {{'files':{{}}}}, {{'root':'/tmp/localhost-only', 'execution_authorized':False, 'controller_ansible':{selected!r}}})
except ValueError as error:
    controller.receipt(evidence/'refusal.json', {{'reason':str(error)}})
finally:
    for path in secrets.iterdir(): path.unlink()
    secrets.rmdir()
    controller.receipt(evidence/'qualification.json', {{'status':code, 'fixture_credentials_removed':not secrets.exists(), 'path':os.environ['PATH']}})
raise SystemExit(code)
''')
                unit = controller.render(bundle, approval, evidence, work/'unused-agent')
                unit = '\n'.join('ExecStart=/usr/bin/python3 '+str(probe) if line.startswith('ExecStart=') else line for line in unit.splitlines())+'\n'
                unit = unit.replace('RuntimeMaxSec=12000', 'RuntimeMaxSec=60').replace('UMask=0077', 'UMask=0077\nEnvironment=PATH=/usr/bin:/bin')
                path = work/name; path.write_text(unit)
                (evidence_root/(case+'.service')).write_text(unit)
                try:
                    subprocess.run(['systemctl','--user','link',str(path)], check=True, capture_output=True)
                    subprocess.run(['systemctl','--user','start',name], check=True, capture_output=True)
                    deadline = time.monotonic()+90
                    while time.monotonic() < deadline:
                        show = subprocess.run(['systemctl','--user','show',name,'--property=ActiveState,Result,ExecMainStatus'], check=True, capture_output=True, text=True)
                        state = dict(line.split('=',1) for line in show.stdout.splitlines())
                        if state['ActiveState'] in ('inactive','failed'): break
                        time.sleep(1)
                    else: self.fail('local_service_timeout')
                    (evidence/'service-state.json').write_text(json.dumps(state))
                    self.assertEqual(int(state['ExecMainStatus']), expected)
                    self.assertTrue(json.loads((evidence/'qualification.json').read_text())['fixture_credentials_removed'])
                    self.assertTrue((evidence/'controller-stop.json').is_file())
                    self.assertFalse((Path('/run/user')/str(os.getuid())/controller.identity(approval)).exists())
                    if case == 'binary_drift':
                        self.assertFalse((evidence/'ansible.stdout').exists())
                        self.assertEqual(json.loads((evidence/'refusal.json').read_text())['reason'], 'controller_ansible_identity')
                    else:
                        output = (evidence/'ansible.stdout').read_text()
                        self.assertIn('PLAY RECAP', output)
                        self.assertIn('j2-svpi4mf', output)
                        self.assertNotIn('disposable-local-input', output)
                finally:
                    subprocess.run(['systemctl','--user','stop',name], capture_output=True)
                    subprocess.run(['systemctl','--user','disable',name], check=True, capture_output=True)
                    subprocess.run(['systemctl','--user','reset-failed',name], capture_output=True)
                    self.assertFalse((Path.home()/'.config/systemd/user'/name).is_symlink())

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
    def test_loginctl_property_selection(self):
        observed = []
        def command(argv):
            observed.append(argv)
            if 'show-user' in argv:
                flags = [argv[i+1] for i, x in enumerate(argv[:-1]) if x == '-p']
                self.assertEqual(flags, ['UID','Linger','State','Sessions'])
                return 'UID=999\nLinger=yes\nState=lingering\nSessions=1\n'
            if 'list-sessions' in argv: return '1 999 nautobot manager-early'
            return 'ActiveState=active\nSubState=running\nResult=success\nInvocationID=fixture\nNRestarts=0\n'
        with patch.object(persistence.baseline,'collect',return_value={'boot_id':'fixture','guard':{'verified':True}}), patch.object(persistence.baseline,'command',side_effect=command), patch.object(Path,'read_text',return_value='fixture'):
            result = persistence.collect()
        self.assertTrue(result['persistence_review']['preconditions_observed'])
        self.assertEqual(result['persistence_user']['Sessions'],'1')

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
