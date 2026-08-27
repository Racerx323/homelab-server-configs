#!/usr/bin/env python3
"""Offline safety regressions for the B2 S3 compatibility launcher."""

from __future__ import annotations

import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest import mock

import yaml

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "backblaze-b2/scripts"
sys.path.insert(0, str(SCRIPT_DIR))
LAUNCHER_PATH = SCRIPT_DIR / "run_s3_compatibility_probe.py"
OPERATION_PATH = ROOT / "backblaze-b2/manifests/operation.yaml"

SPEC = importlib.util.spec_from_file_location("s3_launcher", LAUNCHER_PATH)
assert SPEC is not None and SPEC.loader is not None
LAUNCHER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = LAUNCHER
SPEC.loader.exec_module(LAUNCHER)
PROBE = LAUNCHER.probe


class ContractTests(unittest.TestCase):
    def test_manifest_bundle_and_launcher_inputs_match_exactly(self) -> None:
        operation = yaml.safe_load(OPERATION_PATH.read_text(encoding="utf-8"))
        self.assertEqual(
            tuple(operation["authorization"]["bundle_inputs"]),
            LAUNCHER.BUNDLE_FILES,
        )
        self.assertEqual(
            operation["authorization"]["bundle_domain_separator"],
            LAUNCHER.BUNDLE_DOMAIN,
        )
        self.assertEqual(operation["operation"]["id"], LAUNCHER.EXPECTED_OPERATION_ID)

    def test_every_bundle_digest_affects_hash(self) -> None:
        rows = LAUNCHER.bundle_file_hashes()
        baseline = LAUNCHER.bundle_hash(rows)
        for index in range(len(rows)):
            with self.subTest(path=rows[index][1]):
                changed = list(rows)
                changed[index] = ("f" * 64 if rows[index][0] != "f" * 64 else "e" * 64, rows[index][1])
                self.assertNotEqual(LAUNCHER.bundle_hash(changed), baseline)

    def test_no_old_or_administrator_fallback_is_present(self) -> None:
        source = LAUNCHER_PATH.read_text(encoding="utf-8")
        self.assertNotIn("prd_b2_admin", source)
        self.assertNotIn("MASTER_APPLICATION_KEY", source)
        self.assertNotIn("CANDIDATE", source)
        self.assertNotIn("homelab-nautobot-restic-prd\"", source)
        self.assertIn('"old_key_fallback_attempted": False', source)

    def test_unready_fixture_rejects_before_evidence_or_client(self) -> None:
        before = set(Path("/tmp").glob("backblaze-b2-s3-compatibility.*"))
        called = False
        unready = LAUNCHER.load_operation()
        unready["operation"]["authorization_ready"] = False

        def client(*_args: Any) -> str:
            nonlocal called
            called = True
            return "passed"

        with mock.patch.object(
            LAUNCHER, "validate_operation", return_value=unready
        ):
            with self.assertRaisesRegex(
                LAUNCHER.LauncherBlocked, "operation_not_ready"
            ):
                LAUNCHER.run("execute", "a" * 64, client=client)
        self.assertFalse(called)
        self.assertEqual(
            set(Path("/tmp").glob("backblaze-b2-s3-compatibility.*")), before
        )

    def test_cli_hash_mismatch_rejects_before_doppler_or_network(self) -> None:
        before = set(Path("/tmp").glob("backblaze-b2-s3-compatibility.*"))
        with tempfile.TemporaryDirectory() as temporary:
            marker = Path(temporary) / "external-called"
            fake = Path(temporary) / "doppler"
            fake.write_text(f"#!/bin/sh\ntouch '{marker}'\nexit 99\n", encoding="utf-8")
            fake.chmod(0o700)
            environment = os.environ.copy()
            environment["PATH"] = f"{temporary}:{environment['PATH']}"
            result = subprocess.run(
                (sys.executable, str(LAUNCHER_PATH), "execute", "a" * 64),
                cwd=ROOT,
                env=environment,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
                timeout=30,
            )
            self.assertEqual(result.returncode, 66)
            self.assertIn("bundle_hash_mismatch", result.stderr.decode())
            self.assertFalse(marker.exists())
        self.assertEqual(
            set(Path("/tmp").glob("backblaze-b2-s3-compatibility.*")), before
        )

    def test_unauthorized_preflight_fixture_rejects_before_evidence_or_client(self) -> None:
        before = set(Path("/tmp").glob("backblaze-b2-s3-compatibility.*"))
        called = False
        unauthorized = LAUNCHER.load_operation()
        unauthorized["preflight"]["execution_authorized"] = False

        def client(*_args: Any) -> str:
            nonlocal called
            called = True
            return "preflight_passed"

        with mock.patch.object(
            LAUNCHER, "validate_operation", return_value=unauthorized
        ):
            with self.assertRaisesRegex(
                LAUNCHER.LauncherBlocked, "preflight_not_authorized"
            ):
                LAUNCHER.run("preflight", client=client)
        self.assertFalse(called)
        self.assertEqual(
            set(Path("/tmp").glob("backblaze-b2-s3-compatibility.*")), before
        )

    def test_active_operation_is_hash_ready_and_preflight_is_consumed(self) -> None:
        document = LAUNCHER.load_operation()
        self.assertTrue(document["operation"]["authorization_ready"])
        self.assertTrue(document["implementation"]["live_execution_enabled"])
        self.assertEqual(document["authorization"]["blockers"], [])
        self.assertEqual(document["preflight"]["state"], "passed")
        self.assertFalse(document["preflight"]["execution_authorized"])


class ClassificationTests(unittest.TestCase):
    def test_representative_terminal_classifications(self) -> None:
        cases = (
            ("preflight", "preflight_passed", False, False, True, ("preflight", "passed")),
            ("preflight", "preflight_blocked", False, False, True, ("preflight", "blocked")),
            ("execute", "blocked", False, False, True, ("pre_mutation", "blocked")),
            ("execute", "blocked", True, True, True, ("cleanup", "rolled_back")),
            ("execute", "manual_intervention", True, True, False, ("cleanup", "manual_intervention")),
            ("execute", "passed", True, True, True, ("acceptance", "completed")),
            ("execute", "internal_error", True, False, False, ("cleanup", "manual_intervention")),
        )
        for mode, result, put, delete, absence, expected in cases:
            with self.subTest(mode=mode, result=result, put=put, delete=delete, absence=absence):
                evidence = {
                    "mutation": {"put_attempted": put, "delete_attempted": delete},
                    "cleanup": {"absence_proven": absence},
                }
                self.assertEqual(LAUNCHER.classify(mode, result, evidence), expected)

    def test_offline_preflight_path_writes_protected_sanitized_terminal_evidence(self) -> None:
        def client(root: Path, bundle: str, run_id: str, mode: str) -> str:
            self.assertEqual(mode, "preflight")
            root_fd = PROBE.validate_evidence_root(root)
            try:
                recorder = PROBE.EvidenceRecorder(root_fd, bundle)
                recorder.observe("preflight", "authorize_canonical_credential", "http_2xx")
                recorder.finish(
                    "preflight_passed", None,
                    PROBE._sha256(run_id.encode()), True, False,
                )
            finally:
                os.close(root_fd)
            return "preflight_passed"

        authorized = LAUNCHER.load_operation()
        authorized["preflight"]["execution_authorized"] = True
        with mock.patch.object(LAUNCHER, "validate_operation", return_value=authorized):
            status, root = LAUNCHER.run("preflight", client=client)
        try:
            self.assertEqual(status, 0)
            self.assertEqual(stat.S_IMODE(root.stat().st_mode), 0o700)
            for name in (
                "bundle-files.sha256", "bundle.sha256", "result.json",
                "terminal-result.json",
            ):
                self.assertEqual(stat.S_IMODE((root / name).stat().st_mode), 0o600)
            terminal = json.loads((root / "terminal-result.json").read_text())
            self.assertEqual(terminal["result"], "passed")
            self.assertEqual(terminal["terminal_phase"], "preflight")
            self.assertFalse(terminal["put_attempted"])
            self.assertFalse(terminal["old_key_fallback_attempted"])
            self.assertFalse(terminal["credential_values_or_identifiers_retained"])
            rendered = (root / "terminal-result.json").read_text()
            self.assertNotIn("canonical-id", rendered)
            self.assertNotIn("canonical-value", rendered)
        finally:
            for path in root.iterdir():
                path.unlink()
            root.rmdir()

    def test_terminal_evidence_rejects_missing_client_evidence_as_success(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="backblaze-b2-s3-compatibility.", dir="/tmp"
        ) as temporary:
            root = Path(temporary)
            root.chmod(0o700)
            root_fd = PROBE.validate_evidence_root(root)
            try:
                terminal = LAUNCHER.write_terminal_evidence(
                    root_fd, root, "a" * 64, "execute", "passed"
                )
            finally:
                os.close(root_fd)
            self.assertEqual(terminal["result"], "manual_intervention")
            self.assertIsNone(terminal["client_evidence_sha256"])

    def test_preflight_cannot_pass_without_matching_client_evidence(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="backblaze-b2-s3-compatibility.", dir="/tmp"
        ) as temporary:
            root = Path(temporary)
            root.chmod(0o700)
            root_fd = PROBE.validate_evidence_root(root)
            try:
                terminal = LAUNCHER.write_terminal_evidence(
                    root_fd, root, "a" * 64, "preflight", "preflight_passed"
                )
            finally:
                os.close(root_fd)
            self.assertEqual(terminal["result"], "blocked")
            self.assertIsNone(terminal["client_evidence_sha256"])

    def test_interrupt_after_put_is_recorded_as_manual_intervention(self) -> None:
        def client(root: Path, bundle: str, run_id: str, mode: str) -> str:
            self.assertEqual(mode, "preflight")
            root_fd = PROBE.validate_evidence_root(root)
            try:
                recorder = PROBE.EvidenceRecorder(root_fd, bundle)
                recorder.mutation(put_attempted=True)
            finally:
                os.close(root_fd)
            raise KeyboardInterrupt()

        authorized = LAUNCHER.load_operation()
        authorized["preflight"]["execution_authorized"] = True
        with mock.patch.object(LAUNCHER, "validate_operation", return_value=authorized):
            status, root = LAUNCHER.run("preflight", client=client)
        try:
            self.assertEqual(status, 3)
            terminal = json.loads((root / "terminal-result.json").read_text())
            self.assertEqual(terminal["result"], "manual_intervention")
            self.assertTrue(terminal["put_attempted"])
        finally:
            for path in root.iterdir():
                path.unlink()
            root.rmdir()


class GateTests(unittest.TestCase):
    def ready_document(self) -> dict[str, Any]:
        return {
            "operation": {"authorization_ready": True},
            "implementation": {"live_execution_enabled": True},
            "authorization": {"blockers": []},
        }

    def test_ready_gate_requires_exact_hash_and_empty_blockers(self) -> None:
        LAUNCHER.require_execute_ready(self.ready_document(), "a" * 64, "a" * 64)
        for mutation in ("ready", "enabled", "blocker"):
            document = self.ready_document()
            if mutation == "ready":
                document["operation"]["authorization_ready"] = False
            elif mutation == "enabled":
                document["implementation"]["live_execution_enabled"] = False
            else:
                document["authorization"]["blockers"] = ["still_blocked"]
            with self.subTest(mutation=mutation):
                with self.assertRaisesRegex(LAUNCHER.LauncherBlocked, "operation_not_ready"):
                    LAUNCHER.require_execute_ready(document, "a" * 64, "a" * 64)

    def test_hash_mismatch_and_invalid_hash_are_distinct(self) -> None:
        with self.assertRaisesRegex(LAUNCHER.LauncherBlocked, "invalid_authorized_hash"):
            LAUNCHER.require_execute_ready(self.ready_document(), "wrong", "a" * 64)
        with self.assertRaisesRegex(LAUNCHER.LauncherBlocked, "bundle_hash_mismatch"):
            LAUNCHER.require_execute_ready(self.ready_document(), "b" * 64, "a" * 64)

    def test_preflight_gate_requires_explicit_authorization_and_no_fallback(self) -> None:
        document = LAUNCHER.load_operation()
        document["preflight"]["execution_authorized"] = False
        with self.assertRaisesRegex(LAUNCHER.LauncherBlocked, "preflight_not_authorized"):
            LAUNCHER.require_preflight_authorized(document)
        document["preflight"]["execution_authorized"] = True
        LAUNCHER.require_preflight_authorized(document)
        for key, value in (
            ("mutation_authorized", True),
            ("old_key_fallback_available", True),
            ("old_key_fallback_attempt_authorized", True),
        ):
            with self.subTest(key=key):
                changed = yaml.safe_load(yaml.safe_dump(document))
                changed["preflight"][key] = value
                with self.assertRaisesRegex(
                    LAUNCHER.LauncherBlocked, "preflight_not_authorized"
                ):
                    LAUNCHER.require_preflight_authorized(changed)

    def test_validator_failures_are_sanitized(self) -> None:
        cases = (
            (FileNotFoundError("missing"), "operation_validator_unavailable"),
            (
                subprocess.TimeoutExpired(("check-jsonschema",), 30),
                "operation_validator_timeout",
            ),
        )
        for failure, expected in cases:
            with self.subTest(expected=expected):
                runner = mock.Mock(side_effect=failure)
                with self.assertRaisesRegex(LAUNCHER.LauncherBlocked, expected):
                    LAUNCHER.validate_operation(runner=runner)


if __name__ == "__main__":
    unittest.main(verbosity=2)
