#!/usr/bin/env python3
"""Offline transaction and failure regressions for the B2 S3 probe."""

from __future__ import annotations

import datetime as dt
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

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
CLIENT_PATH = ROOT / "backblaze-b2/scripts/s3_compatibility_probe.py"
SPEC = importlib.util.spec_from_file_location("s3_probe", CLIENT_PATH)
assert SPEC is not None and SPEC.loader is not None
CLIENT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CLIENT
SPEC.loader.exec_module(CLIENT)


def list_response(keys: list[str], status: int = 200) -> Any:
    contents = "".join(f"<Contents><Key>{key}</Key></Contents>" for key in keys)
    body = (
        "<?xml version='1.0' encoding='UTF-8'?>"
        "<ListBucketResult xmlns='http://s3.amazonaws.com/doc/2006-03-01/'>"
        f"<IsTruncated>false</IsTruncated>{contents}</ListBucketResult>"
    ).encode()
    return CLIENT.Response(status, {}, body)


class FakeTransport:
    def __init__(self, responses: list[Any]):
        self.responses = list(responses)
        self.calls: list[dict[str, Any]] = []

    def request(self, method: str, object_key: str | None = None,
                query: dict[str, str] | None = None, body: bytes = b"",
                content_type: str | None = None) -> Any:
        self.calls.append(
            {
                "method": method,
                "object_key": object_key,
                "query": query or {},
                "body": body,
                "content_type": content_type,
            }
        )
        if not self.responses:
            raise AssertionError("unexpected request")
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response


class FakeNativeResponse:
    def __init__(self, payload: dict[str, Any], status: int = 200):
        self.payload = json.dumps(payload).encode()
        self.status = status

    def __enter__(self) -> "FakeNativeResponse":
        return self

    def __exit__(self, *args: Any) -> None:
        return None

    def geturl(self) -> str:
        return CLIENT.AUTH_URL

    def read(self, size: int) -> bytes:
        return self.payload[:size]


class FakeNativeOpener:
    def __init__(self, payload: dict[str, Any]):
        self.payload = payload
        self.requests: list[Any] = []

    def open(self, request: Any, timeout: int) -> FakeNativeResponse:
        self.requests.append(request)
        return FakeNativeResponse(self.payload)


def authorization_response() -> dict[str, Any]:
    return {
        "accountId": "account-under-test",
        "authorizationToken": "token-under-test",
        "applicationKeyExpirationTimestamp": None,
        "apiInfo": {
            "storageApi": {
                "apiUrl": "https://api123.backblazeb2.com",
                "s3ApiUrl": CLIENT.ENDPOINT,
                "allowed": {
                    "buckets": [
                        {"id": CLIENT.BUCKET_ID, "name": CLIENT.BUCKET}
                    ],
                    "capabilities": sorted(CLIENT.EXPECTED_CAPABILITIES),
                    "namePrefix": None,
                },
            }
        },
    }


class RecorderFixture:
    def __init__(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="backblaze-b2-s3-test.", dir="/tmp")
        self.root = Path(self.temp.name)
        os.chmod(self.root, 0o700)
        self.fd = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY)
        self.recorder = CLIENT.EvidenceRecorder(self.fd, "a" * 64)

    def close(self) -> None:
        os.close(self.fd)
        self.temp.cleanup()

    def document(self) -> dict[str, Any]:
        return json.loads((self.root / "result.json").read_text())


class SigningTests(unittest.TestCase):
    def test_fixed_signature_and_exact_path_style_url(self) -> None:
        request = CLIENT.signed_request(
            "PUT",
            "__capability_probe__/homelab-nautobot-restic-prd-v2/0123456789abcdef0123456789abcdef/probe.txt",
            {},
            CLIENT.CONTENT,
            b"002fixturekeyid",
            b"fixture-secret",
            dt.datetime(2026, 8, 27, 18, 30, 0, tzinfo=dt.timezone.utc),
            CLIENT.CONTENT_TYPE,
        )
        self.assertEqual(
            request.full_url,
            "https://s3.us-west-002.backblazeb2.com/"
            "theama-homelab-nautobot-restic-prd/__capability_probe__/"
            "homelab-nautobot-restic-prd-v2/0123456789abcdef0123456789abcdef/probe.txt",
        )
        self.assertEqual(request.get_method(), "PUT")
        self.assertEqual(request.data, CLIENT.CONTENT)
        self.assertEqual(request.get_header("X-amz-date"), "20260827T183000Z")
        self.assertEqual(request.get_header("X-amz-content-sha256"), CLIENT.CONTENT_SHA256)
        self.assertEqual(request.get_header("Content-type"), "text/plain")
        self.assertEqual(
            request.get_header("Authorization"),
            "AWS4-HMAC-SHA256 Credential=002fixturekeyid/20260827/us-west-002/s3/aws4_request, "
            "SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date, "
            "Signature=323dd71b5976c3adbed1a7135a0c2ef463b86fce68a282ab5f3554da8f32e55a",
        )

    def test_list_query_is_sorted_and_rfc3986_encoded(self) -> None:
        request = CLIENT.signed_request(
            "GET", None,
            {"prefix": "a/b/", "max-keys": "2", "list-type": "2"}, b"",
            b"key-id", b"secret",
            dt.datetime(2026, 8, 27, tzinfo=dt.timezone.utc),
        )
        self.assertTrue(
            request.full_url.endswith("?list-type=2&max-keys=2&prefix=a%2Fb%2F")
        )


class TransactionTests(unittest.TestCase):
    RUN_ID = "0123456789abcdef0123456789abcdef"

    def setUp(self) -> None:
        self.fixture = RecorderFixture()
        self.prefix = f"{CLIENT.KEY_PARENT}/{self.RUN_ID}/"
        self.key = f"{self.prefix}probe.txt"

    def tearDown(self) -> None:
        self.fixture.close()

    def successful_responses(self) -> list[Any]:
        return [
            list_response([]),
            CLIENT.Response(200, {}, b""),
            CLIENT.Response(200, {"content-length": str(len(CLIENT.CONTENT))}, b""),
            list_response([self.key]),
            CLIENT.Response(200, {}, CLIENT.CONTENT),
            CLIENT.Response(204, {}, b""),
            CLIENT.Response(404, {}, b""),
            list_response([]),
        ]

    def test_success_is_exact_ordered_single_object_transaction(self) -> None:
        transport = FakeTransport(self.successful_responses())
        result = CLIENT.perform_probe(transport, self.fixture.recorder, self.RUN_ID)
        self.assertEqual(result, "passed")
        self.assertEqual(
            [call["method"] for call in transport.calls],
            ["GET", "PUT", "HEAD", "GET", "GET", "DELETE", "HEAD", "GET"],
        )
        self.assertEqual(sum(call["method"] == "PUT" for call in transport.calls), 1)
        self.assertEqual(sum(call["method"] == "DELETE" for call in transport.calls), 1)
        self.assertEqual(transport.calls[1]["object_key"], self.key)
        self.assertEqual(transport.calls[1]["body"], CLIENT.CONTENT)
        self.assertEqual(transport.calls[1]["content_type"], CLIENT.CONTENT_TYPE)
        self.assertTrue(all(call["object_key"] in {None, self.key} for call in transport.calls))
        self.assertTrue(
            all(call["query"] in ({}, CLIENT._list_query(self.prefix)) for call in transport.calls)
        )
        evidence = self.fixture.document()
        self.assertEqual(evidence["result"], "passed")
        self.assertTrue(evidence["cleanup"]["absence_proven"])
        self.assertFalse(evidence["cleanup"]["residue_possible"])

    def test_nonempty_initial_prefix_blocks_before_put(self) -> None:
        transport = FakeTransport([list_response([self.key])])
        result = CLIENT.perform_probe(transport, self.fixture.recorder, self.RUN_ID)
        self.assertEqual(result, "blocked")
        self.assertEqual([call["method"] for call in transport.calls], ["GET"])
        self.assertFalse(self.fixture.document()["mutation"]["put_attempted"])

    def test_ambiguous_put_runs_bounded_exact_cleanup(self) -> None:
        transport = FakeTransport(
            [
                list_response([]),
                CLIENT.ProbeBlocked("provider_transport_error"),
                CLIENT.Response(204, {}, b""),
                CLIENT.Response(404, {}, b""),
                list_response([]),
            ]
        )
        result = CLIENT.perform_probe(transport, self.fixture.recorder, self.RUN_ID)
        self.assertEqual(result, "blocked")
        self.assertEqual(
            [call["method"] for call in transport.calls],
            ["GET", "PUT", "DELETE", "HEAD", "GET"],
        )
        self.assertEqual(transport.calls[2]["object_key"], self.key)
        self.assertNotIn("prefix", transport.calls[2]["query"])
        self.assertTrue(self.fixture.document()["cleanup"]["absence_proven"])

    def test_forward_content_failure_records_observation_before_cleanup(self) -> None:
        responses = self.successful_responses()[:4] + [
            CLIENT.Response(200, {}, b"wrong"),
            CLIENT.Response(204, {}, b""),
            CLIENT.Response(404, {}, b""),
            list_response([]),
        ]
        result = CLIENT.perform_probe(FakeTransport(responses), self.fixture.recorder, self.RUN_ID)
        self.assertEqual(result, "blocked")
        evidence = self.fixture.document()
        self.assertEqual(evidence["error_class"], "content_mismatch")
        self.assertIn(
            {"phase": "forward", "request_class": "get_exact_object", "status": "http_2xx"},
            evidence["observations"],
        )

    def test_unproven_cleanup_requires_manual_intervention(self) -> None:
        transport = FakeTransport(
            [
                list_response([]),
                CLIENT.Response(500, {}, b""),
                CLIENT.ProbeBlocked("provider_transport_error"),
                CLIENT.Response(200, {}, b""),
                list_response([self.key]),
            ]
        )
        result = CLIENT.perform_probe(transport, self.fixture.recorder, self.RUN_ID)
        self.assertEqual(result, "manual_intervention")
        evidence = self.fixture.document()
        self.assertTrue(evidence["cleanup"]["residue_possible"])
        self.assertFalse(evidence["cleanup"]["absence_proven"])
        self.assertEqual(sum(call["method"] == "PUT" for call in transport.calls), 1)
        self.assertEqual(sum(call["method"] == "DELETE" for call in transport.calls), 1)

    def test_acceptance_failure_after_delete_does_not_delete_twice(self) -> None:
        responses = self.successful_responses()[:-1] + [
            CLIENT.ProbeBlocked("provider_transport_error"),
            CLIENT.Response(404, {}, b""),
            list_response([]),
        ]
        transport = FakeTransport(responses)
        result = CLIENT.perform_probe(transport, self.fixture.recorder, self.RUN_ID)
        self.assertEqual(result, "blocked")
        self.assertEqual(sum(call["method"] == "DELETE" for call in transport.calls), 1)
        self.assertTrue(self.fixture.document()["cleanup"]["absence_proven"])

    def test_truncated_list_is_rejected(self) -> None:
        response = CLIENT.Response(
            200, {},
            b"<ListBucketResult><IsTruncated>true</IsTruncated></ListBucketResult>",
        )
        transport = FakeTransport([response])
        self.assertEqual(
            CLIENT.perform_probe(transport, self.fixture.recorder, self.RUN_ID),
            "blocked",
        )


class ReadOnlyPreflightTests(unittest.TestCase):
    RUN_ID = "fedcba9876543210fedcba9876543210"

    def setUp(self) -> None:
        self.fixture = RecorderFixture()

    def tearDown(self) -> None:
        self.fixture.close()

    def test_exact_scope_authentication_and_empty_s3_list_pass(self) -> None:
        native = FakeNativeOpener(authorization_response())
        s3 = FakeTransport([list_response([])])
        result = CLIENT.perform_read_only_preflight(
            b"canonical-id", b"canonical-value", s3, self.fixture.recorder,
            self.RUN_ID, native,
        )
        self.assertEqual(result, "preflight_passed")
        self.assertEqual(len(native.requests), 1)
        request = native.requests[0]
        self.assertEqual(request.full_url, CLIENT.AUTH_URL)
        self.assertEqual(request.get_method(), "POST")
        self.assertEqual(request.data, b"{}")
        self.assertTrue(request.get_header("Authorization").startswith("Basic "))
        self.assertEqual([call["method"] for call in s3.calls], ["GET"])
        self.assertEqual(s3.calls[0]["object_key"], None)
        self.assertEqual(self.fixture.document()["result"], "preflight_passed")
        self.assertFalse(self.fixture.document()["mutation"]["put_attempted"])
        self.assertEqual(
            self.fixture.document()["scope"],
            {
                "response_shape": "allowed_buckets_array",
                "bucket_count": 1,
                "exact_bucket_match": True,
                "exact_capabilities": True,
                "null_name_prefix": True,
                "no_provider_expiration": True,
                "exact_s3_endpoint": True,
            },
        )

    def test_scope_mismatch_blocks_before_s3_request(self) -> None:
        payload = authorization_response()
        payload["apiInfo"]["storageApi"]["allowed"]["capabilities"].append(
            "writeBuckets"
        )
        native = FakeNativeOpener(payload)
        s3 = FakeTransport([])
        result = CLIENT.perform_read_only_preflight(
            b"canonical-id", b"canonical-value", s3, self.fixture.recorder,
            self.RUN_ID, native,
        )
        self.assertEqual(result, "preflight_blocked")
        self.assertEqual(s3.calls, [])
        self.assertEqual(self.fixture.document()["error_class"], "capability_scope_mismatch")

    def test_every_scope_field_is_fail_closed(self) -> None:
        mutations = (
            ("id", "wrong"),
            ("name", "wrong"),
        )
        for field, value in mutations:
            with self.subTest(field=field):
                fixture = RecorderFixture()
                try:
                    payload = authorization_response()
                    payload["apiInfo"]["storageApi"]["allowed"]["buckets"][0][field] = value
                    result = CLIENT.perform_read_only_preflight(
                        b"canonical-id", b"canonical-value", FakeTransport([]),
                        fixture.recorder, self.RUN_ID, FakeNativeOpener(payload),
                    )
                    self.assertEqual(result, "preflight_blocked")
                finally:
                    fixture.close()

    def test_non_bucket_scope_fields_are_fail_closed_after_observation(self) -> None:
        def add_capability(payload: dict[str, Any]) -> None:
            payload["apiInfo"]["storageApi"]["allowed"]["capabilities"].append(
                "writeBuckets"
            )

        def set_name_prefix(payload: dict[str, Any]) -> None:
            payload["apiInfo"]["storageApi"]["allowed"]["namePrefix"] = (
                "restricted/"
            )

        def set_s3_endpoint(payload: dict[str, Any]) -> None:
            payload["apiInfo"]["storageApi"]["s3ApiUrl"] = (
                "https://wrong.invalid"
            )

        def set_expiration(payload: dict[str, Any]) -> None:
            payload["applicationKeyExpirationTimestamp"] = 123

        cases = (
            ("capabilities", add_capability, "capability_scope_mismatch"),
            ("name_prefix", set_name_prefix, "prefix_scope_mismatch"),
            ("s3_endpoint", set_s3_endpoint, "s3_endpoint_mismatch"),
            ("expiration", set_expiration, "credential_expiration_present"),
        )
        for name, mutate, expected_error in cases:
            with self.subTest(name=name):
                fixture = RecorderFixture()
                try:
                    payload = authorization_response()
                    mutate(payload)
                    result = CLIENT.perform_read_only_preflight(
                        b"canonical-id", b"canonical-value", FakeTransport([]),
                        fixture.recorder, self.RUN_ID, FakeNativeOpener(payload),
                    )
                    self.assertEqual(result, "preflight_blocked")
                    evidence = fixture.document()
                    self.assertEqual(evidence["error_class"], expected_error)
                    self.assertIn("scope", evidence)
                finally:
                    fixture.close()

    def test_scope_shape_is_recorded_before_legacy_scalar_rejection(self) -> None:
        payload = authorization_response()
        allowed = payload["apiInfo"]["storageApi"]["allowed"]
        allowed.pop("buckets")
        allowed["bucketId"] = CLIENT.BUCKET_ID
        allowed["bucketName"] = CLIENT.BUCKET
        result = CLIENT.perform_read_only_preflight(
            b"canonical-id", b"canonical-value", FakeTransport([]),
            self.fixture.recorder, self.RUN_ID, FakeNativeOpener(payload),
        )
        self.assertEqual(result, "preflight_blocked")
        evidence = self.fixture.document()
        self.assertEqual(evidence["error_class"], "bucket_scope_mismatch")
        self.assertEqual(evidence["scope"]["response_shape"], "legacy_scalar")
        self.assertEqual(evidence["scope"]["bucket_count"], 1)
        self.assertFalse(evidence["scope"]["exact_bucket_match"])

    def test_non_single_allowed_buckets_are_rejected_with_sanitized_count(self) -> None:
        cases = (
            ([], 0),
            (
                [
                    {"id": CLIENT.BUCKET_ID, "name": CLIENT.BUCKET},
                    {"id": "unrelated-id", "name": "unrelated-name"},
                ],
                2,
            ),
        )
        for buckets, expected_count in cases:
            with self.subTest(bucket_count=expected_count):
                fixture = RecorderFixture()
                try:
                    payload = authorization_response()
                    payload["apiInfo"]["storageApi"]["allowed"]["buckets"] = buckets
                    result = CLIENT.perform_read_only_preflight(
                        b"canonical-id", b"canonical-value", FakeTransport([]),
                        fixture.recorder, self.RUN_ID, FakeNativeOpener(payload),
                    )
                    self.assertEqual(result, "preflight_blocked")
                    evidence = fixture.document()
                    self.assertEqual(
                        evidence["scope"]["bucket_count"], expected_count
                    )
                    self.assertFalse(evidence["scope"]["exact_bucket_match"])
                    self.assertNotIn("unrelated-id", json.dumps(evidence))
                    self.assertNotIn("unrelated-name", json.dumps(evidence))
                finally:
                    fixture.close()

    def test_malformed_allowed_buckets_is_observed_before_rejection(self) -> None:
        payload = authorization_response()
        payload["apiInfo"]["storageApi"]["allowed"]["buckets"] = {
            "id": CLIENT.BUCKET_ID,
            "name": CLIENT.BUCKET,
        }
        result = CLIENT.perform_read_only_preflight(
            b"canonical-id", b"canonical-value", FakeTransport([]),
            self.fixture.recorder, self.RUN_ID, FakeNativeOpener(payload),
        )
        self.assertEqual(result, "preflight_blocked")
        evidence = self.fixture.document()
        self.assertEqual(evidence["error_class"], "bucket_scope_mismatch")
        self.assertEqual(evidence["scope"]["response_shape"], "allowed_buckets_invalid")

    def test_duplicate_capability_is_not_exact(self) -> None:
        payload = authorization_response()
        capabilities = payload["apiInfo"]["storageApi"]["allowed"]["capabilities"]
        capabilities.append(capabilities[0])
        result = CLIENT.perform_read_only_preflight(
            b"canonical-id", b"canonical-value", FakeTransport([]),
            self.fixture.recorder, self.RUN_ID, FakeNativeOpener(payload),
        )
        self.assertEqual(result, "preflight_blocked")
        evidence = self.fixture.document()
        self.assertEqual(evidence["error_class"], "capability_scope_mismatch")
        self.assertFalse(evidence["scope"]["exact_capabilities"])

    def test_expiration_is_rejected(self) -> None:
        payload = authorization_response()
        payload["applicationKeyExpirationTimestamp"] = 123
        result = CLIENT.perform_read_only_preflight(
            b"canonical-id", b"canonical-value", FakeTransport([]),
            self.fixture.recorder, self.RUN_ID, FakeNativeOpener(payload),
        )
        self.assertEqual(result, "preflight_blocked")
        self.assertEqual(self.fixture.document()["error_class"], "credential_expiration_present")


class ProtectionTests(unittest.TestCase):
    def test_doppler_commands_are_exact_and_secret_free(self) -> None:
        for name in (CLIENT.KEY_ID_NAME, CLIENT.KEY_VALUE_NAME):
            argv = CLIENT.doppler_secret_argv(name)
            self.assertEqual(
                argv,
                (
                    "doppler", "--no-check-version", "--no-read-env", "--silent",
                    "secrets", "get", name, "--project", "homelab-dev",
                    "--config", "prd_b2", "--plain",
                ),
            )
        self.assertNotIn("DOPPLER_TOKEN", CLIENT.minimal_environment())
        rendered = CLIENT_PATH.read_text(encoding="utf-8")
        self.assertNotIn("prd_b2_admin", rendered)
        self.assertNotIn("CANDIDATE", rendered)

    def test_secret_reader_uses_no_shell_stdin_or_stderr(self) -> None:
        completed = subprocess.CompletedProcess((), 0, b"fixture-secret\n", b"")
        runner = mock.Mock(return_value=completed)
        value = CLIENT.read_secret(CLIENT.KEY_ID_NAME, runner=runner)
        self.assertEqual(value, bytearray(b"fixture-secret"))
        kwargs = runner.call_args.kwargs
        self.assertIs(kwargs["stdin"], subprocess.DEVNULL)
        self.assertIs(kwargs["stderr"], subprocess.DEVNULL)
        self.assertNotIn("shell", kwargs)
        self.assertNotIn(b"fixture-secret", repr(runner.call_args.args).encode())

    def test_evidence_is_mode_0600_and_contains_no_fixture_secrets_or_key(self) -> None:
        fixture = RecorderFixture()
        try:
            fixture.recorder.finish("blocked", "fixture_error", "b" * 64, True, False)
            path = fixture.root / "result.json"
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            raw = path.read_text()
            self.assertNotIn("fixture-secret", raw)
            self.assertNotIn("0123456789abcdef0123456789abcdef", raw)
            self.assertNotIn("Authorization", raw)
            self.assertNotIn("NAUTOBOT_RESTIC_B2_APPLICATION_KEY", raw)
        finally:
            fixture.close()

    def test_direct_cli_is_fail_closed_and_contacts_nothing(self) -> None:
        result = subprocess.run(
            [sys.executable, str(CLIENT_PATH)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=5,
        )
        self.assertEqual(result.returncode, 69)
        self.assertEqual(
            result.stdout.decode().strip(),
            "result=blocked error_class=hash_bound_launcher_required",
        )

    def test_evidence_root_must_be_owned_mode_0700_beneath_tmp(self) -> None:
        with tempfile.TemporaryDirectory(prefix="backblaze-b2-s3-compatibility.", dir="/tmp") as name:
            path = Path(name)
            os.chmod(path, 0o755)
            with self.assertRaisesRegex(CLIENT.ProbeBlocked, "unsafe_evidence_root"):
                CLIENT.validate_evidence_root(path)


if __name__ == "__main__":
    unittest.main()
