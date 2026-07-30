#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly driver_sha256=916f8b8a109494523906d189f8cabec834ccf40fd04a38cb5686f355f3aee631
readonly regression_sha256=4849d4057405d996415c62e3f44998e145936697420327147cd269209d25ac60
readonly accepted_action17e_runner_sha256=5354fcd0fa5710ebef77f6751e4094903685d17056891760229c84b08868be92
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly candidate_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly accepted_live_state_sha256=3a05c0487101f3b44f8e5ba41a4a74713d07cddc369542f04d4a8b1f417cb824
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co
readonly expected_stage=/var/tmp/caddy-unbound-node-b-action17f-local-zone

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
workspace_root=$(cd -- "$caddy_root/../.." && pwd)
readonly workspace_root
readonly driver="$script_dir/stage-node-b-unbound-local-zone-action17f.sh"
readonly regression="$caddy_root/tests/action17f-node-b-unbound-local-zone-stage-regression.sh"
readonly accepted_action17e_runner="$script_dir/run-node-b-unbound-primary-stage-action17e-retry.sh"
readonly candidate_primary="$workspace_root/homelab-dns/Unbound/configs/pihole0.conf"
readonly candidate_local_zone="$workspace_root/homelab-dns/Unbound/configs/pihole0-local-zone.conf"
readonly dns_repo="$workspace_root/homelab-dns"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_file() {
    local path=$1
    local expected_hash=$2

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(file_hash "$path")" == "$expected_hash" ]]
}

verify_sources() {
    verify_file "$driver" "$driver_sha256"
    verify_file "$regression" "$regression_sha256"
    verify_file \
        "$accepted_action17e_runner" "$accepted_action17e_runner_sha256"
    verify_file "$candidate_primary" "$candidate_primary_sha256"
    verify_file "$candidate_local_zone" "$candidate_local_zone_sha256"
    bash -n "$driver" "$regression" "$accepted_action17e_runner"
}

verify_live_sources() {
    local path

    verify_sources
    for path in "$driver" "$regression" "$accepted_action17e_runner"; do
        [[ "$(stat -c '%U:%G:%a' "$path")" == aaron:aaron:755 ]]
    done
    [[ "$(stat -c '%U:%G:%a' "$candidate_primary")" == aaron:aaron:644 ]]
    [[ "$(stat -c '%U:%G:%a' "$candidate_local_zone")" == aaron:aaron:644 ]]
    git -C "$dns_repo" check-ignore -q Unbound/configs/pihole0.conf
    git -C "$dns_repo" check-ignore -q \
        Unbound/configs/pihole0-local-zone.conf
    if git -C "$dns_repo" ls-files --error-unmatch \
        Unbound/configs/pihole0.conf >/dev/null 2>&1 ||
        git -C "$dns_repo" ls-files --error-unmatch \
            Unbound/configs/pihole0-local-zone.conf >/dev/null 2>&1; then
        printf 'Private Unbound operator sources unexpectedly became tracked.\n' \
            >&2
        return 1
    fi
}

require_one() {
    local record=$1
    local transcript=$2

    [[ "$(grep -Fxc "$record" "$transcript")" -eq 1 ]]
}

value_for() {
    local prefix=$1
    local transcript=$2
    local record

    [[ "$(grep -Ec "^${prefix}=" "$transcript")" -eq 1 ]] || return 1
    record=$(grep -E "^${prefix}=" "$transcript")
    printf '%s\n' "${record#*=}"
}

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=|private-domain:|local-data(-ptr)?:' \
        "$@"
}

validate_success() {
    local output=$1
    local error_file=$2
    local ssh_status=$3
    local before_hash after_hash
    local -a markers=(
        action_17f_preflight_complete=true
        primary_stage_accepted=true
        local_zone_stage_previously_absent=true
        action_17f_mutation_started=true
        "local_zone_candidate_sha256=$candidate_local_zone_sha256"
        "local_zone_stage_path=$expected_stage"
        local_zone_stage_owner_mode=root:root:700
        local_zone_file_owner_mode=root:root:600
        primary_stage_still_valid=true
        combined_pair_parser_valid=true
        local_zone_ownership_boundary_valid=true
        local_zone_stage_complete=true
        live_unbound_configuration_mutated=false
        dns_queries_performed=false
        service_mutations=false
        live_state_unchanged=true
        persistent_mutation_scope=local_zone_stage_only
        action_17f_node_b_unbound_local_zone_stage_complete=true
    )
    local marker

    [[ "$ssh_status" -eq 0 ]]
    [[ ! -s "$error_file" ]]
    for marker in "${markers[@]}"; do
        require_one "$marker" "$output" || return 1
    done
    before_hash=$(value_for before_live_state_sha256 "$output")
    after_hash=$(value_for after_live_state_sha256 "$output")
    [[ "$before_hash" == "$accepted_live_state_sha256" ]]
    [[ "$after_hash" == "$before_hash" ]]
    if grep -Eq \
        'action_17f_rollback_|action_17f_prewrite_failure_|manual_intervention_required=true' \
        "$output" "$error_file"; then
        return 1
    fi
}

validate_failure() {
    local output=$1
    local error_file=$2
    local ssh_status=$3

    [[ "$ssh_status" -ne 0 ]]
    if grep -Fq 'manual_intervention_required=true' \
        "$output" "$error_file" ||
        grep -Fq 'action_17f_rollback_complete=false' \
            "$output" "$error_file"; then
        return 97
    fi
    if grep -Fq 'action_17f_mutation_started=true' "$output"; then
        require_one action_17f_rollback_started=true "$error_file" ||
            return 97
        require_one action_17f_rollback_complete=true "$error_file" ||
            return 97
        if grep -Fq 'action_17f_prewrite_failure_before_mutation=true' \
            "$error_file"; then
            return 97
        fi
    else
        require_one action_17f_prewrite_failure_before_mutation=true \
            "$error_file" || return 97
        if grep -Eq 'action_17f_rollback_' "$output" "$error_file"; then
            return 97
        fi
    fi
}

write_success_fixture() {
    local output=$1

    printf '%s\n' \
        action_17f_preflight_complete=true \
        "before_live_state_sha256=$accepted_live_state_sha256" \
        primary_stage_accepted=true \
        local_zone_stage_previously_absent=true \
        action_17f_mutation_started=true \
        "local_zone_candidate_sha256=$candidate_local_zone_sha256" \
        "local_zone_stage_path=$expected_stage" \
        local_zone_stage_owner_mode=root:root:700 \
        local_zone_file_owner_mode=root:root:600 \
        primary_stage_still_valid=true \
        combined_pair_parser_valid=true \
        local_zone_ownership_boundary_valid=true \
        local_zone_stage_complete=true \
        live_unbound_configuration_mutated=false \
        dns_queries_performed=false \
        service_mutations=false \
        "after_live_state_sha256=$accepted_live_state_sha256" \
        live_state_unchanged=true \
        persistent_mutation_scope=local_zone_stage_only \
        action_17f_node_b_unbound_local_zone_stage_complete=true \
        >"$output"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for value in \
        "$driver_sha256" \
        "$regression_sha256" \
        "$accepted_action17e_runner_sha256" \
        "$candidate_primary_sha256" \
        "$candidate_local_zone_sha256" \
        "$accepted_live_state_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    verify_sources
    "$driver" --self-test >/dev/null
    "$regression" --self-test >/dev/null
    printf 'action_17f_node_b_unbound_local_zone_stage_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_live_sources
    printf 'action_17f_node_b_unbound_local_zone_stage_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action17f-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    success=$contract_dir/success
    error_file=$contract_dir/error
    : >"$error_file"
    write_success_fixture "$success"
    validate_secret_free "$success" "$error_file"
    validate_success "$success" "$error_file" 0

    duplicate=$contract_dir/duplicate
    cp -- "$success" "$duplicate"
    printf 'local_zone_stage_complete=true\n' >>"$duplicate"
    if validate_success "$duplicate" "$error_file" 0; then
        printf 'Duplicate Action 17f marker was accepted.\n' >&2
        exit 1
    fi

    unsafe=$contract_dir/unsafe
    cp -- "$success" "$unsafe"
    printf '%s\n' 'local-data: "private.example. A 192.0.2.1"' >>"$unsafe"
    if validate_secret_free "$unsafe" "$error_file"; then
        printf 'Private directive output was accepted.\n' >&2
        exit 1
    fi

    rollback_output=$contract_dir/rollback-output
    rollback_error=$contract_dir/rollback-error
    printf 'action_17f_mutation_started=true\n' >"$rollback_output"
    printf '%s\n' \
        action_17f_rollback_started=true \
        action_17f_rollback_complete=true >"$rollback_error"
    validate_failure "$rollback_output" "$rollback_error" 1

    prewrite_output=$contract_dir/prewrite-output
    prewrite_error=$contract_dir/prewrite-error
    : >"$prewrite_output"
    printf 'action_17f_prewrite_failure_before_mutation=true\n' \
        >"$prewrite_error"
    validate_failure "$prewrite_output" "$prewrite_error" 1

    incomplete_error=$contract_dir/incomplete-error
    printf 'action_17f_rollback_started=true\n' >"$incomplete_error"
    set +e
    validate_failure "$rollback_output" "$incomplete_error" 1
    incomplete_status=$?
    set -e
    [[ "$incomplete_status" -eq 97 ]]
    printf 'action_17f_node_b_unbound_local_zone_stage_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_live_sources
work_dir=$(mktemp -d /tmp/caddy-action17f.XXXXXX)
readonly work_dir
readonly payload_dir="$work_dir/payload"
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
        printf 'action_17f_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_17f_local_cleanup_complete=true\n'
    exit "$status"
}

install -d -m 0700 "$payload_dir"
install -m 0600 \
    "$candidate_local_zone" "$payload_dir/pihole0-local-zone.conf"
[[ "$(file_hash "$payload_dir/pihole0-local-zone.conf")" == "$candidate_local_zone_sha256" ]]

remote_script=$(base64 -w 0 <"$driver")
printf -v remote_command \
    "sudo -n /bin/bash -c 'cd / && exec /bin/bash -c \"\$(printf %%s %s | base64 -d)\"'" \
    "$remote_script"
ssh_status=0
set +e
tar -C "$payload_dir" -cf - pihole0-local-zone.conf |
    ssh -T \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o "HostKeyAlias=$expected_host_alias" \
        -o StrictHostKeyChecking=yes \
        "$expected_target" \
        "$remote_command" >"$remote_output" 2>"$remote_error"
pipeline_result="$? ${PIPESTATUS[*]}"
set -e
read -r pipeline_status tar_status ssh_status <<<"$pipeline_result"

cat "$remote_output"
cat "$remote_error" >&2
printf 'tar_exit_status=%s\n' "$tar_status"
printf 'ssh_exit_status=%s\n' "$ssh_status"
printf 'pipeline_exit_status=%s\n' "$pipeline_status"
if ! validate_secret_free "$remote_output" "$remote_error"; then
    printf 'Unsafe Action 17f output detected.\n' >&2
    finish 97
fi
if [[ "$pipeline_status" -eq 0 &&
    "$tar_status" -eq 0 && "$ssh_status" -eq 0 ]]; then
    if ! validate_success "$remote_output" "$remote_error" "$ssh_status"; then
        printf 'Action 17f success contract failed.\n' >&2
        finish 97
    fi
    printf 'action_17f_node_b_unbound_local_zone_stage_accepted=true\n'
    finish 0
fi

set +e
validate_failure "$remote_output" "$remote_error" "$ssh_status"
failure_validation_status=$?
set -e
if [[ "$failure_validation_status" -eq 97 ]]; then
    printf 'Action 17f failure evidence is incomplete.\n' >&2
    finish 97
fi
printf 'action_17f_node_b_unbound_local_zone_stage_accepted=false\n'
finish "$pipeline_status"
