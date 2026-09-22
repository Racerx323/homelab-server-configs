#!/usr/bin/env python3
"""Offline tests of real continuation parser, boundaries and Ansible stop path."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import yaml
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
def load(name,file):
    s=importlib.util.spec_from_file_location(name,ROOT/'Nautobot/ansible/scripts'/file)
    m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
app=load('continuation','migration-continuation.py');node=load('continuation_node','continuation-node.py')
launcher=load('runtime_launcher','run-runtime.py');renderer=load('render_continuation','render-runtime.py')

class Continuation(unittest.TestCase):
    def operation(self):
        schema=json.loads((ROOT/'Nautobot/schemas/runtime-continuation.schema.json').read_text())
        return {k:copy.deepcopy(v['const']) for k,v in schema['properties'].items()}

    def test_split_progress_and_secret_rejection(self):
        rows=[];p=app.Progress(lambda event,**v:rows.append({'event':event,**v}),[('users','0002_change')])
        for data in [b'Performing database mig',b'rations...\n  Applying users.0002_',b'change...',b' OK ( 1.0s)\n',b'password=private-sentinel\n',b'  Applying secret.bad... OK\n']:
            p.feed('stdout',data)
        self.assertEqual([r['event'] for r in rows],['phase','migration_start','migration_complete'])
        self.assertNotIn('private-sentinel',json.dumps(rows))
        p.feed('stderr',b'x'*300000+b'\nClearing cache...\n')
        self.assertEqual(rows[-1],{'event':'phase','phase':'clear_cache'})

    def test_pinned_truncated_name_and_timing_format(self):
        rows=[];name='0009_update_all_charfields_max_length_to_255'
        p=app.Progress(lambda e,**v:rows.append({'event':e,**v}),[('users',name)])
        line=('  Applying '+('users.'+name)[:50]+'...').ljust(64)
        p.feed('stdout',line.encode());p.feed('stdout',b' OK        0.10s\n')
        self.assertEqual([r['event'] for r in rows],['migration_start','migration_complete'])
        self.assertEqual(rows[-1]['migration'],name)
        rows.clear();p=app.Progress(lambda e,**v:rows.append(v),[('users','x'*60+'a'),('users','x'*60+'b')])
        p.feed('stdout',('  Applying '+('users.'+'x'*60)[:50]+'... OK 0.10s\n').encode())
        self.assertEqual(rows,[])

    def test_real_child_progress_timeout_output_limit(self):
        rows=[];p=app.Progress(lambda e,**v:rows.append(e),[])
        result=app.run([sys.executable,'-c','print("Clearing cache...")'],5,p)
        self.assertEqual(result['exit_status'],0);self.assertEqual(rows,['phase'])
        result=app.run([sys.executable,'-c','import time;time.sleep(5)'],.05,p)
        self.assertEqual(result['error'],'timeout')
        result=app.run([sys.executable,'-c','import os;os.write(1,b"x"*10000000)'],5,p)
        self.assertEqual(result['error'],'output_limit')

    def test_native_plan_checks_real_producer(self):
        with tempfile.TemporaryDirectory() as tmp:
            source=Path(tmp)/'migration.py';source.write_text('pinned migration')
            migration=SimpleNamespace(app_label='users',name='0002_change',atomic=True)
            module=migration.__class__.__module__
            contract={'modules':{module:{'sha256':hashlib.sha256(source.read_bytes()).hexdigest()}},'applied':[['users','0001_initial']],'reviewed_non_atomic':[]}
            loader=SimpleNamespace(check_consistent_history=lambda _:None,detect_conflicts=lambda:{},applied_migrations={('users','0001_initial')},graph=SimpleNamespace(leaf_nodes=lambda:[]))
            executor=SimpleNamespace(loader=loader,connection=object(),migration_plan=lambda _: [(migration,False)])
            with patch.object(app.inspect,'getsourcefile',return_value=str(source)):
                self.assertEqual(app.validate_plan(executor,contract),[['users','0002_change']])
                migration.atomic=False
                with self.assertRaisesRegex(ValueError,'non_atomic'):app.validate_plan(executor,contract)
                migration.atomic=True;source.write_text('changed')
                with self.assertRaisesRegex(ValueError,'source_drift'):app.validate_plan(executor,contract)
                executor.migration_plan=lambda _: [(migration,True)]
                with self.assertRaisesRegex(ValueError,'unreviewed'):app.validate_plan(executor,contract)
                contract['applied']=[]
                with self.assertRaisesRegex(ValueError,'ledger_drift'):app.validate_plan(executor,contract)
                loader.detect_conflicts=lambda:{'users':['a','b']}
                with self.assertRaisesRegex(ValueError,'graph_conflict'):app.validate_plan(executor,contract)

    def test_native_sequence_and_failure_stop(self):
        for fail in (None,0,1,2,3,4):
            with self.subTest(fail=fail),tempfile.TemporaryDirectory() as tmp:
                calls=[]
                def run(argv,timeout,observer):
                    i=len(calls);calls.append(argv);self.assertLessEqual(timeout,1800)
                    if i==1:observer.feed('stdout',(app.PLAN_PREFIX+json.dumps({'passed':True,'pending':[['users','0002_change']]})+'\n').encode())
                    return {'exit_status':1 if fail==i else 0,'error':None,'bytes':0}
                result=app.continue_application({'known_migrations':[['users','0002_change']]},Path(tmp),'a'*64,run,False)
                self.assertEqual(result['passed'],fail is None)
                self.assertEqual(len(calls),5 if fail is None else fail+1)
                self.assertEqual(json.loads((Path(tmp)/'receipt.json').read_text()),result)
                self.assertEqual([r['step'] for r in map(json.loads,(Path(tmp)/'progress.jsonl').read_text().splitlines()) if r['event']=='step_start'],[x[0] for x in app.STEPS][:len(calls)])

    def test_missing_and_unknown_plan_never_migrates(self):
        for payload in (None,{'passed':False,'pending':[]},{'passed':True,'pending':[['private','sentinel']]}):
            with tempfile.TemporaryDirectory() as tmp:
                calls=[]
                def run(argv,timeout,p):
                    calls.append(argv)
                    if len(calls)==2 and payload is not None:p.feed('stdout',(app.PLAN_PREFIX+json.dumps(payload)+'\n').encode())
                    return {'exit_status':0,'error':None,'bytes':0}
                r=app.continue_application({'known_migrations':[]},Path(tmp),'a'*64,run,False)
                self.assertFalse(r['passed']);self.assertFalse(r['migration_attempted']);self.assertEqual(len(calls),2)
                self.assertNotIn('sentinel',(Path(tmp)/'receipt.json').read_text())

    def test_stale_invocation_never_reads_receipt(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'preflight.json').write_text(json.dumps({'before':{'migration':{'InvocationID':'a'*32}}}))
            with patch.object(node.inspection,'state',return_value={'InvocationID':'a'*32}),patch.object(node,'receipt',side_effect=AssertionError('stale must not read')):
                with self.assertRaisesRegex(ValueError,'stale_migration'):node.poll(root,{})

    def test_stale_startup_wait_is_bounded(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'preflight.json').write_text(json.dumps({'before':{'migration':{'InvocationID':'a'*32}}}))
            with patch.object(node.inspection,'state',return_value={'InvocationID':'a'*32,'ActiveState':'failed'}),patch.object(node.time,'monotonic',side_effect=[100,100,131]),patch.object(node,'receipt',side_effect=AssertionError('must not read old receipt')):
                self.assertTrue(node.poll(root,{})['pending'])
                with self.assertRaisesRegex(ValueError,'stale_migration'):node.poll(root,{})

    def test_repeated_poll_preserves_latest_progress(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'preflight.json').write_text(json.dumps({'before':{'migration':{'InvocationID':'a'*32}}}))
            state={'InvocationID':'b'*32,'ActiveState':'activating'}
            with patch.object(node.inspection,'state',return_value=state),patch.object(node,'events',side_effect=[[],[{'event':'phase'}]]):
                self.assertTrue(node.poll(root,{})['pending'])
                self.assertTrue(node.poll(root,{})['pending'])
            self.assertEqual(json.loads((root/'native-progress.json').read_text())['events'],[{'event':'phase'}])

    def test_copy_hash_rejection(self):
        op={'continuation':{'cold_copy':'/var/lib/nautobot/recovery/test','cold_volumes':{'volume':{'tree_sha256':'0'*64,'entries':0}}}}
        info=SimpleNamespace(st_mode=0o40700,st_uid=0)
        with patch.object(node.Path,'is_symlink',return_value=False),patch.object(node.Path,'lstat',return_value=info),patch.object(node.runtime.storage,'ancestry'),patch.object(node.inspection,'no_submounts'),patch.object(node.inspection,'tree',return_value={}):
            with self.assertRaisesRegex(ValueError,'cold_copy_changed'):node.copied_trees(op)

    def test_stale_receipt_rejected(self):
        with patch.object(node,'read_safe',return_value=json.dumps({'passed':True,'token':'b'*64,'migration_attempted':True})):
            with self.assertRaisesRegex(ValueError,'receipt_identity'):node.receipt({'continuation':{'invocation_nonce':'a'*64}})

    def test_guard_continues_after_first_stop_failure(self):
        calls=[]
        def run(argv,*_):
            calls.append(argv)
            if len(calls)==1:raise RuntimeError('stop failed')
        with patch.object(node.inspection,'command',side_effect=run),patch.object(node.runtime.storage,'record'):
            self.assertFalse(node.guard_stop(Path('/tmp'))['passed'])
        self.assertEqual(len(calls),3);self.assertIn('nautobot-postgresql.service',calls[-1])

    def test_actual_ansible_always_and_failed_stop_loop(self):
        tasks=yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/continue-runtime-tasks.yaml').read_text())
        stop=copy.deepcopy(tasks[-1]['always'][0]);stop['ansible.builtin.command']['argv']=['/bin/false']
        assertions={'ansible.builtin.assert':{'that':['continuation_stop.results | length == 3','continuation_stop.results[2].rc == 1']}}
        fixture=[{'hosts':'localhost','gather_facts':False,'tasks':[{'block':[{'ansible.builtin.command':{'argv':['/bin/false']}}],'rescue':[{'ansible.builtin.debug':{'msg':'fixture failure'}}],'always':[stop,assertions]}]}]
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'play.yaml';path.write_text(yaml.safe_dump(fixture))
            r=subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','-i','localhost,','-c','local',str(path)],capture_output=True,timeout=60)
            self.assertEqual(r.returncode,0,r.stdout.decode()+r.stderr.decode())
        self.assertIn('continuation_stopped.rc | default(1) == 0',next(t for t in tasks[-1]['always'] if t['name'].startswith('Disarm'))['when'])

    def test_continuation_quadlet_real_parser_and_no_other_changes(self):
        from quadlet_tool import resolve
        desired=yaml.safe_load((ROOT/'Nautobot/manifests/desired-state.yaml').read_text());inputs=json.loads((ROOT/'Nautobot/manifests/runtime-inputs.json').read_text())
        before=renderer.render(desired,inputs,True);after=renderer.render(desired,inputs,True,'a'*64)
        self.assertEqual([k for k in before if before[k]!=after[k]],['nautobot-migration.container'])
        self.assertIn('TimeoutStartSec=1860',after['nautobot-migration.container'])
        self.assertIn('--memory-swap=1536m',after['nautobot-migration.container'])
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);units=root/'units';units.mkdir();out=root/'out';out.mkdir()
            for n,s in after.items():(units/n).write_text(s)
            r=subprocess.run([str(resolve()),'--user',str(out)],env={**os.environ,'QUADLET_UNIT_DIRS':str(units)},capture_output=True,timeout=30)
            self.assertEqual(r.returncode,0,r.stderr.decode());self.assertIn('/run/migration-continuation.py',(out/'nautobot-migration.service').read_text())

    def test_schema_and_bad_hash_no_execution(self):
        op=self.operation()
        desired=yaml.safe_load((ROOT/'Nautobot/manifests/desired-state.yaml').read_text())
        inputs=json.loads((ROOT/'Nautobot/manifests/runtime-inputs.json').read_text())
        artifacts=renderer.render(desired,inputs,True,op['continuation']['invocation_nonce'])
        with tempfile.TemporaryDirectory() as tmp:
            directory=Path(tmp)
            op['runtime']['rendered_directory']=str(directory)
            for name in op['runtime']['artifact_sha256']:
                data=artifacts[name].encode()
                (directory/name).write_bytes(data)
                op['runtime']['artifact_sha256'][name]=hashlib.sha256(data).hexdigest()
            with patch.object(launcher,'validate',return_value=op),patch.object(launcher.bounded,'drain_process',side_effect=AssertionError('must not execute')):
                with self.assertRaisesRegex(launcher.bounded.PreflightBlocked,'bundle_hash_mismatch'):
                    launcher.execute('0'*64)
                (directory/'nautobot-migration.container').write_text('corrupted fixture')
                with self.assertRaisesRegex(launcher.bounded.PreflightBlocked,'artifact_hash_mismatch'):
                    launcher.execute('0'*64)
        self.assertFalse(op['runtime']['first_install_only'])
        play=yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/deploy-runtime.yaml').read_text())[0]
        guard=next(t for t in play['pre_tasks'] if t['name']=='Require a first installation')
        self.assertEqual(guard['ansible.builtin.assert']['that'],'not item.stat.exists')
        self.assertEqual(guard['when'],"runtime_operation.operation.stage == 'runtime_initialization'")

if __name__=='__main__':unittest.main(verbosity=2)
