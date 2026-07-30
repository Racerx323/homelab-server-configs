#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly node_b_inspector_sha256=eb348a76e2ebfe64060e9976ffdbbb772c6a4fc1cf61e092288ce36bd6ec83d2
readonly node_a_diagnostic_sha256=e3fe442b4fcb0a275fb29e5c1e9b4171b3588a27fa51a077cb18cf464c385a82
readonly node_a_host_alias=pihole0.local.theama.co
readonly node_a_target=pi@10.1.0.53
readonly node_b_host_alias=pihole00.local.theama.co
readonly node_b_target=pi@10.1.0.54

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly node_b_inspector="$script_dir/inspect-node-b-ipv6-restricted-transport-action17c-a.sh"
readonly node_a_diagnostic="$script_dir/diagnose-node-a-ipv6-source-selection-action17c-b.sh"

readonly -a node_b_fixed_markers=(
    action_17c_a_node_b_preflight_complete=true
    node_b_relevant_state_unchanged=true
    node_b_release_payload_transferred=false
    node_b_service_mutations=false
    action_17c_a_node_b_inspection_complete=true
)
readonly -a node_b_boolean_prefixes=(
    node_b_ipv6_address_present
    node_b_ssh_ipv6_listener_present
    node_b_ipv6_route_source_matches
    node_b_ipv6_route_device_matches
    node_b_authorization_source_ipv6_present
    node_b_sshd_active
)
readonly -a node_a_fixed_markers=(
    action_17c_b_node_a_preflight_complete=true
    node_a_relevant_state_unchanged=true
    release_payload_transferred=false
    rsync_invoked=false
    service_mutations=false
    action_17c_b_node_a_cleanup_complete=true
    action_17c_b_node_a_diagnostic_complete=true
)
readonly -a probe_boolean_suffixes=(
    ssh_connecting
    ssh_connection_established
    ssh_host_key_verified
    ssh_public_key_offered
    ssh_server_accepted_key
    ssh_authenticated
    forced_receiver_message
)

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

validate_node_b_transcript() {
    local transcript=$1
    local marker prefix route_status

    for marker in "${node_b_fixed_markers[@]}"; do
        require_one "$marker" "$transcript" || return 1
    done
    for prefix in "${node_b_boolean_prefixes[@]}"; do
        validate_boolean "$prefix" "$transcript" || return 1
    done
    route_status=$(value_for node_b_ipv6_route_status "$transcript") ||
        return 1
    [[ "$route_status" =~ ^[0-9]{1,3}$ ]]
}

validate_probe() {
    local label=$1
    local transcript=$2
    local suffix status error_class stderr_hash

    status=$(value_for "${label}_ssh_status" "$transcript") || return 1
    error_class=$(value_for "${label}_ssh_error_class" "$transcript") ||
        return 1
    stderr_hash=$(value_for "${label}_ssh_stderr_sha256" "$transcript") ||
        return 1
    [[ "$status" =~ ^[0-9]{1,3}$ ]]
    [[ "$error_class" =~ ^(forced_receiver_rejection|bind_address_unavailable|network_unreachable|no_route_to_host|connection_timed_out|connection_refused|publickey_denied|host_key_mismatch|connection_closed|unclassified)$ ]]
    [[ "$stderr_hash" =~ ^[0-9a-f]{64}$ ]]
    for suffix in "${probe_boolean_suffixes[@]}"; do
        validate_boolean "${label}_${suffix}" "$transcript" || return 1
    done

    if [[ "$error_class" == forced_receiver_rejection ]]; then
        [[ "$status" -eq 126 ]]
        require_one "${label}_ssh_authenticated=true" "$transcript"
        require_one "${label}_forced_receiver_message=true" "$transcript"
    fi
}

validate_node_a_transcript() {
    local transcript=$1
    local marker route_status selected_source

    for marker in "${node_a_fixed_markers[@]}"; do
        require_one "$marker" "$transcript" || return 1
    done
    route_status=$(value_for node_a_ipv6_route_status "$transcript") ||
        return 1
    selected_source=$(value_for node_a_ipv6_selected_source "$transcript") ||
        return 1
    [[ "$route_status" =~ ^[0-9]{1,3}$ ]]
    [[ "$selected_source" == none ||
        ("$selected_source" =~ ^[0-9A-Fa-f:]+$ &&
        ${#selected_source} -le 39) ]]
    validate_boolean \
        node_a_ipv6_selected_source_matches_stable "$transcript"
    validate_probe unbound "$transcript"
    validate_probe bound "$transcript"
}

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$@"
}

derive_conclusion() {
    local transcript=$1
    local unbound_class bound_class

    unbound_class=$(value_for unbound_ssh_error_class "$transcript")
    bound_class=$(value_for bound_ssh_error_class "$transcript")

    if [[ "$bound_class" == forced_receiver_rejection ]]; then
        if [[ "$unbound_class" == forced_receiver_rejection ]]; then
            printf 'both_source_modes_authorized\n'
        else
            printf 'stable_source_binding_restores_authorization\n'
        fi
    elif [[ "$bound_class" == bind_address_unavailable ]]; then
        printf 'stable_bind_address_unavailable\n'
    elif [[ "$bound_class" == publickey_denied ]]; then
        printf 'stable_source_binding_key_denied\n'
    elif [[ "$bound_class" =~ ^(network_unreachable|no_route_to_host|connection_timed_out|connection_refused|host_key_mismatch|connection_closed)$ ]]; then
        printf 'stable_source_binding_%s\n' "$bound_class"
    else
        printf 'stable_source_binding_unclassified\n'
    fi
}

write_node_b_fixture() {
    local destination=$1

    printf '%s\n' \
        "${node_b_fixed_markers[@]}" \
        node_b_ipv6_address_present=true \
        node_b_ssh_ipv6_listener_present=true \
        node_b_ipv6_route_status=0 \
        node_b_ipv6_route_source_matches=true \
        node_b_ipv6_route_device_matches=true \
        node_b_authorization_source_ipv6_present=true \
        node_b_sshd_active=true >"$destination"
}

write_probe_fixture() {
    local label=$1
    local error_class=$2
    local destination=$3
    local status=255
    local accepted=false
    local authenticated=false
    local forced=false

    if [[ "$error_class" == forced_receiver_rejection ]]; then
        status=126
        accepted=true
        authenticated=true
        forced=true
    fi
    printf '%s\n' \
        "${label}_ssh_status=$status" \
        "${label}_ssh_error_class=$error_class" \
        "${label}_ssh_connecting=true" \
        "${label}_ssh_connection_established=true" \
        "${label}_ssh_host_key_verified=true" \
        "${label}_ssh_public_key_offered=true" \
        "${label}_ssh_server_accepted_key=$accepted" \
        "${label}_ssh_authenticated=$authenticated" \
        "${label}_forced_receiver_message=$forced" \
        "${label}_ssh_stderr_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
        >>"$destination"
}

write_node_a_fixture() {
    local destination=$1

    printf '%s\n' \
        "${node_a_fixed_markers[@]}" \
        node_a_ipv6_route_status=0 \
        node_a_ipv6_selected_source=fd36:5aa8:6971:1:1234:5678:9abc:def0 \
        node_a_ipv6_selected_source_matches_stable=false >"$destination"
    write_probe_fixture unbound publickey_denied "$destination"
    write_probe_fixture bound forced_receiver_rejection "$destination"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$node_b_inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$node_a_diagnostic_sha256" =~ ^[0-9a-f]{64}$ ]]
    verify_artifact "$node_b_inspector" "$node_b_inspector_sha256"
    verify_artifact "$node_a_diagnostic" "$node_a_diagnostic_sha256"
    "$node_b_inspector" --self-test >/dev/null
    "$node_a_diagnostic" --self-test >/dev/null
    printf 'action_17c_b_source_selection_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action17c-b-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    write_node_b_fixture "$contract_dir/node-b"
    write_node_a_fixture "$contract_dir/node-a"
    : >"$contract_dir/empty-error"
    validate_node_b_transcript "$contract_dir/node-b"
    validate_node_a_transcript "$contract_dir/node-a"
    validate_secret_free \
        "$contract_dir/node-b" "$contract_dir/node-a" \
        "$contract_dir/empty-error"
    [[ "$(derive_conclusion "$contract_dir/node-a")" == stable_source_binding_restores_authorization ]]

    cp -- "$contract_dir/node-a" "$contract_dir/duplicate"
    printf 'bound_ssh_status=126\n' >>"$contract_dir/duplicate"
    if validate_node_a_transcript "$contract_dir/duplicate"; then
        printf 'Duplicate Action 17c-b evidence was accepted.\n' >&2
        exit 1
    fi

    cp -- "$contract_dir/node-a" "$contract_dir/secret"
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$contract_dir/secret"
    if validate_secret_free "$contract_dir/secret"; then
        printf 'Secret-bearing Action 17c-b evidence was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17c_b_source_selection_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_artifact "$node_b_inspector" "$node_b_inspector_sha256"
verify_artifact "$node_a_diagnostic" "$node_a_diagnostic_sha256"
work_dir=$(mktemp -d /tmp/caddy-action17c-b.XXXXXX)
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

node_b_status=0
node_a_status=0
run_remote \
    "$node_b_host_alias" "$node_b_target" "$node_b_inspector" \
    "$work_dir/node-b.out" "$work_dir/node-b.err" node_b_status
run_remote \
    "$node_a_host_alias" "$node_a_target" "$node_a_diagnostic" \
    "$work_dir/node-a.out" "$work_dir/node-a.err" node_a_status

cat "$work_dir/node-b.out"
cat "$work_dir/node-a.out"
cat "$work_dir/node-b.err" >&2
cat "$work_dir/node-a.err" >&2
printf 'node_b_admin_ssh_status=%s\n' "$node_b_status"
printf 'node_a_admin_ssh_status=%s\n' "$node_a_status"

if ! validate_secret_free "$work_dir"/*.out "$work_dir"/*.err; then
    printf 'Unsafe Action 17c-b output detected.\n' >&2
    exit 97
fi
if [[ "$node_b_status" -ne 0 || "$node_a_status" -ne 0 ]] ||
    [[ -s "$work_dir/node-b.err" || -s "$work_dir/node-a.err" ]] ||
    ! validate_node_b_transcript "$work_dir/node-b.out" ||
    ! validate_node_a_transcript "$work_dir/node-a.out"; then
    printf 'Action 17c-b collection evidence is malformed or incomplete.\n' >&2
    exit 97
fi

conclusion=$(derive_conclusion "$work_dir/node-a.out")
readonly conclusion
printf 'action_17c_b_diagnostic_conclusion=%s\n' "$conclusion"
printf 'action_17c_b_source_selection_diagnostic_accepted=true\n'

cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf 'action_17c_b_local_cleanup_complete=true\n'
