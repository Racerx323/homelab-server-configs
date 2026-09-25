#!/usr/bin/env python3
"""Exercise owned-session and observation failures without host contact."""
import copy
from datetime import datetime,timezone
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import yaml

ROOT=Path(__file__).resolve().parents[2]

def load(name,file):
    spec=importlib.util.spec_from_file_location(name,ROOT/'Nautobot/ansible/scripts'/file)
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod
node=load('logout_node','logout-node.py');bundle=load('logout_bundle','logout-bundle.py')
MANAGER={'Id':'1','User':'999','Service':'systemd-user','Class':'manager-early','Leader':'812','State':'active'}


def baseline():
    return {'boot_id':'boot','services':{role:{'InvocationID':role,'NRestarts':'0'} for role in node.ROLES}}


def sample(now=0):
    return {'monotonic':now,'utc':now,'boot_id':'boot','http_status':'200','sessions':{'1':MANAGER},
            'units':{'nautobot-'+r+'.service':{'ActiveState':'active','SubState':'running','Result':'success','InvocationID':r,'NRestarts':'0'} for r in node.ROLES}}


class Logout(unittest.TestCase):
    def test_session_ownership_preserves_manager_and_rejects_ambiguity(self):
        before={'1':MANAGER};now=copy.deepcopy(before)
        now['c5']={'User':'999','Service':'login','Leader':'1234','Class':'background','State':'active'}
        self.assertEqual(node.owned_session(before,now,'1234'),'c5')
        for bad in (before,dict(now,c6=now['c5']),{'c5':now['c5']},dict(now,c5=dict(now['c5'],User='1000')),dict(now,c5=dict(now['c5'],Leader='5678'))):
            with self.assertRaises(ValueError):node.owned_session(before,bad,'1234')

    def test_continuity_rejects_restart_session_and_health_drift(self):
        row=sample();node.check_sample(row,baseline(),{'1':MANAGER})
        for field,value in (('boot_id','new'),('http_status','503'),('sessions',{})):
            bad=copy.deepcopy(row);bad[field]=value
            with self.assertRaises(ValueError):node.check_sample(bad,baseline(),{'1':MANAGER})
        bad=copy.deepcopy(row);bad['units']['nautobot-web.service']['NRestarts']='1'
        with self.assertRaisesRegex(ValueError,'service_changed'):node.check_sample(bad,baseline(),{'1':MANAGER})

    def test_observer_full_coverage_and_failure_receipts(self):
        for fault in (None,'gap','http','cursor','storage'):
            with self.subTest(fault=fault),tempfile.TemporaryDirectory() as d:
                root=Path(d)
                (root/'before.json').write_text(json.dumps({'sample':sample(),'cursor':'cursor'}))
                (root/'closed.json').write_text(json.dumps({'monotonic':0}))
                clock=[0]
                def snapshot():
                    row=sample(clock[0])
                    if fault=='http':row['http_status']='500'
                    return row
                def sleep(seconds):clock[0]+=11 if fault=='gap' else seconds
                def command(argv):
                    if '--cursor' in argv:return json.dumps({'__CURSOR':'lost' if fault=='cursor' else 'cursor'})
                    return json.dumps({'MESSAGE':'USB device reset'}) if fault=='storage' else ''
                with patch.object(node,'snapshot',side_effect=snapshot),patch.object(node.time,'monotonic',side_effect=lambda:clock[0]),patch.object(node.time,'sleep',side_effect=sleep),patch.object(node,'command',side_effect=command),patch.object(node,'artifacts'):
                    if fault:
                        with self.assertRaises(ValueError):node.observe(root,{'baseline':baseline()})
                    else:node.observe(root,{'baseline':baseline()})
                result=json.loads((root/'result.json').read_text())
                self.assertEqual(result['passed'],fault is None)
                if fault is None:
                    self.assertEqual(result['duration_seconds'],300)
                    self.assertEqual(result['samples'],61)

    def test_closure_requires_session_absence_and_unit_stop(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'before.json').write_text(json.dumps({'sample':sample()}))
            with patch.object(node,'sessions',return_value={'1':MANAGER}),patch.object(node,'command',return_value='ActiveState=inactive\nMainPID=0\n'):
                node.closed(root,{'test_unit':'owned.service'})
            self.assertTrue(json.loads((root/'closed.json').read_text())['session_absent'])
            with patch.object(node,'sessions',return_value={'1':MANAGER,'c4':{}}):
                with self.assertRaisesRegex(ValueError,'session_not_closed'):node.closed(root,{'test_unit':'owned.service'})

    def test_playbook_syntax_and_lifecycle_boundary(self):
        play=ROOT/'Nautobot/ansible/playbooks/logout-persistence.yaml'
        result=subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','--syntax-check','-i',str(ROOT/'inventory/prod/hosts.yaml'),str(play)],capture_output=True,text=True,cwd=ROOT)
        self.assertEqual(result.returncode,0,result.stderr)
        parsed=yaml.safe_load(play.read_text())[0]
        always=parsed['tasks'][0]['always']
        self.assertTrue(any('ansible.builtin.fetch' in task for task in always))
        self.assertNotIn('terminate-user',play.read_text())
        self.assertNotIn('reboot',play.read_text())
        self.assertEqual(parsed['hosts'],'j2-svpi4mf')

    def test_ansible_resolution_without_interactive_path(self):
        with tempfile.TemporaryDirectory() as d:
            home=Path(d);binary=home/'.local/bin/ansible-playbook'
            binary.parent.mkdir(parents=True);binary.write_text('#!/bin/sh\nexit 0\n');binary.chmod(0o700)
            with patch.object(bundle.Path,'home',return_value=home),patch.dict(bundle.os.environ,{'PATH':'/nonexistent'}):
                self.assertEqual(bundle.ansible_executable(),str(binary))
        with patch.object(bundle.shutil,'which',return_value=None):
            with self.assertRaisesRegex(ValueError,'ansible_executable_unavailable'):
                bundle.ansible_executable()

    def test_actual_cleanup_assertions_allow_only_proven_absence(self):
        play=yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/logout-persistence.yaml').read_text())[0]
        task=copy.deepcopy(play['tasks'][0]['always'][-1])
        for code,load,pid,state,read_rc,passes in (
            (0,'loaded',0,'inactive',0,True),
            (5,'not-found',0,'inactive',0,True),
            (5,'loaded',0,'inactive',0,False),
            (1,'not-found',0,'inactive',0,False),
            (5,'not-found',123,'inactive',0,False),
            (5,'not-found',0,'active',0,False),
            (5,'not-found',0,'inactive',1,False),
        ):
            with self.subTest(code=code,load=load,pid=pid,state=state,read_rc=read_rc),tempfile.TemporaryDirectory() as d:
                unit={'rc':read_rc,'stdout_lines':[f'LoadState={load}',f'MainPID={pid}',f'ActiveState={state}']}
                probe=[{'hosts':'localhost','gather_facts':False,'vars':{
                    'logout_stop':{'rc':code},'logout_final_units':{'results':[unit]}},'tasks':[task]}]
                path=Path(d)/'test.yaml';path.write_text(yaml.safe_dump(probe))
                result=subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','-i','localhost,','-c','local',str(path)],capture_output=True,text=True,cwd=ROOT)
                self.assertEqual(result.returncode==0,passes,result.stdout+result.stderr)

    def test_bundle_tamper_and_expiry(self):
        op=json.loads((ROOT/'Nautobot/tests/fixtures/logout-operation.json').read_text())
        op['baseline']['collected_at']=datetime.now(timezone.utc).isoformat()
        with tempfile.TemporaryDirectory() as d:
            dest=Path(d)/'bundle'
            dest.mkdir()
            for name,source in bundle.FILES.items():
                (dest/name).write_bytes((ROOT/source).read_bytes())
            op['plan_sha256']=bundle.sha(dest/'PLAN.md')
            (dest/'operation.json').write_text(json.dumps(op));(dest/'inventory.ini').write_text('fixture')
            def approval():
                manifest={'source_commit':op['operation']['source_commit'],'stage':'logout_persistence','targets':['ama@10.1.2.170','pi@10.1.0.53'],
                          'files':{p.name:bundle.sha(p) for p in dest.iterdir() if p.name!='bundle.json'}}
                (dest/'bundle.json').write_text(json.dumps(manifest));return bundle.sha(dest/'bundle.json')
            digest=approval();bundle.verify(dest,digest)
            (dest/'logout-node.py').write_text('tampered')
            with self.assertRaisesRegex(ValueError,'input_identity'):bundle.verify(dest,digest)
            op['baseline']['collected_at']='2000-01-01T00:00:00+00:00';(dest/'operation.json').write_text(json.dumps(op));digest=approval()
            with self.assertRaisesRegex(ValueError,'baseline_expired'):bundle.verify(dest,digest)

if __name__=='__main__':unittest.main()
