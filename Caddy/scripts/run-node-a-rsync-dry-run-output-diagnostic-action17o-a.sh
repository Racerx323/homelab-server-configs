#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly node_a_diagnostic_sha256=aabb66b50a14459f75b409e666ddf776b48eba9a1457810d74448315e3e4e06c
readonly node_b_inspector_sha256=6d5e7ee4834a58fec35e45f296b83df98963848613483405a961eda4ec301896
readonly historical_runner_sha256=053bd8aa483ed92736aa0bbcee2232b9bf6d17de5ea937e4aea8690fd4e95c48
readonly historical_node_a_sha256=f86c256a1e0af8a1e805a0329a6195e548651b28dfafbd160b98c714e5c61b7c
readonly historical_regression_sha256=284c5e5007f8da42b69e6cb058301f6d279cf9cdda2dfb360ba8326e4fff8569
readonly node_a_host_alias=pihole0.local.theama.co
readonly node_a_target=pi@10.1.0.53
readonly node_b_host_alias=pihole00.local.theama.co
readonly node_b_target=pi@10.1.0.54

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly node_a_diagnostic="$script_dir/diagnose-node-a-rsync-dry-run-output-action17o-a.sh"
readonly node_b_inspector="$script_dir/inspect-node-b-source-bound-restricted-transport-action17o.sh"
readonly historical_runner="$script_dir/run-node-a-to-node-b-source-bound-restricted-transport-action17o.sh"
readonly historical_node_a="$script_dir/inspect-node-a-source-bound-restricted-transport-action17o.sh"
readonly historical_regression="$caddy_root/tests/action17o-source-bound-restricted-transport-regression.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_content() {
    local content_path=$1
    local content_hash=$2

    [[ -f "$content_path" ]]
    [[ ! -L "$content_path" ]]
    [[ "$(file_hash "$content_path")" == "$content_hash" ]]
    bash -n "$content_path"
}

verify_source() {
    local source_path=$1
    local source_hash=$2

    verify_content "$source_path" "$source_hash"
    [[ "$(stat -c '%U:%G:%a' "$source_path")" == aaron:aaron:755 ]]
}

verify_contents() {
    verify_content "$node_a_diagnostic" "$node_a_diagnostic_sha256"
    verify_content "$node_b_inspector" "$node_b_inspector_sha256"
    verify_content "$historical_runner" "$historical_runner_sha256"
    verify_content "$historical_node_a" "$historical_node_a_sha256"
    verify_content "$historical_regression" "$historical_regression_sha256"
}

verify_sources() {
    verify_source "$node_a_diagnostic" "$node_a_diagnostic_sha256"
    verify_source "$node_b_inspector" "$node_b_inspector_sha256"
    verify_source "$historical_runner" "$historical_runner_sha256"
    verify_source "$historical_node_a" "$historical_node_a_sha256"
    verify_source "$historical_regression" "$historical_regression_sha256"
}

value_for() {
    local value_prefix=$1
    local value_transcript=$2
    local value_record

    [[ "$(grep -Ec "^${value_prefix}=" "$value_transcript")" -eq 1 ]] ||
        return 1
    value_record=$(grep -E "^${value_prefix}=" "$value_transcript")
    printf '%s\n' "${value_record#*=}"
}

require_one() {
    local required_record=$1
    local required_transcript=$2

    [[ "$(grep -Fxc "$required_record" "$required_transcript")" -eq 1 ]]
}

validate_check_set() {
    local check_prefix=$1
    local count_prefix=$2
    local check_transcript=$3
    local check_count
    local unique_count
    local total_count
    local passed_count
    local failed_count

    check_count=$(
        grep -Ec "^${check_prefix}[a-z0-9_]+=(true|false)$" \
            "$check_transcript" || true
    )
    unique_count=$(
        sed -n \
            "s/^\\(${check_prefix}[a-z0-9_]*\\)=\\(true\\|false\\)$/\\1/p" \
            "$check_transcript" |
            LC_ALL=C sort -u |
            wc -l
    )
    total_count=$(value_for "${count_prefix}_checks_total" "$check_transcript") ||
        return 1
    passed_count=$(value_for "${count_prefix}_checks_passed" "$check_transcript") ||
        return 1
    failed_count=$(value_for "${count_prefix}_checks_failed" "$check_transcript") ||
        return 1

    [[ "$check_count" =~ ^[0-9]+$ ]] || return 1
    [[ "$unique_count" =~ ^[0-9]+$ ]] || return 1
    [[ "$total_count" =~ ^[0-9]+$ ]] || return 1
    [[ "$passed_count" =~ ^[0-9]+$ ]] || return 1
    [[ "$failed_count" =~ ^[0-9]+$ ]] || return 1
    [[ "$check_count" -eq "$unique_count" ]] || return 1
    [[ "$check_count" -eq "$total_count" ]] || return 1
    [[ "$passed_count" -eq "$total_count" ]] || return 1
    [[ "$failed_count" -eq 0 ]] || return 1
    [[ "$(grep -Ec "^${check_prefix}[a-z0-9_]+=false$" \
        "$check_transcript" || true)" -eq 0 ]] || return 1
}

validate_node_a() {
    local node_a_transcript=$1
    local before_hash
    local after_hash
    local stdout_bytes
    local stdout_lines
    local stdout_hash
    local stdout_classification

    validate_check_set \
        action_17o_a_check_ action_17o_a "$node_a_transcript" || return 1
    require_one action_17o_a_first_failure=none "$node_a_transcript" ||
        return 1
    require_one action_17o_a_value_rsync_attempted=true "$node_a_transcript" ||
        return 1
    require_one action_17o_a_value_rsync_status=0 "$node_a_transcript" ||
        return 1
    require_one action_17o_a_raw_stdout_emitted=false "$node_a_transcript" ||
        return 1
    require_one action_17o_a_release_payload_transferred=false \
        "$node_a_transcript" || return 1
    require_one action_17o_a_synchronization_executed=false \
        "$node_a_transcript" || return 1
    require_one action_17o_a_service_mutations=false "$node_a_transcript" ||
        return 1
    require_one action_17o_a_persistent_mutations=false "$node_a_transcript" ||
        return 1
    require_one action_17o_a_node_a_collection_complete=true \
        "$node_a_transcript" || return 1

    before_hash=$(value_for action_17o_a_value_before_state_sha256 \
        "$node_a_transcript") || return 1
    after_hash=$(value_for action_17o_a_value_after_state_sha256 \
        "$node_a_transcript") || return 1
    stdout_bytes=$(value_for action_17o_a_value_stdout_bytes \
        "$node_a_transcript") || return 1
    stdout_lines=$(value_for action_17o_a_value_stdout_lines \
        "$node_a_transcript") || return 1
    stdout_hash=$(value_for action_17o_a_value_stdout_sha256 \
        "$node_a_transcript") || return 1
    stdout_classification=$(value_for action_17o_a_value_stdout_classification \
        "$node_a_transcript") || return 1

    [[ "$before_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$after_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$before_hash" == "$after_hash" ]] || return 1
    [[ "$stdout_bytes" =~ ^[0-9]+$ ]] || return 1
    [[ "$stdout_lines" =~ ^[0-9]+$ ]] || return 1
    [[ "$stdout_bytes" -le 4096 ]] || return 1
    [[ "$stdout_lines" -le 20 ]] || return 1
    [[ "$stdout_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$stdout_classification" =~ ^(empty|itemized_current_directory_only|itemized_relative_paths|bounded_safe_other)$ ]] ||
        return 1
}

validate_node_b() {
    local node_b_transcript=$1
    local state_hash

    validate_check_set \
        action_17o_node_b_check_ action_17o_node_b "$node_b_transcript" ||
        return 1
    require_one action_17o_node_b_first_failure=none "$node_b_transcript" ||
        return 1
    require_one action_17o_node_b_persistent_mutations=false \
        "$node_b_transcript" || return 1
    require_one action_17o_node_b_synchronization_executed=false \
        "$node_b_transcript" || return 1
    require_one action_17o_node_b_acceptance=true "$node_b_transcript" ||
        return 1
    state_hash=$(value_for action_17o_node_b_value_state_sha256 \
        "$node_b_transcript") || return 1
    [[ "$state_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
}

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$@"
}

write_node_a_fixture() {
    local fixture_path=$1
    local state_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    local stdout_hash=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

    printf '%s\n' \
        action_17o_a_check_fixture=true \
        "action_17o_a_value_before_state_sha256=$state_hash" \
        action_17o_a_value_rsync_attempted=true \
        action_17o_a_value_rsync_status=0 \
        action_17o_a_value_stdout_bytes=15 \
        action_17o_a_value_stdout_lines=1 \
        "action_17o_a_value_stdout_sha256=$stdout_hash" \
        action_17o_a_value_stdout_classification=itemized_current_directory_only \
        action_17o_a_raw_stdout_emitted=false \
        "action_17o_a_value_after_state_sha256=$state_hash" \
        action_17o_a_checks_total=1 \
        action_17o_a_checks_passed=1 \
        action_17o_a_checks_failed=0 \
        action_17o_a_first_failure=none \
        action_17o_a_release_payload_transferred=false \
        action_17o_a_synchronization_executed=false \
        action_17o_a_service_mutations=false \
        action_17o_a_persistent_mutations=false \
        action_17o_a_node_a_collection_complete=true >"$fixture_path"
}

write_node_b_fixture() {
    local fixture_path=$1
    local state_hash=$2

    printf '%s\n' \
        action_17o_node_b_check_fixture=true \
        "action_17o_node_b_value_state_sha256=$state_hash" \
        action_17o_node_b_checks_total=1 \
        action_17o_node_b_checks_passed=1 \
        action_17o_node_b_checks_failed=0 \
        action_17o_node_b_first_failure=none \
        action_17o_node_b_persistent_mutations=false \
        action_17o_node_b_synchronization_executed=false \
        action_17o_node_b_acceptance=true >"$fixture_path"
}

run_remote() {
    local remote_host_alias=$1
    local remote_target=$2
    local remote_command=$3
    local remote_payload=$4
    local remote_output=$5
    local remote_error=$6
    local remote_status_name=$7
    local remote_status=0

    ssh -T \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o "HostKeyAlias=$remote_host_alias" \
        -o StrictHostKeyChecking=yes \
        "$remote_target" "$remote_command" \
        <"$remote_payload" >"$remote_output" 2>"$remote_error" ||
        remote_status=$?
    printf -v "$remote_status_name" '%s' "$remote_status"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_contents
    "$node_a_diagnostic" --self-test >/dev/null
    "$node_a_diagnostic" --classifier-test >/dev/null
    "$node_b_inspector" --self-test >/dev/null
    printf 'action_17o_a_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_sources
    printf 'action_17o_a_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action17o-a-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    write_node_a_fixture "$contract_dir/node-a"
    write_node_b_fixture \
        "$contract_dir/node-b" \
        cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
    validate_node_a "$contract_dir/node-a"
    validate_node_b "$contract_dir/node-b"
    validate_secret_free "$contract_dir/node-a" "$contract_dir/node-b"

    cp -- "$contract_dir/node-a" "$contract_dir/node-a-duplicate"
    printf 'action_17o_a_value_stdout_lines=1\n' \
        >>"$contract_dir/node-a-duplicate"
    if validate_node_a "$contract_dir/node-a-duplicate"; then
        printf 'Duplicate stdout metadata was accepted.\n' >&2
        exit 1
    fi

    sed \
        's/itemized_current_directory_only/unsafe/' \
        "$contract_dir/node-a" >"$contract_dir/node-a-unsafe"
    if validate_node_a "$contract_dir/node-a-unsafe"; then
        printf 'Unsafe stdout classification was accepted.\n' >&2
        exit 1
    fi

    printf 'action_17o_a_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_sources
work_dir=$(mktemp -d /tmp/caddy-action17o-a-runner.XXXXXX)
readonly work_dir
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

node_b_before_status=0
node_a_status=0
node_b_after_status=0
run_remote \
    "$node_b_host_alias" "$node_b_target" \
    'sudo -n /bin/bash -s --' "$node_b_inspector" \
    "$work_dir/node-b-before.out" "$work_dir/node-b-before.err" \
    node_b_before_status
run_remote \
    "$node_a_host_alias" "$node_a_target" \
    "sudo -n /bin/bash -c 'cd / && exec /usr/sbin/runuser -u caddy-sync -- /bin/bash -s --'" \
    "$node_a_diagnostic" \
    "$work_dir/node-a.out" "$work_dir/node-a.err" node_a_status
run_remote \
    "$node_b_host_alias" "$node_b_target" \
    'sudo -n /bin/bash -s --' "$node_b_inspector" \
    "$work_dir/node-b-after.out" "$work_dir/node-b-after.err" \
    node_b_after_status

printf 'action_17o_a_node_b_before_ssh_status=%s\n' "$node_b_before_status"
printf 'action_17o_a_node_a_ssh_status=%s\n' "$node_a_status"
printf 'action_17o_a_node_b_after_ssh_status=%s\n' "$node_b_after_status"

if [[ "$node_b_before_status" -ne 0 ]]; then
    sed -n '1,240p' "$work_dir/node-b-before.out" >&2
    printf 'action_17o_a_runner_acceptance=false\n' >&2
    exit 97
fi
if [[ "$node_a_status" -ne 0 ]]; then
    sed -n '1,240p' "$work_dir/node-a.out" >&2
    printf 'action_17o_a_runner_acceptance=false\n' >&2
    exit 97
fi
if [[ "$node_b_after_status" -ne 0 ]]; then
    sed -n '1,240p' "$work_dir/node-b-after.out" >&2
    printf 'action_17o_a_runner_acceptance=false\n' >&2
    exit 97
fi
if [[ -s "$work_dir/node-b-before.err" ]]; then
    printf 'action_17o_a_node_b_before_stderr_empty=false\n' >&2
    exit 97
fi
if [[ -s "$work_dir/node-a.err" ]]; then
    printf 'action_17o_a_node_a_stderr_empty=false\n' >&2
    exit 97
fi
if [[ -s "$work_dir/node-b-after.err" ]]; then
    printf 'action_17o_a_node_b_after_stderr_empty=false\n' >&2
    exit 97
fi
if ! validate_node_b "$work_dir/node-b-before.out"; then
    printf 'action_17o_a_node_b_before_transcript_valid=false\n' >&2
    exit 97
fi
if ! validate_node_a "$work_dir/node-a.out"; then
    printf 'action_17o_a_node_a_transcript_valid=false\n' >&2
    exit 97
fi
if ! validate_node_b "$work_dir/node-b-after.out"; then
    printf 'action_17o_a_node_b_after_transcript_valid=false\n' >&2
    exit 97
fi
if ! validate_secret_free \
    "$work_dir/node-b-before.out" "$work_dir/node-b-before.err" \
    "$work_dir/node-a.out" "$work_dir/node-a.err" \
    "$work_dir/node-b-after.out" "$work_dir/node-b-after.err"; then
    printf 'action_17o_a_transcripts_secret_free=false\n' >&2
    exit 97
fi

before_digest=$(value_for action_17o_node_b_value_state_sha256 \
    "$work_dir/node-b-before.out")
after_digest=$(value_for action_17o_node_b_value_state_sha256 \
    "$work_dir/node-b-after.out")
if [[ "$before_digest" != "$after_digest" ]]; then
    printf 'action_17o_a_node_b_state_unchanged=false\n' >&2
    exit 97
fi

printf 'action_17o_a_stdout_bytes=%s\n' \
    "$(value_for action_17o_a_value_stdout_bytes "$work_dir/node-a.out")"
printf 'action_17o_a_stdout_lines=%s\n' \
    "$(value_for action_17o_a_value_stdout_lines "$work_dir/node-a.out")"
printf 'action_17o_a_stdout_sha256=%s\n' \
    "$(value_for action_17o_a_value_stdout_sha256 "$work_dir/node-a.out")"
printf 'action_17o_a_stdout_classification=%s\n' \
    "$(value_for action_17o_a_value_stdout_classification \
        "$work_dir/node-a.out")"
printf 'action_17o_a_raw_stdout_emitted=false\n'
printf 'action_17o_a_node_a_state_unchanged=true\n'
printf 'action_17o_a_node_b_state_unchanged=true\n'
printf 'action_17o_a_release_payload_transferred=false\n'
printf 'action_17o_a_synchronization_executed=false\n'
printf 'action_17o_a_service_mutations=false\n'
printf 'action_17o_a_persistent_mutations=false\n'
printf 'action_17o_a_runner_acceptance=true\n'

cleanup
trap - EXIT
[[ ! -e "$work_dir" ]]
printf 'action_17o_a_workstation_cleanup_complete=true\n'
