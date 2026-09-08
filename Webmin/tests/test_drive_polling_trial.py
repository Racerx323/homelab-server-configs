import importlib.util
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('trial', Path(__file__).parents[1] / 'scripts/drive-polling-trial.py')
trial = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trial)


class GuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'config'
        self.path.write_bytes(b'collect_interval=5\n')
        self.path.chmod(0o600)
        os.utime(self.path, ns=(1_000_000_000, 2_000_000_000))
        i = self.path.stat()
        self.meta = dict(uid=i.st_uid, gid=i.st_gid, mode=stat.S_IMODE(i.st_mode),
                         atime_ns=i.st_atime_ns, mtime_ns=i.st_mtime_ns)
        self.before = self.path.read_bytes()
        self.after = self.before + b'collect_notemp=1\n'

    def test_nul_padded_legacy_history_and_invalid_future_records(self):
        directory = self.path.parent
        now = int(trial.time.time())
        (directory / 'load').write_text('\x00\x00' + str(now - 300) + ' 0.1\ninvalid 0.1\n' +
                                      str(now) + ' 0.2\n' + str(now + 999) + ' 0.3\n')
        with patch.object(trial, 'HISTORY', directory):
            self.assertEqual(trial.history('load'), [now - 300, now])

    def test_exact_restore_and_metadata(self):
        trial.guarded_replace(self.path, self.before, self.after, self.meta)
        trial.guarded_replace(self.path, self.after, self.before, self.meta, restore=True)
        self.assertEqual(self.path.read_bytes(), self.before)
        i = self.path.stat()
        self.assertEqual((i.st_uid, i.st_gid, stat.S_IMODE(i.st_mode), i.st_mtime_ns),
                         (self.meta['uid'], self.meta['gid'], 0o600, self.meta['mtime_ns']))
        self.assertEqual(list(self.path.parent.glob('.polling-trial-*')), [])

    def test_conflicting_edit_not_overwritten(self):
        self.path.write_bytes(b'another_edit=1\n')
        with self.assertRaisesRegex(RuntimeError, 'config_conflict'):
            trial.guarded_replace(self.path, self.after, self.before, self.meta, restore=True)
        self.assertEqual(self.path.read_bytes(), b'another_edit=1\n')

    def test_symlink_rejected(self):
        link = self.path.parent / 'link'
        link.symlink_to(self.path)
        with self.assertRaisesRegex(RuntimeError, 'config_not_regular'):
            trial.guarded_replace(link, self.before, self.after, self.meta)

    def test_old_failure_cannot_be_cleared_by_quiet_sample(self):
        result = trial.assess([{'reasons': ['usb_reset']}, {'reasons': []}],
                              {'complete': True, 'read_commands': []}, 7200, 24)
        self.assertEqual(result['result'], 'review_required')
        self.assertIn('usb_reset', result['reasons'])
        self.assertFalse(result['storage_accepted'])

    def test_missing_trace_or_cycles_not_quiet(self):
        result = trial.assess([{'reasons': []}], None, 7200, 2)
        self.assertIn('trace_incomplete', result['reasons'])
        self.assertIn('insufficient_collection_cycles', result['reasons'])

    def test_quiet_requires_completed_trace_and_no_smart_reads(self):
        trace = {'complete': True, 'read_commands': []}
        self.assertEqual(trial.assess([{'reasons': []}], trace, 7200, 24)['result'], 'quiet')
        trace['read_commands'] = [{'argv': ['smartctl', '-a', '/dev/sda']}]
        self.assertEqual(trial.assess([{'reasons': []}], trace, 7200, 24)['result'], 'review_required')


if __name__ == '__main__':
    unittest.main()
