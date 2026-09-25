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
