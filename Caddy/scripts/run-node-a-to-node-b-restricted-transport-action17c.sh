#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=37e5390fb132c77002b468d9dfabfc579d5bb03f1da44f60802c448df3a35111
readonly driver_sha256=f3e775716ec0d3506b67088286545fb5998e2c587b56f18e5f20b27c314a15c0
readonly node_a_host_alias=pihole0.local.theama.co
readonly node_a_target=pi@10.1.0.53
readonly node_b_host_alias=pihole00.local.theama.co
readonly node_b_target=pi@10.1.0.54

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly inspector="$script_dir/inspect-node-b-restricted-transport-state-action17c.sh"
readonly driver="$script_dir/validate-node-a-to-node-b-restricted-transport-action17c.sh"

verify_artifact() {
    local path=$1
    local expected_hash=$2

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(stat -c '%U:%G:%a' "$path")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$path" | awk '{ print $1 }')" == "$expected_hash" ]]
    bash -n "$path"
}

require_one() {
    local value=$1
    local transcript=$2

    [[ "$(grep -Fxc "$value" "$transcript")" -eq 1 ]]
}

extract_one_digest() {
    local prefix=$1
    local transcript=$2
    local record

    [[ "$(grep -Ec "^${prefix}[0-9a-f]{64}$" "$transcript")" -eq 1 ]] ||
        return 1
    record=$(grep -E "^${prefix}[0-9a-f]{64}$" "$transcript")
    printf '%s\n' "${record#"$prefix"}"
}

validate_node_b_transcript() {
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
    extract_one_digest node_b_state_digest= "$transcript" >/dev/null
}

validate_node_a_success() {
    local transcript=$1
    local marker

    for marker in \
        action_17c_node_a_preflight_complete=true \
        ipv4_restricted_authentication=true \
        ipv4_forced_receiver_rejection=true \
        ipv6_restricted_authentication=true \
        ipv6_forced_receiver_rejection=true \
        ipv4_rsync_dry_run=true \
        node_a_protected_state_unchanged=true \
        release_payload_transferred=false \
        incoming_node_a_present=false \
        incoming_node_b_present=false \
        outbound_file_count=0 \
        lsyncd_configuration_present=false \
        service_mutations=false \
        first_failure=none \
        action_17c_node_a_cleanup_complete=true \
        action_17c_restricted_transport_validation_complete=true; do
        require_one "$marker" "$transcript" || return 1
    done
    if grep -Fq \
        'action_17c_restricted_transport_validation_complete=false' \
        "$transcript"; then
        return 1
    fi
}

validate_node_a_semantic_failure() {
    local transcript=$1

    require_one action_17c_node_a_preflight_complete=true "$transcript" ||
        return 1
    require_one node_a_protected_state_unchanged=true "$transcript" ||
        return 1
    require_one release_payload_transferred=false "$transcript" ||
        return 1
    require_one action_17c_node_a_cleanup_complete=true "$transcript" ||
        return 1
    require_one \
        action_17c_restricted_transport_validation_complete=false \
        "$transcript" || return 1
    [[ "$(grep -Ec \
        '^first_failure=(ipv4_forced_receiver_rejection|ipv6_forced_receiver_rejection|ipv4_rsync_dry_run)$' \
        "$transcript")" -eq 1 ]]
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

write_node_a_success_fixture() {
    local destination=$1

    printf '%s\n' \
        action_17c_node_a_preflight_complete=true \
        ipv4_restricted_authentication=true \
        ipv4_forced_receiver_rejection=true \
        ipv6_restricted_authentication=true \
        ipv6_forced_receiver_rejection=true \
        ipv4_rsync_dry_run=true \
        node_a_protected_state_unchanged=true \
        release_payload_transferred=false \
        incoming_node_a_present=false \
        incoming_node_b_present=false \
        outbound_file_count=0 \
        lsyncd_configuration_present=false \
        service_mutations=false \
        first_failure=none \
        action_17c_node_a_cleanup_complete=true \
        action_17c_restricted_transport_validation_complete=true \
        >"$destination"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$driver_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$node_a_host_alias" == pihole0.local.theama.co ]]
    [[ "$node_a_target" == pi@10.1.0.53 ]]
    [[ "$node_b_host_alias" == pihole00.local.theama.co ]]
    [[ "$node_b_target" == pi@10.1.0.54 ]]
    verify_artifact "$inspector" "$inspector_sha256"
    verify_artifact "$driver" "$driver_sha256"
    "$inspector" --self-test >/dev/null
    "$driver" --self-test >/dev/null
    printf 'action_17c_restricted_transport_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action17c-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    digest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    write_node_b_fixture "$contract_dir/node-b-before" "$digest"
    write_node_b_fixture "$contract_dir/node-b-after" "$digest"
    write_node_a_success_fixture "$contract_dir/node-a"
    : >"$contract_dir/empty-error"
    validate_node_b_transcript "$contract_dir/node-b-before"
    validate_node_b_transcript "$contract_dir/node-b-after"
    validate_node_a_success "$contract_dir/node-a"
    validate_secret_free \
        "$contract_dir/node-b-before" \
        "$contract_dir/node-b-after" \
        "$contract_dir/node-a" \
        "$contract_dir/empty-error"
    [[ "$(extract_one_digest node_b_state_digest= \
        "$contract_dir/node-b-before")" == "$(extract_one_digest \
            node_b_state_digest= "$contract_dir/node-b-after")" ]]

    cp -- "$contract_dir/node-a" "$contract_dir/duplicate"
    printf 'ipv4_rsync_dry_run=true\n' >>"$contract_dir/duplicate"
    if validate_node_a_success "$contract_dir/duplicate"; then
        printf 'Duplicate transport marker was accepted.\n' >&2
        exit 1
    fi

    printf '%s\n' \
        action_17c_node_a_preflight_complete=true \
        ipv4_restricted_authentication=false \
        ipv4_forced_receiver_rejection=false \
        ipv6_restricted_authentication=false \
        ipv6_forced_receiver_rejection=false \
        ipv4_rsync_dry_run=false \
        node_a_protected_state_unchanged=true \
        release_payload_transferred=false \
        incoming_node_a_present=false \
        incoming_node_b_present=false \
        outbound_file_count=0 \
        lsyncd_configuration_present=false \
        service_mutations=false \
        first_failure=ipv4_forced_receiver_rejection \
        action_17c_node_a_cleanup_complete=true \
        action_17c_restricted_transport_validation_complete=false \
        >"$contract_dir/semantic-failure"
    validate_node_a_semantic_failure "$contract_dir/semantic-failure"

    cp -- "$contract_dir/node-a" "$contract_dir/secret"
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$contract_dir/secret"
    if validate_secret_free "$contract_dir/secret"; then
        printf 'Secret-bearing output was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17c_restricted_transport_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_artifact "$inspector" "$inspector_sha256"
verify_artifact "$driver" "$driver_sha256"
work_dir=$(mktemp -d /tmp/caddy-action17c.XXXXXX)
readonly work_dir

cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

run_remote() {
    local host_alias=$1
    local target=$2
    local payload=$3
    local output_file=$4
    local error_file=$5
    local status_name=$6
    local command_status=0

    ssh -T \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o "HostKeyAlias=$host_alias" \
        -o StrictHostKeyChecking=yes \
        "$target" \
        'sudo -n /bin/bash -s --' \
        <"$payload" >"$output_file" 2>"$error_file" || command_status=$?
    printf -v "$status_name" '%s' "$command_status"
}

node_b_before_status=0
node_a_status=0
node_b_after_status=0
run_remote \
    "$node_b_host_alias" "$node_b_target" "$inspector" \
    "$work_dir/node-b-before.out" "$work_dir/node-b-before.err" \
    node_b_before_status
run_remote \
    "$node_a_host_alias" "$node_a_target" "$driver" \
    "$work_dir/node-a.out" "$work_dir/node-a.err" \
    node_a_status
run_remote \
    "$node_b_host_alias" "$node_b_target" "$inspector" \
    "$work_dir/node-b-after.out" "$work_dir/node-b-after.err" \
    node_b_after_status

cat "$work_dir/node-a.out"
cat "$work_dir/node-b-before.err" >&2
cat "$work_dir/node-a.err" >&2
cat "$work_dir/node-b-after.err" >&2
printf 'node_b_before_ssh_status=%s\n' "$node_b_before_status"
printf 'node_a_probe_ssh_status=%s\n' "$node_a_status"
printf 'node_b_after_ssh_status=%s\n' "$node_b_after_status"

if ! validate_secret_free "$work_dir"/*.out "$work_dir"/*.err; then
    printf 'Unsafe Action 17c output detected.\n' >&2
    exit 97
fi
if [[ "$node_b_before_status" -ne 0 || "$node_b_after_status" -ne 0 ]] ||
    [[ -s "$work_dir/node-b-before.err" ||
        -s "$work_dir/node-b-after.err" ]] ||
    ! validate_node_b_transcript "$work_dir/node-b-before.out" ||
    ! validate_node_b_transcript "$work_dir/node-b-after.out"; then
    cat "$work_dir/node-b-before.out" >&2
    cat "$work_dir/node-b-after.out" >&2
    printf 'Action 17c Node B state evidence is incomplete.\n' >&2
    exit 97
fi

before_digest=$(extract_one_digest \
    node_b_state_digest= "$work_dir/node-b-before.out")
after_digest=$(extract_one_digest \
    node_b_state_digest= "$work_dir/node-b-after.out")
if [[ "$before_digest" != "$after_digest" ]]; then
    printf 'Action 17c changed protected Node B state.\n' >&2
    exit 97
fi
printf 'node_b_before_state_valid=true\n'
printf 'node_b_before_state_digest=%s\n' "$before_digest"
printf 'node_b_after_state_valid=true\n'
printf 'node_b_after_state_digest=%s\n' "$after_digest"

if [[ "$node_a_status" -eq 0 ]]; then
    if [[ -s "$work_dir/node-a.err" ]] ||
        ! validate_node_a_success "$work_dir/node-a.out"; then
        printf 'Action 17c success evidence is malformed.\n' >&2
        exit 97
    fi
    printf 'node_b_protected_state_unchanged=true\n'
    printf 'action_17c_restricted_transport_accepted=true\n'
    cleanup
    trap - EXIT
    [[ ! -e "$work_dir" && ! -L "$work_dir" ]]
    printf 'action_17c_local_cleanup_complete=true\n'
    exit 0
fi

if [[ "$node_a_status" -eq 1 ]] &&
    [[ ! -s "$work_dir/node-a.err" ]] &&
    validate_node_a_semantic_failure "$work_dir/node-a.out"; then
    printf 'node_b_protected_state_unchanged=true\n'
    printf 'action_17c_restricted_transport_accepted=false\n'
    cleanup
    trap - EXIT
    [[ ! -e "$work_dir" && ! -L "$work_dir" ]]
    printf 'action_17c_local_cleanup_complete=true\n'
    exit 1
fi

printf 'Action 17c failure evidence is malformed or incomplete.\n' >&2
exit 97
