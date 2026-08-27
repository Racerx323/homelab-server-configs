#!/usr/bin/env python3
"""Read-only Backblaze B2 capability-remediation preflight."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import selectors
import ssl
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

OPERATION_ID = "backblaze-b2-capability-remediation-preflight-v3"
AUTH_URL = "https://api.backblazeb2.com/b2api/v4/b2_authorize_account"
EXPECTED_S3_URL = "https://s3.us-west-002.backblazeb2.com"
EXPECTED_BUCKET_NAME = "theama-homelab-nautobot-restic-prd"
EXPECTED_BUCKET_ID = "4d1bda761665474eaf030b18"
REJECTED_KEY_NAME = "homelab-nautobot-restic-prd"
REPLACEMENT_KEY_NAME = "homelab-nautobot-restic-prd-v2"
REQUIRED_AUTH_CAPABILITIES = {
    "listKeys",
    "writeKeys",
    "listBuckets",
    "readBuckets",
    "listFiles",
}
REQUIRED_FILE_CAPABILITIES = {
    "listAllBucketNames",
    "listBuckets",
    "readBuckets",
    "listFiles",
    "readFiles",
    "writeFiles",
    "deleteFiles",
}
PROHIBITED_RESIDUE_CAPABILITIES = {
    "writeBuckets",
    "writeBucketLifecycleRules",
    "writeBucketEncryption",
    "writeBucketLogging",
    "writeBucketNotifications",
    "writeBucketReplications",
}
CANONICAL_SECRET_NAMES = {
    "NAUTOBOT_RESTIC_B2_APPLICATION_KEY_ID",
    "NAUTOBOT_RESTIC_B2_APPLICATION_KEY",
}
CANDIDATE_SECRET_NAMES = {
    "NAUTOBOT_RESTIC_B2_CANDIDATE_APPLICATION_KEY_ID",
    "NAUTOBOT_RESTIC_B2_CANDIDATE_APPLICATION_KEY",
}
MAX_CREDENTIAL_BYTES = 4096
MAX_RESPONSE_BYTES = 1024 * 1024
MAX_DOPPLER_OUTPUT_BYTES = 1024 * 1024
HTTP_TIMEOUT_SECONDS = 20
DOPPLER_TIMEOUT_SECONDS = 30
API_HOST_RE = re.compile(r"api(?:[0-9]+)?\.backblazeb2\.com", re.ASCII)
DOPPLER_BASE = (
    "doppler",
    "--no-check-version",
    "--no-read-env",
    "--silent",
)
ADMIN_DOPPLER_PROJECT = "homelab-dev"
ADMIN_DOPPLER_CONFIG = "prd_b2_admin"
ADMIN_KEY_ID_NAME = "BACKBLAZE_B2_MASTER_APPLICATION_KEY_ID"
ADMIN_KEY_VALUE_NAME = "BACKBLAZE_B2_MASTER_APPLICATION_KEY"
DOPPLER_NAMES_ARGV = DOPPLER_BASE + (
    "secrets",
    "--project",
    "homelab-dev",
    "--config",
    "prd_b2",
    "--only-names",
    "--json",
)


class PreflightBlocked(Exception):
    """A bounded, sanitized preflight rejection."""

    def __init__(self, code: str, observations: dict[str, Any] | None = None):
        if not re.fullmatch(r"[a-z0-9_]+", code):
            code = "invalid_error_class"
        self.code = code
        self.observations = observations if observations is not None else {}
        super().__init__(code)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req: Any, fp: Any, code: int, msg: str,
                         headers: Any, newurl: str) -> None:
        return None


def validate_evidence_root(path: Path) -> int:
    if (
        not path.is_absolute()
        or path.parent != Path("/tmp")
        or not re.fullmatch(r"backblaze-b2-capability-preflight\.[A-Za-z0-9_]+", path.name)
    ):
        raise PreflightBlocked("invalid_evidence_root")
    try:
        info = path.lstat()
    except OSError as exc:
        raise PreflightBlocked("invalid_evidence_root") from exc
    if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise PreflightBlocked("invalid_evidence_root")
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise PreflightBlocked("unsafe_evidence_root")
    flags = os.O_RDONLY | os.O_DIRECTORY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        return os.open(path, flags)
    except OSError as exc:
        raise PreflightBlocked("invalid_evidence_root") from exc


def minimal_environment() -> dict[str, str]:
    allowed = ("HOME", "PATH", "LANG", "LC_ALL", "XDG_CONFIG_HOME")
    return {name: os.environ[name] for name in allowed if name in os.environ}


def doppler_secret_argv(name: str) -> tuple[str, ...]:
    if name not in {ADMIN_KEY_ID_NAME, ADMIN_KEY_VALUE_NAME}:
        raise PreflightBlocked("invalid_admin_secret_name")
    return DOPPLER_BASE + (
        "secrets",
        "get",
        name,
        "--project",
        ADMIN_DOPPLER_PROJECT,
        "--config",
        ADMIN_DOPPLER_CONFIG,
        "--plain",
    )


def validate_api_base(url: str) -> str:
    parsed = urllib.parse.urlsplit(url)
    if (
        parsed.scheme != "https"
        or parsed.username is not None
        or parsed.password is not None
        or parsed.port not in {None, 443}
        or parsed.query
        or parsed.fragment
        or parsed.path not in {"", "/"}
        or not parsed.hostname
        or not API_HOST_RE.fullmatch(parsed.hostname)
    ):
        raise PreflightBlocked("unsafe_api_url")
    return f"https://{parsed.hostname}"


def validate_s3_url(url: str) -> None:
    if url != EXPECTED_S3_URL:
        raise PreflightBlocked("unexpected_s3_url")


def build_opener() -> urllib.request.OpenerDirector:
    context = ssl.create_default_context()
    return urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPSHandler(context=context),
        NoRedirect(),
    )


def request_json(opener: Any, method: str, url: str, authorization: str,
                 body: dict[str, Any] | None = None) -> dict[str, Any]:
    data = None
    headers = {"Authorization": authorization, "Accept": "application/json"}
    if body is not None:
        data = json.dumps(body, separators=(",", ":")).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with opener.open(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
            if response.geturl() != url:
                raise PreflightBlocked("redirect_rejected")
            payload = response.read(MAX_RESPONSE_BYTES + 1)
    except urllib.error.HTTPError as exc:
        raise PreflightBlocked(f"provider_http_{exc.code}") from None
    except (urllib.error.URLError, TimeoutError, ssl.SSLError) as exc:
        raise PreflightBlocked("provider_transport_error") from exc
    if len(payload) > MAX_RESPONSE_BYTES:
        raise PreflightBlocked("provider_response_too_large")
    try:
        parsed = json.loads(payload)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise PreflightBlocked("invalid_provider_response") from exc
    if not isinstance(parsed, dict):
        raise PreflightBlocked("invalid_provider_response")
    return parsed


def require_string(mapping: dict[str, Any], key: str) -> str:
    value = mapping.get(key)
    if not isinstance(value, str) or not value:
        raise PreflightBlocked("invalid_provider_response")
    return value


def require_dict(mapping: dict[str, Any], key: str) -> dict[str, Any]:
    value = mapping.get(key)
    if not isinstance(value, dict):
        raise PreflightBlocked("invalid_provider_response")
    return value


def require_list(mapping: dict[str, Any], key: str) -> list[Any]:
    value = mapping.get(key)
    if not isinstance(value, list):
        raise PreflightBlocked("invalid_provider_response")
    return value


def run_bounded_doppler(argv: tuple[str, ...], failure_code: str) -> bytearray:
    try:
        process = subprocess.Popen(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=minimal_environment(),
            start_new_session=True,
        )
    except OSError as exc:
        raise PreflightBlocked("doppler_cli_unavailable") from exc
    assert process.stdout is not None
    assert process.stderr is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ, "stdout")
    selector.register(process.stderr, selectors.EVENT_READ, "stderr")
    captured = {"stdout": bytearray(), "stderr": bytearray()}
    deadline = time.monotonic() + DOPPLER_TIMEOUT_SECONDS
    try:
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise PreflightBlocked("doppler_timeout")
            events = selector.select(remaining)
            if not events:
                raise PreflightBlocked("doppler_timeout")
            for key, _ in events:
                chunk = os.read(key.fileobj.fileno(), 8192)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                stream = captured[key.data]
                stream.extend(chunk)
                if len(stream) > MAX_DOPPLER_OUTPUT_BYTES:
                    raise PreflightBlocked("doppler_output_too_large")
        status = process.wait(timeout=1)
    except PreflightBlocked:
        process.kill()
        process.wait()
        for stream in captured.values():
            stream[:] = b"\x00" * len(stream)
            stream.clear()
        raise
    except subprocess.TimeoutExpired as exc:
        process.kill()
        process.wait()
        for stream in captured.values():
            stream[:] = b"\x00" * len(stream)
            stream.clear()
        raise PreflightBlocked("doppler_timeout") from exc
    finally:
        selector.close()
    if status != 0:
        for stream in captured.values():
            stream[:] = b"\x00" * len(stream)
            stream.clear()
        raise PreflightBlocked(failure_code)
    captured["stderr"][:] = b"\x00" * len(captured["stderr"])
    captured["stderr"].clear()
    return captured["stdout"]


def read_admin_secret(name: str) -> bytearray:
    value = run_bounded_doppler(
        doppler_secret_argv(name),
        "doppler_admin_secret_lookup_failed",
    )
    if value.endswith(b"\n"):
        del value[-1:]
        if value.endswith(b"\r"):
            del value[-1:]
    if (
        not value
        or len(value) > MAX_CREDENTIAL_BYTES
        or any(marker in value for marker in (b"\n", b"\r", b"\x00"))
    ):
        value[:] = b"\x00" * len(value)
        value.clear()
        raise PreflightBlocked("invalid_admin_secret_value")
    return value


def read_doppler_names() -> set[str]:
    captured = run_bounded_doppler(
        DOPPLER_NAMES_ARGV,
        "doppler_metadata_failed",
    )
    try:
        output = json.loads(captured)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise PreflightBlocked("invalid_doppler_output") from exc
    finally:
        captured[:] = b"\x00" * len(captured)
        captured.clear()
    if not isinstance(output, dict):
        raise PreflightBlocked("invalid_doppler_output")
    if any(value != {} for value in output.values()):
        raise PreflightBlocked("doppler_values_exposed")
    if not all(isinstance(name, str) for name in output):
        raise PreflightBlocked("invalid_doppler_output")
    return set(output)


def perform_preflight(key_id: bytes | bytearray, application_key: bytes | bytearray,
                      opener: Any | None = None,
                      doppler_names: set[str] | None = None,
                      observations: dict[str, Any] | None = None) -> dict[str, Any]:
    client = opener if opener is not None else build_opener()
    checks = observations if observations is not None else {}
    checks["no_mutation_endpoint_attempted"] = True
    basic_source = bytearray(key_id)
    basic_source.extend(b":")
    basic_source.extend(application_key)
    basic_value = bytearray(base64.b64encode(basic_source))
    basic_source[:] = b"\x00" * len(basic_source)
    basic_source.clear()
    try:
        authorization = request_json(
            client,
            "POST",
            AUTH_URL,
            "Basic " + basic_value.decode("ascii"),
            {},
        )
    finally:
        basic_value[:] = b"\x00" * len(basic_value)
        basic_value.clear()
    account_id = require_string(authorization, "accountId")
    account_token = require_string(authorization, "authorizationToken")
    checks["authentication_succeeds"] = True
    api_info = require_dict(authorization, "apiInfo")
    storage_api = require_dict(api_info, "storageApi")
    allowed = require_dict(storage_api, "allowed")
    capabilities = set(require_list(allowed, "capabilities"))
    present_required_capabilities = sorted(REQUIRED_AUTH_CAPABILITIES & capabilities)
    missing_required_capabilities = sorted(REQUIRED_AUTH_CAPABILITIES - capabilities)
    if missing_required_capabilities:
        raise PreflightBlocked(
            "insufficient_management_authority",
            {
                "authentication_succeeds": True,
                "required_key_management_capabilities_present": False,
                "present_required_management_capabilities": present_required_capabilities,
                "missing_required_management_capabilities": missing_required_capabilities,
            },
        )
    checks["required_key_management_capabilities_present"] = True
    api_base = validate_api_base(require_string(storage_api, "apiUrl"))
    validate_s3_url(require_string(storage_api, "s3ApiUrl"))
    checks["returned_api_and_s3_urls_pass_allowlist"] = True

    token_header = account_token
    rejected: list[dict[str, Any]] = []
    replacement: list[dict[str, Any]] = []
    start_key_id: str | None = None
    seen_page_ids: set[str] = set()
    for _ in range(100):
        key_request: dict[str, Any] = {"accountId": account_id}
        if start_key_id is not None:
            key_request["startApplicationKeyId"] = start_key_id
        keys = request_json(
            client,
            "POST",
            f"{api_base}/b2api/v4/b2_list_keys",
            token_header,
            key_request,
        )
        for item in require_list(keys, "keys"):
            if not isinstance(item, dict):
                raise PreflightBlocked("invalid_provider_response")
            if item.get("keyName") == REJECTED_KEY_NAME:
                rejected.append(item)
            elif item.get("keyName") == REPLACEMENT_KEY_NAME:
                replacement.append(item)
        next_key_id = keys.get("nextApplicationKeyId")
        if next_key_id is None:
            break
        if (
            not isinstance(next_key_id, str)
            or not next_key_id
            or next_key_id in seen_page_ids
        ):
            raise PreflightBlocked("invalid_key_pagination")
        seen_page_ids.add(next_key_id)
        start_key_id = next_key_id
    else:
        raise PreflightBlocked("key_listing_page_limit")
    if len(rejected) != 1:
        raise PreflightBlocked("rejected_key_identity_mismatch")
    checks["rejected_key_present"] = True
    if replacement:
        raise PreflightBlocked("replacement_key_already_exists")
    checks["replacement_key_absent"] = True
    rejected_caps = set(require_list(rejected[0], "capabilities"))
    if not REQUIRED_FILE_CAPABILITIES <= rejected_caps:
        raise PreflightBlocked("rejected_key_file_capabilities_changed")
    if not PROHIBITED_RESIDUE_CAPABILITIES <= rejected_caps:
        raise PreflightBlocked("rejected_key_residue_changed")
    checks["rejected_key_prohibited_capabilities_still_present"] = True

    buckets = request_json(
        client,
        "POST",
        f"{api_base}/b2api/v4/b2_list_buckets",
        token_header,
        {"accountId": account_id, "bucketTypes": ["allPrivate"]},
    )
    bucket_records = require_list(buckets, "buckets")
    exact_buckets = [item for item in bucket_records if isinstance(item, dict) and item.get("bucketName") == EXPECTED_BUCKET_NAME]
    if len(exact_buckets) != 1:
        raise PreflightBlocked("bucket_identity_mismatch")
    bucket = exact_buckets[0]
    if bucket.get("bucketId") != EXPECTED_BUCKET_ID or bucket.get("bucketType") != "allPrivate":
        raise PreflightBlocked("bucket_policy_mismatch")
    checks["exact_bucket_identity_private_region_and_endpoint"] = True

    files = request_json(
        client,
        "POST",
        f"{api_base}/b2api/v4/b2_list_file_names",
        token_header,
        {"bucketId": EXPECTED_BUCKET_ID, "maxFileCount": 1},
    )
    if require_list(files, "files"):
        raise PreflightBlocked("bucket_not_empty")
    checks["exact_bucket_current_file_count_zero"] = True

    names = doppler_names if doppler_names is not None else read_doppler_names()
    checks["exact_doppler_config_present"] = True
    if not CANONICAL_SECRET_NAMES <= names:
        raise PreflightBlocked("canonical_doppler_names_missing")
    checks["canonical_secret_names_present_without_values"] = True
    if CANDIDATE_SECRET_NAMES & names:
        raise PreflightBlocked("candidate_doppler_name_collision")
    checks["candidate_secret_names_absent"] = True

    return checks


def write_evidence(root_fd: int, bundle_sha256: str, result: str, checks: dict[str, Any],
                   error_class: str | None = None) -> None:
    document: dict[str, Any] = {
        "schema_version": 1,
        "operation": OPERATION_ID,
        "bundle_sha256": bundle_sha256,
        "result": result,
        "checks": checks,
        "credential_source": "doppler_prd_b2_admin_in_memory",
        "credential_values_retained": False,
        "secrets_recorded": False,
        "raw_responses_recorded": False,
        "mutation_attempted": False,
    }
    if error_class is not None:
        document["error_class"] = error_class
    payload = (json.dumps(document, indent=2, sort_keys=True) + "\n").encode("utf-8")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    evidence_fd = os.open("result.json", flags, 0o600, dir_fd=root_fd)
    try:
        os.write(evidence_fd, payload)
        os.fsync(evidence_fd)
    finally:
        os.close(evidence_fd)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-root", required=True, type=Path)
    parser.add_argument("--bundle-sha256", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not re.fullmatch(r"[0-9a-f]{64}", args.bundle_sha256):
        print("result=invalid_bundle_hash", file=sys.stderr)
        return 64
    try:
        root_fd = validate_evidence_root(args.evidence_root)
    except PreflightBlocked:
        print("result=blocked error_class=invalid_evidence_root", file=sys.stderr)
        return 2
    checks: dict[str, Any] = {}
    key_id: bytearray | None = None
    application_key: bytearray | None = None
    try:
        key_id = read_admin_secret(ADMIN_KEY_ID_NAME)
        application_key = read_admin_secret(ADMIN_KEY_VALUE_NAME)
        checks["administrator_doppler_secret_names_resolve"] = True
        checks = perform_preflight(
            key_id,
            application_key,
            observations=checks,
        )
        write_evidence(root_fd, args.bundle_sha256, "passed", checks)
        print(f"result=passed evidence_root={args.evidence_root}")
        return 0
    except PreflightBlocked as exc:
        checks.update(exc.observations)
        write_evidence(root_fd, args.bundle_sha256, "blocked", checks, exc.code)
        print(f"result=blocked evidence_root={args.evidence_root}", file=sys.stderr)
        return 2
    except Exception:
        write_evidence(root_fd, args.bundle_sha256, "internal_error", checks, "internal_error")
        print(f"result=internal_error evidence_root={args.evidence_root}", file=sys.stderr)
        return 1
    finally:
        for secret in (key_id, application_key):
            if isinstance(secret, bytearray):
                secret[:] = b"\x00" * len(secret)
                secret.clear()
        os.close(root_fd)


if __name__ == "__main__":
    raise SystemExit(main())
