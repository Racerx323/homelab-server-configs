#!/usr/bin/env python3
"""Failure boundaries; real database/restore coverage lives in the local qualifier."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'ansible/scripts'))
import recurring_logical as logical
from recurring_protection import atomic, Blocked


class LogicalCaptureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='recurring-logical.')
        self.root = Path(self.tmp.name)
        (self.root/'payload').mkdir(mode=0o700)
        p = self.root/'payload/postgresql_custom_dump'; p.write_bytes(b'unit-only'); p.chmod(0o600)
        self.spec = {'captures': {'postgresql_custom_dump': {'argv': ['--logical-reference']}}}
        atomic(self.root/'application-backup.json', self.spec)
        self.identity = dict(format='postgresql17-logical-v1', server_version_num='170006', schemas=['public'],
                             definitions={}, tables={'sample': {'rows': 1, 'sha256': 'a'*64}}, sequences={})
        self.probe = patch.object(logical, 'probe', return_value=(self.identity, 1.0))
        self.probe.start()
        self.addCleanup(self.probe.stop)
        self.addCleanup(self.tmp.cleanup)

    def finish(self):
        value = logical.finish(self.root, None, 'a'*64)
        atomic(self.root/'payload/versions_migrations', value)
        return value

    def test_before_dump_reference_bound_and_replay_refused(self):
        logical.begin(self.root, None, 'a'*64)
        with self.assertRaisesRegex(Blocked, 'consumed'): logical.begin(self.root, None, 'a'*64)
        value = self.finish()
        hashes = {'postgresql_custom_dump': logical.digest(self.root/'payload/postgresql_custom_dump')}
        logical.verify_retained(self.root, self.spec, hashes)
        self.assertEqual(value['logical_reference'], self.identity)
        with self.assertRaisesRegex(Blocked, 'consumed'): self.finish()
        hashes['postgresql_custom_dump'] = 'b'*64
        with self.assertRaisesRegex(Blocked, 'mismatch'): logical.verify_retained(self.root, self.spec, hashes)

    def test_after_drift_leaves_no_accepted_reference(self):
        logical.begin(self.root, None, 'a'*64)
        changed = copy.deepcopy(self.identity); changed['tables']['sample']['rows'] += 1
        with patch.object(logical, 'probe', return_value=(changed, 1.0)):
            with self.assertRaisesRegex(Blocked, 'changed'): self.finish()
        self.assertFalse((self.root/'logical-reference.json').exists())
        self.assertFalse((self.root/'logical-capture.json').exists())
        self.assertTrue((self.root/'payload/postgresql_custom_dump').exists())

    def test_probe_failure_preserves_payload_and_before_receipt(self):
        logical.begin(self.root, None, 'a'*64)
        with patch.object(logical, 'probe', side_effect=ValueError('native_command_failed')):
            with self.assertRaises(ValueError): self.finish()
        self.assertTrue((self.root/'logical-before.json').exists())
        self.assertFalse((self.root/'logical-reference.json').exists())

    def test_missing_before_and_unsafe_reference_refused(self):
        with self.assertRaises(FileNotFoundError): self.finish()
        logical.begin(self.root, None, 'a'*64); self.finish()
        path = self.root/'logical-reference.json'; path.chmod(0o644)
        with self.assertRaisesRegex(Blocked, 'unsafe_metadata'): logical.read(path)


if __name__ == '__main__': unittest.main()
