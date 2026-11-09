#!/usr/bin/env python3
"""Restore containment, identity rejection and cleanup regressions."""
import importlib.util
import hashlib
import copy
import io
import json
import os
from pathlib import Path
import sys
import tarfile
import tempfile
import time
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'Nautobot/ansible/scripts'))
import restore_payload
import restore_runtime
spec=importlib.util.spec_from_file_location('restore',ROOT/'restic/scripts/application-restore.py')
restore=importlib.util.module_from_spec(spec);spec.loader.exec_module(restore)


class RestoreTests(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory();self.addCleanup(self.temporary.cleanup)
        self.root=Path(self.temporary.name);self.root.chmod(0o700)

    def make_archives(self, member=None):
        expected={}
        for section in restore_payload.ARCHIVES:
            with tarfile.open(self.root/section,'w') as archive:
                item=member if member is not None and section=='configuration' else tarfile.TarInfo('.')
                if item.name=='.':item.type=tarfile.DIRTYPE
                archive.addfile(item,io.BytesIO(b'x'*item.size) if item.isfile() else None)
            expected[section]={'.':{'type':'directory'}}
        (self.root/'versions_migrations').write_text('{"versions":{},"migrations":[]}')
        return expected

    def test_valid_directory_only_archives(self):
        expected=self.make_archives()
        restore_payload.extract(self.root,self.root/'out',expected)
        self.assertTrue((self.root/'out/media').is_dir())
        with self.assertRaises(FileExistsError):restore_payload.extract(self.root,self.root/'out',expected)

    def test_recurring_reference_binding_before_any_extraction(self):
        import logical_database
        expected = self.make_archives()
        identity = dict(format='postgresql17-logical-v1', server_version_num='170006', schemas=['public'],
                        definitions={}, tables={'sample': {'rows': 1, 'sha256': 'a'*64}}, sequences={})
        reference = self.root/'logical-reference.json'
        reference.write_text(json.dumps(identity))
        dump = self.root/'postgresql_custom_dump'; dump.write_bytes(b'unit-only-dump')
        receipt = dict(format='recurring-logical-v1', specification_sha256='a'*64,
                       dump_sha256=hashlib.sha256(dump.read_bytes()).hexdigest(),
                       reference_sha256=hashlib.sha256(reference.read_bytes()).hexdigest(),
                       before_seconds=1, after_seconds=1, comparison=logical_database.compare(identity, identity))
        original = dict(versions={}, migrations=[], logical_reference=identity, logical_capture=receipt)
        for case in ('missing_reference', 'reference', 'dump', 'comparison', 'fields', 'half', 'symlink'):
            with self.subTest(case=case):
                value = copy.deepcopy(original); selected = reference
                if case == 'missing_reference': selected = None
                elif case == 'reference': value['logical_reference']['tables']['sample']['rows'] = 2
                elif case == 'dump': value['logical_capture']['dump_sha256'] = '0'*64
                elif case == 'comparison': value['logical_capture']['comparison']['equal'] = False
                elif case == 'fields': value['unexpected'] = True
                elif case == 'half': del value['logical_capture']
                else:
                    selected = self.root/'link'; selected.symlink_to(reference)
                (self.root/'versions_migrations').write_text(json.dumps(value))
                with self.assertRaises(ValueError):
                    restore_payload.extract(self.root, self.root/'out', expected, selected)
                self.assertFalse((self.root/'out').exists())
        (self.root/'versions_migrations').write_text(json.dumps(original))
        self.assertEqual(restore_payload.extract(self.root, self.root/'out', expected, reference), original)

    def test_unsafe_names_and_links_fail_before_extraction(self):
        for name,kind in [('../escape',tarfile.REGTYPE),('/absolute',tarfile.REGTYPE),
                          ('linked',tarfile.SYMTYPE),('hard',tarfile.LNKTYPE),('device',tarfile.CHRTYPE)]:
            with self.subTest(name=name):
                member=tarfile.TarInfo(name);member.type=kind;member.linkname='../escape'
                expected=self.make_archives(member)
                with self.assertRaises(ValueError):restore_payload.extract(self.root,self.root/'out',expected)
                self.assertFalse((self.root/'out').exists())

    def test_inventory_mismatch_and_symlink_destination(self):
        expected=self.make_archives();expected['media']['unexpected']={'type':'directory'}
        with self.assertRaises(ValueError):restore_payload.extract(self.root,self.root/'out',expected)
        expected=self.make_archives();(self.root/'out').symlink_to(self.root,target_is_directory=True)
        with self.assertRaises(ValueError):restore_payload.extract(self.root,self.root/'out',expected)

    def test_media_files_and_duplicate_names(self):
        expected=self.make_archives()
        for duplicate in (False,True):
            with tarfile.open(self.root/'media','w') as archive:
                member=tarfile.TarInfo('.')
                if duplicate:member.type=tarfile.DIRTYPE
                archive.addfile(member)
                if duplicate:archive.addfile(member)
            with self.assertRaises(ValueError):restore_payload.extract(self.root,self.root/'out',expected)

    def test_import_rejects_unowned_exposed_or_mounted_container(self):
        token='nautobot-restore-local-'+'a'*12
        dump=self.root/'dump';dump.write_bytes(b'PGDMPtest')
        for info in [
            {'Config':{'Labels':{}},'HostConfig':{},'Mounts':[]},
            {'Config':{'Labels':{'nautobot.restore.local':token}},'HostConfig':{'PortBindings':{'5432':[]}},'Mounts':[]},
            {'Config':{'Labels':{'nautobot.restore.local':token}},'HostConfig':{},'Mounts':[{'Source':'production'}]}]:
            calls=[]
            def call(argv, **kwargs):
                calls.append(argv)
                return json.dumps([info]).encode()
            with self.assertRaises(ValueError):
                restore_runtime.import_database(call,token+'-postgresql','restored_fixture',token,dump)
            self.assertEqual(len(calls),1)

    def test_actual_command_timeout_is_bounded(self):
        start=time.monotonic()
        with self.assertRaises(restore.backup.Blocked):
            restore.backup.invoke(['/usr/bin/sleep','10'], {'PATH':'/usr/bin:/bin'},
                                  time.monotonic()+0.1)
        self.assertLess(time.monotonic()-start,3)

    def test_bad_contract_still_removes_both_credentials(self):
        for name in ('password','credentials.json'):
            path=self.root/name;path.write_text('{}');path.chmod(0o600)
        result=restore.retrieve(self.root,{})
        self.assertFalse(result['retrieved'])
        self.assertEqual(result['reason'],'contract_fields')
        self.assertEqual(result['credential_cleanup'],{'password':True,'credentials.json':True})

    def test_cleanup_failure_does_not_skip_other_credential(self):
        (self.root/'password').symlink_to(self.root/'absent')
        path=self.root/'credentials.json';path.write_text('{}');path.chmod(0o600)
        result=restore.retrieve(self.root,{})
        self.assertFalse(result['credential_cleanup']['password'])
        self.assertTrue(result['credential_cleanup']['credentials.json'])


if __name__=='__main__':unittest.main()
