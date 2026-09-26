#!/usr/bin/env python3
"""Exercise credential finalization and frozen restore semantics without real secrets."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT/'Nautobot/ansible/scripts'
sys.path.insert(0,str(SCRIPTS))
spec=importlib.util.spec_from_file_location('bundle',SCRIPTS/'application-restore-bundle.py')
bundle=importlib.util.module_from_spec(spec);spec.loader.exec_module(bundle)
import restore_node as node


class DeliveryTests(unittest.TestCase):
    def test_provider_partial_failure_erases_buffers_and_files(self):
        with tempfile.TemporaryDirectory() as d:
            parent=Path(d); buffers=[]
            def reader(*_):
                if buffers: raise RuntimeError('provider unavailable')
                raw=bytearray(b'synthetic'); buffers.append(raw); return raw
            with self.assertRaises(RuntimeError):
                with bundle.credentials(parent,reader,parent/'receipt.json'): self.fail('yielded partial credentials')
            self.assertEqual(buffers[0],bytearray(len(buffers[0])))
            self.assertEqual([p.name for p in parent.iterdir()],['receipt.json'])

    def test_delivery_failure_cleans_controller_credentials(self):
        with tempfile.TemporaryDirectory() as d:
            parent=Path(d)
            with self.assertRaisesRegex(ValueError,'simulated'):
                with bundle.credentials(parent,lambda *_:bytearray(b'x'*40),parent/'receipt.json') as path:
                    self.assertEqual(path.stat().st_mode & 0o777,0o600)
                    self.assertEqual(set(json.loads(path.read_text())),{'django','password','id','key'})
                    raise ValueError('simulated')
            self.assertTrue(json.loads((parent/'receipt.json').read_text())['controller_credentials_absent'])

    def test_node_partial_injection_erases_all_delivered_files(self):
        with tempfile.TemporaryDirectory() as d:
            runtime=object.__new__(node.Restore);runtime.root=Path(d)
            (runtime.root/'retrieval').mkdir(mode=0o700)
            raw=json.dumps(dict(django='x'*40,password='synthetic',id='test',key='test')).encode()
            with patch.object(runtime,'active',side_effect=[None,node.Blocked('terminal_restore')]):
                with self.assertRaisesRegex(node.Blocked,'terminal_restore'): runtime.inject(raw)
            self.assertFalse((runtime.root/'django-secret').exists())
            self.assertEqual(list((runtime.root/'retrieval').iterdir()),[])

    def test_terminal_delivery_cannot_recreate_secret(self):
        with tempfile.TemporaryDirectory() as d:
            runtime=object.__new__(node.Restore);runtime.root=Path(d)
            (runtime.root/'stopped.json').write_text('{}')
            raw=json.dumps(dict(django='x'*40,password='synthetic',id='test',key='test')).encode()
            with self.assertRaisesRegex(node.Blocked,'terminal_restore'): runtime.inject(raw)
            self.assertFalse((runtime.root/'django-secret').exists())

    def test_rendered_controller_uses_repository_launcher_from_bundled_helper(self):
        controller=bundle.module(SCRIPTS/'workload_controller.py','restore_controller_test')
        controller.ROOT=Path('/incorrect/bundled/root')
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            with patch.object(bundle,'verify'), patch.object(bundle,'module',return_value=controller), patch.object(controller,'persistent_path',side_effect=lambda p:p):
                unit=bundle.render(root,'a'*64,root/'evidence',root/'ssh-agent')
            self.assertIn('WorkingDirectory='+str(ROOT),unit)
            self.assertIn(str(SCRIPTS/'application-restore-bundle.py')+' execute --bundle',unit)
            self.assertNotIn('/incorrect/',unit)
            self.assertIn('RuntimeMaxSec=4500',unit)

    def test_generated_retrieval_pins_all_source_fields(self):
        import yaml
        prep=yaml.safe_load((ROOT/bundle.FILES['preparation.yaml']).read_text())
        runtime, contract=bundle.generated({'root':'/var/lib/nautobot/restore-tests/nautobot-restore-'+'a'*24,
            'token':'nautobot-restore-'+'a'*24,'restic_version':'pinned'},prep)
        self.assertEqual(contract['snapshot_id'],prep['source']['snapshot_id'])
        self.assertEqual(contract['content_sha256'],prep['source']['content_sha256'])
        self.assertEqual(len(runtime['production_containers']),5)
        self.assertEqual(set(runtime['images']),{'application','postgresql','redis'})


class FrozenTests(unittest.TestCase):
    def test_freeze_rejects_rehashed_runtime_redirection_and_extra_files(self):
        import shutil
        import yaml
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)/'repo';root.mkdir();inputs=Path(d)/'inputs';inputs.mkdir()
            for relative in bundle.FILES.values():
                dest=root/relative;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/relative,dest)
            roles=('postgresql','redis','web','worker','scheduler')
            services={r:{'ActiveState':'active','SubState':'running','Result':'success','NRestarts':'0','InvocationID':'test'} for r in roles}
            baseline={'host':'j2-svpi4mf','boot_id':'00000000-0000-4000-8000-000000000001',
                'collected_at':'2026-09-26T16:35:55+00:00','persistence_user':{'UID':'999','Linger':'yes'},
                'persistence_services':services,'guard':{'verified':True},'quadlets':{},
                'runtime_files':{'nautobot_config.py':{'regular':True,'uid':999,'mode':'0o644','sha256':'a'*64}}}
            for name,value in (('baseline.json',baseline),('members.json',{}),('logical.json',{})):
                (inputs/name).write_text(json.dumps(value))
            prep_path=root/bundle.FILES['preparation.yaml'];prep=yaml.safe_load(prep_path.read_text())
            prep['baseline'].update(sha256=bundle.sha(inputs/'baseline.json'),collected_at=baseline['collected_at'])
            prep['source']['logical_reference_sha256']=bundle.sha(inputs/'logical.json')
            prep['configuration']['archive_member_map_sha256']=bundle.sha(inputs/'members.json')
            prep_path.write_text(yaml.safe_dump(prep))
            accepted_path=root/bundle.FILES['accepted-state.yaml'];accepted=yaml.safe_load(accepted_path.read_text())
            accepted['recovery_preservation']['logical_before_sha256']=bundle.sha(inputs/'logical.json')
            accepted_path.write_text(yaml.safe_dump(accepted))
            schema=json.loads((root/bundle.FILES['schema.json']).read_text());token='nautobot-restore-'+'a'*24
            op={'schema_version':1,'operation':{'state':'definition','stage':'isolated_application_restore',
                'id':'nautobot-application-restore-v1','target':'j2-svpi4mf','authorization_ready':False,'source_commit':'a'*40},
                'token':token,'root':'/var/lib/nautobot/restore-tests/'+token,'monitor_root':'/tmp/nautobot-restore-monitor-'+'a'*24,
                'ci_success_commit':None,'restic_version':schema['properties']['restic_version']['const'],
                'boundaries':schema['properties']['boundaries']['const'],
                'baseline':{'collected_at':baseline['collected_at'],'sha256':bundle.sha(inputs/'baseline.json'),
                    'boot_id':baseline['boot_id'],'services':services,'artifact_sha256':{'/var/lib/nautobot/runtime/nautobot_config.py':'a'*64}}}
            for name,field in (('PLAN.md','plan_sha256'),('accepted-state.yaml','accepted_state_sha256'),('preparation.yaml','preparation_sha256')):
                op[field]=bundle.sha(root/bundle.FILES[name])
            op.update(members_sha256=bundle.sha(inputs/'members.json'),logical_sha256=bundle.sha(inputs/'logical.json'))
            (inputs/'operation.json').write_text(json.dumps(op))
            with patch.object(bundle,'ROOT',root):
                dest=Path(d)/'bundle'
                approval=bundle.freeze(inputs/'operation.json',dest,inputs/'baseline.json',inputs/'members.json',inputs/'logical.json')
                bundle.verify(dest,approval,executing=False)
                (dest/'extra').write_text('unexpected')
                with self.assertRaisesRegex(ValueError,'bundle_file_set'):bundle.verify(dest,approval,executing=False)
                (dest/'extra').unlink()
                data=json.loads((dest/'runtime.json').read_text());data['restic_helper']='/wrong/helper'
                (dest/'runtime.json').write_text(json.dumps(data))
                manifest=json.loads((dest/'bundle.json').read_text());manifest['files']['runtime.json']=bundle.sha(dest/'runtime.json')
                (dest/'bundle.json').write_text(json.dumps(manifest))
                with self.assertRaisesRegex(ValueError,'runtime_contract'):
                    bundle.verify(dest,bundle.sha(dest/'bundle.json'),executing=False)


if __name__=='__main__': unittest.main()
