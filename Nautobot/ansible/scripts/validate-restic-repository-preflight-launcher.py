#!/usr/bin/env python3
"""Offline safety regressions for the Restic preflight controller."""

from __future__ import annotations

import importlib.util
import json
import os
import shutil
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

ROOT = Path(__file__).resolve().parents[3]
LAUNCHER_PATH = ROOT / "Nautobot/ansible/scripts/run-restic-repository-preflight.py"
OPERATION_PATH = ROOT / "Nautobot/manifests/deferred-restic-initialization.yaml"
SPEC = importlib.util.spec_from_file_location("restic_preflight_launcher", LAUNCHER_PATH)
assert SPEC is not None and SPEC.loader is not None
LAUNCHER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = LAUNCHER
SPEC.loader.exec_module(LAUNCHER)


def operation_definition() -> dict[str, Any]:
    document = yaml.safe_load(OPERATION_PATH.read_text(encoding="utf-8"))
    assert isinstance(document, dict)
    return document


def ready_definition(bundle: str) -> dict[str, Any]:
    document = operation_definition()
    document["preflight"]["state"] = "pending"
    document["preflight"]["implementation_state"] = "reviewed"
    document["preflight"]["authorization_ready"] = True
    document["preflight"]["execution_authorized"] = True
    document["authorization"]["blockers"] = [
        blocker
        for blocker in document["authorization"]["blockers"]
        if blocker != "read_only_repository_absence_preflight_review_required"
    ]
    return document


def remove_evidence(root: Path) -> None:
    if root.exists():
        shutil.rmtree(root)


class ContractTests(unittest.TestCase):
    def test_completed_preflight_is_not_executable(self) -> None:
        document = operation_definition()
        self.assertEqual(document["operation"]["state"], "definition")
        self.assertFalse(document["operation"]["authorization_ready"])
        self.assertTrue(document["secret_contract"]["repository_password"]["config_exists"])
        self.assertTrue(document["secret_contract"]["repository_password"]["key_exists"])
        self.assertEqual(document["preflight"]["state"], "passed")
        self.assertEqual(document["preflight"]["implementation_state"], "reviewed")
        self.assertFalse(document["preflight"]["authorization_ready"])
        self.assertFalse(document["preflight"]["execution_authorized"])
        self.assertFalse(document["authorization"]["mutation_authorized"])
        self.assertNotIn(
            "doppler_prd_restic_config_and_password_key_required",
            document["authorization"]["blockers"],
        )
        self.assertNotIn(
            "read_only_repository_absence_preflight_review_required",
            document["authorization"]["blockers"],
        )
        self.assertNotIn(
            "restic_version_and_execution_identity_preflight_required",
            document["authorization"]["blockers"],
        )
        self.assertIn(
            "accepted_host_baseline_identity_required",
            document["authorization"]["blockers"],
        )
        self.assertEqual(document["repository"]["initialized_state"], "absent_verified")
        self.assertEqual(
            document["provider_acceptance"]["accepted_live_state"],
            "backblaze-b2/manifests/accepted-live-state.yaml",
        )
        self.assertEqual(document["preflight"]["last_result"]["config_exit_status"], 10)
        self.assertEqual(document["preflight"]["last_result"]["execution_user"], "nautobot")
        self.assertEqual(document["preflight"]["last_result"]["restic_version_number"], "0.18.0")
        self.assertTrue(document["preflight"]["last_result"]["version_supported"])
        self.assertTrue(document["preflight"]["last_result"]["exact_version_retained"])

    def test_manifest_and_launcher_bundle_contract_match(self) -> None:
        preflight = operation_definition()["preflight"]
        self.assertEqual(tuple(preflight["bundle_inputs"]), LAUNCHER.BUNDLE_FILES)
        self.assertEqual(preflight["bundle_domain_separator"], LAUNCHER.BUNDLE_DOMAIN)

    def test_every_bundle_digest_changes_the_hash(self) -> None:
        rows = LAUNCHER.bundle_file_hashes()
        baseline = LAUNCHER.bundle_hash(rows)
        for index, row in enumerate(rows):
            with self.subTest(path=row[1]):
                changed = list(rows)
                replacement = "f" * 64 if row[0] != "f" * 64 else "e" * 64
                changed[index] = (replacement, row[1])
                self.assertNotEqual(LAUNCHER.bundle_hash(changed), baseline)

    def test_exact_doppler_references(self) -> None:
        expected = (
            ("restic_repository_password", "homelab-dev", "prd_restic", "NAUTOBOT_RESTIC_REPOSITORY_PASSWORD"),
            ("restic_b2_application_key_id", "homelab-dev", "prd_b2", "NAUTOBOT_RESTIC_B2_APPLICATION_KEY_ID"),
            ("restic_b2_application_key", "homelab-dev", "prd_b2", "NAUTOBOT_RESTIC_B2_APPLICATION_KEY"),
        )
        self.assertEqual(LAUNCHER.SECRET_REFERENCES, expected)
        for _, project, config, name in expected:
            argv = LAUNCHER.doppler_argv(project, config, name)
            self.assertEqual(
                argv,
                LAUNCHER.DOPPLER_BASE
                + ("secrets", "get", name, "--project", project, "--config", config, "--plain"),
            )

    def test_ansible_argv_contains_paths_not_secret_values(self) -> None:
        path = Path("/tmp/nautobot-restic-preflight.fixture/protected-extra-vars.json")
        argv = LAUNCHER.ansible_argv(path)
        self.assertEqual(
            argv,
            (
                "ansible-playbook", "--inventory", str(LAUNCHER.INVENTORY_PATH),
                "--limit", LAUNCHER.EXPECTED_TARGET, "--user", "ama",
                "--extra-vars", f"ansible_host={LAUNCHER.EXPECTED_ADDRESS}",
                "--extra-vars", f"@{path}", str(LAUNCHER.PLAYBOOK_PATH),
            ),
        )
        rendered = " ".join(argv)
        self.assertNotIn("repository-password-value", rendered)
        self.assertNotIn("b2-secret-value", rendered)

    def test_no_old_candidate_or_admin_credential_fallback(self) -> None:
        source = LAUNCHER_PATH.read_text(encoding="utf-8")
        self.assertNotIn("prd_b2_admin", source)
        self.assertNotIn("MASTER_APPLICATION_KEY", source)
        self.assertNotIn("CANDIDATE_APPLICATION_KEY", source)
        self.assertFalse(operation_definition()["preflight"]["credential_fallback_allowed"])

    def test_unready_operation_rejects_before_evidence_or_secrets(self) -> None:
        document = operation_definition()
        document["preflight"]["execution_authorized"] = False
        document["preflight"]["execution_authorized"] = False
        document["preflight"]["execution_authorized"] = False
        calculated = LAUNCHER.bundle_hash()
        before = set(Path("/tmp").glob(f"{LAUNCHER.EVIDENCE_PREFIX}*"))
        with mock.patch.object(LAUNCHER, "validate_operation", return_value=document), mock.patch.object(
            LAUNCHER, "read_secret"
        ) as read_secret:
            with self.assertRaisesRegex(LAUNCHER.PreflightBlocked, "preflight_not_ready"):
                LAUNCHER.execute(calculated)
        read_secret.assert_not_called()
        self.assertEqual(set(Path("/tmp").glob(f"{LAUNCHER.EVIDENCE_PREFIX}*")), before)

    def test_hash_mismatch_rejects_before_evidence_or_secrets(self) -> None:
        calculated = LAUNCHER.bundle_hash()
        document = ready_definition("a" * 64)
        with mock.patch.object(LAUNCHER, "validate_operation", return_value=document), mock.patch.object(
            LAUNCHER, "read_secret"
        ) as read_secret:
            with self.assertRaisesRegex(LAUNCHER.PreflightBlocked, "bundle_hash_mismatch"):
                LAUNCHER.execute("a" * 64)
        self.assertNotEqual(calculated, "a" * 64)
        read_secret.assert_not_called()


class ExecutionTests(unittest.TestCase):
    @staticmethod
    def fake_secret(_project: str, _config: str, name: str) -> bytearray:
        return bytearray(f"protected-{name}".encode())

    def test_offline_success_is_protected_and_sanitized(self) -> None:
        calculated = LAUNCHER.bundle_hash()
        document = ready_definition(calculated)
        with mock.patch.object(LAUNCHER, "validate_operation", return_value=document), mock.patch.object(
            LAUNCHER, "read_secret", side_effect=self.fake_secret
        ), mock.patch.object(
            LAUNCHER, "drain_process", return_value=(0, b"sanitized stdout\n", b"", False)
        ):
            status, root = LAUNCHER.execute(calculated)
        try:
            self.assertEqual(status, 0)
            self.assertEqual(stat.S_IMODE(root.stat().st_mode), 0o700)
            self.assertFalse((root / "protected-extra-vars.json").exists())
            self.assertFalse((root / "ansible-local").exists())
            for name in (
                "bundle-files.sha256", "bundle.sha256", "ansible.stdout",
                "ansible.stderr", "ansible.status", "terminal-result.json",
            ):
                self.assertEqual(stat.S_IMODE((root / name).stat().st_mode), 0o600)
            terminal = json.loads((root / "terminal-result.json").read_text())
            self.assertEqual(terminal["result"], "passed")
            self.assertFalse(terminal["repository_initialization_attempted"])
            self.assertTrue(terminal["controller_secret_file_absent"])
            self.assertTrue(terminal["ansible_local_temp_absent"])
            rendered = "".join(
                path.read_text(errors="replace") for path in root.iterdir() if path.is_file()
            )
            self.assertNotIn("protected-NAUTOBOT", rendered)
        finally:
            remove_evidence(root)

    def test_nonzero_ansible_status_is_blocked(self) -> None:
        calculated = LAUNCHER.bundle_hash()
        with mock.patch.object(
            LAUNCHER, "validate_operation", return_value=ready_definition(calculated)
        ), mock.patch.object(
            LAUNCHER, "read_secret", side_effect=self.fake_secret
        ), mock.patch.object(
            LAUNCHER, "drain_process", return_value=(2, b"sanitized failure\n", b"", False)
        ):
            status, root = LAUNCHER.execute(calculated)
        try:
            self.assertEqual(status, 69)
            terminal = json.loads((root / "terminal-result.json").read_text())
            self.assertEqual(terminal["result"], "blocked")
            self.assertEqual(terminal["ansible_exit_status"], 2)
            self.assertEqual(terminal["error_class"], "ansible_exit_nonzero")
        finally:
            remove_evidence(root)

    def test_secret_in_ansible_output_fails_closed(self) -> None:
        calculated = LAUNCHER.bundle_hash()
        leaked = b"protected-NAUTOBOT_RESTIC_REPOSITORY_PASSWORD"
        with mock.patch.object(
            LAUNCHER, "validate_operation", return_value=ready_definition(calculated)
        ), mock.patch.object(
            LAUNCHER, "read_secret", side_effect=self.fake_secret
        ), mock.patch.object(
            LAUNCHER, "drain_process", return_value=(0, leaked, b"", False)
        ):
            status, root = LAUNCHER.execute(calculated)
        try:
            self.assertEqual(status, 69)
            terminal = json.loads((root / "terminal-result.json").read_text())
            self.assertEqual(terminal["error_class"], "secret_value_in_ansible_output")
            self.assertFalse((root / "ansible.stdout").exists())
        finally:
            remove_evidence(root)

    def test_invalid_secret_is_zeroed_and_rejected(self) -> None:
        with self.assertRaisesRegex(LAUNCHER.PreflightBlocked, "invalid_secret_value"):
            LAUNCHER.read_secret(
                "homelab-dev", "prd_restic", "NAME",
                runner=lambda _argv: (0, bytearray(), False),
            )

    def test_oversized_secret_is_rejected(self) -> None:
        oversized = bytearray(b"x" * (LAUNCHER.MAX_SECRET_BYTES + 1))
        with self.assertRaisesRegex(LAUNCHER.PreflightBlocked, "invalid_secret_value"):
            LAUNCHER.read_secret(
                "homelab-dev", "prd_restic", "NAME",
                runner=lambda _argv: (0, oversized, True),
            )
        self.assertEqual(set(oversized), {0})

    def test_controller_cleanup_failure_is_blocked(self) -> None:
        with tempfile.TemporaryDirectory(prefix=LAUNCHER.EVIDENCE_PREFIX, dir="/tmp") as temporary:
            root = Path(temporary)
            root.chmod(0o700)
            root_fd = LAUNCHER.validate_evidence_root(root)
            with mock.patch.object(LAUNCHER, "read_secret", side_effect=self.fake_secret), mock.patch.object(
                LAUNCHER, "drain_process", return_value=(0, b"sanitized\n", b"", False)
            ), mock.patch.object(Path, "unlink", side_effect=OSError("fixture")):
                with self.assertRaisesRegex(
                    LAUNCHER.PreflightBlocked, "controller_secret_cleanup_failed"
                ):
                    LAUNCHER.run_preflight(root, root_fd)
            os.close(root_fd)


class CliTests(unittest.TestCase):
    def test_current_cli_rejects_unready_before_external_access(self) -> None:
        before = set(Path("/tmp").glob(f"{LAUNCHER.EVIDENCE_PREFIX}*"))
        with tempfile.TemporaryDirectory() as temporary:
            marker = Path(temporary) / "doppler-called"
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
            self.assertEqual(result.returncode, 69)
            self.assertIn("active_operation_mismatch", result.stderr.decode())
            self.assertFalse(marker.exists())
        self.assertEqual(set(Path("/tmp").glob(f"{LAUNCHER.EVIDENCE_PREFIX}*")), before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
