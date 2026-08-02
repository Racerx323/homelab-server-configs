#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=6f75baf2f1b5826ce5ac9453b84914f5caff39d83b669e26c1ee97d84e59eb2e
readonly inspector_name=diagnose-node-a-cutover-preflight-action16ao-a.sh
readonly -a singleton_prefixes=(
    hostname_status
    node_hostname
    architecture_status
    node_architecture
    ipv6_command_status
    ipv6_record_count
    systemctl_command_status
    caddy_type
    caddy_load_state
    caddy_active_state
    caddy_unit_file_state
    caddy_fragment_path
    caddy_dropin_paths
    type_directive_status
    type_directive_record_count
    ss_command_status
    tcp80_listener_count
)
readonly -a fixed_markers=(
    action_16ao_a_remote_reached=true
    peer_connections=false
    installed_helper_execution=false
    systemd_daemon_reload_performed=false
    service_mutations=false
    action_16ao_a_diagnostic_complete=true
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

evaluate_contract() {
    local output_file=$1
    local error_file=$2
    local ssh_status=$3
    local prefix marker ipv6_count type_count listener_count

    for marker in "${fixed_markers[@]}"; do
        [[ "$(grep -Fxc "$marker" "$output_file")" -eq 1 ]] || return 97
    done
    for prefix in "${singleton_prefixes[@]}"; do
        [[ "$(grep -c "^${prefix}=" "$output_file")" -eq 1 ]] || return 97
    done
    if grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=' \
        "$output_file" "$error_file"; then
        return 97
    fi
    if LC_ALL=C grep -n '[^[:print:][:space:]]' "$output_file" "$error_file" \
        >/dev/null; then
        return 97
    fi

    for prefix in \
        hostname_status architecture_status ipv6_command_status \
        systemctl_command_status type_directive_status ss_command_status; do
        grep -Eq "^${prefix}=[0-9]+$" "$output_file" || return 97
    done
    ipv6_count=$(sed -n 's/^ipv6_record_count=//p' "$output_file")
    type_count=$(sed -n 's/^type_directive_record_count=//p' "$output_file")
    listener_count=$(sed -n 's/^tcp80_listener_count=//p' "$output_file")
    [[ "$ipv6_count" =~ ^[0-9]+$ ]] || return 97
    [[ "$type_count" =~ ^[0-9]+$ ]] || return 97
    [[ "$listener_count" =~ ^[0-9]+$ ]] || return 97
    [[ "$(grep -c '^ipv6_record=' "$output_file" || true)" -eq "$ipv6_count" ]] ||
        return 97
    [[ "$(grep -c '^type_directive_record=' "$output_file" || true)" -eq "$type_count" ]] ||
        return 97
    [[ "$(grep -c '^tcp80_listener=' "$output_file" || true)" -eq "$listener_count" ]] ||
        return 97
    [[ "$ssh_status" -eq 0 ]] || return 97
    grep -Eq '^node_hostname=[A-Za-z0-9._-]+$' "$output_file" || return 97
    grep -Eq '^node_architecture=[A-Za-z0-9._-]+$' "$output_file" || return 97
    return 0
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "${#singleton_prefixes[@]}" -eq 17 ]]
    [[ "${#fixed_markers[@]}" -eq 6 ]]
    verify_inspector
    printf 'action_16ao_a_diagnostic_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action16ao-a-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    success="$contract_dir/success.out"
    error_file="$contract_dir/error"
    {
        printf '%s\n' "${fixed_markers[@]}"
        printf 'hostname_status=0\n'
        printf 'node_hostname=j1-svpihole0\n'
        printf 'architecture_status=0\n'
        printf 'node_architecture=arm64\n'
        printf 'ipv6_command_status=0\n'
        printf 'ipv6_record_count=1\n'
        printf 'ipv6_record=2: eth0 inet6 fd00::1/128 scope global\n'
        printf 'systemctl_command_status=0\n'
        printf 'caddy_type=notify\n'
        printf 'caddy_load_state=loaded\n'
        printf 'caddy_active_state=inactive\n'
        printf 'caddy_unit_file_state=masked\n'
        printf 'caddy_fragment_path=/lib/systemd/system/caddy.service\n'
        printf 'caddy_dropin_paths=/etc/systemd/system/caddy.service.d/override.conf\n'
        printf 'type_directive_status=0\n'
        printf 'type_directive_record_count=1\n'
        printf 'type_directive_record=/lib/systemd/system/caddy.service:25:Type=notify\n'
        printf 'ss_command_status=0\n'
        printf 'tcp80_listener_count=2\n'
        printf 'tcp80_listener=LISTEN 0 1024 0.0.0.0:80 0.0.0.0:* users:(("lighttpd",pid=1,fd=1))\n'
        printf 'tcp80_listener=LISTEN 0 1024 [::]:80 [::]:* users:(("lighttpd",pid=1,fd=2))\n'
    } >"$success"
    : >"$error_file"
    evaluate_contract "$success" "$error_file" 0

    duplicate="$contract_dir/duplicate.out"
    cp -- "$success" "$duplicate"
    printf 'caddy_type=notify\n' >>"$duplicate"
    if evaluate_contract "$duplicate" "$error_file" 0; then
        printf 'Duplicate Action 16ao-a evidence was accepted.\n' >&2
        exit 1
    fi
    inconsistent="$contract_dir/inconsistent.out"
    sed 's/tcp80_listener_count=2/tcp80_listener_count=1/' \
        "$success" >"$inconsistent"
    if evaluate_contract "$inconsistent" "$error_file" 0; then
        printf 'Inconsistent Action 16ao-a evidence was accepted.\n' >&2
        exit 1
    fi
    secret="$contract_dir/secret.out"
    cp -- "$success" "$secret"
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$secret"
    if evaluate_contract "$secret" "$error_file" 0; then
        printf 'Secret-bearing Action 16ao-a evidence was accepted.\n' >&2
        exit 1
    fi
    printf 'action_16ao_a_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_inspector
work_dir=$(mktemp -d /tmp/caddy-action16ao-a.XXXXXX)
readonly work_dir
readonly remote_output="$work_dir/remote.out"
readonly remote_error="$work_dir/remote.err"

cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

finish() {
    local status=$1

    cleanup
    trap - EXIT
    if [[ -e "$work_dir" || -L "$work_dir" ]]; then
        printf 'action_16ao_a_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16ao_a_local_cleanup_complete=true\n'
    exit "$status"
}

set +e
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias=pihole0.local.theama.co \
    -o StrictHostKeyChecking=yes \
    pi@10.1.0.53 \
    'sudo -n /bin/bash -s --' \
    <"$inspector" >"$remote_output" 2>"$remote_error"
ssh_status=$?
set -e

cat "$remote_output"
cat "$remote_error" >&2
printf 'ssh_exit_status=%s\n' "$ssh_status"
set +e
evaluate_contract "$remote_output" "$remote_error" "$ssh_status"
contract_status=$?
set -e
finish "$contract_status"
