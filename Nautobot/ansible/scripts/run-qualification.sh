#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository_root=$(cd -- "${script_directory}/../../.." && pwd)
readonly script_directory repository_root
readonly qualification_inventory="${repository_root}/inventory/prod/hosts.yaml"
readonly qualification_playbook="${repository_root}/Nautobot/ansible/playbooks/qualify-host.yaml"
readonly qualification_group_vars="${repository_root}/inventory/prod/groups/inventory_automation.yaml"
readonly qualification_host_vars="${repository_root}/inventory/prod/hosts/j2-svpi4mf.yaml"
readonly qualification_target=j2-svpi4mf
readonly qualification_address=10.1.2.170
readonly qualification_user=ama
readonly evidence_limit_bytes=4194304

usage() {
    printf '%s\n' \
        "Usage:" \
        "  ${0##*/} show-command" \
        "  ${0##*/} execute" \
        "  ${0##*/} self-test"
}

qualification_command() {
    printf '%q ' \
        ansible-playbook \
        --inventory "$qualification_inventory" \
        --limit "$qualification_target" \
        --user "$qualification_user" \
        --extra-vars "ansible_host=${qualification_address}" \
        --check \
        "$qualification_playbook"
    printf '\n'
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
    local started_at=$2
    local finished_at=$3
    local execution_status=$4
    local stdout_bytes stderr_bytes status_bytes
    local stdout_hash stderr_hash status_hash
    local launcher_hash playbook_hash inventory_hash group_vars_hash host_vars_hash
    local stdout_truncated=false
    local stderr_truncated=false

    stdout_bytes=$(stat --format=%s "${evidence_directory}/stdout.log")
    stderr_bytes=$(stat --format=%s "${evidence_directory}/stderr.log")
    status_bytes=$(stat --format=%s "${evidence_directory}/status.txt")
    stdout_hash=$(sha256sum "${evidence_directory}/stdout.log" | cut -d ' ' -f 1)
    stderr_hash=$(sha256sum "${evidence_directory}/stderr.log" | cut -d ' ' -f 1)
    status_hash=$(sha256sum "${evidence_directory}/status.txt" | cut -d ' ' -f 1)
    launcher_hash=$(sha256sum "${BASH_SOURCE[0]}" | cut -d ' ' -f 1)
    playbook_hash=$(sha256sum "$qualification_playbook" | cut -d ' ' -f 1)
    inventory_hash=$(sha256sum "$qualification_inventory" | cut -d ' ' -f 1)
    group_vars_hash=$(sha256sum "$qualification_group_vars" | cut -d ' ' -f 1)
    host_vars_hash=$(sha256sum "$qualification_host_vars" | cut -d ' ' -f 1)
    [[ ! -e "${evidence_directory}/stdout.truncated" ]] || stdout_truncated=true
    [[ ! -e "${evidence_directory}/stderr.truncated" ]] || stderr_truncated=true

    {
        printf '%s\n' '---' 'schema_version: 1'
        printf 'target: %s\n' "$qualification_target"
        printf 'address: %s\n' "$qualification_address"
        printf 'started_at_utc: %s\n' "$started_at"
        printf 'finished_at_utc: %s\n' "$finished_at"
        printf 'exit_status: %s\n' "$execution_status"
        printf '%s\n' 'check_mode: true' 'capture_limit_bytes_per_stream: 4194304'
        printf '%s\n' 'inputs:'
        printf '  launcher_sha256: %s\n' "$launcher_hash"
        printf '  playbook_sha256: %s\n' "$playbook_hash"
        printf '  inventory_sha256: %s\n' "$inventory_hash"
        printf '  group_vars_sha256: %s\n' "$group_vars_hash"
        printf '  host_vars_sha256: %s\n' "$host_vars_hash"
        printf '%s\n' 'evidence:'
        printf '%s\n' '  stdout:'
        printf '    bytes: %s\n' "$stdout_bytes"
        printf '    sha256: %s\n' "$stdout_hash"
        printf '    truncated: %s\n' "$stdout_truncated"
        printf '%s\n' '  stderr:'
        printf '    bytes: %s\n' "$stderr_bytes"
        printf '    sha256: %s\n' "$stderr_hash"
        printf '    truncated: %s\n' "$stderr_truncated"
        printf '%s\n' '  status:'
        printf '    bytes: %s\n' "$status_bytes"
        printf '    sha256: %s\n' "$status_hash"
    } >"${evidence_directory}/manifest.yaml"
}

execute_qualification() {
    local evidence_directory stdout_fifo stderr_fifo
    local stdout_consumer_pid stderr_consumer_pid
    local started_at finished_at execution_status consumer_status=0
    local -a command=(
        ansible-playbook
        --inventory "$qualification_inventory"
        --limit "$qualification_target"
        --user "$qualification_user"
        --extra-vars "ansible_host=${qualification_address}"
        --check
        "$qualification_playbook"
    )

    command -v ansible-playbook >/dev/null 2>&1 || {
        printf '%s\n' 'ansible-playbook is required.' >&2
        return 127
    }

    evidence_directory=$(mktemp -d /tmp/nautobot-qualification.XXXXXX)
    chmod 0700 "$evidence_directory"
    stdout_fifo="${evidence_directory}/stdout.pipe"
    stderr_fifo="${evidence_directory}/stderr.pipe"
    mkfifo -m 0600 "$stdout_fifo" "$stderr_fifo"

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
    write_evidence_manifest "$evidence_directory" "$started_at" \
        "$finished_at" "$execution_status"

    printf 'Qualification evidence: %s\n' "$evidence_directory"
    printf 'Ansible exit status: %s\n' "$execution_status"
    if [[ "$consumer_status" -ne 0 ]]; then
        printf '%s\n' 'Evidence capture failed.' >&2
        return 70
    fi
    return "$execution_status"
}

run_self_test() {
    local self_test_directory self_test_fifo self_test_log self_test_marker
    local self_test_consumer_pid self_test_size self_test_mode

    self_test_directory=$(mktemp -d /tmp/nautobot-qualification-self-test.XXXXXX)
    case "$self_test_directory" in
        /tmp/nautobot-qualification-self-test.*) ;;
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
    self_test_size=$(stat --format=%s "$self_test_log")
    [[ "$self_test_size" -eq 1024 ]]
    [[ -f "$self_test_marker" ]]
    printf '%s\n' 'bounded stderr fixture' >"${self_test_directory}/stderr.log"
    printf '%s\n' 'ansible_playbook_exit_status=0' \
        >"${self_test_directory}/status.txt"
    write_evidence_manifest "$self_test_directory" \
        2000-01-01T00:00:00Z 2000-01-01T00:00:01Z 0
    yamllint --strict "${self_test_directory}/manifest.yaml"
    self_test_mode=$(stat --format=%a "$self_test_directory")
    [[ "$self_test_mode" == 700 ]]
    [[ $(stat --format=%a "$self_test_log") == 600 ]]
    grep -Fxq '    bytes: 1024' "${self_test_directory}/manifest.yaml"
    grep -Fxq '    truncated: true' "${self_test_directory}/manifest.yaml"
    rm -rf -- "$self_test_directory"
    printf '%s\n' 'Qualification evidence capture self-test passed.'
}

case "${1:-}" in
    show-command)
        [[ $# -eq 1 ]] || {
            usage >&2
            exit 64
        }
        qualification_command
        ;;
    execute)
        [[ $# -eq 1 ]] || {
            usage >&2
            exit 64
        }
        execute_qualification
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
