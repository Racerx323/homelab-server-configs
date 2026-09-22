#!/usr/bin/env python3
"""Offline bootstrap behavior, private handoff and independent cleanup tests."""
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
from unittest.mock import patch, MagicMock
import yaml
from jsonschema import Draft202012Validator, ValidationError
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT/'Nautobot/ansible/scripts'/file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


app = load('bootstrap_app', 'bootstrap-application.py')
node = load('bootstrap_node', 'bootstrap-node.py')
launcher = load('bootstrap_launcher', 'run-runtime.py')
secret = load('bootstrap_secret', 'bootstrap-secret.py')
DATA = {'username': 'admin', 'email': 'fixture@example.invalid', 'password': 'a'*64}


class Bootstrap(unittest.TestCase):
    def operation(self):
        schema = json.loads((ROOT/'Nautobot/schemas/administrator-bootstrap.schema.json').read_text())
        return {k: copy.deepcopy(v['const']) for k, v in schema['properties'].items()}

    def test_native_order_secret_environment_and_no_migration(self):
        calls = []
        def run(argv, timeout):
            calls.append(argv)
            self.assertEqual(timeout, 120)
            self.assertNotIn(DATA['password'], json.dumps(argv))
            self.assertEqual(os.environ.get('DJANGO_SUPERUSER_PASSWORD'), DATA['password'] if argv[1] == 'createsuperuser' else None)
            return {'exit_status': 0, 'output_limited': False}
        with patch.object(app, 'credentials', return_value=DATA):
            value = app.bootstrap(run, inspect=False)
        self.assertTrue(value['passed'])
        self.assertEqual([c[1] for c in calls], ['check','migrate','shell','createsuperuser','shell'])
        self.assertEqual(calls[1], ['nautobot-server','migrate','--check'])
        self.assertEqual(calls[3], ['nautobot-server','createsuperuser','--noinput'])
        self.assertNotIn('DJANGO_SUPERUSER_PASSWORD', os.environ)
        self.assertNotIn(DATA['password'], json.dumps(value))

    def test_every_native_failure_stops_and_is_named(self):
        for failed in range(5):
            calls=[]
            def run(argv, timeout):
                calls.append(argv)
                return {'exit_status': 17 if len(calls)-1 == failed else 0}
            with patch.object(app, 'credentials', return_value=DATA):
                value=app.bootstrap(run, inspect=False)
            self.assertFalse(value['passed'])
            self.assertEqual(len(calls),failed+1)
            self.assertEqual(value['failed_phase'],node.STEPS[failed])
            self.assertEqual(value['creation_attempted'],failed>=3)
            self.assertNotIn('DJANGO_SUPERUSER_PASSWORD',os.environ)

    def test_exception_after_creation_does_not_leak(self):
        def run(argv, timeout):
            if argv[1]=='createsuperuser':raise RuntimeError(DATA['password'])
            return {'exit_status':0}
        with patch.object(app,'credentials',return_value=DATA):value=app.bootstrap(run,inspect=False)
        self.assertTrue(value['creation_attempted'])
        self.assertFalse(value['passed'])
        self.assertNotIn(DATA['password'],json.dumps(value))
        self.assertNotIn('DJANGO_SUPERUSER_PASSWORD',os.environ)

    def test_real_child_output_and_timeout_remain_secret_safe(self):
        for code, timeout in [("print('private-sentinel')",2),("import time;time.sleep(5)",0.05)]:
            value=app.native.command([sys.executable,'-c',code],timeout)
            self.assertNotIn('private-sentinel',json.dumps(value))
        self.assertEqual(value['error'],'timeout')

    def test_input_metadata_and_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'input';p.write_text(json.dumps(DATA));p.chmod(0o600)
            self.assertEqual(app.credentials(p),DATA)
            q=Path(tmp)/'link';q.symlink_to(p)
            with self.assertRaises(ValueError):app.credentials(q)
            p.chmod(0o644)
            with self.assertRaises(ValueError):app.credentials(p)

    def test_private_identity_drift_stops_before_doppler(self):
        with tempfile.TemporaryDirectory(prefix='nautobot-bootstrap.',dir='/dev/shm') as tmp:
            root=Path(tmp);identity=root/'identity.json'
            identity.write_text(json.dumps({k:DATA[k] for k in ('username','email')}));identity.chmod(0o600)
            digest=hashlib.sha256(identity.read_bytes()).hexdigest()
            with patch.object(secret,'IDENTITY',identity),patch.object(secret.provider,'doppler',return_value=DATA['password']) as provider:
                with self.assertRaisesRegex(ValueError,'identity_changed'):secret.resolve(root,'0'*64)
                provider.assert_not_called()
                secret.resolve(root,digest)
                self.assertEqual(json.loads((root/'input.json').read_text()),DATA)
                self.assertEqual((root/'input.json').stat().st_mode & 0o777,0o600)
                provider.assert_called_once_with('secrets','get','NAUTOBOT_INITIAL_ADMIN_PASSWORD','--plain','--config','prd_nautobot')

    def test_configured_user_and_positive_backend(self):
        user=SimpleNamespace(pk=123,email=DATA['email'],is_active=True,is_staff=True,is_superuser=True,get_username=lambda:'admin')
        model=MagicMock();model.USERNAME_FIELD='username';model.objects.filter.return_value.exists.return_value=True;model.objects.get.return_value=user
        auth=SimpleNamespace(get_user_model=lambda:model,authenticate=lambda **kw:user)
        with patch.dict(sys.modules,{'django':MagicMock(),'django.contrib':MagicMock(),'django.contrib.auth':auth}),patch.object(app,'credentials',return_value=DATA):
            with self.assertRaises(SystemExit) as ctx:app.account_phase('absent')
            self.assertEqual(ctx.exception.code,17)
            model.objects.filter.return_value.exists.return_value=False
            app.account_phase('absent');app.account_phase('verify')
            user.is_superuser=False
            with self.assertRaises(SystemExit) as ctx:app.account_phase('verify')
            self.assertEqual(ctx.exception.code,18)
            user.is_superuser=True;auth.authenticate=lambda **kw:None
            with self.assertRaises(SystemExit) as ctx:app.account_phase('verify')
            self.assertEqual(ctx.exception.code,20)

    def test_independent_cleanup_survives_container_and_first_stop_failure(self):
        calls=[]
        def command(argv,*args):
            calls.append(argv)
            if 'nautobot-redis.service' in argv:raise RuntimeError('fixture')
            return ''
        with tempfile.TemporaryDirectory() as tmp:
            transient=Path(tmp)/'missing'
            with patch.object(node,'TRANSIENT',transient),patch.object(node.r,'podman',side_effect=RuntimeError('fixture')),patch.object(node.i,'command',side_effect=command):
                value=node.cleanup(Path(tmp),self.operation())
        self.assertFalse(value['passed']);self.assertFalse(value['cleanup']['probe'])
        self.assertFalse(value['cleanup']['redis']);self.assertTrue(value['cleanup']['postgresql'])
        self.assertTrue(value['cleanup']['input.json']);self.assertTrue(value['cleanup']['directory'])
        self.assertTrue(any('nautobot-postgresql.service' in a for a in calls))

    def test_residue_and_stale_invocations_block(self):
        with patch.object(node.i,'identities'),patch.object(node.i,'stopped',side_effect=ValueError('container_residue')),patch.object(node.os,'geteuid',return_value=0):
            with self.assertRaisesRegex(ValueError,'container_residue'):node.preflight(Path('/tmp'),self.operation())
        before={'before':{'postgresql':{'InvocationID':'a'*32}}}
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'preflight.json').write_text(json.dumps(before))
            with patch.object(node.i,'state',return_value={'ActiveState':'active','InvocationID':'a'*32}):
                with self.assertRaisesRegex(ValueError,'stale_service'):node.c.ready(root,self.operation())

    def test_probe_has_no_admin_environment_listener_or_durable_mount(self):
        args=node.create_args(self.operation())
        self.assertIn('--read-only',args);self.assertIn('--timeout=660',args)
        self.assertIn('--memory=1536m',args);self.assertIn('--memory-swap=1536m',args)
        self.assertIn('--entrypoint=/bin/sleep',args)
        self.assertNotIn('createsuperuser',args);self.assertNotIn('--publish',args)
        self.assertNotIn(DATA['password'],json.dumps(args))
        self.assertNotIn('SUPERUSER',json.dumps(args))
        self.assertFalse(any('_data:' in a for a in args))

    def test_receipt_rejects_secret_and_forged_success(self):
        value={'passed':True,'creation_attempted':True,'steps':{n:{'exit_status':0} for n in node.STEPS}}
        self.assertEqual(node.receipt(json.dumps(value, sort_keys=True)),value)
        for change in ({**value,'password':'private'}, {**value,'steps':{}}, {**value,'creation_attempted':False}):
            with self.assertRaises(ValueError):node.receipt(json.dumps(change))

    def test_schema_rejects_scope_expansion(self):
        op=self.operation();schema=json.loads((ROOT/'Nautobot/schemas/administrator-bootstrap.schema.json').read_text())
        validator=Draft202012Validator(schema);validator.validate(op)
        for section,key,val in [('runtime','first_install_only',True),('runtime','services',['postgresql','redis','web']),('bootstrap','guard_seconds',3600),('failure','automatic_retry',True)]:
            bad=copy.deepcopy(op);bad[section][key]=val
            with self.assertRaises(ValidationError):validator.validate(bad)

    def test_bad_hash_cannot_fetch_credentials_or_contact_host(self):
        with patch.object(launcher,'validate',return_value=self.operation()),patch.object(launcher,'bundle_rows',return_value=[('a'*64,'fixture')]),patch.object(launcher,'verify_prerequisites',side_effect=AssertionError('must stop first')),patch.object(launcher.bounded,'drain_process',side_effect=AssertionError('no execute')):
            with self.assertRaisesRegex(launcher.bounded.PreflightBlocked,'bundle_hash_mismatch'):launcher.execute('0'*64)

    def test_checkout_without_private_identity_fails_closed(self):
        operation=self.operation()
        with tempfile.TemporaryDirectory() as tmp:
            operation['bootstrap']['identity_reference']=str(Path(tmp)/'absent.json')
            with self.assertRaisesRegex(launcher.bounded.PreflightBlocked,'bootstrap_identity_metadata'):
                launcher.bundle_rows(operation)

    def test_interrupted_controller_removes_private_input(self):
        rows=[('a'*64,'fixture')]
        launcher.bounded.BUNDLE_DOMAIN='nautobot-runtime-bundle-v1'
        digest=launcher.bounded.bundle_hash(rows)
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);private=root/'private';private.mkdir(mode=0o700)
            fd=os.open(root,os.O_RDONLY|os.O_DIRECTORY)
            def interrupted(*args):
                (private/'input.json').write_text(json.dumps(DATA))
                raise KeyboardInterrupt()
            with patch.object(launcher,'validate',return_value=self.operation()),patch.object(launcher,'bundle_rows',return_value=rows),patch.object(launcher,'verify_prerequisites'),patch.object(launcher.bounded,'prepare_evidence',return_value=(root,fd)),patch.object(launcher.tempfile,'mkdtemp',return_value=str(private)),patch.object(launcher.bounded,'drain_process',side_effect=interrupted):
                self.assertEqual(launcher.execute(digest),69)
            result=json.loads((root/'result.json').read_text())
            self.assertTrue(result['controller_secret_cleanup'])
            self.assertFalse(private.exists())
            self.assertNotIn(DATA['password'],json.dumps(result))

    def test_ansible_failure_reaches_all_cleanup_tasks(self):
        play=yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/bootstrap-administrator.yaml').read_text())[0]
        guarded=play['tasks'][-1];always=guarded['always']
        disarm=next(t for t in always if t['name'].startswith('Disarm'))
        self.assertEqual(disarm['when'],'bootstrap_stopped.rc | default(69) == 0')
        guard=guarded['block'][0]['ansible.builtin.command']['argv']
        self.assertIn('--on-active=15m',guard);self.assertEqual(guard[-2],'cleanup')
        # Run the actual cleanup task ordering and failure policies with inert commands.
        tasks=[]
        for t in always[:4]:
            q={k:copy.deepcopy(v) for k,v in t.items() if k in ('name','failed_when','ignore_errors','register','no_log')}
            q['ansible.builtin.command']={'argv':['/bin/false']}
            q['changed_when']=False;tasks.append(q)
        tasks.append({'ansible.builtin.assert':{'that':['bootstrap_cleanup.rc == 1','bootstrap_controller_cleanup.rc == 1','bootstrap_stopped.rc == 1']}})
        fixture=[{'hosts':'localhost','gather_facts':False,'tasks':[{'block':[{'ansible.builtin.command':{'argv':['/bin/false']}}],'rescue':[{'ansible.builtin.debug':{'msg':'fixture failure'}}],'always':tasks}]}]
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'play.yaml';path.write_text(yaml.safe_dump(fixture))
            proc=subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','-i','localhost,','-c','local',str(path)],capture_output=True,timeout=60)
            self.assertEqual(proc.returncode,0,proc.stdout.decode()+proc.stderr.decode())


if __name__=='__main__':unittest.main(verbosity=2)
