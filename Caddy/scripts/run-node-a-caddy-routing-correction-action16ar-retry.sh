#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_driver_name=apply-node-a-caddy-routing-correction-action16ar.sh
readonly historical_driver_sha256=a361d0f4e37bd84a440de9115c0a3148cf9511f3e80736ae93795d812b09278a
readonly transformer_name=correct-node-a-caddy-routing-transaction-action16ar-retry.sh
readonly transformer_sha256=d8c612cb6ea765d45ddb34878ab0dba31a30642d4c473340ce114f37264270e7
readonly rendered_driver_sha256=b62222cc0edd941e7ea4ade533f494fe289b9ac741eb254b0c0b61cde8284a2f
readonly correction_relative=../configs/caddy/conf.d/91-exact-listener-default-deny.caddy
readonly correction_sha256=d3a31eabc6fd75784f5f3891d55dd80d3f024463d112d8dd68549c91bcde8ae7
readonly -a success_markers=(
    action_16ar_retry_remote_reached=true
    action_16ar_retry_preflight_complete=true
    action_16ar_retry_mutation_started=true
    caddy_reload_performed=true
    caddy_restart_performed=false
    systemd_daemon_reload_performed=false
    lighttpd_mutations=false
    keepalived_mutations=false
    lsyncd_mutations=false
    peer_connections=false
    action_16ar_retry_routing_correction_complete=true
)
readonly -a success_prefixes=(
    previous_release
    selected_release
    caddy_main_pid_before
    caddy_main_pid_after
    exact_listener_default_deny_sha256
    release_manifest_sha256
    content_manifest_sha256
    unknown_ipv4_code
    unknown_ipv6_code
    unknown_loopback_code
)

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly historical_driver="$script_dir/$historical_driver_name"
readonly transformer="$script_dir/$transformer_name"
readonly correction="$script_dir/$correction_relative"

verify_source_artifacts() {
    [[ -f "$historical_driver" && ! -L "$historical_driver" ]]
    [[ "$(stat -c '%U:%G:%a' "$historical_driver")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$historical_driver" | awk '{ print $1 }')" == "$historical_driver_sha256" ]]
    [[ -f "$transformer" && ! -L "$transformer" ]]
    [[ "$(stat -c '%U:%G:%a' "$transformer")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$transformer" | awk '{ print $1 }')" == "$transformer_sha256" ]]
    [[ -f "$correction" && ! -L "$correction" ]]
    [[ "$(stat -c '%U:%G:%a' "$correction")" == aaron:aaron:644 ]]
    [[ "$(sha256sum "$correction" | awk '{ print $1 }')" == "$correction_sha256" ]]
    bash -n "$historical_driver" "$transformer"
    "$historical_driver" --self-test >/dev/null
    "$transformer" --self-test >/dev/null
}

render_driver() {
    local output=$1

    "$transformer" --render "$historical_driver" >"$output"
    [[ -f "$output" && ! -L "$output" ]]
    [[ "$(sha256sum "$output" | awk '{ print $1 }')" == "$rendered_driver_sha256" ]]
    bash -n "$output"
    bash "$output" --self-test >/dev/null
}

record_count() {
    local prefix=$1
    local transcript=$2

    grep -c "^${prefix}=" "$transcript" || true
}

record_value() {
    local prefix=$1
    local transcript=$2

    sed -n "s/^${prefix}=//p" "$transcript"
}

evaluate_success() {
    local output_file=$1
    local error_file=$2
    local ssh_status=$3
    local marker prefix before_pid after_pid hash_prefix

    [[ "$ssh_status" -eq 0 ]] || return 97
    [[ ! -s "$error_file" ]] || return 97
    for marker in "${success_markers[@]}"; do
        [[ "$(grep -Fxc "$marker" "$output_file")" -eq 1 ]] || return 97
    done
    for prefix in "${success_prefixes[@]}"; do
        [[ "$(record_count "$prefix" "$output_file")" -eq 1 ]] || return 97
    done
    grep -Fxq 'previous_release=/etc/caddy/releases/bootstrap' "$output_file" ||
        return 97
    grep -Fxq \
        'selected_release=/etc/caddy/releases/action16ar-retry-node-a-default-deny' \
        "$output_file" || return 97
    grep -Fxq \
        "exact_listener_default_deny_sha256=$correction_sha256" \
        "$output_file" || return 97
    for hash_prefix in release_manifest_sha256 content_manifest_sha256; do
        grep -Eq "^${hash_prefix}=[0-9a-f]{64}$" "$output_file" || return 97
    done
    for prefix in unknown_ipv4_code unknown_ipv6_code unknown_loopback_code; do
        grep -Fxq "${prefix}=421" "$output_file" || return 97
    done
    before_pid=$(record_value caddy_main_pid_before "$output_file")
    after_pid=$(record_value caddy_main_pid_after "$output_file")
    [[ "$before_pid" =~ ^[1-9][0-9]*$ ]] || return 97
    [[ "$after_pid" == "$before_pid" ]] || return 97
    if grep -Eq \
        'action_16ar_retry_(rollback_complete|rollback_incomplete|rollback_not_required)=true|manual_intervention_required=true' \
        "$output_file" "$error_file"; then
        return 97
    fi
    return 0
}

evaluate_contract() {
    local output_file=$1
    local error_file=$2
    local ssh_status=$3

    if grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$output_file" "$error_file"; then
        return 97
    fi
    if LC_ALL=C grep -n '[^[:print:][:space:]]' \
        "$output_file" "$error_file" >/dev/null; then
        return 97
    fi
    if [[ "$(grep -Fxc \
        'action_16ar_retry_routing_correction_complete=true' \
        "$output_file")" -eq 1 ]]; then
        evaluate_success "$output_file" "$error_file" "$ssh_status"
        return
    fi
    [[ "$ssh_status" -ne 0 ]] || return 97
    if grep -Fxq 'action_16ar_retry_rollback_incomplete=true' "$error_file" ||
        grep -Fxq 'manual_intervention_required=true' "$error_file"; then
        return 97
    fi
    if [[ "$(grep -Fxc 'action_16ar_retry_rollback_complete=true' \
        "$error_file")" -eq 1 ]]; then
        return 1
    fi
    if [[ "$(grep -Fxc 'action_16ar_retry_rollback_not_required=true' \
        "$error_file")" -eq 1 ]]; then
        return 1
    fi
    return 97
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$historical_driver_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$transformer_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$rendered_driver_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$correction_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "${#success_markers[@]}" -eq 11 ]]
    [[ "${#success_prefixes[@]}" -eq 10 ]]
    verify_source_artifacts
    self_test_driver=$(mktemp /tmp/caddy-action16ar-retry-self-test.XXXXXX)
    trap 'rm -f -- "$self_test_driver"' EXIT
    render_driver "$self_test_driver"
    printf 'action_16ar_retry_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action16ar-retry-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    success="$contract_dir/success.out"
    error_file="$contract_dir/error"
    {
        printf '%s\n' "${success_markers[@]}"
        printf 'previous_release=/etc/caddy/releases/bootstrap\n'
        printf 'selected_release=/etc/caddy/releases/action16ar-retry-node-a-default-deny\n'
        printf 'caddy_main_pid_before=1234\n'
        printf 'caddy_main_pid_after=1234\n'
        printf 'exact_listener_default_deny_sha256=%s\n' "$correction_sha256"
        printf 'release_manifest_sha256=%064d\n' 1
        printf 'content_manifest_sha256=%064d\n' 2
        printf 'unknown_ipv4_code=421\n'
        printf 'unknown_ipv6_code=421\n'
        printf 'unknown_loopback_code=421\n'
    } >"$success"
    : >"$error_file"
    evaluate_contract "$success" "$error_file" 0

    duplicate="$contract_dir/duplicate.out"
    cp -- "$success" "$duplicate"
    printf 'unknown_ipv4_code=421\n' >>"$duplicate"
    if evaluate_contract "$duplicate" "$error_file" 0; then
        printf 'Duplicate Action 16ar retry evidence was accepted.\n' >&2
        exit 1
    fi

    wrong_code="$contract_dir/wrong-code.out"
    sed 's/^unknown_ipv6_code=421$/unknown_ipv6_code=200/' \
        "$success" >"$wrong_code"
    if evaluate_contract "$wrong_code" "$error_file" 0; then
        printf 'Incorrect Action 16ar retry rejection status was accepted.\n' \
            >&2
        exit 1
    fi

    restarted="$contract_dir/restarted.out"
    sed 's/^caddy_main_pid_after=1234$/caddy_main_pid_after=5678/' \
        "$success" >"$restarted"
    if evaluate_contract "$restarted" "$error_file" 0; then
        printf 'Action 16ar retry Caddy restart evidence was accepted.\n' >&2
        exit 1
    fi

    rollback_error="$contract_dir/rollback.error"
    printf 'action_16ar_retry_rollback_complete=true\n' >"$rollback_error"
    set +e
    evaluate_contract /dev/null "$rollback_error" 1
    rollback_status=$?
    set -e
    [[ "$rollback_status" -eq 1 ]]

    no_mutation_error="$contract_dir/no-mutation.error"
    printf 'action_16ar_retry_rollback_not_required=true\n' \
        >"$no_mutation_error"
    set +e
    evaluate_contract /dev/null "$no_mutation_error" 1
    no_mutation_status=$?
    set -e
    [[ "$no_mutation_status" -eq 1 ]]

    incomplete_error="$contract_dir/incomplete.error"
    {
        printf 'action_16ar_retry_rollback_incomplete=true\n'
        printf 'manual_intervention_required=true\n'
    } >"$incomplete_error"
    set +e
    evaluate_contract /dev/null "$incomplete_error" 125
    incomplete_status=$?
    set -e
    [[ "$incomplete_status" -eq 97 ]]

    secret="$contract_dir/secret.out"
    cp -- "$success" "$secret"
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$secret"
    if evaluate_contract "$secret" "$error_file" 0; then
        printf 'Secret-bearing Action 16ar retry evidence was accepted.\n' >&2
        exit 1
    fi

    printf 'action_16ar_retry_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_source_artifacts
work_dir=$(mktemp -d /tmp/caddy-action16ar-retry.XXXXXX)
readonly work_dir
readonly rendered_driver="$work_dir/driver.sh"
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
        printf 'action_16ar_retry_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16ar_retry_local_cleanup_complete=true\n'
    exit "$status"
}

render_driver "$rendered_driver"
set +e
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias=pihole0.local.theama.co \
    -o StrictHostKeyChecking=yes \
    pi@10.1.0.53 \
    'sudo -n /bin/bash -s --' \
    <"$rendered_driver" >"$remote_output" 2>"$remote_error"
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
