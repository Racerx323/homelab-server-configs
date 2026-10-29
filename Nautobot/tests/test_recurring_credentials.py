#!/usr/bin/env python3
"""Local credential boundaries; no provider, SSH or live credential operations."""
import copy
from datetime import datetime, timedelta, timezone
import importlib.util
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / 'Nautobot/ansible/scripts'
sys.path.insert(0, str(SCRIPTS))
import recurring_credentials as node
spec = importlib.util.spec_from_file_location('bundle', SCRIPTS / 'recurring-credential-bundle.py')
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)
SCHEMA = json.loads((ROOT / 'Nautobot/schemas/recurring-credentials.schema.json').read_text())


def fixture(root):
    for name, source in bundle.FILES.items():
        if name in ('operation.yaml', 'qualification.json'):
            continue
        path = root / source
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / source, path)
    (root / bundle.FILES['qualification.json']).write_text(json.dumps({'fixture_only': True}))
    props = SCHEMA['properties']
    op = {k: copy.deepcopy(v['const']) for k, v in props.items() if 'const' in v}
    accepted = yaml.safe_load((ROOT / bundle.FILES['accepted.yaml']).read_text())
    op.update(operation=dict(id='disposable-fixture', stage='recurring_credential_provisioning', state='pending',
                             authorization_ready=False, execution_enabled=False, source_commit="0" * 40),
              plan_sha256=bundle.sha(ROOT / bundle.FILES['PLAN.md']),
              accepted_prerequisite={k: accepted['recurring_prerequisites'][k] for k in props['accepted_prerequisite']['required']},
              baseline=dict(artifact_sha256=accepted['application_startup']['artifact_sha256'], mapped_media={'fixture-a': {}, 'fixture-b': {}}))
    for key in ('external_inputs', 'acceptance', 'rollback', 'later_stages'):
        op[key] = ['fixture only']
    (root / bundle.FILES['operation.yaml']).write_text(yaml.safe_dump(op))
    return op


class Credentials(unittest.TestCase):
    def test_real_bundle_and_tamper_refusal(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / 'repo'
            fixture(repo)
            # CI installs Ansible in its Python toolchain, outside system paths.
            toolchain = root / 'toolchain'
            toolchain.mkdir()
            ansible = toolchain / 'ansible-playbook'
            ansible.symlink_to(shutil.which('ansible-playbook'))
            # Freeze hashes Doppler but must never invoke it in this local test.
            doppler = toolchain / 'doppler'
            doppler.write_text('#!/bin/sh\nexit 99\n')
            doppler.chmod(0o700)
            with patch.object(bundle, 'ROOT', repo), patch.object(bundle, 'DOPPLER', str(doppler), create=True), \
                    patch.object(Path, 'home', return_value=root), \
                    patch.dict(os.environ, {'PATH': str(toolchain) + os.pathsep + os.defpath}), patch('builtins.print'):
                bundle.freeze(root / 'candidate')
            controller = json.loads((root / 'candidate/controller.json').read_text())
            self.assertEqual(controller, {str(p): bundle.sha(p) for p in (ansible, doppler)})
            digest = bundle.sha(root / 'candidate/bundle.json')
            op = bundle.verify(root / 'candidate', digest)
            self.assertTrue(op['operation']['execution_enabled'])
            self.assertFalse(yaml.safe_load((repo / bundle.FILES['operation.yaml']).read_text())['operation']['execution_enabled'])
            (root / 'candidate/delivery.yaml').write_text('tampered')
            with self.assertRaisesRegex(ValueError, 'bundle_member'):
                bundle.verify(root / 'candidate', digest)

    def test_scope_expiry_and_sanitized_metadata(self):
        provider = SCHEMA['properties']['provider']['const']
        now = datetime.now(timezone.utc) - timedelta(seconds=2)
        row = dict(project=provider['project'], environment=provider['environment'], config=provider['config'],
                   name=provider['token_name'], access='read', slug='disposable-slug',
                   created_at=now.isoformat(), expires_at=(now + timedelta(days=90)).isoformat(),
                   token='dp.st.' + secrets.token_hex(32))
        metadata = node.token_metadata([row], provider)
        self.assertNotIn(row['token'], json.dumps(metadata))
        self.assertNotIn('token', metadata)
        self.assertEqual(datetime.fromisoformat(metadata['rotation_due_at']), now + timedelta(days=76))
        for key, value in [('access', 'read/write'), ('config', 'prd'),
                           ('expires_at', (now + timedelta(days=100)).isoformat()), ('slug', '../bad')]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                node.token_metadata([{**row, key: value}], provider)
        with self.assertRaises(ValueError):
            node.token_metadata([row, row], provider)

    def test_actual_ansible_delivery_duplicate_refusal_and_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            destination = root / 'credentials'
            token = 'dp.st.' + secrets.token_hex(32)
            op = dict(target=dict(uid=os.getuid(), gid=os.getgid()),
                      delivery=dict(directory=str(destination), token_file=str(destination / 'doppler-service-token'),
                                    metadata_file=str(destination / 'metadata.json')))
            play = [dict(hosts='localhost', gather_facts=False,
                         vars=dict(op=op, issued_token={'stdout': token}, metadata={'stdout': '{"fixture":true}'}),
                         tasks=[dict(name='Actual protected delivery', no_log=True, diff=False,
                                     block=[{'ansible.builtin.include_tasks': str(ROOT / 'Nautobot/ansible/tasks/deliver-recurring-token.yaml')}])])]
            path = root / 'play.yaml'; path.write_text(yaml.safe_dump(play)); path.chmod(0o600)
            env = {**os.environ, 'ANSIBLE_CONFIG': str(ROOT / 'Nautobot/ansible/ansible.cfg'), 'ANSIBLE_NOCOLOR': '1'}
            argv = ['/bin/bash', str(ROOT / 'tests/repository/run-with-ansible-local-temp.sh'),
                    shutil.which('ansible-playbook'), '-i', 'localhost,', '-c', 'local', str(path)]
            result = subprocess.run(argv, env=env, capture_output=True, text=True, timeout=90)
            self.assertNotIn(token, result.stdout + result.stderr)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual((destination / 'doppler-service-token').read_text(), token)
            self.assertEqual(destination.stat().st_mode & 0o777, 0o700)
            for file in destination.iterdir():
                self.assertEqual(file.stat().st_mode & 0o777, 0o600)
            repeated = subprocess.run(argv, env=env, capture_output=True, text=True, timeout=90)
            self.assertNotEqual(repeated.returncode, 0)
            self.assertNotIn(token, repeated.stdout + repeated.stderr)
            self.assertEqual((destination / 'doppler-service-token').read_text(), token)
            node.cleanup(destination, os.getuid(), os.getgid())
            self.assertFalse(destination.exists())
            # Exercise a real copy failure after the token has been delivered.
            play[0]['vars']['op']['delivery']['metadata_file'] = str(destination / 'missing/metadata.json')
            path.write_text(yaml.safe_dump(play))
            partial = subprocess.run(argv, env=env, capture_output=True, text=True, timeout=90)
            self.assertNotEqual(partial.returncode, 0)
            self.assertNotIn(token, partial.stdout + partial.stderr)
            self.assertEqual((destination / 'doppler-service-token').read_text(), token)
            node.cleanup(destination, os.getuid(), os.getgid())
            self.assertFalse(destination.exists())

    def test_cleanup_refuses_unknown_symlink_and_hardlink_without_deletion(self):
        for kind in ('unknown', 'symlink', 'hardlink'):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp); directory = root / 'credentials'; directory.mkdir(mode=0o700)
                token = directory / 'doppler-service-token'; token.write_text('disposable'); token.chmod(0o600)
                extra = directory / ('unknown' if kind == 'unknown' else 'metadata.json')
                if kind == 'symlink':
                    extra.symlink_to(token)
                elif kind == 'hardlink':
                    os.link(token, extra)
                else:
                    extra.write_text('retained')
                with self.assertRaises(ValueError):
                    node.cleanup(directory, os.getuid(), os.getgid())
                self.assertEqual(token.read_text(), 'disposable')
                self.assertTrue(extra.exists())

    def test_provider_and_delivery_are_private_and_later_stages_absent(self):
        play = yaml.safe_load((ROOT / 'Nautobot/ansible/playbooks/provision-recurring-credentials.yaml').read_text())[0]
        stage = next(task for task in play['tasks'] if 'block' in task)
        private = next(task for task in stage['block'] if 'block' in task)
        self.assertTrue(private['no_log']); self.assertFalse(private['diff'])
        raw = json.dumps(play)
        self.assertNotIn('apt-get', raw)
        self.assertNotIn('secrets download', raw)
        self.assertNotIn('configs", "delete', raw)
        self.assertNotIn('ansible.builtin.service', raw)
        self.assertNotIn('ansible.builtin.systemd', raw)


if __name__ == '__main__':
    unittest.main()
