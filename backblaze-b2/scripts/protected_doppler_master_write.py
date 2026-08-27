#!/usr/bin/env python3
"""Store one-time B2 master credentials in Doppler without value output."""

from __future__ import annotations

import argparse
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path
from typing import Callable

PROJECT = "homelab-dev"
CONFIG = "prd_b2_admin"
KEY_ID_NAME = "BACKBLAZE_B2_MASTER_APPLICATION_KEY_ID"
KEY_VALUE_NAME = "BACKBLAZE_B2_MASTER_APPLICATION_KEY"
EXPECTED_NAMES = {KEY_ID_NAME, KEY_VALUE_NAME}
MAX_SECRET_BYTES = 4096
MAX_OUTPUT_BYTES = 1024 * 1024
TIMEOUT_SECONDS = 30
DOPPLER_BASE = ("doppler", "--no-check-version", "--no-read-env", "--silent")


class ProtectedWriteBlocked(Exception):
    """A bounded failure with a non-secret classification."""

    def __init__(self, code: str):
        self.code = code if re.fullmatch(r"[a-z0-9_]+", code) else "invalid_error_class"
        super().__init__(self.code)


def validate_root(path: Path) -> int:
    if (
        not path.is_absolute()
        or path.parent != Path("/tmp")
        or not re.fullmatch(r"backblaze-b2-master-key-rotation\.[A-Za-z0-9_]+", path.name)
    ):
        raise ProtectedWriteBlocked("invalid_evidence_root")
    try:
        info = path.lstat()
    except OSError as exc:
        raise ProtectedWriteBlocked("invalid_evidence_root") from exc
    if (
        not stat.S_ISDIR(info.st_mode)
        or stat.S_ISLNK(info.st_mode)
        or info.st_uid != os.getuid()
        or stat.S_IMODE(info.st_mode) != 0o700
    ):
        raise ProtectedWriteBlocked("unsafe_evidence_root")
    flags = os.O_RDONLY | os.O_DIRECTORY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        return os.open(path, flags)
    except OSError as exc:
        raise ProtectedWriteBlocked("invalid_evidence_root") from exc


def read_owned_fifo(root_fd: int, name: str) -> bytearray:
    if "/" in name or name in {"", ".", ".."}:
        raise ProtectedWriteBlocked("invalid_fifo_name")
    try:
        before = os.stat(name, dir_fd=root_fd, follow_symlinks=False)
    except OSError as exc:
        raise ProtectedWriteBlocked("invalid_secret_fifo") from exc
    if (
        not stat.S_ISFIFO(before.st_mode)
        or before.st_uid != os.getuid()
        or stat.S_IMODE(before.st_mode) != 0o600
    ):
        raise ProtectedWriteBlocked("unsafe_secret_fifo")
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fifo_fd = os.open(name, flags, dir_fd=root_fd)
    except OSError as exc:
        raise ProtectedWriteBlocked("invalid_secret_fifo") from exc
    try:
        opened = os.fstat(fifo_fd)
        current = os.stat(name, dir_fd=root_fd, follow_symlinks=False)
        identity = (before.st_dev, before.st_ino)
        if identity != (opened.st_dev, opened.st_ino) or identity != (
            current.st_dev,
            current.st_ino,
        ):
            raise ProtectedWriteBlocked("secret_fifo_replaced")
        os.unlink(name, dir_fd=root_fd)
        value = bytearray(os.read(fifo_fd, MAX_SECRET_BYTES + 1))
        if len(value) > MAX_SECRET_BYTES:
            raise ProtectedWriteBlocked("secret_too_large")
        if not value or any(marker in value for marker in (b"\n", b"\r", b"\x00")):
            raise ProtectedWriteBlocked("invalid_secret_value")
        if os.read(fifo_fd, 1):
            raise ProtectedWriteBlocked("secret_too_large")
        return value
    finally:
        os.close(fifo_fd)


def minimal_environment() -> dict[str, str]:
    allowed = ("HOME", "PATH", "LANG", "LC_ALL", "XDG_CONFIG_HOME")
    return {name: os.environ[name] for name in allowed if name in os.environ}


def run_doppler(argv: tuple[str, ...], value: bytearray | None = None) -> bytes:
    try:
        result = subprocess.run(
            argv,
            input=None if value is None else bytes(value),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=minimal_environment(),
            timeout=TIMEOUT_SECONDS,
            check=False,
            start_new_session=True,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ProtectedWriteBlocked("doppler_transport_failed") from exc
    if len(result.stdout) > MAX_OUTPUT_BYTES or len(result.stderr) > MAX_OUTPUT_BYTES:
        raise ProtectedWriteBlocked("doppler_output_too_large")
    if result.returncode != 0:
        raise ProtectedWriteBlocked("doppler_command_failed")
    return result.stdout


Runner = Callable[[tuple[str, ...], bytearray | None], bytes]


def set_argv(secret_name: str) -> tuple[str, ...]:
    return DOPPLER_BASE + (
        "secrets",
        "set",
        secret_name,
        "--project",
        PROJECT,
        "--config",
        CONFIG,
    )


def names_argv() -> tuple[str, ...]:
    return DOPPLER_BASE + (
        "secrets",
        "--project",
        PROJECT,
        "--config",
        CONFIG,
        "--only-names",
        "--json",
    )


def parse_name_only_output(payload: bytes) -> set[str]:
    try:
        document = json.loads(payload)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ProtectedWriteBlocked("invalid_name_only_readback") from exc
    if not isinstance(document, dict) or not all(
        isinstance(name, str) and value == {} for name, value in document.items()
    ):
        raise ProtectedWriteBlocked("doppler_values_exposed")
    return set(document)


def store_from_fifos(
    root_fd: int,
    key_id_fifo: str,
    key_value_fifo: str,
    runner: Runner = run_doppler,
) -> dict[str, bool]:
    key_id_written = False
    key_value_written = False
    value = read_owned_fifo(root_fd, key_id_fifo)
    try:
        runner(set_argv(KEY_ID_NAME), value)
        key_id_written = True
    finally:
        value[:] = b"\x00" * len(value)
        value.clear()

    value = read_owned_fifo(root_fd, key_value_fifo)
    try:
        try:
            runner(set_argv(KEY_VALUE_NAME), value)
            key_value_written = True
        except ProtectedWriteBlocked as exc:
            if key_id_written:
                raise ProtectedWriteBlocked("partial_secret_write_manual_intervention") from exc
            raise
    finally:
        value[:] = b"\x00" * len(value)
        value.clear()

    try:
        names = parse_name_only_output(runner(names_argv(), None))
        if not EXPECTED_NAMES.issubset(names):
            raise ProtectedWriteBlocked("name_only_acceptance_failed")
    except ProtectedWriteBlocked as exc:
        if key_id_written and key_value_written:
            raise ProtectedWriteBlocked("post_write_acceptance_manual_intervention") from exc
        raise
    return {
        "master_key_id_written": key_id_written,
        "master_key_value_written": key_value_written,
        "exact_names_present": True,
        "value_readback_performed": False,
    }


def write_evidence(
    root_fd: int,
    bundle_sha256: str,
    result: str,
    checks: dict[str, bool],
    error_class: str | None,
) -> None:
    document = {
        "schema_version": 1,
        "operation": "backblaze-b2-master-key-rotation-v1",
        "bundle_sha256": bundle_sha256,
        "result": result,
        "checks": checks,
        "error_class": error_class,
        "secret_values_or_identifiers_retained": False,
    }
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open("doppler-write-result.json", flags, 0o600, dir_fd=root_fd)
    try:
        os.write(fd, json.dumps(document, sort_keys=True).encode("utf-8") + b"\n")
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
        return 2
    root_fd = -1
    checks: dict[str, bool] = {}
    result = "blocked"
    error_class: str | None = None
    try:
        root_fd = validate_root(args.evidence_root)
        checks = store_from_fifos(root_fd, args.key_id_fifo, args.key_value_fifo)
        result = "stored"
    except ProtectedWriteBlocked as exc:
        error_class = exc.code
    finally:
        if root_fd >= 0:
            write_evidence(root_fd, args.bundle_sha256, result, checks, error_class)
            os.close(root_fd)
    print(f"result={result}" + ("" if error_class is None else f" error_class={error_class}"))
    return 0 if result == "stored" else 2


if __name__ == "__main__":
    raise SystemExit(main())
