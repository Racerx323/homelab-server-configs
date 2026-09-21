#!/usr/bin/env python3
"""Offline producer, watchdog, identity and orchestration failure tests."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import yaml
from jsonschema import Draft202012Validator, ValidationError
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]


def module(name,path):
    spec=importlib.util.spec_from_file_location(name,ROOT/path)
    obj=importlib.util.module_from_spec(spec);spec.loader.exec_module(obj);return obj


c=module('loader','Nautobot/ansible/scripts/load-images.py')
n=module('node','Nautobot/ansible/scripts/image-load-node.py')


class ImageLoad(unittest.TestCase):
    def setUp(self):
        self.p=patch.dict(c.FILES,{'operation.yaml':'Nautobot/tests/fixtures/image-load-operation.yaml'})
        self.p.start();self.addCleanup(self.p.stop)

    def test_prepare_verify_tamper_and_no_host_contact(self):
        with tempfile.TemporaryDirectory() as tmp:
            bundle=Path(tmp)/'bundle';c.prepare(bundle);h=c.sha(bundle/'SHA256SUMS.json');c.verify(bundle,h)
            self.assertEqual(set(json.loads((bundle/'spec.json').read_text())['images']),{'custom','postgresql','redis'})
            (bundle/'node.py').write_text('tampered')
            with patch.object(c.subprocess,'Popen') as contact:
                with self.assertRaises(ValueError):c.execute(bundle,h)
                contact.assert_not_called()

    def test_extra_member_symlink_and_wrong_hash(self):
        for kind in ['extra','symlink','hash']:
            with tempfile.TemporaryDirectory() as tmp:
                b=Path(tmp)/'bundle';c.prepare(b);h=c.sha(b/'SHA256SUMS.json')
                if kind=='extra':(b/'extra').write_text('x')
                if kind=='symlink':(b/'node.py').unlink();(b/'node.py').symlink_to(b/'bounded.py')
                with self.assertRaises(ValueError):c.verify(b,'0'*64 if kind=='hash' else h)

    def test_clean_slot_and_weakened_operation_rejected(self):
        schema=json.loads((ROOT/'Nautobot/schemas/image-load.schema.json').read_text())
        op=copy.deepcopy(schema['const'])
        for section,key,value in [('limits','post_exit_seconds',30),('authorization','mutation_authorized',True),('boundaries','runtime_deployment',True)]:
            bad=copy.deepcopy(op);bad[section][key]=value
            with self.assertRaises(ValidationError):Draft202012Validator(schema).validate(bad)
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'clean';path.write_text('schema_version: 1\noperation: {state: clean, authorization_ready: false}\n')
            with patch.dict(c.FILES,{'operation.yaml':str(path)}):
                with self.assertRaises(ValidationError):c.prepare(Path(tmp)/'bundle')

    def test_inspect_rejects_wrong_platform_digest_id_or_reference(self):
        expected={'reference':'localhost/example@sha256:'+'a'*64,'digest':'sha256:'+'a'*64,'image_id':'sha256:'+'b'*64}
        data={'Os':'linux','Architecture':'arm64','Id':'b'*64,'Digest':expected['digest'],'RepoDigests':[expected['reference']]}
        n.image_check([data],expected)
        for key,value in [('Os','windows'),('Architecture','amd64'),('Id','c'*64),('Digest','sha256:'+'c'*64),('RepoDigests',[])]:
            with self.assertRaises(RuntimeError):n.image_check([{**data,key:value}],expected)
        n.image_check([{**data,'RepoDigests':[]}],expected,repository=False)

    def test_default_network_timestamp_is_not_configuration_drift(self):
        first = {'name': 'podman', 'id': 'same', 'created': 'first', 'subnets': ['reviewed']}
        second = {**first, 'created': 'later'}
        self.assertEqual(n.network_metadata([first]), n.network_metadata([second]))
        self.assertNotEqual(n.network_metadata([first]), n.network_metadata([{**second, 'subnets': ['different']}]))
        with self.assertRaises(RuntimeError): n.network_metadata({})

    def test_secret_listing_uses_name_template_and_metadata_only_inspection(self):
        value = [{'ID': 'fixture', 'Spec': {'Name': 'nautobot-redis-config'}}]
        with patch.object(n, 'pod', side_effect=['nautobot-redis-config\n', json.dumps(value)]) as call:
            self.assertEqual(n.secret_metadata(), value)
            self.assertEqual(call.call_args_list[0].args[0], ['secret', 'ls', '--format', '{{.Name}}'])
            self.assertEqual(call.call_args_list[1].args[0], ['secret', 'inspect', 'nautobot-redis-config'])
        for output in ['', 'json\n', 'other\n', 'nautobot-redis-config\nextra\n']:
            with patch.object(n, 'pod', return_value=output) as call:
                with self.assertRaises(RuntimeError): n.secret_metadata()
                self.assertEqual(call.call_count, 1)
        for output in ['invalid', '{}', '[]', '[{"ID":"fixture","Spec":{"Name":"wrong"}}]']:
            with patch.object(n, 'pod', side_effect=['nautobot-redis-config', output]):
                with self.assertRaises((RuntimeError, ValueError)): n.secret_metadata()

    def test_commands_never_run_container_or_mutable_pull(self):
        spec={'archive':'/reviewed/archive','images':{'custom':{'image_id':'sha256:'+'b'*64},'postgresql':{'reference':'docker.io/library/postgres@sha256:'+'a'*64},'redis':{'reference':'docker.io/library/redis@sha256:'+'c'*64}}}
        self.assertEqual(n.command(spec,'custom'),['load','--input','/reviewed/archive'])
        self.assertEqual(n.command(spec,'alias')[0],'tag')
        for key in ['postgresql','redis']:
            args=n.command(spec,key);self.assertEqual(args[0],'pull');self.assertIn('--retry=0',args);self.assertIn('--tls-verify=true',args)
        with self.assertRaises(RuntimeError):n.command(spec,'web')

    def guard(self,failure=None):
        clock=[0.0]; calls=[]
        class Process:
            returncode=None
            def poll(self):
                if failure not in ('health','gap','timeout'):self.returncode=1 if failure=='command' else 0
                return self.returncode
            def wait(self,timeout=None):self.returncode=0;return 0
        process=Process()
        def sleep(seconds):clock[0]+=20 if failure=='gap' else seconds
        def health(spec):
            if failure=='health' and calls:raise RuntimeError('resource_guard')
            return {'monotonic':clock[0]}
        def launch(*args,**kwargs):calls.append(args[0]);return process
        def run(args,timeout=20):
            if 'stop' in args:calls.append(args);process.returncode=0;return ''
            return 'active' if failure=='residue' else 'inactive'
        with tempfile.TemporaryDirectory(prefix='nautobot-load-test-') as tmp:
            root=Path(tmp);(root/'before.json').write_text('{"cursor":"fixture"}')
            with patch.object(n.time,'monotonic',side_effect=lambda:clock[0]),patch.object(n.time,'sleep',side_effect=sleep),patch.object(n,'health',side_effect=health),patch.object(n,'journal'),patch.object(n,'run',side_effect=run),patch.object(n.subprocess,'Popen',side_effect=launch):
                if failure:
                    with self.assertRaises(RuntimeError):n.guarded(root,{},'custom')
                else:n.guarded(root,{},'custom')
            result=json.loads((root/'custom-result.json').read_text())
            return result,calls

    def test_guard_delayed_observation_and_effective_unit_limits(self):
        result,calls=self.guard();self.assertTrue(result['accepted']);self.assertGreaterEqual(result['post_exit_seconds'],75)
        for flag in ['--property=MemoryMax=3G','--property=MemorySwapMax=0','--property=CPUQuota=200%','--property=RuntimeMaxSec=900','--uid=999']:
            self.assertIn(flag,calls[0])

    def test_guard_command_gap_resource_and_residue_failures(self):
        for failure in ['command','gap','health','timeout','residue']:
            with self.subTest(failure=failure):
                result,calls=self.guard(failure);self.assertFalse(result['accepted'])
                if failure in ('gap','health','timeout'):self.assertTrue(any('stop' in c for c in calls))

    def test_kernel_patterns_and_cursor_failure(self):
        for value in ['usb 2-2: reset SuperSpeed USB device','Buffer I/O error','EXT4-fs error','oom-kill','usb command timed out']:
            self.assertTrue(n.ERRORS.search(value))
        self.assertFalse(n.ERRORS.search('normal disk activity'))
        with patch.object(n,'run',return_value=''):
            with self.assertRaises(RuntimeError):n.journal()
        with patch.object(n,'run',return_value='{"MESSAGE":"reset SuperSpeed USB device"}\n'):
            with self.assertRaises(RuntimeError):n.journal('cursor')

    def test_partial_or_incomplete_results_never_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            spec={'images':{name:{'digest':'digest','reference':'reference','image_id':'id'} for name in ('custom','postgresql','redis')}}
            with self.assertRaises(ValueError):c.evaluate(root,1,spec)
            (root/'after.json').write_text('{"accepted":true,"runtime_started":false}')
            with self.assertRaises(FileNotFoundError):c.evaluate(root,0,spec)
            for name in ('custom','alias','postgresql','redis'):
                (root/(name+'-result.json')).write_text(json.dumps({'accepted':True,'worker_stopped':True,'post_exit_seconds':75,'samples':[{'monotonic':i*5} for i in range(16)]}))
            for name in ('custom','postgresql','redis'):(root/(name+'-image.json')).write_text(json.dumps({'Digest':'digest','RepoDigests':['reference'],'Architecture':'arm64','Os':'linux','Id':'id'}))
            c.evaluate(root,0,spec)
            (root/'redis-result.json').write_text('{"accepted":false}')
            with self.assertRaises(ValueError):c.evaluate(root,0,spec)

    def test_controller_cleanup_failure_cannot_pass(self):
        from types import SimpleNamespace
        original=tempfile.TemporaryDirectory
        original_mkdtemp=tempfile.mkdtemp
        class CleanupFailure:
            def __init__(self,*args,**kwargs):self.inner=original(*args,**kwargs)
            def __enter__(self):return self.inner.__enter__()
            def __exit__(self,*args):
                self.inner.__exit__(*args)
                raise OSError('cleanup fixture')
        with original() as tmp:
            root=Path(tmp);bundle=root/'bundle';c.prepare(bundle)
            evidence=root/'evidence';evidence.mkdir()
            fake=SimpleNamespace(capture=lambda *a,**k:'fixture')
            loader=SimpleNamespace(loader=SimpleNamespace(exec_module=lambda m:None))
            with patch.object(c.tempfile,'mkdtemp',side_effect=lambda *a,**k: str(evidence) if k.get('prefix')=='nautobot-image-load-evidence.' else original_mkdtemp(*a,**k)), patch.object(c.tempfile,'TemporaryDirectory',CleanupFailure), patch.object(c.importlib.util,'spec_from_file_location',return_value=loader), patch.object(c.importlib.util,'module_from_spec',return_value=fake), patch.object(c,'evaluate'):
                self.assertEqual(c.execute(bundle,c.sha(bundle/'SHA256SUMS.json')),69)
            self.assertFalse(json.loads((evidence/'result.json').read_text())['accepted'])

    def test_real_ansible_stops_after_partial_pull_and_collects(self):
        # Exercise the production block, include_tasks and always collection on localhost.
        play=yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/load-images.yaml').read_text())[0]
        block=next(t for t in play['tasks'] if 'block' in t)
        with tempfile.TemporaryDirectory(prefix='image-load-ansible-') as tmp:
            root=Path(tmp);node=root/'node';node.mkdir();evidence=root/'evidence';evidence.mkdir()
            script="""import json,sys
from pathlib import Path
root=Path(sys.argv[2]);mode=sys.argv[1];step=sys.argv[3] if len(sys.argv)>3 else ''
with (root/'trace').open('a') as f:f.write(mode+' '+step+'\\n')
(root/'fixture.json').write_text(json.dumps({'mode':mode,'step':step}))
raise SystemExit(69 if step=='postgresql' else 0)
"""
            (node/'node.py').write_text(script)
            fixture=[{'name':'Production sequencing fixture','hosts':'localhost','gather_facts':False,'vars':{'node':{'path':str(node)},'bundle_root':str(ROOT/'Nautobot/ansible/playbooks'),'evidence_root':str(evidence)},'tasks':[block]}]
            path=root/'play.yaml';path.write_text(yaml.safe_dump(fixture))
            env={**os.environ,'ANSIBLE_NOCOLOR':'1','ANSIBLE_LOCAL_TEMP':str(root/'ansible-tmp')}
            p=subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','-i','localhost,','-c','local',str(path)],capture_output=True,text=True,env=env,timeout=90)
            self.assertNotEqual(p.returncode,0)
            self.assertTrue((node/'trace').exists(),p.stdout+p.stderr)
            trace=(node/'trace').read_text();self.assertIn('guarded postgresql',trace);self.assertNotIn('redis',trace);self.assertNotIn('after',trace)
            self.assertTrue((evidence/'fixture.json').exists(),p.stdout+p.stderr)


if __name__=='__main__':unittest.main()
