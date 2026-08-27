#!/usr/bin/env python3
"""Protected Backblaze B2 S3 compatibility probe client.

The module contains the exact transaction implementation, but intentionally has
no live command-line entrypoint.  A separately reviewed hash-bound launcher must
provide the protected evidence directory before live use.
"""

from __future__ import annotations

import datetime as dt
import base64
import hashlib
import hmac
import json
import os
import re
import ssl
import stat
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

OPERATION_ID = "backblaze-b2-s3-compatibility-v1"
AUTH_URL = "https://api.backblazeb2.com/b2api/v4/b2_authorize_account"
ENDPOINT = "https://s3.us-west-002.backblazeb2.com"
HOST = "s3.us-west-002.backblazeb2.com"
REGION = "us-west-002"
SERVICE = "s3"
BUCKET = "theama-homelab-nautobot-restic-prd"
BUCKET_ID = "4d1bda761665474eaf030b18"
KEY_PARENT = "__capability_probe__/homelab-nautobot-restic-prd-v2"
CONTENT = b"nautobot B2 S3 compatibility probe v1\n"
CONTENT_SHA256 = "d351ee40d27759daeca28938056b90208e9c5b791d1f9267b2aec8ec1ae13089"
CONTENT_TYPE = "text/plain"
PROJECT = "homelab-dev"
CONFIG = "prd_b2"
KEY_ID_NAME = "NAUTOBOT_RESTIC_B2_APPLICATION_KEY_ID"
KEY_VALUE_NAME = "NAUTOBOT_RESTIC_B2_APPLICATION_KEY"
MAX_CREDENTIAL_BYTES = 4096
MAX_RESPONSE_BYTES = 1024 * 1024
HTTP_TIMEOUT_SECONDS = 20
DOPPLER_TIMEOUT_SECONDS = 30
DOPPLER_BASE = ("doppler", "--no-check-version", "--no-read-env", "--silent")
EXPECTED_CAPABILITIES = {
    "listAllBucketNames",
    "listBuckets",
    "readBuckets",
    "listFiles",
    "readFiles",
    "writeFiles",
    "deleteFiles",
}


class ProbeBlocked(Exception):
    """A fail-closed probe rejection with a sanitized error class."""

    def __init__(self, code: str):
        self.code = code if re.fullmatch(r"[a-z0-9_]+", code) else "invalid_error_class"
        super().__init__(self.code)


@dataclass(frozen=True)
class Response:
    status: int
    headers: dict[str, str]
    body: bytes


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req: Any, fp: Any, code: int, msg: str,
                         headers: Any, newurl: str) -> None:
        return None


def minimal_environment() -> dict[str, str]:
    allowed = ("HOME", "PATH", "LANG", "LC_ALL", "XDG_CONFIG_HOME")
    return {name: os.environ[name] for name in allowed if name in os.environ}


def doppler_secret_argv(name: str) -> tuple[str, ...]:
    if name not in {KEY_ID_NAME, KEY_VALUE_NAME}:
        raise ProbeBlocked("invalid_secret_name")
    return DOPPLER_BASE + (
        "secrets", "get", name, "--project", PROJECT, "--config", CONFIG, "--plain",
    )


def read_secret(name: str, runner: Callable[..., subprocess.CompletedProcess[bytes]] = subprocess.run) -> bytearray:
    try:
        result = runner(
            doppler_secret_argv(name),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=minimal_environment(),
            timeout=DOPPLER_TIMEOUT_SECONDS,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise ProbeBlocked("doppler_read_failed") from exc
    value = bytearray(result.stdout)
    if result.returncode != 0 or not value or len(value) > MAX_CREDENTIAL_BYTES:
        value[:] = b"\0" * len(value)
        value.clear()
        raise ProbeBlocked("doppler_read_failed")
    while value.endswith(b"\n") or value.endswith(b"\r"):
        value.pop()
    if not value or b"\n" in value or b"\r" in value or b"\0" in value:
        value[:] = b"\0" * len(value)
        value.clear()
        raise ProbeBlocked("invalid_secret_value")
    return value


def validate_evidence_root(path: Path) -> int:
    if (
        not path.is_absolute()
        or path.parent != Path("/tmp")
        or not re.fullmatch(r"backblaze-b2-s3-compatibility\.[A-Za-z0-9_]+", path.name)
    ):
        raise ProbeBlocked("invalid_evidence_root")
    try:
        info = path.lstat()
    except OSError as exc:
        raise ProbeBlocked("invalid_evidence_root") from exc
    if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise ProbeBlocked("invalid_evidence_root")
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ProbeBlocked("unsafe_evidence_root")
    flags = os.O_RDONLY | os.O_DIRECTORY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        return os.open(path, flags)
    except OSError as exc:
        raise ProbeBlocked("invalid_evidence_root") from exc


class EvidenceRecorder:
    """Persist progressive sanitized observations before later gates run."""

    def __init__(self, root_fd: int, bundle_sha256: str):
        if not re.fullmatch(r"[0-9a-f]{64}", bundle_sha256):
            raise ProbeBlocked("invalid_bundle_hash")
        self.root_fd = root_fd
        self.document: dict[str, Any] = {
            "schema_version": 1,
            "operation": OPERATION_ID,
            "bundle_sha256": bundle_sha256,
            "result": "running",
            "credential_source": "doppler_prd_b2_in_memory",
            "credential_values_retained": False,
            "provider_response_bodies_retained": False,
            "observations": [],
            "mutation": {"put_attempted": False, "delete_attempted": False},
            "cleanup": {"absence_proven": False, "residue_possible": False},
        }
        self._write()

    def observe(self, phase: str, request_class: str, status: str) -> None:
        for value in (phase, request_class, status):
            if not re.fullmatch(r"[a-z0-9_]+", value):
                raise ProbeBlocked("invalid_observation")
        self.document["observations"].append(
            {"phase": phase, "request_class": request_class, "status": status}
        )
        self._write()

    def mutation(self, *, put_attempted: bool | None = None,
                 delete_attempted: bool | None = None) -> None:
        if put_attempted is not None:
            self.document["mutation"]["put_attempted"] = put_attempted
        if delete_attempted is not None:
            self.document["mutation"]["delete_attempted"] = delete_attempted
        self._write()

    def scope(
        self,
        response_shape: str,
        bucket_count: int,
        exact_bucket_match: bool,
        exact_capabilities: bool,
        null_name_prefix: bool,
        no_provider_expiration: bool,
        exact_s3_endpoint: bool,
    ) -> None:
        if response_shape not in {
            "allowed_buckets_array",
            "allowed_buckets_invalid",
            "allowed_invalid",
            "legacy_scalar",
            "allowed_missing",
        }:
            raise ProbeBlocked("invalid_scope_observation")
        if not isinstance(bucket_count, int) or not 0 <= bucket_count <= 101:
            raise ProbeBlocked("invalid_scope_observation")
        values = (
            exact_bucket_match,
            exact_capabilities,
            null_name_prefix,
            no_provider_expiration,
            exact_s3_endpoint,
        )
        if not all(isinstance(value, bool) for value in values):
            raise ProbeBlocked("invalid_scope_observation")
        self.document["scope"] = {
            "response_shape": response_shape,
            "bucket_count": bucket_count,
            "exact_bucket_match": exact_bucket_match,
            "exact_capabilities": exact_capabilities,
            "null_name_prefix": null_name_prefix,
            "no_provider_expiration": no_provider_expiration,
            "exact_s3_endpoint": exact_s3_endpoint,
        }
        self._write()

    def finish(self, result: str, error_class: str | None, run_id_sha256: str,
               absence_proven: bool, residue_possible: bool) -> None:
        self.document["result"] = result
        self.document["run_id_sha256"] = run_id_sha256
        self.document["content_sha256"] = CONTENT_SHA256
        self.document["content_size"] = len(CONTENT)
        self.document["cleanup"] = {
            "absence_proven": absence_proven,
            "residue_possible": residue_possible,
        }
        if error_class is not None:
            self.document["error_class"] = error_class
        self._write()

    def _write(self) -> None:
        payload = (json.dumps(self.document, indent=2, sort_keys=True) + "\n").encode()
        flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        fd = os.open("result.json", flags, 0o600, dir_fd=self.root_fd)
        try:
            os.write(fd, payload)
            os.fchmod(fd, 0o600)
            os.fsync(fd)
        finally:
            os.close(fd)


def _sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _hmac(key: bytes, value: str) -> bytes:
    return hmac.new(key, value.encode(), hashlib.sha256).digest()


def _encoded_path(object_key: str | None) -> str:
    suffix = "" if object_key is None else f"/{object_key}"
    return urllib.parse.quote(f"/{BUCKET}{suffix}", safe="/-_.~")


def _encoded_query(params: dict[str, str]) -> str:
    return "&".join(
        f"{urllib.parse.quote(key, safe='-_.~')}={urllib.parse.quote(value, safe='-_.~')}"
        for key, value in sorted(params.items())
    )


def signed_request(method: str, object_key: str | None, query: dict[str, str], body: bytes,
                   key_id: bytes, application_key: bytes, now: dt.datetime,
                   content_type: str | None = None) -> urllib.request.Request:
    if method not in {"GET", "PUT", "HEAD", "DELETE"}:
        raise ProbeBlocked("invalid_request_method")
    if now.tzinfo is None:
        raise ProbeBlocked("invalid_signing_time")
    path = _encoded_path(object_key)
    query_string = _encoded_query(query)
    payload_hash = _sha256(body)
    timestamp = now.astimezone(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    date = timestamp[:8]
    headers = {
        "host": HOST,
        "x-amz-content-sha256": payload_hash,
        "x-amz-date": timestamp,
    }
    if content_type is not None:
        headers["content-type"] = content_type
    signed_headers = ";".join(sorted(headers))
    canonical_headers = "".join(f"{name}:{headers[name]}\n" for name in sorted(headers))
    canonical_request = "\n".join(
        [method, path, query_string, canonical_headers, signed_headers, payload_hash]
    )
    scope = f"{date}/{REGION}/{SERVICE}/aws4_request"
    string_to_sign = "\n".join(
        ["AWS4-HMAC-SHA256", timestamp, scope, _sha256(canonical_request.encode())]
    )
    date_key = _hmac(b"AWS4" + application_key, date)
    region_key = _hmac(date_key, REGION)
    service_key = _hmac(region_key, SERVICE)
    signing_key = _hmac(service_key, "aws4_request")
    signature = hmac.new(signing_key, string_to_sign.encode(), hashlib.sha256).hexdigest()
    authorization = (
        f"AWS4-HMAC-SHA256 Credential={key_id.decode('ascii')}/{scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )
    request_headers = {name: value for name, value in headers.items() if name != "host"}
    request_headers["Authorization"] = authorization
    url = f"{ENDPOINT}{path}"
    if query_string:
        url += f"?{query_string}"
    data = body if method == "PUT" else None
    return urllib.request.Request(url, data=data, headers=request_headers, method=method)


class S3Transport:
    def __init__(self, key_id: bytes, application_key: bytes,
                 clock: Callable[[], dt.datetime] | None = None):
        self.key_id = key_id
        self.application_key = application_key
        self.clock = clock or (lambda: dt.datetime.now(dt.timezone.utc))
        context = ssl.create_default_context()
        self.opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}),
            urllib.request.HTTPSHandler(context=context),
            NoRedirect(),
        )

    def request(self, method: str, object_key: str | None = None,
                query: dict[str, str] | None = None, body: bytes = b"",
                content_type: str | None = None) -> Response:
        request = signed_request(
            method, object_key, query or {}, body, self.key_id, self.application_key,
            self.clock(), content_type,
        )
        try:
            response = self.opener.open(request, timeout=HTTP_TIMEOUT_SECONDS)
        except urllib.error.HTTPError as exc:
            response = exc
        except (urllib.error.URLError, TimeoutError, ssl.SSLError) as exc:
            raise ProbeBlocked("provider_transport_error") from exc
        with response:
            if response.geturl() != request.full_url:
                raise ProbeBlocked("redirect_rejected")
            payload = response.read(MAX_RESPONSE_BYTES + 1)
            if len(payload) > MAX_RESPONSE_BYTES:
                raise ProbeBlocked("provider_response_too_large")
            return Response(
                status=response.status,
                headers={key.lower(): value for key, value in response.headers.items()},
                body=payload,
            )


def _native_authorization(key_id: bytes, application_key: bytes, opener: Any) -> dict[str, Any]:
    source = bytearray(key_id)
    source.extend(b":")
    source.extend(application_key)
    encoded = bytearray(base64.b64encode(source))
    source[:] = b"\0" * len(source)
    source.clear()
    try:
        request = urllib.request.Request(
            AUTH_URL,
            data=b"{}",
            headers={
                "Authorization": "Basic " + encoded.decode("ascii"),
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
            method="POST",
        )
        try:
            response = opener.open(request, timeout=HTTP_TIMEOUT_SECONDS)
        except urllib.error.HTTPError as exc:
            response = exc
        except (urllib.error.URLError, TimeoutError, ssl.SSLError) as exc:
            raise ProbeBlocked("provider_transport_error") from exc
        with response:
            if response.geturl() != AUTH_URL:
                raise ProbeBlocked("redirect_rejected")
            payload = response.read(MAX_RESPONSE_BYTES + 1)
            if len(payload) > MAX_RESPONSE_BYTES:
                raise ProbeBlocked("provider_response_too_large")
            if response.status != 200:
                raise ProbeBlocked(f"authorize_http_{response.status}")
    finally:
        encoded[:] = b"\0" * len(encoded)
        encoded.clear()
    try:
        document = json.loads(payload)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ProbeBlocked("invalid_authorization_response") from exc
    if not isinstance(document, dict):
        raise ProbeBlocked("invalid_authorization_response")
    return document


def perform_read_only_preflight(key_id: bytes, application_key: bytes,
                                s3_transport: Any, recorder: EvidenceRecorder,
                                run_id: str, native_opener: Any) -> str:
    if not re.fullmatch(r"[0-9a-f]{32}", run_id):
        raise ProbeBlocked("invalid_run_id")
    run_hash = _sha256(run_id.encode())
    prefix = f"{KEY_PARENT}/{run_id}/"
    try:
        document = _native_authorization(key_id, application_key, native_opener)
        recorder.observe("preflight", "authorize_canonical_credential", "http_2xx")
        api_info = document.get("apiInfo")
        storage = api_info.get("storageApi") if isinstance(api_info, dict) else None
        if not isinstance(storage, dict):
            raise ProbeBlocked("invalid_authorization_response")
        allowed = storage.get("allowed")
        allowed_mapping = allowed if isinstance(allowed, dict) else {}
        buckets = allowed_mapping.get("buckets")
        if isinstance(buckets, list):
            response_shape = "allowed_buckets_array"
            bucket_count = min(len(buckets), 101)
            exact_bucket_match = (
                len(buckets) == 1
                and isinstance(buckets[0], dict)
                and buckets[0].get("id") == BUCKET_ID
                and buckets[0].get("name") == BUCKET
            )
        elif "buckets" in allowed_mapping:
            response_shape = "allowed_buckets_invalid"
            bucket_count = 0
            exact_bucket_match = False
        elif any(
            name in allowed_mapping for name in ("bucketId", "bucketName")
        ):
            response_shape = "legacy_scalar"
            bucket_count = 1
            exact_bucket_match = False
        elif isinstance(allowed, dict):
            response_shape = "allowed_missing"
            bucket_count = 0
            exact_bucket_match = False
        else:
            response_shape = "allowed_invalid"
            bucket_count = 0
            exact_bucket_match = False
        capabilities = allowed_mapping.get("capabilities")
        exact_capabilities = (
            isinstance(capabilities, list)
            and len(capabilities) == len(EXPECTED_CAPABILITIES)
            and all(isinstance(capability, str) for capability in capabilities)
            and set(capabilities) == EXPECTED_CAPABILITIES
        )
        null_name_prefix = allowed_mapping.get("namePrefix") is None
        no_provider_expiration = (
            document.get("applicationKeyExpirationTimestamp") is None
        )
        exact_s3_endpoint = storage.get("s3ApiUrl") == ENDPOINT
        recorder.scope(
            response_shape,
            bucket_count,
            exact_bucket_match,
            exact_capabilities,
            null_name_prefix,
            no_provider_expiration,
            exact_s3_endpoint,
        )
        if response_shape != "allowed_buckets_array" or not exact_bucket_match:
            raise ProbeBlocked("bucket_scope_mismatch")
        if not exact_capabilities:
            raise ProbeBlocked("capability_scope_mismatch")
        if not null_name_prefix:
            raise ProbeBlocked("prefix_scope_mismatch")
        if not exact_s3_endpoint:
            raise ProbeBlocked("s3_endpoint_mismatch")
        if not no_provider_expiration:
            raise ProbeBlocked("credential_expiration_present")

        response = s3_transport.request("GET", query=_list_query(prefix))
        recorder.observe("preflight", "list_owned_prefix", f"http_{response.status // 100}xx")
        _require_empty_list(response)
        recorder.finish("preflight_passed", None, run_hash, True, False)
        return "preflight_passed"
    except Exception as exc:
        error = exc if isinstance(exc, ProbeBlocked) else ProbeBlocked("internal_error")
        recorder.finish("preflight_blocked", error.code, run_hash, True, False)
        return "preflight_blocked"


def _list_keys(response: Response) -> list[str]:
    if response.status != 200:
        raise ProbeBlocked(f"list_http_{response.status}")
    try:
        root = ET.fromstring(response.body)
    except ET.ParseError as exc:
        raise ProbeBlocked("invalid_list_response") from exc
    if root.findtext("{*}IsTruncated") not in {"false", "False"}:
        raise ProbeBlocked("list_response_truncated")
    return [node.text or "" for node in root.findall("{*}Contents/{*}Key")]


def _require_empty_list(response: Response) -> None:
    if _list_keys(response):
        raise ProbeBlocked("owned_prefix_not_empty")


def _list_query(prefix: str) -> dict[str, str]:
    return {"list-type": "2", "max-keys": "2", "prefix": prefix}


def perform_probe(transport: Any, recorder: EvidenceRecorder, run_id: str) -> str:
    if not re.fullmatch(r"[0-9a-f]{32}", run_id):
        raise ProbeBlocked("invalid_run_id")
    prefix = f"{KEY_PARENT}/{run_id}/"
    object_key = f"{prefix}probe.txt"
    run_hash = _sha256(run_id.encode())
    put_attempted = False
    delete_attempted = False

    try:
        response = transport.request("GET", query=_list_query(prefix))
        recorder.observe("initial", "list_owned_prefix", f"http_{response.status // 100}xx")
        _require_empty_list(response)

        put_attempted = True
        recorder.mutation(put_attempted=True)
        response = transport.request(
            "PUT", object_key=object_key, body=CONTENT, content_type=CONTENT_TYPE,
        )
        recorder.observe("forward", "put_exact_object", f"http_{response.status // 100}xx")
        if response.status != 200:
            raise ProbeBlocked(f"put_http_{response.status}")

        response = transport.request("HEAD", object_key=object_key)
        recorder.observe("forward", "head_exact_object", f"http_{response.status // 100}xx")
        if response.status != 200 or response.headers.get("content-length") != str(len(CONTENT)):
            raise ProbeBlocked("head_mismatch")

        response = transport.request("GET", query=_list_query(prefix))
        recorder.observe("forward", "list_owned_prefix", f"http_{response.status // 100}xx")
        if _list_keys(response) != [object_key]:
            raise ProbeBlocked("list_exact_object_mismatch")

        response = transport.request("GET", object_key=object_key)
        recorder.observe("forward", "get_exact_object", f"http_{response.status // 100}xx")
        if response.status != 200 or response.body != CONTENT or _sha256(response.body) != CONTENT_SHA256:
            raise ProbeBlocked("content_mismatch")

        delete_attempted = True
        recorder.mutation(delete_attempted=True)
        response = transport.request("DELETE", object_key=object_key)
        recorder.observe("forward", "delete_exact_object", f"http_{response.status // 100}xx")
        if response.status != 204:
            raise ProbeBlocked(f"delete_http_{response.status}")

        response = transport.request("HEAD", object_key=object_key)
        recorder.observe("acceptance", "head_exact_object", f"http_{response.status // 100}xx")
        if response.status != 404:
            raise ProbeBlocked("object_still_present")
        response = transport.request("GET", query=_list_query(prefix))
        recorder.observe("acceptance", "list_owned_prefix", f"http_{response.status // 100}xx")
        _require_empty_list(response)
        recorder.finish("passed", None, run_hash, True, False)
        return "passed"
    except Exception as exc:
        forward_error = exc if isinstance(exc, ProbeBlocked) else ProbeBlocked("internal_error")
        if not put_attempted:
            recorder.finish("blocked", forward_error.code, run_hash, True, False)
            return "blocked"

        head_absent = False
        list_empty = False
        if not delete_attempted:
            try:
                delete_attempted = True
                recorder.mutation(delete_attempted=True)
                response = transport.request("DELETE", object_key=object_key)
                recorder.observe("cleanup", "delete_exact_object", f"http_{response.status // 100}xx")
            except ProbeBlocked:
                recorder.observe("cleanup", "delete_exact_object", "transport_error")
        try:
            response = transport.request("HEAD", object_key=object_key)
            recorder.observe("cleanup", "head_exact_object", f"http_{response.status // 100}xx")
            head_absent = response.status == 404
        except ProbeBlocked:
            recorder.observe("cleanup", "head_exact_object", "transport_error")
        try:
            response = transport.request("GET", query=_list_query(prefix))
            recorder.observe("cleanup", "list_owned_prefix", f"http_{response.status // 100}xx")
            list_empty = _list_keys(response) == []
        except ProbeBlocked:
            recorder.observe("cleanup", "list_owned_prefix", "transport_error")
        absence = delete_attempted and head_absent and list_empty
        result = "blocked" if absence else "manual_intervention"
        recorder.finish(result, forward_error.code, run_hash, absence, not absence)
        return result


def execute(evidence_root: Path, bundle_sha256: str, run_id: str, mode: str,
            transport_factory: Callable[[bytes, bytes], Any] = S3Transport) -> str:
    if mode not in {"preflight", "execute"}:
        raise ProbeBlocked("invalid_execution_mode")
    root_fd = validate_evidence_root(evidence_root)
    key_id: bytearray | None = None
    application_key: bytearray | None = None
    try:
        recorder = EvidenceRecorder(root_fd, bundle_sha256)
        key_id = read_secret(KEY_ID_NAME)
        application_key = read_secret(KEY_VALUE_NAME)
        transport = transport_factory(bytes(key_id), bytes(application_key))
        if mode == "preflight":
            return perform_read_only_preflight(
                bytes(key_id), bytes(application_key), transport, recorder, run_id,
                transport.opener,
            )
        return perform_probe(transport, recorder, run_id)
    finally:
        for secret in (key_id, application_key):
            if isinstance(secret, bytearray):
                secret[:] = b"\0" * len(secret)
                secret.clear()
        os.close(root_fd)


if __name__ == "__main__":
    print("result=blocked error_class=hash_bound_launcher_required")
    raise SystemExit(69)
