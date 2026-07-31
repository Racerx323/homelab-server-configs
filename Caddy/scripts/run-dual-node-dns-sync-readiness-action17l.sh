#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=fe8d5f2e0a2fb245d35d695747286141ed75e83147f6b00ce46729da6ec1a80a
readonly regression_sha256=d94d32b571059c85bdd4b105ce0de914f5711619e4a17d98a57ac9132bb78417
readonly historical_source_regression_sha256=2e06d533ea7b2af529fa9ba5b5f272c7a75e33115473f2ec1a06dc3dd3878269
readonly collision_checker_sha256=78b46fcdc6c4ca6b4cfe0121c347e0e101c472d723a891aac2dea7f23f085cd8
readonly expected_assertion_count=111
readonly node_a_target=pi@10.1.0.53
readonly node_a_alias=pihole0.local.theama.co
readonly node_b_target=pi@10.1.0.54
readonly node_b_alias=pihole00.local.theama.co

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly inspector="$script_dir/inspect-dual-node-dns-sync-readiness-action17l.sh"
readonly regression="$caddy_root/tests/action17l-dual-node-dns-sync-readiness-regression.sh"
readonly historical_source_regression="$caddy_root/tests/action17l-historical-unbound-source-advance-regression.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_file() {
    local verified_path=$1
    local expected_hash=$2

    [[ -f "$verified_path" && ! -L "$verified_path" ]]
    [[ "$(file_hash "$verified_path")" == "$expected_hash" ]]
}

verify_sources() {
    verify_file "$inspector" "$inspector_sha256"
    verify_file "$regression" "$regression_sha256"
    verify_file \
        "$historical_source_regression" "$historical_source_regression_sha256"
    verify_file "$collision_checker" "$collision_checker_sha256"
    bash -n \
        "$inspector" "$regression" "$historical_source_regression" \
        "$collision_checker"
    "$inspector" --self-test >/dev/null
    "$regression" --self-test >/dev/null
    "$historical_source_regression" --self-test >/dev/null
    "$collision_checker" \
        "$inspector" "$regression" "$historical_source_regression" "$0" \
        >/dev/null
}

verify_live_sources() {
    local live_source_path

    verify_sources
    for live_source_path in \
        "$inspector" "$regression" "$historical_source_regression" \
        "$collision_checker" "$0"; do
        [[ "$(stat -c '%U:%G:%a' "$live_source_path")" == aaron:aaron:755 ]]
    done
}

value_for() {
    local value_key=$1
    local transcript_path=$2
    local value_record

    [[ "$(grep -Ec "^${value_key}=" "$transcript_path")" -eq 1 ]] ||
        return 1
    value_record=$(grep -E "^${value_key}=" "$transcript_path")
    printf '%s\n' "${value_record#*=}"
}

require_value() {
    local required_key=$1
    local required_value=$2
    local transcript_path=$3

    [[ "$(value_for "$required_key" "$transcript_path")" == "$required_value" ]]
}

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=|private-domain:|local-data(-ptr)?:|ssh-ed25519[[:space:]]+AAAA' \
        "$@"
}

validate_structure() {
    local transcript_path=$1
    local expected_role=$2
    local assertion_total unique_assertion_total false_assertion_total
    local reported_failure_total reported_first_failure reported_conclusion
    local before_state after_state

    assertion_total=$(
        grep -Ec '^action_17l_assertion_[a-z0-9_]+=((true)|(false))$' \
            "$transcript_path"
    )
    unique_assertion_total=$(
        grep -E '^action_17l_assertion_[a-z0-9_]+=((true)|(false))$' \
            "$transcript_path" |
            cut -d= -f1 |
            LC_ALL=C sort -u |
            wc -l
    )
    false_assertion_total=$(
        grep -Ec '^action_17l_assertion_[a-z0-9_]+=false$' \
            "$transcript_path" || true
    )
    [[ "$assertion_total" -eq "$expected_assertion_count" ]] || return 1
    [[ "$unique_assertion_total" -eq "$expected_assertion_count" ]] ||
        return 1
    require_value action_17l_remote_reached true "$transcript_path" ||
        return 1
    require_value action_17l_node_role "$expected_role" "$transcript_path" ||
        return 1
    require_value action_17l_assertion_count \
        "$expected_assertion_count" "$transcript_path" || return 1
    require_value action_17l_remote_complete true "$transcript_path" ||
        return 1
    require_value dns_queries_performed true "$transcript_path" || return 1
    require_value peer_connections false "$transcript_path" || return 1
    require_value synchronization_commands_executed false \
        "$transcript_path" || return 1
    require_value remote_paths_created false "$transcript_path" || return 1
    require_value dns_configuration_mutations false "$transcript_path" ||
        return 1
    require_value service_mutations false "$transcript_path" || return 1
    require_value filesystem_mutations false "$transcript_path" || return 1
    require_value persistent_mutations false "$transcript_path" || return 1

    before_state=$(value_for action_17l_before_state_sha256 "$transcript_path")
    after_state=$(value_for action_17l_after_state_sha256 "$transcript_path")
    [[ "$before_state" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$after_state" == "$before_state" ]] || return 1

    reported_failure_total=$(
        value_for action_17l_failed_assertion_count "$transcript_path"
    )
    reported_first_failure=$(
        value_for action_17l_first_failure "$transcript_path"
    )
    reported_conclusion=$(value_for action_17l_conclusion "$transcript_path")
    [[ "$reported_failure_total" =~ ^[0-9]+$ ]] || return 1
    [[ "$reported_failure_total" -eq "$false_assertion_total" ]] || return 1
    if [[ "$reported_failure_total" -eq 0 ]]; then
        [[ "$reported_first_failure" == none ]] || return 1
        [[ "$reported_conclusion" == dns_and_sync_prerequisites_ready ]] ||
            return 1
    else
        [[ "$reported_first_failure" =~ ^[a-z0-9_]+$ ]] || return 1
        [[ "$(grep -Fxc \
            "action_17l_assertion_${reported_first_failure}=false" \
            "$transcript_path")" -eq 1 ]] || return 1
        [[ "$reported_conclusion" == dns_or_sync_prerequisite_mismatch ]] ||
            return 1
    fi
}

classify_transcript() {
    local transcript_path=$1
    local expected_role=$2
    local ssh_exit_status=$3
    local reported_failure_total

    validate_structure "$transcript_path" "$expected_role" || return 97
    reported_failure_total=$(
        value_for action_17l_failed_assertion_count "$transcript_path"
    )
    if [[ "$reported_failure_total" -eq 0 && "$ssh_exit_status" -eq 0 ]]; then
        return 0
    fi
    if [[ "$reported_failure_total" -gt 0 && "$ssh_exit_status" -eq 1 ]]; then
        return 1
    fi
    return 97
}

write_fixture() {
    local fixture_path=$1
    local fixture_role=$2
    local false_index=${3:-0}
    local fixture_assertion_index fixture_assertion_status
    local fixture_failure_total=0
    local fixture_first_failure=none
    local fixture_conclusion=dns_and_sync_prerequisites_ready

    printf '%s\n' \
        action_17l_remote_reached=true \
        "action_17l_node_role=$fixture_role" >"$fixture_path"
    for ((fixture_assertion_index = 1;  \
    fixture_assertion_index <= expected_assertion_count;  \
    fixture_assertion_index += 1)); do
        fixture_assertion_status=true
        if [[ "$fixture_assertion_index" -eq "$false_index" ]]; then
            fixture_assertion_status=false
            fixture_failure_total=1
            fixture_first_failure=$(printf 'fixture_%03d' "$fixture_assertion_index")
            fixture_conclusion=dns_or_sync_prerequisite_mismatch
        fi
        printf 'action_17l_assertion_fixture_%03d=%s\n' \
            "$fixture_assertion_index" "$fixture_assertion_status"
    done >>"$fixture_path"
    printf '%s\n' \
        "action_17l_assertion_count=$expected_assertion_count" \
        "action_17l_failed_assertion_count=$fixture_failure_total" \
        "action_17l_first_failure=$fixture_first_failure" \
        action_17l_before_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        action_17l_after_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        dns_queries_performed=true \
        peer_connections=false \
        synchronization_commands_executed=false \
        remote_paths_created=false \
        dns_configuration_mutations=false \
        service_mutations=false \
        filesystem_mutations=false \
        persistent_mutations=false \
        "action_17l_conclusion=$fixture_conclusion" \
        action_17l_remote_complete=true >>"$fixture_path"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_sources
    grep -Fq \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s -- --node node-a'" \
        "$0"
    grep -Fq \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s -- --node node-b'" \
        "$0"
    printf 'action_17l_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_live_sources
    printf 'action_17l_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_directory=$(mktemp -d /tmp/caddy-action17l-contract.XXXXXX)
    trap 'rm -rf -- "$contract_directory"' EXIT
    success_fixture="$contract_directory/success"
    mismatch_fixture="$contract_directory/mismatch"
    duplicate_fixture="$contract_directory/duplicate"
    unsafe_fixture="$contract_directory/unsafe"

    write_fixture "$success_fixture" node-a
    classify_transcript "$success_fixture" node-a 0
    write_fixture "$mismatch_fixture" node-b 37
    set +e
    classify_transcript "$mismatch_fixture" node-b 1
    mismatch_status=$?
    set -e
    [[ "$mismatch_status" -eq 1 ]]
    cp -- "$success_fixture" "$duplicate_fixture"
    printf 'action_17l_assertion_fixture_001=true\n' >>"$duplicate_fixture"
    set +e
    classify_transcript "$duplicate_fixture" node-a 0
    duplicate_status=$?
    set -e
    [[ "$duplicate_status" -eq 97 ]]
    cp -- "$success_fixture" "$unsafe_fixture"
    printf '%s\n' 'local-data: "private.example. A 192.0.2.1"' \
        >>"$unsafe_fixture"
    if validate_secret_free "$unsafe_fixture"; then
        printf 'Action 17l unsafe fixture was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17l_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_live_sources
work_directory=$(mktemp -d /tmp/caddy-action17l.XXXXXX)
readonly work_directory
readonly node_a_output="$work_directory/node-a.out"
readonly node_a_error="$work_directory/node-a.err"
readonly node_b_output="$work_directory/node-b.out"
readonly node_b_error="$work_directory/node-b.err"

cleanup() {
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

finish() {
    local finish_status=$1

    cleanup
    trap - EXIT
    if [[ -e "$work_directory" || -L "$work_directory" ]]; then
        printf 'action_17l_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_17l_local_cleanup_complete=true\n'
    exit "$finish_status"
}

node_a_ssh_status=0
set +e
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o "HostKeyAlias=$node_a_alias" \
    -o StrictHostKeyChecking=yes \
    "$node_a_target" \
    "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s -- --node node-a'" \
    <"$inspector" >"$node_a_output" 2>"$node_a_error"
node_a_ssh_status=$?
set -e

node_b_ssh_status=0
set +e
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o "HostKeyAlias=$node_b_alias" \
    -o StrictHostKeyChecking=yes \
    "$node_b_target" \
    "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s -- --node node-b'" \
    <"$inspector" >"$node_b_output" 2>"$node_b_error"
node_b_ssh_status=$?
set -e

cat "$node_a_output"
cat "$node_a_error" >&2
printf 'node_a_ssh_exit_status=%s\n' "$node_a_ssh_status"
cat "$node_b_output"
cat "$node_b_error" >&2
printf 'node_b_ssh_exit_status=%s\n' "$node_b_ssh_status"

if ! validate_secret_free \
    "$node_a_output" "$node_a_error" "$node_b_output" "$node_b_error"; then
    printf 'Unsafe Action 17l output detected.\n' >&2
    finish 97
fi
if [[ -s "$node_a_error" || -s "$node_b_error" ]]; then
    printf 'Action 17l remote execution emitted unexpected stderr.\n' >&2
    finish 97
fi

set +e
classify_transcript "$node_a_output" node-a "$node_a_ssh_status"
node_a_classification=$?
classify_transcript "$node_b_output" node-b "$node_b_ssh_status"
node_b_classification=$?
set -e
printf '%s\n' \
    "action_17l_node_a_classification=$node_a_classification" \
    "action_17l_node_b_classification=$node_b_classification"
if [[ "$node_a_classification" -eq 97 ||
    "$node_b_classification" -eq 97 ]]; then
    printf 'Action 17l authoritative evidence contract failed.\n' >&2
    finish 97
fi
if [[ "$node_a_classification" -eq 0 &&
    "$node_b_classification" -eq 0 ]]; then
    printf 'action_17l_dual_node_readiness_accepted=true\n'
    finish 0
fi
printf 'action_17l_dual_node_readiness_accepted=false\n'
finish 1
