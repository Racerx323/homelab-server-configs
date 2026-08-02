#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly installer_sha256=192a682795655d363eab2e07f3af3932a08cc77d8ff4cf96b19ea6b2daafb9c2
readonly installer_name=install-node-a-systemd-action16an.sh
readonly -a required_markers=(
    action_16an_remote_reached=true
    action_16an_preflight_complete=true
    action_16an_mutation_started=true
    action_16an_files_installed=true
    systemd_daemon_reload_performed=true
    action_16an_postinstall_systemd_valid=true
    action_16an_protected_state_unchanged=true
    stage_retained=true
    retained_sync_stage_preserved=true
    custom_units_enabled=false
    custom_units_active=false
    peer_connections=false
    installed_helper_execution=false
    service_mutations=false
    lsyncd_configuration_installed=false
    caddy_keepalived_fragment_installed=false
    action_16an_systemd_install_complete=true
)

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly installer="$script_dir/$installer_name"

verify_installer() {
    [[ -f "$installer" && ! -L "$installer" ]]
    [[ "$(stat -c '%U:%G:%a' "$installer")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$installer" | awk '{ print $1 }')" == "$installer_sha256" ]]
    bash -n "$installer"
    "$installer" --self-test >/dev/null
}

validate_success_output() {
    local output_file=$1
    local error_file=$2
    local ssh_status=$3
    local marker

    if [[ "$ssh_status" -ne 0 ]]; then
        return 1
    fi
    for marker in "${required_markers[@]}"; do
        if [[ "$(grep -Fxc "$marker" "$output_file")" -ne 1 ]]; then
            return 1
        fi
    done
    if grep -Eq \
        'manual_intervention_required=true|action_16an_rollback_complete=' \
        "$output_file" "$error_file"; then
        return 1
    fi
    if grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=' \
        "$output_file" "$error_file"; then
        return 1
    fi
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$installer_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "${#required_markers[@]}" -eq 17 ]]
    verify_installer
    printf 'action_16an_systemd_install_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action16an-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    success_output="$contract_dir/success.out"
    success_error="$contract_dir/success.err"
    printf '%s\n' "${required_markers[@]}" >"$success_output"
    : >"$success_error"
    validate_success_output "$success_output" "$success_error" 0
    cp -- "$success_output" "$contract_dir/duplicate.out"
    printf '%s\n' "${required_markers[0]}" >>"$contract_dir/duplicate.out"
    if validate_success_output \
        "$contract_dir/duplicate.out" "$success_error" 0; then
        printf 'Duplicate Action 16an evidence was accepted.\n' >&2
        exit 1
    fi
    sed '1d' "$success_output" >"$contract_dir/missing.out"
    if validate_success_output "$contract_dir/missing.out" "$success_error" 0; then
        printf 'Missing Action 16an evidence was accepted.\n' >&2
        exit 1
    fi
    printf 'action_16an_rollback_complete=true\n' \
        >"$contract_dir/rollback.err"
    if validate_success_output \
        "$success_output" "$contract_dir/rollback.err" 0; then
        printf 'Rollback-bearing Action 16an success was accepted.\n' >&2
        exit 1
    fi
    if validate_success_output "$success_output" "$success_error" 1; then
        printf 'Nonzero Action 16an SSH status was accepted.\n' >&2
        exit 1
    fi
    printf 'action_16an_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_installer
work_dir=$(mktemp -d /tmp/caddy-action16an.XXXXXX)
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
        printf 'action_16an_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16an_local_cleanup_complete=true\n'
    exit "$status"
}

set +e
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias=pihole0.local.theama.co \
    -o StrictHostKeyChecking=yes \
    pi@10.1.0.53 \
    'sudo -n /bin/bash -s' \
    <"$installer" >"$remote_output" 2>"$remote_error"
ssh_status=$?
set -e

if grep -Eq \
    'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=' \
    "$remote_output" "$remote_error"; then
    printf 'Action 16an suppressed unexpected private material.\n' >&2
    finish 97
fi

cat "$remote_output"
cat "$remote_error" >&2
printf 'ssh_exit_status=%s\n' "$ssh_status"

if ! grep -Fxq 'action_16an_remote_reached=true' "$remote_output"; then
    finish "$ssh_status"
fi
if [[ "$ssh_status" -ne 0 ]]; then
    if grep -Fxq 'action_16an_mutation_started=true' "$remote_output"; then
        if ! grep -Fxq 'action_16an_rollback_complete=true' "$remote_error"; then
            printf 'Action 16an lacks required rollback evidence.\n' >&2
            finish 97
        fi
    fi
    if grep -Fq 'manual_intervention_required=true' \
        "$remote_output" "$remote_error"; then
        finish 97
    fi
    finish "$ssh_status"
fi

if ! validate_success_output "$remote_output" "$remote_error" "$ssh_status"; then
    printf 'Invalid Action 16an success transcript.\n' >&2
    finish 97
fi

finish 0
