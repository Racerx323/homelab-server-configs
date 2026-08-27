#!/usr/bin/env python3
"""Offline regressions for the protected Doppler master-key writer."""

from __future__ import annotations

import importlib.util
import json
import os
import stat
import sys
import tempfile
import threading
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
CLIENT_PATH = ROOT / "backblaze-b2/scripts/protected_doppler_master_write.py"
SPEC = importlib.util.spec_from_file_location("protected_doppler_write", CLIENT_PATH)
assert SPEC is not None and SPEC.loader is not None
CLIENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CLIENT)


class ProtectedWriteTests(unittest.TestCase):
    def make_root(self) -> tuple[tempfile.TemporaryDirectory[str], Path, int]:
        temporary = tempfile.TemporaryDirectory(
            prefix="backblaze-b2-master-key-rotation.", dir="/tmp"
        )
        root = Path(temporary.name)
        root.chmod(0o700)
        return temporary, root, CLIENT.validate_root(root)

    @staticmethod
    def make_fifo(root: Path, name: str, value: bytes) -> threading.Thread:
        fifo = root / name
        os.mkfifo(fifo, 0o600)

        def writer() -> None:
            with fifo.open("wb") as stream:
                stream.write(value)

        thread = threading.Thread(target=writer, daemon=True)
        thread.start()
        return thread

    def test_values_use_stdin_only_and_name_readback_is_value_free(self) -> None:
        temporary, root, root_fd = self.make_root()
        calls: list[tuple[tuple[str, ...], bytes | None]] = []
        key_id = b"fixture-master-id"
        key_value = b"fixture-master-value"
        writers = [
            self.make_fifo(root, "id.fifo", key_id),
            self.make_fifo(root, "value.fifo", key_value),
        ]

        def runner(argv: tuple[str, ...], value: bytearray | None) -> bytes:
            captured = None if value is None else bytes(value)
            calls.append((argv, captured))
            if "--only-names" in argv:
                return json.dumps({name: {} for name in CLIENT.EXPECTED_NAMES}).encode()
            return b""

        try:
            checks = CLIENT.store_from_fifos(root_fd, "id.fifo", "value.fifo", runner)
        finally:
            os.close(root_fd)
            temporary.cleanup()
        for writer in writers:
            writer.join(timeout=2)
            self.assertFalse(writer.is_alive())
        self.assertEqual(
            checks,
            {
                "master_key_id_written": True,
                "master_key_value_written": True,
                "exact_names_present": True,
                "value_readback_performed": False,
            },
        )
        self.assertEqual(calls[0][1], key_id)
        self.assertEqual(calls[1][1], key_value)
        self.assertIsNone(calls[2][1])
        rendered_argv = " ".join(part for argv, _ in calls for part in argv)
        self.assertNotIn(key_id.decode(), rendered_argv)
        self.assertNotIn(key_value.decode(), rendered_argv)
        self.assertIn("--only-names", calls[2][0])

    def test_second_write_failure_is_manual_intervention(self) -> None:
        temporary, root, root_fd = self.make_root()
        writers = [
            self.make_fifo(root, "id.fifo", b"fixture-id"),
            self.make_fifo(root, "value.fifo", b"fixture-value"),
        ]
        call_count = 0

        def runner(argv: tuple[str, ...], value: bytearray | None) -> bytes:
            nonlocal call_count
            call_count += 1
            if call_count == 2:
                raise CLIENT.ProtectedWriteBlocked("doppler_command_failed")
            return b""

        try:
            with self.assertRaisesRegex(
                CLIENT.ProtectedWriteBlocked, "partial_secret_write_manual_intervention"
            ):
                CLIENT.store_from_fifos(root_fd, "id.fifo", "value.fifo", runner)
        finally:
            os.close(root_fd)
            temporary.cleanup()
        for writer in writers:
            writer.join(timeout=2)

    def test_value_bearing_name_readback_is_rejected(self) -> None:
        payload = json.dumps({CLIENT.KEY_ID_NAME: {"raw": "fixture"}}).encode()
        with self.assertRaisesRegex(CLIENT.ProtectedWriteBlocked, "doppler_values_exposed"):
            CLIENT.parse_name_only_output(payload)

    def test_post_write_readback_failure_is_manual_intervention(self) -> None:
        temporary, root, root_fd = self.make_root()
        writers = [
            self.make_fifo(root, "id.fifo", b"fixture-id"),
            self.make_fifo(root, "value.fifo", b"fixture-value"),
        ]

        def runner(argv: tuple[str, ...], value: bytearray | None) -> bytes:
            if "--only-names" in argv:
                return b"{}"
            return b""

        try:
            with self.assertRaisesRegex(
                CLIENT.ProtectedWriteBlocked,
                "post_write_acceptance_manual_intervention",
            ):
                CLIENT.store_from_fifos(root_fd, "id.fifo", "value.fifo", runner)
        finally:
            os.close(root_fd)
            temporary.cleanup()
        for writer in writers:
            writer.join(timeout=2)

    def test_fifo_wrong_mode_is_rejected_before_read(self) -> None:
        temporary, root, root_fd = self.make_root()
        fifo = root / "secret.fifo"
        os.mkfifo(fifo, 0o600)
        fifo.chmod(0o644)
        try:
            with self.assertRaisesRegex(CLIENT.ProtectedWriteBlocked, "unsafe_secret_fifo"):
                CLIENT.read_owned_fifo(root_fd, fifo.name)
        finally:
            os.close(root_fd)
            temporary.cleanup()

    def test_fifo_mode_and_identity_are_enforced_and_consumed(self) -> None:
        temporary, root, root_fd = self.make_root()
        fifo = root / "secret.fifo"
        os.mkfifo(fifo, 0o600)

        def feed() -> None:
            with fifo.open("wb") as stream:
                stream.write(b"fixture")

        thread = threading.Thread(target=feed, daemon=True)
        thread.start()
        try:
            value = CLIENT.read_owned_fifo(root_fd, fifo.name)
            self.assertEqual(value, bytearray(b"fixture"))
            self.assertFalse(fifo.exists())
        finally:
            os.close(root_fd)
            temporary.cleanup()
        thread.join(timeout=2)

    def test_evidence_is_exclusive_mode_0600_and_sanitized(self) -> None:
        temporary, root, root_fd = self.make_root()
        try:
            CLIENT.write_evidence(
                root_fd,
                "a" * 64,
                "blocked",
                {"master_key_id_written": True},
                "partial_secret_write_manual_intervention",
            )
        finally:
            os.close(root_fd)
        evidence = root / "doppler-write-result.json"
        self.assertEqual(stat.S_IMODE(evidence.stat().st_mode), 0o600)
        document = json.loads(evidence.read_text(encoding="utf-8"))
        self.assertFalse(document["secret_values_or_identifiers_retained"])
        self.assertNotIn("fixture", evidence.read_text(encoding="utf-8"))
        temporary.cleanup()

    def test_exact_doppler_argv_uses_stdin_form(self) -> None:
        for name in CLIENT.EXPECTED_NAMES:
            argv = CLIENT.set_argv(name)
            self.assertIn(name, argv)
            self.assertFalse(any("=" in argument for argument in argv))
            self.assertIn("--no-read-env", argv)
            self.assertIn("--silent", argv)
        self.assertIn("--only-names", CLIENT.names_argv())


if __name__ == "__main__":
    unittest.main()
