#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly diagnostic_sha256=94a0c6d8470fc0366e233ddeec6af9e7be3403b7950a70801825e8c3ff9de9b3
readonly regression_sha256=3d04aacbe1fe1e131b120aba1f28d898870014b69d62edc31d4698020cf08aff
readonly failed_driver_sha256=916f8b8a109494523906d189f8cabec834ccf40fd04a38cb5686f355f3aee631
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly diagnostic="$script_dir/diagnose-node-b-unbound-action17f-transition.sh"
readonly regression="$caddy_root/tests/action17f-b-transition-diagnostic-regression.sh"
readonly failed_driver="$script_dir/stage-node-b-unbound-local-zone-action17f.sh"

readonly -a required_prefixes=(
    action_17f_b_remote_reached
    working_directory_is_root
    transition_validate_baseline_status
    transition_live_state_assignment_status
    transition_snapshot_bytes
    transition_snapshot_readonly_status
    transition_snapshot_hash_status
    transition_snapshot_sha256
    transition_snapshot_hash_readonly_status
    transition_exact_block_status
    remote_paths_created
    dns_queries_performed
    dns_configuration_mutations
    service_mutations
    persistent_mutations
    action_17f_b_transition_diagnostic_complete
)

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_file() {
    local path=$1
    local expected_hash=$2

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(file_hash "$path")" == "$expected_hash" ]]
}

verify_sources() {
    verify_file "$diagnostic" "$diagnostic_sha256"
    verify_file "$regression" "$regression_sha256"
    verify_file "$failed_driver" "$failed_driver_sha256"
    bash -n "$diagnostic" "$regression" "$failed_driver"
}

verify_live_sources() {
    local path

    verify_sources
    for path in "$diagnostic" "$regression" "$failed_driver"; do
        [[ "$(stat -c '%U:%G:%a' "$path")" == aaron:aaron:755 ]]
    done
}

value_for() {
    local prefix=$1
    local transcript=$2
    local record

    [[ "$(grep -Ec "^${prefix}=" "$transcript")" -eq 1 ]] || return 1
    record=$(grep -E "^${prefix}=" "$transcript")
    printf '%s\n' "${record#*=}"
}

require_value() {
    local prefix=$1
    local expected=$2
    local transcript=$3

    [[ "$(value_for "$prefix" "$transcript")" == "$expected" ]]
}

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=|private-domain:|local-data(-ptr)?:' \
        "$@"
}

validate_transcript() {
    local transcript=$1
    local prefix exact_status failure_count completion_count

    for prefix in "${required_prefixes[@]}"; do
        [[ "$(grep -Ec "^${prefix}=" "$transcript")" -eq 1 ]] || return 1
    done
    require_value action_17f_b_remote_reached true "$transcript"
    require_value working_directory_is_root true "$transcript"
    require_value remote_paths_created false "$transcript"
    require_value dns_queries_performed false "$transcript"
    require_value dns_configuration_mutations false "$transcript"
    require_value service_mutations false "$transcript"
    require_value persistent_mutations false "$transcript"
    require_value action_17f_b_transition_diagnostic_complete true "$transcript"

    for prefix in \
        transition_validate_baseline_status \
        transition_live_state_assignment_status \
        transition_snapshot_bytes \
        transition_snapshot_readonly_status \
        transition_snapshot_hash_status \
        transition_snapshot_hash_readonly_status \
        transition_exact_block_status; do
        [[ "$(value_for "$prefix" "$transcript")" =~ ^[0-9]+$ ]]
    done
    [[ "$(value_for transition_snapshot_sha256 "$transcript")" =~ ^[0-9a-f]{64}$ ]]

    exact_status=$(value_for transition_exact_block_status "$transcript")
    failure_count=$(
        grep -Ec '^transition_exact_failure_step=' "$transcript" || true
    )
    completion_count=$(
        grep -Ec '^transition_exact_block_complete=true$' "$transcript" || true
    )
    if [[ "$exact_status" -eq 0 ]]; then
        [[ "$failure_count" -eq 0 ]]
        [[ "$completion_count" -eq 1 ]]
    else
        [[ "$failure_count" -ge 1 ]]
        [[ "$completion_count" -eq 0 ]]
        [[ "$(grep -Ec '^transition_exact_failure_status=[1-9][0-9]*$' "$transcript")" -ge 1 ]]
    fi
    validate_secret_free "$transcript"
}

run_contract_test() {
    local work_dir failure_fixture success_fixture

    work_dir=$(mktemp -d)
    trap 'rm -rf -- "$work_dir"' RETURN
    failure_fixture="$work_dir/failure"
    success_fixture="$work_dir/success"

    for fixture in "$failure_fixture" "$success_fixture"; do
        printf '%s\n' \
            action_17f_b_remote_reached=true \
            working_directory_is_root=true \
            transition_validate_baseline_status=0 \
            transition_live_state_assignment_status=0 \
            transition_snapshot_bytes=123 \
            transition_snapshot_readonly_status=0 \
            transition_snapshot_hash_status=0 \
            transition_snapshot_sha256=3a05c0487101f3b44f8e5ba41a4a74713d07cddc369542f04d4a8b1f417cb824 \
            transition_snapshot_hash_readonly_status=0 \
            remote_paths_created=false \
            dns_queries_performed=false \
            dns_configuration_mutations=false \
            service_mutations=false \
            persistent_mutations=false \
            action_17f_b_transition_diagnostic_complete=true >"$fixture"
    done
    printf '%s\n' \
        transition_exact_failure_step=snapshot_readonly \
        transition_exact_failure_status=1 \
        transition_exact_block_status=1 >>"$failure_fixture"
    printf '%s\n' \
        transition_exact_validate_baseline_status=0 \
        transition_exact_live_state_assignment_status=0 \
        transition_exact_snapshot_readonly_status=0 \
        transition_exact_snapshot_hash_status=0 \
        transition_exact_snapshot_hash_readonly_status=0 \
        transition_exact_block_complete=true \
        transition_exact_block_status=0 >>"$success_fixture"

    validate_transcript "$failure_fixture"
    validate_transcript "$success_fixture"
    printf 'action_17f_b_transition_runner_contract_test_complete=true\n'
}

case "${1:-}" in
    --self-test)
        (($# == 1))
        verify_sources
        "$diagnostic" --self-test >/dev/null
        printf 'action_17f_b_transition_runner_self_test_complete=true\n'
        exit 0
        ;;
    --contract-test)
        (($# == 1))
        verify_sources
        run_contract_test
        exit 0
        ;;
    --source-test)
        (($# == 1))
        verify_live_sources
        printf 'action_17f_b_transition_runner_source_test_complete=true\n'
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--self-test|--contract-test|--source-test]\n' \
            "${0##*/}" >&2
        exit 2
        ;;
esac

verify_live_sources
"$diagnostic" --self-test >/dev/null
"$regression" >/dev/null
run_contract_test >/dev/null

work_dir=$(mktemp -d)
readonly work_dir
transcript="$work_dir/transcript"
readonly transcript
cleanup() {
    rm -rf -- "$work_dir"
    printf 'action_17f_b_transition_local_cleanup_complete=true\n'
}
trap cleanup EXIT

ssh_status=0
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias="$expected_host_alias" \
    -o StrictHostKeyChecking=yes \
    "$expected_target" \
    "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" \
    <"$diagnostic" >"$transcript" 2>&1 || ssh_status=$?

cat "$transcript"
printf 'ssh_exit_status=%s\n' "$ssh_status"
[[ "$ssh_status" -eq 0 ]]
validate_transcript "$transcript"
printf 'action_17f_b_transition_diagnostic_accepted=true\n'
