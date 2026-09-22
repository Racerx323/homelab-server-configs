#!/usr/bin/env python3
"""Offline initialization-only production path, parser and failure tests."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode=True
import tempfile
import unittest
from unittest.mock import patch
import yaml
from quadlet_tool import resolve
ROOT=Path(__file__).resolve().parents[2]

def load(name,path):
    spec=importlib.util.spec_from_file_location(name,ROOT/path)
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod

renderer=load('renderer','Nautobot/ansible/scripts/render-runtime.py')
application=load('application','Nautobot/ansible/scripts/initialize-application.py')
node=load('node','Nautobot/ansible/scripts/runtime-initialization-node.py')
launcher=load('launcher','Nautobot/ansible/scripts/run-runtime.py')

class Initialization(unittest.TestCase):
    def setUp(self):
        schema=json.loads((ROOT/'Nautobot/schemas/runtime-initialization.schema.json').read_text())
        self.op={k:copy.deepcopy(v['const']) for k,v in schema['properties'].items()}
        self.desired=yaml.safe_load((ROOT/'Nautobot/manifests/desired-state.yaml').read_text())
        self.inputs=json.loads((ROOT/'Nautobot/manifests/runtime-inputs.json').read_text())

    def test_selected_units_and_real_generator(self):
        files=renderer.render(self.desired,self.inputs,True)
        self.assertEqual(len(files),6)
        self.assertFalse(any(x in n for n in files for x in ('web','worker','scheduler','media')))
        self.assertFalse(any('PublishPort=' in t for t in files.values()))
        migration=files['nautobot-migration.container']
        self.assertIn('Entrypoint=python3',migration)
        self.assertIn('--memory=1536m',migration)
        self.assertIn('--memory-swap=1536m',migration)
        self.assertIn('TimeoutStartSec=900',migration)
        self.assertNotIn('WantedBy=',migration)
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp);u=path/'units';u.mkdir();out=path/'out';out.mkdir()
            for n,t in files.items():(u/n).write_text(t)
            result=subprocess.run([str(resolve()),'--user',str(out)],env={**os.environ,'QUADLET_UNIT_DIRS':str(u)},capture_output=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stderr.decode())
            for role in ('postgresql','redis','migration'):self.assertTrue((out/f'nautobot-{role}.service').exists())
            self.assertFalse((out/'nautobot-web.service').exists())
            text=(out/'nautobot-migration.service').read_text()
            self.assertIn('/run/initialize-application.py',text)
            self.assertIn('--memory=1536m',text)

    def test_native_sequence_and_stop_at_each_failure(self):
        for failure in (None,0,1,2,3):
            with self.subTest(failure=failure):
                calls=[]
                def runner(argv,timeout):
                    i=len(calls);calls.append(argv);self.assertLessEqual(timeout,840)
                    return {'exit_status':1 if i==failure else 0,'output_limited':False}
                result=application.initialize(runner,inspect=False)
                self.assertEqual(result['passed'],failure is None)
                self.assertEqual(len(calls),4 if failure is None else failure+1)
                self.assertEqual(calls,[['nautobot-server']+argv for _,argv in application.STEPS][:len(calls)])
                self.assertFalse(any('createsuperuser' in c for c in calls))

    def test_native_timeout_and_output_limit(self):
        for response in ({'exit_status':None,'error':'timeout'},{'exit_status':0,'output_limited':True}):
            self.assertFalse(application.initialize(lambda *_:response,inspect=False)['passed'])
        response=application.command([sys.executable,'-c','import time;time.sleep(2)'],0.05)
        self.assertEqual(response['error'],'timeout')
        self.assertTrue(application.command([sys.executable,'-c','import os;os.write(1,b"x"*5000000)'],5)['output_limited'])

    def test_startup_failure_has_safe_specific_code(self):
        with patch.object(application.Path,'read_text',side_effect=['1610612736','0']), \
             patch.object(application.os,'getuid',return_value=1000), \
             patch.object(application.tempfile,'TemporaryFile',side_effect=PermissionError('private details')):
            result=application.initialize()
        self.assertEqual(result['error'],'writable_git')
        self.assertFalse(result['migration_attempted'])
        self.assertNotIn('private details',json.dumps(result))

    def receipt(self):
        v=application.initialize(lambda *_:{'exit_status':0,'output_limited':False},inspect=False)
        v.update(memory_limit_bytes=1610612736,swap_limit_bytes=0,uid=1000)
        return v

    def test_receipt_is_strict_and_failure_remains_identifiable(self):
        receipt=self.receipt()
        encode=lambda v:json.dumps({'MESSAGE':application.PREFIX+json.dumps(v)})+'\n'
        self.assertTrue(node.migration_receipt(encode(receipt))['passed'])
        bad=copy.deepcopy(receipt);bad['passed']=False;bad['steps']['post_upgrade']['exit_status']=1
        with self.assertRaisesRegex(ValueError,'native_initialization_failed'):node.migration_receipt(encode(bad))
        sanitized=node.migration_receipt(encode(bad),False)
        self.assertEqual(sanitized['steps']['post_upgrade']['exit_status'],1)
        receipt['raw_secret']='must-not-appear'
        self.assertNotIn('must-not-appear',json.dumps(node.migration_receipt(encode(receipt))))
        for raw in ('',encode(receipt)*2,'{truncated'):
            with self.assertRaises((ValueError,json.JSONDecodeError)):node.migration_receipt(raw)

    def test_private_container_checks(self):
        v={'Image':'sha256:abc','State':{'Running':True,'Health':{'Status':'healthy'}},
           'HostConfig':{'Memory':1536*1024**2,'PortBindings':{}},
           'NetworkSettings':{'Ports':{'5432/tcp':None},'Networks':{'nautobot-private':{}}},
           'Mounts':[{'Type':'volume','Name':'nautobot-postgresql_data','Destination':'/var/lib/postgresql/data'}]}
        self.assertTrue(node.container_evidence(v,'postgresql','abc')['private'])
        for mutate in (lambda x:x['HostConfig'].update(Memory=0),lambda x:x['NetworkSettings'].update(Ports={'5432/tcp':[{'HostPort':'5432'}]}),lambda x:x['State'].update(Running=False),lambda x:x.update(Mounts=[])):
            bad=copy.deepcopy(v);mutate(bad)
            with self.assertRaises(ValueError):node.container_evidence(bad,'postgresql','abc')

    def test_bad_bundle_never_executes(self):
        with tempfile.TemporaryDirectory() as tmp:
            op=copy.deepcopy(self.op);op['runtime']['rendered_directory']=tmp
            files=renderer.render(self.desired,self.inputs,True)
            # Synthetic current-render fixture; preserve consumed historical hashes.
            op['runtime']['artifact_sha256']={n:hashlib.sha256(t.encode()).hexdigest() for n,t in files.items()}
            for n,t in files.items():(Path(tmp)/n).write_text(t)
            with patch.object(launcher,'validate',return_value=op), patch.object(launcher.bounded,'drain_process',side_effect=AssertionError('must not execute')):
                with self.assertRaisesRegex(launcher.bounded.PreflightBlocked,'bundle_hash_mismatch'):launcher.execute('0'*64)
            (Path(tmp)/'nautobot-migration.container').write_text('tampered')
            with self.assertRaisesRegex(launcher.bounded.PreflightBlocked,'artifact_hash_mismatch'):launcher.bundle_rows(op)

    def test_archived_prerequisites_without_live_git_dependency(self):
        def git(argv,**kwargs):
            args=argv[3:]
            if args[0]=='status':return b''
            for proof in self.op['prerequisites']:
                if proof['tag'] in ' '.join(args):
                    if args[0]=='cat-file':return b'tag'
                    if args[0]=='rev-parse':return proof['commit'].encode()
                    if args[0]=='show':return (ROOT/proof['path']).read_bytes()
            raise AssertionError(args)
        # Exercise prerequisite mechanics against explicit current fixture hashes;
        # consumed initialization inputs must not track evolving desired state.
        op=copy.deepcopy(self.op)
        op['input_sha256']={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest()
                            for name in op['input_sha256']}
        with patch.object(launcher.subprocess,'check_output',side_effect=git):
            launcher.verify_prerequisites(op)
            op['input_sha256']['Nautobot/manifests/desired-state.yaml']='0'*64
            with self.assertRaisesRegex(launcher.bounded.PreflightBlocked,'accepted_input_drift'):
                launcher.verify_prerequisites(op)

    def test_prerequisite_record_drift(self):
        op=copy.deepcopy(self.op);op['prerequisites'][0]['sha256']='0'*64
        with self.assertRaisesRegex(launcher.bounded.PreflightBlocked,'prerequisite_identity'):launcher.verify_prerequisites(op)

    def test_actual_startup_failure_and_independent_stops(self):
        play=yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/deploy-runtime.yaml').read_text())[0]
        starts=[copy.deepcopy(t) for t in play['tasks'][0]['block'] if t['name'].startswith('Start ')]
        self.assertEqual(len(starts),3)
        for failed in range(3):
            with self.subTest(failed=failed),tempfile.TemporaryDirectory() as tmp:
                path=Path(tmp);tasks=copy.deepcopy(starts)
                for i,t in enumerate(tasks):
                    t['ansible.builtin.command']['argv']=['/bin/false' if i==failed else '/bin/true']
                rescue=copy.deepcopy(play['tasks'][0]['rescue'])
                # Execute the real independent loop with harmless fixture commands.
                rescue[0]['ansible.builtin.command']['argv']=['/bin/false']
                assertions=[{'ansible.builtin.assert':{'that':['runtime_stop.results | length == 3',f'runtime_start_{("postgresql","redis","migration")[failed]}.rc != 0']}}]
                if failed<2:assertions[0]['ansible.builtin.assert']['that'].append('runtime_start_migration is not defined')
                fixture=[{'hosts':'localhost','gather_facts':False,'tasks':[{'block':tasks,'rescue':rescue[:-1],'always':assertions}]}]
                f=path/'play.yaml';f.write_text(yaml.safe_dump(fixture))
                result=subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','-i','localhost,','-c','local',str(f)],capture_output=True,timeout=60)
                self.assertEqual(result.returncode,0,result.stdout.decode()+result.stderr.decode())

    def test_command_defaults_and_real_failure_diagnostics(self):
        play=yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/deploy-runtime.yaml').read_text())[0]
        name='Inspect existing runtime objects before first installation'
        for hidden in (False,True):
            with self.subTest(no_log=hidden),tempfile.TemporaryDirectory() as tmp:
                path=Path(tmp);progress=path/'progress.jsonl';progress.touch(mode=0o600)
                task={'name':name,'ansible.builtin.command':{'argv':[sys.executable,'-c',
                      'import os,sys; assert os.getcwd()=="/"; print("private-sentinel"); sys.exit(7)']},
                      'no_log':hidden}
                fixture=[{'hosts':'localhost','gather_facts':False,
                          'module_defaults':play['module_defaults'],'tasks':[task]}]
                f=path/'play.yaml';f.write_text(yaml.safe_dump(fixture))
                env={**os.environ,'ANSIBLE_CONFIG':str(ROOT/'Nautobot/ansible/ansible.cfg'),
                     'ANSIBLE_CALLBACK_PLUGINS':str(ROOT/'Nautobot/ansible/callback_plugins'),
                     'ANSIBLE_CALLBACKS_ENABLED':'runtime_progress','NAUTOBOT_PROGRESS_FILE':str(progress)}
                result=subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),
                    'ansible-playbook','-i','localhost,','-c','local',str(f)],env=env,cwd=tmp,capture_output=True,timeout=60)
                self.assertEqual(result.returncode,2,result.stdout.decode()+result.stderr.decode())
                raw=progress.read_text();rows=[json.loads(line) for line in raw.splitlines()]
                failure=next(r for r in rows if r['event']=='task_failed')
                self.assertEqual(failure['task'],name)
                self.assertEqual(failure.get('exit_status'),None if hidden else 7)
                self.assertEqual(rows[-1]['event'],'playbook_complete')
                self.assertNotIn('private-sentinel',raw)
                self.assertNotIn(str(path),raw)

    def test_node_main_recovers_inaccessible_inherited_directory(self):
        original=os.getcwd()
        with tempfile.TemporaryDirectory(prefix='nautobot-runtime.') as tmp:
            root=Path(tmp);(root/'operation.json').write_text('{}')
            private=root/'private';private.mkdir();os.chdir(private);private.chmod(0)
            try:
                def probe(*_):
                    # Exercise the real nested subprocess runner after main's
                    # directory boundary, without sudo or contacting a host.
                    observed=node.call([sys.executable,'-c','import os;print(os.getcwd())']).strip()
                    self.assertEqual(observed,'/')
                    return {'passed':True}
                with patch.object(sys,'argv',['helper','preflight',tmp]), \
                     patch.object(node,'preflight',side_effect=probe),patch('builtins.print'):
                    self.assertEqual(node.main(),0)
            finally:
                private.chmod(0o700);os.chdir(original)

    def test_playbook_syntax(self):
        result=subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','--syntax-check','-i',str(ROOT/'inventory/prod/hosts.yaml'),str(ROOT/'Nautobot/ansible/playbooks/deploy-runtime.yaml')],capture_output=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stdout.decode()+result.stderr.decode())

if __name__=='__main__':unittest.main(verbosity=2)
