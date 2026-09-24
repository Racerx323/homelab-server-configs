#!/usr/bin/env python3
"""Exercise phase, dispatch ownership and backup-overlap decisions offline."""
import copy
import importlib.util
import hashlib
import shutil
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from concurrent.futures import Future
import yaml

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT/'Nautobot/ansible/scripts'
sys.path.insert(0, str(SCRIPTS))
import workload_session as session
spec = importlib.util.spec_from_file_location('launcher', SCRIPTS/'run-workload.py')
launcher = importlib.util.module_from_spec(spec); spec.loader.exec_module(launcher)
CONTRACT = yaml.safe_load((ROOT/'Nautobot/manifests/workload-test.yaml').read_text())


def backup():
    return {'kind': 'application_backup', 'operation_id': 'test', 'upload_passed': True, 'integrity_passed': True,
            'credential_cleanup': {'password': True, 'credentials.json': True},
            'snapshot_id': 'a'*64, 'content_sha256': {k: 'b'*64 for k in ('postgresql_custom_dump', 'media', 'configuration', 'image_dependency_manifest', 'quadlet_config_hashes', 'versions_migrations')},
            'started': 0, 'finished': 100000}


class WorkloadOrchestrationTests(unittest.TestCase):
    def test_backup_requires_real_content_identity_success_and_actual_overlap(self):
        jobs = [{'started': 1, 'done': 2}]
        session.verify_backup(backup(), jobs, 'test')
        for change in ({'kind': 'canary'}, {'operation_id': 'other'}, {'integrity_passed': False},
                       {'snapshot_id': 'latest'}, {'content_sha256': {}}, {'credential_cleanup': {}}, {'started': 3, 'finished': 4}):
            with self.subTest(change=change):
                with self.assertRaises(ValueError): session.verify_backup(dict(backup(), **change), jobs, 'test')
        with self.assertRaises(ValueError): session.verify_backup(backup(), [{'started': None, 'done': None}], 'test')

    def test_dispatch_ownership_is_durable_before_client_call(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            def client(request):
                self.assertEqual(json.loads((root/'owned-jobs.json').read_text()), [x['id'] for x in request['requests']])
                raise RuntimeError('transport_lost_after_dispatch')
            runner = session.Session(root, CONTRACT, client, backup)
            with self.assertRaises(RuntimeError): runner.submit('audit', {}, count=2)
            self.assertEqual(len(runner.owned), 2)

    def test_all_phases_and_counts_use_contract(self):
        contract = copy.deepcopy(CONTRACT)
        for p in contract['phases']: p['minimum_seconds'] = 2
        now = [0]
        requests = []
        def client(request):
            if request['action'] == 'submit_batch':
                requests.extend(request['requests']); return {}
            item = next(r for r in requests if r['id'] == request['id'])
            result = {'sha256': 'c'*64}
            if item['kind'] == 'import': result['receipt'] = {'objects': {'owned': 'id'}}
            return {'id': request['id'], 'status': 'SUCCESS', 'terminal': True, 'started': now[0], 'done': now[0]+1, 'result': result}
        with tempfile.TemporaryDirectory() as d:
            runner = session.Session(Path(d), contract, client, backup, clock=lambda: now[0], sleep=lambda x: now.__setitem__(0, now[0]+x))
            result = runner.execute({}, 'test')
            self.assertTrue(result['backup_overlap_passed'])
            self.assertEqual([sum(r['kind'] == k for r in requests) for k in ('import', 'export', 'audit')], [2, 3, 10])
            self.assertEqual(len(runner.phases), 5)
            self.assertTrue(all(a['end'] == b['start'] for a, b in zip(runner.phases, runner.phases[1:])))

    def test_sampler_failure_stops_further_submissions(self):
        with tempfile.TemporaryDirectory() as d:
            calls = []
            runner = session.Session(Path(d), CONTRACT, calls.append, backup)
            runner.monitor = Future(); runner.monitor.set_exception(ValueError('storage_error'))
            with self.assertRaisesRegex(ValueError, 'storage_error'): runner.submit('import', {})
            self.assertEqual(calls, [])
            self.assertEqual(runner.owned, [])

    def test_worker_absence_requires_positive_complete_replies(self):
        import workload_control
        self.assertTrue(workload_control.revoke_acknowledged([{'worker':{'ok':'task flagged as revoked'}}]))
        for replies in (None, [], [{'worker':{'error':'no'}}], [{'one':{'ok':'yes'},'two':{'ok':'yes'}}]):
            self.assertFalse(workload_control.revoke_acknowledged(replies))
        class Inspector:
            def __init__(self, peers, replies):self.peers,self.replies=peers,replies
            def ping(self):return self.peers
            def query_task(self, identity):return self.replies
        self.assertTrue(workload_control.confirmed_worker_absence('owned',Inspector({'worker':{'ok':'pong'}},{'worker':{}})))
        for peers,replies in [(None,None),({'worker':{'ok':'pong'}},None),({'worker':{'ok':'pong'}},{'other':{}}),
                              ({'worker':{'ok':'pong'}},{'worker':{'error':'bad'}}),
                              ({'worker':{'ok':'pong'}},{'worker':{'owned':['active',{}]}}),
                              ({'one':{'ok':'pong'},'two':{'ok':'pong'}},{'one':{}})]:
            self.assertFalse(workload_control.confirmed_worker_absence('owned',Inspector(peers,replies)))

    def test_native_bridge_preserves_file_limits_and_bounds_failures(self):
        import resource
        raw=session.native_command(['/usr/bin/python3','-c','import resource,json;print(json.dumps(resource.getrlimit(resource.RLIMIT_FSIZE)))'],b'')
        self.assertEqual(json.loads(raw),list(resource.getrlimit(resource.RLIMIT_FSIZE)))
        with self.assertRaisesRegex(ValueError,'native_bridge_timeout'):
            session.native_command(['/bin/sleep','5'],b'',timeout=0.05)
        with self.assertRaisesRegex(ValueError,'native_bridge_'):
            session.native_command(['/usr/bin/python3','-c','print("x"*5000000)'],b'')

    def test_backup_failure_stops_new_job_submissions(self):
        with tempfile.TemporaryDirectory() as d:
            calls=[]
            runner=session.Session(Path(d), CONTRACT, calls.append, backup)
            runner.backup_future=Future()
            runner.backup_future.set_exception(ValueError('backup_integrity_failed'))
            with self.assertRaisesRegex(ValueError, 'backup_integrity_failed'):
                runner.submit('audit', {}, count=2)
            self.assertEqual(calls, [])
            self.assertEqual(runner.owned, [])

    def test_cancel_keeps_unknown_worker_state_unresolved_and_attempts_all_ids(self):
        with tempfile.TemporaryDirectory() as d:
            calls = []
            def client(request):
                calls.append(request['id'])
                if request['id'] == 'one': raise RuntimeError('unreachable')
                return {'terminal': True, 'worker_absent': False}
            runner = session.Session(Path(d), CONTRACT, client, backup)
            runner.owned = ['one', 'two']
            self.assertFalse(runner.cancel_owned())
            self.assertEqual(calls, ['one', 'two'])
            self.assertEqual(len(json.loads((Path(d)/'stop-results.json').read_text())), 2)

    def test_job_failure_cancels_owned_work_and_preserves_receipt(self):
        contract = copy.deepcopy(CONTRACT); contract['phases'] = [contract['phases'][1]]
        calls = []
        def client(request):
            calls.append(request)
            if request['action'] == 'submit_batch': return {}
            if request['action'] == 'cancel': return {'terminal': True, 'worker_absent': True}
            return {'terminal': True, 'status': 'FAILURE', 'started': 1, 'done': 2}
        with tempfile.TemporaryDirectory() as d:
            runner = session.Session(Path(d), contract, client, backup)
            with self.assertRaisesRegex(ValueError, 'job_failed'): runner.execute({}, 'test')
            self.assertTrue(any(c['action'] == 'cancel' for c in calls))
            self.assertTrue((Path(d)/'owned-jobs.json').exists())
            self.assertTrue((Path(d)/'stop-results.json').exists())

    def test_actual_playbook_rejects_inactive_operation_locally(self):
        with tempfile.TemporaryDirectory() as d:
            inventory = Path(d)/'inventory.yaml'
            inventory.write_text('all:\n  children:\n    inventory_automation:\n      hosts:\n        j2-svpi4mf:\n          ansible_connection: local\n')
            result = subprocess.run(['ansible-playbook', '-i', str(inventory),
                str(ROOT/'Nautobot/ansible/playbooks/run-workload.yaml')], capture_output=True, timeout=30, cwd=ROOT)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b'Reject unverified or unreviewed activation before target contact', result.stdout)
            self.assertNotIn(b'TASK [Require a new protected operation directory]', result.stdout)

    def test_complete_bundle_validation_and_input_drift(self):
        import workload_sampler
        import jsonschema
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for name in launcher.REQUIRED - {'execution.json', 'contract.json', 'dataset.json', 'application-backup.json'}:
                source = ROOT/'restic/scripts'/name if name == 'application-backup.py' else (ROOT/'Nautobot/ansible/playbooks'/name if name.endswith('.yaml') else SCRIPTS/name)
                shutil.copyfile(source, root/name)
            execution = {'schema_version': 1, 'stage': 'workload_qualification', 'execution_authorized': True,
                'operation_id': 'offline-fixture', 'root': '/tmp/nautobot-workload.'+'a'*32,
                'boot_id': '00000000-0000-0000-0000-000000000000', 'journal_cursor': 'offline-only',
                'baseline_review': {'passed': True, 'boot_id': '00000000-0000-0000-0000-000000000000',
                    'services': {r: {'memory_max': 1024, 'invocation': 'a'*32} for r in workload_sampler.ROLES}},
                'backup': {'authorized': True, 'argv': ['/usr/bin/python3', '/tmp/nautobot-workload.'+'a'*32+'/application-backup.py', '--root', '/tmp/nautobot-workload.'+'a'*32],
                           'receipt': '/tmp/nautobot-workload.'+'a'*32+'/application-backup-result.json'}}
            (root/'execution.json').write_text(json.dumps(execution))
            (root/'contract.json').write_text(json.dumps(CONTRACT))
            spec = importlib.util.spec_from_file_location('generator', SCRIPTS/'make-workload-fixture.py')
            generator = importlib.util.module_from_spec(spec); spec.loader.exec_module(generator)
            (root/'dataset.json').write_bytes(generator.canonical(generator.dataset(CONTRACT)))
            producer_tests = importlib.util.spec_from_file_location('producer_tests', ROOT/'restic/tests/test_application_backup.py')
            pt = importlib.util.module_from_spec(producer_tests); producer_tests.loader.exec_module(pt)
            specification = pt.contract(); specification['operation_id'] = execution['operation_id']
            (root/'application-backup.json').write_text(json.dumps(specification))
            manifest = {'files': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in root.iterdir()},
                        'source_files': {p: hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in launcher.SOURCE_FILES}}
            raw = json.dumps(manifest).encode(); (root/'bundle.json').write_bytes(raw)
            approval = hashlib.sha256(raw).hexdigest()
            _, actual = launcher.verify(root, approval)
            self.assertEqual(actual, execution)
            (root/'workload_session.py').write_text('changed')
            with self.assertRaisesRegex(ValueError, 'input_identity'): launcher.verify(root, approval)
            schema = json.loads((ROOT/'Nautobot/schemas/workload-execution.schema.json').read_text())
            for invalid in (dict(execution, unexpected=True), dict(execution, stage='initialization')):
                with self.assertRaises(jsonschema.ValidationError): jsonschema.validate(invalid, schema)

    def test_bundle_hash_rejects_before_reading_activation(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d); (p/'bundle.json').write_text('{}')
            with self.assertRaisesRegex(ValueError, 'bundle_identity'): launcher.verify(p, '0'*64)


if __name__ == '__main__': unittest.main()
