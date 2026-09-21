#!/usr/bin/env python3
"""Offline tests of actual canary decisions, cleanup tasks and launcher gates."""
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
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


helper = load('canary', 'restic/scripts/canary-backup.py')
launcher = load('canary_launcher', 'Nautobot/ansible/scripts/run-canary-backup.py')
SCHEMA = json.loads((ROOT / 'Nautobot/schemas/canary-backup.schema.json').read_text())
CONTRACT = {k: copy.deepcopy(v['const']) for k, v in SCHEMA['properties'].items()}
SID = 'a' * 64


class Workload(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.source = self.root / 'source'
        self.source.mkdir(mode=0o700)
        (self.source / 'predata').mkdir(mode=0o700)
        p = self.source / 'predata/canary.txt'
        p.write_text(CONTRACT['dataset']['files'][0]['content_utf8']); p.chmod(0o600)
        for name, value in {'repository': CONTRACT['repository']['url'],
                            'password': 'offline-password',
                            'operation.json': json.dumps(CONTRACT),
                            'credentials.json': json.dumps({'id': 'offline-id', 'key': 'offline-key'})}.items():
            p = self.root / name; p.write_text(value); p.chmod(0o600)
        self.calls = []

    def tearDown(self):
        self.tmp.cleanup()

    def snapshot(self):
        return {'id': SID, 'hostname': 'j2-svpi4mf', 'paths': [str(self.source)],
                'tags': ['nautobot-predata-canary-v1']}

    def run_case(self, backup_status=0, check_status=0, timeout=False, version=None,
                 config=None, after=None, locks=b'', mutate=False):
        responses = [(0, (version or CONTRACT['restic_version']).encode()),
                     (0, json.dumps(config or {'id': CONTRACT['repository']['id'], 'version': 2}).encode()),
                     (0, b'[]'), (backup_status, b'ignored'),
                     (0, json.dumps([self.snapshot()] if after is None else after).encode()),
                     (check_status, b'ignored'), (0, locks)]
        def runner(argv, env, limit):
            self.calls.append(argv)
            self.assertLessEqual(limit, 600)
            if timeout and len(self.calls) == 4:
                raise helper.Blocked('command_timeout')
            if mutate and len(self.calls) == 6:
                (self.source / 'predata/canary.txt').write_text('changed')
            return responses[len(self.calls)-1]
        return helper.backup(self.root, CONTRACT, runner,
                             source_factory=lambda *_: self.source)

    def test_success_and_no_replay(self):
        result = self.run_case()
        self.assertEqual(result['result'], 'backup_integrity_review_required')
        self.assertEqual(result['snapshot_id'], SID)
        self.assertIn('--read-data', self.calls[5])
        self.assertNotIn('--no-lock', self.calls[3])
        self.assertNotIn('--no-lock', self.calls[5])
        with self.assertRaises(FileExistsError): self.run_case()
        self.assertEqual(len(self.calls), 7)

    def test_incomplete_upload_retains_evidence_no_integrity(self):
        r = self.run_case(backup_status=3)
        self.assertTrue(r['upload_attempted'])
        self.assertEqual(r['error_class'], 'backup_failed_no_retry')
        self.assertEqual(len(self.calls), 5)
        self.assertTrue((self.root / 'snapshots-after.json').exists())
        self.assertTrue(self.source.exists())

    def test_interruption_preserves_attempt(self):
        r = self.run_case(timeout=True)
        self.assertTrue(r['upload_attempted'])
        self.assertIsNone(r['backup_exit_status'])
        self.assertTrue((self.root / 'upload-attempt.json').exists())
        self.assertEqual(len(self.calls), 4)

    def test_integrity_failure_retains_snapshot(self):
        r = self.run_case(check_status=1)
        self.assertEqual(r['snapshot_id'], SID)
        self.assertEqual(r['error_class'], 'integrity_failed')
        self.assertEqual(len(self.calls), 6)

    def test_version_mismatch_prevents_upload(self):
        self.assertFalse(self.run_case(version='wrong')['upload_attempted'])
        self.assertEqual(len(self.calls), 1)

    def test_repository_mismatch_prevents_upload(self):
        self.assertFalse(self.run_case(config={'id': 'b'*64, 'version': 2})['upload_attempted'])
        self.assertEqual(len(self.calls), 2)

    def test_no_snapshot_prevents_check(self):
        self.assertEqual(self.run_case(after=[])['error_class'], 'new_snapshot_count')
        self.assertEqual(len(self.calls), 5)

    def test_source_change_blocks_acceptance(self):
        self.assertEqual(self.run_case(mutate=True)['error_class'], 'source_content_mismatch')

    def test_lock_residue_blocks_acceptance(self):
        self.assertEqual(self.run_case(locks=b'lock')['error_class'], 'lock_or_cache_absence_unproved')

    def test_source_modes_and_symlink(self):
        p = self.source / 'predata/canary.txt'; p.chmod(0o644)
        with self.assertRaises(helper.Blocked): helper.tree(self.source, CONTRACT['dataset'])
        p.unlink(); p.symlink_to(self.root / 'password')
        with self.assertRaises(helper.Blocked): helper.tree(self.source, CONTRACT['dataset'])

    def test_mount_mismatch_before_creation(self):
        contract = copy.deepcopy(CONTRACT['dataset'])
        contract['source_root_pattern'] = str(self.root / 'new-parent/source.*')
        with self.assertRaisesRegex(helper.Blocked, 'source_mount_mismatch'):
            helper.create_source(contract, lambda *_: (0, b'/dev/wrong\n'))
        self.assertFalse((self.root / 'new-parent').exists())

    def test_sanitized_records(self):
        self.run_case()
        for p in self.root.glob('*.json'):
            if p.name not in ('credentials.json', 'operation.json'):
                for secret in ('offline-password', 'offline-id', 'offline-key'):
                    self.assertNotIn(secret, p.read_text())

    def test_snapshot_selection_rejects_malformed_and_wrong_metadata(self):
        for raw in (b'{}', b'not-json', b'[{"id":"short"}]'):
            with self.assertRaises((helper.Blocked, ValueError)): helper.snapshots(raw)
        good = self.snapshot()
        for key, value in [('hostname', 'other'), ('paths', ['/other']), ('tags', ['other'])]:
            bad = {**good, key: value}
            with self.assertRaises(helper.Blocked):
                helper.select_snapshot({}, {SID: bad}, self.source, CONTRACT['snapshot_identity'])
        for before, after in [({SID: good}, {}), ({}, {}), ({}, {SID: good, 'b'*64: good})]:
            with self.assertRaises(helper.Blocked):
                helper.select_snapshot(before, after, self.source, CONTRACT['snapshot_identity'])


class Boundaries(unittest.TestCase):
    def test_wrong_hash_or_stage_never_resolves_credentials(self):
        with patch.object(launcher.common, 'read_secret', side_effect=AssertionError('external access')):
            with self.assertRaises(launcher.common.PreflightBlocked):
                launcher.transport.execute('0'*64)

    def test_journal_missing_truncated_boot_changed_and_event(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
            (root / 'journal-baseline.json').write_text(json.dumps({'boot_id': boot, 'cursor': 'cursor'}))
            def call_with(lines, first=b'{"__CURSOR":"cursor"}\n'):
                responses = iter([(0, first), (0, lines)])
                with patch.object(helper.time, 'monotonic', side_effect=[0, 75]):
                    return helper.journal('journal-review', root, CONTRACT,
                                          runner=lambda *_: next(responses), sleeper=lambda _: None)
            self.assertTrue(call_with(b'')['passed'])
            self.assertFalse(call_with(b'{"MESSAGE":"reset SuperSpeed USB device"}\n')['passed'])
            with self.assertRaises(helper.Blocked): call_with(b'', b'')
            with self.assertRaises(ValueError): call_with(b'{truncated')
            with patch.object(helper.time, 'monotonic', side_effect=[0, 2]):
                with self.assertRaisesRegex(helper.Blocked, 'observation_incomplete'):
                    helper.journal('journal-review', root, CONTRACT, sleeper=lambda _: None)
            (root / 'journal-baseline.json').write_text(json.dumps({'boot_id': 'old', 'cursor': 'cursor'}))
            with self.assertRaisesRegex(helper.Blocked, 'boot_changed'): call_with(b'')

    def test_capture_timeout_and_output_bound(self):
        with self.assertRaisesRegex(helper.Blocked, 'command_timeout'):
            helper.invoke([sys.executable, '-c', 'import time; time.sleep(2)'],
                          {'PATH': '/usr/bin:/bin'}, timeout=0.05)
        with patch.object(helper, 'LIMIT', 1024):
            with self.assertRaisesRegex(helper.Blocked, 'output_limit'):
                helper.invoke([sys.executable, '-c', 'import os; os.write(1,b"x"*2048)'],
                              {'PATH': '/usr/bin:/bin'})

    def test_canary_playbook_syntax(self):
        result = subprocess.run(['/bin/bash', str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),
                                 'ansible-playbook', '--syntax-check', '--inventory',
                                 str(ROOT/'inventory/prod/hosts.yaml'),
                                 str(ROOT/'Nautobot/ansible/playbooks/backup-canary.yaml')],
                                capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout.decode()+result.stderr.decode())

    def test_real_production_cleanup_tasks(self):
        play = yaml.safe_load((ROOT / 'Nautobot/ansible/playbooks/backup-canary.yaml').read_text())[0]
        cleanup = copy.deepcopy(play['tasks'][2]['always'])
        for task in cleanup:
            if 'ansible.builtin.command' in task:
                task['ansible.builtin.command']['argv'] = task['ansible.builtin.command']['argv'][6:]
        for failure in ('none', 'workload', 'first_cleanup'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                for name in ('repository', 'password', 'credentials.json'):
                    (root / name).write_text('offline-secret')
                (root / 'result.json').write_text('{"upload_attempted":true,"result":"blocked"}')
                tasks = copy.deepcopy(cleanup)
                if failure == 'first_cleanup': tasks[0]['ansible.builtin.command']['argv'] = ['/bin/false']
                fixture = [{'hosts': 'localhost', 'gather_facts': False,
                            'vars': {'canary_directory': {'stdout': directory}, 'canary_evidence_root': directory},
                            'tasks': [{'block': [{'ansible.builtin.command': {'argv': ['/bin/false' if failure == 'workload' else '/bin/true']}}],
                                       'always': tasks}]}]
                f = root / 'play.yaml'; f.write_text(yaml.safe_dump(fixture))
                result = subprocess.run(['/bin/bash', str(ROOT / 'tests/repository/run-with-ansible-local-temp.sh'),
                                         'ansible-playbook', '-i', 'localhost,', '-c', 'local', str(f)],
                                        capture_output=True, timeout=60)
                self.assertEqual(result.returncode, 0 if failure == 'none' else 2, result.stdout.decode())
                for name in ('password', 'credentials.json'): self.assertFalse((root / name).exists())
                self.assertTrue((root / 'node-records.json').exists())
                self.assertNotIn(b'offline-secret', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
