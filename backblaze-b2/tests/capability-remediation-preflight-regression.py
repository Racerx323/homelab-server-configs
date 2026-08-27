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
import threading
import unittest
import urllib.error
from pathlib import Path
from typing import Any

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


class FifoTests(unittest.TestCase):
    def test_fifo_is_mode_checked_consumed_and_unlinked(self) -> None:
        with tempfile.TemporaryDirectory(prefix="backblaze-b2-capability-preflight.", dir="/tmp") as temporary:
            root = Path(temporary)
            root.chmod(0o700)
            fifo = root / "credential.fifo"
            os.mkfifo(fifo, 0o600)
            root_fd = CLIENT.validate_evidence_root(root)
            value = "generated-credential-value"

            def writer() -> None:
                with fifo.open("w", encoding="utf-8") as stream:
                    stream.write(value)

            thread = threading.Thread(target=writer, daemon=True)
            thread.start()
            try:
                self.assertEqual(CLIENT.read_owned_fifo(root_fd, fifo.name), value)
            finally:
                os.close(root_fd)
            thread.join(timeout=2)
            self.assertFalse(thread.is_alive())
            self.assertFalse(fifo.exists())

    def test_fifo_rejects_wrong_mode_before_open(self) -> None:
        with tempfile.TemporaryDirectory(prefix="backblaze-b2-capability-preflight.", dir="/tmp") as temporary:
            root = Path(temporary)
            root.chmod(0o700)
            fifo = root / "credential.fifo"
            os.mkfifo(fifo, 0o644)
            fifo.chmod(0o644)
            root_fd = CLIENT.validate_evidence_root(root)
            try:
                with self.assertRaisesRegex(CLIENT.PreflightBlocked, "unsafe_credential_fifo"):
                    CLIENT.read_owned_fifo(root_fd, fifo.name)
            finally:
                os.close(root_fd)

    def test_fifo_rejects_symlink(self) -> None:
        with tempfile.TemporaryDirectory(prefix="backblaze-b2-capability-preflight.", dir="/tmp") as temporary:
            root = Path(temporary)
            root.chmod(0o700)
            target = root / "target"
            target.write_text("not-a-fifo", encoding="utf-8")
            link = root / "credential.fifo"
            link.symlink_to(target.name)
            root_fd = CLIENT.validate_evidence_root(root)
            try:
                with self.assertRaisesRegex(CLIENT.PreflightBlocked, "invalid_credential_fifo"):
                    CLIENT.read_owned_fifo(root_fd, link.name)
            finally:
                os.close(root_fd)


class ApiTests(unittest.TestCase):
    def test_full_preflight_uses_only_exact_read_calls(self) -> None:
        opener = FakeOpener(provider_responses())
        names = CLIENT.CANONICAL_SECRET_NAMES | {"UNRELATED_NAME"}
        checks = CLIENT.perform_preflight(
            "generated-key-id",
            "generated-application-key",
            opener=opener,
            doppler_names=names,
        )
        self.assertTrue(all(checks.values()))
        self.assertEqual(
            [(item["method"], item["url"]) for item in opener.requests],
            [
                ("GET", CLIENT.AUTH_URL),
                ("POST", "https://api123.backblazeb2.com/b2api/v4/b2_list_keys"),
                ("POST", "https://api123.backblazeb2.com/b2api/v4/b2_list_buckets"),
                ("POST", "https://api123.backblazeb2.com/b2api/v3/b2_list_file_names"),
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
            CLIENT.perform_preflight("id", "value", opener=opener, doppler_names=names)

    def test_missing_list_files_authority_blocks(self) -> None:
        responses = provider_responses()
        responses[0]["apiInfo"]["storageApi"]["capabilities"].remove("listFiles")
        with self.assertRaisesRegex(CLIENT.PreflightBlocked, "insufficient_management_authority"):
            CLIENT.perform_preflight(
                "id",
                "value",
                opener=FakeOpener(responses),
                doppler_names=CLIENT.CANONICAL_SECRET_NAMES,
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
            "id",
            "value",
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
            CLIENT.DOPPLER_ARGV,
            (
                "doppler",
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
            "mktemp -d /tmp/backblaze-b2-capability-preflight.XXXXXX",
            "chmod 0700",
            "mkfifo -m 0600",
            "[[ -p ${key_id_fifo} && ! -L ${key_id_fifo} ]]",
            "trap cleanup_writers EXIT",
            "trap 'cleanup_writers; exit 130' INT",
            "trap 'cleanup_writers; exit 143' TERM",
            "unset key_id application_key",
            "return \"${client_status}\"",
        ]
        for fragment in required:
            self.assertIn(fragment, source)
        self.assertNotIn("--key-id \"${key_id}\"", source)
        self.assertNotIn("--application-key \"${application_key}\"", source)

    def test_launcher_rejects_live_execution_while_unready(self) -> None:
        result = subprocess.run(
            ["/bin/bash", str(LAUNCHER_PATH), "execute", "a" * 64],
            cwd=ROOT,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        self.assertEqual(result.returncode, 69)
        self.assertIn("operation is not authorization-ready", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
