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


def preparation():
    # Minimal operation input; no completed production trial is a test default.
    sections = ('postgresql_custom_dump', 'media', 'configuration',
                'image_dependency_manifest', 'quadlet_config_hashes', 'versions_migrations')
    return {'source': {'snapshot_id': 'a'*64, 'repository_id': 'b'*64,
                      'repository_url': '/fixture/repository', 'hostname': 'fixture',
                      'tags': ['fixture'], 'payload_path': '/fixture/payload',
                      'content_sha256': {name: 'c'*64 for name in sections}},
            'runtime': {'image_ids': {role: 'd'*64 for role in ('application', 'postgresql', 'redis')}},
            'baseline': {}, 'configuration': {}}


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
        prep=preparation()
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
            prep_path=inputs/'preparation.yaml';prep=preparation()
            historical = yaml.safe_load((root/bundle.FILES['accepted-state.yaml']).read_text())['recovery_preservation']
            prep['source'].update(kind='recovery_preservation', **{k:historical[k] for k in ('snapshot_id','terminal_tag','archive_commit')})
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
                'attended_window':{'start':'2026-11-24T17:00:00-06:00','end':'2026-11-24T19:00:00-06:00'},
                'ci_success_commit':None,'restic_version':schema['properties']['restic_version']['const'],
                'boundaries':schema['properties']['boundaries']['const'],
                'baseline':{'collected_at':baseline['collected_at'],'sha256':bundle.sha(inputs/'baseline.json'),
                    'boot_id':baseline['boot_id'],'services':services,'artifact_sha256':{'/var/lib/nautobot/runtime/nautobot_config.py':'a'*64}}}
            for name,field in (('PLAN.md','plan_sha256'),('accepted-state.yaml','accepted_state_sha256'),('preparation.yaml','preparation_sha256')):
                op[field]=bundle.sha(prep_path if name == 'preparation.yaml' else root/bundle.FILES[name])
            op.update(members_sha256=bundle.sha(inputs/'members.json'),logical_sha256=bundle.sha(inputs/'logical.json'))
            (inputs/'operation.json').write_text(json.dumps(op))
            with patch.object(bundle,'ROOT',root):
                dest=Path(d)/'bundle'
                saved = prep_path.read_bytes()
                prep_path.write_bytes(saved + b'\n')
                with self.assertRaisesRegex(ValueError, 'preparation_identity'):
                    bundle.freeze(inputs/'operation.json', dest, inputs/'baseline.json', inputs/'members.json', inputs/'logical.json', preparation=prep_path)
                self.assertFalse(dest.exists())
                prep_path.write_bytes(saved)
                approval=bundle.freeze(inputs/'operation.json',dest,inputs/'baseline.json',inputs/'members.json',inputs/'logical.json',preparation=prep_path)
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


class MonthlyTests(unittest.TestCase):
    def test_recurring_source_binds_accepted_receipts_and_rejects_wrong_dump(self):
        import copy
        import hashlib
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'logical-reference.json').write_text('{}\n')
            reference = bundle.sha(root/'logical-reference.json')
            spec = {'repository_id':'r'}
            identity = hashlib.sha256(json.dumps(spec,sort_keys=True,separators=(',', ':')).encode()).hexdigest()
            capture = {'specification_sha256':identity,'capture_passed':True,'content_sha256':{'postgresql_custom_dump':'a'*64}}
            upload = dict(capture,upload_passed=True,integrity_passed=True,integrity_exit_status=0,backup_exit_status=0,snapshot_id='s')
            logical = {'specification_sha256':identity,'reference_sha256':reference,'dump_sha256':'a'*64,
                       'comparison':{'equal':True,'changed_sections':[]}}
            receipts = {'application-backup.json':spec,'application-capture-result.json':capture,
                        'application-backup-result.json':upload,'logical-capture.json':logical,'logical-reference.json':{}}
            (root/'source-evidence.json').write_text(json.dumps({'receipts':receipts}))
            source = {'kind':'recurring_logical_promotion','snapshot_id':'s','repository_id':'r','terminal_tag':'tag',
                      'archive_commit':'commit','content_sha256':capture['content_sha256']}
            record = dict(source,status='first_scheduled_cycle_accepted',terminal_archival='published_verified',
                          independent_acceptance=True,logical_reference_sha256=reference,
                          evidence_sha256={'independent-readback.json':bundle.sha(root/'source-evidence.json')})
            accepted = {'recurring_logical_promotion':record}
            bundle.verify_source(root,{'source':source},{'logical_sha256':reference},accepted)
            wrong = copy.deepcopy(source); wrong['snapshot_id']='other'
            with self.assertRaisesRegex(ValueError,'archive_source'):
                bundle.verify_source(root,{'source':wrong},{'logical_sha256':reference},accepted)
            wrong = copy.deepcopy(source); wrong['content_sha256']['postgresql_custom_dump']='b'*64
            with self.assertRaisesRegex(ValueError,'source_sections'):
                bundle.verify_source(root,{'source':wrong},{'logical_sha256':reference},accepted)
            (root/'source-evidence.json').write_text('{}')
            with self.assertRaisesRegex(ValueError,'source_evidence_identity'):
                bundle.verify_source(root,{'source':source},{'logical_sha256':reference},accepted)

    def test_pre_admission_reboot_allowed_but_continuity_and_drift_fail(self):
        import copy
        preflight = bundle.module(SCRIPTS/'restore_preflight.py','monthly_preflight')
        services = {role:{'ActiveState':'active','SubState':'running','Result':'success','InvocationID':'new',
                          'NRestarts':'0','MainPID':'20'} for role in ('postgresql','redis','web','worker','scheduler')}
        current = {'host':'j2-svpi4mf','boot_id':'new','persistence_user':{'UID':'999','Linger':'yes'},
                   'persistence_services':services,'guard':{'verified':True},'runtime_files':{},'quadlets':{}}
        expected = {'boot_id':'old','services':copy.deepcopy(services),'artifact_sha256':{}}
        for row in expected['services'].values(): row.update(InvocationID='old',MainPID='10')
        preflight.assess(current,expected)
        with self.assertRaisesRegex(ValueError,'boot_changed'): preflight.assess(current,expected,continuity=True)
        admitted = dict(expected,boot_id='new',services=services)
        preflight.assess(current,admitted,continuity=True)
        wrong = dict(current,host='wrong')
        with self.assertRaisesRegex(ValueError,'baseline_identity'): preflight.assess(wrong,expected)
        with self.assertRaisesRegex(ValueError,'artifact_drift'): preflight.assess(current,dict(expected,artifact_sha256={'missing':'a'*64}))

    def test_monitor_pins_admitted_boot_and_service_invocation(self):
        import copy
        monitor = bundle.module(SCRIPTS/'restore_host_monitor.py','monthly_monitor')
        admission = {'boot_id':'admitted','services':{'web':{'InvocationID':'i','NRestarts':'0'}}}
        sample = {'boot_id':'admitted','services':{'web':{'unit':{'InvocationID':'i','NRestarts':'0'}}}}
        monitor.assess_admission(sample,admission)
        with self.assertRaisesRegex(ValueError,'boot_changed'):
            monitor.assess_admission(dict(sample,boot_id='rebooted'),admission)
        changed = copy.deepcopy(sample);changed['services']['web']['unit']['InvocationID']='other'
        with self.assertRaisesRegex(ValueError,'admission_service_changed'):
            monitor.assess_admission(changed,admission)

    def test_attended_window_and_backup_overlap_are_enforced(self):
        import copy
        from datetime import datetime
        preflight = bundle.module(SCRIPTS/'restore_preflight.py','monthly_window')
        window = {'start':'2026-11-24T17:00:00-06:00','end':'2026-11-24T19:00:00-06:00'}
        now = datetime.fromisoformat(window['start'])
        units = {name:{'ActiveState':'inactive','Result':'success'} for name in
                 ('nautobot-protection.service','nautobot-protection-recovery.service')}
        units['nautobot-protection.timer']={'ActiveState':'active','UnitFileState':'enabled'}
        preflight.admit_window(window,units,now.timestamp()+20000,now)
        with self.assertRaisesRegex(ValueError,'protection_overlap'):
            preflight.admit_window(window,units,now.timestamp()+100,now)
        with self.assertRaisesRegex(ValueError,'attended_window'):
            preflight.admit_window(window,units,now.timestamp()+20000,datetime.fromisoformat(window['end']))
        active = copy.deepcopy(units);active['nautobot-protection.service']['ActiveState']='active'
        with self.assertRaisesRegex(ValueError,'protection_not_idle'):
            preflight.admit_window(window,active,now.timestamp()+20000,now)


if __name__=='__main__': unittest.main()
