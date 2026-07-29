#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=43fb0866dd95347ff720e8fdccb567b4cb9cb7b332ac87a79ff993b4e45c13d8
readonly inspector_name=diagnose-caddy-validation-provenance-action16ap-b.sh
readonly -a singleton_prefixes=(
    diagnostic_node
    node_hostname
    node_architecture
    caddy_binary_path
    caddy_binary_sha256
    caddy_version_status
    caddy_version
    caddy_package
    environment_metadata
    environment_sha256
    current_link_target
    current_release
    current_revision
    caddyfile_sha256
    config_tree_sha256
    unit_property_record_count
    validation_status_bare
    validation_record_count_bare
    environment_source_status
    environment_value_count
    validation_status_environment
    validation_record_count_environment
)
readonly -a fixed_markers=(
    action_16ap_b_remote_reached=true
    peer_connections=false
    installed_helper_execution=false
    systemd_daemon_reload_performed=false
    service_mutations=false
    filesystem_mutations=false
    action_16ap_b_validation_provenance_complete=true
)
readonly -a expected_unit_properties=(
    LoadState
    ActiveState
    SubState
    UnitFileState
    User
    Group
    EnvironmentFiles
    ExecStart
    FragmentPath
    DropInPaths
)
readonly -a expected_environment_names=(
    NODE_ROLE
    NODE_FQDN
    NODE_IPV4
    NODE_IPV6
    CADDY_CONFIG_ROOT
)

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly inspector="$script_dir/$inspector_name"

verify_inspector() {
    [[ -f "$inspector" && ! -L "$inspector" ]]
    [[ "$(stat -c '%U:%G:%a' "$inspector")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$inspector" | awk '{ print $1 }')" == "$inspector_sha256" ]]
    bash -n "$inspector"
    "$inspector" --self-test >/dev/null
}

record_count() {
    local prefix=$1
    local output_file=$2

    grep -c "^${prefix}=" "$output_file" || true
}

evaluate_node_contract() {
    local output_file=$1
    local error_file=$2
    local ssh_status=$3
    local expected_node=$4
    local expected_hostname=$5
    local marker prefix property variable_name mode count status
    local total_validation_records=0

    [[ "$ssh_status" -eq 0 ]] || return 97
    [[ ! -s "$error_file" ]] || return 97
    for marker in "${fixed_markers[@]}"; do
        [[ "$(grep -Fxc "$marker" "$output_file")" -eq 1 ]] || return 97
    done
    for prefix in "${singleton_prefixes[@]}"; do
        [[ "$(record_count "$prefix" "$output_file")" -eq 1 ]] || return 97
    done
    if grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=' \
        "$output_file" "$error_file"; then
        return 97
    fi
    if LC_ALL=C grep -n '[^[:print:][:space:]]' \
        "$output_file" "$error_file" >/dev/null; then
        return 97
    fi

    grep -Fxq "diagnostic_node=$expected_node" "$output_file" || return 97
    grep -Fxq "node_hostname=$expected_hostname" "$output_file" || return 97
    grep -Eq '^node_architecture=[A-Za-z0-9._-]+$' "$output_file" || return 97
    grep -Eq '^caddy_binary_path=/[^[:space:]]+$' "$output_file" || return 97
    grep -Eq '^caddy_binary_sha256=([0-9a-f]{64}|unavailable)$' \
        "$output_file" || return 97
    grep -Eq '^caddy_version_status=[0-9]+$' "$output_file" || return 97
    grep -Eq '^caddy_package=install ok installed\|caddy\|[^|]+\|[^|]+$' \
        "$output_file" || return 97
    grep -Eq '^environment_sha256=([0-9a-f]{64}|unavailable)$' \
        "$output_file" || return 97
    grep -Eq '^caddyfile_sha256=([0-9a-f]{64}|unavailable)$' \
        "$output_file" || return 97
    grep -Eq '^config_tree_sha256=([0-9a-f]{64}|unavailable)$' \
        "$output_file" || return 97
    grep -Eq '^environment_source_status=[0-9]+$' "$output_file" || return 97

    count=$(sed -n 's/^unit_property_record_count=//p' "$output_file")
    [[ "$count" =~ ^[0-9]+$ ]] || return 97
    [[ "$count" -eq "${#expected_unit_properties[@]}" ]] || return 97
    [[ "$(record_count unit_property_record "$output_file")" -eq "$count" ]] ||
        return 97
    for property in "${expected_unit_properties[@]}"; do
        [[ "$(grep -c "^unit_property_record=${property}|" \
            "$output_file")" -eq 1 ]] || return 97
    done

    count=$(sed -n 's/^environment_value_count=//p' "$output_file")
    [[ "$count" -eq "${#expected_environment_names[@]}" ]] || return 97
    [[ "$(record_count environment_value "$output_file")" -eq "$count" ]] ||
        return 97
    for variable_name in "${expected_environment_names[@]}"; do
        [[ "$(grep -c "^environment_value=${variable_name}|" \
            "$output_file")" -eq 1 ]] || return 97
    done

    for mode in bare environment; do
        status=$(sed -n "s/^validation_status_${mode}=//p" "$output_file")
        [[ "$status" =~ ^([0-9]+|not_applicable)$ ]] || return 97
        count=$(sed -n \
            "s/^validation_record_count_${mode}=//p" "$output_file")
        [[ "$count" =~ ^[0-9]+$ ]] || return 97
        [[ "$count" -le 40 ]] || return 97
        [[ "$(grep -c "^validation_output_record=${mode}|" \
            "$output_file" || true)" -eq "$count" ]] || return 97
        total_validation_records=$((total_validation_records + count))
    done
    [[ "$(record_count validation_output_record "$output_file")" -eq "$total_validation_records" ]] || return 97
    return 0
}

emit_synthetic_node() {
    local node=$1
    local hostname=$2
    local property variable_name

    printf '%s\n' "${fixed_markers[@]}"
    printf 'diagnostic_node=%s\n' "$node"
    printf 'node_hostname=%s\n' "$hostname"
    printf 'node_architecture=arm64\n'
    printf 'caddy_binary_path=/usr/bin/caddy\n'
    printf 'caddy_binary_sha256=%064d\n' 1
    printf 'caddy_version_status=0\n'
    printf 'caddy_version=v2.11.4\n'
    printf 'caddy_package=install ok installed|caddy|2.11.4|arm64\n'
    printf 'environment_metadata=root:caddy-tls:640:1:1:1\n'
    printf 'environment_sha256=%064d\n' 2
    printf 'current_link_target=/etc/caddy/releases/example\n'
    printf 'current_release=/etc/caddy/releases/example\n'
    printf 'current_revision=example\n'
    printf 'caddyfile_sha256=%064d\n' 3
    printf 'config_tree_sha256=%064d\n' 4
    printf 'unit_property_record_count=10\n'
    for property in "${expected_unit_properties[@]}"; do
        printf 'unit_property_record=%s|example\n' "$property"
    done
    printf 'validation_status_bare=1\n'
    printf 'validation_record_count_bare=1\n'
    printf 'validation_output_record=bare|Error: empty node address\n'
    printf 'environment_source_status=0\n'
    printf 'environment_value_count=5\n'
    for variable_name in "${expected_environment_names[@]}"; do
        printf 'environment_value=%s|example\n' "$variable_name"
    done
    printf 'validation_status_environment=0\n'
    printf 'validation_record_count_environment=1\n'
    printf 'validation_output_record=environment|Valid configuration\n'
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "${#singleton_prefixes[@]}" -eq 22 ]]
    [[ "${#fixed_markers[@]}" -eq 7 ]]
    [[ "${#expected_unit_properties[@]}" -eq 10 ]]
    [[ "${#expected_environment_names[@]}" -eq 5 ]]
    verify_inspector
    printf 'action_16ap_b_validation_provenance_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action16ap-b-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    node_a="$contract_dir/node-a.out"
    node_b="$contract_dir/node-b.out"
    error_file="$contract_dir/error"
    emit_synthetic_node node-a j1-svpihole0 >"$node_a"
    emit_synthetic_node node-b j1-svpihole00 >"$node_b"
    : >"$error_file"
    evaluate_node_contract "$node_a" "$error_file" 0 \
        node-a j1-svpihole0
    evaluate_node_contract "$node_b" "$error_file" 0 \
        node-b j1-svpihole00

    duplicate="$contract_dir/duplicate.out"
    cp -- "$node_a" "$duplicate"
    printf 'validation_status_environment=0\n' >>"$duplicate"
    if evaluate_node_contract "$duplicate" "$error_file" 0 \
        node-a j1-svpihole0; then
        printf 'Duplicate Action 16ap-b evidence was accepted.\n' >&2
        exit 1
    fi
    inconsistent="$contract_dir/inconsistent.out"
    sed 's/unit_property_record_count=10/unit_property_record_count=9/' \
        "$node_a" >"$inconsistent"
    if evaluate_node_contract "$inconsistent" "$error_file" 0 \
        node-a j1-svpihole0; then
        printf 'Inconsistent Action 16ap-b evidence was accepted.\n' >&2
        exit 1
    fi
    secret="$contract_dir/secret.out"
    cp -- "$node_a" "$secret"
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$secret"
    if evaluate_node_contract "$secret" "$error_file" 0 \
        node-a j1-svpihole0; then
        printf 'Secret-bearing Action 16ap-b evidence was accepted.\n' >&2
        exit 1
    fi
    if evaluate_node_contract "$node_a" "$error_file" 255 \
        node-a j1-svpihole0; then
        printf 'Nonzero-SSH Action 16ap-b evidence was accepted.\n' >&2
        exit 1
    fi
    printf 'action_16ap_b_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_inspector
work_dir=$(mktemp -d /tmp/caddy-action16ap-b.XXXXXX)
readonly work_dir
readonly node_a_output="$work_dir/node-a.out"
readonly node_a_error="$work_dir/node-a.err"
readonly node_b_output="$work_dir/node-b.out"
readonly node_b_error="$work_dir/node-b.err"

cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

finish() {
    local status=$1

    cleanup
    trap - EXIT
    if [[ -e "$work_dir" || -L "$work_dir" ]]; then
        printf 'action_16ap_b_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16ap_b_local_cleanup_complete=true\n'
    exit "$status"
}

set +e
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias=pihole0.local.theama.co \
    -o StrictHostKeyChecking=yes \
    pi@10.1.0.53 \
    'sudo -n /bin/bash -s -- node-a' \
    <"$inspector" >"$node_a_output" 2>"$node_a_error"
node_a_ssh_status=$?
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias=pihole00.local.theama.co \
    -o StrictHostKeyChecking=yes \
    pi@10.1.0.54 \
    'sudo -n /bin/bash -s -- node-b' \
    <"$inspector" >"$node_b_output" 2>"$node_b_error"
node_b_ssh_status=$?
set -e

printf 'action_16ap_b_node_a_output_begin=true\n'
cat "$node_a_output"
printf 'action_16ap_b_node_a_output_end=true\n'
cat "$node_a_error" >&2
printf 'node_a_ssh_exit_status=%s\n' "$node_a_ssh_status"
printf 'action_16ap_b_node_b_output_begin=true\n'
cat "$node_b_output"
printf 'action_16ap_b_node_b_output_end=true\n'
cat "$node_b_error" >&2
printf 'node_b_ssh_exit_status=%s\n' "$node_b_ssh_status"

set +e
evaluate_node_contract "$node_a_output" "$node_a_error" \
    "$node_a_ssh_status" node-a j1-svpihole0
node_a_contract_status=$?
evaluate_node_contract "$node_b_output" "$node_b_error" \
    "$node_b_ssh_status" node-b j1-svpihole00
node_b_contract_status=$?
set -e
if [[ "$node_a_contract_status" -ne 0 ||
    "$node_b_contract_status" -ne 0 ]]; then
    finish 97
fi
printf 'action_16ap_b_comparison_complete=true\n'
finish 0
