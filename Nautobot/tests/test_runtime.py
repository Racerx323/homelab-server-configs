#!/usr/bin/env python3
"""Local rendering and installed Quadlet-generator tests; no container execution."""
import copy
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import yaml

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('render',ROOT/'Nautobot/ansible/scripts/render-runtime.py')
renderer=importlib.util.module_from_spec(spec);spec.loader.exec_module(renderer)

class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.desired=yaml.safe_load((ROOT/'Nautobot/manifests/desired-state.yaml').read_text())
        # Offline-only synthetic digest; never a deployable image.
        self.inputs={'custom_image':'localhost/offline-fixture@sha256:'+'a'*64,'recovery_host':'recovery.example.invalid'}
    def test_deterministic_and_private(self):
        files=renderer.render(self.desired,self.inputs)
        self.assertEqual(files,renderer.render(self.desired,self.inputs))
        self.assertEqual(len(files),11)
        for name,text in files.items():
            if name.endswith('.container'):
                self.assertIn('Pull=never',text)
                if 'web' not in name:self.assertNotIn('PublishPort=',text)
        web=files['nautobot-web.container']
        self.assertIn('PublishPort=10.1.2.170:8080:8080',web)
        self.assertIn('PublishPort=[fd36:5aa8:6971:1::170]:8080:8080',web)
    def test_migration_dependency_and_limits(self):
        files=renderer.render(self.desired,self.inputs)
        for role in ('web','worker','scheduler'):
            self.assertIn('Requires=nautobot-migration.service',files[f'nautobot-{role}.container'])
            self.assertIn('\nAfter=nautobot-migration.service',files[f'nautobot-{role}.container'])
        migration=files['nautobot-migration.container']
        self.assertIn('Type=oneshot',migration);self.assertIn('Restart=no',migration)
        self.assertIn('Exec=post_upgrade',migration)
        for role,limit in [('web',1536),('worker',1536),('scheduler',384),('postgresql',1536),('redis',512)]:
            self.assertIn(f'--memory={limit}m',files[f'nautobot-{role}.container'])
    def test_reject_unsafe_inputs(self):
        for value in ['latest','repo:latest','repo@sha256:'+'a'*64+'\nExec=oops']:
            with self.assertRaises(ValueError):renderer.render(self.desired,{**self.inputs,'custom_image':value})
        with self.assertRaises(ValueError):renderer.render(self.desired,{**self.inputs,'recovery_host':'a\nb'})
        bad=copy.deepcopy(self.desired);bad['services']['postgresql']['published_endpoints']=[{'address':'0.0.0.0'}]
        with self.assertRaises(ValueError):renderer.render(bad,self.inputs)
    def test_fixture_counts_and_determinism(self):
        fixture_spec=importlib.util.spec_from_file_location('fixture',ROOT/'Nautobot/ansible/scripts/make-workload-fixture.py')
        fixture=importlib.util.module_from_spec(fixture_spec);fixture_spec.loader.exec_module(fixture)
        data=fixture.dataset()
        self.assertEqual(fixture.canonical(data),fixture.canonical(fixture.dataset()))
        self.assertEqual(len(data['locations']),10)
        self.assertEqual(len(data['devices']),500)
        self.assertEqual(sum(len(d['interfaces']) for d in data['devices']),2000)
        self.assertEqual(len({a['address'] for a in data['ip_assignments']}),500)
        devices={d['key'] for d in data['devices']}
        self.assertTrue(all(a['device'] in devices for a in data['ip_assignments']))

    def test_inactive_playbook_gate_locally(self):
        production=yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/deploy-runtime.yaml').read_text())[0]
        operation=yaml.safe_load((ROOT/'Nautobot/manifests/operation.yaml').read_text())
        with tempfile.TemporaryDirectory(prefix='nautobot-runtime-gate.') as tmp:
            p=Path(tmp)/'gate.yaml'
            fixture=[{'hosts':'j2-svpi4mf','gather_facts':False,'vars':{'runtime_operation':operation},'tasks':production['pre_tasks'][:1]}]
            p.write_text(yaml.safe_dump(fixture))
            result=subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','-i','j2-svpi4mf,','-c','local',str(p)],capture_output=True,timeout=30)
            self.assertEqual(result.returncode,2,result.stdout.decode()+result.stderr.decode())
            self.assertIn(b'Runtime definition is inactive',result.stdout)

    def test_launcher_rejects_current_operation(self):
        spec=importlib.util.spec_from_file_location('runtime_launcher',ROOT/'Nautobot/ansible/scripts/run-runtime.py')
        mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
        from unittest.mock import patch
        with patch.object(mod.bounded,'drain_process',side_effect=AssertionError('no execution allowed')):
            with self.assertRaises(mod.bounded.PreflightBlocked):mod.execute('0'*64)

    def test_migration_failure_cannot_continue_loop(self):
        play=yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/deploy-runtime.yaml').read_text())[0]
        starts=[t for t in play['tasks'][0]['block'] if t['name'].startswith('Start ')]
        self.assertEqual(len(starts),6)
        self.assertTrue(all('loop' not in t and not t.get('ignore_errors') for t in starts))
        self.assertIn('migration',starts[2]['name'])
        self.assertIn('web',starts[3]['name'])

    def test_generator(self):
        generator=Path(os.environ.get('NAUTOBOT_QUADLET_GENERATOR', '/usr/lib/systemd/system-generators/podman-system-generator'))
        self.assertTrue(generator.is_file(),'Quadlet generator required for this test')
        with tempfile.TemporaryDirectory(prefix='nautobot-runtime-test.') as tmp:
            root=Path(tmp);units=root/'units';output=root/'generated';units.mkdir();output.mkdir()
            for name,text in renderer.render(self.desired,self.inputs).items():(units/name).write_text(text)
            env={**os.environ,'QUADLET_UNIT_DIRS':str(units)}
            result=subprocess.run([str(generator),'--user',str(output)],env=env,capture_output=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stderr.decode())
            for role in renderer.SERVICES:
                p=output/f'nautobot-{role}.service'
                self.assertTrue(p.exists(),result.stderr.decode())
            web=(output/'nautobot-web.service').read_text()
            self.assertIn('--memory=1536m',web)
            self.assertIn('nautobot-migration.service',web)
            self.assertNotIn('--publish',(output/'nautobot-postgresql.service').read_text())

if __name__=='__main__':unittest.main()
