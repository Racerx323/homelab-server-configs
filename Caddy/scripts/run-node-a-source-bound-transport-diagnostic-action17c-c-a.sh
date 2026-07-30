#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly node_a_diagnostic_sha256=3011cd5498729b8b3fff9731975f51f737610e41d0b9ee60e857ec3ff83b0609
readonly node_b_inspector_sha256=37e5390fb132c77002b468d9dfabfc579d5bb03f1da44f60802c448df3a35111
readonly node_a_host_alias=pihole0.local.theama.co
readonly node_a_target=pi@10.1.0.53
readonly node_b_host_alias=pihole00.local.theama.co
readonly node_b_target=pi@10.1.0.54

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly node_a_diagnostic="$script_dir/diagnose-node-a-source-bound-transport-action17c-c-a.sh"
readonly node_b_inspector="$script_dir/inspect-node-b-restricted-transport-state-action17c.sh"

readonly -a prestate_labels=(
    identity
    working_directory
    hostname
    architecture
    environment_file
    environment_role
    environment_node_ipv6
    environment_peer_ipv6
    environment_sync_target
    private_key_regular
    private_key_not_symlink
    public_key_regular
    known_hosts_regular
    ssh_directory_mode
    private_key_mode
    known_hosts_mode
    public_key_fingerprint
    known_host_fingerprint
    stable_ipv6_present
)
readonly -a probe_boolean_suffixes=(
    connecting
    connection_established
    host_key_verified
    public_key_offered
    server_accepted_key
    authenticated
)

verify_artifact_content() {
    local path=$1
    local expected_hash=$2

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(sha256sum "$path" | awk '{ print $1 }')" == "$expected_hash" ]]
    bash -n "$path"
}

verify_artifact() {
    local path=$1
    local expected_hash=$2

    verify_artifact_content "$path" "$expected_hash"
    [[ "$(stat -c '%U:%G:%a' "$path")" == aaron:aaron:755 ]]
}

require_one() {
    local value=$1
    local transcript=$2

    [[ "$(grep -Fxc "$value" "$transcript")" -eq 1 ]]
}

value_for() {
    local prefix=$1
    local transcript=$2
    local record

    [[ "$(grep -Ec "^${prefix}=" "$transcript")" -eq 1 ]] || return 1
    record=$(grep -E "^${prefix}=" "$transcript")
    printf '%s\n' "${record#*=}"
}

validate_boolean() {
    local prefix=$1
    local transcript=$2
    local value

    value=$(value_for "$prefix" "$transcript") || return 1
    [[ "$value" == true || "$value" == false ]]
}

validate_node_b() {
    local transcript=$1
    local marker

    for marker in \
        action_17c_node_b_state_valid=true \
        restricted_authorization_count=1 \
        incoming_node_a_present=false \
        incoming_node_b_present=false \
        outbound_file_count=0 \
        lsyncd_configuration_present=false \
        synchronization_services_active=false \
        action_17c_node_b_state_inspection_complete=true; do
        require_one "$marker" "$transcript" || return 1
    done
    [[ "$(grep -Ec '^node_b_state_digest=[0-9a-f]{64}$' \
        "$transcript")" -eq 1 ]]
}

validate_state_record() {
    local label=$1
    local transcript=$2
    local status state_hash stderr_hash

    status=$(value_for "${label}_state_status" "$transcript") || return 1
    state_hash=$(value_for "${label}_state_sha256" "$transcript") || return 1
    stderr_hash=$(value_for "${label}_state_stderr_sha256" "$transcript") ||
        return 1
    [[ "$status" =~ ^[0-9]{1,3}$ ]]
    [[ "$stderr_hash" =~ ^[0-9a-f]{64}$ ]]
    if [[ "$status" -eq 0 ]]; then
        [[ "$state_hash" =~ ^[0-9a-f]{64}$ ]]
    else
        [[ "$state_hash" == unavailable ]]
    fi
}

validate_node_a() {
    local transcript=$1
    local label suffix
    local total passed failed status error_class

    for marker in \
        action_17c_c_a_prestate_collection_complete=true \
        action_17c_c_a_direct_ssh_collection_complete=true \
        release_payload_transferred=false \
        rsync_invoked=false \
        service_mutations=false \
        action_17c_c_a_node_a_cleanup_complete=true \
        action_17c_c_a_node_a_diagnostic_complete=true; do
        require_one "$marker" "$transcript" || return 1
    done
    for label in "${prestate_labels[@]}"; do
        validate_boolean "prestate_check_$label" "$transcript" || return 1
    done
    total=$(value_for prestate_checks_total "$transcript") || return 1
    passed=$(value_for prestate_checks_passed "$transcript") || return 1
    failed=$(value_for prestate_checks_failed "$transcript") || return 1
    [[ "$total" =~ ^[0-9]{1,2}$ ]]
    [[ "$passed" =~ ^[0-9]{1,2}$ ]]
    [[ "$failed" =~ ^[0-9]{1,2}$ ]]
    [[ "$total" -eq "${#prestate_labels[@]}" ]]
    [[ $((passed + failed)) -eq total ]]
    validate_state_record before "$transcript" || return 1
    validate_state_record after "$transcript" || return 1
    validate_boolean node_a_relevant_state_unchanged "$transcript" || return 1

    status=$(value_for source_bound_ssh_status "$transcript") || return 1
    error_class=$(value_for source_bound_ssh_error_class "$transcript") ||
        return 1
    [[ "$status" =~ ^[0-9]{1,3}$ ]]
    [[ "$error_class" =~ ^(forced_receiver_rejection|name_resolution_failed|bind_address_unavailable|network_unreachable|no_route_to_host|connection_timed_out|connection_refused|host_key_mismatch|publickey_denied|connection_closed|unclassified)$ ]]
    for suffix in "${probe_boolean_suffixes[@]}"; do
        validate_boolean "source_bound_ssh_$suffix" "$transcript" || return 1
    done
    validate_boolean source_bound_forced_receiver_message "$transcript" ||
        return 1
    validate_boolean source_bound_ssh_stdout_empty "$transcript" || return 1
    [[ "$(value_for source_bound_ssh_stdout_sha256 "$transcript")" =~ ^[0-9a-f]{64}$ ]]
    [[ "$(value_for source_bound_ssh_stderr_sha256 "$transcript")" =~ ^[0-9a-f]{64}$ ]]
    if [[ "$error_class" == forced_receiver_rejection ]]; then
        [[ "$status" -eq 126 ]]
        require_one source_bound_ssh_authenticated=true "$transcript" ||
            return 1
        require_one source_bound_forced_receiver_message=true "$transcript" ||
            return 1
    fi
}

derive_conclusion() {
    local transcript=$1
    local failed before_status after_status unchanged error_class

    failed=$(value_for prestate_checks_failed "$transcript")
    before_status=$(value_for before_state_status "$transcript")
    after_status=$(value_for after_state_status "$transcript")
    unchanged=$(value_for node_a_relevant_state_unchanged "$transcript")
    error_class=$(value_for source_bound_ssh_error_class "$transcript")

    if [[ "$failed" -ne 0 || "$before_status" -ne 0 ]]; then
        printf 'node_a_prestate_incomplete\n'
    elif [[ "$after_status" -ne 0 || "$unchanged" != true ]]; then
        printf 'node_a_poststate_mismatch\n'
    elif [[ "$error_class" == forced_receiver_rejection ]]; then
        printf 'source_bound_direct_ssh_reaches_forced_receiver\n'
    else
        printf 'source_bound_direct_ssh_%s\n' "$error_class"
    fi
}

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$@"
}

write_node_b_fixture() {
    local destination=$1
    local digest=$2

    printf '%s\n' \
        action_17c_node_b_state_valid=true \
        "node_b_state_digest=$digest" \
        restricted_authorization_count=1 \
        incoming_node_a_present=false \
        incoming_node_b_present=false \
        outbound_file_count=0 \
        lsyncd_configuration_present=false \
        synchronization_services_active=false \
        action_17c_node_b_state_inspection_complete=true >"$destination"
}

write_node_a_fixture() {
    local destination=$1
    local label
    local empty_hash=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

    for label in "${prestate_labels[@]}"; do
        printf 'prestate_check_%s=true\n' "$label"
    done >"$destination"
    printf '%s\n' \
        "prestate_checks_total=${#prestate_labels[@]}" \
        "prestate_checks_passed=${#prestate_labels[@]}" \
        prestate_checks_failed=0 \
        action_17c_c_a_prestate_collection_complete=true \
        before_state_status=0 \
        "before_state_stderr_sha256=$empty_hash" \
        before_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        source_bound_ssh_status=126 \
        source_bound_ssh_error_class=forced_receiver_rejection \
        source_bound_ssh_connecting=true \
        source_bound_ssh_connection_established=true \
        source_bound_ssh_host_key_verified=true \
        source_bound_ssh_public_key_offered=true \
        source_bound_ssh_server_accepted_key=true \
        source_bound_ssh_authenticated=true \
        source_bound_forced_receiver_message=true \
        source_bound_ssh_stdout_empty=true \
        "source_bound_ssh_stdout_sha256=$empty_hash" \
        source_bound_ssh_stderr_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
        action_17c_c_a_direct_ssh_collection_complete=true \
        after_state_status=0 \
        "after_state_stderr_sha256=$empty_hash" \
        after_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        node_a_relevant_state_unchanged=true \
        release_payload_transferred=false \
        rsync_invoked=false \
        service_mutations=false \
        action_17c_c_a_node_a_cleanup_complete=true \
        action_17c_c_a_node_a_diagnostic_complete=true >>"$destination"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$node_a_diagnostic_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$node_b_inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    verify_artifact_content "$node_a_diagnostic" "$node_a_diagnostic_sha256"
    verify_artifact_content "$node_b_inspector" "$node_b_inspector_sha256"
    "$node_a_diagnostic" --self-test >/dev/null
    "$node_b_inspector" --self-test >/dev/null
    printf 'action_17c_c_a_diagnostic_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    test_dir=$(mktemp -d /tmp/caddy-action17c-c-a-contract.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    digest=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
    write_node_b_fixture "$test_dir/node-b" "$digest"
    write_node_a_fixture "$test_dir/node-a"
    validate_node_b "$test_dir/node-b"
    validate_node_a "$test_dir/node-a"
    [[ "$(derive_conclusion "$test_dir/node-a")" == source_bound_direct_ssh_reaches_forced_receiver ]]
    validate_secret_free "$test_dir/node-a" "$test_dir/node-b"
    cp -- "$test_dir/node-a" "$test_dir/duplicate"
    printf 'source_bound_ssh_status=126\n' >>"$test_dir/duplicate"
    if validate_node_a "$test_dir/duplicate"; then
        printf 'Duplicate diagnostic marker was accepted.\n' >&2
        exit 1
    fi
    sed \
        's/source_bound_ssh_authenticated=true/source_bound_ssh_authenticated=false/' \
        "$test_dir/node-a" >"$test_dir/inconsistent"
    if validate_node_a "$test_dir/inconsistent"; then
        printf 'Inconsistent forced-receiver evidence was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17c_c_a_diagnostic_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_artifact "$node_a_diagnostic" "$node_a_diagnostic_sha256"
verify_artifact "$node_b_inspector" "$node_b_inspector_sha256"
work_dir=$(mktemp -d /tmp/caddy-action17c-c-a-runner.XXXXXX)
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

run_remote() {
    local host_alias=$1
    local target=$2
    local command=$3
    local payload=$4
    local output=$5
    local error=$6
    local status_name=$7
    local status=0

    ssh -T \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o "HostKeyAlias=$host_alias" \
        -o StrictHostKeyChecking=yes \
        "$target" "$command" \
        <"$payload" >"$output" 2>"$error" || status=$?
    printf -v "$status_name" '%s' "$status"
}

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
    "$node_a_diagnostic" "$work_dir/node-a.out" "$work_dir/node-a.err" \
    node_a_status
run_remote \
    "$node_b_host_alias" "$node_b_target" \
    'sudo -n /bin/bash -s --' "$node_b_inspector" \
    "$work_dir/node-b-after.out" "$work_dir/node-b-after.err" \
    node_b_after_status

cat "$work_dir/node-a.out"
cat "$work_dir/node-b-before.err" >&2
cat "$work_dir/node-a.err" >&2
cat "$work_dir/node-b-after.err" >&2
printf 'node_b_before_ssh_status=%s\n' "$node_b_before_status"
printf 'node_a_diagnostic_ssh_status=%s\n' "$node_a_status"
printf 'node_b_after_ssh_status=%s\n' "$node_b_after_status"

if [[ "$node_b_before_status" -ne 0 ||
    "$node_a_status" -ne 0 ||
    "$node_b_after_status" -ne 0 ]] ||
    [[ -s "$work_dir/node-b-before.err" ||
        -s "$work_dir/node-a.err" ||
        -s "$work_dir/node-b-after.err" ]] ||
    ! validate_node_b "$work_dir/node-b-before.out" ||
    ! validate_node_a "$work_dir/node-a.out" ||
    ! validate_node_b "$work_dir/node-b-after.out" ||
    ! validate_secret_free "$work_dir"/*.out "$work_dir"/*.err; then
    printf 'Action 17c-c-a diagnostic evidence is incomplete.\n' >&2
    exit 97
fi

before_digest=$(value_for node_b_state_digest "$work_dir/node-b-before.out")
after_digest=$(value_for node_b_state_digest "$work_dir/node-b-after.out")
if [[ "$before_digest" != "$after_digest" ]]; then
    printf 'Node B protected-state digest changed during the diagnostic.\n' >&2
    exit 97
fi
printf 'node_b_before_state_digest=%s\n' "$before_digest"
printf 'node_b_after_state_digest=%s\n' "$after_digest"
printf 'node_b_protected_state_unchanged=true\n'
printf 'action_17c_c_a_diagnostic_conclusion=%s\n' \
    "$(derive_conclusion "$work_dir/node-a.out")"
printf 'action_17c_c_a_diagnostic_accepted=true\n'

cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf 'action_17c_c_a_local_cleanup_complete=true\n'
