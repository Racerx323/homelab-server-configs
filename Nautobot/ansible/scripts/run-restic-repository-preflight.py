#!/usr/bin/env python3
"""Hash-bound controller for the Nautobot Restic absence preflight."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Callable

import yaml

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[3]
OPERATION_PATH = ROOT / "Nautobot/manifests/operation.yaml"
OPERATION_SCHEMA = ROOT / "Nautobot/schemas/operation.schema.json"
EXPECTED_OPERATION_ID = "nautobot-restic-repository-initialization-v1"
EXPECTED_TARGET = "j2-svpi4mf"
BUNDLE_DOMAIN = "nautobot-restic-repository-preflight-bundle-v1"
BUNDLE_FILES = (
    "Nautobot/ansible/playbooks/preflight-restic-repository.yaml",
    "Nautobot/ansible/scripts/run-restic-repository-preflight.py",
    "Nautobot/ansible/scripts/validate-restic-repository-preflight.py",
    "Nautobot/ansible/scripts/validate-restic-repository-preflight-launcher.py",
    "Nautobot/manifests/operation.yaml",
    "Nautobot/schemas/operation.schema.json",
    "Nautobot/schemas/repository-initialization.schema.json",
    "inventory/prod/hosts.yaml",
    "inventory/prod/groups/inventory_automation.yaml",
    "inventory/prod/hosts/j2-svpi4mf.yaml",
    "restic/docs/READ_ONLY_PREFLIGHT.md",
)
INVENTORY_PATH = ROOT / "inventory/prod/hosts.yaml"
PLAYBOOK_PATH = ROOT / "Nautobot/ansible/playbooks/preflight-restic-repository.yaml"
EVIDENCE_PREFIX = "nautobot-restic-preflight."
MAX_SECRET_BYTES = 4096
MAX_STREAM_BYTES = 4 * 1024 * 1024
COMMAND_TIMEOUT_SECONDS = 300
DOPPLER_TIMEOUT_SECONDS = 30
DOPPLER_BASE = ("doppler", "--no-check-version", "--no-read-env", "--silent")
SECRET_REFERENCES = (
    ("restic_repository_password", "homelab-dev", "prd_restic", "NAUTOBOT_RESTIC_REPOSITORY_PASSWORD"),
    ("restic_b2_application_key_id", "homelab-dev", "prd_b2", "NAUTOBOT_RESTIC_B2_APPLICATION_KEY_ID"),
    ("restic_b2_application_key", "homelab-dev", "prd_b2", "NAUTOBOT_RESTIC_B2_APPLICATION_KEY"),
)


class PreflightBlocked(Exception):
    def __init__(self, code: str, status: int = 69):
        self.code = code if re.fullmatch(r"[a-z0-9_]+", code) else "invalid_error_class"
        self.status = status
        super().__init__(self.code)


def minimal_environment() -> dict[str, str]:
    allowed = ("HOME", "PATH", "LANG", "LC_ALL", "XDG_CONFIG_HOME", "SSH_AUTH_SOCK")
    return {name: os.environ[name] for name in allowed if name in os.environ}


def load_operation() -> dict[str, Any]:
    document = yaml.safe_load(OPERATION_PATH.read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        raise PreflightBlocked("invalid_operation")
    return document


def validate_operation(
    runner: Callable[..., subprocess.CompletedProcess[Any]] = subprocess.run,
) -> dict[str, Any]:
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
        raise PreflightBlocked("operation_validator_timeout") from exc
    except OSError as exc:
        raise PreflightBlocked("operation_validator_unavailable") from exc
    if result.returncode != 0:
        raise PreflightBlocked("operation_schema_invalid")
    document = load_operation()
    if document.get("operation", {}).get("id") != EXPECTED_OPERATION_ID:
        raise PreflightBlocked("active_operation_mismatch")
    return document


def bundle_file_hashes() -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    for relative in BUNDLE_FILES:
        path = ROOT / relative
        if not path.is_file() or path.is_symlink():
            raise PreflightBlocked("invalid_bundle_input")
        rows.append((hashlib.sha256(path.read_bytes()).hexdigest(), relative))
    return rows


def bundle_hash(rows: list[tuple[str, str]] | None = None) -> str:
    inputs = rows if rows is not None else bundle_file_hashes()
    payload = BUNDLE_DOMAIN + "\n"
    payload += "".join(f"{digest}  {relative}\n" for digest, relative in inputs)
    return hashlib.sha256(payload.encode()).hexdigest()


def require_ready(document: dict[str, Any], authorized_hash: str, calculated_hash: str) -> None:
    operation = document.get("operation", {})
    preflight = document.get("preflight", {})
    authorization = document.get("authorization", {})
    blockers = authorization.get("blockers", [])
    if (
        operation.get("authorization_ready") is not False
        or authorization.get("mutation_authorized") is not False
        or preflight.get("state") != "pending"
        or preflight.get("implementation_state") != "reviewed"
        or preflight.get("authorization_ready") is not True
        or preflight.get("execution_authorized") is not True
        or preflight.get("credential_fallback_allowed") is not False
        or "doppler_prd_restic_config_and_password_key_required" in blockers
        or "read_only_repository_absence_preflight_review_required" in blockers
    ):
        raise PreflightBlocked("preflight_not_ready")
    if not re.fullmatch(r"[0-9a-f]{64}", authorized_hash):
        raise PreflightBlocked("invalid_authorized_hash", 66)
    if authorized_hash != calculated_hash:
        raise PreflightBlocked("bundle_hash_mismatch", 66)


def _open_exclusive(root_fd: int, name: str) -> int:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    return os.open(name, flags, 0o600, dir_fd=root_fd)


def validate_evidence_root(root: Path) -> int:
    info = root.lstat()
    if (
        root.parent != Path("/tmp")
        or not root.name.startswith(EVIDENCE_PREFIX)
        or not stat.S_ISDIR(info.st_mode)
        or stat.S_ISLNK(info.st_mode)
        or info.st_uid != os.getuid()
        or stat.S_IMODE(info.st_mode) != 0o700
    ):
        raise PreflightBlocked("unsafe_evidence_root")
    flags = os.O_RDONLY | os.O_DIRECTORY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    return os.open(root, flags)


def write_exclusive(root_fd: int, name: str, payload: bytes) -> None:
    fd = _open_exclusive(root_fd, name)
    try:
        os.write(fd, payload)
        os.fsync(fd)
    finally:
        os.close(fd)


def prepare_evidence(rows: list[tuple[str, str]], calculated_hash: str) -> tuple[Path, int]:
    root = Path(tempfile.mkdtemp(prefix=EVIDENCE_PREFIX, dir="/tmp"))
    root.chmod(0o700)
    root_fd = validate_evidence_root(root)
    write_exclusive(
        root_fd,
        "bundle-files.sha256",
        "".join(f"{digest}  {relative}\n" for digest, relative in rows).encode(),
    )
    write_exclusive(root_fd, "bundle.sha256", f"{calculated_hash}\n".encode())
    return root, root_fd


def doppler_argv(project: str, config: str, name: str) -> tuple[str, ...]:
    return DOPPLER_BASE + (
        "secrets", "get", name, "--project", project, "--config", config, "--plain",
    )


def run_bounded_secret_command(argv: tuple[str, ...]) -> tuple[int, bytearray, bool]:
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
        raise PreflightBlocked("doppler_unavailable") from exc
    assert process.stdout is not None and process.stderr is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ, "stdout")
    selector.register(process.stderr, selectors.EVENT_READ, "stderr")
    value = bytearray()
    too_large = False
    deadline = time.monotonic() + DOPPLER_TIMEOUT_SECONDS
    try:
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                os.killpg(process.pid, signal.SIGTERM)
                raise PreflightBlocked("doppler_timeout")
            events = selector.select(remaining)
            if not events:
                os.killpg(process.pid, signal.SIGTERM)
                raise PreflightBlocked("doppler_timeout")
            for key, _ in events:
                chunk = os.read(key.fileobj.fileno(), 8192)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                if key.data != "stdout":
                    continue
                retained = MAX_SECRET_BYTES + 1 - len(value)
                if retained > 0:
                    value.extend(chunk[:retained])
                if len(chunk) > retained or len(value) > MAX_SECRET_BYTES:
                    too_large = True
        status = process.wait(timeout=5)
    finally:
        selector.close()
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
    return status, value, too_large


def read_secret(
    project: str,
    config: str,
    name: str,
    runner: Callable[[tuple[str, ...]], tuple[int, bytearray, bool]] = run_bounded_secret_command,
) -> bytearray:
    status, value, too_large = runner(doppler_argv(project, config, name))
    if status != 0:
        for index in range(len(value)):
            value[index] = 0
        raise PreflightBlocked("doppler_secret_unavailable")
    while value.endswith(b"\n") or value.endswith(b"\r"):
        value.pop()
    if too_large or not value or b"\x00" in value or b"\n" in value:
        for index in range(len(value)):
            value[index] = 0
        raise PreflightBlocked("invalid_secret_value")
    return value


def write_extra_vars(root_fd: int, secrets_by_variable: dict[str, bytearray]) -> None:
    values = {
        variable: bytes(secret).decode("utf-8")
        for variable, secret in secrets_by_variable.items()
    }
    try:
        payload = (json.dumps(values, separators=(",", ":")) + "\n").encode()
        write_exclusive(root_fd, "protected-extra-vars.json", payload)
    except UnicodeDecodeError as exc:
        raise PreflightBlocked("invalid_secret_encoding") from exc
    finally:
        values.clear()


def drain_process(argv: tuple[str, ...], environment: dict[str, str]) -> tuple[int, bytes, bytes, bool]:
    try:
        process = subprocess.Popen(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
            start_new_session=True,
        )
    except OSError as exc:
        raise PreflightBlocked("ansible_unavailable") from exc
    assert process.stdout is not None and process.stderr is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ, "stdout")
    selector.register(process.stderr, selectors.EVENT_READ, "stderr")
    captured = {"stdout": bytearray(), "stderr": bytearray()}
    truncated = False
    deadline = time.monotonic() + COMMAND_TIMEOUT_SECONDS
    try:
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                os.killpg(process.pid, signal.SIGTERM)
                raise PreflightBlocked("ansible_timeout")
            events = selector.select(remaining)
            if not events:
                os.killpg(process.pid, signal.SIGTERM)
                raise PreflightBlocked("ansible_timeout")
            for key, _ in events:
                chunk = os.read(key.fileobj.fileno(), 8192)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                stream = captured[key.data]
                remaining_bytes = MAX_STREAM_BYTES - len(stream)
                if remaining_bytes > 0:
                    stream.extend(chunk[:remaining_bytes])
                if len(chunk) > remaining_bytes:
                    truncated = True
        status = process.wait(timeout=5)
    finally:
        selector.close()
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
    return status, bytes(captured["stdout"]), bytes(captured["stderr"]), truncated


def ansible_argv(extra_vars_path: Path) -> tuple[str, ...]:
    return (
        "ansible-playbook", "--inventory", str(INVENTORY_PATH), "--limit",
        EXPECTED_TARGET, "--user", "ama", "--extra-vars", f"@{extra_vars_path}",
        str(PLAYBOOK_PATH),
    )


def run_preflight(root: Path, root_fd: int) -> int:
    secrets_by_variable: dict[str, bytearray] = {}
    secret_values: list[bytes] = []
    extra_vars_path = root / "protected-extra-vars.json"
    ansible_temp = root / "ansible-local"
    cleanup_failed = False
    try:
        for variable, project, config, name in SECRET_REFERENCES:
            secret = read_secret(project, config, name)
            secrets_by_variable[variable] = secret
            secret_values.append(bytes(secret))
        write_extra_vars(root_fd, secrets_by_variable)
        if stat.S_IMODE(extra_vars_path.stat().st_mode) != 0o600:
            raise PreflightBlocked("unsafe_controller_secret_file")
        ansible_temp.mkdir(mode=0o700)
        environment = minimal_environment()
        environment["ANSIBLE_LOCAL_TEMP"] = str(ansible_temp)
        status, stdout, stderr, truncated = drain_process(
            ansible_argv(extra_vars_path), environment
        )
        if any(value in stdout or value in stderr for value in secret_values):
            raise PreflightBlocked("secret_value_in_ansible_output")
        write_exclusive(root_fd, "ansible.stdout", stdout)
        write_exclusive(root_fd, "ansible.stderr", stderr)
        write_exclusive(root_fd, "ansible.status", f"{status}\n".encode())
        if truncated:
            raise PreflightBlocked("ansible_output_truncated")
        return status
    finally:
        try:
            if extra_vars_path.exists() and not extra_vars_path.is_symlink():
                extra_vars_path.unlink()
            if extra_vars_path.exists():
                cleanup_failed = True
        except OSError:
            cleanup_failed = True
        try:
            if ansible_temp.exists() and not ansible_temp.is_symlink():
                shutil.rmtree(ansible_temp)
            if ansible_temp.exists():
                cleanup_failed = True
        except OSError:
            cleanup_failed = True
        for secret in secrets_by_variable.values():
            for index in range(len(secret)):
                secret[index] = 0
        secrets_by_variable.clear()
        secret_values.clear()
        if cleanup_failed:
            raise PreflightBlocked("controller_secret_cleanup_failed")


def write_terminal(root_fd: int, calculated_hash: str, status: int | None,
                   error: str | None, secret_file_absent: bool,
                   ansible_temp_absent: bool) -> dict[str, Any]:
    result = "passed" if status == 0 and error is None else "blocked"
    document = {
        "schema_version": 1,
        "operation": EXPECTED_OPERATION_ID,
        "stage": "repository_absence_preflight",
        "bundle_sha256": calculated_hash,
        "result": result,
        "ansible_exit_status": status,
        "error_class": error,
        "repository_mutation_authorized": False,
        "repository_initialization_attempted": False,
        "controller_secret_file_absent": secret_file_absent,
        "ansible_local_temp_absent": ansible_temp_absent,
        "credential_values_retained": False,
    }
    write_exclusive(
        root_fd, "terminal-result.json",
        (json.dumps(document, sort_keys=True) + "\n").encode(),
    )
    return document


def execute(authorized_hash: str) -> tuple[int, Path]:
    document = validate_operation()
    rows = bundle_file_hashes()
    calculated_hash = bundle_hash(rows)
    require_ready(document, authorized_hash, calculated_hash)
    root, root_fd = prepare_evidence(rows, calculated_hash)
    status: int | None = None
    error: str | None = None
    try:
        try:
            status = run_preflight(root, root_fd)
        except PreflightBlocked as exc:
            error = exc.code
        except KeyboardInterrupt:
            error = "interrupted"
        except Exception:
            error = "internal_error"
        secret_absent = not (root / "protected-extra-vars.json").exists()
        temp_absent = not (root / "ansible-local").exists()
        terminal = write_terminal(
            root_fd, calculated_hash, status, error, secret_absent, temp_absent
        )
    finally:
        os.close(root_fd)
    print(f"result={terminal['result']} evidence_root={root}")
    return (0 if terminal["result"] == "passed" else 69), root


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("execute", "show-hash"))
    parser.add_argument("authorized_hash", nargs="?")
    args = parser.parse_args()
    if args.mode == "execute" and args.authorized_hash is None:
        parser.error("execute requires AUTHORIZED_HASH")
    if args.mode == "show-hash" and args.authorized_hash is not None:
        parser.error("show-hash accepts no hash")
    return args


def main() -> int:
    os.umask(0o077)
    args = parse_args()
    try:
        if args.mode == "show-hash":
            document = validate_operation()
            operation = document.get("operation", {})
            preflight = document.get("preflight", {})
            if (
                operation.get("authorization_ready") is not False
                or preflight.get("state") != "pending"
                or preflight.get("implementation_state") != "reviewed"
                or preflight.get("authorization_ready") is not True
                or preflight.get("execution_authorized") is not True
            ):
                raise PreflightBlocked("show_hash_requires_ready_preflight")
            print(bundle_hash())
            return 0
        status, _ = execute(args.authorized_hash)
        return status
    except PreflightBlocked as exc:
        print(f"result=blocked error={exc.code}", file=sys.stderr)
        return exc.status


if __name__ == "__main__":
    raise SystemExit(main())
