#!/usr/bin/env python3
"""Require filter-based Nautobot Ansible assertion expressions."""

from pathlib import Path
import re
import sys

import yaml


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
ANSIBLE_ROOT = REPOSITORY_ROOT / "Nautobot" / "ansible"
FORBIDDEN_EXPRESSION = re.compile(r"\.split\s*\(\s*\)\s*\.count\s*\(")
FORBIDDEN_METHOD_CALL = re.compile(r"\.[A-Za-z_][A-Za-z0-9_]*\s*\(")


def assertion_conditions(node):
    """Yield task names and assertion conditions recursively."""
    if isinstance(node, dict):
        assertion = node.get("ansible.builtin.assert")
        if isinstance(assertion, dict):
            for condition in assertion.get("that", []):
                yield node.get("name", "<unnamed assertion>"), str(condition)
        for value in node.values():
            yield from assertion_conditions(value)
    elif isinstance(node, list):
        for value in node:
            yield from assertion_conditions(value)


def main():
    violations = []
    yaml_paths = sorted((ANSIBLE_ROOT / "playbooks").glob("*.yaml"))
    yaml_paths += sorted((ANSIBLE_ROOT / "tasks").glob("*.yaml"))
    for yaml_path in yaml_paths:
        with yaml_path.open(encoding="utf-8") as stream:
            document = yaml.safe_load(stream)
        for task_name, condition in assertion_conditions(document):
            if FORBIDDEN_EXPRESSION.search(condition) or FORBIDDEN_METHOD_CALL.search(condition):
                relative_path = yaml_path.relative_to(REPOSITORY_ROOT)
                violations.append(f"{relative_path}: {task_name}: {condition}")

    if violations:
        print("Forbidden method calls in Ansible assertion expressions:", file=sys.stderr)
        print("\n".join(violations), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
