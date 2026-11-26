#!/usr/bin/env python3
"""Offline tests of shared restore decisions and failure boundaries."""
import copy
import hashlib
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


helper = load('restore', 'restic/scripts/restore-canary.py')
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
              'snapshot_metadata': ['--no-lock',
                                    'cat',
                                    'snapshot',
                                    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'],
              'restore': ['restore',
                          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:/var/lib/nautobot/backup-restore-tests/source.4cp8z75y',
                          '--target',
                          'NEW_EMPTY_RESTORE_ROOT'],
              'locks_after': ['--no-lock', 'list', 'locks']},
 'observation': {'journal_scope': 'cursor_bounded_kernel',
                 'delayed_seconds': 75,
                 'storage_event_pattern': 'I/O error|Buffer I/O|EXT4-fs error|uas_eh_|device '
                                          'reset|reset.*USB|USB.*reset|timed out|timeout',
                 'on_missing_or_truncated_evidence': 'not_accepted'},
 'snapshot': {'id': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              'source_root': '/var/lib/nautobot/backup-restore-tests/source.4cp8z75y',
              'metadata': {'hostname': 'j2-svpi4mf',
                           'id': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                           'paths': ['/var/lib/nautobot/backup-restore-tests/source.4cp8z75y'],
                           'tags': ['nautobot-predata-canary-v1']},
              'selection': 'exact_full_id_and_exact_archived_subdirectory',
              'restore_selector': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:/var/lib/nautobot/backup-restore-tests/source.4cp8z75y'},
 'destination': {'root_pattern': '/var/lib/nautobot/backup-restore-tests/restore.*',
                 'parent_must_exist': True,
                 'new_empty_directory_required': True,
                 'owner': 'nautobot',
                 'directory_mode': '0700',
                 'required_filesystem': '/dev/sda2',
                 'symlink_ancestors_allowed': False,
                 'source_overlap_allowed': False,
                 'existing_destination_reuse_allowed': False,
                 'retain_after_success_and_failure': True},
 'expected_tree': {'relative_directories': [{'path': 'predata', 'mode': '0700'}],
                   'files': [{'path': 'predata/canary.txt',
                              'content_utf8': 'nautobot isolated backup restore verification v1\n',
                              'size_bytes': 49,
                              'sha256': '0b8fefbdc586f053d6e69ee230d119d668e2dc7f4739fe61a334227d61142de2'}],
                   'file_mode': '0600',
                   'owner': 'nautobot',
                   'extra_paths_allowed': False,
                   'symlinks_allowed': False,
                   'special_files_allowed': False,
                   'comparison_source': 'independent_manifest_fixture',
                   'require_original_source_unchanged': True}}
SID = 'a' * 64


class Workload(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.contract = copy.deepcopy(CONTRACT)
        self.source = self.root / 'source.original'
        self.make_tree(self.source)
        self.contract['snapshot']['source_root'] = str(self.source)
        self.contract['destination']['root_pattern'] = str(self.root / 'restore.*')
        for name, value in {'repository': CONTRACT['repository']['url'],
                            'password': 'offline-password', 'operation.json': json.dumps(self.contract),
                            'credentials.json': json.dumps({'id': 'offline-id', 'key': 'offline-key'})}.items():
            p = self.root / name; p.write_text(value); p.chmod(0o600)
        self.calls = []
        self.target = None

    def tearDown(self):
        self.tmp.cleanup()

    def make_tree(self, target):
        target.mkdir(mode=0o700, exist_ok=True)
        (target / 'predata').mkdir(mode=0o700)
        p = target / 'predata/canary.txt'
        p.write_text(CONTRACT['expected_tree']['files'][0]['content_utf8']); p.chmod(0o600)

    def run_case(self, rc=0, damage=None, timeout=False, metadata=None, version=None,
                 config=None, locks=b''):
        responses = [(0, (version or CONTRACT['restic_version']).encode()),
                     (0, json.dumps(config or {'id': CONTRACT['repository']['id'], 'version': 2}).encode()),
                     (0, json.dumps(metadata if metadata is not None else CONTRACT['snapshot']['metadata']).encode())]
        def runner(argv, env, limit):
            self.calls.append(argv)
            self.assertLessEqual(limit, 600)
            if argv[0] == '/usr/bin/findmnt': return 0, b'/dev/sda2\n'
            if 'restore' in argv:
                self.target = Path(argv[-1])
                self.make_tree(self.target)
                if damage: damage(self.target)
                if timeout: raise helper.Blocked('command_timeout')
                return rc, b'ignored'
            if 'locks' in argv: return 0, locks
            return responses.pop(0)
        return helper.restore(self.root, self.contract, runner)

    def test_success_exact_command_no_replay(self):
        self.assertEqual(self.run_case()['result'], 'isolated_restore_review_required')
        command = next(c for c in self.calls if 'restore' in c)
        self.assertIn(CONTRACT['snapshot']['restore_selector'], command)
        self.assertNotIn('--no-lock', command)
        self.assertEqual((self.target/'predata/canary.txt').read_bytes(),
                         CONTRACT['expected_tree']['files'][0]['content_utf8'].encode())
        count=len(self.calls)
        with self.assertRaises(FileExistsError): self.run_case()
        self.assertEqual(len(self.calls),count)
        for p in self.root.glob('*.json'):
            if p.name not in ('credentials.json', 'operation.json'):
                for secret in ('offline-password','offline-id','offline-key'):
                    self.assertNotIn(secret,p.read_text())

    def test_failed_restore_retains_partial_and_status(self):
        result=self.run_case(rc=1)
        self.assertEqual(result['error_class'],'restore_failed_no_retry')
        self.assertTrue(self.target.exists())
        self.assertEqual(json.loads((self.root/'restore-result.json').read_text())['exit_status'],1)
        self.assertEqual(sum('restore' in c for c in self.calls),1)

    def test_interruption_retains_attempt_unknown_exit(self):
        result=self.run_case(timeout=True)
        self.assertTrue(result['restore_attempted'])
        self.assertIsNone(result['restore_exit_status'])
        self.assertTrue((self.root/'restore-attempt.json').exists())
        self.assertFalse((self.root/'restore-result.json').exists())
        self.assertTrue(self.target.exists())

    def test_wrong_version(self):
        self.assertFalse(self.run_case(version='wrong')['restore_attempted'])

    def test_wrong_repository(self):
        self.assertFalse(self.run_case(config={'id':'wrong'})['restore_attempted'])

    def test_wrong_snapshot(self):
        self.assertFalse(self.run_case(metadata={})['restore_attempted'])

    def test_source_changed(self):
        result=self.run_case(damage=lambda _: (self.source/'predata/canary.txt').write_text('changed'))
        self.assertEqual(result['result'],'blocked')

    def test_lock_residue(self):
        self.assertEqual(self.run_case(locks=b'lock')['result'],'blocked')

    def test_corrupt_file(self):
        self.assertEqual(self.run_case(damage=lambda p: (p/'predata/canary.txt').write_text('bad'))['result'],'blocked')

    def test_extra_file(self):
        self.assertEqual(self.run_case(damage=lambda p: (p/'extra').touch())['result'],'blocked')

    def test_missing_file(self):
        self.assertEqual(self.run_case(damage=lambda p: (p/'predata/canary.txt').unlink())['result'],'blocked')

    def test_wrong_mode(self):
        self.assertEqual(self.run_case(damage=lambda p: (p/'predata').chmod(0o755))['result'],'blocked')

    def test_symlink(self):
        def damage(p):
            f=p/'predata/canary.txt'; f.unlink(); f.symlink_to(self.source/'predata/canary.txt')
        self.assertEqual(self.run_case(damage=damage)['result'],'blocked')

    def test_special_file(self):
        def damage(p):
            f=p/'predata/canary.txt'; f.unlink(); os.mkfifo(f,0o600)
        self.assertEqual(self.run_case(damage=damage)['result'],'blocked')

    def test_wrong_owner(self):
        with patch.object(helper.common.os,'getuid',return_value=os.getuid()+1):
            with self.assertRaises(helper.Blocked): helper.common.tree(self.source,CONTRACT['expected_tree'])

    def test_destination_containment_and_empty(self):
        p=self.root/'restore.test'; p.mkdir(mode=0o700)
        (p/'existing').touch()
        with self.assertRaisesRegex(helper.Blocked,'not_empty'):
            helper.validate_destination(p,self.source,self.root)
        with self.assertRaises(helper.Blocked): helper.validate_destination(self.source,self.source,self.root)
        q=self.source/'restore.nested'; q.mkdir(mode=0o700)
        with self.assertRaises(helper.Blocked): helper.validate_destination(q,self.source,self.source)
        link=self.root/'restore.link'; link.symlink_to(p)
        with self.assertRaises(helper.Blocked): helper.validate_destination(link,self.source,self.root)
        with self.assertRaisesRegex(helper.Blocked,'mount_mismatch'):
            helper.destination(self.contract['destination'],self.source,lambda *_:(0,b'/dev/wrong'))


class Boundaries(unittest.TestCase):



    def test_journal_missing_truncated_boot_changed_and_event(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
            (root / 'journal-baseline.json').write_text(json.dumps({'boot_id': boot, 'cursor': 'cursor'}))
            def call_with(lines, first=b'{"__CURSOR":"cursor"}\n'):
                responses = iter([(0, first), (0, lines)])
                with patch.object(helper.common.time, 'monotonic', side_effect=[0, 75]):
                    return helper.common.journal('journal-review', root, CONTRACT,
                                          runner=lambda *_: next(responses), sleeper=lambda _: None)
            self.assertTrue(call_with(b'')['passed'])
            self.assertFalse(call_with(b'{"MESSAGE":"reset SuperSpeed USB device"}\n')['passed'])
            with self.assertRaises(helper.Blocked): call_with(b'', b'')
            with self.assertRaises(ValueError): call_with(b'{truncated')
            with patch.object(helper.common.time, 'monotonic', side_effect=[0, 2]):
                with self.assertRaisesRegex(helper.Blocked, 'observation_incomplete'):
                    helper.common.journal('journal-review', root, CONTRACT, sleeper=lambda _: None)
            (root / 'journal-baseline.json').write_text(json.dumps({'boot_id': 'old', 'cursor': 'cursor'}))
            with self.assertRaisesRegex(helper.Blocked, 'boot_changed'): call_with(b'')

    def test_capture_timeout_and_output_bound(self):
        with self.assertRaisesRegex(helper.Blocked, 'command_timeout'):
            helper.common.invoke([sys.executable, '-c', 'import time; time.sleep(2)'],
                          {'PATH': '/usr/bin:/bin'}, timeout=0.05)
        with patch.object(helper.common, 'LIMIT', 1024):
            with self.assertRaisesRegex(helper.Blocked, 'output_limit'):
                helper.common.invoke([sys.executable, '-c', 'import os; os.write(1,b"x"*2048)'],
                              {'PATH': '/usr/bin:/bin'})




if __name__ == '__main__':
    unittest.main(verbosity=2)
