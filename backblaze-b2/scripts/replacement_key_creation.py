#!/usr/bin/env python3
"""Create one exact B2 replacement key and deliver it to protected FIFOs."""

from __future__ import annotations

import argparse
import base64
import errno
import json
import os
import re
import stat
import sys
import time
from pathlib import Path
from typing import Any, Callable

import capability_remediation_preflight as preflight

OPERATION_ID = "backblaze-b2-replacement-key-creation-v1"
REPLACEMENT_KEY_NAME = "homelab-nautobot-restic-prd-v2"
EXPECTED_BUCKET_ID = "4d1bda761665474eaf030b18"
EXPECTED_CAPABILITIES = {
    "listAllBucketNames",
    "listBuckets",
    "readBuckets",
    "listFiles",
    "readFiles",
    "writeFiles",
    "deleteFiles",
}
EXPECTED_OPTIONS = ["s3"]
MAX_SECRET_BYTES = 4096
FIFO_CONNECT_TIMEOUT_SECONDS = 10


class CreationBlocked(Exception):
    """A bounded creation failure with a sanitized classification."""

    def __init__(
        self,
        code: str,
        observations: dict[str, Any] | None = None,
        mutation_attempted: bool = False,
    ):
        self.code = code if re.fullmatch(r"[a-z0-9_]+", code) else "invalid_error_class"
        self.observations = observations if observations is not None else {}
        self.mutation_attempted = mutation_attempted
        super().__init__(self.code)


def validate_root(path: Path) -> int:
    if (
        not path.is_absolute()
        or path.parent != Path("/tmp")
        or not re.fullmatch(
            r"backblaze-b2-replacement-key-creation\.[A-Za-z0-9_]+", path.name
        )
    ):
        raise CreationBlocked("invalid_evidence_root")
    try:
        info = path.lstat()
    except OSError as exc:
        raise CreationBlocked("invalid_evidence_root") from exc
    if (
        not stat.S_ISDIR(info.st_mode)
        or stat.S_ISLNK(info.st_mode)
        or info.st_uid != os.getuid()
        or stat.S_IMODE(info.st_mode) != 0o700
    ):
        raise CreationBlocked("unsafe_evidence_root")
    flags = os.O_RDONLY | os.O_DIRECTORY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        return os.open(path, flags)
    except OSError as exc:
        raise CreationBlocked("invalid_evidence_root") from exc


def authorize_account(
    key_id: bytearray,
    application_key: bytearray,
    opener: Any,
) -> tuple[str, str, str]:
    source = bytearray(key_id)
    source.extend(b":")
    source.extend(application_key)
    basic = bytearray(base64.b64encode(source))
    source[:] = b"\x00" * len(source)
    source.clear()
    try:
        response = preflight.request_json(
            opener,
            "POST",
            preflight.AUTH_URL,
            "Basic " + basic.decode("ascii"),
            {},
        )
    except preflight.PreflightBlocked as exc:
        raise CreationBlocked(exc.code) from exc
    finally:
        basic[:] = b"\x00" * len(basic)
        basic.clear()
    account_id = preflight.require_string(response, "accountId")
    token = preflight.require_string(response, "authorizationToken")
    storage_api = preflight.require_dict(preflight.require_dict(response, "apiInfo"), "storageApi")
    allowed = preflight.require_dict(storage_api, "allowed")
    capabilities = set(preflight.require_list(allowed, "capabilities"))
    if not preflight.REQUIRED_AUTH_CAPABILITIES <= capabilities:
        raise CreationBlocked("insufficient_management_authority")
    api_base = preflight.validate_api_base(preflight.require_string(storage_api, "apiUrl"))
    preflight.validate_s3_url(preflight.require_string(storage_api, "s3ApiUrl"))
    return account_id, token, api_base


def exact_create_body(account_id: str) -> dict[str, Any]:
    return {
        "accountId": account_id,
        "capabilities": sorted(EXPECTED_CAPABILITIES),
        "keyName": REPLACEMENT_KEY_NAME,
        "bucketIds": [EXPECTED_BUCKET_ID],
    }


def validate_replacement_metadata(item: dict[str, Any]) -> None:
    if set(item) & {"applicationKey"}:
        raise CreationBlocked("secret_present_in_metadata_readback", mutation_attempted=True)
    if item.get("keyName") != REPLACEMENT_KEY_NAME:
        raise CreationBlocked("replacement_name_mismatch", mutation_attempted=True)
    if item.get("bucketIds") != [EXPECTED_BUCKET_ID]:
        raise CreationBlocked("replacement_bucket_scope_mismatch", mutation_attempted=True)
    if item.get("namePrefix") is not None:
        raise CreationBlocked("replacement_prefix_scope_mismatch", mutation_attempted=True)
    capabilities = item.get("capabilities")
    if not isinstance(capabilities, list) or set(capabilities) != EXPECTED_CAPABILITIES:
        raise CreationBlocked("replacement_capability_mismatch", mutation_attempted=True)
    if item.get("expirationTimestamp") is not None:
        raise CreationBlocked("replacement_expiration_present", mutation_attempted=True)
    if item.get("options") != EXPECTED_OPTIONS:
        raise CreationBlocked("replacement_s3_option_mismatch", mutation_attempted=True)


def write_owned_fifo(root_fd: int, name: str, value: bytearray) -> None:
    if "/" in name or name in {"", ".", ".."}:
        raise CreationBlocked("invalid_fifo_name", mutation_attempted=True)
    if not value or len(value) > MAX_SECRET_BYTES:
        raise CreationBlocked("invalid_provider_secret", mutation_attempted=True)
    try:
        before = os.stat(name, dir_fd=root_fd, follow_symlinks=False)
    except OSError as exc:
        raise CreationBlocked("invalid_secret_fifo", mutation_attempted=True) from exc
    if (
        not stat.S_ISFIFO(before.st_mode)
        or before.st_uid != os.getuid()
        or stat.S_IMODE(before.st_mode) != 0o600
    ):
        raise CreationBlocked("unsafe_secret_fifo", mutation_attempted=True)
    flags = os.O_WRONLY | os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    deadline = time.monotonic() + FIFO_CONNECT_TIMEOUT_SECONDS
    while True:
        try:
            fifo_fd = os.open(name, flags, dir_fd=root_fd)
            break
        except OSError as exc:
            if exc.errno != errno.ENXIO or time.monotonic() >= deadline:
                raise CreationBlocked(
                    "secret_delivery_failed",
                    mutation_attempted=True,
                ) from exc
            time.sleep(0.05)
    try:
        opened = os.fstat(fifo_fd)
        if (before.st_dev, before.st_ino) != (opened.st_dev, opened.st_ino):
            raise CreationBlocked("secret_fifo_replaced", mutation_attempted=True)
        view = memoryview(value)
        written = 0
        while written < len(view):
            count = os.write(fifo_fd, view[written:])
            if count <= 0:
                raise CreationBlocked("secret_delivery_failed", mutation_attempted=True)
            written += count
    finally:
        os.close(fifo_fd)


def list_exact_keys(
    opener: Any,
    api_base: str,
    token: str,
    account_id: str,
    mutation_attempted: bool,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    rejected: list[dict[str, Any]] = []
    replacement: list[dict[str, Any]] = []
    start_key_id: str | None = None
    seen: set[str] = set()
    for _ in range(100):
        body: dict[str, Any] = {"accountId": account_id}
        if start_key_id is not None:
            body["startApplicationKeyId"] = start_key_id
        response = preflight.request_json(
            opener,
            "POST",
            f"{api_base}/b2api/v4/b2_list_keys",
            token,
            body,
        )
        for item in preflight.require_list(response, "keys"):
            if not isinstance(item, dict):
                raise CreationBlocked(
                    "invalid_provider_response",
                    mutation_attempted=mutation_attempted,
                )
            if item.get("keyName") == preflight.REJECTED_KEY_NAME:
                rejected.append(item)
            elif item.get("keyName") == REPLACEMENT_KEY_NAME:
                replacement.append(item)
        next_id = response.get("nextApplicationKeyId")
        if next_id is None:
            return rejected, replacement
        if not isinstance(next_id, str) or not next_id or next_id in seen:
            raise CreationBlocked(
                "invalid_key_pagination",
                mutation_attempted=mutation_attempted,
            )
        seen.add(next_id)
        start_key_id = next_id
    raise CreationBlocked(
        "key_listing_page_limit",
        mutation_attempted=mutation_attempted,
    )


def key_metadata_fingerprint(item: dict[str, Any]) -> tuple[Any, ...]:
    capabilities = item.get("capabilities")
    bucket_ids = item.get("bucketIds")
    options = item.get("options")
    if not isinstance(capabilities, list):
        raise CreationBlocked("invalid_provider_response")
    if bucket_ids is not None and not isinstance(bucket_ids, list):
        raise CreationBlocked("invalid_provider_response")
    if options is not None and not isinstance(options, list):
        raise CreationBlocked("invalid_provider_response")
    return (
        item.get("applicationKeyId"),
        item.get("keyName"),
        tuple(sorted(capabilities)),
        None if bucket_ids is None else tuple(bucket_ids),
        item.get("namePrefix"),
        item.get("expirationTimestamp"),
        None if options is None else tuple(options),
    )


SecretSink = Callable[[bytearray, bytearray], None]


def perform_creation(
    key_id: bytearray,
    application_key: bytearray,
    secret_sink: SecretSink,
    opener: Any | None = None,
    doppler_names: set[str] | None = None,
    observations: dict[str, Any] | None = None,
) -> dict[str, Any]:
    client = opener if opener is not None else preflight.build_opener()
    checks = observations if observations is not None else {}
    try:
        preflight.perform_preflight(
            key_id,
            application_key,
            opener=client,
            doppler_names=doppler_names,
            observations=checks,
        )
    except preflight.PreflightBlocked as exc:
        checks.update(exc.observations)
        raise CreationBlocked(exc.code, checks) from exc
    checks.pop("no_mutation_endpoint_attempted", None)
    checks["predecessor_preflight_still_matches"] = True

    try:
        account_id, token, api_base = authorize_account(key_id, application_key, client)
    except (preflight.PreflightBlocked, CreationBlocked) as exc:
        code = exc.code if hasattr(exc, "code") else "provider_authorization_failed"
        raise CreationBlocked(code, checks) from exc
    checks["creation_authorization_refreshed"] = True
    try:
        rejected_before, replacement_before = list_exact_keys(
            client,
            api_base,
            token,
            account_id,
            mutation_attempted=False,
        )
    except preflight.PreflightBlocked as exc:
        raise CreationBlocked(exc.code, checks) from exc
    if len(rejected_before) != 1:
        raise CreationBlocked("rejected_key_identity_mismatch", checks)
    if replacement_before:
        raise CreationBlocked("replacement_key_already_exists", checks)
    rejected_fingerprint = key_metadata_fingerprint(rejected_before[0])
    checks["immediate_pre_create_key_residue_matches"] = True
    create_body = exact_create_body(account_id)
    checks["exact_create_request_prepared"] = True
    checks["provider_create_attempted"] = True
    try:
        created = preflight.request_json(
            client,
            "POST",
            f"{api_base}/b2api/v4/b2_create_key",
            token,
            create_body,
        )
    except preflight.PreflightBlocked as exc:
        raise CreationBlocked(exc.code, checks, mutation_attempted=True) from exc
    checks["provider_create_response_received"] = True

    raw_id = created.pop("applicationKeyId", None)
    raw_value = created.pop("applicationKey", None)
    if not isinstance(raw_id, str) or not isinstance(raw_value, str):
        raise CreationBlocked("provider_secret_fields_missing", checks, mutation_attempted=True)
    key_id_buffer = bytearray(raw_id.encode("utf-8"))
    key_value_buffer = bytearray(raw_value.encode("utf-8"))
    raw_id = ""
    raw_value = ""
    try:
        validate_replacement_metadata(created)
        checks["create_response_metadata_exact"] = True
        secret_sink(key_id_buffer, key_value_buffer)
        checks["provider_values_delivered_to_protected_writer"] = True
    except CreationBlocked:
        raise
    except Exception as exc:
        raise CreationBlocked("secret_delivery_failed", checks, mutation_attempted=True) from exc
    finally:
        key_id_buffer[:] = b"\x00" * len(key_id_buffer)
        key_id_buffer.clear()
        key_value_buffer[:] = b"\x00" * len(key_value_buffer)
        key_value_buffer.clear()

    try:
        rejected, replacement = list_exact_keys(
            client,
            api_base,
            token,
            account_id,
            mutation_attempted=True,
        )
    except preflight.PreflightBlocked as exc:
        raise CreationBlocked(exc.code, checks, mutation_attempted=True) from exc
    checks["post_create_key_listing_received"] = True
    if len(rejected) != 1:
        raise CreationBlocked("rejected_key_identity_mismatch", checks, mutation_attempted=True)
    if len(replacement) != 1:
        raise CreationBlocked("replacement_key_identity_mismatch", checks, mutation_attempted=True)
    validate_replacement_metadata(replacement[0])
    if key_metadata_fingerprint(rejected[0]) != rejected_fingerprint:
        raise CreationBlocked("rejected_key_metadata_changed", checks, mutation_attempted=True)
    checks["exact_provider_key_metadata_readback"] = True
    checks["rejected_key_unchanged"] = True
    checks["no_object_mutation_or_consumer_contact"] = True
    return checks


def write_evidence(
    root_fd: int,
    bundle_sha256: str,
    result: str,
    checks: dict[str, Any],
    error_class: str | None,
    mutation_attempted: bool,
) -> None:
    document = {
        "schema_version": 1,
        "operation": OPERATION_ID,
        "bundle_sha256": bundle_sha256,
        "result": result,
        "checks": checks,
        "error_class": error_class,
        "provider_create_attempted": mutation_attempted,
        "provider_or_doppler_secret_values_retained": False,
        "raw_provider_responses_retained": False,
        "automatic_retry_performed": False,
        "automatic_cleanup_performed": False,
    }
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open("provider-result.json", flags, 0o600, dir_fd=root_fd)
    try:
        os.write(fd, json.dumps(document, sort_keys=True).encode("utf-8") + b"\n")
        os.fsync(fd)
    finally:
        os.close(fd)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-root", type=Path, required=True)
    parser.add_argument("--key-id-fifo", required=True)
    parser.add_argument("--key-value-fifo", required=True)
    parser.add_argument("--bundle-sha256", required=True)
    return parser.parse_args()


def main() -> int:
    os.umask(0o077)
    args = parse_args()
    if not re.fullmatch(r"[0-9a-f]{64}", args.bundle_sha256):
        print("result=blocked error_class=invalid_bundle_hash", file=sys.stderr)
        return 64
    root_fd = -1
    key_id: bytearray | None = None
    application_key: bytearray | None = None
    checks: dict[str, Any] = {}
    result = "blocked"
    error_class: str | None = None
    mutation_attempted = False
    try:
        root_fd = validate_root(args.evidence_root)
        key_id = preflight.read_admin_secret(preflight.ADMIN_KEY_ID_NAME)
        application_key = preflight.read_admin_secret(preflight.ADMIN_KEY_VALUE_NAME)
        checks["administrator_doppler_secret_names_resolve"] = True

        def sink(candidate_id: bytearray, candidate_value: bytearray) -> None:
            write_owned_fifo(root_fd, args.key_id_fifo, candidate_id)
            write_owned_fifo(root_fd, args.key_value_fifo, candidate_value)

        checks = perform_creation(
            key_id,
            application_key,
            sink,
            observations=checks,
        )
        mutation_attempted = True
        result = "created_and_delivered"
    except CreationBlocked as exc:
        checks.update(exc.observations)
        error_class = exc.code
        mutation_attempted = exc.mutation_attempted or checks.get(
            "provider_create_attempted", False
        )
        result = "manual_intervention" if mutation_attempted else "blocked"
    except preflight.PreflightBlocked as exc:
        checks.update(exc.observations)
        error_class = exc.code
    except Exception:
        error_class = "internal_error"
        mutation_attempted = checks.get("provider_create_attempted", False)
        result = "manual_intervention" if mutation_attempted else "internal_error"
    finally:
        for secret in (key_id, application_key):
            if isinstance(secret, bytearray):
                secret[:] = b"\x00" * len(secret)
                secret.clear()
        if root_fd >= 0:
            write_evidence(
                root_fd,
                args.bundle_sha256,
                result,
                checks,
                error_class,
                mutation_attempted,
            )
            os.close(root_fd)
    print(f"result={result}" + ("" if error_class is None else f" error_class={error_class}"))
    return 0 if result == "created_and_delivered" else 2


if __name__ == "__main__":
    raise SystemExit(main())
