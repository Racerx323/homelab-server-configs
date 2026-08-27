#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository_root=$(cd -- "${script_directory}/../../.." && pwd)
readonly script_directory repository_root
readonly operation_file="${repository_root}/Nautobot/manifests/operation.yaml"
readonly operation_schema="${repository_root}/Nautobot/schemas/operation.schema.json"
readonly inventory_file="${repository_root}/inventory/prod/hosts.yaml"
readonly playbook_file="${repository_root}/Nautobot/ansible/playbooks/diagnose-storage.yaml"
readonly operation_target=j2-svpi4mf
readonly operation_address=10.1.2.170
readonly operation_user=ama
readonly evidence_limit_bytes=8388608
readonly -a bundle_files=(
    Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md
    Nautobot/docs/STORAGE_REMEDIATION_DECISION.md
    Nautobot/manifests/operation.yaml
    Nautobot/schemas/operation.schema.json
    Nautobot/ansible/playbooks/diagnose-storage.yaml
    Nautobot/ansible/scripts/run-storage-diagnostic.sh
    inventory/prod/hosts.yaml
    inventory/prod/groups/inventory_automation.yaml
    inventory/prod/hosts/j2-svpi4mf.yaml
)

usage() {
    printf '%s\n' \
        "Usage:" \
        "  ${0##*/} show-bundle" \
        "  ${0##*/} execute BUNDLE_SHA256" \
        "  ${0##*/} self-test"
}

validate_operation() {
    check-jsonschema --schemafile "$operation_schema" "$operation_file"
}

operation_ready() {
    python3 -c \
        'import sys,yaml; print(str(bool(yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["operation"]["authorization_ready"])).lower())' \
        "$operation_file"
}

operation_blockers() {
    python3 -c \
        'import sys,yaml; d=yaml.safe_load(open(sys.argv[1], encoding="utf-8")); print(",".join(d.get("authorization", {}).get("blockers", ["no_active_operation"])))' \
        "$operation_file"
}

write_bundle_file_hashes() {
    local destination_file=$1
    local relative_path

    : >"$destination_file"
    for relative_path in "${bundle_files[@]}"; do
        [[ -f "${repository_root}/${relative_path}" ]] || {
            printf 'Missing bundle input: %s\n' "$relative_path" >&2
            return 1
        }
        [[ ! -L "${repository_root}/${relative_path}" ]] || {
            printf 'Refusing symbolic-link bundle input: %s\n' "$relative_path" >&2
            return 1
        }
        printf '%s  %s\n' \
            "$(sha256sum "${repository_root}/${relative_path}" | cut -d ' ' -f 1)" \
            "$relative_path" >>"$destination_file"
    done
}

calculate_bundle_hash() {
    local bundle_file_list calculated_hash

    bundle_file_list=$(mktemp /tmp/nautobot-storage-diagnostic-bundle.XXXXXX)
    write_bundle_file_hashes "$bundle_file_list"
    calculated_hash=$(
        {
            printf '%s\n' 'nautobot-storage-soak-verification-bundle-v1'
            cat "$bundle_file_list"
        } | sha256sum | cut -d ' ' -f 1
    )
    rm -f -- "$bundle_file_list"
    printf '%s\n' "$calculated_hash"
}

show_bundle() {
    local bundle_hash readiness blockers bundle_file_list

    validate_operation
    bundle_hash=$(calculate_bundle_hash)
    readiness=$(operation_ready)
    blockers=$(operation_blockers)
    bundle_file_list=$(mktemp /tmp/nautobot-storage-diagnostic-bundle.XXXXXX)
    write_bundle_file_hashes "$bundle_file_list"
    printf 'authorization_ready=%s\n' "$readiness"
    printf 'authorization_blockers=%s\n' "$blockers"
    printf 'bundle_sha256=%s\n' "$bundle_hash"
    cat "$bundle_file_list"
    rm -f -- "$bundle_file_list"
}

consume_bounded_stream() {
    local source_fifo=$1
    local destination_file=$2
    local truncation_marker=$3
    local byte_limit=$4
    local stream_file_descriptor

    exec {stream_file_descriptor}<"$source_fifo"
    head -c "$byte_limit" <&"$stream_file_descriptor" >"$destination_file"
    if IFS= read -r -n 1 -u "$stream_file_descriptor"; then
        : >"$truncation_marker"
        cat <&"$stream_file_descriptor" >/dev/null
    fi
    exec {stream_file_descriptor}<&-
}

write_evidence_record() {
    local evidence_directory=$1
    local evidence_name=$2
    local evidence_path="${evidence_directory}/${evidence_name}"

    printf '  - file: %s\n' "$evidence_name"
    if [[ -f "$evidence_path" ]]; then
        printf '%s\n' '    present: true'
        printf '    bytes: %s\n' "$(stat --format=%s "$evidence_path")"
        printf '    sha256: %s\n' \
            "$(sha256sum "$evidence_path" | cut -d ' ' -f 1)"
    else
        printf '%s\n' '    present: false'
    fi
}

write_evidence_manifest() {
    local evidence_directory=$1
    local bundle_hash=$2
    local started_at=$3
    local finished_at=$4
    local execution_status=$5
    local operation_result=$6
    local evidence_name
    local -a evidence_names=(
        bundle-files.sha256
        stdout.log
        stderr.log
        status.txt
        soak.log
        topology.log
        kernel.log
        power.log
        smart.log
        filesystem.log
        diagnostic.yaml
    )

    {
        printf '%s\n' '---' 'schema_version: 1'
        printf '%s\n' 'operation_id: nautobot-storage-soak-verification-v1'
        printf 'target: %s\n' "$operation_target"
        printf 'address: %s\n' "$operation_address"
        printf 'bundle_sha256: %s\n' "$bundle_hash"
        printf 'started_at_utc: %s\n' "$started_at"
        printf 'finished_at_utc: %s\n' "$finished_at"
        printf 'ansible_exit_status: %s\n' "$execution_status"
        printf 'result: %s\n' "$operation_result"
        printf '%s\n' 'mutation_authorized: false'
        printf 'stdout_truncated: %s\n' \
            "$([[ -f "${evidence_directory}/stdout.truncated" ]] && printf true || printf false)"
        printf 'stderr_truncated: %s\n' \
            "$([[ -f "${evidence_directory}/stderr.truncated" ]] && printf true || printf false)"
        printf '%s\n' 'evidence:'
        for evidence_name in "${evidence_names[@]}"; do
            write_evidence_record "$evidence_directory" "$evidence_name"
        done
    } >"${evidence_directory}/manifest.yaml"
}

classify_result() {
    local evidence_directory=$1
    local execution_status=$2

    if [[ "$execution_status" -eq 0 &&
        -f "${evidence_directory}/diagnostic.yaml" &&
        ! -f "${evidence_directory}/stdout.truncated" &&
        ! -f "${evidence_directory}/stderr.truncated" ]]; then
        printf '%s\n' collected
    else
        printf '%s\n' incomplete
    fi
}

verify_read_only_playbook() {
    python3 - "$playbook_file" <<'PY'
import sys
from pathlib import Path

import yaml

playbook_path = sys.argv[1]
with open(playbook_path, encoding="utf-8") as playbook_stream:
    playbook = yaml.safe_load(playbook_stream)

assert len(playbook) == 1
play = playbook[0]
assert play["hosts"] == "inventory_automation"
assert play["gather_facts"] is False
assert play["become"] is False

expected_vars_files = [
    "../../manifests/operation.yaml",
    "../../../inventory/prod/groups/inventory_automation.yaml",
    "../../../inventory/prod/hosts/j2-svpi4mf.yaml",
]
assert play["vars_files"] == expected_vars_files

def merge_vars_files(ordered_vars_files):
    merged = {}
    owners = {}
    for vars_file_name, vars_data in ordered_vars_files:
        assert isinstance(vars_data, dict), vars_file_name
        collisions = sorted(set(merged) & set(vars_data))
        assert not collisions, {
            "vars_file": vars_file_name,
            "collisions": collisions,
            "previous_owners": {
                key: owners[key] for key in collisions
            },
        }
        merged.update(vars_data)
        owners.update({key: vars_file_name for key in vars_data})
    return merged


def assert_operation_storage_shape(operation_vars):
    operation_state = operation_vars["operation"]["state"]
    if operation_state == "clean":
        assert operation_vars["operation"] == {
            "state": "clean",
            "authorization_ready": False,
        }
        assert "diagnostic_storage" not in operation_vars
        return

    assert operation_state in {"definition", "pending"}
    if operation_vars["operation"].get("id") != \
            "nautobot-storage-soak-verification-v1":
        assert "diagnostic_storage" not in operation_vars
        assert "storage_soak" not in operation_vars
        return

    assert operation_vars["operation"]["id"] == \
        "nautobot-storage-soak-verification-v1"
    assert operation_vars["operation"]["stage"] == \
        "storage_soak_verification"
    assert operation_vars["diagnostic_storage"]["root_device"] == "/dev/sda"
    assert operation_vars["storage_soak"]["minimum_uninterrupted_seconds"] == 86400


loaded_vars_files = []
for relative_vars_file in expected_vars_files:
    vars_file_path = (Path(playbook_path).parent / relative_vars_file).resolve()
    with open(vars_file_path, encoding="utf-8") as vars_stream:
        loaded_vars_files.append(
            (relative_vars_file, yaml.safe_load(vars_stream))
        )

merged_vars = merge_vars_files(loaded_vars_files)
assert_operation_storage_shape(loaded_vars_files[0][1])
assert merged_vars["storage"]["root"]["filesystem"] == "ext4"

assert_operation_storage_shape({
    "operation": {
        "id": "nautobot-storage-soak-verification-v1",
        "state": "pending",
        "authorization_ready": True,
        "stage": "storage_soak_verification",
    },
    "diagnostic_storage": {"root_device": "/dev/sda"},
    "storage_soak": {"minimum_uninterrupted_seconds": 86400},
})

try:
    merge_vars_files([
        ("operation.yaml", {"storage": {"root_device": "/dev/sda"}}),
        ("host.yaml", {"storage": {"root": {"filesystem": "ext4"}}}),
    ])
except AssertionError:
    pass
else:
    raise AssertionError("Top-level vars_files collision was not rejected")

allowed_modules = {
    "ansible.builtin.assert",
    "ansible.builtin.command",
    "ansible.builtin.copy",
    "ansible.builtin.set_fact",
    "ansible.builtin.stat",
}
expected_commands = {
    "Verify noninteractive read-only privilege access": [
        "/usr/bin/sudo", "-n", "/usr/bin/true"
    ],
    "Read current boot ID": [
        "/usr/bin/sudo", "-n", "/usr/bin/cat",
        "/proc/sys/kernel/random/boot_id",
    ],
    "Read current uptime": [
        "/usr/bin/sudo", "-n", "/usr/bin/cat", "/proc/uptime",
    ],
    "Read current kernel command line": [
        "/usr/bin/sudo", "-n", "/usr/bin/cat", "/proc/cmdline",
    ],
    "Read root filesystem identity": [
        "/usr/bin/sudo", "-n", "/usr/bin/findmnt", "--json", "--bytes",
        "--output=SOURCE,FSTYPE,SIZE,AVAIL,TARGET", "/",
    ],
    "Resolve the mounted root device": [
        "/usr/bin/sudo", "-n", "/usr/bin/readlink", "--canonicalize-existing",
        "{{ storage_diagnostic_root_source }}",
    ],
    "Read block topology": [
        "/usr/bin/sudo", "-n", "/usr/bin/lsblk", "--json", "--bytes",
        "--output=NAME,KNAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS,TRAN,MODEL,SERIAL",
    ],
    "Read USB driver and negotiated topology": [
        "/usr/bin/sudo", "-n", "/usr/bin/lsusb", "--tree",
    ],
    "Read root-device udev identity and attribute chain": [
        "/usr/bin/sudo", "-n", "/usr/bin/udevadm", "info",
        "--attribute-walk", "{{ diagnostic_storage.root_device }}",
    ],
    "Read current-boot kernel context": [
        "/usr/bin/sudo", "-n", "/usr/bin/journalctl",
        "--boot=0", "--dmesg",
        "--output=short-iso", "--lines={{ collection.journal_line_limit }}",
        "--no-pager", "--quiet",
    ],
    "Read focused current-boot storage events": [
        "/usr/bin/sudo", "-n", "/usr/bin/journalctl",
        "--boot=0", "--dmesg",
        "--grep={{ collection.focused_storage_event_pattern }}",
        "--output=short-iso", "--lines={{ collection.journal_line_limit }}",
        "--no-pager", "--quiet",
    ],
    "Read current-boot power and throttling kernel events": [
        "/usr/bin/sudo", "-n", "/usr/bin/journalctl",
        "--boot=0", "--dmesg",
        "--grep=under-voltage|voltage normalised|throttled|over-current",
        "--output=short-iso", "--lines={{ collection.journal_line_limit }}",
        "--no-pager", "--quiet",
    ],
    "Read Raspberry Pi throttling history": [
        "/usr/bin/sudo", "-n", "/usr/bin/vcgencmd", "get_throttled",
    ],
    "Read Raspberry Pi temperature": [
        "/usr/bin/sudo", "-n", "/usr/bin/vcgencmd", "measure_temp",
    ],
    "Read Raspberry Pi core voltage": [
        "/usr/bin/sudo", "-n", "/usr/bin/vcgencmd", "measure_volts", "core",
    ],
    "Read extended SMART and NVMe health": [
        "/usr/bin/sudo", "-n", "/usr/sbin/smartctl", "--xall",
        "{{ diagnostic_storage.root_device }}",
    ],
    "Read mounted ext4 metadata": [
        "/usr/bin/sudo", "-n", "/usr/sbin/tune2fs", "-l",
        "{{ storage_diagnostic_root_source }}",
    ],
    "Read the live ext4 error counter": [
        "/usr/bin/sudo", "-n", "/usr/bin/cat",
        "/sys/fs/ext4/{{ storage_diagnostic_root_name }}/errors_count",
    ],
}

observed_commands = {}
for task in play.get("pre_tasks", []) + play.get("tasks", []):
    modules = [key for key in task if key.startswith("ansible.builtin.")]
    assert len(modules) == 1, task.get("name")
    module = modules[0]
    assert module in allowed_modules, (task.get("name"), module)
    if module == "ansible.builtin.command":
        assert task.get("changed_when") is False
        assert task.get("check_mode") is False
        argv = task[module]["argv"]
        assert isinstance(argv, list)
        assert all(isinstance(argument, str) for argument in argv)
        assert argv[:2] == ["/usr/bin/sudo", "-n"]
        observed_commands[task["name"]] = argv
    if module == "ansible.builtin.copy":
        assert task.get("delegate_to") == "localhost"
        assert task.get("become") is False
        destination = task[module]["dest"]
        assert destination.startswith("{{ storage_diagnostic_evidence_directory }}/")

assert not any("ansible.builtin.shell" in task for task in play["tasks"])
assert observed_commands == expected_commands
PY
}

execute_operation() {
    local expected_hash=$1
    local actual_hash readiness blockers evidence_directory
    local stdout_fifo stderr_fifo stdout_consumer_pid stderr_consumer_pid
    local started_at finished_at execution_status operation_result
    local consumer_status=0
    local -a command

    [[ "$expected_hash" =~ ^[0-9a-f]{64}$ ]] || {
        printf '%s\n' 'BUNDLE_SHA256 must contain 64 lowercase hexadecimal characters.' >&2
        return 64
    }
    validate_operation
    readiness=$(operation_ready)
    blockers=$(operation_blockers)
    [[ "$readiness" == true ]] || {
        printf 'Operation is not authorization-ready: %s\n' "$blockers" >&2
        return 65
    }
    [[ -z "$(git -C "$repository_root" status --porcelain)" ]] || {
        printf '%s\n' 'Refusing execution from a dirty worktree.' >&2
        return 65
    }
    actual_hash=$(calculate_bundle_hash)
    [[ "$actual_hash" == "$expected_hash" ]] || {
        printf 'Bundle mismatch: expected %s, calculated %s\n' \
            "$expected_hash" "$actual_hash" >&2
        return 65
    }

    evidence_directory=$(mktemp -d /tmp/nautobot-storage-diagnostic.XXXXXX)
    chmod 0700 "$evidence_directory"
    write_bundle_file_hashes "${evidence_directory}/bundle-files.sha256"
    stdout_fifo="${evidence_directory}/stdout.pipe"
    stderr_fifo="${evidence_directory}/stderr.pipe"
    mkfifo -m 0600 "$stdout_fifo" "$stderr_fifo"
    command=(
        ansible-playbook
        --inventory "$inventory_file"
        --limit "$operation_target"
        --user "$operation_user"
        --extra-vars "ansible_host=${operation_address}"
        --extra-vars "storage_diagnostic_evidence_directory=${evidence_directory}"
        "$playbook_file"
    )

    consume_bounded_stream "$stdout_fifo" \
        "${evidence_directory}/stdout.log" \
        "${evidence_directory}/stdout.truncated" \
        "$evidence_limit_bytes" &
    stdout_consumer_pid=$!
    consume_bounded_stream "$stderr_fifo" \
        "${evidence_directory}/stderr.log" \
        "${evidence_directory}/stderr.truncated" \
        "$evidence_limit_bytes" &
    stderr_consumer_pid=$!

    started_at=$(date --utc +%Y-%m-%dT%H:%M:%SZ)
    set +e
    "${command[@]}" >"$stdout_fifo" 2>"$stderr_fifo"
    execution_status=$?
    set -e
    wait "$stdout_consumer_pid" || consumer_status=1
    wait "$stderr_consumer_pid" || consumer_status=1
    rm -f -- "$stdout_fifo" "$stderr_fifo"
    finished_at=$(date --utc +%Y-%m-%dT%H:%M:%SZ)
    printf 'ansible_playbook_exit_status=%s\n' "$execution_status" \
        >"${evidence_directory}/status.txt"

    operation_result=$(classify_result "$evidence_directory" "$execution_status")
    write_evidence_manifest "$evidence_directory" "$actual_hash" \
        "$started_at" "$finished_at" "$execution_status" "$operation_result"

    printf 'Storage diagnostic evidence: %s\n' "$evidence_directory"
    printf 'Diagnostic result: %s\n' "$operation_result"
    [[ "$consumer_status" -eq 0 && "$operation_result" == collected ]]
}

run_self_test() {
    local classification_directory self_test_directory self_test_fifo
    local self_test_log self_test_marker
    local self_test_consumer_pid

    verify_read_only_playbook

    self_test_directory=$(mktemp -d /tmp/nautobot-storage-diagnostic-self-test.XXXXXX)
    case "$self_test_directory" in
        /tmp/nautobot-storage-diagnostic-self-test.*) ;;
        *) return 70 ;;
    esac
    self_test_fifo="${self_test_directory}/stream.pipe"
    self_test_log="${self_test_directory}/stdout.log"
    self_test_marker="${self_test_directory}/stdout.truncated"
    mkfifo -m 0600 "$self_test_fifo"
    consume_bounded_stream "$self_test_fifo" "$self_test_log" \
        "$self_test_marker" 1024 &
    self_test_consumer_pid=$!
    awk 'BEGIN { for (i = 0; i < 2048; i++) printf "x" }' >"$self_test_fifo"
    wait "$self_test_consumer_pid"
    [[ $(stat --format=%s "$self_test_log") -eq 1024 ]]
    [[ -f "$self_test_marker" ]]
    [[ $(stat --format=%a "$self_test_directory") == 700 ]]
    classification_directory="${self_test_directory}/classification"
    mkdir "$classification_directory"
    [[ $(classify_result "$classification_directory" 2) == incomplete ]]
    : >"${classification_directory}/diagnostic.yaml"
    [[ $(classify_result "$classification_directory" 2) == incomplete ]]
    [[ $(classify_result "$classification_directory" 0) == collected ]]
    : >"${classification_directory}/stderr.truncated"
    [[ $(classify_result "$classification_directory" 0) == incomplete ]]
    ANSIBLE_LOCAL_TEMP="${self_test_directory}/ansible-local" \
        ansible-playbook \
        --syntax-check \
        --inventory "$inventory_file" \
        "$playbook_file"
    rm -rf -- "$self_test_directory"
    printf '%s\n' 'Storage diagnostic launcher self-test passed.'
}

case "${1:-}" in
    show-bundle)
        [[ $# -eq 1 ]] || {
            usage >&2
            exit 64
        }
        show_bundle
        ;;
    execute)
        [[ $# -eq 2 ]] || {
            usage >&2
            exit 64
        }
        execute_operation "$2"
        ;;
    self-test)
        [[ $# -eq 1 ]] || {
            usage >&2
            exit 64
        }
        run_self_test
        ;;
    *)
        usage >&2
        exit 64
        ;;
esac
