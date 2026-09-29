import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from urllib.parse import quote

SPEC = importlib.util.spec_from_file_location('passive', Path(__file__).parents[1] / 'scripts/observe-disk-discovery.py')
passive = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(passive)


def serialize(value):
    if value is None:
        return 'UNDEF'
    if isinstance(value, dict):
        parts = [x for pair in value.items() for x in pair]
        return 'HASH,' + ','.join(quote(serialize(x), safe='') for x in parts)
    if isinstance(value, list):
        return 'ARRAY' + (',' + ','.join(quote(serialize(x), safe='') for x in value) if value else '')
    return 'VAL,' + quote(str(value), safe='')


class PassiveTests(unittest.TestCase):
    def setUp(self):
        self.drive = {'device': '/dev/sda', 'temp': '43', 'failed': '', 'errors': None}
        self.spec = dict(boot='boot', kernel='kernel', root='root', topology='path', files={'source': 'hash'},
                         packages={'webmin': '2.670'}, services='active', interval_seconds=300,
                         sample_seconds=60)
        self.sample = dict(self.spec, wall=1000000000, mono=100, cache_mtime=999999950,
                           history={'load': {999999950: []}, 'drivetemp': {999999950: 43}},
                           busy=False, counters={'ioerr': 10, 'iotmo': 0, 'ext4': 0}, kernel_events=[], health=[self.drive])

    def test_recursive_health_parser_and_exact_drive_coverage(self):
        raw = serialize({'other': 'literal,comma%value', 'drivetemps': [self.drive]}).encode()
        self.assertEqual(passive.drive_health(raw, ['/dev/sda']), [{'device': '/dev/sda', 'temp': 43.0}])
        for expected in [[], ['/dev/sda', '/dev/sdb']]:
            with self.assertRaisesRegex(ValueError, 'coverage'):
                passive.drive_health(raw, expected)
        with self.assertRaises(ValueError):
            passive.drive_health(serialize({'drivetemps': []}).encode(), ['/dev/sda'])

    def test_failed_missing_duplicate_and_invalid_health(self):
        for changes in [{'failed': '1'}, {'errors': ['error']}, {'temp': 'nan'}, {'temp': '80'}]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                passive.drive_health(serialize({'drivetemps': [dict(self.drive, **changes)]}).encode(), ['/dev/sda'])
        with self.assertRaises(ValueError):
            passive.drive_health(serialize({'drivetemps': [self.drive, self.drive]}).encode(), ['/dev/sda'])
        incomplete = dict(self.drive)
        del incomplete['failed']
        with self.assertRaises(ValueError):
            passive.drive_health(serialize({'drivetemps': [incomplete]}).encode(), ['/dev/sda'])

    def test_histories_nul_duplicate_future_and_temperature(self):
        self.assertEqual(passive.history(b'\0\0' + b'1000000000 43\n1000000000 43\n', 1000000001, True), {1000000000: 43.0})
        for data in [b'garbage 43\n', b'1000000009 43\n', b'1000000000 nan\n',
                     b'1000000000 43\n1000000000 42\n']:
            with self.assertRaises(ValueError):
                passive.history(data, 1000000001, True)

    def test_drift_and_storage_fail_closed(self):
        passive.validate(self.spec, self.sample, self.sample)
        for key in ['files', 'services', 'boot', 'packages']:
            changed = dict(self.sample, **{key: 'changed'})
            with self.assertRaisesRegex(RuntimeError, 'drift'):
                passive.validate(self.spec, self.sample, changed)
        for counter in ['ioerr', 'iotmo', 'ext4']:
            changed = copy.deepcopy(self.sample)
            changed['counters'][counter] += 1
            with self.assertRaises(RuntimeError) as exc:
                passive.validate(self.spec, self.sample, changed)
            if counter == 'ioerr':
                self.assertIn('requires_attribution', str(exc.exception))

    def test_stale_health_history_clock_and_kernel(self):
        for change in [{'cache_mtime': 999999000}, {'history': {'load': {999999000: []}}},
                       {'wall': 1000000100}, {'kernel_events': [{'message': 'fault'}]}]:
            with self.assertRaises(RuntimeError):
                passive.validate(self.spec, self.sample, dict(self.sample, **change))

    def test_checkpoint_requires_each_history_coverage(self):
        sample = dict(self.sample, mono=7300)
        seen = {'load': set(range(23)), 'drivetemp': set(range(23))}
        self.assertEqual(passive.checkpoint(self.spec, self.sample, sample, seen)['minimum_cycles'], 23)
        seen['drivetemp'].remove(0)
        with self.assertRaisesRegex(RuntimeError, 'insufficient'):
            passive.checkpoint(self.spec, self.sample, sample, seen)

    def test_finalizer_marks_interruption_without_changing_monitoring(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            passive.write(root / 'result.json', {'state': 'observing'})
            passive.finalize(root)
            result = json.loads((root / 'result.json').read_text())
            self.assertEqual(result['state'], 'review_required')
            self.assertFalse(result['rollback_performed'])
            self.assertFalse(result['monitoring_changed'])
            passive.write(root / 'result.json', {'state': 'complete'})
            passive.finalize(root)
            self.assertEqual(json.loads((root / 'result.json').read_text()), {'state': 'complete'})

    def test_complete_lifecycle_two_hour_checkpoint_and_final_settle(self):
        from unittest.mock import patch
        calls = 0
        base = 1000000000
        spec = dict(self.spec, history={'load': 'unused', 'drivetemp': 'unused'})

        def sample(*args):
            nonlocal calls
            elapsed = calls * 60
            calls += 1
            records = {base - 10: 43}
            records.update({base + n * 300: 43 for n in range(1, elapsed // 300 + 1)})
            return dict(self.sample, wall=base + elapsed, mono=100 + elapsed, busy=elapsed == 86520,
                        cache_mtime=max(records),
                        history={'load': dict(records), 'drivetemp': dict(records)})

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            root.chmod(0o700)
            spec_path = root / 'spec.json'
            passive.write(spec_path, spec)
            # This test runs without root, timers, service startup or host reads.
            original_stat = Path.stat
            def safe_stat(path, *args, **kwargs):
                value = original_stat(path, *args, **kwargs)
                if path == root:
                    from types import SimpleNamespace
                    return SimpleNamespace(st_uid=0, st_mode=value.st_mode)
                return value
            with patch.object(passive, 'collect', side_effect=sample), patch.object(passive, 'notify'), \
                    patch.object(passive.time, 'sleep'), patch.object(passive.signal, 'signal'), \
                    patch.object(Path, 'stat', safe_stat):
                passive.observe(spec_path, root)
            result = json.loads((root / 'result.json').read_text())
            self.assertEqual(result['state'], 'complete')
            self.assertGreaterEqual(result['settled_seconds'], 75)
            self.assertGreaterEqual(result['elapsed_seconds'], 86580)
            self.assertGreaterEqual(result['counts']['drivetemp'], 287)
            self.assertTrue((root / 'checkpoint-2h.json').exists())
            self.assertTrue((root / 'checkpoint-24h.json').exists())
            self.assertFalse((root / 'ALERT.json').exists())

    def test_bundle_reproducibility_and_patch_identity_gate(self):
        spec = importlib.util.spec_from_file_location('prepare_observation', Path(__file__).parents[1] / 'scripts/prepare-disk-discovery-observation.py')
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        manifest = json.loads((builder.WEBMIN / 'patches/disk-only-discovery.json').read_text())
        operation = {'sample_seconds': 60, 'interval_seconds': 300, 'expected_devices': ['/dev/sda'],
                     'files': {'/usr/share/webmin/' + name: value['after'] for name, value in manifest['files'].items()}}
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            op = root / 'operation.json'
            op.write_text(json.dumps(operation))
            a, ah = builder.prepare(op, root / 'a')
            b, bh = builder.prepare(op, root / 'b')
            self.assertEqual(ah, bh)
            self.assertEqual(a.read_bytes(), b.read_bytes())
            with self.assertRaises(FileExistsError):
                builder.prepare(op, root / 'a')
            operation['files'][next(iter(operation['files']))] = 'drift'
            op.write_text(json.dumps(operation))
            with self.assertRaisesRegex(ValueError, 'pin'):
                builder.prepare(op, root / 'bad')
            self.assertFalse((root / 'bad').exists())
