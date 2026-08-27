#!/usr/bin/env python3
"""Offline regressions for replacement-key creation and protected storage."""

from __future__ import annotations

import importlib.util
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from typing import Any
from unittest import mock

import yaml

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "backblaze-b2/scripts"
sys.path.insert(0, str(SCRIPT_DIR))


def load_module(name: str, path: Path) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CLIENT = load_module("replacement_creation", SCRIPT_DIR / "replacement_key_creation.py")
WRITER = load_module(
    "candidate_writer", SCRIPT_DIR / "protected_doppler_candidate_write.py"
)
PREFLIGHT = CLIENT.preflight
LAUNCHER = SCRIPT_DIR / "run-replacement-key-creation.sh"
OPERATION = ROOT / "backblaze-b2/manifests/operation.yaml"


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


def authorization_response() -> dict[str, Any]:
    return {
        "accountId": "account-under-test",
        "authorizationToken": "token-under-test",
        "apiInfo": {
            "storageApi": {
                "apiUrl": "https://api123.backblazeb2.com",
                "s3ApiUrl": PREFLIGHT.EXPECTED_S3_URL,
                "allowed": {
                    "capabilities": sorted(PREFLIGHT.REQUIRED_AUTH_CAPABILITIES),
                },
            }
        },
    }


def rejected_key() -> dict[str, Any]:
    return {
        "applicationKeyId": "rejected-id-under-test",
        "keyName": PREFLIGHT.REJECTED_KEY_NAME,
        "capabilities": sorted(
            PREFLIGHT.REQUIRED_FILE_CAPABILITIES
            | PREFLIGHT.PROHIBITED_RESIDUE_CAPABILITIES
        ),
    }


def replacement_metadata() -> dict[str, Any]:
    return {
        "accountId": "account-under-test",
        "applicationKeyId": "candidate-id-under-test",
        "bucketIds": [CLIENT.EXPECTED_BUCKET_ID],
        "capabilities": sorted(CLIENT.EXPECTED_CAPABILITIES),
        "expirationTimestamp": None,
        "keyName": CLIENT.REPLACEMENT_KEY_NAME,
        "namePrefix": None,
        "options": ["s3"],
    }


def successful_responses() -> list[dict[str, Any]]:
    create = replacement_metadata()
    create["applicationKey"] = "candidate-value-under-test"
    return [
        authorization_response(),
        {"keys": [rejected_key()], "nextApplicationKeyId": None},
        {
            "buckets": [
                {
                    "bucketName": PREFLIGHT.EXPECTED_BUCKET_NAME,
                    "bucketId": CLIENT.EXPECTED_BUCKET_ID,
                    "bucketType": "allPrivate",
                }
            ]
        },
        {"files": [], "nextFileName": None},
        authorization_response(),
        {"keys": [rejected_key()], "nextApplicationKeyId": None},
        create,
        {
            "keys": [rejected_key(), replacement_metadata()],
            "nextApplicationKeyId": None,
        },
    ]


class ProviderClientTests(unittest.TestCase):
    def test_exact_single_create_and_sanitized_secret_sink(self) -> None:
        opener = FakeOpener(successful_responses())
        delivered: list[tuple[bytes, bytes]] = []

        def sink(key_id: bytearray, key_value: bytearray) -> None:
            delivered.append((bytes(key_id), bytes(key_value)))

        checks = CLIENT.perform_creation(
            bytearray(b"admin-id"),
            bytearray(b"admin-value"),
            sink,
            opener=opener,
            doppler_names=PREFLIGHT.CANONICAL_SECRET_NAMES,
        )
        create_requests = [
            request for request in opener.requests if request["url"].endswith("/b2_create_key")
        ]
        self.assertEqual(len(create_requests), 1)
        self.assertEqual(
            create_requests[0]["body"],
            {
                "accountId": "account-under-test",
                "capabilities": sorted(CLIENT.EXPECTED_CAPABILITIES),
                "keyName": CLIENT.REPLACEMENT_KEY_NAME,
                "bucketIds": [CLIENT.EXPECTED_BUCKET_ID],
            },
        )
        self.assertNotIn("validDurationInSeconds", create_requests[0]["body"])
        self.assertEqual(
            delivered,
            [(b"candidate-id-under-test", b"candidate-value-under-test")],
        )
        self.assertTrue(checks["provider_create_attempted"])
        self.assertTrue(checks["exact_provider_key_metadata_readback"])
        self.assertTrue(checks["no_object_mutation_or_consumer_contact"])
        self.assertNotIn("no_mutation_endpoint_attempted", checks)

    def test_precreate_failure_never_calls_create_or_sink(self) -> None:
        responses = successful_responses()
        responses[1] = {
            "keys": [rejected_key(), replacement_metadata()],
            "nextApplicationKeyId": None,
        }
        opener = FakeOpener(responses)
        called = False

        def sink(key_id: bytearray, key_value: bytearray) -> None:
            nonlocal called
            called = True

        with self.assertRaisesRegex(CLIENT.CreationBlocked, "replacement_key_already_exists"):
            CLIENT.perform_creation(
                bytearray(b"admin-id"),
                bytearray(b"admin-value"),
                sink,
                opener=opener,
                doppler_names=PREFLIGHT.CANONICAL_SECRET_NAMES,
            )
        self.assertFalse(called)
        self.assertFalse(any("create_key" in item["url"] for item in opener.requests))

    def test_postcreate_metadata_failure_is_manual_intervention_boundary(self) -> None:
        responses = successful_responses()
        responses[6]["capabilities"].append("writeBuckets")
        observations: dict[str, Any] = {}
        with self.assertRaises(CLIENT.CreationBlocked) as context:
            CLIENT.perform_creation(
                bytearray(b"admin-id"),
                bytearray(b"admin-value"),
                lambda _key_id, _key_value: None,
                opener=FakeOpener(responses),
                doppler_names=PREFLIGHT.CANONICAL_SECRET_NAMES,
                observations=observations,
            )
        self.assertTrue(context.exception.mutation_attempted)
        self.assertTrue(observations["provider_create_attempted"])
        self.assertTrue(observations["provider_create_response_received"])

    def test_rejected_key_metadata_drift_blocks_after_create(self) -> None:
        responses = successful_responses()
        responses[7]["keys"][0]["capabilities"].append("newCapability")
        observations: dict[str, Any] = {}
        with self.assertRaisesRegex(
            CLIENT.CreationBlocked,
            "rejected_key_metadata_changed",
        ) as context:
            CLIENT.perform_creation(
                bytearray(b"admin-id"),
                bytearray(b"admin-value"),
                lambda _key_id, _key_value: None,
                opener=FakeOpener(responses),
                doppler_names=PREFLIGHT.CANONICAL_SECRET_NAMES,
                observations=observations,
            )
        self.assertTrue(context.exception.mutation_attempted)
        self.assertTrue(observations["provider_create_response_received"])

    def test_metadata_validation_checks_every_forward_and_readback_gate(self) -> None:
        mutations = {
            "keyName": "wrong",
            "bucketIds": ["wrong"],
            "namePrefix": "unexpected",
            "capabilities": ["listFiles"],
            "expirationTimestamp": 1,
            "options": [],
        }
        for field, value in mutations.items():
            with self.subTest(field=field):
                item = replacement_metadata()
                item[field] = value
                with self.assertRaises(CLIENT.CreationBlocked):
                    CLIENT.validate_replacement_metadata(item)

    def test_missing_fifo_reader_fails_within_bounded_connect_window(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="backblaze-b2-replacement-key-creation.", dir="/tmp"
        ) as temporary:
            root = Path(temporary)
            root.chmod(0o700)
            fifo = root / "unread.fifo"
            os.mkfifo(fifo, 0o600)
            root_fd = CLIENT.validate_root(root)
            started = time.monotonic()
            try:
                with mock.patch.object(CLIENT, "FIFO_CONNECT_TIMEOUT_SECONDS", 0.05):
                    with self.assertRaisesRegex(
                        CLIENT.CreationBlocked,
                        "secret_delivery_failed",
                    ):
                        CLIENT.write_owned_fifo(root_fd, fifo.name, bytearray(b"secret"))
            finally:
                os.close(root_fd)
            self.assertLess(time.monotonic() - started, 1)


class CandidateWriterTests(unittest.TestCase):
    def make_root(self) -> tuple[tempfile.TemporaryDirectory[str], Path, int]:
        temporary = tempfile.TemporaryDirectory(
            prefix="backblaze-b2-replacement-key-creation.", dir="/tmp"
        )
        root = Path(temporary.name)
        root.chmod(0o700)
        return temporary, root, WRITER.validate_root(root)

    @staticmethod
    def make_fifo(root: Path, name: str, value: bytes) -> threading.Thread:
        fifo = root / name
        os.mkfifo(fifo, 0o600)

        def feed() -> None:
            with fifo.open("wb") as stream:
                stream.write(value)

        thread = threading.Thread(target=feed, daemon=True)
        thread.start()
        return thread

    def test_exact_candidate_stdin_writes_and_name_only_readback(self) -> None:
        temporary, root, root_fd = self.make_root()
        calls: list[tuple[tuple[str, ...], bytes | None]] = []
        threads = [
            self.make_fifo(root, "id.fifo", b"candidate-id"),
            self.make_fifo(root, "value.fifo", b"candidate-value"),
        ]

        def runner(argv: tuple[str, ...], value: bytearray | None) -> bytes:
            calls.append((argv, None if value is None else bytes(value)))
            if "--only-names" in argv:
                names = WRITER.CANDIDATE_NAMES | WRITER.CANONICAL_NAMES
                return json.dumps({name: {} for name in names}).encode()
            return b""

        try:
            checks = WRITER.store_from_fifos(root_fd, "id.fifo", "value.fifo", runner)
        finally:
            os.close(root_fd)
            temporary.cleanup()
        for thread in threads:
            thread.join(timeout=2)
        self.assertEqual(
            checks,
            {
                "candidate_key_id_written": True,
                "candidate_key_value_written": True,
                "exact_candidate_names_present": True,
                "canonical_names_still_present": True,
                "value_readback_performed": False,
            },
        )
        self.assertEqual(calls[0][1], b"candidate-id")
        self.assertEqual(calls[1][1], b"candidate-value")
        self.assertIsNone(calls[2][1])
        rendered = " ".join(part for argv, _ in calls for part in argv)
        self.assertNotIn("candidate-id", rendered)
        self.assertNotIn("candidate-value", rendered)
        self.assertNotIn("NAUTOBOT_RESTIC_B2_APPLICATION_KEY ", rendered)

    def test_partial_write_requires_manual_intervention(self) -> None:
        temporary, root, root_fd = self.make_root()
        threads = [
            self.make_fifo(root, "id.fifo", b"candidate-id"),
            self.make_fifo(root, "value.fifo", b"candidate-value"),
        ]
        count = 0

        def runner(argv: tuple[str, ...], value: bytearray | None) -> bytes:
            nonlocal count
            count += 1
            if count == 2:
                raise WRITER.ProtectedWriteBlocked("doppler_command_failed")
            return b""

        try:
            with self.assertRaisesRegex(
                WRITER.ProtectedWriteBlocked,
                "partial_candidate_write_manual_intervention",
            ):
                WRITER.store_from_fifos(root_fd, "id.fifo", "value.fifo", runner)
        finally:
            os.close(root_fd)
            temporary.cleanup()
        for thread in threads:
            thread.join(timeout=2)

    def test_writer_evidence_is_exclusive_mode_0600_and_sanitized(self) -> None:
        temporary, root, root_fd = self.make_root()
        try:
            WRITER.write_evidence(
                root_fd,
                "a" * 64,
                "blocked",
                {"candidate_key_id_written": True},
                "partial_candidate_write_manual_intervention",
            )
        finally:
            os.close(root_fd)
        evidence = root / "candidate-write-result.json"
        rendered = evidence.read_text(encoding="utf-8")
        self.assertEqual(stat.S_IMODE(evidence.stat().st_mode), 0o600)
        self.assertFalse(json.loads(rendered)["candidate_values_or_identifiers_retained"])
        self.assertNotIn("candidate-id", rendered)
        self.assertNotIn("candidate-value", rendered)
        temporary.cleanup()


class EvidenceTests(unittest.TestCase):
    def test_provider_evidence_is_exclusive_mode_0600_and_sanitized(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="backblaze-b2-replacement-key-creation.", dir="/tmp"
        ) as temporary:
            root = Path(temporary)
            root.chmod(0o700)
            root_fd = CLIENT.validate_root(root)
            try:
                CLIENT.write_evidence(
                    root_fd,
                    "a" * 64,
                    "manual_intervention",
                    {
                        "provider_create_attempted": True,
                        "provider_create_response_received": True,
                    },
                    "secret_delivery_failed",
                    True,
                )
            finally:
                os.close(root_fd)
            evidence = root / "provider-result.json"
            rendered = evidence.read_text(encoding="utf-8")
            self.assertEqual(stat.S_IMODE(evidence.stat().st_mode), 0o600)
            document = json.loads(rendered)
            self.assertTrue(document["provider_create_attempted"])
            self.assertFalse(document["automatic_retry_performed"])
            self.assertFalse(document["automatic_cleanup_performed"])
            self.assertFalse(document["provider_or_doppler_secret_values_retained"])
            self.assertNotIn("candidate-id", rendered)
            self.assertNotIn("candidate-value", rendered)


class LauncherAndContractTests(unittest.TestCase):
    def test_consumed_operation_is_retired(self) -> None:
        operation = yaml.safe_load(OPERATION.read_text(encoding="utf-8"))
        self.assertEqual(
            operation,
            {"schema_version": 1, "operation": {"state": "clean", "authorization_ready": False}},
        )

    def test_invalid_hash_rejects_before_evidence_or_external_command(self) -> None:
        before = set(Path("/tmp").glob("backblaze-b2-replacement-key-creation.*"))
        with tempfile.TemporaryDirectory() as temporary:
            marker = Path(temporary) / "external-command-called"
            fake = Path(temporary) / "doppler"
            fake.write_text(f"#!/bin/sh\ntouch '{marker}'\nexit 99\n", encoding="utf-8")
            fake.chmod(0o700)
            environment = os.environ.copy()
            environment["PATH"] = f"{temporary}:{environment['PATH']}"
            result = subprocess.run(
                ["/bin/bash", str(LAUNCHER), "execute", "a" * 64],
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            self.assertEqual(result.returncode, 69)
            self.assertIn("active operation does not belong", result.stderr)
            self.assertFalse(marker.exists())
        after = set(Path("/tmp").glob("backblaze-b2-replacement-key-creation.*"))
        self.assertEqual(after, before)

    def test_launcher_has_exact_gate_bundle_and_terminal_boundaries(self) -> None:
        source = LAUNCHER.read_text(encoding="utf-8")
        for fragment in (
            "set +x",
            "umask 077",
            "ulimit -c 0",
            "expected_operation_id=backblaze-b2-replacement-key-creation-v1",
            '$(operation_id) != "${expected_operation_id}"',
            "mktemp -d /tmp/backblaze-b2-replacement-key-creation.XXXXXX",
            "mkfifo -m 0600",
            "trap cleanup_creation EXIT",
            'exit "${client_status}"',
            "exit 2",
            "exit 0",
            "manual_intervention",
            "provider_create_attempted",
            "credential_accepted_for_use",
        ):
            self.assertIn(fragment, source)
        self.assertNotIn("set -x", source)
        self.assertNotIn("/dev/tty", source)
        self.assertNotIn("doppler secrets get", source)
        self.assertLess(source.index("validate_operation"), source.index("calculate_bundle_hash"))

    def test_manifest_bundle_contract_matches_launcher_exactly(self) -> None:
        exact_schema = json.loads(
            (ROOT / "backblaze-b2/schemas/replacement-key-creation.schema.json").read_text(
                encoding="utf-8"
            )
        )["const"]
        source = LAUNCHER.read_text(encoding="utf-8")
        match = re.search(
            r"readonly -a bundle_files=\(\n(?P<body>.*?)\n\)",
            source,
            re.DOTALL,
        )
        self.assertIsNotNone(match)
        assert match is not None
        launcher_inputs = [line.strip() for line in match.group("body").splitlines()]
        self.assertEqual(exact_schema["authorization"]["bundle_inputs"], launcher_inputs)
        self.assertIn(
            "readonly bundle_domain="
            + exact_schema["authorization"]["bundle_domain_separator"],
            source,
        )

    def test_terminal_evidence_contract_is_sanitized_and_nonaccepting(self) -> None:
        source = LAUNCHER.read_text(encoding="utf-8")
        self.assertIn('"credential_values_or_identifiers_retained": False', source)
        self.assertIn('"automatic_retry_performed": False', source)
        self.assertIn('"automatic_provider_or_secret_cleanup_performed": False', source)
        self.assertIn('"credential_accepted_for_use": False', source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
