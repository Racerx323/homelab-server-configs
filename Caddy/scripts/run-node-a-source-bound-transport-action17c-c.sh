#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly validator_sha256=a7da9a9190595e17f8e563c25845648cfe062faed554fde7e8cdcf56059c27dc
readonly inspector_sha256=37e5390fb132c77002b468d9dfabfc579d5bb03f1da44f60802c448df3a35111
readonly template_sha256=f7e1e481b4cc0ab1e5f0b503a1f90fa4d42a76b3e68c1cdd5c48f2e9736be976
readonly renderer_sha256=36c048b75f865ab31a8f8d18a24d09b3bad0610355e752ea7bbe3ef9593eb5f3
readonly node_a_host_alias=pihole0.local.theama.co
readonly node_a_target=pi@10.1.0.53
readonly node_b_host_alias=pihole00.local.theama.co
readonly node_b_target=pi@10.1.0.54

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly validator="$script_dir/validate-sync-ssh-source-bound.sh"
readonly inspector="$script_dir/inspect-node-b-restricted-transport-state-action17c.sh"
readonly template="$caddy_root/templates/lsyncd-caddy-source-bound.lua.in"
readonly renderer="$script_dir/render-source-bound-sync-config-action17c-c.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_artifact() {
    local path=$1
    local expected_hash=$2
    local expected_mode=$3

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(stat -c '%U:%G:%a' "$path")" == "aaron:aaron:$expected_mode" ]]
    [[ "$(file_hash "$path")" == "$expected_hash" ]]
}

require_one() {
    local value=$1
    local transcript=$2

    [[ "$(grep -Fxc "$value" "$transcript")" -eq 1 ]]
}

extract_digest() {
    local transcript=$1
    local record

    [[ "$(grep -Ec '^node_b_state_digest=[0-9a-f]{64}$' \
        "$transcript")" -eq 1 ]]
    record=$(grep -E '^node_b_state_digest=[0-9a-f]{64}$' "$transcript")
    printf '%s\n' "${record#*=}"
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
        require_one "$marker" "$transcript"
    done
    extract_digest "$transcript" >/dev/null
}

validate_node_a() {
    local transcript=$1
    local marker

    for marker in \
        source_bound_ssh_configuration_valid=true \
        source_bound_direct_ssh_reached_forced_receiver=true \
        source_bound_rsync_dry_run=true \
        node_relevant_state_unchanged=true \
        release_payload_transferred=false; do
        require_one "$marker" "$transcript"
    done
    [[ "$(grep -Fxc \
        'Source-bound synchronization SSH validation passed for pihole00.local.theama.co via fd36:5aa8:6971:1::53.' \
        "$transcript")" -eq 1 ]]
}

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$@"
}

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

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$validator_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$template_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$renderer_sha256" =~ ^[0-9a-f]{64}$ ]]
    verify_artifact "$validator" "$validator_sha256" 755
    verify_artifact "$inspector" "$inspector_sha256" 755
    verify_artifact "$template" "$template_sha256" 644
    verify_artifact "$renderer" "$renderer_sha256" 755
    bash -n "$validator" "$inspector"
    "$validator" --self-test >/dev/null
    "$inspector" --self-test >/dev/null
    "$renderer" --self-test >/dev/null
    grep -Fq 'BindAddress = "@NODE_IPV6@"' "$template"
    grep -Fq 'AddressFamily = "inet6"' "$template"
    grep -Fq 'HostKeyAlias = "@PEER_FQDN@"' "$template"
    printf 'action_17c_c_source_binding_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action17c-c-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    printf '%s\n' \
        source_bound_ssh_configuration_valid=true \
        source_bound_direct_ssh_reached_forced_receiver=true \
        source_bound_rsync_dry_run=true \
        node_relevant_state_unchanged=true \
        release_payload_transferred=false \
        'Source-bound synchronization SSH validation passed for pihole00.local.theama.co via fd36:5aa8:6971:1::53.' \
        >"$contract_dir/node-a"
    validate_node_a "$contract_dir/node-a"
    printf 'action_17c_c_source_binding_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_artifact "$validator" "$validator_sha256" 755
verify_artifact "$inspector" "$inspector_sha256" 755
verify_artifact "$template" "$template_sha256" 644
verify_artifact "$renderer" "$renderer_sha256" 755
bash -n "$validator" "$inspector"
"$validator" --self-test >/dev/null
"$inspector" --self-test >/dev/null
"$renderer" --self-test >/dev/null

work_dir=$(mktemp -d /tmp/caddy-action17c-c.XXXXXX)
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

node_b_before_status=0
node_a_status=0
node_b_after_status=0
run_remote \
    "$node_b_host_alias" "$node_b_target" \
    'sudo -n /bin/bash -s --' "$inspector" \
    "$work_dir/node-b-before.out" "$work_dir/node-b-before.err" \
    node_b_before_status
run_remote \
    "$node_a_host_alias" "$node_a_target" \
    'sudo -n /usr/sbin/runuser -u caddy-sync -- /bin/bash -s -- --connect' \
    "$validator" "$work_dir/node-a.out" "$work_dir/node-a.err" node_a_status
run_remote \
    "$node_b_host_alias" "$node_b_target" \
    'sudo -n /bin/bash -s --' "$inspector" \
    "$work_dir/node-b-after.out" "$work_dir/node-b-after.err" \
    node_b_after_status

cat "$work_dir/node-a.out"
cat "$work_dir/node-b-before.err" >&2
cat "$work_dir/node-a.err" >&2
cat "$work_dir/node-b-after.err" >&2
printf 'node_b_before_ssh_status=%s\n' "$node_b_before_status"
printf 'node_a_source_bound_ssh_status=%s\n' "$node_a_status"
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
    printf 'Action 17c-c source-bound transport evidence is incomplete.\n' >&2
    exit 97
fi

before_digest=$(extract_digest "$work_dir/node-b-before.out")
after_digest=$(extract_digest "$work_dir/node-b-after.out")
[[ "$before_digest" == "$after_digest" ]]
printf 'node_b_before_state_digest=%s\n' "$before_digest"
printf 'node_b_after_state_digest=%s\n' "$after_digest"
printf 'node_b_protected_state_unchanged=true\n'
printf 'action_17c_c_source_bound_transport_accepted=true\n'

cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf 'action_17c_c_local_cleanup_complete=true\n'
