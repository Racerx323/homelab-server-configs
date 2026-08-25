#!/bin/bash
set -euo pipefail
umask 077

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly script_directory
repository_root=$(cd -- "${script_directory}/../../.." && pwd -P)
readonly repository_root
readonly operation_file="${repository_root}/Nautobot/manifests/operation.yaml"
readonly operation_schema="${repository_root}/Nautobot/schemas/operation.schema.json"
readonly inventory_file="${repository_root}/inventory/prod/hosts.yaml"
readonly playbook_file="${repository_root}/Nautobot/ansible/playbooks/apply-uas-quirk.yaml"
readonly operation_target=j2-svpi4mf
readonly operation_address=10.1.2.170
readonly operation_user=ama
readonly evidence_limit_bytes=8388608
readonly -a bundle_files=(
    inventory/prod/hosts.yaml
    inventory/prod/groups/inventory_automation.yaml
    inventory/prod/hosts/j2-svpi4mf.yaml
    Nautobot/docs/STORAGE_REMEDIATION_DECISION.md
    Nautobot/manifests/operation.yaml
    Nautobot/schemas/operation.schema.json
    Nautobot/ansible/playbooks/apply-uas-quirk.yaml
    Nautobot/ansible/scripts/run-uas-quirk.sh
)

usage() {
    printf '%s\n' \
        "Usage:" \
        "  ${0##*/} show-bundle" \
        "  ${0##*/} preflight" \
        "  ${0##*/} execute BUNDLE_SHA256" \
        "  ${0##*/} self-test"
}

validate_operation() {
    check-jsonschema --schemafile "$operation_schema" "$operation_file"
}

require_active_operation() {
    [[ $(operation_value 'd["operation"].get("id", "")') == nautobot-uas-quirk-v2 ]] || {
        printf '%s\n' 'No Nautobot UAS-quirk operation is active.' >&2
        return 65
    }
}

operation_value() {
    python3 - "$operation_file" "$1" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as stream:
    d = yaml.safe_load(stream)
print(eval(sys.argv[2], {"__builtins__": {"bool": bool, "str": str}}, {"d": d}))
PY
}

preflight_is_fresh() {
    local comparison_time=${1:-}
    local completed_override=${2:-}

    python3 - "$operation_file" "$comparison_time" "$completed_override" <<'PY'
import datetime
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as stream:
    operation = yaml.safe_load(stream)
preflight = operation.get("preflight", {})
completed_text = sys.argv[3] or preflight.get("completed_at_utc")
if completed_text is None:
    print("false")
    raise SystemExit
completed = datetime.datetime.fromisoformat(completed_text.replace("Z", "+00:00"))
if sys.argv[2]:
    now = datetime.datetime.fromisoformat(sys.argv[2].replace("Z", "+00:00"))
else:
    now = datetime.datetime.now(datetime.timezone.utc)
maximum_age = datetime.timedelta(minutes=preflight.get("maximum_age_minutes", 30))
print(str(completed <= now <= completed + maximum_age).lower())
PY
}

write_bundle_file_hashes() {
    local destination_file=$1
    local relative_path absolute_path

    : >"$destination_file"
    for relative_path in "${bundle_files[@]}"; do
        absolute_path="${repository_root}/${relative_path}"
        [[ -f "$absolute_path" && ! -L "$absolute_path" ]] || {
            printf 'Invalid bundle input: %s\n' "$relative_path" >&2
            return 65
        }
        printf '%s  %s\n' \
            "$(sha256sum "$absolute_path" | cut -d ' ' -f 1)" \
            "$relative_path" >>"$destination_file"
    done
}

calculate_bundle_hash() {
    local bundle_file_list

    bundle_file_list=$(mktemp /tmp/nautobot-uas-quirk-bundle.XXXXXX)
    write_bundle_file_hashes "$bundle_file_list"
    {
        printf '%s\n' nautobot-uas-quirk-bundle-v2
        cat "$bundle_file_list"
    } | sha256sum | cut -d ' ' -f 1
    rm -f -- "$bundle_file_list"
}

show_bundle() {
    local bundle_file_list

    validate_operation
    require_active_operation
    bundle_file_list=$(mktemp /tmp/nautobot-uas-quirk-bundle.XXXXXX)
    write_bundle_file_hashes "$bundle_file_list"
    printf 'bundle_sha256=%s\n' "$(calculate_bundle_hash)"
    cat "$bundle_file_list"
    rm -f -- "$bundle_file_list"
    printf 'authorization_ready=%s\n' \
        "$(operation_value 'str(bool(d["operation"]["authorization_ready"])).lower()')"
    printf 'preflight_fresh=%s\n' "$(preflight_is_fresh)"
    printf 'blockers=%s\n' \
        "$(operation_value '",".join(d["authorization"]["blockers"])')"
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

write_evidence_manifest() {
    local evidence_directory=$1
    local bundle_hash=$2
    local started_at=$3
    local finished_at=$4
    local execution_status=$5
    local result=$6
    local evidence_name evidence_path
    local -a evidence_names=(
        bundle-files.sha256
        stdout.log
        stderr.log
        status.txt
        preflight.yaml
        mutation.yaml
        forward-observations.yaml
        reboot-acceptance.yaml
        rollback-observations.yaml
        rollback.yaml
    )

    {
        printf '%s\n' '---' 'schema_version: 1' 'operation_id: nautobot-uas-quirk-v2'
        printf 'target: %s\naddress: %s\n' "$operation_target" "$operation_address"
        printf 'bundle_sha256: %s\nstarted_at_utc: %s\nfinished_at_utc: %s\n' \
            "$bundle_hash" "$started_at" "$finished_at"
        printf 'ansible_exit_status: %s\nresult: %s\n' "$execution_status" "$result"
        printf '%s\n' 'evidence:'
        for evidence_name in "${evidence_names[@]}"; do
            evidence_path="${evidence_directory}/${evidence_name}"
            printf '  - file: %s\n' "$evidence_name"
            if [[ -f "$evidence_path" ]]; then
                printf '%s\n' '    present: true'
                printf '    bytes: %s\n' "$(stat --format=%s "$evidence_path")"
                printf '    sha256: %s\n' "$(sha256sum "$evidence_path" | cut -d ' ' -f 1)"
            else
                printf '%s\n' '    present: false'
            fi
        done
    } >"${evidence_directory}/manifest.yaml"
}

classify_result() {
    local evidence_directory=$1
    local execution_status=$2
    local mode=$3

    if [[ -f "${evidence_directory}/stdout.truncated" ||
        -f "${evidence_directory}/stderr.truncated" ]]; then
        printf '%s\n' manual_intervention
    elif [[ "$execution_status" -eq 0 && "$mode" == preflight &&
        -f "${evidence_directory}/preflight.yaml" ]]; then
        printf '%s\n' preflight_passed
    elif [[ "$execution_status" -eq 0 &&
        -f "${evidence_directory}/reboot-acceptance.yaml" ]]; then
        printf '%s\n' initial_acceptance_pending_soak
    elif [[ -f "${evidence_directory}/rollback.yaml" ]]; then
        printf '%s\n' rolled_back
    elif [[ -f "${evidence_directory}/mutation.yaml" ]]; then
        printf '%s\n' manual_intervention
    else
        printf '%s\n' preflight_failed
    fi
}

verify_playbook() {
    python3 - "$playbook_file" <<'PY'
import base64
import copy
import sys
import yaml
from jinja2.nativetypes import NativeEnvironment

with open(sys.argv[1], encoding="utf-8") as stream:
    playbook = yaml.safe_load(stream)
assert len(playbook) == 1
play = playbook[0]
assert play["hosts"] == "inventory_automation"
assert play["gather_facts"] is False
assert play["become"] is False
serialized = yaml.safe_dump(play, sort_keys=True)
operation_blocks = [task for task in play["tasks"] if "block" in task]
assert len(operation_blocks) == 1
operation_block = operation_blocks[0]
block_tasks = operation_block["block"]
rescue_tasks = operation_block["rescue"]
replace_tasks = [
    task["ansible.builtin.replace"]
    for task in block_tasks
    if "ansible.builtin.replace" in task
]
task_by_name = {task["name"]: task for task in block_tasks + rescue_tasks}
assert "ansible.builtin.shell" not in serialized
assert "ansible.builtin.raw" not in serialized
assert ".split().count(" not in serialized
assert serialized.count("ansible.builtin.reboot") == 2
assert "usb-storage.quirks=152d:0583:u" not in serialized
assert "mutation.append_token" in serialized
assert len(replace_tasks) == 1
assert replace_tasks[0]["regexp"] == r"\Z"
assert replace_tasks[0]["replace"] == " {{ mutation.append_token }}"
assert "Create the exact rollback copy" not in serialized
assert "uas_quirk_backup.stat.checksum == rollback.expected_restored_sha256" in serialized
assert "uas_quirk_boot_content.content" in serialized
assert block_tasks.index(task_by_name["Record that the boot-file mutation completed"]) == 1
assert block_tasks.index(task_by_name["Enforce the exact boot-file mutation"]) == 3
assert block_tasks.index(task_by_name["Record forward observations before acceptance"]) < block_tasks.index(task_by_name["Enforce immediate reboot acceptance"])
assert rescue_tasks.index(task_by_name["Record rollback observations before acceptance"]) < rescue_tasks.index(task_by_name["Enforce rollback acceptance"])
original = "console=tty1 root=PARTUUID=3e6cba06-02 rootwait"
mutated = __import__("re").sub(
    replace_tasks[0]["regexp"],
    " usb-storage.quirks=152d:0583:u",
    original,
)
assert mutated == original + " usb-storage.quirks=152d:0583:u"
assert "\n" not in mutated
exact_condition = task_by_name["Enforce the exact boot-file mutation"]["ansible.builtin.assert"]["that"][0]
environment = NativeEnvironment(autoescape=False)
environment.filters["b64decode"] = lambda value: base64.b64decode(value).decode("utf-8")
environment.filters["split"] = lambda value, separator=None, maxsplit=-1: value.split(separator, maxsplit)
environment.filters["trim"] = lambda value: value.strip()
condition_template = environment.from_string("{{ (%s) | string | lower }}" % exact_condition)
template_variables = {
    "mutation": {"append_token": "usb-storage.quirks=152d:0583:u"},
    "uas_quirk_boot_content": {"content": base64.b64encode(original.encode()).decode()},
    "uas_quirk_mutated_content": {
        "content": base64.b64encode(mutated.encode()).decode()
    },
}
assert condition_template.render(**template_variables) == "true"
template_variables["uas_quirk_mutated_content"]["content"] = base64.b64encode(
    (mutated + " usb-storage.quirks=152d:0583:u").encode()
).decode()
assert condition_template.render(**template_variables) == "false"

def evaluate_conditions(task_name, variables):
    conditions = task_by_name[task_name]["ansible.builtin.assert"]["that"]
    return [
        bool(environment.compile_expression(str(condition))(**variables))
        for condition in conditions
    ]

token = "usb-storage.quirks=152d:0583:u"
forward_variables = {
    "mutation": {"append_token": token},
    "acceptance": {
        "immediate": {
            "require_cmdline_token_count": 1,
            "require_root_source": "/dev/sda2",
            "require_usb_vendor_id": "152d",
            "require_usb_product_id": "0583",
            "require_usb_driver": "usb-storage",
            "reject_usb_driver": "uas",
        }
    },
    "uas_quirk_cmdline_after": {"stdout": original + " " + token},
    "uas_quirk_root_after": {"stdout": "/dev/sda2\n"},
    "uas_quirk_udev_after": {
        "stdout_lines": [
            "ID_VENDOR_ID=152d",
            "ID_MODEL_ID=0583",
            "ID_USB_DRIVER=usb-storage",
        ]
    },
    "uas_quirk_failed_units": {"stdout": ""},
    "uas_quirk_storage_events": {"stdout": ""},
}
assert evaluate_conditions("Enforce immediate reboot acceptance", forward_variables) == [True] * 8
forward_failures = (
    ("uas_quirk_cmdline_after", "stdout", original + " " + token + " " + token, 0),
    ("uas_quirk_root_after", "stdout", "/dev/mmcblk0p2\n", 1),
    ("uas_quirk_udev_after", "stdout_lines", ["ID_MODEL_ID=0583", "ID_USB_DRIVER=usb-storage"], 2),
    ("uas_quirk_udev_after", "stdout_lines", ["ID_VENDOR_ID=152d", "ID_USB_DRIVER=usb-storage"], 3),
    ("uas_quirk_udev_after", "stdout_lines", ["ID_VENDOR_ID=152d", "ID_MODEL_ID=0583", "ID_USB_DRIVER=uas"], 4),
    ("uas_quirk_failed_units", "stdout", "failed.service", 6),
    ("uas_quirk_storage_events", "stdout", "I/O error", 7),
)
for variable, field, bad_value, failed_index in forward_failures:
    scenario = copy.deepcopy(forward_variables)
    scenario[variable][field] = bad_value
    assert evaluate_conditions("Enforce immediate reboot acceptance", scenario)[failed_index] is False

rollback_variables = {
    "mutation": {"append_token": token},
    "preflight": {"expected": {"root_source": "/dev/sda2", "usb_driver": "uas"}},
    "uas_quirk_rollback_cmdline": {"stdout": original},
    "uas_quirk_rollback_root": {"stdout": "/dev/sda2\n"},
    "uas_quirk_rollback_udev": {"stdout_lines": ["ID_USB_DRIVER=uas"]},
}
restored_variables = {
    "rollback": {"expected_restored_sha256": "expected-hash"},
    "uas_quirk_restored_file": {"stat": {"checksum": "expected-hash"}},
}
assert evaluate_conditions("Enforce restored boot-file identity", restored_variables) == [True]
restored_variables["uas_quirk_restored_file"]["stat"]["checksum"] = "wrong-hash"
assert evaluate_conditions("Enforce restored boot-file identity", restored_variables) == [False]
assert evaluate_conditions("Enforce rollback acceptance", rollback_variables) == [True] * 3
rollback_failures = (
    ("uas_quirk_rollback_cmdline", "stdout", original + " " + token, 0),
    ("uas_quirk_rollback_root", "stdout", "/dev/mmcblk0p2\n", 1),
    ("uas_quirk_rollback_udev", "stdout_lines", ["ID_USB_DRIVER=usb-storage"], 2),
)
for variable, field, bad_value, failed_index in rollback_failures:
    scenario = copy.deepcopy(rollback_variables)
    scenario[variable][field] = bad_value
    assert evaluate_conditions("Enforce rollback acceptance", scenario)[failed_index] is False
for task_name in (
    "Read the post-reboot kernel command line",
    "Read the post-reboot root source",
    "Read the post-reboot bridge driver",
    "Read post-reboot failed units",
    "Read new storage events",
    "Read rollback kernel command line",
    "Read rollback bridge driver",
    "Read rollback root source",
):
    assert task_by_name[task_name]["become"] is False
assert task_by_name["Read new storage events"]["ansible.builtin.command"]["argv"][:3] == [
    "/usr/bin/sudo", "-n", "/usr/bin/journalctl"
]
assert serialized.count("remote_src: true") == 1
assert "ID_USB_DRIVER=" in serialized
assert "passed_pending_24_hour_soak" in serialized
PY
}

verify_classification() {
    local test_directory expected_result actual_result execution_status mode
    local marker

    classification_case() {
        expected_result=$1
        execution_status=$2
        mode=$3
        shift 3
        test_directory=$(mktemp -d /tmp/nautobot-uas-classification.XXXXXX)
        for marker in "$@"; do
            : >"${test_directory}/${marker}"
        done
        actual_result=$(classify_result "$test_directory" "$execution_status" "$mode")
        [[ "$actual_result" == "$expected_result" ]]
        rm -f -- "${test_directory}"/*
        rmdir -- "$test_directory"
    }

    classification_case preflight_passed 0 preflight preflight.yaml
    classification_case initial_acceptance_pending_soak 0 execute mutation.yaml forward-observations.yaml reboot-acceptance.yaml
    classification_case rolled_back 2 execute mutation.yaml forward-observations.yaml rollback-observations.yaml rollback.yaml
    classification_case manual_intervention 2 execute mutation.yaml forward-observations.yaml
    classification_case manual_intervention 2 execute rollback.yaml stdout.truncated
    classification_case preflight_failed 2 execute
    classification_case preflight_failed 0 execute
}

verify_evidence_modes() {
    local test_directory test_path
    local -a test_files=(
        bundle-files.sha256
        stdout.log
        stderr.log
        status.txt
        preflight.yaml
        manifest.yaml
    )

    test_directory=$(mktemp -d /tmp/nautobot-uas-quirk-self-test.XXXXXX)
    case "$test_directory" in
        /tmp/nautobot-uas-quirk-self-test.*) ;;
        *)
            printf 'Unexpected self-test directory: %s\n' "$test_directory" >&2
            return 65
            ;;
    esac
    chmod 0700 "$test_directory"
    write_bundle_file_hashes "${test_directory}/bundle-files.sha256"
    : >"${test_directory}/stdout.log"
    : >"${test_directory}/stderr.log"
    printf '%s\n' ansible_playbook_exit_status=0 >"${test_directory}/status.txt"
    printf '%s\n' '---' 'result: passed' >"${test_directory}/preflight.yaml"
    write_evidence_manifest "$test_directory" \
        0000000000000000000000000000000000000000000000000000000000000000 \
        1970-01-01T00:00:00Z 1970-01-01T00:00:01Z 0 preflight_passed

    [[ "$(stat --format=%a "$test_directory")" == 700 ]]
    for test_path in "${test_files[@]}"; do
        [[ -f "${test_directory}/${test_path}" ]]
        [[ ! -L "${test_directory}/${test_path}" ]]
        [[ "$(stat --format=%a "${test_directory}/${test_path}")" == 600 ]]
    done

    rm -f -- \
        "${test_directory}/bundle-files.sha256" \
        "${test_directory}/stdout.log" \
        "${test_directory}/stderr.log" \
        "${test_directory}/status.txt" \
        "${test_directory}/preflight.yaml" \
        "${test_directory}/manifest.yaml"
    rmdir -- "$test_directory"
}

run_operation() {
    local mode=$1
    local expected_hash=${2:-}
    local actual_hash readiness blockers evidence_directory
    local stdout_fifo stderr_fifo stdout_consumer_pid stderr_consumer_pid
    local started_at finished_at execution_status consumer_status=0 result
    local -a command

    validate_operation
    require_active_operation
    [[ -z "$(git -C "$repository_root" status --porcelain)" ]] || {
        printf '%s\n' 'Refusing host contact from a dirty worktree.' >&2
        return 65
    }
    actual_hash=$(calculate_bundle_hash)
    if [[ "$mode" == execute ]]; then
        [[ "$expected_hash" =~ ^[0-9a-f]{64}$ ]] || {
            printf '%s\n' 'BUNDLE_SHA256 must contain 64 lowercase hexadecimal characters.' >&2
            return 64
        }
        readiness=$(operation_value 'str(bool(d["operation"]["authorization_ready"])).lower()')
        blockers=$(operation_value '",".join(d["authorization"]["blockers"])')
        [[ "$readiness" == true && -z "$blockers" ]] || {
            printf 'Operation is not authorization-ready: %s\n' "$blockers" >&2
            return 65
        }
        [[ "$(preflight_is_fresh)" == true ]] || {
            printf '%s\n' 'Operation preflight is absent or older than its allowed lifetime.' >&2
            return 65
        }
        [[ "$actual_hash" == "$expected_hash" ]] || {
            printf 'Bundle mismatch: expected %s, calculated %s\n' "$expected_hash" "$actual_hash" >&2
            return 65
        }
    fi

    evidence_directory=$(mktemp -d /tmp/nautobot-uas-quirk.XXXXXX)
    chmod 0700 "$evidence_directory"
    write_bundle_file_hashes "${evidence_directory}/bundle-files.sha256"
    stdout_fifo="${evidence_directory}/stdout.pipe"
    stderr_fifo="${evidence_directory}/stderr.pipe"
    mkfifo -m 0600 "$stdout_fifo" "$stderr_fifo"
    command=(ansible-playbook --inventory "$inventory_file" --limit "$operation_target" --user "$operation_user" --extra-vars "ansible_host=${operation_address}" --extra-vars "uas_quirk_evidence_directory=${evidence_directory}")
    if [[ "$mode" == preflight ]]; then
        command+=(--check --extra-vars uas_quirk_preflight_only=true)
    fi
    command+=("$playbook_file")

    consume_bounded_stream "$stdout_fifo" "${evidence_directory}/stdout.log" "${evidence_directory}/stdout.truncated" "$evidence_limit_bytes" &
    stdout_consumer_pid=$!
    consume_bounded_stream "$stderr_fifo" "${evidence_directory}/stderr.log" "${evidence_directory}/stderr.truncated" "$evidence_limit_bytes" &
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
    printf 'ansible_playbook_exit_status=%s\n' "$execution_status" >"${evidence_directory}/status.txt"

    result=$(classify_result "$evidence_directory" "$execution_status" "$mode")
    write_evidence_manifest "$evidence_directory" "$actual_hash" "$started_at" "$finished_at" "$execution_status" "$result"
    printf 'UAS-quirk evidence: %s\nResult: %s\n' "$evidence_directory" "$result"
    [[ "$consumer_status" -eq 0 && "$result" != manual_intervention && "$result" != preflight_failed ]]
}

self_test() {
    validate_operation
    verify_playbook
    verify_classification
    verify_evidence_modes
    [[ "$(preflight_is_fresh 2026-08-25T19:16:00Z 2026-08-25T19:15:48Z)" == true ]]
    [[ "$(preflight_is_fresh 2026-08-25T19:46:00Z 2026-08-25T19:15:48Z)" == false ]]
    ansible-playbook --syntax-check --inventory "$inventory_file" "$playbook_file" >/dev/null
    calculate_bundle_hash >/dev/null
    printf '%s\n' 'UAS-quirk launcher self-test passed.'
}

case "${1:-}" in
    show-bundle)
        [[ $# -eq 1 ]] || {
            usage >&2
            exit 64
        }
        show_bundle
        ;;
    preflight)
        [[ $# -eq 1 ]] || {
            usage >&2
            exit 64
        }
        run_operation preflight
        ;;
    execute)
        [[ $# -eq 2 ]] || {
            usage >&2
            exit 64
        }
        run_operation execute "$2"
        ;;
    self-test)
        [[ $# -eq 1 ]] || {
            usage >&2
            exit 64
        }
        self_test
        ;;
    *)
        usage >&2
        exit 64
        ;;
esac
