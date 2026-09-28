#!/usr/bin/env python3
"""Successful-payload disposal preserves failed, changed and unsafe captures."""
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'ansible/scripts'))
from recurring_disposal import dispose
from recurring_protection import protected, require, atomic, Blocked


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


if __name__=='__main__': unittest.main()
