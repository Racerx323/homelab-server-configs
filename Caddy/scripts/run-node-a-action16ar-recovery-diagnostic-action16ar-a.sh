#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_name=diagnose-node-a-action16ar-recovery-action16ar-a.sh
readonly inspector_sha256=c63146c3c2d7e3201bb5a90d3456333a3ccdcb4bf6a287721607e8f046ff28cb
readonly -a singleton_prefixes=(
    node_hostname
    node_architecture
    collection_timestamp
    command_record_count
    path_record_count
    release_record_count
    environment_record_count
    environment_file_sha256
    service_record_count
    caddy_environment_files
    caddy_invocation_id
    caddy_validate_status
    tree_record_count
    listener_record_count
    process_record_count
    probe_record_count
    journal_status
    journal_record_count
)
readonly -a fixed_markers=(
    action_16ar_a_remote_reached=true
    runtime_metrics_counter_effect=true
    peer_connections=false
    installed_helper_execution=false
    systemd_daemon_reload_performed=false
    service_mutations=false
    filesystem_mutations=false
    action_16ar_a_recovery_diagnostic_complete=true
)
readonly -a expected_commands=(
    awk caddy curl date dpkg find grep hostname journalctl jq pgrep readlink
    runuser sed sha256sum sort ss stat systemctl tr wc xargs
)
readonly -a expected_paths=(
    /etc/caddy/current
    /etc/caddy/releases/bootstrap
    /etc/caddy/releases/action16ar-node-a-default-deny
    /etc/caddy/releases/.action16ar-node-a-default-deny.staging
    /etc/caddy/current.action16ar-new
    /etc/default/caddy-ha
    /etc/keepalived/conf.d/caddy-ha.conf
    /etc/caddy/current/Caddyfile
    /etc/caddy/current/conf.d/90-default-deny.caddy
    /etc/caddy/current/conf.d/91-exact-listener-default-deny.caddy
    /etc/caddy/releases/action16ar-node-a-default-deny/.complete
    /etc/caddy/releases/action16ar-node-a-default-deny/manifest.sha256
    /etc/caddy/releases/action16ar-node-a-default-deny/release-manifest.json
    /etc/caddy/releases/.action16ar-node-a-default-deny.staging/.complete
    /etc/caddy/releases/.action16ar-node-a-default-deny.staging/manifest.sha256
    /etc/caddy/releases/.action16ar-node-a-default-deny.staging/release-manifest.json
)
readonly -a expected_releases=(
    /etc/caddy/releases/bootstrap
    /etc/caddy/releases/action16ar-node-a-default-deny
    /etc/caddy/releases/.action16ar-node-a-default-deny.staging
)
readonly -a expected_environment_keys=(
    NODE_ROLE
    NODE_FQDN
    NODE_IPV4
    NODE_IPV6
    PEER_ROLE
    PEER_IPV4
    PEER_IPV6
    CADDY_PRIORITY
    NETWORK_INTERFACE
    SYNC_TARGET
)
readonly -a expected_units=(
    caddy.service
    lighttpd.service
    keepalived.service
    lsyncd.service
    caddy-lsyncd.service
    caddy-api.service
    caddy-validate-reload.path
    caddy-validate-reload.service
)
readonly -a expected_probe_labels=(
    backend
    localhost_health
    management_ipv4
    management_ipv6
    unknown_ipv4
    unknown_ipv6
    unknown_loopback_ipv4
    unknown_loopback_ipv6
)
readonly -a expected_trees=(
    /etc/caddy
    /etc/keepalived
    /etc/lighttpd
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

record_value() {
    local prefix=$1
    local output_file=$2

    sed -n "s/^${prefix}=//p" "$output_file"
}

validate_count() {
    local count=$1

    [[ "$count" =~ ^[0-9]+$ ]]
}

evaluate_contract() {
    local output_file=$1
    local error_file=$2
    local ssh_status=$3
    local marker prefix expected count config_count route_total
    local journal_count listener_count process_count

    [[ "$ssh_status" -eq 0 ]] || return 97
    [[ ! -s "$error_file" ]] || return 97
    for marker in "${fixed_markers[@]}"; do
        [[ "$(grep -Fxc "$marker" "$output_file")" -eq 1 ]] || return 97
    done
    for prefix in "${singleton_prefixes[@]}"; do
        [[ "$(record_count "$prefix" "$output_file")" -eq 1 ]] || return 97
    done
    if grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$output_file" "$error_file"; then
        return 97
    fi
    if LC_ALL=C grep -n '[^[:print:][:space:]]' \
        "$output_file" "$error_file" >/dev/null; then
        return 97
    fi

    grep -Eq '^node_hostname=[A-Za-z0-9._-]+$' "$output_file" || return 97
    grep -Eq '^node_architecture=[A-Za-z0-9._-]+$' "$output_file" ||
        return 97
    grep -Eq \
        '^collection_timestamp=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' \
        "$output_file" || return 97
    grep -Eq '^environment_file_sha256=([0-9a-f]{64}|not_regular)$' \
        "$output_file" || return 97
    grep -Eq '^caddy_validate_status=([0-9]+|not_applicable)$' \
        "$output_file" || return 97
    grep -Eq '^journal_status=[0-9]+$' "$output_file" || return 97

    count=$(record_value command_record_count "$output_file")
    validate_count "$count" || return 97
    [[ "$count" -eq "${#expected_commands[@]}" ]] || return 97
    [[ "$(record_count command_record "$output_file")" -eq "$count" ]] ||
        return 97
    for expected in "${expected_commands[@]}"; do
        [[ "$(grep -Ec "^command_record=${expected}\\|[0-9]+$" \
            "$output_file")" -eq 1 ]] || return 97
    done

    count=$(record_value path_record_count "$output_file")
    validate_count "$count" || return 97
    [[ "$count" -eq "${#expected_paths[@]}" ]] || return 97
    [[ "$(record_count path_record "$output_file")" -eq "$count" ]] ||
        return 97
    for expected in "${expected_paths[@]}"; do
        [[ "$(grep -c "^path_record=${expected}|" "$output_file")" -eq 1 ]] ||
            return 97
    done
    if grep '^path_record=' "$output_file" |
        grep -Ev '\|(absent|symlink|directory|regular|other)\|'; then
        return 97
    fi

    count=$(record_value release_record_count "$output_file")
    validate_count "$count" || return 97
    [[ "$count" -eq "${#expected_releases[@]}" ]] || return 97
    [[ "$(record_count release_record "$output_file")" -eq "$count" ]] ||
        return 97
    for expected in "${expected_releases[@]}"; do
        [[ "$(grep -c "^release_record=${expected}|" "$output_file")" -eq 1 ]] ||
            return 97
    done
    if grep '^release_record=' "$output_file" |
        grep -Ev '\|(absent|directory|regular|symlink|other)\|'; then
        return 97
    fi

    count=$(record_value environment_record_count "$output_file")
    validate_count "$count" || return 97
    [[ "$count" -eq "${#expected_environment_keys[@]}" ]] || return 97
    [[ "$(record_count environment_record "$output_file")" -eq "$count" ]] ||
        return 97
    for expected in "${expected_environment_keys[@]}"; do
        [[ "$(grep -c "^environment_record=${expected}|" \
            "$output_file")" -eq 1 ]] || return 97
    done

    count=$(record_value service_record_count "$output_file")
    validate_count "$count" || return 97
    [[ "$count" -eq "${#expected_units[@]}" ]] || return 97
    [[ "$(record_count service_record "$output_file")" -eq "$count" ]] ||
        return 97
    for expected in "${expected_units[@]}"; do
        [[ "$(grep -c "^service_record=${expected}|" "$output_file")" -eq 1 ]] ||
            return 97
    done

    config_count=$(record_count config_record "$output_file")
    [[ "$config_count" -eq 2 ]] || return 97
    for expected in adapted runtime; do
        [[ "$(grep -Ec \
            "^config_record=${expected}\\|[0-9]+\\|([0-9a-f]{64}|unavailable)\\|[0-9]+$" \
            "$output_file")" -eq 1 ]] || return 97
    done
    route_total=$(
        awk -F '|' '/^config_record=/ {
            if ($4 !~ /^[0-9]+$/) exit 2
            total += $4
        } END { print total + 0 }' "$output_file"
    ) || return 97
    [[ "$(record_count route_record "$output_file")" -eq "$route_total" ]] ||
        return 97
    if grep '^route_record=' "$output_file" |
        grep -Ev '^route_record=(adapted|runtime)\|\{.*\}$'; then
        return 97
    fi

    count=$(record_value tree_record_count "$output_file")
    [[ "$count" -eq "${#expected_trees[@]}" ]] || return 97
    [[ "$(record_count tree_record "$output_file")" -eq "$count" ]] ||
        return 97
    for expected in "${expected_trees[@]}"; do
        [[ "$(grep -Ec "^tree_record=${expected}\\|([0-9a-f]{64}|unavailable)$" \
            "$output_file")" -eq 1 ]] || return 97
    done

    listener_count=$(record_value listener_record_count "$output_file")
    process_count=$(record_value process_record_count "$output_file")
    validate_count "$listener_count" || return 97
    validate_count "$process_count" || return 97
    [[ "$(record_count listener_record "$output_file")" -eq "$listener_count" ]] ||
        return 97
    [[ "$(record_count process_record "$output_file")" -eq "$process_count" ]] ||
        return 97

    count=$(record_value probe_record_count "$output_file")
    [[ "$count" -eq "${#expected_probe_labels[@]}" ]] || return 97
    [[ "$(record_count probe_record "$output_file")" -eq "$count" ]] ||
        return 97
    for expected in "${expected_probe_labels[@]}"; do
        [[ "$(grep -Ec \
            "^probe_record=${expected}\\|[0-9]+\\|([0-9]{3}%7C[^|]+|missing)$" \
            "$output_file")" -eq 1 ]] || return 97
    done

    journal_count=$(record_value journal_record_count "$output_file")
    validate_count "$journal_count" || return 97
    [[ "$journal_count" -le 80 ]] || return 97
    [[ "$(record_count journal_record "$output_file")" -eq "$journal_count" ]] ||
        return 97
    return 0
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "${#singleton_prefixes[@]}" -eq 18 ]]
    [[ "${#fixed_markers[@]}" -eq 8 ]]
    [[ "${#expected_commands[@]}" -eq 22 ]]
    [[ "${#expected_paths[@]}" -eq 16 ]]
    [[ "${#expected_releases[@]}" -eq 3 ]]
    [[ "${#expected_environment_keys[@]}" -eq 10 ]]
    [[ "${#expected_units[@]}" -eq 8 ]]
    [[ "${#expected_probe_labels[@]}" -eq 8 ]]
    verify_inspector
    printf 'action_16ar_a_recovery_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action16ar-a-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    success="$contract_dir/success.out"
    error_file="$contract_dir/error"
    {
        printf '%s\n' "${fixed_markers[@]}"
        printf 'node_hostname=j1-svpihole0\n'
        printf 'node_architecture=arm64\n'
        printf 'collection_timestamp=2026-07-29T16:30:00Z\n'
        printf 'command_record_count=%s\n' "${#expected_commands[@]}"
        for expected in "${expected_commands[@]}"; do
            printf 'command_record=%s|0\n' "$expected"
        done
        printf 'path_record_count=%s\n' "${#expected_paths[@]}"
        for expected in "${expected_paths[@]}"; do
            printf 'path_record=%s|absent|unavailable|none|none|none\n' \
                "$expected"
        done
        printf 'release_record_count=%s\n' "${#expected_releases[@]}"
        for expected in "${expected_releases[@]}"; do
            printf 'release_record=%s|absent|unavailable|unavailable|absent|not_applicable|unavailable|unavailable|unavailable|unavailable|unavailable|0|not_regular\n' \
                "$expected"
        done
        printf 'environment_record_count=%s\n' \
            "${#expected_environment_keys[@]}"
        for expected in "${expected_environment_keys[@]}"; do
            printf 'environment_record=%s|missing\n' "$expected"
        done
        printf 'environment_file_sha256=not_regular\n'
        printf 'service_record_count=%s\n' "${#expected_units[@]}"
        for expected in "${expected_units[@]}"; do
            printf 'service_record=%s|not-found|inactive|dead|disabled|success|0|0|0||\n' \
                "$expected"
        done
        printf 'caddy_environment_files=\n'
        printf 'caddy_invocation_id=\n'
        printf 'caddy_validate_status=not_applicable\n'
        printf 'config_record=adapted|1|unavailable|0\n'
        printf 'config_record=runtime|7|unavailable|0\n'
        printf 'tree_record_count=%s\n' "${#expected_trees[@]}"
        for expected in "${expected_trees[@]}"; do
            printf 'tree_record=%s|unavailable\n' "$expected"
        done
        printf 'listener_record_count=0\n'
        printf 'process_record_count=0\n'
        printf 'probe_record_count=%s\n' "${#expected_probe_labels[@]}"
        for expected in "${expected_probe_labels[@]}"; do
            printf 'probe_record=%s|7|missing\n' "$expected"
        done
        printf 'journal_status=0\n'
        printf 'journal_record_count=0\n'
    } >"$success"
    : >"$error_file"
    evaluate_contract "$success" "$error_file" 0

    duplicate="$contract_dir/duplicate.out"
    cp -- "$success" "$duplicate"
    printf 'caddy_validate_status=0\n' >>"$duplicate"
    if evaluate_contract "$duplicate" "$error_file" 0; then
        printf 'Duplicate Action 16ar-a evidence was accepted.\n' >&2
        exit 1
    fi

    inconsistent="$contract_dir/inconsistent.out"
    sed 's/^path_record_count=16$/path_record_count=15/' \
        "$success" >"$inconsistent"
    if evaluate_contract "$inconsistent" "$error_file" 0; then
        printf 'Inconsistent Action 16ar-a evidence was accepted.\n' >&2
        exit 1
    fi

    wrong_probe="$contract_dir/wrong-probe.out"
    sed '/^probe_record=unknown_ipv6|/d' "$success" >"$wrong_probe"
    if evaluate_contract "$wrong_probe" "$error_file" 0; then
        printf 'Incomplete Action 16ar-a probe evidence was accepted.\n' >&2
        exit 1
    fi

    secret="$contract_dir/secret.out"
    cp -- "$success" "$secret"
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$secret"
    if evaluate_contract "$secret" "$error_file" 0; then
        printf 'Secret-bearing Action 16ar-a evidence was accepted.\n' >&2
        exit 1
    fi

    if evaluate_contract "$success" "$error_file" 255; then
        printf 'Nonzero-SSH Action 16ar-a evidence was accepted.\n' >&2
        exit 1
    fi

    printf 'action_16ar_a_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_inspector
work_dir=$(mktemp -d /tmp/caddy-action16ar-a.XXXXXX)
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
        printf 'action_16ar_a_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16ar_a_local_cleanup_complete=true\n'
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
