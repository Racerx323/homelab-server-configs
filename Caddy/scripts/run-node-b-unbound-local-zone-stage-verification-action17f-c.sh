#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=836097c5a03939d7c7674d7486dd8f0d52b6217bc96eebf6376b3ed7bf367ca9
readonly regression_sha256=711315c95a1a5f7826e58ff888b347f6a9a3896625fde3917020b6b7285c5df4
readonly executed_action17f_runner_sha256=7abff23f8227e2c059d02484eb83f28c9aabd11f6054d12caff7adf5496f1f1b
readonly collision_checker_sha256=78b46fcdc6c4ca6b4cfe0121c347e0e101c472d723a891aac2dea7f23f085cd8
readonly accepted_live_state_sha256=3a05c0487101f3b44f8e5ba41a4a74713d07cddc369542f04d4a8b1f417cb824
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly candidate_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co
readonly expected_assertion_count=57

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly inspector="$script_dir/inspect-node-b-unbound-local-zone-stage-action17f-c.sh"
readonly regression="$caddy_root/tests/action17f-c-retained-stage-regression.sh"
readonly executed_action17f_runner="$script_dir/run-node-b-unbound-local-zone-stage-action17f-normalized-retry.sh"
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
    verify_file "$inspector" "$inspector_sha256"
    verify_file "$regression" "$regression_sha256"
    verify_file \
        "$executed_action17f_runner" "$executed_action17f_runner_sha256"
    verify_file "$collision_checker" "$collision_checker_sha256"
    bash -n \
        "$inspector" "$regression" "$executed_action17f_runner" \
        "$collision_checker"
}

verify_live_sources() {
    local verified_source

    verify_sources
    for verified_source in \
        "$inspector" "$regression" "$executed_action17f_runner" \
        "$collision_checker"; do
        [[ "$(stat -c '%U:%G:%a' "$verified_source")" == aaron:aaron:755 ]]
    done
}

value_for() {
    local value_prefix=$1
    local value_transcript=$2
    local value_record

    [[ "$(grep -Ec "^${value_prefix}=" "$value_transcript")" -eq 1 ]] ||
        return 1
    value_record=$(grep -E "^${value_prefix}=" "$value_transcript")
    printf '%s\n' "${value_record#*=}"
}

require_value() {
    local required_prefix=$1
    local required_value=$2
    local required_transcript=$3

    [[ "$(value_for "$required_prefix" "$required_transcript")" == "$required_value" ]]
}

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=|private-domain:|local-data(-ptr)?:' \
        "$@"
}

classify_historical_wrapper_markers() {
    local historical_transcript_path=$1
    local no_query_count no_service_count

    no_query_count=$(
        grep -Ec '^dns_queries_performed=false$' \
            "$historical_transcript_path" || true
    )
    no_service_count=$(
        grep -Ec '^service_mutations=false$' \
            "$historical_transcript_path" || true
    )
    if [[ "$no_query_count" -eq 2 && "$no_service_count" -eq 2 ]]; then
        printf 'workstation_wrapper_advisory_duplicate_no_query_count=2\n'
        printf 'workstation_wrapper_advisory_duplicate_no_service_count=2\n'
        printf 'workstation_wrapper_advisory_non_blocking=true\n'
        return 0
    fi
    printf 'workstation_wrapper_advisory_non_blocking=false\n'
    return 1
}

validate_remote_transcript() {
    local remote_transcript_path=$1
    local assertion_lines unique_assertion_lines false_assertion_lines
    local required_prefix
    local -a required_prefixes=(
        action_17f_c_remote_reached
        required_command_count
        missing_commands
        effective_uid_status
        effective_uid
        working_directory_status
        working_directory
        hostname_status
        hostname
        live_root_state
        live_root_sha256
        live_primary_state
        live_primary_sha256
        live_primary_metadata
        live_local_zone_state
        primary_stage_state
        primary_stage_metadata
        primary_candidate_sha256
        primary_manifest_check_status
        local_zone_stage_state
        local_zone_stage_metadata
        local_zone_candidate_sha256
        local_zone_manifest_check_status
        transaction_stage_count
        unbound_active_status
        unbound_active
        pihole_ftl_active_status
        pihole_ftl_active
        live_checkconf_status
        combined_checkconf_status
        live_state_one_status
        live_state_one_sha256
        live_state_two_status
        live_state_two_sha256
        action_17f_c_assertion_count
        action_17f_c_failed_assertion_count
        action_17f_c_first_failure
        action_17f_c_conclusion
        remote_paths_created
        dns_queries_performed
        dns_configuration_mutations
        service_mutations
        persistent_mutations
        action_17f_c_remote_complete
    )

    for required_prefix in "${required_prefixes[@]}"; do
        [[ "$(grep -Ec "^${required_prefix}=" "$remote_transcript_path")" -eq 1 ]] ||
            return 1
    done

    assertion_lines=$(
        grep -Ec '^action_17f_c_assertion_[a-z0-9_]+=((true)|(false))$' \
            "$remote_transcript_path"
    )
    unique_assertion_lines=$(
        grep -E '^action_17f_c_assertion_[a-z0-9_]+=((true)|(false))$' \
            "$remote_transcript_path" |
            cut -d= -f1 |
            LC_ALL=C sort -u |
            wc -l
    )
    false_assertion_lines=$(
        grep -Ec '^action_17f_c_assertion_[a-z0-9_]+=false$' \
            "$remote_transcript_path" || true
    )
    [[ "$assertion_lines" -eq "$expected_assertion_count" ]] || return 1
    [[ "$unique_assertion_lines" -eq "$expected_assertion_count" ]] ||
        return 1
    [[ "$false_assertion_lines" -eq 0 ]] || return 1
    require_value action_17f_c_assertion_count \
        "$expected_assertion_count" "$remote_transcript_path" || return 1
    require_value action_17f_c_failed_assertion_count 0 \
        "$remote_transcript_path" || return 1
    require_value action_17f_c_first_failure none "$remote_transcript_path" ||
        return 1
    require_value action_17f_c_conclusion \
        retained_stage_and_node_b_continuity_verified \
        "$remote_transcript_path" || return 1

    require_value live_root_sha256 \
        8808b474175ff8eeebecbf407f9091fd73f65c4a43a6ee212e8ae2d9f80778f8 \
        "$remote_transcript_path" || return 1
    require_value live_primary_sha256 \
        017aa2556346c93a64a3571dcb49046fb858edd358937339bc5f7e60d145fac7 \
        "$remote_transcript_path" || return 1
    require_value primary_candidate_sha256 \
        "$candidate_primary_sha256" "$remote_transcript_path" || return 1
    require_value local_zone_candidate_sha256 \
        "$candidate_local_zone_sha256" "$remote_transcript_path" || return 1
    require_value live_state_one_sha256 \
        "$accepted_live_state_sha256" "$remote_transcript_path" || return 1
    require_value live_state_two_sha256 \
        "$accepted_live_state_sha256" "$remote_transcript_path" || return 1

    require_value remote_paths_created false "$remote_transcript_path" ||
        return 1
    require_value dns_queries_performed false "$remote_transcript_path" ||
        return 1
    require_value dns_configuration_mutations false "$remote_transcript_path" ||
        return 1
    require_value service_mutations false "$remote_transcript_path" ||
        return 1
    require_value persistent_mutations false "$remote_transcript_path" ||
        return 1
    require_value action_17f_c_remote_complete true "$remote_transcript_path" ||
        return 1
}

write_remote_fixture() {
    local fixture_destination=$1
    local fixture_false_label=${2:-}
    local fixture_index
    local fixture_false_count=0
    local fixture_first_failure=none
    local fixture_conclusion=retained_stage_and_node_b_continuity_verified

    printf '%s\n' \
        action_17f_c_remote_reached=true \
        required_command_count=14 \
        missing_commands=none \
        effective_uid_status=0 \
        effective_uid=0 \
        working_directory_status=0 \
        working_directory=/ \
        hostname_status=0 \
        hostname=j1-svpihole00 \
        live_root_state=regular \
        live_root_sha256=8808b474175ff8eeebecbf407f9091fd73f65c4a43a6ee212e8ae2d9f80778f8 \
        live_primary_state=regular \
        live_primary_sha256=017aa2556346c93a64a3571dcb49046fb858edd358937339bc5f7e60d145fac7 \
        live_primary_metadata=root:root:644:34342 \
        live_local_zone_state=absent \
        primary_stage_state=directory \
        primary_stage_metadata=root:root:700 \
        "primary_candidate_sha256=$candidate_primary_sha256" \
        primary_manifest_check_status=0 \
        local_zone_stage_state=directory \
        local_zone_stage_metadata=root:root:700 \
        "local_zone_candidate_sha256=$candidate_local_zone_sha256" \
        local_zone_manifest_check_status=0 \
        transaction_stage_count=0 \
        unbound_active_status=0 \
        unbound_active=active \
        pihole_ftl_active_status=0 \
        pihole_ftl_active=active \
        live_checkconf_status=0 \
        combined_checkconf_status=0 \
        live_state_one_status=0 \
        "live_state_one_sha256=$accepted_live_state_sha256" \
        live_state_two_status=0 \
        "live_state_two_sha256=$accepted_live_state_sha256" \
        >"$fixture_destination"

    for ((fixture_index = 1; fixture_index <= expected_assertion_count; fixture_index += 1)); do
        fixture_value=true
        if [[ "$fixture_false_label" == "fixture_${fixture_index}" ]]; then
            fixture_value=false
            fixture_false_count=1
            fixture_first_failure=$fixture_false_label
            fixture_conclusion=retained_stage_or_node_b_continuity_mismatch
        fi
        printf 'action_17f_c_assertion_fixture_%02d=%s\n' \
            "$fixture_index" "$fixture_value"
    done >>"$fixture_destination"

    printf '%s\n' \
        "action_17f_c_assertion_count=$expected_assertion_count" \
        "action_17f_c_failed_assertion_count=$fixture_false_count" \
        "action_17f_c_first_failure=$fixture_first_failure" \
        "action_17f_c_conclusion=$fixture_conclusion" \
        remote_paths_created=false \
        dns_queries_performed=false \
        dns_configuration_mutations=false \
        service_mutations=false \
        persistent_mutations=false \
        action_17f_c_remote_complete=true \
        >>"$fixture_destination"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_sources
    grep -Fq \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" \
        "$0"
    printf 'action_17f_c_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_live_sources
    printf 'action_17f_c_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_directory=$(mktemp -d /tmp/caddy-action17f-c-contract.XXXXXX)
    trap 'rm -rf -- "$contract_directory"' EXIT
    success_fixture="$contract_directory/success"
    mismatch_fixture="$contract_directory/mismatch"
    historical_fixture="$contract_directory/historical"
    triple_fixture="$contract_directory/triple"
    missing_fixture="$contract_directory/missing"
    unsafe_fixture="$contract_directory/unsafe"

    write_remote_fixture "$success_fixture"
    validate_remote_transcript "$success_fixture"
    write_remote_fixture "$mismatch_fixture" fixture_17
    if validate_remote_transcript "$mismatch_fixture"; then
        printf 'Action 17f-c mismatch fixture was accepted.\n' >&2
        exit 1
    fi

    printf '%s\n' \
        dns_queries_performed=false \
        service_mutations=false \
        dns_queries_performed=false \
        service_mutations=false \
        >"$historical_fixture"
    classify_historical_wrapper_markers "$historical_fixture" >/dev/null
    cp -- "$historical_fixture" "$triple_fixture"
    printf '%s\n' \
        dns_queries_performed=false \
        service_mutations=false \
        >>"$triple_fixture"
    if classify_historical_wrapper_markers "$triple_fixture" >/dev/null; then
        printf 'Unknown triple-marker transcript was accepted as advisory.\n' \
            >&2
        exit 1
    fi
    printf '%s\n' \
        dns_queries_performed=false \
        service_mutations=false \
        >"$missing_fixture"
    if classify_historical_wrapper_markers "$missing_fixture" >/dev/null; then
        printf 'Single-marker transcript was accepted as duplicate advisory.\n' \
            >&2
        exit 1
    fi

    cp -- "$success_fixture" "$unsafe_fixture"
    printf '%s\n' 'local-data: "private.example. A 192.0.2.1"' \
        >>"$unsafe_fixture"
    if validate_secret_free "$unsafe_fixture"; then
        printf 'Private Action 17f-c output was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17f_c_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_live_sources
"$regression" --production-test >/dev/null
work_directory=$(mktemp -d /tmp/caddy-action17f-c.XXXXXX)
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
        printf 'action_17f_c_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_17f_c_local_cleanup_complete=true\n'
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
    <"$inspector" >"$remote_output_path" 2>"$remote_error_path" ||
    ssh_status=$?

cat "$remote_output_path"
cat "$remote_error_path" >&2
printf 'ssh_exit_status=%s\n' "$ssh_status"
if [[ "$ssh_status" -ne 0 || -s "$remote_error_path" ]] ||
    ! validate_secret_free "$remote_output_path" "$remote_error_path" ||
    ! validate_remote_transcript "$remote_output_path"; then
    printf 'Action 17f-c authoritative evidence contract failed.\n' >&2
    finish 97
fi

printf 'workstation_wrapper_advisory_non_blocking=false\n'
printf 'action_17f_c_node_b_continuity_accepted=true\n'
finish 0
