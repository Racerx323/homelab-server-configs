#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly diagnostic_sha256=4a0b4371bbf8778cb98f217c0cd102b2f85b70aa16068c16899eb7575e5fa111
readonly diagnostic_name=diagnose-node-a-lighttpd-routing-action16aq-a.sh
readonly -a fixed_markers=(
    action_16aq_a_remote_reached=true
    peer_connections=false
    installed_helper_execution=false
    systemd_daemon_reload_performed=false
    service_mutations=false
    filesystem_mutations=false
    action_16aq_a_lighttpd_routing_diagnostic_complete=true
)
readonly -a singleton_prefixes=(
    node_hostname
    node_architecture
    command_record_count
    lighttpd_native_parse_status
    lighttpd_directive_record_count
    lighttpd_include_record_count
    lighttpd_enabled_record_count
    lighttpd_effective_print_status
    lighttpd_effective_record_count
    lighttpd_listener_record_count
    caddy_adapt_status
    adapted_route_status
    adapted_route_record_count
    runtime_config_status
    runtime_route_status
    runtime_route_record_count
    probe_record_count
    probe_header_record_count
)
readonly -a probe_labels=(
    unknown_default
    known_default
    known_sni_unknown_host
    unknown_sni_known_host
    ip_sni_unknown_host
)

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly diagnostic="$script_dir/$diagnostic_name"

verify_diagnostic() {
    [[ -f "$diagnostic" && ! -L "$diagnostic" ]]
    [[ "$(stat -c '%U:%G:%a' "$diagnostic")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$diagnostic" | awk '{ print $1 }')" == "$diagnostic_sha256" ]]
    bash -n "$diagnostic"
    "$diagnostic" --self-test >/dev/null
}

record_count() {
    local prefix=$1
    local output_file=$2

    grep -c "^${prefix}=" "$output_file" || true
}

numeric_value() {
    local prefix=$1
    local output_file=$2

    sed -n "s/^${prefix}=//p" "$output_file"
}

reconcile_records() {
    local count_prefix=$1
    local record_prefix=$2
    local output_file=$3
    local expected

    expected=$(numeric_value "$count_prefix" "$output_file")
    [[ "$expected" =~ ^[0-9]+$ ]] || return 97
    [[ "$(record_count "$record_prefix" "$output_file")" -eq "$expected" ]]
}

evaluate_contract() {
    local output_file=$1
    local error_file=$2
    local ssh_status=$3
    local marker prefix label

    [[ "$ssh_status" -eq 0 ]] || return 97
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

    grep -Fxq 'node_hostname=j1-svpihole0' "$output_file" || return 97
    grep -Fxq 'node_architecture=arm64' "$output_file" || return 97
    grep -Fxq 'command_record_count=15' "$output_file" || return 97
    [[ "$(record_count command_status "$output_file")" -eq 15 ]] || return 97
    if grep '^command_status=' "$output_file" |
        grep -Ev '^command_status=[a-z0-9.-]+\|[0-9]+$' >/dev/null; then
        return 97
    fi

    for prefix in \
        lighttpd_native_parse_status lighttpd_effective_print_status \
        caddy_adapt_status adapted_route_status runtime_config_status \
        runtime_route_status; do
        [[ "$(numeric_value "$prefix" "$output_file")" =~ ^[0-9]+$ ]] ||
            return 97
    done
    reconcile_records lighttpd_directive_record_count \
        lighttpd_directive_record "$output_file" || return 97
    reconcile_records lighttpd_include_record_count \
        lighttpd_include_record "$output_file" || return 97
    reconcile_records lighttpd_enabled_record_count \
        lighttpd_enabled_record "$output_file" || return 97
    reconcile_records lighttpd_effective_record_count \
        lighttpd_effective_record "$output_file" || return 97
    reconcile_records lighttpd_listener_record_count \
        lighttpd_listener_record "$output_file" || return 97
    reconcile_records adapted_route_record_count \
        adapted_route_record "$output_file" || return 97
    reconcile_records runtime_route_record_count \
        runtime_route_record "$output_file" || return 97
    reconcile_records probe_header_record_count \
        probe_header_record "$output_file" || return 97

    grep -Fxq 'probe_record_count=5' "$output_file" || return 97
    [[ "$(record_count probe_record "$output_file")" -eq 5 ]] || return 97
    for label in "${probe_labels[@]}"; do
        [[ "$(grep -c "^probe_record=${label}|" "$output_file")" -eq 1 ]] ||
            return 97
        grep -Eq \
            "^probe_record=${label}\\|[0-9]+\\|(missing|[0-9]{3}\\|[^|]*\\|[^|]*\\|[0-9]+\\|[0-9]+\\|.*)$" \
            "$output_file" || return 97
    done
    if grep '^probe_header_record=' "$output_file" |
        grep -Ev '^probe_header_record=[a-z0-9_]+\|.+'; then
        return 97
    fi
    if grep -E \
        '^(adapted|runtime)_route_record=' "$output_file" |
        sed 's/^[^=]*=//' |
        jq -e . >/dev/null; then
        :
    elif grep -Eq '^(adapted|runtime)_route_record=' "$output_file"; then
        return 97
    fi
    return 0
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$diagnostic_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "${#fixed_markers[@]}" -eq 7 ]]
    [[ "${#singleton_prefixes[@]}" -eq 18 ]]
    [[ "${#probe_labels[@]}" -eq 5 ]]
    verify_diagnostic
    printf 'action_16aq_a_lighttpd_routing_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action16aq-a-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    success="$contract_dir/success.out"
    error_file="$contract_dir/error"
    {
        printf '%s\n' "${fixed_markers[@]}"
        printf 'node_hostname=j1-svpihole0\n'
        printf 'node_architecture=arm64\n'
        printf 'command_record_count=15\n'
        for command_name in \
            awk caddy curl dpkg find grep hostname jq lighttpd readlink sed ss \
            stat systemctl tail; do
            printf 'command_status=%s|0\n' "$command_name"
        done
        printf 'lighttpd_native_parse_status=0\n'
        printf 'lighttpd_directive_record_count=1\n'
        printf 'lighttpd_directive_record=lighttpd.conf:1:server.port = 8080\n'
        printf 'lighttpd_include_record_count=0\n'
        printf 'lighttpd_enabled_record_count=0\n'
        printf 'lighttpd_effective_print_status=0\n'
        printf 'lighttpd_effective_record_count=0\n'
        printf 'lighttpd_listener_record_count=0\n'
        printf 'caddy_adapt_status=0\n'
        printf 'adapted_route_status=0\n'
        printf 'adapted_route_record_count=1\n'
        printf '%s\n' \
            'adapted_route_record={"server":"srv0","hosts":["example.test"]}'
        printf 'runtime_config_status=0\n'
        printf 'runtime_route_status=0\n'
        printf 'runtime_route_record_count=1\n'
        printf '%s\n' \
            'runtime_route_record={"server":"srv0","hosts":["example.test"]}'
        printf 'probe_record_count=5\n'
        for label in "${probe_labels[@]}"; do
            printf 'probe_record=%s|0|421|10.1.0.53|2|0|0|text/plain\n' \
                "$label"
        done
        printf 'probe_header_record_count=0\n'
    } >"$success"
    : >"$error_file"
    evaluate_contract "$success" "$error_file" 0

    duplicate="$contract_dir/duplicate.out"
    cp -- "$success" "$duplicate"
    printf '%s\n' "${fixed_markers[0]}" >>"$duplicate"
    if evaluate_contract "$duplicate" "$error_file" 0; then
        printf 'Duplicate Action 16aq-a evidence was accepted.\n' >&2
        exit 1
    fi
    inconsistent="$contract_dir/inconsistent.out"
    sed 's/lighttpd_directive_record_count=1/lighttpd_directive_record_count=2/' \
        "$success" >"$inconsistent"
    if evaluate_contract "$inconsistent" "$error_file" 0; then
        printf 'Count-inconsistent Action 16aq-a evidence was accepted.\n' >&2
        exit 1
    fi
    missing_probe="$contract_dir/missing-probe.out"
    grep -v '^probe_record=unknown_default|' "$success" >"$missing_probe"
    if evaluate_contract "$missing_probe" "$error_file" 0; then
        printf 'Missing-probe Action 16aq-a evidence was accepted.\n' >&2
        exit 1
    fi
    secret="$contract_dir/secret.out"
    cp -- "$success" "$secret"
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$secret"
    if evaluate_contract "$secret" "$error_file" 0; then
        printf 'Secret-bearing Action 16aq-a evidence was accepted.\n' >&2
        exit 1
    fi
    if evaluate_contract "$success" "$error_file" 255; then
        printf 'Nonzero-SSH Action 16aq-a evidence was accepted.\n' >&2
        exit 1
    fi
    printf 'action_16aq_a_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_diagnostic
work_dir=$(mktemp -d /tmp/caddy-action16aq-a.XXXXXX)
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
        printf 'action_16aq_a_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16aq_a_local_cleanup_complete=true\n'
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
    <"$diagnostic" >"$remote_output" 2>"$remote_error"
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
