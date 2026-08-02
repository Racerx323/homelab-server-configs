#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=68716f33d1dd1e027c6cecca91d2e1be2a23a7cbd3292919863cdc30a899cf9e
readonly inspector_name=inspect-node-a-systemd-postinstall-action16an-a.sh
readonly -a fixed_markers=(
    action_16an_a_remote_reached=true
    stage_file_count=16
    stage_digest=305120fdb6b9c970a2aab12aa21ed88c06c3f77b9f63654cd0487fc2656e6e15
    installed_target_count=16
    peer_connections=false
    installed_helper_execution=false
    systemd_daemon_reload_performed=false
    service_mutations=false
    action_16an_a_inspection_complete=true
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
    local assertion_count mismatch_count valid expected_status marker
    local check_count false_check_count malformed_check_count

    for marker in "${fixed_markers[@]}"; do
        [[ "$(grep -Fxc "$marker" "$output_file")" -eq 1 ]] || return 97
    done
    for prefix in \
        acceptance_assertion_count acceptance_mismatch_count first_failure \
        action_16an_a_postinstall_valid effective_caddy_unit_sha256 \
        effective_lighttpd_unit_sha256 journal_disk_usage; do
        [[ "$(grep -c "^${prefix}=" "$output_file")" -eq 1 ]] || return 97
    done
    if grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=' \
        "$output_file" "$error_file"; then
        return 97
    fi

    assertion_count=$(
        sed -n 's/^acceptance_assertion_count=//p' "$output_file"
    )
    mismatch_count=$(
        sed -n 's/^acceptance_mismatch_count=//p' "$output_file"
    )
    valid=$(sed -n 's/^action_16an_a_postinstall_valid=//p' "$output_file")
    [[ "$assertion_count" =~ ^[1-9][0-9]*$ ]] || return 97
    [[ "$mismatch_count" =~ ^[0-9]+$ ]] || return 97
    ((mismatch_count <= assertion_count)) || return 97

    check_count=$(grep -c '^check_' "$output_file")
    false_check_count=$(
        grep -c '^check_.*=false$' "$output_file" || true
    )
    malformed_check_count=$(
        grep '^check_' "$output_file" |
            grep -Evc '^check_[a-z0-9_]+=(true|false)$' || true
    )
    [[ "$check_count" -eq "$assertion_count" ]] || return 97
    [[ "$false_check_count" -eq "$mismatch_count" ]] || return 97
    [[ "$malformed_check_count" -eq 0 ]] || return 97

    if [[ "$mismatch_count" -eq 0 ]]; then
        [[ "$valid" == true ]] || return 97
        grep -Fxq 'first_failure=none' "$output_file" || return 97
        expected_status=0
    else
        [[ "$valid" == false ]] || return 97
        ! grep -Fxq 'first_failure=none' "$output_file" || return 97
        expected_status=1
    fi
    [[ "$ssh_status" -eq "$expected_status" ]] || return 97
    return "$expected_status"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "${#fixed_markers[@]}" -eq 9 ]]
    verify_inspector
    printf 'action_16an_a_systemd_postinstall_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action16an-a-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    success="$contract_dir/success.out"
    error_file="$contract_dir/error"
    {
        printf '%s\n' "${fixed_markers[@]}"
        printf 'check_example=true\n'
        printf 'check_baseline_unit_pihole_ftl_service_active=true\n'
        printf 'acceptance_assertion_count=2\n'
        printf 'acceptance_mismatch_count=0\n'
        printf 'first_failure=none\n'
        printf 'action_16an_a_postinstall_valid=true\n'
        printf 'effective_caddy_unit_sha256=%064d\n' 0
        printf 'effective_lighttpd_unit_sha256=%064d\n' 0
        printf 'journal_disk_usage=3.4G.\n'
    } >"$success"
    : >"$error_file"
    evaluate_contract "$success" "$error_file" 0

    mismatch=${success/success.out/mismatch.out}
    sed \
        -e 's/check_example=true/check_example=false/' \
        -e 's/acceptance_mismatch_count=0/acceptance_mismatch_count=1/' \
        -e 's/first_failure=none/first_failure=example/' \
        -e 's/action_16an_a_postinstall_valid=true/action_16an_a_postinstall_valid=false/' \
        "$success" >"$mismatch"
    set +e
    evaluate_contract "$mismatch" "$error_file" 1
    mismatch_status=$?
    set -e
    [[ "$mismatch_status" -eq 1 ]]

    duplicate=${success/success.out/duplicate.out}
    cp -- "$success" "$duplicate"
    printf '%s\n' "${fixed_markers[0]}" >>"$duplicate"
    if evaluate_contract "$duplicate" "$error_file" 0; then
        printf 'Duplicate Action 16an-a evidence was accepted.\n' >&2
        exit 1
    fi
    malformed=${success/success.out/malformed.out}
    sed 's/check_example=true/check_example=invalid/' "$success" >"$malformed"
    if evaluate_contract "$malformed" "$error_file" 0; then
        printf 'Malformed Action 16an-a evidence was accepted.\n' >&2
        exit 1
    fi
    uppercase=${success/success.out/uppercase.out}
    sed 's/pihole_ftl/pihole_FTL/' "$success" >"$uppercase"
    if evaluate_contract "$uppercase" "$error_file" 0; then
        printf 'Non-normalized Action 16an-a label was accepted.\n' >&2
        exit 1
    fi
    inconsistent=${success/success.out/inconsistent.out}
    sed 's/acceptance_mismatch_count=0/acceptance_mismatch_count=1/' \
        "$success" >"$inconsistent"
    if evaluate_contract "$inconsistent" "$error_file" 0; then
        printf 'Inconsistent Action 16an-a evidence was accepted.\n' >&2
        exit 1
    fi
    secret=${success/success.out/secret.out}
    cp -- "$success" "$secret"
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$secret"
    if evaluate_contract "$secret" "$error_file" 0; then
        printf 'Secret-bearing Action 16an-a evidence was accepted.\n' >&2
        exit 1
    fi
    printf 'action_16an_a_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_inspector
work_dir=$(mktemp -d /tmp/caddy-action16an-a.XXXXXX)
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
        printf 'action_16an_a_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16an_a_local_cleanup_complete=true\n'
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
