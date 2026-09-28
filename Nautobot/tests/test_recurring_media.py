#!/usr/bin/env python3
"""Media rejection and capacity admission regressions; no target access."""
import io
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'ansible/scripts'))
import media_namespace as media
import recurring_node as node


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


if __name__=='__main__': unittest.main()
