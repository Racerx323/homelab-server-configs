#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly node_a_inspector_sha256=f86c256a1e0af8a1e805a0329a6195e548651b28dfafbd160b98c714e5c61b7c
readonly node_b_inspector_sha256=6d5e7ee4834a58fec35e45f296b83df98963848613483405a961eda4ec301896
readonly historical_retry_sha256=5ec46ca77782160164785eefb75289e9a02f6d3262577261ce7cdcc31abbd6ab
readonly historical_diagnostic_sha256=f460262cded8b056818f27b0d82cd637627aa6440a67d6eb409325ac73c301d2
readonly accepted_dns_nss_runner_sha256=b9e2a07622bf7c401f667dfdb68bace73c086775de55fe8c0c24ba72b14b3b2e
readonly accepted_dns_nss_driver_sha256=94c1ea0cf40cda26fa28130c1167f6f00f73957c9ed7430a8e8ec1510f7ef755
readonly node_a_host_alias=pihole0.local.theama.co
readonly node_a_target=pi@10.1.0.53
readonly node_b_host_alias=pihole00.local.theama.co
readonly node_b_target=pi@10.1.0.54

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly node_a_inspector="$script_dir/inspect-node-a-source-bound-restricted-transport-action17o.sh"
readonly node_b_inspector="$script_dir/inspect-node-b-source-bound-restricted-transport-action17o.sh"
readonly historical_retry="$script_dir/run-node-a-source-bound-transport-action17c-c-retry.sh"
readonly historical_diagnostic="$script_dir/run-node-a-source-bound-transport-diagnostic-action17c-c-a.sh"
readonly accepted_dns_nss_runner="$script_dir/run-node-a-dns-nss-correction-action17n-reset-retry.sh"
readonly accepted_dns_nss_driver="$script_dir/apply-node-a-dns-nss-correction-action17n-reset-retry.sh"

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
    verify_content "$node_a_inspector" "$node_a_inspector_sha256"
    verify_content "$node_b_inspector" "$node_b_inspector_sha256"
    verify_content "$historical_retry" "$historical_retry_sha256"
    verify_content "$historical_diagnostic" "$historical_diagnostic_sha256"
    verify_content \
        "$accepted_dns_nss_runner" "$accepted_dns_nss_runner_sha256"
    verify_content \
        "$accepted_dns_nss_driver" "$accepted_dns_nss_driver_sha256"
}

verify_sources() {
    verify_source "$node_a_inspector" "$node_a_inspector_sha256"
    verify_source "$node_b_inspector" "$node_b_inspector_sha256"
    verify_source "$historical_retry" "$historical_retry_sha256"
    verify_source "$historical_diagnostic" "$historical_diagnostic_sha256"
    verify_source \
        "$accepted_dns_nss_runner" "$accepted_dns_nss_runner_sha256"
    verify_source \
        "$accepted_dns_nss_driver" "$accepted_dns_nss_driver_sha256"
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
    total_count=$(value_for "${count_prefix}_checks_total" "$check_transcript")
    passed_count=$(value_for "${count_prefix}_checks_passed" "$check_transcript")
    failed_count=$(value_for "${count_prefix}_checks_failed" "$check_transcript")

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

    validate_check_set \
        action_17o_check_ action_17o "$node_a_transcript" || return 1
    require_one action_17o_first_failure=none "$node_a_transcript" ||
        return 1
    require_one action_17o_value_transport_probe_attempted=true \
        "$node_a_transcript" || return 1
    require_one action_17o_value_direct_ssh_status=126 "$node_a_transcript" ||
        return 1
    require_one \
        action_17o_value_direct_ssh_error_class=forced_receiver_rejection \
        "$node_a_transcript" || return 1
    require_one action_17o_value_rsync_dry_run_attempted=true \
        "$node_a_transcript" || return 1
    require_one action_17o_value_rsync_dry_run_status=0 "$node_a_transcript" ||
        return 1
    require_one action_17o_release_payload_transferred=false \
        "$node_a_transcript" || return 1
    require_one action_17o_synchronization_executed=false \
        "$node_a_transcript" || return 1
    require_one action_17o_service_mutations=false "$node_a_transcript" ||
        return 1
    require_one action_17o_persistent_mutations=false "$node_a_transcript" ||
        return 1
    require_one action_17o_node_a_acceptance=true "$node_a_transcript" ||
        return 1

    before_hash=$(value_for action_17o_value_before_state_sha256 \
        "$node_a_transcript") || return 1
    after_hash=$(value_for action_17o_value_after_state_sha256 \
        "$node_a_transcript") || return 1
    [[ "$before_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$after_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$before_hash" == "$after_hash" ]] || return 1
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
    local fixture_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    printf '%s\n' \
        action_17o_check_fixture=true \
        "action_17o_value_before_state_sha256=$fixture_hash" \
        action_17o_value_transport_probe_attempted=true \
        action_17o_value_direct_ssh_status=126 \
        action_17o_value_direct_ssh_error_class=forced_receiver_rejection \
        action_17o_value_rsync_dry_run_attempted=true \
        action_17o_value_rsync_dry_run_status=0 \
        "action_17o_value_after_state_sha256=$fixture_hash" \
        action_17o_checks_total=1 \
        action_17o_checks_passed=1 \
        action_17o_checks_failed=0 \
        action_17o_first_failure=none \
        action_17o_release_payload_transferred=false \
        action_17o_synchronization_executed=false \
        action_17o_service_mutations=false \
        action_17o_persistent_mutations=false \
        action_17o_node_a_acceptance=true >"$fixture_path"
}

write_node_b_fixture() {
    local fixture_path=$1
    local fixture_hash=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

    printf '%s\n' \
        action_17o_node_b_check_fixture=true \
        "action_17o_node_b_value_state_sha256=$fixture_hash" \
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
    "$node_a_inspector" --self-test >/dev/null
    "$node_a_inspector" --contract-test >/dev/null
    "$node_b_inspector" --self-test >/dev/null
    printf 'action_17o_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_sources
    printf 'action_17o_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action17o-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    write_node_a_fixture "$contract_dir/node-a"
    write_node_b_fixture "$contract_dir/node-b"
    validate_node_a "$contract_dir/node-a"
    validate_node_b "$contract_dir/node-b"
    validate_secret_free "$contract_dir/node-a" "$contract_dir/node-b"

    cp -- "$contract_dir/node-a" "$contract_dir/node-a-duplicate"
    printf 'action_17o_check_fixture=true\n' \
        >>"$contract_dir/node-a-duplicate"
    if validate_node_a "$contract_dir/node-a-duplicate"; then
        printf 'Duplicate Node A assertion was accepted.\n' >&2
        exit 1
    fi

    sed 's/action_17o_value_rsync_dry_run_status=0/action_17o_value_rsync_dry_run_status=1/' \
        "$contract_dir/node-a" >"$contract_dir/node-a-failed-rsync"
    if validate_node_a "$contract_dir/node-a-failed-rsync"; then
        printf 'Failed rsync dry run was accepted.\n' >&2
        exit 1
    fi

    printf 'action_17o_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_sources
work_dir=$(mktemp -d /tmp/caddy-action17o-runner.XXXXXX)
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
    "$node_a_inspector" \
    "$work_dir/node-a.out" "$work_dir/node-a.err" node_a_status
run_remote \
    "$node_b_host_alias" "$node_b_target" \
    'sudo -n /bin/bash -s --' "$node_b_inspector" \
    "$work_dir/node-b-after.out" "$work_dir/node-b-after.err" \
    node_b_after_status

printf 'action_17o_node_b_before_ssh_status=%s\n' "$node_b_before_status"
printf 'action_17o_node_a_ssh_status=%s\n' "$node_a_status"
printf 'action_17o_node_b_after_ssh_status=%s\n' "$node_b_after_status"

if [[ "$node_b_before_status" -ne 0 ]]; then
    sed -n '1,240p' "$work_dir/node-b-before.out" >&2
    sed -n '1,80p' "$work_dir/node-b-before.err" >&2
    printf 'action_17o_runner_acceptance=false\n' >&2
    exit 97
fi
if [[ "$node_a_status" -ne 0 ]]; then
    sed -n '1,320p' "$work_dir/node-a.out" >&2
    sed -n '1,80p' "$work_dir/node-a.err" >&2
    printf 'action_17o_runner_acceptance=false\n' >&2
    exit 97
fi
if [[ "$node_b_after_status" -ne 0 ]]; then
    sed -n '1,240p' "$work_dir/node-b-after.out" >&2
    sed -n '1,80p' "$work_dir/node-b-after.err" >&2
    printf 'action_17o_runner_acceptance=false\n' >&2
    exit 97
fi
if [[ -s "$work_dir/node-b-before.err" ]]; then
    printf 'action_17o_node_b_before_stderr_empty=false\n' >&2
    exit 97
fi
if [[ -s "$work_dir/node-a.err" ]]; then
    printf 'action_17o_node_a_stderr_empty=false\n' >&2
    exit 97
fi
if [[ -s "$work_dir/node-b-after.err" ]]; then
    printf 'action_17o_node_b_after_stderr_empty=false\n' >&2
    exit 97
fi
if ! validate_node_b "$work_dir/node-b-before.out"; then
    printf 'action_17o_node_b_before_transcript_valid=false\n' >&2
    exit 97
fi
if ! validate_node_a "$work_dir/node-a.out"; then
    printf 'action_17o_node_a_transcript_valid=false\n' >&2
    exit 97
fi
if ! validate_node_b "$work_dir/node-b-after.out"; then
    printf 'action_17o_node_b_after_transcript_valid=false\n' >&2
    exit 97
fi
if ! validate_secret_free \
    "$work_dir/node-b-before.out" "$work_dir/node-b-before.err" \
    "$work_dir/node-a.out" "$work_dir/node-a.err" \
    "$work_dir/node-b-after.out" "$work_dir/node-b-after.err"; then
    printf 'action_17o_transcripts_secret_free=false\n' >&2
    exit 97
fi

before_digest=$(value_for action_17o_node_b_value_state_sha256 \
    "$work_dir/node-b-before.out")
after_digest=$(value_for action_17o_node_b_value_state_sha256 \
    "$work_dir/node-b-after.out")
if [[ "$before_digest" != "$after_digest" ]]; then
    printf 'action_17o_node_b_state_unchanged=false\n' >&2
    exit 97
fi

printf 'action_17o_node_b_before_transcript_valid=true\n'
printf 'action_17o_node_a_transcript_valid=true\n'
printf 'action_17o_node_b_after_transcript_valid=true\n'
printf 'action_17o_transcripts_secret_free=true\n'
printf 'action_17o_node_b_state_unchanged=true\n'
printf 'action_17o_release_payload_transferred=false\n'
printf 'action_17o_synchronization_executed=false\n'
printf 'action_17o_service_mutations=false\n'
printf 'action_17o_persistent_mutations=false\n'
printf 'action_17o_runner_acceptance=true\n'

cleanup
trap - EXIT
[[ ! -e "$work_dir" ]]
printf 'action_17o_workstation_cleanup_complete=true\n'
