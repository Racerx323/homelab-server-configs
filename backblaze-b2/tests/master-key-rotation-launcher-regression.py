#!/usr/bin/env python3
"""Offline regressions for the hash-bound master-key rotation launcher."""

from __future__ import annotations

import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "backblaze-b2/scripts/run-master-key-rotation.sh"
OPERATION = ROOT / "backblaze-b2/manifests/operation.yaml"


class LauncherTests(unittest.TestCase):
    def test_active_successor_rejects_before_doppler_or_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            marker = Path(temporary) / "doppler-called"
            fake = Path(temporary) / "doppler"
            fake.write_text(f"#!/bin/sh\ntouch '{marker}'\nexit 99\n", encoding="utf-8")
            fake.chmod(0o700)
            environment = os.environ.copy()
            environment["PATH"] = f"{temporary}:{environment['PATH']}"
            result = subprocess.run(
                [str(LAUNCHER), "execute", "0" * 64],
                cwd=ROOT,
                env=environment,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(result.returncode, 69)
            self.assertIn(
                "active operation does not belong to this launcher",
                result.stderr,
            )
            self.assertFalse(marker.exists())

    def test_show_bundle_rejects_active_successor(self) -> None:
        result = subprocess.run(
            [str(LAUNCHER), "show-bundle"], cwd=ROOT, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
        )
        self.assertEqual(result.returncode, 69)
        self.assertIn(
            "active operation does not belong to this launcher",
            result.stderr,
        )

    def test_consumed_operation_is_retired(self) -> None:
        operation = yaml.safe_load(OPERATION.read_text(encoding="utf-8"))
        self.assertEqual(operation["schema_version"], 1)
        self.assertNotEqual(
            operation["operation"].get("id"),
            "backblaze-b2-master-key-rotation-v1",
        )
        self.assertEqual(
            operation["operation"].get("id"),
            "backblaze-b2-capability-remediation-preflight-v3",
        )

    def test_launcher_has_exact_operation_id_gate(self) -> None:
        source = LAUNCHER.read_text(encoding="utf-8")
        self.assertIn(
            "expected_operation_id=backblaze-b2-master-key-rotation-v1",
            source,
        )
        self.assertIn('$(operation_id) != "${expected_operation_id}"', source)

    def test_existing_id_is_collected_before_generated_value(self) -> None:
        source = LAUNCHER.read_text(encoding="utf-8")
        id_prompt = (
            "Existing account-level master application-key ID "
            "(shown on the App Keys page): "
        )
        generation_instruction = "Generate the new master key value"
        value_prompt = "New one-time master application-key value: "
        self.assertLess(source.index(id_prompt), source.index(generation_instruction))
        self.assertLess(source.index(generation_instruction), source.index(value_prompt))
        self.assertNotIn("New master application-key ID", source)
        self.assertIn("master_key_id_not_supplied", source)
        self.assertIn("master_key_value_not_supplied", source)
        self.assertLess(source.index("[[ -n ${key_id_value} ]]"), source.index("mkfifo"))
        self.assertLess(source.index("[[ -n ${key_value} ]]"), source.index("mkfifo"))

    def test_launcher_has_bounded_terminal_classifications_and_cleanup(self) -> None:
        source = LAUNCHER.read_text(encoding="utf-8")
        for required in (
            "pre_mutation",
            "doppler_config_creation_attempted",
            "doppler_config_created",
            "master_generated",
            "credentials_stored",
            "accepted",
            "manual_intervention",
            "terminal-result.json",
            "trap cleanup_rotation EXIT",
        ):
            self.assertIn(required, source)
        self.assertNotIn("set -x", source)
        self.assertNotIn("doppler secrets get", source)

    def test_terminal_evidence_shape_is_secret_free_and_mode_0600(self) -> None:
        with tempfile.TemporaryDirectory(dir="/tmp") as temporary:
            path = Path(temporary) / "terminal-result.json"
            document = {
                "schema_version": 1,
                "operation": "backblaze-b2-master-key-rotation-v1",
                "bundle_sha256": "a" * 64,
                "terminal_phase": "master_generated",
                "result": "manual_intervention",
                "error_class": "protected_doppler_write_failed",
                "doppler_writer_evidence_sha256": None,
                "credential_values_or_identifiers_retained": False,
            }
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                json.dump(document, stream)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            rendered = path.read_text(encoding="utf-8")
            self.assertNotIn("applicationKey", rendered)
            self.assertNotIn("keyID", rendered)
            self.assertFalse(json.loads(rendered)["credential_values_or_identifiers_retained"])


if __name__ == "__main__":
    unittest.main()
