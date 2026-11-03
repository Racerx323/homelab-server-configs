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
        import yaml
        current = yaml.safe_load((ROOT/'Nautobot/manifests/operation.yaml').read_text())
        if current['operation'].get('stage') != bundle.transport.STAGE:
            self.skipTest('no pending upload definition; native tests construct disposable inputs')
        accepted = yaml.safe_load((ROOT/'Nautobot/manifests/accepted-live-state.yaml').read_text())
        consumed = accepted.get('recurring_upload_integrity', {}).get('operation_id') == current['operation']['id']
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)/'bundle'
            if consumed:
                # Accepted-state reconciliation invalidates re-freezing the consumed inputs.
                with self.assertRaisesRegex(ValueError, 'accepted_source_drift'):
                    bundle.transport.freeze(root)
                return
            bundle.transport.freeze(root)
            digest = bundle.transport.sha(root/'bundle.json')
            op = bundle.transport.verify(root, digest)
            self.assertTrue(op['operation']['execution_enabled'])
            with self.assertRaises(ValueError): bundle.transport.verify(root, '0'*64)
            (root/'runtime/scripts/upload_node.py').write_text('changed')
            with self.assertRaises(ValueError): bundle.transport.verify(root, digest)


if __name__ == '__main__': unittest.main()
