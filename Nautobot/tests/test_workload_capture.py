#!/usr/bin/env python3
"""Backup source containment and empty-media policy regressions."""
import hashlib
import io
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'ansible/scripts'))
import workload_capture as capture


class CaptureTests(unittest.TestCase):
    def test_empty_media_rejects_files_and_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root/'nested').mkdir()
            self.assertEqual(capture.empty_media(root), ['nested'])
            (root/'nested'/'upload').write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'media_not_empty'): capture.empty_media(root)
            (root/'nested'/'upload').unlink(); (root/'link').symlink_to(root/'nested')
            with self.assertRaisesRegex(ValueError, 'media_not_empty'): capture.empty_media(root)

    def test_only_reviewed_configuration_bytes_are_captured(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); config=root/'config.py'; config.write_bytes(b'nonsecret')
            env=root/'web.env';env.write_bytes(b'not-in-backup')
            expected={str(config):hashlib.sha256(config.read_bytes()).hexdigest()}
            with patch.object(capture,'CONFIG',config),patch.object(capture,'QUADLETS',root/'units'):
                self.assertEqual(capture.reviewed_files(expected),{str(config):b'nonsecret'})
                with self.assertRaisesRegex(ValueError,'source_not_allowed'):
                    capture.reviewed_files(dict(expected, **{str(env):hashlib.sha256(env.read_bytes()).hexdigest()}))
                config.write_bytes(b'drift')
                with self.assertRaisesRegex(ValueError,'source_changed'):capture.reviewed_files(expected)

    def test_archive_is_relative_and_recoverable(self):
        output=io.BytesIO();capture.archive({'/reviewed/config':b'exact'},output)
        with tarfile.open(fileobj=io.BytesIO(output.getvalue())) as stream:
            self.assertEqual(stream.getnames(),['reviewed/config'])
            self.assertEqual(stream.extractfile('reviewed/config').read(),b'exact')

    def test_qualification_failure_cleans_raw_dump_and_preserves_receipt(self):
        import importlib.util,json,shutil
        scripts=Path(capture.__file__).parent
        spec=importlib.util.spec_from_file_location('qualification',scripts/'qualify-workload-capture.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            shutil.copyfile(scripts.parents[2]/'restic/scripts/application-backup.py',root/'application-backup.py')
            (root/'contract.json').write_text('{"stop_criteria":{"mem_available_below_bytes":1}}')
            (root/'workload_capture.py').write_text("import sys\nsection=sys.argv[-1]\nif section=='postgresql_custom_dump':sys.stdout.buffer.write(b'PGDMPfixture')\nelif section=='media':sys.exit(1)\n")
            (root/'backup-sources.json').write_text('{"boot_id":"fixture","invocations":{}}')
            class Reader:
                def __init__(self,*args):pass
                def sample(self):return {'fixture':True,'mem_available_bytes':10**12,'boot_id':'fixture'}
            with patch.object(sys,'argv',['qualification','--root',str(root)]), \
                 patch.object(module.sampler,'run',return_value='{"__CURSOR":"fixture"}'), \
                 patch.object(module.sampler,'Reader',Reader), \
                 patch.object(module.sampler,'validate'):
                self.assertEqual(module.main(),1)
            result=json.loads((root/'capture-qualification.json').read_text())
            self.assertFalse(result['passed'])
            self.assertTrue(all(result['cleanup'].values()))
            self.assertFalse((root/'capture-postgresql_custom_dump').exists())

    def test_qualification_bundle_identity_before_execution(self):
        import importlib.util,json
        path=Path(capture.__file__).parent/'run-capture-qualification.py'
        spec=importlib.util.spec_from_file_location('qualification_launcher',path)
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/path.name).write_bytes(path.read_bytes())
            manifest={'files':{path.name:hashlib.sha256(path.read_bytes()).hexdigest()}}
            raw=json.dumps(manifest).encode();(root/'bundle.json').write_bytes(raw)
            approval=hashlib.sha256(raw).hexdigest()
            module.verify(root,approval)
            with self.assertRaisesRegex(ValueError,'bundle_identity'):module.verify(root,'0'*64)
            (root/path.name).write_text('substituted')
            with self.assertRaisesRegex(ValueError,'bundle_drift'):module.verify(root,approval)

    def test_capture_retains_specific_sanitized_failure(self):
        import json,subprocess
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            (root/'backup-sources.json').write_text(json.dumps({'consistency':'quiet_pilot_empty_media','quiet_window_confirmed':False}))
            result=subprocess.run([sys.executable,capture.__file__,'--root',directory,'media'],capture_output=True)
            self.assertEqual(result.returncode,1)
            receipt=json.loads((root/'capture-error.json').read_text())
            self.assertEqual(receipt,{'failure_class':'ValueError','reason':'quiet_window_unconfirmed'})
            self.assertEqual(result.stdout,b'')

    def test_database_capture_has_container_side_timeout(self):
        argv=capture.command(['pg_dump','--format=custom'])
        self.assertEqual(argv[-4:],['timeout','600','pg_dump','--format=custom'])
        self.assertIn('postgres',argv)

if __name__=='__main__':unittest.main()
