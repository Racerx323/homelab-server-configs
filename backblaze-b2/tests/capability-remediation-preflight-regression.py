#!/usr/bin/env python3
"""Regression tests for the read-only B2 capability preflight."""

from __future__ import annotations

import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from typing import Any
from unittest import mock

import yaml

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
CLIENT_PATH = ROOT / "backblaze-b2/scripts/capability_remediation_preflight.py"
LAUNCHER_PATH = ROOT / "backblaze-b2/scripts/run-capability-remediation-preflight.sh"
SPEC = importlib.util.spec_from_file_location("b2_preflight", CLIENT_PATH)
assert SPEC is not None and SPEC.loader is not None
CLIENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CLIENT)


class FakeResponse:
    def __init__(self, url: str, payload: dict[str, Any]):
        self.url = url
        self.payload = json.dumps(payload).encode("utf-8")

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, *args: Any) -> None:
        return None

    def geturl(self) -> str:
        return self.url

    def read(self, size: int) -> bytes:
        return self.payload[:size]


class FakeOpener:
    def __init__(self, responses: list[dict[str, Any]]):
        self.responses = list(responses)
        self.requests: list[dict[str, Any]] = []

    def open(self, request: Any, timeout: int) -> FakeResponse:
        if not self.responses:
            raise AssertionError("unexpected HTTP request")
        body = None if request.data is None else json.loads(request.data)
        self.requests.append(
            {
                "url": request.full_url,
                "method": request.get_method(),
                "body": body,
                "authorization": request.get_header("Authorization"),
                "timeout": timeout,
            }
        )
        return FakeResponse(request.full_url, self.responses.pop(0))


def provider_responses() -> list[dict[str, Any]]:
    rejected_capabilities = sorted(
        CLIENT.REQUIRED_FILE_CAPABILITIES | CLIENT.PROHIBITED_RESIDUE_CAPABILITIES
    )
    return [
        {
            "accountId": "account-under-test",
            "authorizationToken": "token-under-test",
            "apiInfo": {
                "storageApi": {
                    "apiUrl": "https://api123.backblazeb2.com",
                    "s3ApiUrl": CLIENT.EXPECTED_S3_URL,
                    "capabilities": sorted(CLIENT.REQUIRED_AUTH_CAPABILITIES),
                }
            },
        },
        {
            "keys": [
                {
                    "keyName": CLIENT.REJECTED_KEY_NAME,
                    "capabilities": rejected_capabilities,
                }
            ],
            "nextApplicationKeyId": None,
        },
        {
            "buckets": [
                {
                    "bucketName": CLIENT.EXPECTED_BUCKET_NAME,
                    "bucketId": CLIENT.EXPECTED_BUCKET_ID,
                    "bucketType": "allPrivate",
                }
            ]
        },
        {"files": [], "nextFileName": None},
    ]


class DopplerCredentialTests(unittest.TestCase):
    def test_admin_secret_commands_are_exact_and_value_free(self) -> None:
        for name in (
            "BACKBLAZE_B2_MASTER_APPLICATION_KEY_ID",
            "BACKBLAZE_B2_MASTER_APPLICATION_KEY",
        ):
            argv = CLIENT.doppler_secret_argv(name)
            self.assertEqual(
                argv,
                (
                    "doppler",
                    "--no-check-version",
                    "--no-read-env",
                    "--silent",
                    "secrets",
                    "get",
                    name,
                    "--project",
                    "homelab-dev",
                    "--config",
                    "prd_b2_admin",
                    "--plain",
                ),
            )
            self.assertIn("--no-read-env", argv)
            self.assertIn("--silent", argv)

    def test_admin_secret_is_bounded_and_trimmed_in_memory(self) -> None:
        with mock.patch.object(
            CLIENT,
            "run_bounded_doppler",
            return_value=bytearray(b"fixture-secret\n"),
        ):
            value = CLIENT.read_admin_secret(CLIENT.ADMIN_KEY_ID_NAME)
        self.assertEqual(value, bytearray(b"fixture-secret"))

    def test_admin_secret_rejects_embedded_newline(self) -> None:
        with mock.patch.object(
            CLIENT,
            "run_bounded_doppler",
            return_value=bytearray(b"fixture\nsecret"),
        ):
            with self.assertRaisesRegex(
                CLIENT.PreflightBlocked,
                "invalid_admin_secret_value",
            ):
                CLIENT.read_admin_secret(CLIENT.ADMIN_KEY_VALUE_NAME)

    def test_minimal_environment_excludes_doppler_token(self) -> None:
        with mock.patch.dict(
            os.environ,
            {"HOME": "/tmp/home", "PATH": "/bin", "DOPPLER_TOKEN": "fixture"},
            clear=True,
        ):
            self.assertEqual(
                CLIENT.minimal_environment(),
                {"HOME": "/tmp/home", "PATH": "/bin"},
            )


class ApiTests(unittest.TestCase):
    def test_full_preflight_uses_only_exact_read_calls(self) -> None:
        opener = FakeOpener(provider_responses())
        names = CLIENT.CANONICAL_SECRET_NAMES | {"UNRELATED_NAME"}
        checks = CLIENT.perform_preflight(
            b"generated-key-id",
            b"generated-application-key",
            opener=opener,
            doppler_names=names,
        )
        self.assertTrue(all(checks.values()))
        operation = yaml.safe_load(
            (ROOT / "backblaze-b2/manifests/operation.yaml").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(set(checks), set(operation["assertions"]["require"]))
        self.assertEqual(
            [(item["method"], item["url"]) for item in opener.requests],
            [
                ("GET", CLIENT.AUTH_URL),
                ("POST", "https://api123.backblazeb2.com/b2api/v4/b2_list_keys"),
                ("POST", "https://api123.backblazeb2.com/b2api/v4/b2_list_buckets"),
                ("POST", "https://api123.backblazeb2.com/b2api/v4/b2_list_file_names"),
            ],
        )
        self.assertEqual(opener.requests[1]["body"], {"accountId": "account-under-test"})
        self.assertEqual(
            opener.requests[3]["body"],
            {"bucketId": CLIENT.EXPECTED_BUCKET_ID, "maxFileCount": 1},
        )
        self.assertFalse(
            any("create" in item["url"] or "delete" in item["url"] for item in opener.requests)
        )

    def test_candidate_name_collision_blocks(self) -> None:
        opener = FakeOpener(provider_responses())
        names = CLIENT.CANONICAL_SECRET_NAMES | {next(iter(CLIENT.CANDIDATE_SECRET_NAMES))}
        with self.assertRaisesRegex(CLIENT.PreflightBlocked, "candidate_doppler_name_collision"):
            CLIENT.perform_preflight(b"id", b"value", opener=opener, doppler_names=names)

    def test_missing_list_files_authority_blocks(self) -> None:
        responses = provider_responses()
        responses[0]["apiInfo"]["storageApi"]["capabilities"].remove("listFiles")
        responses[0]["apiInfo"]["storageApi"]["capabilities"].append("unrelatedCapability")
        with self.assertRaisesRegex(CLIENT.PreflightBlocked, "insufficient_management_authority") as context:
            CLIENT.perform_preflight(
                b"id",
                b"value",
                opener=FakeOpener(responses),
                doppler_names=CLIENT.CANONICAL_SECRET_NAMES,
            )
        self.assertEqual(
            context.exception.observations["missing_required_management_capabilities"],
            ["listFiles"],
        )
        self.assertNotIn(
            "unrelatedCapability",
            context.exception.observations["present_required_management_capabilities"],
        )

    def test_key_listing_pagination_is_bounded_and_filtered(self) -> None:
        responses = provider_responses()
        first_key_page = {
            "keys": [{"keyName": "unrelated-key", "capabilities": []}],
            "nextApplicationKeyId": "opaque-next-id",
        }
        responses.insert(1, first_key_page)
        opener = FakeOpener(responses)
        checks = CLIENT.perform_preflight(
            b"id",
            b"value",
            opener=opener,
            doppler_names=CLIENT.CANONICAL_SECRET_NAMES,
        )
        self.assertTrue(all(checks.values()))
        self.assertEqual(
            opener.requests[2]["body"],
            {"accountId": "account-under-test", "startApplicationKeyId": "opaque-next-id"},
        )

    def test_url_allowlists_reject_lookalikes_and_paths(self) -> None:
        invalid = [
            "http://api123.backblazeb2.com",
            "https://api123.backblazeb2.com.evil.example",
            "https://user@api123.backblazeb2.com",
            "https://api123.backblazeb2.com/unexpected",
            "https://api123.backblazeb2.com?query=yes",
        ]
        for url in invalid:
            with self.subTest(url=url):
                with self.assertRaises(CLIENT.PreflightBlocked):
                    CLIENT.validate_api_base(url)

    def test_redirected_response_is_rejected(self) -> None:
        class RedirectedOpener:
            def open(self, request: Any, timeout: int) -> FakeResponse:
                return FakeResponse("https://api123.backblazeb2.com/redirected", {})

        with self.assertRaisesRegex(CLIENT.PreflightBlocked, "redirect_rejected"):
            CLIENT.request_json(
                RedirectedOpener(),
                "GET",
                CLIENT.AUTH_URL,
                "Basic generated",
            )

    def test_oversized_provider_response_is_rejected(self) -> None:
        class OversizedResponse(FakeResponse):
            def __init__(self, url: str):
                self.url = url
                self.payload = b"x" * (CLIENT.MAX_RESPONSE_BYTES + 1)

        class OversizedOpener:
            def open(self, request: Any, timeout: int) -> OversizedResponse:
                return OversizedResponse(request.full_url)

        with self.assertRaisesRegex(CLIENT.PreflightBlocked, "provider_response_too_large"):
            CLIENT.request_json(
                OversizedOpener(),
                "GET",
                CLIENT.AUTH_URL,
                "Basic generated",
            )

    def test_doppler_command_is_name_only_and_explicitly_scoped(self) -> None:
        self.assertEqual(
            CLIENT.DOPPLER_NAMES_ARGV,
            (
                "doppler",
                "--no-check-version",
                "--no-read-env",
                "--silent",
                "secrets",
                "get",
                "--project",
                "homelab-dev",
                "--config",
                "prd_b2",
                "--only-names",
                "--json",
            ),
        )


class EvidenceAndLauncherTests(unittest.TestCase):
    def test_evidence_root_is_restricted_to_protected_tmp_namespace(self) -> None:
        with tempfile.TemporaryDirectory(dir="/tmp") as temporary:
            root = Path(temporary)
            root.chmod(0o700)
            with self.assertRaisesRegex(CLIENT.PreflightBlocked, "invalid_evidence_root"):
                CLIENT.validate_evidence_root(root)

    def test_evidence_is_exclusive_mode_0600_and_sanitized(self) -> None:
        with tempfile.TemporaryDirectory(prefix="backblaze-b2-capability-preflight.", dir="/tmp") as temporary:
            root = Path(temporary)
            root.chmod(0o700)
            root_fd = CLIENT.validate_evidence_root(root)
            try:
                CLIENT.write_evidence(root_fd, "a" * 64, "blocked", {}, "provider_http_401")
            finally:
                os.close(root_fd)
            evidence = root / "result.json"
            self.assertEqual(stat.S_IMODE(evidence.stat().st_mode), 0o600)
            document = json.loads(evidence.read_text(encoding="utf-8"))
            self.assertEqual(document["bundle_sha256"], "a" * 64)
            self.assertEqual(document["error_class"], "provider_http_401")
            self.assertFalse(document["secrets_recorded"])
            with self.assertRaises(FileExistsError):
                root_fd = CLIENT.validate_evidence_root(root)
                try:
                    CLIENT.write_evidence(root_fd, "a" * 64, "passed", {})
                finally:
                    os.close(root_fd)

    def test_launcher_preserves_secret_and_evidence_boundaries(self) -> None:
        source = LAUNCHER_PATH.read_text(encoding="utf-8")
        required = [
            "set +x",
            "umask 077",
            "ulimit -c 0",
            "mktemp -d /tmp/backblaze-b2-capability-preflight.XXXXXX",
            "chmod 0700",
            "return \"${client_status}\"",
        ]
        for fragment in required:
            self.assertIn(fragment, source)
        for prohibited in (
            "mkfifo",
            "/dev/tty",
            "key_id_fifo",
            "application_key_fifo",
            "--key-id",
            "--application-key",
            "doppler secrets get",
        ):
            self.assertNotIn(prohibited, source)

    def test_successor_is_unready_and_definition_only(self) -> None:
        operation = yaml.safe_load(
            (ROOT / "backblaze-b2/manifests/operation.yaml").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(
            operation["operation"]["id"],
            "backblaze-b2-capability-remediation-preflight-v2",
        )
        self.assertEqual(operation["operation"]["state"], "definition")
        self.assertFalse(operation["operation"]["authorization_ready"])
        self.assertFalse(operation["implementation"]["live_execution_enabled"])
        self.assertIsNone(operation["authorization"]["command"])
        self.assertFalse(operation["authorization"]["mutation_authorized"])
        self.assertGreater(len(operation["authorization"]["blockers"]), 0)

    def test_launcher_rejects_unready_or_invalid_hash_execution(self) -> None:
        evidence_before = set(Path("/tmp").glob("backblaze-b2-capability-preflight.*"))
        result = subprocess.run(
            ["/bin/bash", str(LAUNCHER_PATH), "execute", "a" * 64],
            cwd=ROOT,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        operation = yaml.safe_load(
            (ROOT / "backblaze-b2/manifests/operation.yaml").read_text(encoding="utf-8")
        )
        is_ready = (
            operation["operation"]["authorization_ready"] is True
            and operation["implementation"]["live_execution_enabled"] is True
            and operation["authorization"]["blockers"] == []
        )
        if is_ready:
            self.assertEqual(result.returncode, 66)
            self.assertIn("bundle hash does not match", result.stderr)
        else:
            self.assertEqual(result.returncode, 69)
            self.assertIn("operation is not authorization-ready", result.stderr)
        evidence_after = set(Path("/tmp").glob("backblaze-b2-capability-preflight.*"))
        self.assertEqual(evidence_after, evidence_before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
