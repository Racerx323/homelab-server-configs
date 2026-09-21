#!/usr/bin/env python3
"""Offline failure injection into the real initialization boundary and launcher."""
import sys
sys.dont_write_bytecode = True
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2]
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod
init=load('init',ROOT/'restic/scripts/initialize-repository.py')
launcher=load('launcher',ROOT/'Nautobot/ansible/scripts/run-restic-initialization.py')
VERSION='restic 0.18.0 compiled with go1.24.4 on linux/arm64'
URL='s3:https://example.invalid/test/'
class Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.calls=[]
        for name,value in {'repository':URL,'password':'test-password','credentials.json':json.dumps({'id':'fixture-id','key':'fixture-key'})}.items():
            p=self.root/name;p.write_text(value);p.chmod(0o600)
    def tearDown(self):self.temp.cleanup()
    def run_case(self,absence=10,init_rc=0,readback=0,config=None,locks=b'',fail=None):
        answers=[(0,VERSION.encode()),(absence,b'ignored'),(init_rc,b'ignored'),(readback,json.dumps(config or {'version':2,'id':'a'*64}).encode()),(0,locks)]
        def runner(argv,env):
            self.calls.append(argv)
            self.assertEqual(env['AWS_ACCESS_KEY_ID'],'fixture-id')
            if len(self.calls)==fail:raise init.Blocked('command_timeout')
            return answers[len(self.calls)-1]
        return init.initialize(self.root,URL,VERSION,runner)
    def test_success_no_replay(self):
        self.assertEqual(self.run_case()['result'],'initialized_review_required')
        with self.assertRaises(FileExistsError):self.run_case()
        self.assertEqual(len(self.calls),5)
    def test_ambiguous_absence(self):
        for rc in (0,1,11,12,130):
            for p in self.root.glob('*.json'):
                if p.name!='credentials.json':p.unlink()
            self.calls=[]
            self.assertFalse(self.run_case(absence=rc)['mutation_attempted'])
            self.assertEqual(len(self.calls),2)
            self.assertFalse((self.root/'init-attempt.json').exists())
    def test_init_failure(self):
        result=self.run_case(init_rc=1)
        self.assertTrue(result['mutation_attempted']);self.assertEqual(result['init_exit_status'],1)
        self.assertEqual(len(self.calls),3)
    def test_partial_initialization(self):
        result=self.run_case(fail=3)
        self.assertTrue(result['mutation_attempted']);self.assertIsNone(result['init_exit_status'])
        self.assertTrue((self.root/'init-attempt.json').exists())
        self.assertFalse((self.root/'init-result.json').exists())
    def test_readback_failure(self):
        result=self.run_case(readback=1)
        self.assertEqual(result['result'],'blocked');self.assertEqual(result['init_exit_status'],0)
        self.assertEqual(len(self.calls),4)
    def test_bad_config(self):self.assertEqual(self.run_case(config={'version':1,'id':'bad'})['error_class'],'readback_invalid')
    def test_lock_residue(self):self.assertEqual(self.run_case(locks=b'lock\n')['result'],'blocked')
    def test_unsafe_inputs(self):
        p=self.root/'password';p.chmod(0o644)
        with self.assertRaises(init.Blocked):self.run_case()
        p.unlink();p.symlink_to(self.root/'repository')
        with self.assertRaises(init.Blocked):self.run_case()
        self.assertEqual(self.calls,[])
    def test_sanitized_records(self):
        self.run_case()
        for p in self.root.glob('*.json'):
            if p.name!='credentials.json':
                for secret in ('test-password','fixture-id','fixture-key'):self.assertNotIn(secret,p.read_text())
    def test_inactive_gate_precedes_secret_access(self):
        with patch.object(launcher.common,'read_secret',side_effect=AssertionError('must not resolve')):
            with self.assertRaises(launcher.common.PreflightBlocked):launcher.execute('0'*64)
    def test_archived_absence_binding(self):
        import copy
        import yaml
        schema=json.loads((ROOT/'Nautobot/schemas/operation.schema.json').read_text())
        branch=next(b for b in schema['oneOf'] if b.get('title')=='Reviewed standalone Restic initialization')
        document={key:copy.deepcopy(value['const']) for key,value in branch['properties'].items()}
        proof=document['preflight']['terminal_proof']
        raw=(ROOT/'Nautobot/manifests/restic-preflight-result.json').read_bytes()
        with patch.object(launcher.subprocess,'check_output',side_effect=[
            b'tag\n', (proof['archive_commit']+'\n').encode(), raw]):
            launcher.require_preflight(document)
        document['preflight']['terminal_proof']['result_sha256']='0'*64
        with self.assertRaisesRegex(launcher.common.PreflightBlocked,'fresh_absence_proof_invalid'):
            launcher.require_preflight(document)

    def test_initialization_contract_scope(self):
        import copy
        from jsonschema import Draft202012Validator
        schema=json.loads((ROOT/'Nautobot/schemas/operation.schema.json').read_text())
        branch=next(b for b in schema['oneOf'] if b.get('title')=='Reviewed standalone Restic initialization')
        document={key:copy.deepcopy(value['const']) for key,value in branch['properties'].items()}
        validator=Draft202012Validator(branch)
        validator.validate(document)
        for section,key,value in [('repository','bucket','other'),
                                  ('preflight','state','pending'),
                                  ('failure_and_recovery','automatic_init_retry',True)]:
            changed=copy.deepcopy(document);changed[section][key]=value
            self.assertFalse(validator.is_valid(changed))

    def test_production_always_cleanup_with_local_ansible(self):
        import copy
        import subprocess
        import yaml
        play=yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/initialize-restic-repository.yaml').read_text())[0]
        cleanup=copy.deepcopy(play['tasks'][2]['always'])
        for task in cleanup:
            if 'ansible.builtin.command' in task:
                # Only transport/identity adapter: production cleanup commands unchanged.
                task['ansible.builtin.command']['argv']=task['ansible.builtin.command']['argv'][6:]
        for failed, cleanup_failure in ((False,False),(True,False),(False,True)):
            with self.subTest(failed=failed, cleanup_failure=cleanup_failure), tempfile.TemporaryDirectory() as directory:
                root=Path(directory)
                for name in ('repository','password','credentials.json'):
                    (root/name).write_text('offline-secret')
                attempt=copy.deepcopy(cleanup)
                if cleanup_failure:
                    # Reachable-target failure in the first real cleanup task.
                    attempt[0]['ansible.builtin.command']['argv']=['/bin/false']
                fixture=[{'hosts':'localhost','gather_facts':False,
                    'vars':{'restic_init_directory':{'stdout':str(root)},'restic_init_evidence_root':str(root)},
                    'tasks':[{'block':[{'ansible.builtin.command':{'argv':['/bin/false' if failed else '/bin/true']}}], 'always':attempt}]}]
                path=root/'fixture.yaml';path.write_text(yaml.safe_dump(fixture))
                result=subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','-i','localhost,','-c','local',str(path)],capture_output=True,timeout=60)
                self.assertEqual(result.returncode,2 if failed or cleanup_failure else 0,result.stdout.decode()+result.stderr.decode())
                for name in ('password','credentials.json'):self.assertFalse((root/name).exists())
                self.assertEqual((root/'repository').exists(),cleanup_failure)
                self.assertTrue((root/'node-records.json').exists())
                self.assertNotIn(b'offline-secret',result.stdout+result.stderr)

    def test_controller_secret_cleanup_after_failure(self):
        c=launcher.common;root,fd=c.prepare_evidence([],'0'*64)
        try:
            with patch.object(c,'read_secret',side_effect=lambda *a:bytearray(b'fixture')),patch.object(c,'drain_process',side_effect=c.PreflightBlocked('ansible_timeout')):
                with self.assertRaises(c.PreflightBlocked):c.run_preflight(root,fd)
            self.assertFalse((root/'protected-extra-vars.json').exists());self.assertFalse((root/'ansible-local').exists())
        finally:
            os.close(fd)
            import shutil
            shutil.rmtree(root)
if __name__=='__main__':unittest.main()
