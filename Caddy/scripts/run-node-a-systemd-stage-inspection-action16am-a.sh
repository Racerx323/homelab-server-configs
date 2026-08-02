#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=5ec3f551701185b26dccd3fac84e5e6e6ea599e9e809bcdc8a28855ab1b4fa1d
readonly stage_digest_sha256=305120fdb6b9c970a2aab12aa21ed88c06c3f77b9f63654cd0487fc2656e6e15

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly inspector="$script_dir/inspect-node-a-systemd-stage-action16am-a.sh"

verify_inspector() {
    [[ -f "$inspector" && ! -L "$inspector" ]]
    [[ "$(stat -c '%U:%G:%a' "$inspector")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$inspector" | awk '{ print $1 }')" == "$inspector_sha256" ]]
}

evaluate_contract() {
    local output_file=$1
    local error_file=$2
    local ssh_status=$3
    local contract_valid=true
    local label marker
    local mismatch_count first_failure inspection_valid
    local stage_owner_mode stage_file_count stage_digest
    local false_line_count expected_false_line_count

    if grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=' \
        "$output_file" "$error_file"; then
        printf 'Action 16am-a suppressed unexpected private material.\n' >&2
        return 97
    fi
    if [[ "$(grep -Fxc 'action_16am_a_remote_reached=true' \
        "$output_file")" -ne 1 ]]; then
        if [[ "$ssh_status" -eq 0 ]]; then
            return 97
        fi
        return "$ssh_status"
    fi

    [[ "$(grep -Fxc \
        'action_16am_a_read_only_inspection_complete=true' \
        "$output_file")" -eq 1 ]] || contract_valid=false
    for label in \
        inspection_mismatch_count \
        first_failure \
        action_16am_a_stage_and_protected_state_valid \
        systemd_version \
        effective_caddy_unit_sha256 \
        effective_lighttpd_unit_sha256 \
        journal_disk_usage \
        protected_package_inventory_sha256 \
        stage_path \
        stage_owner_mode \
        stage_file_count_valid \
        stage_file_count \
        stage_digest_valid \
        stage_digest; do
        [[ "$(grep -c "^${label}=" "$output_file")" -eq 1 ]] ||
            contract_valid=false
    done
    grep -Eq '^inspection_mismatch_count=[0-9]+$' "$output_file" ||
        contract_valid=false
    grep -Eq '^first_failure=(none|[a-z0-9_]+)$' "$output_file" ||
        contract_valid=false
    grep -Eq \
        '^action_16am_a_stage_and_protected_state_valid=(true|false)$' \
        "$output_file" || contract_valid=false
    grep -Eq '^systemd_version=systemd 252([[:space:]]|$)' \
        "$output_file" || contract_valid=false
    grep -Eq '^effective_caddy_unit_sha256=[0-9a-f]{64}$' \
        "$output_file" || contract_valid=false
    grep -Eq '^effective_lighttpd_unit_sha256=[0-9a-f]{64}$' \
        "$output_file" || contract_valid=false
    grep -Eq '^protected_package_inventory_sha256=[0-9a-f]{64}$' \
        "$output_file" || contract_valid=false
    grep -Fxq 'stage_path=/var/tmp/caddy-systemd-node-a-action16am' \
        "$output_file" || contract_valid=false
    grep -Eq '^stage_owner_mode=([^:]+:){2}[0-9]+$' \
        "$output_file" || contract_valid=false
    grep -Eq '^stage_file_count_valid=(true|false)$' \
        "$output_file" || contract_valid=false
    grep -Eq '^stage_file_count=[0-9]+$' "$output_file" ||
        contract_valid=false
    grep -Eq '^stage_digest_valid=(true|false)$' \
        "$output_file" || contract_valid=false
    grep -Eq '^stage_digest=([0-9a-f]{64}|)$' "$output_file" ||
        contract_valid=false
    for marker in \
        peer_connections=false \
        installed_helper_execution=false \
        systemd_daemon_reload_performed=false \
        service_mutations=false; do
        [[ "$(grep -Fxc "$marker" "$output_file")" -eq 1 ]] ||
            contract_valid=false
    done
    if grep -Eq \
        'manual_intervention_required=true|rollback_complete=|mutation_started=true' \
        "$output_file" "$error_file"; then
        contract_valid=false
    fi
    if [[ "$contract_valid" != true ]]; then
        printf 'Action 16am-a output contract failed.\n' >&2
        return 97
    fi

    mismatch_count=$(
        sed -n 's/^inspection_mismatch_count=//p' "$output_file"
    )
    first_failure=$(
        sed -n 's/^first_failure=//p' "$output_file"
    )
    inspection_valid=$(
        sed -n \
            's/^action_16am_a_stage_and_protected_state_valid=//p' \
            "$output_file"
    )
    stage_owner_mode=$(
        sed -n 's/^stage_owner_mode=//p' "$output_file"
    )
    stage_file_count=$(
        sed -n 's/^stage_file_count=//p' "$output_file"
    )
    stage_digest=$(
        sed -n 's/^stage_digest=//p' "$output_file"
    )
    false_line_count=$(grep -Ec '=false$' "$output_file")
    expected_false_line_count=$((mismatch_count + 4))
    if [[ "$inspection_valid" == false ]]; then
        expected_false_line_count=$((expected_false_line_count + 1))
    fi
    if [[ "$false_line_count" -ne "$expected_false_line_count" ]]; then
        printf 'Action 16am-a mismatch count is inconsistent.\n' >&2
        return 97
    fi
    if [[ "$mismatch_count" -eq 0 ]]; then
        if [[ "$first_failure" != none ||
            "$inspection_valid" != true ||
            "$stage_owner_mode" != root:root:750 ||
            "$stage_file_count" -ne 16 ||
            "$stage_digest" != "$stage_digest_sha256" ||
            "$ssh_status" -ne 0 ]]; then
            printf 'Action 16am-a valid-state result is inconsistent.\n' >&2
            return 97
        fi
        return 0
    fi
    if [[ "$first_failure" == none ||
        "$inspection_valid" != false ||
        "$ssh_status" -ne 1 ]]; then
        printf 'Action 16am-a mismatch result is inconsistent.\n' >&2
        return 97
    fi
    return 1
}

contract_test() {
    local test_dir output_file error_file success mismatch
    local duplicate malformed missing_marker inconsistent secret

    test_dir=$(mktemp -d /tmp/caddy-action16am-a-contract.XXXXXX)
    output_file="$test_dir/remote.out"
    error_file="$test_dir/remote.err"
    trap 'rm -rf -- "$test_dir"' RETURN
    : >"$error_file"
    success=$(printf '%s\n' \
        action_16am_a_remote_reached=true \
        'systemd_version=systemd 252 (252.39-1~deb12u2)' \
        effective_caddy_unit_sha256=3a5f3f84e08686a1cb6d247ee84698b896bf025203a2f74ab4cd578dee731a40 \
        effective_lighttpd_unit_sha256=fdd4ccfc6ffcf219d2d51e721798ee7fee0393356198e294e03b6e69f3c8ec67 \
        'journal_disk_usage=Archived and active journals take up 3.4G in the file system.' \
        protected_package_inventory_sha256=6377ab1492b2da992dce53199e359c5a2faf3563abd8bf766e6d6967fa07da5c \
        stage_path=/var/tmp/caddy-systemd-node-a-action16am \
        stage_owner_mode=root:root:750 \
        stage_file_count_valid=true \
        stage_file_count=16 \
        stage_digest_valid=true \
        "stage_digest=$stage_digest_sha256" \
        inspection_mismatch_count=0 \
        first_failure=none \
        peer_connections=false \
        installed_helper_execution=false \
        systemd_daemon_reload_performed=false \
        service_mutations=false \
        action_16am_a_stage_and_protected_state_valid=true \
        action_16am_a_read_only_inspection_complete=true)

    printf '%s\n' "$success" >"$output_file"
    evaluate_contract "$output_file" "$error_file" 0 >/dev/null 2>&1

    mismatch=${success/stage_file_count_valid=true/stage_file_count_valid=false}
    mismatch=${mismatch/inspection_mismatch_count=0/inspection_mismatch_count=1}
    mismatch=${mismatch/first_failure=none/first_failure=stage_file_count_valid}
    mismatch=${mismatch/action_16am_a_stage_and_protected_state_valid=true/action_16am_a_stage_and_protected_state_valid=false}
    printf '%s\n' "$mismatch" >"$output_file"
    set +e
    evaluate_contract "$output_file" "$error_file" 1 >/dev/null 2>&1
    mismatch_status=$?
    set -e
    [[ "$mismatch_status" -eq 1 ]]

    duplicate=$(printf '%s\nstage_file_count=16\n' "$success")
    malformed=${success/stage_file_count=16/stage_file_count=invalid}
    missing_marker=$(
        printf '%s\n' "$success" |
            sed '/^service_mutations=false$/d'
    )
    inconsistent=$(printf '%s\nstage_root_meta=false\n' "$success")
    secret=$(printf '%s\nPRIVATE_KEY=unexpected\n' "$success")
    for transcript in \
        "$duplicate" "$malformed" "$missing_marker" "$inconsistent" "$secret"; do
        printf '%s\n' "$transcript" >"$output_file"
        set +e
        evaluate_contract "$output_file" "$error_file" 0 >/dev/null 2>&1
        invalid_status=$?
        set -e
        [[ "$invalid_status" -eq 97 ]]
    done
    printf 'action_16am_a_transcript_contract_test_complete=true\n'
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$stage_digest_sha256" =~ ^[0-9a-f]{64}$ ]]
    verify_inspector
    bash -n "$inspector"
    "$inspector" --self-test >/dev/null
    printf 'action_16am_a_systemd_stage_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    verify_inspector
    contract_test
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_inspector
work_dir=$(mktemp -d /tmp/caddy-action16am-a.XXXXXX)
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
        printf 'action_16am_a_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16am_a_local_cleanup_complete=true\n'
    exit "$status"
}

ssh_status=0
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias=pihole0.local.theama.co \
    -o StrictHostKeyChecking=yes \
    pi@10.1.0.53 \
    'sudo -n /bin/bash -s --' \
    <"$inspector" >"$remote_output" 2>"$remote_error" || ssh_status=$?

if grep -Eq \
    'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=' \
    "$remote_output" "$remote_error"; then
    printf 'Action 16am-a suppressed unexpected private material.\n' >&2
    finish 97
fi
cat "$remote_output"
cat "$remote_error" >&2
printf 'ssh_exit_status=%s\n' "$ssh_status"
set +e
evaluate_contract "$remote_output" "$remote_error" "$ssh_status"
contract_status=$?
set -e
finish "$contract_status"
