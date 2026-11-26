#!/usr/bin/env python3
"""Offline transport and cleanup ownership; native qualification is separate."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT/'Nautobot/ansible/scripts'
sys.path.insert(0, str(SCRIPTS))
sys.dont_write_bytecode = True
import upload_node as node

spec = importlib.util.spec_from_file_location('upload_bundle', SCRIPTS/'upload-integrity-bundle.py')
bundle = importlib.util.module_from_spec(spec); spec.loader.exec_module(bundle)


class UploadTests(unittest.TestCase):
    def test_stop_post_does_not_delete_unowned_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            secret = root/'password'; secret.write_text('local-placeholder'); secret.chmod(0o600)
            self.assertTrue(all(node.cleanup({'payload_root': str(root)}, root).values()))
            self.assertTrue(secret.exists())

    def test_stop_post_attempts_every_owned_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            marker = root/'credentials-owned.json'
            marker.write_text(json.dumps({'payload_root': str(root)})); marker.chmod(0o600)
            for name in node.SECRETS:
                path = root/name; path.write_text('local-placeholder'); path.chmod(0o600)
            (root/'password').chmod(0o644)
            result = node.cleanup({'payload_root': str(root)}, root)
            self.assertFalse(result['password'])
            self.assertTrue(all(result[name] for name in node.SECRETS if name != 'password'))

    def test_bundle_integrity_and_accepted_bindings(self):
        from bundle_samples import definition
        spec = importlib.util.spec_from_file_location('upload_bundle', SCRIPTS/'upload-integrity-bundle.py')
        bundle = importlib.util.module_from_spec(spec); spec.loader.exec_module(bundle)
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            source = definition('upload', bundle, parent)
            candidate = parent/'candidate'
            bundle.transport.freeze(candidate, operation=source)
            digest = bundle.transport.sha(candidate/'bundle.json')
            self.assertTrue(bundle.transport.verify(candidate, digest)['operation']['execution_enabled'])
            with self.assertRaises(ValueError): bundle.transport.verify(candidate, '0'*64)
            (candidate/'runtime/scripts/recurring_delivery.py').write_text('changed')
            with self.assertRaisesRegex(ValueError, 'input_drift'):
                bundle.transport.verify(candidate, digest)


if __name__ == '__main__': unittest.main()
