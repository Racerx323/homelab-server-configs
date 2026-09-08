#!/usr/bin/env python3
"""Offline contract checks for the Nautobot Restic absence preflight."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Any

import yaml

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[3]
PLAYBOOK = ROOT / "Nautobot/ansible/playbooks/preflight-restic-repository.yaml"
OPERATION = ROOT / "Nautobot/manifests/deferred-restic-initialization.yaml"


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


def protected_metadata_is_safe(return_code: int, output: str) -> bool:
    return return_code == 0 and output == "nautobot:600:regular file"


def restic_version_is_supported(output: str) -> bool:
    match = re.fullmatch(r"restic ([0-9]+)[.]([0-9]+)[.]([0-9]+)(?: .*)?", output)
    if match is None:
        return False
    return tuple(int(value) for value in match.groups()) >= (0, 17, 0)


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
    if play.get("vars", {}).get("restic_preflight_minimum_version") != "0.17.0":
        fail("minimum Restic version must remain 0.17.0")

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

    metadata_task = by_name["Inspect protected preflight input metadata"]
    require_exact_command(
        metadata_task,
        [
            "/usr/bin/sudo", "-n", "/usr/sbin/runuser", "--user",
            "nautobot", "--", "/usr/bin/stat", "--printf=%U:%a:%F",
            f"{remote}/{{{{ item }}}}",
        ],
    )
    if (
        metadata_task.get("changed_when") is not False
        or metadata_task.get("failed_when") is not False
    ):
        fail("metadata inspection must capture status without mutation or early failure")

    metadata_gate = by_name["Require protected preflight input ownership and modes"]
    metadata_assertions = metadata_gate.get("ansible.builtin.assert", {}).get("that", [])
    if metadata_assertions != [
        "item.rc == 0",
        'item.stdout == "nautobot:600:regular file"',
    ]:
        fail("protected metadata assertion is not exact")

    metadata_cases = {
        (0, "nautobot:600:regular file"): True,
        (1, ""): False,
        (0, "ama:600:regular file"): False,
        (0, "nautobot:644:regular file"): False,
        (0, "nautobot:600:symbolic link"): False,
        (0, "nautobot:600:directory"): False,
    }
    for (status, output), expected in metadata_cases.items():
        if protected_metadata_is_safe(status, output) is not expected:
            fail(f"incorrect protected metadata classification for {status}:{output}")

    runuser_prefix = [
        "/usr/bin/sudo", "-n", "/usr/sbin/runuser", "--user",
        "nautobot", "--",
    ]
    protected_content_tasks = (
        "Create empty protected credential files",
        "Write protected preflight inputs",
        "Inspect protected preflight input metadata",
        "Read Restic repository config",
    )
    for name in protected_content_tasks:
        argv = by_name[name].get("ansible.builtin.command", {}).get("argv", [])
        if argv[: len(runuser_prefix)] != runuser_prefix:
            fail(f"protected-path task does not execute as nautobot: {name}")

    cleanup_probe = by_name["Verify protected remote preflight cleanup"]
    if cleanup_probe.get("ansible.builtin.stat", {}).get("path") != remote:
        fail("cleanup probe must inspect only the removed directory entry")

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

    version_cases = {
        "restic 0.16.5 compiled with go1.22.0 on linux/arm64": False,
        "restic 0.17.0 compiled with go1.23.0 on linux/arm64": True,
        "restic 0.18.1": True,
        "restic 1.0.0 compiled with go1.24.0 on linux/arm64": True,
        "0.17.0": False,
        "restic development": False,
        "": False,
    }
    for output, expected in version_cases.items():
        if restic_version_is_supported(output) is not expected:
            fail(f"incorrect supported-version classification for {output!r}")

    observations = by_name["Record sanitized forward observations"].get(
        "ansible.builtin.set_fact", {}
    ).get("restic_preflight_observation", {})
    required_observations = {
        "execution_user",
        "execution_user_matches",
        "restic_version_output",
        "restic_version_number",
        "version_command_succeeded",
        "version_supported",
        "config_exit_status",
        "repository_absent",
    }
    if not required_observations.issubset(observations):
        fail("sanitized identity/version observations are incomplete")

    operation = load_yaml(OPERATION)
    preflight = operation.get("preflight", {})
    if operation.get("operation", {}).get("id") != "nautobot-restic-repository-initialization-v1":
        fail("unexpected active operation")
    if preflight.get("execution_authorized") is not False:
        fail("corrected preflight execution must remain unauthorized")
    if preflight.get("authorization_ready") is not False:
        fail("completed preflight must remain authorization-unready")
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
    if "restic_version_and_execution_identity_preflight_required" in blockers:
        fail("satisfied identity/version blocker remains present")
    if "doppler_prd_restic_config_and_password_key_required" in blockers:
        fail("satisfied Doppler password blocker remains present")
    if "accepted_host_baseline_identity_required" not in blockers:
        fail("unresolved host-baseline acceptance blocker is missing")
    if operation.get("repository", {}).get("initialized_state") != "absent_verified":
        fail("passed absence evidence is not reflected in repository state")
    if (
        operation.get("provider_acceptance", {}).get("accepted_live_state")
        != "backblaze-b2/manifests/accepted-live-state.yaml"
    ):
        fail("accepted Backblaze live-state reference is missing")
    last_result = preflight.get("last_result", {})
    if (
        preflight.get("state") != "passed"
        or preflight.get("implementation_state") != "reviewed"
        or last_result.get("execution_user") != "nautobot"
        or last_result.get("restic_version_number") != "0.18.0"
        or last_result.get("version_supported") is not True
        or last_result.get("exact_version_retained") is not True
        or last_result.get("config_exit_status") != 10
    ):
        fail("combined preflight evidence is incomplete")

    print("Nautobot Restic repository-absence preflight regression passed.")


if __name__ == "__main__":
    main()
