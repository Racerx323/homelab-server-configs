#!/usr/bin/env python3
"""Capture payload integrity, media admission and verified disposal boundaries."""
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'ansible/scripts'))
import media_namespace as media
import recurring_node as node
import recurring_logical as logical
from recurring_disposal import dispose
from recurring_protection import protected, require, atomic, Blocked


class MediaTests(unittest.TestCase):
    def test_directory_archive_and_unsafe_entries(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name); (root/'nested').mkdir()
            output=io.BytesIO(); media.archive(root,output); output.seek(0)
            with tarfile.open(fileobj=output) as archive:
                self.assertEqual(archive.getnames(),['.','nested'])
                self.assertTrue(all(item.isdir() for item in archive))
            (root/'file').write_text('data')
            with self.assertRaises(ValueError): media.directories(root)
            (root/'file').unlink(); (root/'link').symlink_to(root/'nested')
            with self.assertRaises(ValueError): media.directories(root)

    def test_budget_reserved_before_credentials_or_pause(self):
        with tempfile.TemporaryDirectory(prefix='nautobot-recurring.') as name:
            root=Path(name)
            cfg=dict(artifact_sha256={},minimum_free_bytes=10,capture_limits={'database':100},maximum_retained_bytes=99)
            with patch.object(node,'scrub_idle'),patch.object(node,'health'),patch.object(node,'media_directories',return_value=[]),patch.object(node.capture,'reviewed_files'),patch.object(node,'resolve') as resolve:
                with patch.object(node.shutil,'disk_usage',return_value=type('Usage',(),{'free':109})()):
                    with self.assertRaisesRegex(ValueError,'capture_capacity'): node.prepare(root/'binding',cfg,root)
                with patch.object(node.shutil,'disk_usage',return_value=type('Usage',(),{'free':110})()):
                    with self.assertRaisesRegex(ValueError,'retained_capacity'): node.prepare(root/'binding',cfg,root)
                resolve.assert_not_called()


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


class DisposalTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='nautobot-recurring.')
        self.root=Path(self.tmp.name)
        payload=self.root/'payload'; payload.mkdir(mode=0o700)
        self.files=['database','media']
        spec={'operation_id':'nautobot-recurring','captures':{n:{'maximum_bytes':1000} for n in self.files}}
        hashes={}
        for n in self.files:
            p=payload/n;p.write_bytes(b'fixture');p.chmod(0o600)
            hashes[n]=hashlib.sha256(p.read_bytes()).hexdigest()
        self.row=dict(specification_sha256=hashlib.sha256(json.dumps(spec,sort_keys=True,separators=(',',':')).encode()).hexdigest(),capture_passed=True,
                      content_sha256=hashes,credential_cleanup={'password':True,'credentials.json':True},
                      upload_passed=True,integrity_passed=True,backup_exit_status=0,integrity_exit_status=0,
                      snapshot_id='a'*64,new_snapshot_ids=['a'*64])
        atomic(self.root/'application-backup.json',spec)
        atomic(self.root/'application-capture-result.json',self.row)
        atomic(self.root/'application-backup-result.json',self.row)

    def tearDown(self): self.tmp.cleanup()
    def run_disposal(self): dispose(self.root,protected,require,atomic)

    def test_success_preserves_receipts_and_root(self):
        self.run_disposal()
        self.assertEqual(list((self.root/'payload').iterdir()),[])
        self.assertTrue((self.root/'application-backup-result.json').is_file())
        self.assertEqual(json.loads((self.root/'payload-disposal.json').read_text())['phase'],'complete')

    def test_failed_integrity_retains_every_file(self):
        self.row['integrity_passed']=False;atomic(self.root/'application-backup-result.json',self.row)
        with self.assertRaises(Blocked): self.run_disposal()
        self.assertEqual(len(list((self.root/'payload').iterdir())),2)

    def test_all_files_verified_before_deletion(self):
        (self.root/'payload/media').write_bytes(b'changed')
        with self.assertRaises(Blocked): self.run_disposal()
        self.assertTrue((self.root/'payload/database').exists())

    def test_links_and_extra_files_refused(self):
        p=self.root/'payload/media';p.unlink();p.symlink_to(self.root/'application-backup.json')
        with self.assertRaises(OSError): self.run_disposal()
        p.unlink();os.link(self.root/'payload/database',p)
        with self.assertRaises(Blocked): self.run_disposal()
        self.assertTrue((self.root/'payload/database').exists())

    def test_unexpected_membership_retained(self):
        (self.root/'payload/extra').write_text('retain')
        with self.assertRaises(Blocked): self.run_disposal()
        self.assertEqual(len(list((self.root/'payload').iterdir())),3)

    def test_snapshot_and_specification_bound(self):
        self.row['specification_sha256']='b'*64;atomic(self.root/'application-backup-result.json',self.row)
        with self.assertRaises(Blocked): self.run_disposal()
        self.assertEqual(len(list((self.root/'payload').iterdir())),2)


if __name__ == '__main__': unittest.main()
