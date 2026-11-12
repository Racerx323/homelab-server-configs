import importlib.util
import os
from pathlib import Path
import tempfile
import subprocess
import sys
import json
import unittest

spec = importlib.util.spec_from_file_location("configuration", Path(__file__).parents[1] / "scripts/configure-miniserv.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class MiniservConfiguration(unittest.TestCase):
    def test_preserves_unmanaged_keys_and_replaces_once(self):
        self.assertEqual(module.render(b"port=10000\nroot=/usr/share/webmin\nssl=1\n", {"ssl": "0"}),
                         b"port=10000\nroot=/usr/share/webmin\nssl=0\n")

    def test_duplicate_managed_setting_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "duplicate"):
            module.render(b"bind=0.0.0.0\nbind=127.0.0.1\n", {"bind": "127.0.0.1"})

    def test_multiline_policy_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "invalid"):
            module.render(b"ssl=1\n", {"ssl": "0\nbind=0.0.0.0"})

    def test_atomic_configuration_preserves_mode_and_other_options(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "miniserv.conf"
            path.write_bytes(b"root=/usr/share/webmin\nssl=1\n")
            path.chmod(0o600)
            module.configure(path, {"ssl": "0"})
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(path.read_bytes(), b"root=/usr/share/webmin\nssl=0\n")
            self.assertEqual(list(path.parent.glob(".miniserv-*")), [])

    def test_symlink_rejected_without_changing_referent(self):
        with tempfile.TemporaryDirectory() as directory:
            real = Path(directory) / "real"
            real.write_bytes(b"ssl=1\n")
            path = Path(directory) / "miniserv.conf"
            path.symlink_to(real)
            with self.assertRaisesRegex(ValueError, "symlink"):
                module.configure(path, {"ssl": "0"})
            self.assertEqual(real.read_bytes(), b"ssl=1\n")

    def test_module_profile_preserves_other_collection_and_temperature_options(self):
        raw = b"collect_interval=5\ncollect_pkgs=1\ncollect_notemp=1\n"
        result = module.render(raw, {"collect_pkgs": "0"})
        self.assertIn(b"collect_interval=5\n", result)
        self.assertIn(b"collect_notemp=1\n", result)
        self.assertEqual(result.count(b"collect_pkgs="), 1)
        self.assertIn(b"collect_pkgs=0\n", result)

    def test_verify_cli_is_read_only_and_rejects_missing_or_duplicate_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "config"
            policy = Path(directory) / "policy.json"
            policy.write_text(json.dumps({"collect_pkgs": "0"}))
            for raw, expected in [(b"collect_pkgs=0\n", 0),
                                  (b"collect_interval=5\n", 1),
                                  (b"collect_pkgs=0\ncollect_pkgs=0\n", 1)]:
                config.write_bytes(raw)
                before = config.stat().st_mtime_ns
                result = subprocess.run([sys.executable, "-B", str(Path(module.__file__)),
                                         "--config", str(config), "--policy", str(policy), "--verify"],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, expected)
                self.assertEqual(config.read_bytes(), raw)
                self.assertEqual(config.stat().st_mtime_ns, before)


if __name__ == "__main__":
    unittest.main()
