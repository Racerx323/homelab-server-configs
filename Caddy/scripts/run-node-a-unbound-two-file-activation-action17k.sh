#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly driver_sha256=2fb35e9129c0e12773500c669ca9f5e0a9bdd13c79bf65f4afe3f7ccf3fb33f0
readonly collision_checker_sha256=78b46fcdc6c4ca6b4cfe0121c347e0e101c472d723a891aac2dea7f23f085cd8
readonly expected_target=pi@10.1.0.53
readonly expected_host_alias=pihole0.local.theama.co
readonly expected_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly expected_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly expected_backup_path=/var/backups/caddy-ha/action17k-node-a-unbound-two-file
readonly expected_check_count=122

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly driver="$script_dir/activate-node-a-unbound-two-file-action17k.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_file() {
    local verified_path=$1
    local expected_hash=$2

    [[ -f "$verified_path" && ! -L "$verified_path" ]]
    [[ "$(file_hash "$verified_path")" == "$expected_hash" ]]
}

verify_sources() {
    verify_file "$driver" "$driver_sha256"
    verify_file "$collision_checker" "$collision_checker_sha256"
    bash -n "$driver" "$collision_checker"
    "$driver" --self-test >/dev/null
    "$collision_checker" "$driver" "$0" >/dev/null
}

verify_live_sources() {
    local source_path

    verify_sources
    for source_path in "$driver" "$collision_checker" "$0"; do
        [[ -f "$source_path" && ! -L "$source_path" ]]
        [[ "$(stat -c '%U:%G:%a' "$source_path")" == aaron:aaron:755 ]]
    done
}

value_for() {
    local value_key=$1
    local transcript_path=$2
    local value_record

    [[ "$(grep -Ec "^${value_key}=" "$transcript_path")" -eq 1 ]] ||
        return 1
    value_record=$(grep -E "^${value_key}=" "$transcript_path")
    printf '%s\n' "${value_record#*=}"
}

require_value() {
    local required_key=$1
    local required_value=$2
    local transcript_path=$3

    [[ "$(value_for "$required_key" "$transcript_path")" == "$required_value" ]]
}

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=|private-domain:|local-data(-ptr)?:' \
        "$@"
}

validate_success_transcript() {
    local transcript_path=$1
    local check_count unique_check_count

    check_count=$(
        grep -Ec '^action_17k_check_[a-z0-9_]+=true$' "$transcript_path"
    )
    unique_check_count=$(
        grep -E '^action_17k_check_[a-z0-9_]+=true$' "$transcript_path" |
            cut -d= -f1 |
            LC_ALL=C sort -u |
            wc -l
    )
    [[ "$check_count" -eq "$expected_check_count" ]] || return 1
    [[ "$check_count" -eq "$unique_check_count" ]] || return 1
    if grep -Eq '^action_17k_check_[a-z0-9_]+=false$' "$transcript_path"; then
        return 1
    fi
    if grep -Eq '^action_17k_failed_(step|observed)=' "$transcript_path"; then
        return 1
    fi
    if grep -Eq '^action_17k_(rollback_started|rollback_complete|prewrite_failure_before_mutation)=' \
        "$transcript_path"; then
        return 1
    fi

    require_value action_17k_preflight_complete true "$transcript_path" ||
        return 1
    require_value action_17k_live_primary_name pihole.conf "$transcript_path" ||
        return 1
    require_value action_17k_live_local_zone_name \
        pihole-local-zone.conf "$transcript_path" || return 1
    require_value action_17k_mutation_started true "$transcript_path" ||
        return 1
    require_value action_17k_live_switch_started true "$transcript_path" ||
        return 1
    require_value action_17k_reload_attempted true "$transcript_path" ||
        return 1
    require_value action_17k_reload_status 0 "$transcript_path" || return 1
    require_value action_17k_backup_path \
        "$expected_backup_path" "$transcript_path" || return 1
    require_value action_17k_primary_sha256 \
        "$expected_primary_sha256" "$transcript_path" || return 1
    require_value action_17k_local_zone_sha256 \
        "$expected_local_zone_sha256" "$transcript_path" || return 1
    require_value action_17k_unbound_pid_preserved true "$transcript_path" ||
        return 1
    require_value action_17k_ftl_pid_preserved true "$transcript_path" ||
        return 1
    require_value action_17k_live_names_correct true "$transcript_path" ||
        return 1
    require_value action_17k_legacy_live_name_absent true "$transcript_path" ||
        return 1
    require_value action_17k_stages_preserved true "$transcript_path" ||
        return 1
    require_value action_17k_dns_queries_performed true "$transcript_path" ||
        return 1
    require_value action_17k_service_mutation \
        unbound_reload_only "$transcript_path" || return 1
    require_value action_17k_persistent_mutation_scope \
        two_live_files_and_backup "$transcript_path" || return 1
    require_value action_17k_node_a_unbound_activation_complete \
        true "$transcript_path" || return 1
}

write_success_fixture() {
    local fixture_path=$1
    local fixture_index

    for ((fixture_index = 1; fixture_index <= expected_check_count; fixture_index += 1)); do
        printf 'action_17k_check_fixture_%02d=true\n' "$fixture_index"
    done >"$fixture_path"
    printf '%s\n' \
        action_17k_preflight_complete=true \
        action_17k_live_primary_name=pihole.conf \
        action_17k_live_local_zone_name=pihole-local-zone.conf \
        action_17k_mutation_started=true \
        action_17k_live_switch_started=true \
        action_17k_reload_attempted=true \
        action_17k_reload_status=0 \
        "action_17k_backup_path=$expected_backup_path" \
        "action_17k_primary_sha256=$expected_primary_sha256" \
        "action_17k_local_zone_sha256=$expected_local_zone_sha256" \
        action_17k_unbound_pid_preserved=true \
        action_17k_ftl_pid_preserved=true \
        action_17k_live_names_correct=true \
        action_17k_legacy_live_name_absent=true \
        action_17k_stages_preserved=true \
        action_17k_dns_queries_performed=true \
        action_17k_service_mutation=unbound_reload_only \
        action_17k_persistent_mutation_scope=two_live_files_and_backup \
        action_17k_node_a_unbound_activation_complete=true \
        >>"$fixture_path"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_sources
    grep -Fq \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" "$0"
    printf 'action_17k_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_live_sources
    printf 'action_17k_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_directory=$(mktemp -d /tmp/caddy-action17k-contract.XXXXXX)
    trap 'rm -rf -- "$contract_directory"' EXIT
    success_fixture="$contract_directory/success"
    false_fixture="$contract_directory/false"
    duplicate_fixture="$contract_directory/duplicate"
    unsafe_fixture="$contract_directory/unsafe"

    write_success_fixture "$success_fixture"
    validate_success_transcript "$success_fixture"
    cp -- "$success_fixture" "$false_fixture"
    printf 'action_17k_check_injected=false\n' >>"$false_fixture"
    if validate_success_transcript "$false_fixture"; then
        printf 'Action 17k false-check fixture was accepted.\n' >&2
        exit 1
    fi
    cp -- "$success_fixture" "$duplicate_fixture"
    printf 'action_17k_check_fixture_01=true\n' >>"$duplicate_fixture"
    if validate_success_transcript "$duplicate_fixture"; then
        printf 'Action 17k duplicate-check fixture was accepted.\n' >&2
        exit 1
    fi
    cp -- "$success_fixture" "$unsafe_fixture"
    printf '%s\n' 'local-data: "private.example. A 192.0.2.1"' \
        >>"$unsafe_fixture"
    if validate_secret_free "$unsafe_fixture"; then
        printf 'Action 17k unsafe fixture was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17k_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_live_sources
work_directory=$(mktemp -d /tmp/caddy-action17k.XXXXXX)
readonly work_directory
readonly remote_output_path="$work_directory/remote.out"
readonly remote_error_path="$work_directory/remote.err"

cleanup() {
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

finish() {
    local finish_status=$1

    cleanup
    trap - EXIT
    if [[ -e "$work_directory" || -L "$work_directory" ]]; then
        printf 'action_17k_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_17k_local_cleanup_complete=true\n'
    exit "$finish_status"
}

ssh_status=0
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o "HostKeyAlias=$expected_host_alias" \
    -o StrictHostKeyChecking=yes \
    "$expected_target" \
    "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" \
    <"$driver" >"$remote_output_path" 2>"$remote_error_path" ||
    ssh_status=$?

cat "$remote_output_path"
cat "$remote_error_path" >&2
printf 'ssh_exit_status=%s\n' "$ssh_status"

if ! validate_secret_free "$remote_output_path" "$remote_error_path"; then
    printf 'Action 17k output safety contract failed.\n' >&2
    finish 97
fi
if [[ "$ssh_status" -eq 0 && ! -s "$remote_error_path" ]] &&
    validate_success_transcript "$remote_output_path"; then
    printf 'action_17k_node_a_unbound_activation_accepted=true\n'
    finish 0
fi
if [[ "$ssh_status" -eq 125 ]] &&
    grep -Fxq action_17k_rollback_complete=false "$remote_error_path" &&
    grep -Fxq manual_intervention_required=true "$remote_error_path"; then
    printf 'action_17k_manual_intervention_required=true\n' >&2
    finish 125
fi
if grep -Fxq action_17k_rollback_complete=true "$remote_error_path"; then
    printf 'action_17k_rollback_accepted=true\n' >&2
    finish "$ssh_status"
fi
if grep -Fxq action_17k_prewrite_failure_before_mutation=true \
    "$remote_error_path"; then
    printf 'action_17k_prewrite_failure_accepted=true\n' >&2
    finish "$ssh_status"
fi

printf 'Action 17k evidence or rollback contract failed.\n' >&2
finish 97
