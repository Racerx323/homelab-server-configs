#!/usr/bin/env python3
"""Hash-bound launcher for the Backblaze B2 S3 compatibility operation."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import secrets
import signal
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Callable

import yaml

sys.dont_write_bytecode = True

import s3_compatibility_probe as probe

ROOT = Path(__file__).resolve().parents[2]
OPERATION_PATH = ROOT / "backblaze-b2/manifests/operation.yaml"
OPERATION_SCHEMA = ROOT / "backblaze-b2/schemas/operation.schema.json"
EXPECTED_OPERATION_ID = "backblaze-b2-s3-compatibility-v1"
BUNDLE_DOMAIN = "backblaze-b2-s3-compatibility-bundle-v1"
BUNDLE_FILES = (
    "backblaze-b2/docs/B2_ARCHITECTURE.md",
    "backblaze-b2/docs/CAPABILITY_REMEDIATION_DECISION.md",
    "backblaze-b2/docs/S3_COMPATIBILITY_PROBE.md",
    "backblaze-b2/manifests/desired-state.yaml",
    "backblaze-b2/manifests/operation.yaml",
    "backblaze-b2/schemas/desired-state.schema.json",
    "backblaze-b2/schemas/operation.schema.json",
    "backblaze-b2/schemas/s3-compatibility-probe.schema.json",
    "backblaze-b2/scripts/s3_compatibility_probe.py",
    "backblaze-b2/scripts/run_s3_compatibility_probe.py",
    "backblaze-b2/tests/s3-compatibility-probe-regression.py",
    "backblaze-b2/tests/s3-compatibility-launcher-regression.py",
)


class LauncherBlocked(Exception):
    def __init__(self, code: str, status: int = 69):
        self.code = code if re.fullmatch(r"[a-z0-9_]+", code) else "invalid_error_class"
        self.status = status
        super().__init__(self.code)


class LauncherInterrupted(Exception):
    """Raised by bounded signal handlers after the evidence root exists."""


def load_operation() -> dict[str, Any]:
    document = yaml.safe_load(OPERATION_PATH.read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        raise LauncherBlocked("invalid_operation")
    return document


def validate_operation(runner: Callable[..., subprocess.CompletedProcess[Any]] = subprocess.run) -> dict[str, Any]:
    try:
        result = runner(
            (
                "check-jsonschema", "--schemafile", str(OPERATION_SCHEMA),
                str(OPERATION_PATH),
            ),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            timeout=30,
        )
    except subprocess.TimeoutExpired as exc:
        raise LauncherBlocked("operation_validator_timeout") from exc
    except OSError as exc:
        raise LauncherBlocked("operation_validator_unavailable") from exc
    if result.returncode != 0:
        raise LauncherBlocked("operation_schema_invalid")
    document = load_operation()
    operation = document.get("operation")
    if not isinstance(operation, dict) or operation.get("id") != EXPECTED_OPERATION_ID:
        raise LauncherBlocked("active_operation_mismatch")
    return document


def bundle_file_hashes() -> list[tuple[str, str]]:
    hashes: list[tuple[str, str]] = []
    for relative in BUNDLE_FILES:
        path = ROOT / relative
        if not path.is_file() or path.is_symlink():
            raise LauncherBlocked("invalid_bundle_input")
        hashes.append((hashlib.sha256(path.read_bytes()).hexdigest(), relative))
    return hashes


def bundle_hash(file_hashes: list[tuple[str, str]] | None = None) -> str:
    rows = file_hashes if file_hashes is not None else bundle_file_hashes()
    payload = BUNDLE_DOMAIN + "\n"
    payload += "".join(f"{digest}  {relative}\n" for digest, relative in rows)
    return hashlib.sha256(payload.encode()).hexdigest()


def operation_blockers(document: dict[str, Any]) -> list[str]:
    authorization = document.get("authorization")
    blockers = authorization.get("blockers") if isinstance(authorization, dict) else None
    if not isinstance(blockers, list) or not all(isinstance(item, str) for item in blockers):
        return ["invalid_operation_blockers"]
    return blockers


def require_execute_ready(document: dict[str, Any], authorized_hash: str,
                          calculated_hash: str) -> None:
    operation = document["operation"]
    implementation = document.get("implementation", {})
    blockers = operation_blockers(document)
    if (
        operation.get("authorization_ready") is not True
        or implementation.get("live_execution_enabled") is not True
        or blockers
    ):
        raise LauncherBlocked("operation_not_ready")
    if not re.fullmatch(r"[0-9a-f]{64}", authorized_hash):
        raise LauncherBlocked("invalid_authorized_hash", 66)
    if authorized_hash != calculated_hash:
        raise LauncherBlocked("bundle_hash_mismatch", 66)


def require_preflight_authorized(document: dict[str, Any]) -> None:
    preflight = document.get("preflight")
    if (
        not isinstance(preflight, dict)
        or preflight.get("execution_authorized") is not True
        or preflight.get("mutation_authorized") is not False
        or preflight.get("old_key_fallback_available") is not False
        or preflight.get("old_key_fallback_attempt_authorized") is not False
    ):
        raise LauncherBlocked("preflight_not_authorized")


def _open_exclusive(root_fd: int, name: str) -> int:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    return os.open(name, flags, 0o600, dir_fd=root_fd)


def prepare_evidence(file_hashes: list[tuple[str, str]], calculated_hash: str) -> tuple[Path, int]:
    root = Path(tempfile.mkdtemp(prefix="backblaze-b2-s3-compatibility.", dir="/tmp"))
    root.chmod(0o700)
    root_fd = probe.validate_evidence_root(root)
    documents = {
        "bundle-files.sha256": "".join(
            f"{digest}  {relative}\n" for digest, relative in file_hashes
        ).encode(),
        "bundle.sha256": f"{calculated_hash}\n".encode(),
    }
    for name, payload in documents.items():
        fd = _open_exclusive(root_fd, name)
        try:
            os.write(fd, payload)
            os.fsync(fd)
        finally:
            os.close(fd)
    return root, root_fd


def read_client_evidence(root: Path) -> dict[str, Any]:
    path = root / "result.json"
    try:
        info = path.lstat()
        if (
            not stat.S_ISREG(info.st_mode)
            or stat.S_ISLNK(info.st_mode)
            or info.st_uid != os.getuid()
            or stat.S_IMODE(info.st_mode) != 0o600
            or info.st_size > probe.MAX_RESPONSE_BYTES
        ):
            return {}
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return {}
    return document if isinstance(document, dict) else {}


def classify(mode: str, client_result: str, evidence: dict[str, Any]) -> tuple[str, str]:
    if not evidence:
        if mode == "preflight":
            return "preflight", "blocked"
        return "cleanup", "manual_intervention"
    mutation = evidence.get("mutation") if isinstance(evidence.get("mutation"), dict) else {}
    cleanup = evidence.get("cleanup") if isinstance(evidence.get("cleanup"), dict) else {}
    put_attempted = mutation.get("put_attempted") is True
    delete_attempted = mutation.get("delete_attempted") is True
    absence_proven = cleanup.get("absence_proven") is True
    if mode == "preflight":
        if client_result == "preflight_passed" and not put_attempted:
            return "preflight", "passed"
        if put_attempted:
            return "preflight", "manual_intervention"
        return "preflight", "blocked"
    if client_result == "passed" and put_attempted and delete_attempted and absence_proven:
        return "acceptance", "completed"
    if client_result == "blocked" and not put_attempted:
        return "pre_mutation", "blocked"
    if client_result == "blocked" and put_attempted and delete_attempted and absence_proven:
        return "cleanup", "rolled_back"
    return "cleanup", "manual_intervention"


def write_terminal_evidence(root_fd: int, root: Path, calculated_hash: str,
                            mode: str, client_result: str) -> dict[str, Any]:
    evidence = read_client_evidence(root)
    evidence_result = evidence.get("result")
    result_matches = evidence_result == client_result or (
        client_result in {"interrupted", "internal_error"}
        and evidence_result == "running"
    )
    if (
        evidence.get("operation") != EXPECTED_OPERATION_ID
        or evidence.get("bundle_sha256") != calculated_hash
        or not result_matches
        or evidence.get("credential_values_retained") is not False
        or evidence.get("provider_response_bodies_retained") is not False
    ):
        evidence = {}
    phase, result = classify(mode, client_result, evidence)
    client_path = root / "result.json"
    client_hash = hashlib.sha256(client_path.read_bytes()).hexdigest() if evidence else None
    mutation = evidence.get("mutation") if isinstance(evidence.get("mutation"), dict) else {}
    cleanup = evidence.get("cleanup") if isinstance(evidence.get("cleanup"), dict) else {}
    document = {
        "schema_version": 1,
        "operation": EXPECTED_OPERATION_ID,
        "bundle_sha256": calculated_hash,
        "mode": mode,
        "terminal_phase": phase,
        "result": result,
        "client_evidence_sha256": client_hash,
        "put_attempted": mutation.get("put_attempted") is True,
        "delete_attempted": mutation.get("delete_attempted") is True,
        "absence_proven": cleanup.get("absence_proven") is True,
        "residue_possible": cleanup.get("residue_possible") is True,
        "old_key_fallback_attempted": False,
        "credential_values_or_identifiers_retained": False,
        "automatic_retry_performed": False,
    }
    fd = _open_exclusive(root_fd, "terminal-result.json")
    try:
        os.write(fd, (json.dumps(document, sort_keys=True) + "\n").encode())
        os.fsync(fd)
    finally:
        os.close(fd)
    return document


def run(mode: str, authorized_hash: str | None = None,
        client: Callable[..., str] = probe.execute) -> tuple[int, Path]:
    document = validate_operation()
    if mode == "preflight":
        require_preflight_authorized(document)
    elif mode != "execute":
        raise LauncherBlocked("invalid_execution_mode", 64)
    file_hashes = bundle_file_hashes()
    calculated_hash = bundle_hash(file_hashes)
    if mode == "execute":
        require_execute_ready(document, authorized_hash or "", calculated_hash)

    root, root_fd = prepare_evidence(file_hashes, calculated_hash)
    client_result = "internal_error"
    previous_handlers: dict[int, Any] = {}

    def interrupt_handler(_signum: int, _frame: Any) -> None:
        raise LauncherInterrupted()

    try:
        for signum in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
            previous_handlers[signum] = signal.signal(signum, interrupt_handler)
        run_id = secrets.token_hex(16)
        try:
            client_result = client(root, calculated_hash, run_id, mode)
        except probe.ProbeBlocked:
            client_result = "preflight_blocked" if mode == "preflight" else "blocked"
        except (KeyboardInterrupt, LauncherInterrupted):
            client_result = "interrupted"
        except Exception:
            client_result = "internal_error"
        terminal = write_terminal_evidence(root_fd, root, calculated_hash, mode, client_result)
    finally:
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
        os.close(root_fd)
    status = 0 if terminal["result"] in {"passed", "completed"} else 3 if terminal["result"] == "manual_intervention" else 2
    return status, root


def show_bundle() -> None:
    document = validate_operation()
    rows = bundle_file_hashes()
    print(f"authorization_ready={str(document['operation']['authorization_ready']).lower()}")
    print(f"authorization_blockers={','.join(operation_blockers(document))}")
    print(f"bundle_sha256={bundle_hash(rows)}")
    for digest, relative in rows:
        print(f"{digest}  {relative}")


def self_test() -> int:
    for relative in (
        "backblaze-b2/tests/s3-compatibility-probe-regression.py",
        "backblaze-b2/tests/s3-compatibility-launcher-regression.py",
    ):
        result = subprocess.run(
            (sys.executable, str(ROOT / relative)),
            stdin=subprocess.DEVNULL,
            check=False,
        )
        if result.returncode != 0:
            return result.returncode
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("show-bundle")
    subparsers.add_parser("preflight")
    execute_parser = subparsers.add_parser("execute")
    execute_parser.add_argument("bundle_sha256")
    subparsers.add_parser("self-test")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "show-bundle":
            show_bundle()
            return 0
        if args.command == "self-test":
            return self_test()
        status, root = run(
            args.command,
            getattr(args, "bundle_sha256", None),
        )
        print(f"evidence_root={root}")
        return status
    except LauncherBlocked as exc:
        print(f"result=blocked error_class={exc.code}", file=sys.stderr)
        return exc.status


if __name__ == "__main__":
    raise SystemExit(main())
