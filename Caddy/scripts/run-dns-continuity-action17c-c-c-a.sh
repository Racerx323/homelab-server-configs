#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=6a7e25823db2eb04e0873e0f71b5f640b1016cfe0789ed52669f8b2aa1e73a81
readonly regression_sha256=31ead9ab002141946bf2b3d14a6cc4a395e4b2596348b25423cbf168664b1daf
readonly failed_runner_sha256=db6c273734ed52b43268af6823feeec08ca1aa191d89b970d641fe53453bf1a6
readonly failed_collector_sha256=5ef814b847151550a6c1cfa935917cc13861152f50ece55bd49b9e8ea107c364
readonly node_a_primary_sha256=dd5af7ccbbac11324921e1d447d753dbab33b633bc4cb1db248ee0574825d3ae
readonly node_a_prestate_sha256=0c6c2c57bc69b7fb2121a0e810ab9f3a31928bf853eafd5b2098a64d3057e102
readonly node_b_primary_sha256=017aa2556346c93a64a3571dcb49046fb858edd358937339bc5f7e60d145fac7
readonly node_b_prestate_sha256=af5b993ae06da8d4cf0199c046887a9d7c9874f8b0b1a547e854f15f2e765744

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly inspector="$script_dir/inspect-dns-continuity-action17c-c-c-a.sh"
readonly regression="$script_dir/../tests/action17c-c-c-a-dns-continuity-regression.sh"
readonly failed_runner="$script_dir/run-dns-path-authority-diagnostic-action17c-c-c.sh"
readonly failed_collector="$script_dir/diagnose-dns-path-authority-action17c-c-c.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_file() {
    local path=$1
    local expected_hash=$2

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(file_hash "$path")" == "$expected_hash" ]]
}

verify_source_content() {
    verify_file "$inspector" "$inspector_sha256"
    verify_file "$regression" "$regression_sha256"
    verify_file "$failed_runner" "$failed_runner_sha256"
    verify_file "$failed_collector" "$failed_collector_sha256"
    bash -n "$inspector"
}

verify_live_sources() {
    verify_source_content
    [[ "$(stat -c '%U:%G:%a' "$inspector")" == aaron:aaron:755 ]]
}

require_one() {
    local record=$1
    local transcript=$2

    [[ "$(grep -Fxc "$record" "$transcript")" -eq 1 ]]
}

value_for() {
    local prefix=$1
    local transcript=$2
    local record

    [[ "$(grep -Ec "^${prefix}=" "$transcript")" -eq 1 ]] || return 1
    record=$(grep -E "^${prefix}=" "$transcript")
    printf '%s\n' "${record#*=}"
}

validate_transcript() {
    local expected_role=$1
    local transcript=$2
    local expected_hostname expected_primary expected_prestate prefix value
    local check_false_count=0

    if [[ "$expected_role" == node-a ]]; then
        expected_hostname=j1-svpihole0
        expected_primary=$node_a_primary_sha256
        expected_prestate=$node_a_prestate_sha256
    else
        expected_hostname=j1-svpihole00
        expected_primary=$node_b_primary_sha256
        expected_prestate=$node_b_prestate_sha256
    fi

    require_one action_17c_c_c_a_remote_reached=true "$transcript"
    require_one "node_role=$expected_role" "$transcript"
    require_one "node_hostname=$expected_hostname" "$transcript"
    require_one action_17c_c_c_a_continuity_inspection_complete=true "$transcript"
    [[ "$(wc -l <"$transcript")" -eq 32 ]]
    for record in \
        dns_queries_performed=false \
        dns_configuration_mutations=false \
        service_mutations=false \
        persistent_mutations=false \
        remote_write_paths_created=false \
        remote_stage_cleanup_not_required=true; do
        require_one "$record" "$transcript" || return 1
    done

    value=$(value_for failed_action_stage_count "$transcript") || return 1
    [[ "$value" =~ ^[0-9]+$ ]]
    value=$(value_for action_17c_c_c_a_mismatch_count "$transcript") || return 1
    [[ "$value" =~ ^[0-9]+$ ]]
    [[ "$(value_for primary_config_file_state "$transcript")" =~ ^(regular|symlink|absent)$ ]]
    [[ "$(value_for primary_config_file_sha256 "$transcript")" =~ ^([0-9a-f]{64}|unavailable)$ ]]
    [[ "$(value_for primary_config_file_metadata "$transcript")" =~ ^([A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+:[0-7]{3,4}:[0-9]+|unavailable)$ ]]
    [[ "$(value_for local_zone_file_state "$transcript")" =~ ^(regular|symlink|absent)$ ]]
    require_one "expected_prestate_sha256=$expected_prestate" "$transcript"
    [[ "$(value_for continuity_state_sha256 "$transcript")" =~ ^[0-9a-f]{64}$ ]]
    require_one "primary_config_file_sha256=$expected_primary" "$transcript"

    for prefix in \
        node_hostname_matches \
        failed_action_stage_absent \
        primary_config_file_state_matches \
        primary_config_file_sha256_matches \
        primary_config_file_metadata_matches \
        local_zone_file_absent \
        primary_server_clause_present \
        primary_ipv4_loopback_present \
        primary_ipv6_loopback_present \
        primary_port_present \
        primary_contains_local_zone \
        unbound_active \
        pihole_ftl_active \
        continuity_state_matches_failed_prestate; do
        value=$(value_for "$prefix" "$transcript") || return 1
        [[ "$value" == true || "$value" == false ]] || return 1
        if [[ "$value" == false ]]; then
            check_false_count=$((check_false_count + 1))
        fi
    done
    [[ "$check_false_count" -eq "$(value_for action_17c_c_c_a_mismatch_count "$transcript")" ]]
}

write_fixture() {
    local role=$1
    local destination=$2
    local hostname primary prestate

    if [[ "$role" == node-a ]]; then
        hostname=j1-svpihole0
        primary=$node_a_primary_sha256
        prestate=$node_a_prestate_sha256
    else
        hostname=j1-svpihole00
        primary=$node_b_primary_sha256
        prestate=$node_b_prestate_sha256
    fi

    printf '%s\n' \
        action_17c_c_c_a_remote_reached=true \
        "node_role=$role" \
        "node_hostname=$hostname" \
        node_hostname_matches=true \
        failed_action_stage_count=0 \
        failed_action_stage_absent=true \
        primary_config_file_state=regular \
        "primary_config_file_sha256=$primary" \
        primary_config_file_metadata=root:root:644:1 \
        primary_config_file_state_matches=true \
        primary_config_file_sha256_matches=true \
        primary_config_file_metadata_matches=true \
        local_zone_file_state=absent \
        local_zone_file_absent=true \
        primary_server_clause_present=true \
        primary_ipv4_loopback_present=true \
        primary_ipv6_loopback_present=true \
        primary_port_present=true \
        primary_contains_local_zone=true \
        unbound_active=true \
        pihole_ftl_active=true \
        "expected_prestate_sha256=$prestate" \
        "continuity_state_sha256=$prestate" \
        continuity_state_matches_failed_prestate=true \
        action_17c_c_c_a_mismatch_count=0 \
        dns_queries_performed=false \
        dns_configuration_mutations=false \
        service_mutations=false \
        persistent_mutations=false \
        remote_write_paths_created=false \
        remote_stage_cleanup_not_required=true \
        action_17c_c_c_a_continuity_inspection_complete=true >"$destination"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for value in \
        "$inspector_sha256" \
        "$regression_sha256" \
        "$failed_runner_sha256" \
        "$failed_collector_sha256" \
        "$node_a_primary_sha256" \
        "$node_a_prestate_sha256" \
        "$node_b_primary_sha256" \
        "$node_b_prestate_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    verify_source_content
    "$inspector" --self-test >/dev/null
    printf 'action_17c_c_c_a_continuity_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    test_dir=$(mktemp -d /tmp/caddy-action17c-c-c-a-contract.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    write_fixture node-a "$test_dir/node-a"
    write_fixture node-b "$test_dir/node-b"
    validate_transcript node-a "$test_dir/node-a"
    validate_transcript node-b "$test_dir/node-b"
    printf 'failed_action_stage_absent=false\n' >>"$test_dir/node-a"
    if validate_transcript node-a "$test_dir/node-a"; then
        printf 'Duplicate continuity assertion was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17c_c_c_a_continuity_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_live_sources
work_dir=$(mktemp -d /tmp/caddy-action17c-c-c-a-runner.XXXXXX)
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

run_node() {
    local role=$1
    local target=$2
    local host_alias=$3
    local output=$4
    local error=$5
    local status=0

    ssh -T \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o "HostKeyAlias=$host_alias" \
        -o StrictHostKeyChecking=yes \
        "$target" \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s -- --node $role'" \
        <"$inspector" >"$output" 2>"$error" || status=$?
    printf '%s\n' "$status"
}

node_a_status=$(
    run_node node-a pi@10.1.0.53 pihole0.local.theama.co \
        "$work_dir/node-a.out" "$work_dir/node-a.err"
)
node_b_status=$(
    run_node node-b pi@10.1.0.54 pihole00.local.theama.co \
        "$work_dir/node-b.out" "$work_dir/node-b.err"
)
cat "$work_dir/node-a.out"
cat "$work_dir/node-b.out"
cat "$work_dir/node-a.err" >&2
cat "$work_dir/node-b.err" >&2
printf '%s\n' \
    "node_a_administrative_ssh_status=$node_a_status" \
    "node_b_administrative_ssh_status=$node_b_status"

if [[ "$node_a_status" -gt 1 || "$node_b_status" -gt 1 ]] ||
    [[ -s "$work_dir/node-a.err" || -s "$work_dir/node-b.err" ]] ||
    ! validate_transcript node-a "$work_dir/node-a.out" ||
    ! validate_transcript node-b "$work_dir/node-b.out"; then
    printf 'Action 17c-c-c-a continuity evidence is incomplete.\n' >&2
    exit 97
fi

node_a_mismatches=$(value_for action_17c_c_c_a_mismatch_count "$work_dir/node-a.out")
node_b_mismatches=$(value_for action_17c_c_c_a_mismatch_count "$work_dir/node-b.out")
if [[ ("$node_a_mismatches" -eq 0 && "$node_a_status" -ne 0) ||
    ("$node_a_mismatches" -gt 0 && "$node_a_status" -ne 1) ||
    ("$node_b_mismatches" -eq 0 && "$node_b_status" -ne 0) ||
    ("$node_b_mismatches" -gt 0 && "$node_b_status" -ne 1) ]]; then
    exit 97
fi
if [[ "$node_a_mismatches" -eq 0 && "$node_b_mismatches" -eq 0 ]]; then
    conclusion=continuity_verified
    accepted=true
    result_status=0
else
    [[ "$node_a_status" -eq 1 || "$node_b_status" -eq 1 ]] || exit 97
    conclusion=continuity_mismatch
    accepted=false
    result_status=1
fi

printf '%s\n' \
    "action_17c_c_c_a_conclusion=$conclusion" \
    "action_17c_c_c_a_continuity_accepted=$accepted"

cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf 'action_17c_c_c_a_local_cleanup_complete=true\n'
exit "$result_status"
