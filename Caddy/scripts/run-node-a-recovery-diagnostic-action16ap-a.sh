#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=d4402abfab7a19f8b8ec3eec83b55f71db0981a6cc6ad5db41aa656e46121a77
readonly inspector_name=diagnose-node-a-recovery-state-action16ap-a.sh
readonly -a singleton_prefixes=(
    node_hostname
    node_architecture
    systemd_version
    service_record_count
    path_record_count
    lighttpd_record_count
    caddy_validate_status
    caddy_tree_sha256
    keepalived_tree_sha256
    listener_record_count
    process_record_count
    health_record_count
    journal_record_count
)
readonly -a fixed_markers=(
    action_16ap_a_remote_reached=true
    peer_connections=false
    installed_helper_execution=false
    systemd_daemon_reload_performed=false
    service_mutations=false
    filesystem_mutations=false
    action_16ap_a_recovery_diagnostic_complete=true
)
readonly -a expected_units=(
    lighttpd.service
    caddy.service
    caddy-api.service
    lsyncd.service
    caddy-lsyncd.service
    keepalived.service
)
readonly -a expected_paths=(
    /etc/lighttpd
    /etc/.lighttpd-pre-action16ap
    /etc/.lighttpd-caddy-action16ap
    /etc/.lighttpd-caddy-action16ap.failed
    /var/tmp/caddy-ha-lighttpd-node-a-action16ab
    /etc/caddy/current
    /etc/systemd/system/caddy.service
    /lib/systemd/system/caddy.service
    /etc/systemd/system/caddy.service.d/override.conf
    /etc/keepalived/conf.d/caddy-ha.conf
)
readonly -a expected_lighttpd_roots=(
    /etc/lighttpd
    /etc/.lighttpd-pre-action16ap
    /etc/.lighttpd-caddy-action16ap
    /etc/.lighttpd-caddy-action16ap.failed
    /var/tmp/caddy-ha-lighttpd-node-a-action16ab
)
readonly -a expected_health_names=(
    backend
    frontend_http
    localhost_https
    management_ipv4
    management_ipv6
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

evaluate_contract() {
    local output_file=$1
    local error_file=$2
    local ssh_status=$3
    local marker prefix unit target root health_name
    local service_count path_count lighttpd_count listener_count process_count
    local health_count journal_count include_total

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

    grep -Eq '^node_hostname=[A-Za-z0-9._-]+$' "$output_file" || return 97
    grep -Eq '^node_architecture=[A-Za-z0-9._-]+$' "$output_file" || return 97
    grep -Eq '^systemd_version=systemd [0-9]+' "$output_file" || return 97
    grep -Eq '^caddy_validate_status=([0-9]+|not_applicable)$' \
        "$output_file" || return 97
    grep -Eq '^caddy_tree_sha256=([0-9a-f]{64}|unavailable)$' \
        "$output_file" || return 97
    grep -Eq '^keepalived_tree_sha256=([0-9a-f]{64}|unavailable)$' \
        "$output_file" || return 97

    service_count=$(sed -n 's/^service_record_count=//p' "$output_file")
    path_count=$(sed -n 's/^path_record_count=//p' "$output_file")
    lighttpd_count=$(sed -n 's/^lighttpd_record_count=//p' "$output_file")
    listener_count=$(sed -n 's/^listener_record_count=//p' "$output_file")
    process_count=$(sed -n 's/^process_record_count=//p' "$output_file")
    health_count=$(sed -n 's/^health_record_count=//p' "$output_file")
    journal_count=$(sed -n 's/^journal_record_count=//p' "$output_file")
    for prefix in \
        "$service_count" "$path_count" "$lighttpd_count" "$listener_count" \
        "$process_count" "$health_count" "$journal_count"; do
        [[ "$prefix" =~ ^[0-9]+$ ]] || return 97
    done

    [[ "$service_count" -eq "${#expected_units[@]}" ]] || return 97
    [[ "$(record_count service_record "$output_file")" -eq "$service_count" ]] ||
        return 97
    for unit in "${expected_units[@]}"; do
        [[ "$(grep -c "^service_record=${unit}|" "$output_file")" -eq 1 ]] ||
            return 97
    done

    [[ "$path_count" -eq "${#expected_paths[@]}" ]] || return 97
    [[ "$(record_count path_record "$output_file")" -eq "$path_count" ]] ||
        return 97
    for target in "${expected_paths[@]}"; do
        [[ "$(grep -c "^path_record=${target}|" "$output_file")" -eq 1 ]] ||
            return 97
    done
    if grep '^path_record=' "$output_file" |
        grep -Ev '\|(absent|symlink|directory|regular|other)\|'; then
        return 97
    fi

    [[ "$lighttpd_count" -eq "${#expected_lighttpd_roots[@]}" ]] || return 97
    [[ "$(record_count lighttpd_record "$output_file")" -eq "$lighttpd_count" ]] ||
        return 97
    for root in "${expected_lighttpd_roots[@]}"; do
        [[ "$(grep -c "^lighttpd_record=${root}|" "$output_file")" -eq 1 ]] ||
            return 97
    done
    include_total=$(
        awk -F '|' '/^lighttpd_record=/ {
            if ($3 !~ /^[0-9]+$/) exit 2
            total += $3
        } END { print total + 0 }' "$output_file"
    ) || return 97
    [[ "$(record_count lighttpd_include_record "$output_file")" -eq "$include_total" ]] || return 97

    [[ "$(record_count listener_record "$output_file")" -eq "$listener_count" ]] ||
        return 97
    [[ "$(record_count process_record "$output_file")" -eq "$process_count" ]] ||
        return 97
    [[ "$health_count" -eq "${#expected_health_names[@]}" ]] || return 97
    [[ "$(record_count health_record "$output_file")" -eq "$health_count" ]] ||
        return 97
    for health_name in "${expected_health_names[@]}"; do
        [[ "$(grep -Ec \
            "^health_record=${health_name}\\|[0-9]+\\|[0-9]{3}$" \
            "$output_file")" -eq 1 ]] || return 97
    done
    [[ "$journal_count" -le 25 ]] || return 97
    [[ "$(record_count journal_record "$output_file")" -eq "$journal_count" ]] ||
        return 97
    return 0
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "${#singleton_prefixes[@]}" -eq 13 ]]
    [[ "${#fixed_markers[@]}" -eq 7 ]]
    [[ "${#expected_units[@]}" -eq 6 ]]
    [[ "${#expected_paths[@]}" -eq 10 ]]
    [[ "${#expected_lighttpd_roots[@]}" -eq 5 ]]
    [[ "${#expected_health_names[@]}" -eq 5 ]]
    verify_inspector
    printf 'action_16ap_a_recovery_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action16ap-a-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    success="$contract_dir/success.out"
    error_file="$contract_dir/error"
    {
        printf '%s\n' "${fixed_markers[@]}"
        printf 'node_hostname=j1-svpihole0\n'
        printf 'node_architecture=arm64\n'
        printf 'systemd_version=systemd 252 (252.39-1~deb12u2)\n'
        printf 'service_record_count=6\n'
        for unit in "${expected_units[@]}"; do
            printf 'service_record=%s|loaded|active|running|enabled|success|0|/lib/systemd/system/example.service|\n' "$unit"
        done
        printf 'path_record_count=10\n'
        for target in "${expected_paths[@]}"; do
            printf 'path_record=%s|absent|unavailable|none|none|none\n' "$target"
        done
        printf 'lighttpd_record_count=5\n'
        for root in "${expected_lighttpd_roots[@]}"; do
            printf 'lighttpd_record=%s|not_applicable|0\n' "$root"
        done
        printf 'caddy_validate_status=not_applicable\n'
        printf 'caddy_tree_sha256=%064d\n' 1
        printf 'keepalived_tree_sha256=%064d\n' 2
        printf 'listener_record_count=0\n'
        printf 'process_record_count=0\n'
        printf 'health_record_count=5\n'
        for health_name in "${expected_health_names[@]}"; do
            printf 'health_record=%s|7|000\n' "$health_name"
        done
        printf 'journal_record_count=0\n'
    } >"$success"
    : >"$error_file"
    evaluate_contract "$success" "$error_file" 0

    duplicate="$contract_dir/duplicate.out"
    cp -- "$success" "$duplicate"
    printf 'caddy_validate_status=0\n' >>"$duplicate"
    if evaluate_contract "$duplicate" "$error_file" 0; then
        printf 'Duplicate Action 16ap-a evidence was accepted.\n' >&2
        exit 1
    fi
    inconsistent="$contract_dir/inconsistent.out"
    sed 's/service_record_count=6/service_record_count=5/' \
        "$success" >"$inconsistent"
    if evaluate_contract "$inconsistent" "$error_file" 0; then
        printf 'Inconsistent Action 16ap-a evidence was accepted.\n' >&2
        exit 1
    fi
    secret="$contract_dir/secret.out"
    cp -- "$success" "$secret"
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$secret"
    if evaluate_contract "$secret" "$error_file" 0; then
        printf 'Secret-bearing Action 16ap-a evidence was accepted.\n' >&2
        exit 1
    fi
    if evaluate_contract "$success" "$error_file" 255; then
        printf 'Nonzero-SSH Action 16ap-a evidence was accepted.\n' >&2
        exit 1
    fi
    printf 'action_16ap_a_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_inspector
work_dir=$(mktemp -d /tmp/caddy-action16ap-a.XXXXXX)
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
        printf 'action_16ap_a_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16ap_a_local_cleanup_complete=true\n'
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
