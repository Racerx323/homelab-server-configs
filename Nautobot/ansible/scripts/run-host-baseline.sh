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
readonly playbook_file="${repository_root}/Nautobot/ansible/playbooks/host-baseline.yaml"
readonly operation_target=j2-svpi4mf
readonly operation_address=10.1.2.170
readonly operation_user=ama
readonly evidence_limit_bytes=8388608
readonly -a bundle_files=(
    Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md
    Nautobot/manifests/desired-state.yaml
    Nautobot/manifests/operation.yaml
    Nautobot/schemas/operation.schema.json
    Nautobot/ansible/playbooks/host-baseline.yaml
    Nautobot/ansible/tasks/rollback-host-baseline.yaml
    Nautobot/ansible/scripts/run-host-baseline.sh
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
        'import sys,yaml; print(",".join(yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["authorization"]["blockers"]))' \
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
    local bundle_file_list
    local calculated_hash

    bundle_file_list=$(mktemp /tmp/nautobot-host-baseline-bundle.XXXXXX)
    write_bundle_file_hashes "$bundle_file_list"
    calculated_hash=$(
        {
            printf '%s\n' 'nautobot-host-baseline-bundle-v1'
            cat "$bundle_file_list"
        } | sha256sum | cut -d ' ' -f 1
    )
    rm -f -- "$bundle_file_list"
    printf '%s\n' "$calculated_hash"
}

show_bundle() {
    local bundle_hash readiness blockers
    local bundle_file_list

    validate_operation
    bundle_hash=$(calculate_bundle_hash)
    readiness=$(operation_ready)
    blockers=$(operation_blockers)
    bundle_file_list=$(mktemp /tmp/nautobot-host-baseline-bundle.XXXXXX)
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

write_execution_manifest() {
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
        preflight.yaml
        mutation.yaml
        acceptance.yaml
        rollback.yaml
        residue.yaml
    )

    {
        printf '%s\n' '---' 'schema_version: 1'
        printf '%s\n' 'operation_id: nautobot-host-baseline-v1'
        printf 'target: %s\n' "$operation_target"
        printf 'address: %s\n' "$operation_address"
        printf 'bundle_sha256: %s\n' "$bundle_hash"
        printf 'started_at_utc: %s\n' "$started_at"
        printf 'finished_at_utc: %s\n' "$finished_at"
        printf 'ansible_exit_status: %s\n' "$execution_status"
        printf 'result: %s\n' "$operation_result"
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
        printf '%s\n' 'Refusing live execution from a dirty worktree.' >&2
        return 65
    }
    actual_hash=$(calculate_bundle_hash)
    [[ "$actual_hash" == "$expected_hash" ]] || {
        printf 'Bundle mismatch: expected %s, calculated %s\n' \
            "$expected_hash" "$actual_hash" >&2
        return 65
    }

    evidence_directory=$(mktemp -d /tmp/nautobot-host-baseline.XXXXXX)
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
        --extra-vars "host_baseline_evidence_directory=${evidence_directory}"
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

    operation_result=manual_intervention
    if [[ "$execution_status" -eq 0 &&
        -f "${evidence_directory}/acceptance.yaml" &&
        ! -f "${evidence_directory}/stdout.truncated" &&
        ! -f "${evidence_directory}/stderr.truncated" ]]; then
        operation_result=accepted
    elif [[ -f "${evidence_directory}/rollback.yaml" ]]; then
        operation_result=rolled_back
    fi
    write_execution_manifest "$evidence_directory" "$actual_hash" \
        "$started_at" "$finished_at" "$execution_status" "$operation_result"

    printf 'Host-baseline evidence: %s\n' "$evidence_directory"
    printf 'Operation result: %s\n' "$operation_result"
    if [[ "$consumer_status" -ne 0 ]]; then
        printf '%s\n' 'Evidence capture failed.' >&2
        return 70
    fi
    [[ "$operation_result" == accepted ]]
}

run_self_test() {
    local self_test_directory self_test_fifo self_test_log self_test_marker
    local self_test_consumer_pid self_test_hash

    validate_operation
    self_test_hash=$(calculate_bundle_hash)
    [[ "$self_test_hash" =~ ^[0-9a-f]{64}$ ]]

    self_test_directory=$(mktemp -d /tmp/nautobot-host-baseline-self-test.XXXXXX)
    case "$self_test_directory" in
        /tmp/nautobot-host-baseline-self-test.*) ;;
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
    ANSIBLE_LOCAL_TEMP="${self_test_directory}/ansible-local" \
        ansible-playbook \
        --syntax-check \
        --inventory "$inventory_file" \
        "$playbook_file"
    rm -rf -- "$self_test_directory"
    printf '%s\n' 'Host-baseline launcher self-test passed.'
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
