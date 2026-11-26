#!/usr/bin/env python3
"""Offline tests of shared restore decisions and failure boundaries."""
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
# Minimal native-helper inputs; no completed operation or launcher dependency.
CONTRACT = {'repository': {'url': 'local:fixture-repository',
                'id': '0000000000000000000000000000000000000000000000000000000000000000'},
 'restic_version': 'restic fixture',
 'commands': {'common': ['restic',
                         '--no-cache',
                         '--repository-file',
                         'PROTECTED_REPOSITORY_FILE',
                         '--password-file',
                         'PROTECTED_PASSWORD_FILE'],
              'config': ['--no-lock', 'cat', 'config'],
              'snapshots_before': ['--no-lock', 'snapshots', '--json'],
              'backup': ['backup',
                         '--json',
                         '--host',
                         'j2-svpi4mf',
                         '--tag',
                         'nautobot-predata-canary-v1',
                         '--',
                         'SOURCE_ROOT'],
              'snapshots_after': ['--no-lock', 'snapshots', '--json'],
              'integrity': ['check', '--read-data'],
              'locks_after': ['--no-lock', 'list', 'locks']},
 'observation': {'journal_scope': 'cursor_bounded_kernel',
                 'delayed_seconds': 75,
                 'storage_event_pattern': 'I/O error|Buffer I/O|EXT4-fs error|uas_eh_|device '
                                          'reset|reset.*USB|USB.*reset|timed out|timeout',
                 'on_missing_or_truncated_evidence': 'not_accepted'},
 'dataset': {'source_root_pattern': '/var/lib/nautobot/backup-restore-tests/source.*',
             'parent_create_policy': 'create_if_absent_after_parent_mount_and_ownership_verification_never_chown_existing',
             'execution_user': 'nautobot',
             'directory_mode': '0700',
             'file_mode': '0600',
             'required_filesystem': '/dev/sda2',
             'files': [{'path': 'predata/canary.txt',
                        'content_utf8': 'nautobot isolated backup restore verification v1\n',
                        'size_bytes': 49,
                        'sha256': '0b8fefbdc586f053d6e69ee230d119d668e2dc7f4739fe61a334227d61142de2'}],
             'symlinks_allowed': False,
             'retain_source': True},
 'snapshot_identity': {'selection': 'exact_set_difference_from_complete_before_after_snapshots_json',
                       'require_prior_ids_unchanged': True,
                       'new_count': 1,
                       'id_pattern': '^[0-9a-f]{64}$',
                       'hostname': 'j2-svpi4mf',
                       'paths': 'exact_single_source_root',
                       'tags': ['nautobot-predata-canary-v1'],
                       'summary_id_is_not_authority': True}}
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




if __name__ == '__main__':
    unittest.main(verbosity=2)
