#!/usr/bin/env python3
"""Producer failure boundaries; real Restic integration is disposable-only."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('producer', Path(__file__).resolve().parents[1]/'scripts/application-backup.py')
producer = importlib.util.module_from_spec(spec); spec.loader.exec_module(producer)


def contract():
    return {'schema_version': 1, 'operation_id': 'offline-backup', 'authorized': True,
            'repository_id': 'a'*64, 'repository_url': '/disposable', 'restic': '/usr/bin/restic', 'restic_version': 'fixture',
            'execution_uid': os.getuid(), 'required_filesystem': 'fixturefs', 'hostname': 'disposable', 'source_consistency_reviewed': True, 'timeout_seconds': 60,
            'dump_validator': ['/usr/bin/pg_restore', '--list'],
            'captures': {k: {'argv': ['/usr/bin/capture', k], 'maximum_bytes': 1024} for k in producer.SECTIONS}}


class BackupTests(unittest.TestCase):
    def exercise(self, root, backup_rc=0, integrity_rc=0):
        for name, value in [('repository', '/disposable'), ('password', 'disposable-only'), ('credentials.json', '{}')]:
            p = root/name; p.write_text(value); p.chmod(0o600)
        calls = []; snapshots = [0]
        def call(argv, env, deadline, **kwargs):
            calls.append(argv)
            if argv[0] == '/usr/bin/findmnt': return 0, b'fixturefs'
            if 'destination' in kwargs:
                self.assertEqual(json.loads((root/'application-capture-started.json').read_text())['operation_id'], 'offline-backup')
                p = kwargs['destination']; p.write_bytes(b'PGDMPfixture'); p.chmod(0o600)
                return 0, b''
            if argv[0] == '/usr/bin/pg_restore': return 0, b'toc'
            if argv[-1] == 'version': return 0, b'fixture'
            if argv[-2:] == ['cat', 'config']: return 0, json.dumps({'id':'a'*64,'version':2}).encode()
            if argv[-2:] == ['snapshots', '--json']:
                snapshots[0] += 1
                return 0, json.dumps([] if snapshots[0] == 1 else [{'id':'b'*64,'hostname':'disposable','paths':[str(root/'payload')],'tags':['offline-backup']}]).encode()
            if 'backup' in argv: return backup_rc, b'raw private output must not escape'
            if 'check' in argv: return integrity_rc, b''
            if argv[-2:] == ['list', 'locks']: return 0, b''
            raise AssertionError(argv)
        result = producer.run(root, contract(), call)
        return result, calls

    def test_success_and_private_credential_cleanup(self):
        with tempfile.TemporaryDirectory() as d:
            result, calls = self.exercise(Path(d))
            self.assertTrue(result['integrity_passed'])
            self.assertFalse(result['accepted'])
            self.assertEqual(len(result['content_sha256']), 6)
            self.assertTrue(all(result['credential_cleanup'].values()))
            self.assertFalse((Path(d)/'password').exists())
            self.assertFalse(any(x in a for a in calls for x in ('init','forget','prune','unlock','restore')))

    def test_incomplete_snapshot_never_passes(self):
        with tempfile.TemporaryDirectory() as d:
            result, calls = self.exercise(Path(d), backup_rc=3)
            self.assertFalse(result['upload_passed'])
            self.assertEqual(result['snapshot_id'], 'b'*64)
            self.assertTrue((Path(d)/'payload').exists())
            self.assertFalse(any('check' in c for c in calls))

    def test_failure_after_upload_preserves_snapshot(self):
        with tempfile.TemporaryDirectory() as d:
            result, _ = self.exercise(Path(d), integrity_rc=1)
            self.assertTrue(result['upload_passed'])
            self.assertFalse(result['integrity_passed'])
            self.assertEqual(result['snapshot_id'], 'b'*64)
            self.assertTrue(all(result['credential_cleanup'].values()))

    def test_cleanup_failure_does_not_skip_second_secret(self):
        original = Path.unlink
        def unlink(path, *args, **kwargs):
            if path.name == 'password': raise PermissionError('private')
            return original(path, *args, **kwargs)
        with tempfile.TemporaryDirectory() as d:
            with patch.object(Path, 'unlink', unlink): result, _ = self.exercise(Path(d))
            self.assertFalse(result['credential_cleanup']['password'])
            self.assertTrue(result['credential_cleanup']['credentials.json'])
            self.assertNotIn('private', (Path(d)/'application-backup-result.json').read_text())

    def test_inactive_and_unreviewed_source_rejected(self):
        for change in ({'authorized':False},{'source_consistency_reviewed':False},{'captures':{}},{'timeout_seconds':1800}):
            with self.subTest(change=change), self.assertRaises(ValueError): producer.validate(dict(contract(), **change))

    def test_signal_cancellation_cleans_both_credentials(self):
        import signal
        import subprocess
        import time
        import sys
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            binary = root/'test-restic'
            binary.write_text("#!/usr/bin/python3\nimport sys,json\nprint('fixture' if sys.argv[-1]=='version' else json.dumps({'id':'"+'a'*64+"','version':2}))\n")
            binary.chmod(0o700)
            specification = contract(); specification['restic'] = str(binary)
            specification['required_filesystem'] = subprocess.check_output(['/usr/bin/findmnt','-n','-o','SOURCE','--target',str(root)]).decode().strip()
            specification['captures']['postgresql_custom_dump']['argv'] = ['/bin/sleep', '30']
            for name, value in [('repository','/disposable'),('password','disposable-only'),('credentials.json','{}'),('application-backup.json',json.dumps(specification))]:
                path=root/name; path.write_text(value); path.chmod(0o600)
            process=subprocess.Popen([sys.executable, str(Path(producer.__file__)), '--root', str(root)], start_new_session=True)
            try:
                deadline=time.monotonic()+10
                while not (root/'payload/postgresql_custom_dump').exists():
                    self.assertLess(time.monotonic(),deadline)
                    self.assertIsNone(process.poll())
                    time.sleep(0.05)
                os.killpg(process.pid,signal.SIGTERM)
                self.assertNotEqual(process.wait(timeout=10),0)
                result=json.loads((root/'application-backup-result.json').read_text())
                self.assertTrue(all(result['credential_cleanup'].values()))
                self.assertFalse(result['upload_attempted'])
                self.assertFalse(result['integrity_passed'])
            finally:
                if process.poll() is None:
                    os.killpg(process.pid,signal.SIGKILL); process.wait(timeout=5)

    def test_output_and_deadline_bounds(self):
        import time
        with self.assertRaises(ValueError):
            producer.invoke(['/bin/true'], {}, time.monotonic()-1)
        with self.assertRaises(ValueError):
            producer.invoke(['/usr/bin/python3','-c','import sys;sys.stdout.write("x"*2048)'],
                            {'PATH':'/usr/bin:/bin'}, time.monotonic()+10, maximum=1024)


if __name__ == '__main__': unittest.main()
