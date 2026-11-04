#!/usr/bin/env python3
"""Filesystem drift/refusal tests for retaining a never-started qualification."""
import copy
import hashlib
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'ansible/scripts'))
from capture_retained import preserve


class Retained(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.root = self.base/'qualification'; self.root.mkdir(mode=0o700)
        (self.base/'staging').mkdir(mode=0o700)
        (self.root/'units').mkdir(mode=0o700)
        self.units = self.base/'runtime'; self.units.mkdir()
        self.names = ['nautobot-protection-qualification'+s for s in
                      ('.service', '-guard.timer', '-guard.service', '-recovery.service')]
        for name in self.names:
            p = self.root/'units'/name; p.write_text('[Unit]\n'); p.chmod(0o600)
            (self.units/name).symlink_to(p)
        self.spec = {'bundle_sha256': 'a'*64, 'files': {}, 'directories': {},
                     'links': {n: str(self.root/'units'/n) for n in self.names},
                     'service_invocations': {'nautobot-'+r+'.service': r for r in
                                             ('postgresql', 'redis', 'web', 'worker', 'scheduler')}}
        for p in [self.root, *self.root.rglob('*')]:
            info = p.stat(); row = {'uid': info.st_uid, 'gid': info.st_gid, 'mode': stat.S_IMODE(info.st_mode)}
            if p.is_file(): row['sha256'] = hashlib.sha256(p.read_bytes()).hexdigest()
            self.spec['directories' if p.is_dir() else 'files'][str(p.relative_to(self.root))] = row

    def tearDown(self): self.tmp.cleanup()

    def show(self, name):
        if name in self.spec['service_invocations']:
            return {'ActiveState': 'active', 'SubState': 'running', 'InvocationID': self.spec['service_invocations'][name]}
        return {'ActiveState': 'inactive', 'InvocationID': '', 'ExecMainStartTimestamp': ''}

    def apply(self, spec=None, show=None):
        return preserve(self.root, spec or self.spec, self.units, show or self.show)

    def test_preserves_bytes_and_refuses_replay(self):
        result = self.apply(); saved = Path(result['preserved_directory'])
        self.assertFalse(self.root.exists()); self.assertEqual(list(self.units.iterdir()), [])
        for name, row in self.spec['files'].items():
            self.assertEqual(hashlib.sha256((saved/name).read_bytes()).hexdigest(), row['sha256'])
        with self.assertRaisesRegex(ValueError, 'retained_destination_exists'): self.apply()

    def test_file_drift_refused_before_mutation(self):
        (self.root/'units'/self.names[0]).write_text('drift')
        with self.assertRaisesRegex(ValueError, 'retained_file_drift'): self.apply()
        self.assertTrue(self.root.exists()); self.assertEqual(len(list(self.units.iterdir())), 4)

    def test_extra_payload_refused(self):
        (self.root/'payload').write_text('retain me')
        with self.assertRaisesRegex(ValueError, 'retained_members'): self.apply()
        self.assertTrue((self.root/'payload').exists())

    def test_directory_permissions_refused(self):
        self.root.chmod(0o755)
        with self.assertRaisesRegex(ValueError, 'directory_drift'): self.apply()

    def test_active_unit_and_service_restart_refused(self):
        for name in (self.names[0], 'nautobot-web.service'):
            def changed(unit):
                row = self.show(unit)
                if unit == name: row['InvocationID'] = 'changed'
                return row
            with self.assertRaises(ValueError): self.apply(show=changed)
            self.assertTrue(self.root.exists())

    def test_wrong_link_refused(self):
        link = self.units/self.names[0]; link.unlink(); link.symlink_to('/tmp/unrelated')
        with self.assertRaisesRegex(ValueError, 'runtime_link_drift'): self.apply()
        self.assertTrue(self.root.exists())

    def test_partial_unlink_failure_preserves_evidence(self):
        with patch.object(Path, 'unlink', side_effect=OSError('injected unlink failure')):
            with self.assertRaises(OSError): self.apply()
        self.assertTrue((self.base/('qualification-retained-'+'a'*12)).is_dir())
        self.assertEqual(len(list(self.units.iterdir())), 4)

    def terminal(self, phase='manual_intervention', additional_payload=False):
        import json
        payload = self.base/'staging/nautobot-recurring.test'; payload.mkdir(mode=0o700)
        (payload/'dump').write_bytes(b'retained payload')
        (self.root/'state').mkdir(mode=0o700)
        state = {'phase': phase, 'credential_cleanup': True, 'health_status': 0 if phase == 'recovered_failure' else 1,
                 'resume_statuses': [0, 0, 0], 'root': str(payload)}
        (self.root/'state/state.json').write_text(json.dumps(state))
        def tree(root):
            result = {'files': {}, 'directories': {}}
            for p in [root, *root.rglob('*')]:
                s = p.stat(); row = {'uid': s.st_uid, 'gid': s.st_gid, 'mode': stat.S_IMODE(s.st_mode)}
                if p.is_file(): row['sha256'] = hashlib.sha256(p.read_bytes()).hexdigest()
                result['directories' if p.is_dir() else 'files'][str(p.relative_to(root))] = row
            return result
        self.spec.update(tree(self.root))
        states = {n: {'ActiveState': 'failed' if n.endswith('.service') else 'inactive',
                     'MainPID': '0', 'ControlPID': '0', 'ControlGroup': '', 'InvocationID': 'old'} for n in self.names}
        self.spec['terminal'] = {'state': state, 'payload': {'path': str(payload), **tree(payload)}, 'units': states}
        if additional_payload:
            other = payload.with_name('nautobot-recurring.older'); other.mkdir(mode=0o700)
            (other/'dump').write_bytes(b'older retained payload')
            self.spec['terminal']['retained_payloads'] = [{'path': str(other), **tree(other)}]
        def show(name): return copy.deepcopy(states[name]) if name in states else self.show(name)
        return payload, show

    def test_terminal_latch_and_payload_preserved(self):
        payload, show = self.terminal()
        saved = Path(self.apply(show=show)['preserved_directory'])
        self.assertTrue((saved/'state/state.json').exists())
        self.assertEqual((payload/'dump').read_bytes(), b'retained payload')

    def test_terminal_payload_drift_refused(self):
        payload, show = self.terminal(); (payload/'dump').write_bytes(b'drift')
        with self.assertRaisesRegex(ValueError, 'retained_file_drift'): self.apply(show=show)
        self.assertTrue(self.root.exists())

    def test_recovered_failure_preserves_all_payloads(self):
        payload, show = self.terminal('recovered_failure', additional_payload=True)
        self.apply(show=show)
        self.assertEqual((payload/'dump').read_bytes(), b'retained payload')
        self.assertEqual((payload.with_name('nautobot-recurring.older')/'dump').read_bytes(), b'older retained payload')

    def test_older_payload_drift_refused(self):
        payload, show = self.terminal('recovered_failure', additional_payload=True)
        (payload.with_name('nautobot-recurring.older')/'dump').write_bytes(b'drift')
        with self.assertRaisesRegex(ValueError, 'retained_file_drift'): self.apply(show=show)
        self.assertTrue(self.root.exists())

    def test_unbound_payload_refused(self):
        payload, show = self.terminal('recovered_failure')
        payload.with_name('nautobot-recurring.unbound').mkdir()
        with self.assertRaisesRegex(ValueError, 'staging_drift'): self.apply(show=show)
        self.assertTrue(self.root.exists())

    def test_terminal_running_unit_refused(self):
        _, show = self.terminal()
        for key, value in [('ActiveState', 'active'), ('MainPID', '42'), ('ControlGroup', '/live')]:
            self.spec['terminal']['units'][self.names[0]][key] = value
            with self.assertRaisesRegex(ValueError, 'unit_running'): self.apply(show=show)
            self.spec['terminal']['units'][self.names[0]][key] = {'ActiveState': 'failed', 'MainPID': '0', 'ControlGroup': ''}[key]
        self.assertTrue(self.root.exists())

    def recovery(self):
        import shutil
        for link in self.units.iterdir(): link.unlink()
        shutil.rmtree(self.root/'units')
        self.root.rename(self.base/'recovery-qualification'); self.root = self.base/'recovery-qualification'
        (self.root/'killed').mkdir(mode=0o700)
        p=self.root/'input';p.write_bytes(b'frozen');p.chmod(0o600)
        self.spec.update(kind='unstarted_recovery', files={}, directories={})
        self.spec.pop('links')
        for p in [self.root, *self.root.rglob('*')]:
            s=p.stat();row={'uid':s.st_uid,'gid':s.st_gid,'mode':stat.S_IMODE(s.st_mode)}
            if p.is_file():row['sha256']=hashlib.sha256(p.read_bytes()).hexdigest()
            self.spec['directories' if p.is_dir() else 'files'][str(p.relative_to(self.root))]=row
        return lambda name: self.show(name) if name in self.spec['service_invocations'] else {
            'LoadState':'not-found','ActiveState':'inactive','MainPID':'0','ControlPID':'0','ControlGroup':''}

    def test_unstarted_recovery_preserves_tree_and_staging(self):
        show=self.recovery();payload=self.base/'staging/old-payload';payload.write_bytes(b'keep')
        result=self.apply(show=show)
        self.assertEqual((Path(result['preserved_directory'])/'input').read_bytes(),b'frozen')
        self.assertEqual(payload.read_bytes(),b'keep');self.assertEqual(result['runtime_links_removed'],[])
        with self.assertRaisesRegex(ValueError,'retained_destination_exists'):self.apply(show=show)

    def test_unstarted_recovery_refuses_loaded_units_or_file_drift(self):
        show=self.recovery()
        def loaded(name):
            row=show(name)
            if 'LoadState' in row:row['LoadState']='loaded'
            return row
        with self.assertRaisesRegex(ValueError,'recovery_unit_present'):self.apply(show=loaded)
        (self.root/'input').write_bytes(b'drift')
        with self.assertRaisesRegex(ValueError,'retained_file_drift'):self.apply(show=show)
        self.assertTrue(self.root.exists())


if __name__ == '__main__': unittest.main()
