#!/usr/bin/env python3
"""Receipt-reader regressions; synthetic inputs do not qualify a live backup."""
import copy
from datetime import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import sys
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1]/'ansible/scripts/inspect-recurring-cycle.py'
SPEC = importlib.util.spec_from_file_location('cycle_readback', SOURCE)
reader = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(reader)


class Readback(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root/'payload').mkdir(mode=0o700)
        start = datetime(2026, 11, 5, 3, 20, tzinfo=reader.CENTRAL).timestamp()
        self.state = dict(phase='complete', exit_status=0, started_at=start,
                          resumed_at=start+200, finished_at=start+250, last_success=start+251)
        spec = dict(operation_id='nautobot-recurring', captures=dict.fromkeys(reader.SECTIONS, {}))
        identity = hashlib.sha256(json.dumps(spec, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        capture = dict(specification_sha256=identity, capture_passed=True,
                       content_sha256=dict.fromkeys(reader.SECTIONS, 'a'*64),
                       credential_cleanup={'password': True, 'credentials.json': True},
                       started=start+10, finished=start+20)
        sid = 'b'*64
        self.receipts = {
            'application-backup.json': spec,
            'application-capture-result.json': capture,
            'application-backup-result.json': dict(capture, requested_at=start+201, finished=start+240,
                snapshot_id=sid, upload_passed=True, integrity_passed=True,
                backup_exit_status=0, integrity_exit_status=0, new_snapshot_ids=[sid]),
            'capture-task-results.json': dict(pause_rc=[0]*4, resume_rc=[0]*3,
                capture_rc=0, health_rc=0, credential_cleanup_failed=False),
            'capture-resume-verification.json': {'verification_rc': 0},
            'payload-disposal.json': dict(phase='complete', snapshot_id=sid, files=sorted(reader.SECTIONS)),
            'application-snapshots-before.json': ['c'*64],
            'application-snapshots-after.json': ['c'*64, sid],
        }
        self.write()

    def write(self):
        for name, value in self.receipts.items():
            p = self.root/name
            p.write_text(json.dumps(value)); p.chmod(0o600)

    def inspect(self):
        return reader.inspect_receipts(self.root, self.state, '2026-11-05')

    def test_disposed_cycle_checks_leave_every_file_unchanged(self):
        before = {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.root.iterdir() if p.is_file()}
        result = self.inspect()
        self.assertTrue(result['capture_resume_upload_order_verified'])
        self.assertEqual(result['snapshot_id'], 'b'*64)
        self.assertEqual(before, {p.name: (p.read_bytes(), p.stat().st_mtime_ns)
                                  for p in self.root.iterdir() if p.is_file()})

    def test_refuses_failed_tasks_hash_drift_snapshot_and_order_errors(self):
        cases = [
            ('capture-task-results.json', 'resume_rc', [1, 0, 0]),
            ('capture-resume-verification.json', 'verification_rc', 1),
            ('application-backup-result.json', 'content_sha256', dict.fromkeys(reader.SECTIONS, 'd'*64)),
            ('application-backup-result.json', 'integrity_passed', False),
            ('application-backup-result.json', 'requested_at', self.state['started_at']),
            ('application-backup-result.json', 'snapshot_id', 'e'*64),
        ]
        original = copy.deepcopy(self.receipts)
        for name, key, value in cases:
            with self.subTest(name=name, key=key):
                self.receipts = copy.deepcopy(original)
                self.receipts[name][key] = value; self.write()
                with self.assertRaises(ValueError): self.inspect()

    def test_credential_residue_is_detected_without_reading_it(self):
        secret = self.root/'password'; secret.write_text('synthetic-unread-value'); secret.chmod(0)
        actual = reader.read
        def checked(path):
            self.assertNotEqual(path, secret)
            return actual(path)
        with patch.object(reader, 'read', side_effect=checked), self.assertRaisesRegex(ValueError, 'credential_residue'):
            self.inspect()

    def logical_receipts(self):
        spec = self.receipts['application-backup.json']
        for value in spec['captures'].values(): value['argv'] = ['capture', '--logical-reference']
        identity = hashlib.sha256(json.dumps(spec, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        for name in ('application-capture-result.json','application-backup-result.json'):
            self.receipts[name]['specification_sha256'] = identity
        reference = {'format':'postgresql17-logical-v1','tables':{'table':{'rows':1,'sha256':'f'*64}}}
        self.receipts['logical-reference.json'] = reference
        self.receipts['logical-before.json'] = {'identity':copy.deepcopy(reference)}
        self.receipts['logical-capture.json'] = {'format':'recurring-logical-v1','specification_sha256':identity,
            'dump_sha256':'a'*64,'reference_sha256':hashlib.sha256(json.dumps(reference).encode()).hexdigest(),
            'comparison':{'equal':True,'changed_sections':[],'writer_control_required':True},
            'before_seconds':5,'after_seconds':5}
        self.write()

    def test_logical_reference_remains_verifiable_after_disposal(self):
        self.logical_receipts()
        result = reader.inspect_receipts(self.root,self.state,'2026-11-05',require_logical=True)
        self.assertTrue(result['logical_reference_verified'])
        self.assertIn('logical-reference.json',result['receipt_sha256'])

    def test_required_logical_capture_cannot_silently_fall_back(self):
        with self.assertRaisesRegex(ValueError,'logical_capture_not_enabled'):
            reader.inspect_receipts(self.root,self.state,'2026-11-05',require_logical=True)

    def test_reference_dump_and_deadline_drift_refused(self):
        self.logical_receipts();original=copy.deepcopy(self.receipts)
        for key,value in [('dump_sha256','b'*64),('reference_sha256','b'*64),('before_seconds',36)]:
            with self.subTest(key=key):
                self.receipts=copy.deepcopy(original);self.receipts['logical-capture.json'][key]=value;self.write()
                with self.assertRaises(ValueError):self.inspect()

    def test_refuses_wrong_day_payload_residue_and_missing_receipt(self):
        with self.assertRaisesRegex(ValueError, 'cycle_window'):
            reader.inspect_receipts(self.root, self.state, '2026-11-06')
        (self.root/'payload/unexpected').touch()
        with self.assertRaisesRegex(ValueError, 'payload_residue'): self.inspect()
        (self.root/'payload/unexpected').unlink()
        (self.root/'capture-task-results.json').unlink()
        with self.assertRaises(FileNotFoundError): self.inspect()

    def test_rejects_symlink_fifo_and_unprotected_receipts(self):
        p = self.root/'bad'
        p.symlink_to(self.root/'application-backup.json')
        with self.assertRaisesRegex(ValueError, 'symlink'): reader.read(p)
        p.unlink(); os.mkfifo(p, 0o600)
        with self.assertRaisesRegex(ValueError, 'unsafe_file'): reader.read(p)
        p.unlink(); p.write_text('{}'); p.chmod(0o644)
        with self.assertRaisesRegex(ValueError, 'unsafe_file'): reader.read(p)

    def test_runtime_cache_does_not_relax_source_or_membership_checks(self):
        runtime = self.root/'runtime'; scripts = runtime/'scripts'; scripts.mkdir(parents=True)
        source = scripts/'worker.py'; source.write_text('# approved\n'); source.chmod(0o600)
        expected = {'scripts/worker.py': hashlib.sha256(source.read_bytes()).hexdigest()}
        cache = scripts/'__pycache__'; cache.mkdir()
        derived = cache/('worker.'+sys.implementation.cache_tag+'.pyc')
        derived.write_bytes(b'opaque derived cache; never executed'); derived.chmod(0o600)
        before = derived.read_bytes(), derived.stat().st_mtime_ns
        actual, caches = reader.runtime_hashes(runtime, expected)
        self.assertEqual(actual, expected); self.assertEqual(len(caches), 1)
        self.assertEqual(before, (derived.read_bytes(), derived.stat().st_mtime_ns))
        source.write_text('# drift\n')
        with self.assertRaisesRegex(ValueError, 'runtime_drift'): reader.runtime_hashes(runtime, expected)
        source.write_text('# approved\n')
        derived.chmod(0o644)
        with self.assertRaisesRegex(ValueError, 'unsafe_file'): reader.runtime_hashes(runtime, expected)
        derived.chmod(0o600)
        for name in ('unknown.'+sys.implementation.cache_tag+'.pyc', 'worker.cpython-999.pyc', 'worker.py'):
            bad = cache/name; bad.write_bytes(b'extra'); bad.chmod(0o600)
            with self.assertRaisesRegex(ValueError, 'runtime_extra'): reader.runtime_hashes(runtime, expected)
            bad.unlink()
        derived.unlink(); derived.symlink_to(source)
        with self.assertRaisesRegex(ValueError, 'runtime_symlink'): reader.runtime_hashes(runtime, expected)
        derived.unlink(); source.unlink()
        with self.assertRaisesRegex(ValueError, 'runtime_drift'): reader.runtime_hashes(runtime, expected)


if __name__ == '__main__':
    unittest.main()
