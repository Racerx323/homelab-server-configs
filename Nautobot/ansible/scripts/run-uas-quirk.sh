#!/bin/bash
set -euo pipefail

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

operation_value() {
    python3 - "$operation_file" "$1" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as stream:
    d = yaml.safe_load(stream)
print(eval(sys.argv[2], {"__builtins__": {"bool": bool, "str": str}}, {"d": d}))
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
        printf '%s\n' nautobot-uas-quirk-bundle-v1
        cat "$bundle_file_list"
    } | sha256sum | cut -d ' ' -f 1
    rm -f -- "$bundle_file_list"
}

show_bundle() {
    local bundle_file_list

    validate_operation
    bundle_file_list=$(mktemp /tmp/nautobot-uas-quirk-bundle.XXXXXX)
    write_bundle_file_hashes "$bundle_file_list"
    printf 'bundle_sha256=%s\n' "$(calculate_bundle_hash)"
    cat "$bundle_file_list"
    rm -f -- "$bundle_file_list"
    printf 'authorization_ready=%s\n' \
        "$(operation_value 'str(bool(d["operation"]["authorization_ready"])).lower()')"
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
    local -a evidence_names=(bundle-files.sha256 stdout.log stderr.log status.txt preflight.yaml mutation.yaml reboot-acceptance.yaml rollback.yaml)

    {
        printf '%s\n' '---' 'schema_version: 1' 'operation_id: nautobot-uas-quirk-v1'
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

verify_playbook() {
    python3 - "$playbook_file" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as stream:
    playbook = yaml.safe_load(stream)
assert len(playbook) == 1
play = playbook[0]
assert play["hosts"] == "inventory_automation"
assert play["gather_facts"] is False
assert play["become"] is False
serialized = yaml.safe_dump(play, sort_keys=True)
operation_block = play["tasks"][2]
replace_tasks = [
    task["ansible.builtin.replace"]
    for task in operation_block["block"]
    if "ansible.builtin.replace" in task
]
assert "ansible.builtin.shell" not in serialized
assert "ansible.builtin.raw" not in serialized
assert serialized.count("ansible.builtin.reboot") == 2
assert "usb-storage.quirks=152d:0583:u" not in serialized
assert "mutation.append_token" in serialized
assert len(replace_tasks) == 1
assert replace_tasks[0]["regexp"] == r"\Z"
assert replace_tasks[0]["replace"] == " {{ mutation.append_token }}"
original = "console=tty1 root=PARTUUID=3e6cba06-02 rootwait"
mutated = __import__("re").sub(
    replace_tasks[0]["regexp"],
    " usb-storage.quirks=152d:0583:u",
    original,
)
assert mutated == original + " usb-storage.quirks=152d:0583:u"
assert "\n" not in mutated
assert "remote_src: true" in serialized
assert "ID_USB_DRIVER=" in serialized
assert "passed_pending_24_hour_soak" in serialized
PY
}

run_operation() {
    local mode=$1
    local expected_hash=${2:-}
    local actual_hash readiness blockers evidence_directory
    local stdout_fifo stderr_fifo stdout_consumer_pid stderr_consumer_pid
    local started_at finished_at execution_status consumer_status=0 result
    local -a command

    validate_operation
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

    if [[ "$execution_status" -eq 0 && "$mode" == preflight && -f "${evidence_directory}/preflight.yaml" ]]; then
        result=preflight_passed
    elif [[ "$execution_status" -eq 0 && -f "${evidence_directory}/reboot-acceptance.yaml" ]]; then
        result=initial_acceptance_pending_soak
    elif [[ -f "${evidence_directory}/rollback.yaml" ]]; then
        result=rolled_back
    elif [[ -f "${evidence_directory}/mutation.yaml" ]]; then
        result=manual_intervention
    else
        result=preflight_failed
    fi
    [[ ! -f "${evidence_directory}/stdout.truncated" && ! -f "${evidence_directory}/stderr.truncated" ]] || result=manual_intervention
    write_evidence_manifest "$evidence_directory" "$actual_hash" "$started_at" "$finished_at" "$execution_status" "$result"
    printf 'UAS-quirk evidence: %s\nResult: %s\n' "$evidence_directory" "$result"
    [[ "$consumer_status" -eq 0 && "$result" != manual_intervention && "$result" != preflight_failed ]]
}

self_test() {
    validate_operation
    verify_playbook
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
