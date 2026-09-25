#!/usr/bin/env python3
"""Preservation drain must reject missing replies, priority work and unacked tasks."""
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock
sys.dont_write_bytecode = True
SCRIPTS = Path(__file__).resolve().parents[1] / 'ansible/scripts'
sys.path.insert(0, str(SCRIPTS))
import recovery_probe as probe


class DrainTests(unittest.TestCase):
    def client(self, rows):
        client = Mock()
        client.scan_iter.return_value = list(rows)
        client.type.side_effect = lambda key: rows[key][0]
        client.llen.side_effect = lambda key: rows[key][1]
        client.hlen.side_effect = lambda key: rows[key][1]
        client.zcard.side_effect = lambda key: rows[key][1]
        return client

    def test_every_priority_and_unacked_checked(self):
        for key, kind in ((b'queue\x06\x169', b'list'), (b'unacked', b'hash'), (b'unacked_index', b'zset')):
            self.assertFalse(probe.broker_empty(self.client({key: (kind, 1)})))
        self.assertTrue(probe.broker_empty(self.client({b'_kombu.binding.celery': (b'set', 1)})))

    def test_missing_worker_is_not_empty(self):
        worker = Mock()
        for bad in (None, {}, {'a': [], 'b': []}):
            worker.active.return_value = bad
            with self.assertRaises(ValueError):
                probe.worker_empty(worker)

    def test_active_reserved_scheduled_and_identity(self):
        for phase in ('active', 'reserved', 'scheduled'):
            worker = Mock()
            for name in ('active', 'reserved', 'scheduled'):
                getattr(worker, name).return_value = {'worker': []}
            getattr(worker, phase).return_value = {'worker': [{'private_task_arguments': 'never logged'}]}
            self.assertFalse(probe.worker_empty(worker))
        worker.active.return_value = {'one': []}
        worker.reserved.return_value = {'two': []}
        with self.assertRaisesRegex(ValueError, 'identity'):
            probe.worker_empty(worker)

    def test_two_observations_and_no_purge_or_cancel(self):
        worker = Mock()
        for name in ('active', 'reserved', 'scheduled'):
            getattr(worker, name).return_value = {'worker': []}
        app = Mock(); app.control.inspect.return_value = worker
        client = self.client({})
        now = [0]
        def sleep(value): now[0] += value
        result = probe.drain(app, client, clock=lambda: now[0], sleep=sleep)
        self.assertEqual(result['consecutive_observations'], 2)
        self.assertEqual(now[0], 5)
        app.control.purge.assert_not_called()
        app.control.revoke.assert_not_called()


class PreparationTests(unittest.TestCase):
    def test_freeze_and_tamper_rejection(self):
        import json
        import tempfile
        from datetime import datetime, timezone
        spec=importlib.util.spec_from_file_location('preservation_bundle',SCRIPTS/'preservation-bundle.py')
        bundle=importlib.util.module_from_spec(spec);spec.loader.exec_module(bundle)
        repo=SCRIPTS.parents[2]
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            op={'schema_version':1,'operation':{'state':'definition','stage':'recovery_preservation','id':'nautobot-recovery-preservation-v1','target':'j2-svpi4mf','authorization_ready':False,'source_commit':'a'*40},
                'plan_sha256':bundle.sha(repo/'Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md'),'accepted_state_sha256':bundle.sha(repo/'Nautobot/manifests/accepted-live-state.yaml'),
                'ci_success_commit':None,'root':'/tmp/nautobot-preservation.'+'a'*32,'token':'a'*32,
                'baseline_collected_at':datetime.now(timezone.utc).isoformat(),'boot_id':'00000000-0000-4000-8000-000000000000',
                'artifact_sha256':{'/var/lib/nautobot/runtime/nautobot_config.py':'a'*64},'app_image_id':'sha256:'+'b'*64,
                'image_ids':{r:'sha256:'+'b'*64 for r in ('postgresql','redis','web','worker','scheduler')},
                'boundaries':{'quiet_window_reserved':True,'stop_and_resume_application_writers':True,'data_service_restart':False,'reboot':False,'restore':False,'cancel_or_purge':False}}
            sections=('postgresql_custom_dump','media','configuration','image_dependency_manifest','quadlet_config_hashes','versions_migrations')
            backup={'schema_version':1,'operation_id':'fixture','authorized':True,'repository_id':'c'*64,'restic':'/usr/bin/restic','restic_version':'fixture','repository_url':'local-fixture','hostname':'fixture',
                'captures':{n:{'argv':['/bin/true'],'maximum_bytes':1024} for n in sections},'dump_validator':['/bin/true'],'source_consistency_reviewed':True,'timeout_seconds':60,'execution_uid':0,'required_filesystem':'tmpfs'}
            sources={'files':{},'consistency':'quiet_pilot_empty_media','quiet_window_confirmed':True,'invocations':{'web':'historical-not-current'}}
            for name,data in [('op',op),('backup',backup),('sources',sources)]: (root/(name+'.json')).write_text(json.dumps(data))
            approval=bundle.freeze(root/'op.json',root/'bundle',root/'backup.json',root/'sources.json')
            bundle.verify(root/'bundle',approval,executing=False)
            self.assertNotIn('invocations',json.loads((root/'bundle/backup-sources.json').read_text()))
            with self.assertRaisesRegex(ValueError,'operation_not_active'): bundle.verify(root/'bundle',approval)
            (root/'bundle/recovery_probe.py').write_text('tampered')
            with self.assertRaisesRegex(ValueError,'bundle_drift'): bundle.verify(root/'bundle',approval,executing=False)

    def test_resource_failure_terminates_owned_producer(self):
        import json
        import os
        import tempfile
        import time
        from unittest.mock import patch
        spec=importlib.util.spec_from_file_location('preservation_guard',SCRIPTS/'preservation-backup.py')
        guard=importlib.util.module_from_spec(spec);spec.loader.exec_module(guard)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); marker=root/'producer.pid'
            (root/'before.json').write_text(json.dumps({'cursor':'fixture','snapshot':{'boot_id':'fixture'}}))
            (root/'application-backup.py').write_text("import os,time,pathlib\npathlib.Path("+repr(str(marker))+").write_text(str(os.getpid()))\nwhile True: time.sleep(1)\n")
            class Reader:
                calls=0
                def __init__(self,*args,**kwargs): pass
                def sample(self):
                    self.calls+=1
                    if self.calls>1:
                        deadline=time.monotonic()+5
                        while not marker.exists() and time.monotonic()<deadline: time.sleep(.01)
                    return {'boot_id':'fixture'}
            with patch.object(sys,'argv',['guard','--root',str(root)]), patch.object(guard.sampler,'Reader',Reader), \
                    patch.object(guard.sampler,'validate',side_effect=[None,ValueError('storage_error')]), patch.object(guard.signal,'signal'):
                self.assertEqual(guard.main(),69)
            receipt=json.loads((root/'backup-resource-review.json').read_text())
            self.assertFalse(receipt['passed'])
            self.assertEqual(receipt['diagnostic']['reason'],'storage_error')
            self.assertTrue(marker.exists())
            with self.assertRaises(ProcessLookupError): os.kill(int(marker.read_text()),0)

    def test_sampler_role_scope_is_explicit(self):
        import workload_sampler as sampler
        self.assertEqual(sampler.Reader('fixture').roles,sampler.ROLES)
        self.assertEqual(sampler.Reader('fixture',roles=('postgresql','redis')).roles,('postgresql','redis'))
        for roles in ((),('unknown',)):
            with self.assertRaises(ValueError): sampler.Reader('fixture',roles=roles)

    def test_inactive_contract_cannot_be_activated(self):
        import json
        import yaml
        import jsonschema
        root = SCRIPTS.parents[1]
        document = yaml.safe_load((root / 'manifests/recovery-preservation.yaml').read_text())
        schema = json.loads((root / 'schemas/recovery-preservation.schema.json').read_text())
        jsonschema.validate(document, schema)
        document['execution_authorized'] = True
        with self.assertRaises(jsonschema.ValidationError):
            jsonschema.validate(document, schema)

    def test_real_ansible_failure_attempts_all_resumes_and_removes_credentials(self):
        import copy
        import json
        import os
        import subprocess
        import tempfile
        import yaml
        root = SCRIPTS.parents[2]
        task = copy.deepcopy(yaml.safe_load((SCRIPTS.parent / 'playbooks/preserve-application.yaml').read_text())[0]['tasks'][0])
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory); stage=base/'stage'; stage.mkdir(); secrets=base/'secrets'; secrets.mkdir()
            evidence=base/'evidence'; evidence.mkdir(); events=base/'resumes'
            for name in ('repository','password','credentials.json'): (secrets/name).write_text('fixture')
            for section in ('block','always'):
                for item in task[section]:
                    if 'ansible.builtin.copy' in item:
                        data=item['ansible.builtin.copy']
                        if 'owner' in data: data['owner']=str(os.getuid()); data['group']=str(os.getgid())
                    if 'ansible.builtin.command' in item:
                        name=item['name']
                        item.pop('async',None); item.pop('poll',None)
                        if name.startswith('Attempt all writer resumes'):
                            code="import pathlib,sys;p=pathlib.Path(sys.argv[1]);p.open('a').write(sys.argv[2]+'\\n');sys.exit(1 if sys.argv[2]=='worker' else 0)"
                            item['ansible.builtin.command']={'argv':[sys.executable,'-c',code,str(events),'{{ item }}']}
                        else:
                            item['ansible.builtin.command']={'argv':['/bin/false' if name.startswith('Execute owning backup') else '/bin/true']}
            play=[{'hosts':'localhost','gather_facts':False,'vars':{'preservation_root':str(stage),'preservation_secrets':str(secrets),'preservation_evidence':str(evidence)},'tasks':[task]}]
            path=base/'play.yaml';path.write_text(yaml.safe_dump(play))
            result=subprocess.run(['/bin/bash',str(root/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','-i','localhost,','-c','local',str(path)],capture_output=True,text=True,timeout=90,cwd=root)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(events.read_text().splitlines(),['worker','web','scheduler'],result.stdout+result.stderr)
            self.assertFalse((stage/'password').exists())
            self.assertFalse((stage/'credentials.json').exists())
            self.assertTrue((evidence/'cleanup.json').exists())

    def test_service_resume_and_cleanup_are_independent(self):
        import yaml
        play = yaml.safe_load((SCRIPTS.parent / 'playbooks/preserve-application.yaml').read_text())[0]
        block = play['tasks'][0]
        cleanup = block['always']
        resume = next(t for t in cleanup if t['name'].startswith('Attempt all writer resumes'))
        self.assertEqual(resume['loop'], ['worker', 'web', 'scheduler'])
        self.assertIs(resume['failed_when'], False)
        secrets = next(t for t in cleanup if t['name'].startswith('Attempt each credential'))
        self.assertEqual(secrets['loop'], ['password', 'credentials.json'])
        self.assertIs(secrets['failed_when'], False)
        self.assertTrue(any('ansible.builtin.assert' in t for t in cleanup))


if __name__ == '__main__':
    unittest.main()
