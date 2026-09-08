#!/usr/bin/env python3
"""Offline contract checks for the Nautobot Restic absence preflight."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

import yaml

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[3]
PLAYBOOK = ROOT / "Nautobot/ansible/playbooks/preflight-restic-repository.yaml"
OPERATION = ROOT / "Nautobot/manifests/operation.yaml"


def fail(message: str) -> None:
    raise SystemExit(f"Restic repository preflight regression failed: {message}")


def load_yaml(path: Path) -> Any:
    document = yaml.safe_load(path.read_text(encoding="utf-8"))
    if document is None:
        fail(f"empty YAML: {path.relative_to(ROOT)}")
    return document


def flatten(tasks: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for task in tasks:
        result.append(task)
        for section in ("block", "rescue", "always"):
            nested = task.get(section)
            if isinstance(nested, list):
                result.extend(flatten(nested))
    return result


def classify(return_code: int) -> str:
    return {
        0: "repository_exists",
        10: "repository_absent",
        11: "repository_locked",
        12: "incorrect_password",
    }.get(return_code, "ambiguous_failure")


def require_exact_command(task: dict[str, Any], expected: list[str]) -> None:
    command = task.get("ansible.builtin.command")
    if not isinstance(command, dict) or command.get("argv") != expected:
        fail(f"unexpected argv for {task.get('name')}")


def main() -> None:
    playbook = load_yaml(PLAYBOOK)
    if not isinstance(playbook, list) or len(playbook) != 1:
        fail("playbook must contain exactly one play")
    play = playbook[0]
    if play.get("hosts") != "inventory_automation":
        fail("unexpected inventory group")
    if play.get("gather_facts") is not False or play.get("become") is not False:
        fail("facts and Ansible become must remain disabled")

    tasks = flatten(play.get("pre_tasks", []) + play.get("tasks", []))
    by_name = {task.get("name"): task for task in tasks}
    required_names = {
        "Require protected controller-supplied credentials",
        "Read the effective Restic execution identity",
        "Read the installed Restic version",
        "Inspect protected preflight input metadata",
        "Require protected preflight input ownership and modes",
        "Read Restic repository config",
        "Record sanitized forward observations",
        "Emit sanitized forward observations",
        "Require the exact repository absence result",
        "Remove only the protected remote preflight directory",
        "Require protected remote preflight cleanup",
    }
    if not required_names.issubset(by_name):
        fail("required task is missing")

    secret_tasks = (
        "Require protected controller-supplied credentials",
        "Create empty protected credential files",
        "Write protected preflight inputs",
        "Inspect protected preflight input metadata",
        "Require protected preflight input ownership and modes",
        "Read Restic repository config",
    )
    if any(by_name[name].get("no_log") is not True for name in secret_tasks):
        fail("a credential-bearing task is missing no_log")

    create_files = by_name["Create empty protected credential files"]
    create_command = create_files.get("ansible.builtin.command", {})
    if "--mode=0600" not in create_command.get("argv", []):
        fail("protected remote files must be created with mode 0600")

    cleanup = by_name["Remove only the protected remote preflight directory"]
    cleanup_argv = cleanup.get("ansible.builtin.command", {}).get("argv", [])
    if cleanup_argv != [
        "/usr/bin/sudo", "-n", "/usr/bin/rm", "--recursive", "--force",
        "--", "{{ restic_preflight_remote_directory.stdout }}",
    ]:
        fail("remote cleanup argv is not exact")

    config_task = by_name["Read Restic repository config"]
    remote = "{{ restic_preflight_remote_directory.stdout }}"
    require_exact_command(
        config_task,
        [
            "/usr/bin/sudo", "-n", "/usr/sbin/runuser", "--user",
            "nautobot", "--", "/usr/bin/env",
            "AWS_SHARED_CREDENTIALS_FILE={{ restic_preflight_remote_directory.stdout }}/aws-credentials",
            "AWS_PROFILE=default", "/usr/bin/restic", "--no-cache",
            "--no-lock", "--repository-file", f"{remote}/repository",
            "--password-file", f"{remote}/password", "cat", "config",
        ],
    )
    if config_task.get("changed_when") is not False or config_task.get("failed_when") is not False:
        fail("config read must capture status without mutation or early failure")

    ordered_names = [task.get("name") for task in tasks]
    if not (
        ordered_names.index("Record sanitized forward observations")
        < ordered_names.index("Emit sanitized forward observations")
        < ordered_names.index("Require the exact repository absence result")
    ):
        fail("forward observations must precede the assertion")

    forbidden = {"init", "backup", "restore", "check", "forget", "prune", "repair", "unlock"}
    for task in tasks:
        command = task.get("ansible.builtin.command")
        if not isinstance(command, dict):
            continue
        argv = command.get("argv", [])
        literal = {item for item in argv if isinstance(item, str)}
        if literal & forbidden:
            fail(f"mutation command present in {task.get('name')}")
    if any("ansible.builtin.shell" in task for task in tasks):
        fail("shell tasks are prohibited")

    expected_classifications = {
        0: "repository_exists",
        1: "ambiguous_failure",
        10: "repository_absent",
        11: "repository_locked",
        12: "incorrect_password",
        130: "ambiguous_failure",
    }
    for status, expected in expected_classifications.items():
        if classify(status) != expected:
            fail(f"incorrect representative classification for exit {status}")

    operation = load_yaml(OPERATION)
    preflight = operation.get("preflight", {})
    if operation.get("operation", {}).get("id") != "nautobot-restic-repository-initialization-v1":
        fail("unexpected active operation")
    if preflight.get("execution_authorized") is not True:
        fail("read-only preflight execution must be enabled")
    if preflight.get("authorization_ready") is not True:
        fail("read-only preflight must be authorization-ready")
    if operation.get("operation", {}).get("authorization_ready") is not False:
        fail("repository initialization must remain authorization-unready")
    if operation.get("authorization", {}).get("mutation_authorized") is not False:
        fail("repository mutation must remain unauthorized")
    if "authorization_hash" in preflight:
        fail("operation must not embed its self-referential bundle hash")
    if preflight.get("repository_absent_exit_code") != 10:
        fail("absence exit status must be 10")
    blockers = operation.get("authorization", {}).get("blockers", [])
    if "read_only_repository_absence_preflight_review_required" in blockers:
        fail("satisfied preflight review blocker remains present")
    if "doppler_prd_restic_config_and_password_key_required" in blockers:
        fail("satisfied Doppler password blocker remains present")

    print("Nautobot Restic repository-absence preflight regression passed.")


if __name__ == "__main__":
    main()
