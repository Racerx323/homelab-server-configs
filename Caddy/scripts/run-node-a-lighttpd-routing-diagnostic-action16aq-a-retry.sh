#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly diagnostic_sha256=4a0b4371bbf8778cb98f217c0cd102b2f85b70aa16068c16899eb7575e5fa111
readonly diagnostic_name=diagnose-node-a-lighttpd-routing-action16aq-a.sh
readonly extension_sha256=e4f42a453851025ffc0bd1cd6b0a6f249ca6eda41bf5cef7aca039673baa8bed
readonly extension_name=extend-node-a-lighttpd-routing-action16aq-a-retry.sh
readonly -a fixed_markers=(
    action_16aq_a_remote_reached=true
    peer_connections=false
    installed_helper_execution=false
    systemd_daemon_reload_performed=false
    service_mutations=false
    filesystem_mutations=false
    action_16aq_a_lighttpd_routing_diagnostic_complete=true
    action_16aq_a_retry_static_response_extension_complete=true
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
    static_response_summary_schema
    adapted_static_response_status
    adapted_static_response_record_count
    runtime_static_response_status
    runtime_static_response_record_count
    static_response_summaries_equal
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
readonly extension="$script_dir/$extension_name"

verify_artifacts() {
    [[ -f "$diagnostic" && ! -L "$diagnostic" ]]
    [[ "$(stat -c '%U:%G:%a' "$diagnostic")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$diagnostic" | awk '{ print $1 }')" == "$diagnostic_sha256" ]]
    bash -n "$diagnostic"
    "$diagnostic" --self-test >/dev/null

    [[ -f "$extension" && ! -L "$extension" ]]
    [[ "$(stat -c '%U:%G:%a' "$extension")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$extension" | awk '{ print $1 }')" == "$extension_sha256" ]]
    bash -n "$extension"
    "$extension" --extension-self-test >/dev/null
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

validate_probe_record() {
    local label=$1
    local output_file=$2
    local line record observed_label remainder curl_status metadata decoded
    local -a fields

    line=$(grep "^probe_record=${label}|" "$output_file")
    record=${line#probe_record=}
    observed_label=${record%%|*}
    remainder=${record#*|}
    curl_status=${remainder%%|*}
    metadata=${remainder#*|}

    [[ "$observed_label" == "$label" ]] || return 97
    [[ "$curl_status" =~ ^[0-9]+$ ]] || return 97
    if [[ "$metadata" == missing ]]; then
        return 0
    fi
    [[ "$metadata" != *"|"* ]] || return 97
    decoded=${metadata//%7C/$'\n'}
    mapfile -t fields <<<"$decoded"
    [[ "${#fields[@]}" -eq 6 ]] || return 97
    [[ "${fields[0]}" =~ ^[0-9]{3}$ ]] || return 97
    [[ -n "${fields[1]}" ]] || return 97
    [[ -n "${fields[2]}" ]] || return 97
    [[ "${fields[3]}" =~ ^[0-9]+$ ]] || return 97
    [[ "${fields[4]}" =~ ^[0-9]+$ ]] || return 97
}

validate_static_response_records() {
    local record_prefix=$1
    local output_file=$2

    sed -n "s/^${record_prefix}=//p" "$output_file" |
        jq -e -s '
            length > 0
            and all(.[];
                type == "object"
                and ((keys | sort) == ([
                    "body_is_421",
                    "body_length",
                    "effective_status_code",
                    "handler_index",
                    "hosts",
                    "listen",
                    "route_index",
                    "server",
                    "status_code_present"
                ] | sort))
                and (.server | type == "string")
                and (.route_index | type == "number")
                and (.handler_index | type == "number")
                and (.listen | type == "array")
                and (.hosts | type == "array")
                and (.status_code_present | type == "boolean")
                and (.effective_status_code | type == "number")
                and (.body_length | type == "number")
                and (.body_is_421 | type == "boolean")
            )
            and any(.[];
                (.listen | index(":443")) != null
                and (.hosts | length) == 0
            )
        ' >/dev/null
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
        runtime_route_status adapted_static_response_status \
        runtime_static_response_status; do
        [[ "$(numeric_value "$prefix" "$output_file")" =~ ^[0-9]+$ ]] ||
            return 97
    done
    grep -Fxq 'static_response_summary_schema=1' "$output_file" || return 97
    grep -Eq '^static_response_summaries_equal=(true|false)$' \
        "$output_file" || return 97

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
    reconcile_records adapted_static_response_record_count \
        adapted_static_response_record "$output_file" || return 97
    reconcile_records runtime_static_response_record_count \
        runtime_static_response_record "$output_file" || return 97

    grep -Fxq 'probe_record_count=5' "$output_file" || return 97
    [[ "$(record_count probe_record "$output_file")" -eq 5 ]] || return 97
    for label in "${probe_labels[@]}"; do
        [[ "$(grep -c "^probe_record=${label}|" "$output_file")" -eq 1 ]] ||
            return 97
        validate_probe_record "$label" "$output_file" || return 97
    done
    if grep '^probe_header_record=' "$output_file" |
        grep -Ev '^probe_header_record=[a-z0-9_]+\|.+'; then
        return 97
    fi

    if sed -n -E \
        's/^(adapted|runtime)_route_record=//p' "$output_file" |
        jq -e . >/dev/null; then
        :
    elif grep -Eq '^(adapted|runtime)_route_record=' "$output_file"; then
        return 97
    fi
    validate_static_response_records adapted_static_response_record \
        "$output_file" || return 97
    validate_static_response_records runtime_static_response_record \
        "$output_file" || return 97
    return 0
}

write_success_fixture() {
    local output_file=$1
    local command_name label

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
            'adapted_route_record={"server":"srv3","hosts":[]}'
        printf 'runtime_config_status=0\n'
        printf 'runtime_route_status=0\n'
        printf 'runtime_route_record_count=1\n'
        printf '%s\n' \
            'runtime_route_record={"server":"srv3","hosts":[]}'
        printf 'probe_record_count=5\n'
        for label in "${probe_labels[@]}"; do
            printf 'probe_record=%s|0|421%%7C10.1.0.53%%7C2%%7C0%%7C0%%7Ctext/plain\n' \
                "$label"
        done
        printf 'probe_header_record_count=0\n'
        printf 'static_response_summary_schema=1\n'
        printf 'adapted_static_response_status=0\n'
        printf 'adapted_static_response_record_count=1\n'
        printf '%s\n' \
            'adapted_static_response_record={"server":"srv3","route_index":0,"handler_index":0,"listen":[":443"],"hosts":[],"status_code_present":false,"effective_status_code":200,"body_length":3,"body_is_421":true}'
        printf 'runtime_static_response_status=0\n'
        printf 'runtime_static_response_record_count=1\n'
        printf '%s\n' \
            'runtime_static_response_record={"server":"srv3","route_index":0,"handler_index":0,"listen":[":443"],"hosts":[],"status_code_present":false,"effective_status_code":200,"body_length":3,"body_is_421":true}'
        printf 'static_response_summaries_equal=true\n'
    } >"$output_file"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$diagnostic_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$extension_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "${#fixed_markers[@]}" -eq 8 ]]
    [[ "${#singleton_prefixes[@]}" -eq 24 ]]
    [[ "${#probe_labels[@]}" -eq 5 ]]
    verify_artifacts
    printf '%s\n' \
        'action_16aq_a_retry_lighttpd_routing_runner_self_test_complete=true'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action16aq-a-retry-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    success="$contract_dir/success.out"
    error_file="$contract_dir/error"
    write_success_fixture "$success"
    : >"$error_file"
    evaluate_contract "$success" "$error_file" 0

    duplicate="$contract_dir/duplicate.out"
    cp -- "$success" "$duplicate"
    printf '%s\n' "${fixed_markers[0]}" >>"$duplicate"
    if evaluate_contract "$duplicate" "$error_file" 0; then
        printf 'Duplicate retry evidence was accepted.\n' >&2
        exit 1
    fi

    literal_probe="$contract_dir/literal-probe.out"
    sed \
        's/unknown_default|0|421%7C10.1.0.53%7C2%7C0%7C0%7Ctext\/plain/unknown_default|0|421|10.1.0.53|2|0|0|text\/plain/' \
        "$success" >"$literal_probe"
    if evaluate_contract "$literal_probe" "$error_file" 0; then
        printf 'Literal-delimiter retry evidence was accepted.\n' >&2
        exit 1
    fi

    inconsistent="$contract_dir/inconsistent.out"
    sed \
        's/adapted_static_response_record_count=1/adapted_static_response_record_count=2/' \
        "$success" >"$inconsistent"
    if evaluate_contract "$inconsistent" "$error_file" 0; then
        printf 'Count-inconsistent retry evidence was accepted.\n' >&2
        exit 1
    fi

    malformed="$contract_dir/malformed.out"
    sed 's/"body_is_421":true/"body_is_421":"true"/' \
        "$success" >"$malformed"
    if evaluate_contract "$malformed" "$error_file" 0; then
        printf 'Malformed static-response evidence was accepted.\n' >&2
        exit 1
    fi

    secret="$contract_dir/secret.out"
    cp -- "$success" "$secret"
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$secret"
    if evaluate_contract "$secret" "$error_file" 0; then
        printf 'Secret-bearing retry evidence was accepted.\n' >&2
        exit 1
    fi

    if evaluate_contract "$success" "$error_file" 255; then
        printf 'Nonzero-SSH retry evidence was accepted.\n' >&2
        exit 1
    fi
    printf 'action_16aq_a_retry_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_artifacts
work_dir=$(mktemp -d /tmp/caddy-action16aq-a-retry.XXXXXX)
readonly work_dir
readonly remote_payload="$work_dir/remote-payload.sh"
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
        printf 'action_16aq_a_retry_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16aq_a_retry_local_cleanup_complete=true\n'
    exit "$status"
}

cat "$diagnostic" "$extension" >"$remote_payload"
chmod 0600 "$remote_payload"

set +e
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias=pihole0.local.theama.co \
    -o StrictHostKeyChecking=yes \
    pi@10.1.0.53 \
    'sudo -n /bin/bash -s --' \
    <"$remote_payload" >"$remote_output" 2>"$remote_error"
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
