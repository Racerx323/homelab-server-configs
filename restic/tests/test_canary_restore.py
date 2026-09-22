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


helper = load('restore', 'restic/scripts/restore-canary.py')
launcher = load('canary_launcher', 'Nautobot/ansible/scripts/run-canary-restore.py')
SCHEMA = json.loads((ROOT / 'Nautobot/schemas/canary-restore.schema.json').read_text())
CONTRACT = {k: copy.deepcopy(v['const']) for k, v in SCHEMA['properties'].items()}
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
    def test_wrong_hash_or_stage_never_resolves_credentials(self):
        with patch.object(launcher.common, 'read_secret', side_effect=AssertionError('external access')):
            with self.assertRaises(launcher.common.PreflightBlocked):
                launcher.transport.execute('0'*64)

    def test_hash_gate_precedes_secret_resolution(self):
        with patch.object(launcher.transport, 'require_ready'), \
             patch.object(launcher.common, 'validate_operation', return_value=CONTRACT), \
             patch.object(launcher.common, 'read_secret', side_effect=AssertionError('external access')):
            with self.assertRaisesRegex(launcher.common.PreflightBlocked, 'bundle_hash_mismatch'):
                launcher.transport.execute('0'*64)

    def test_predecessor_and_snapshot_binding(self):
        def git(argv, **kwargs):
            args=argv[3:]
            if args[0]=='status': return b''
            for name in ('initialization','backup_integrity'):
                proof=CONTRACT['prerequisites'][name]
                if proof['terminal_tag'] in ' '.join(args):
                    if args[0]=='cat-file': return b'tag'
                    if args[0]=='rev-parse': return proof['archive_commit'].encode()
                    if args[0]=='show': return (ROOT/proof['record']).read_bytes()
            raise AssertionError(args)
        with patch.object(launcher.subprocess,'check_output',side_effect=git):
            launcher.require_ready(CONTRACT)
            bad=copy.deepcopy(CONTRACT); bad['snapshot']['id']='b'*64
            with self.assertRaisesRegex(launcher.common.PreflightBlocked,'snapshot_identity_mismatch'):
                launcher.require_ready(bad)
            bad=copy.deepcopy(CONTRACT); bad['prerequisites']['backup_integrity']['record_sha256']='b'*64
            with self.assertRaisesRegex(launcher.common.PreflightBlocked,'predecessor_identity_mismatch'):
                launcher.require_ready(bad)

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

    def test_canary_playbook_syntax(self):
        result = subprocess.run(['/bin/bash', str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),
                                 'ansible-playbook', '--syntax-check', '--inventory',
                                 str(ROOT/'inventory/prod/hosts.yaml'),
                                 str(ROOT/'Nautobot/ansible/playbooks/restore-canary.yaml')],
                                capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout.decode()+result.stderr.decode())

    def test_real_production_cleanup_tasks(self):
        play = yaml.safe_load((ROOT / 'Nautobot/ansible/playbooks/restore-canary.yaml').read_text())[0]
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
                            'vars': {'restore_directory': {'stdout': directory}, 'restore_evidence_root': directory},
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
