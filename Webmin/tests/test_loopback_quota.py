"""File restoration and native-command ordering only; no host/capacity substitute."""
import base64
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('quota', Path(__file__).parents[1]/'scripts/compare-loopback-quota.py')
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)


class QuotaTests(unittest.TestCase):
    def test_native_unit_binds_independent_recovery_and_deadlines(self):
        args = q.unit_command(Path('/run/webmin-quota-test'))
        self.assertIn('--property=RuntimeMaxSec=60s', args)
        self.assertIn('--property=TimeoutStopSec=20s', args)
        cleanup = next(x for x in args if x.startswith('--property=ExecStopPost='))
        self.assertIn('/usr/bin/timeout --kill-after=2s 18s', cleanup)
        self.assertTrue(cleanup.endswith('/run/webmin-quota-test/compare-loopback-quota.py restore'))
        self.assertEqual(args[-1], 'worker')

    def test_restore_exact_existing_or_absent_runtime_file(self):
        for existed in (False, True):
            with self.subTest(existed=existed), tempfile.TemporaryDirectory() as temp:
                root = Path(temp); override = root/'runtime'/'50-CPUQuota.conf'
                override.parent.mkdir(); override.write_text('CPUQuota=200%\n')
                boot = root/'boot'; boot.write_text('same-boot')
                prior = b'[Service]\nCPUQuota=100%\n'
                state = {'boot':'same-boot','inode':12,'main':'10','controls':{'cpu.max':'100000 100000'}}
                saved = dict(state, override_directory_existed=existed, override=None)
                if existed:
                    saved['override'] = dict(bytes=base64.b64encode(prior).decode(), mode=0o640, uid=0, gid=0)
                q.save(root, 'baseline.json', saved)
                calls = []
                def native(*args, **kwargs):
                    calls.append(args)
                    if 'set-property' in args: override.write_text('CPUQuota=100%\n')
                    return ''
                with patch.object(q, 'OVERRIDE', override), patch.object(q, 'BOOT', boot), \
                     patch.object(q, 'command', native), patch.object(q, 'state_now', return_value=state), \
                     patch.object(q.os, 'chown'):
                    q.restore(root)
                self.assertIn('set-property', calls[0]); self.assertIn('daemon-reload', calls[1])
                self.assertTrue(json.loads((root/'restoration.json').read_text())['restored'])
                self.assertEqual(override.exists(), existed)
                if existed:
                    self.assertEqual(override.read_bytes(), prior)
                    self.assertEqual(override.stat().st_mode & 0o777, 0o640)
                else:
                    self.assertFalse(override.parent.exists())

    def test_restore_failure_is_retained_not_accepted(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); boot = root/'boot'; boot.write_text('same-boot')
            q.save(root, 'baseline.json', {'boot':'same-boot'})
            with patch.object(q, 'BOOT', boot), patch.object(q, 'quota', side_effect=subprocess.TimeoutExpired('systemctl', 5)):
                with self.assertRaises(subprocess.TimeoutExpired): q.restore(root)
            receipt = json.loads((root/'restoration.json').read_text())
            self.assertFalse(receipt['restored']); self.assertIn('timed out', receipt['error'])

    def test_worker_admits_before_change_and_uses_two_cpu_measurement(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); state={'boot':'same','main':'10'}; q.save(root,'baseline.json',state)
            calls=[]
            class Diagnostic:
                @staticmethod
                def compare_loopback(expected_cpus):
                    calls.append(('measure', expected_cpus)); return 1
            class Loader:
                def exec_module(self, module): pass
            class Spec:
                loader=Loader()
            with patch.object(q, 'state_now', return_value=state), \
                 patch.object(q, 'quota', side_effect=lambda value:calls.append(('quota',value))), \
                 patch.object(q.importlib.util, 'spec_from_file_location', return_value=Spec()), \
                 patch.object(q.importlib.util, 'module_from_spec', return_value=Diagnostic):
                self.assertEqual(q.worker(root),1)
            self.assertEqual(calls,[('quota',200),('measure',2)])
            with patch.object(q, 'state_now', return_value={'boot':'changed','main':'10'}), patch.object(q,'quota') as change:
                with self.assertRaises(ValueError): q.worker(root)
                change.assert_not_called()


if __name__ == '__main__':
    unittest.main()
