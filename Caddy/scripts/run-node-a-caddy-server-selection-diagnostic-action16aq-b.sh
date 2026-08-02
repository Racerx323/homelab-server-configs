#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly diagnostic_sha256=28ad0167c7e44242540cb5194fc308da8474f378dbc714a9f17931388e6321c3
readonly diagnostic_name=diagnose-node-a-caddy-server-selection-action16aq-b.sh
readonly -a fixed_markers=(
    action_16aq_b_remote_reached=true
    runtime_metrics_counter_effect=true
    peer_connections=false
    installed_helper_execution=false
    systemd_daemon_reload_performed=false
    service_mutations=false
    configuration_mutations=false
    filesystem_mutations=false
    action_16aq_b_server_selection_diagnostic_complete=true
)
readonly -a singleton_prefixes=(
    node_hostname
    node_architecture
    command_record_count
    runtime_config_status
    server_summary_status
    server_summary_record_count
    known_metrics_before_status
    known_metrics_after_status
    unknown_metrics_before_status
    unknown_metrics_after_status
    probe_record_count
    known_metric_delta_record_count
    unknown_metric_delta_record_count
    server_selection_record
)

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly diagnostic="$script_dir/$diagnostic_name"

verify_artifact() {
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
    [[ "${#fields[@]}" -eq 5 ]] || return 97
    [[ "${fields[0]}" =~ ^[0-9]{3}$ ]] || return 97
    [[ -n "${fields[1]}" ]] || return 97
    [[ -n "${fields[2]}" ]] || return 97
    [[ "${fields[3]}" =~ ^[0-9]+$ ]] || return 97
    [[ "${fields[4]}" =~ ^[0-9]+$ ]] || return 97
}

validate_server_summaries() {
    local output_file=$1

    sed -n 's/^server_summary_record=//p' "$output_file" |
        jq -e -s '
            length > 0
            and all(.[];
                type == "object"
                and ((keys | sort) == ([
                    "exact_target",
                    "hostless_static_421",
                    "hosts",
                    "listen",
                    "server",
                    "wildcard_target"
                ] | sort))
                and (.server | test("^srv[0-9]+$"))
                and (.listen | type == "array")
                and (.hosts | type == "array")
                and (.exact_target | type == "boolean")
                and (.wildcard_target | type == "boolean")
                and (.hostless_static_421 | type == "boolean")
            )
        ' >/dev/null
}

validate_delta_records() {
    local prefix=$1
    local output_file=$2

    if grep "^${prefix}=" "$output_file" |
        grep -Ev \
            "^${prefix}=srv[0-9]+[|][A-Za-z0-9_.-]+[|](pihole0[.]local[.]theama[.]co|_other)[|][0-9]{3}[|][0-9]+([.][0-9]+)?$" \
            >/dev/null; then
        return 97
    fi
}

validate_selection_record() {
    local output_file=$1
    local record selected basis conclusive

    record=$(sed -n 's/^server_selection_record=//p' "$output_file")
    IFS='|' read -r selected basis conclusive <<<"$record"
    [[ "$selected" == unresolved || "$selected" =~ ^srv[0-9]+$ ]] ||
        return 97
    [[ "$basis" =~ ^[a-z0-9_]+$ ]] || return 97
    [[ "$conclusive" == true || "$conclusive" == false ]] || return 97
    if [[ "$conclusive" == true ]]; then
        [[ "$selected" =~ ^srv[0-9]+$ ]] || return 97
        [[ "$basis" == metrics_handler_delta ||
            "$basis" == exact_listener_control_plus_unhandled_200 ]] ||
            return 97
    else
        [[ "$selected" == unresolved ]] || return 97
        [[ "$basis" == insufficient_or_concurrent_evidence ]] || return 97
    fi
    return 0
}

evaluate_contract() {
    local output_file=$1
    local error_file=$2
    local ssh_status=$3
    local marker prefix

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
    grep -Fxq 'command_record_count=10' "$output_file" || return 97
    [[ "$(record_count command_status "$output_file")" -eq 10 ]] || return 97
    if grep '^command_status=' "$output_file" |
        grep -Ev '^command_status=[a-z0-9.-]+[|][0-9]+$' >/dev/null; then
        return 97
    fi

    for prefix in \
        runtime_config_status server_summary_status \
        known_metrics_before_status known_metrics_after_status \
        unknown_metrics_before_status unknown_metrics_after_status; do
        [[ "$(numeric_value "$prefix" "$output_file")" =~ ^[0-9]+$ ]] ||
            return 97
    done
    reconcile_records server_summary_record_count \
        server_summary_record "$output_file" || return 97
    reconcile_records known_metric_delta_record_count \
        known_metric_delta_record "$output_file" || return 97
    reconcile_records unknown_metric_delta_record_count \
        unknown_metric_delta_record "$output_file" || return 97
    validate_server_summaries "$output_file" || return 97
    validate_delta_records known_metric_delta_record "$output_file" ||
        return 97
    validate_delta_records unknown_metric_delta_record "$output_file" ||
        return 97

    grep -Fxq 'probe_record_count=2' "$output_file" || return 97
    [[ "$(record_count probe_record "$output_file")" -eq 2 ]] || return 97
    [[ "$(grep -c '^probe_record=known_control|' "$output_file")" -eq 1 ]] ||
        return 97
    [[ "$(grep -c '^probe_record=unknown_default|' "$output_file")" -eq 1 ]] ||
        return 97
    validate_probe_record known_control "$output_file" || return 97
    validate_probe_record unknown_default "$output_file" || return 97
    validate_selection_record "$output_file" || return 97
}

write_success_fixture() {
    local output_file=$1
    local command_name

    {
        printf '%s\n' "${fixed_markers[@]}"
        printf 'node_hostname=j1-svpihole0\n'
        printf 'node_architecture=arm64\n'
        printf 'command_record_count=10\n'
        for command_name in \
            awk curl cut dpkg grep hostname jq sed sort tail; do
            printf 'command_status=%s|0\n' "$command_name"
        done
        printf 'runtime_config_status=0\n'
        printf 'server_summary_status=0\n'
        printf 'server_summary_record_count=2\n'
        printf '%s\n' \
            'server_summary_record={"server":"srv0","listen":["10.1.0.53:443"],"exact_target":true,"wildcard_target":false,"hosts":["pihole0.local.theama.co"],"hostless_static_421":false}'
        printf '%s\n' \
            'server_summary_record={"server":"srv3","listen":[":443"],"exact_target":false,"wildcard_target":true,"hosts":[],"hostless_static_421":true}'
        printf 'known_metrics_before_status=0\n'
        printf 'known_metrics_after_status=0\n'
        printf 'unknown_metrics_before_status=0\n'
        printf 'unknown_metrics_after_status=0\n'
        printf 'probe_record_count=2\n'
        printf 'probe_record=known_control|0|200%%7C10.1.0.53%%7C2%%7C0%%7C0\n'
        printf 'probe_record=unknown_default|0|200%%7C10.1.0.53%%7C2%%7C0%%7C0\n'
        printf 'known_metric_delta_record_count=1\n'
        printf '%s\n' \
            'known_metric_delta_record=srv0|subroute|pihole0.local.theama.co|200|1'
        printf 'unknown_metric_delta_record_count=0\n'
        printf '%s\n' \
            'server_selection_record=srv0|exact_listener_control_plus_unhandled_200|true'
    } >"$output_file"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$diagnostic_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "${#fixed_markers[@]}" -eq 9 ]]
    [[ "${#singleton_prefixes[@]}" -eq 14 ]]
    verify_artifact
    printf 'action_16aq_b_server_selection_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action16aq-b-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    success="$contract_dir/success.out"
    error_file="$contract_dir/error"
    write_success_fixture "$success"
    : >"$error_file"
    evaluate_contract "$success" "$error_file" 0

    unresolved="$contract_dir/unresolved.out"
    sed \
        's/srv0|exact_listener_control_plus_unhandled_200|true/unresolved|insufficient_or_concurrent_evidence|false/' \
        "$success" >"$unresolved"
    evaluate_contract "$unresolved" "$error_file" 0

    duplicate="$contract_dir/duplicate.out"
    cp -- "$success" "$duplicate"
    printf '%s\n' "${fixed_markers[0]}" >>"$duplicate"
    if evaluate_contract "$duplicate" "$error_file" 0; then
        printf 'Duplicate Action 16aq-b evidence was accepted.\n' >&2
        exit 1
    fi

    inconsistent="$contract_dir/inconsistent.out"
    sed \
        's/known_metric_delta_record_count=1/known_metric_delta_record_count=2/' \
        "$success" >"$inconsistent"
    if evaluate_contract "$inconsistent" "$error_file" 0; then
        printf 'Count-inconsistent Action 16aq-b evidence was accepted.\n' >&2
        exit 1
    fi

    malformed="$contract_dir/malformed.out"
    sed 's/"exact_target":true/"exact_target":"true"/' \
        "$success" >"$malformed"
    if evaluate_contract "$malformed" "$error_file" 0; then
        printf 'Malformed Action 16aq-b summary was accepted.\n' >&2
        exit 1
    fi

    false_conclusive="$contract_dir/false-conclusive.out"
    sed \
        's/srv0|exact_listener_control_plus_unhandled_200|true/unresolved|metrics_handler_delta|true/' \
        "$success" >"$false_conclusive"
    if evaluate_contract "$false_conclusive" "$error_file" 0; then
        printf 'Inconsistent Action 16aq-b selection was accepted.\n' >&2
        exit 1
    fi

    secret="$contract_dir/secret.out"
    cp -- "$success" "$secret"
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$secret"
    if evaluate_contract "$secret" "$error_file" 0; then
        printf 'Secret-bearing Action 16aq-b evidence was accepted.\n' >&2
        exit 1
    fi

    if evaluate_contract "$success" "$error_file" 255; then
        printf 'Nonzero-SSH Action 16aq-b evidence was accepted.\n' >&2
        exit 1
    fi
    printf 'action_16aq_b_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_artifact
work_dir=$(mktemp -d /tmp/caddy-action16aq-b.XXXXXX)
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
        printf 'action_16aq_b_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16aq_b_local_cleanup_complete=true\n'
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
