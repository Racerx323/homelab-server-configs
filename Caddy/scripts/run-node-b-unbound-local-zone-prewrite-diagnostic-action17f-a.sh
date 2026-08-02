#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=f380b441aad02b981669d8b251bae67633c49d8769d2e424e20c52b6c8cd3081
readonly regression_sha256=0a327ca94ecd4802bca8e5cc16f32404da1897f51e214d44a826593502032f3a
readonly failed_runner_sha256=700097f301c49bfef34b60dc6fdeb4e8c0b03282f2ccf7831fa306a930fe7c33
readonly failed_driver_sha256=916f8b8a109494523906d189f8cabec834ccf40fd04a38cb5686f355f3aee631
readonly accepted_live_state_sha256=3a05c0487101f3b44f8e5ba41a4a74713d07cddc369542f04d4a8b1f417cb824
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly inspector="$script_dir/diagnose-node-b-unbound-local-zone-prewrite-action17f-a.sh"
readonly regression="$caddy_root/tests/action17f-a-node-b-unbound-prewrite-diagnostic-regression.sh"
readonly failed_runner="$script_dir/run-node-b-unbound-local-zone-stage-action17f.sh"
readonly failed_driver="$script_dir/stage-node-b-unbound-local-zone-action17f.sh"

readonly -a command_labels=(
    command_awk_available
    command_base64_available
    command_cat_available
    command_chmod_available
    command_chown_available
    command_find_available
    command_grep_available
    command_hostname_available
    command_install_available
    command_mapfile_available
    command_mktemp_available
    command_mv_available
    command_readlink_available
    command_rm_available
    command_sha256sum_available
    command_sort_available
    command_stat_available
    command_systemctl_available
    command_tar_available
    command_touch_available
    command_unbound-checkconf_available
    command_wc_available
    command_xargs_available
)
readonly -a state_labels=(
    uid_is_root
    working_directory_is_root
    hostname_matches
    live_root_regular
    live_root_hash_matches
    live_primary_regular
    live_primary_hash_matches
    live_primary_metadata_matches
    live_local_zone_absent
    primary_stage_directory_valid
    primary_stage_metadata_matches
    primary_stage_entry_set_matches
    primary_complete_file_valid
    primary_manifest_file_valid
    primary_candidate_file_valid
    primary_meta_file_valid
    primary_files_metadata_match
    primary_complete_empty
    primary_candidate_hash_matches
    primary_manifest_content_matches
    primary_manifest_check_passes
    primary_meta_content_matches
    local_zone_stage_absent
    transaction_stage_count_zero
    unbound_active
    pihole_ftl_active
    live_checkconf_valid
    live_state_one_collected
    live_state_two_collected
    live_state_one_matches
    live_state_two_matches
    live_state_snapshots_stable
)
readonly -a assertion_labels=("${command_labels[@]}" "${state_labels[@]}")
readonly -a required_prefixes=(
    action_17f_a_remote_reached
    required_command_count
    missing_command_count
    missing_commands_b64
    effective_uid_status
    effective_uid
    working_directory_status
    working_directory_is_root
    hostname_status
    hostname_b64
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
    transaction_stage_count
    unbound_active_status
    unbound_active
    pihole_ftl_active_status
    pihole_ftl_active
    live_checkconf_status
    live_state_one_status
    live_state_one_sha256
    live_state_two_status
    live_state_two_sha256
    prewrite_assertion_count
    prewrite_failed_assertion_count
    action_17f_a_conclusion
    remote_paths_created
    dns_queries_performed
    dns_configuration_mutations
    service_mutations
    persistent_mutations
    action_17f_a_node_b_prewrite_diagnostic_complete
)

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
    verify_file "$inspector" "$inspector_sha256"
    verify_file "$regression" "$regression_sha256"
    verify_file "$failed_runner" "$failed_runner_sha256"
    verify_file "$failed_driver" "$failed_driver_sha256"
    bash -n "$inspector" "$regression" "$failed_runner" "$failed_driver"
}

verify_live_sources() {
    local path

    verify_sources
    for path in "$inspector" "$regression" "$failed_runner" "$failed_driver"; do
        [[ "$(stat -c '%U:%G:%a' "$path")" == aaron:aaron:755 ]]
    done
}

value_for() {
    local prefix=$1
    local transcript=$2
    local record

    [[ "$(grep -Ec "^${prefix}=" "$transcript")" -eq 1 ]] || return 1
    record=$(grep -E "^${prefix}=" "$transcript")
    printf '%s\n' "${record#*=}"
}

require_value() {
    local prefix=$1
    local expected=$2
    local transcript=$3

    [[ "$(value_for "$prefix" "$transcript")" == "$expected" ]]
}

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=|private-domain:|local-data(-ptr)?:' \
        "$@"
}

validate_transcript() {
    local transcript=$1
    local prefix value
    local false_count=0 command_false_count=0
    local expected_conclusion expected_pwd
    local state_one_hash state_two_hash state_one_status state_two_status

    [[ "${#assertion_labels[@]}" -eq 55 ]]
    for prefix in "${required_prefixes[@]}"; do
        [[ "$(grep -Ec "^${prefix}=" "$transcript")" -eq 1 ]] || return 1
    done
    for prefix in "${assertion_labels[@]}"; do
        value=$(value_for "prewrite_${prefix}" "$transcript") || return 1
        [[ "$value" == true || "$value" == false ]] || return 1
        if [[ "$value" == false ]]; then
            ((false_count += 1))
        fi
    done
    for prefix in "${command_labels[@]}"; do
        if [[ "$(value_for "prewrite_${prefix}" "$transcript")" == false ]]; then
            ((command_false_count += 1))
        fi
    done

    require_value action_17f_a_remote_reached true "$transcript"
    require_value required_command_count 23 "$transcript"
    require_value missing_command_count "$command_false_count" "$transcript"
    [[ "$(value_for missing_commands_b64 "$transcript")" =~ ^[A-Za-z0-9+/]*={0,2}$ ]]
    require_value prewrite_assertion_count 55 "$transcript"
    require_value prewrite_failed_assertion_count "$false_count" "$transcript"
    expected_conclusion=all_prewrite_prerequisites_pass
    ((false_count)) && expected_conclusion=prewrite_prerequisite_mismatch
    require_value action_17f_a_conclusion "$expected_conclusion" "$transcript"

    expected_pwd=$(value_for prewrite_working_directory_is_root "$transcript")
    require_value working_directory_is_root "$expected_pwd" "$transcript"
    require_value remote_paths_created false "$transcript"
    require_value dns_queries_performed false "$transcript"
    require_value dns_configuration_mutations false "$transcript"
    require_value service_mutations false "$transcript"
    require_value persistent_mutations false "$transcript"
    require_value action_17f_a_node_b_prewrite_diagnostic_complete true \
        "$transcript"

    for prefix in \
        effective_uid_status effective_uid working_directory_status \
        hostname_status primary_manifest_check_status transaction_stage_count \
        unbound_active_status pihole_ftl_active_status live_checkconf_status \
        live_state_one_status live_state_two_status; do
        [[ "$(value_for "$prefix" "$transcript")" =~ ^[0-9]+$ ]] || return 1
    done
    for prefix in hostname_b64 live_root_sha256 live_primary_sha256 \
        primary_candidate_sha256 live_state_one_sha256 \
        live_state_two_sha256; do
        [[ "$(value_for "$prefix" "$transcript")" =~ ^([0-9a-f]{64}|[A-Za-z0-9+/]*={0,2}|unavailable)$ ]] ||
            return 1
    done

    state_one_hash=$(value_for live_state_one_sha256 "$transcript")
    state_two_hash=$(value_for live_state_two_sha256 "$transcript")
    state_one_status=$(value_for live_state_one_status "$transcript")
    state_two_status=$(value_for live_state_two_status "$transcript")
    require_value prewrite_live_state_one_collected \
        "$([[ "$state_one_status" == 0 ]] && printf true || printf false)" \
        "$transcript"
    require_value prewrite_live_state_two_collected \
        "$([[ "$state_two_status" == 0 ]] && printf true || printf false)" \
        "$transcript"
    require_value prewrite_live_state_one_matches \
        "$([[ "$state_one_hash" == "$accepted_live_state_sha256" ]] && printf true || printf false)" \
        "$transcript"
    require_value prewrite_live_state_two_matches \
        "$([[ "$state_two_hash" == "$accepted_live_state_sha256" ]] && printf true || printf false)" \
        "$transcript"
    require_value prewrite_live_state_snapshots_stable \
        "$([[ "$state_one_hash" == "$state_two_hash" ]] && printf true || printf false)" \
        "$transcript"
}

write_fixture() {
    local destination=$1
    local false_label=${2:-}
    local label value false_count=0
    local conclusion=all_prewrite_prerequisites_pass

    printf '%s\n' \
        action_17f_a_remote_reached=true \
        required_command_count=23 \
        missing_command_count=0 \
        missing_commands_b64= \
        effective_uid_status=0 \
        effective_uid=0 \
        working_directory_status=0 \
        working_directory_is_root=true \
        hostname_status=0 \
        hostname_b64=ajEtc3ZwaWhvbGUwMA== \
        live_root_state=regular \
        live_root_sha256=8808b474175ff8eeebecbf407f9091fd73f65c4a43a6ee212e8ae2d9f80778f8 \
        live_primary_state=regular \
        live_primary_sha256=017aa2556346c93a64a3571dcb49046fb858edd358937339bc5f7e60d145fac7 \
        live_primary_metadata=root:root:644:34342 \
        live_local_zone_state=absent \
        primary_stage_state=directory \
        primary_stage_metadata=root:root:700 \
        primary_candidate_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8 \
        primary_manifest_check_status=0 \
        local_zone_stage_state=absent \
        transaction_stage_count=0 \
        unbound_active_status=0 \
        unbound_active=active \
        pihole_ftl_active_status=0 \
        pihole_ftl_active=active \
        live_checkconf_status=0 \
        live_state_one_status=0 \
        "live_state_one_sha256=$accepted_live_state_sha256" \
        live_state_two_status=0 \
        "live_state_two_sha256=$accepted_live_state_sha256" \
        >"$destination"
    for label in "${assertion_labels[@]}"; do
        value=true
        if [[ "$label" == "$false_label" ]]; then
            value=false
            ((false_count += 1))
        fi
        printf 'prewrite_%s=%s\n' "$label" "$value"
    done >>"$destination"
    if ((false_count)); then
        conclusion=prewrite_prerequisite_mismatch
        if [[ "$false_label" == working_directory_is_root ]]; then
            sed -i 's/^working_directory_is_root=true$/working_directory_is_root=false/' \
                "$destination"
        fi
    fi
    printf '%s\n' \
        prewrite_assertion_count=55 \
        "prewrite_failed_assertion_count=$false_count" \
        "action_17f_a_conclusion=$conclusion" \
        remote_paths_created=false \
        dns_queries_performed=false \
        dns_configuration_mutations=false \
        service_mutations=false \
        persistent_mutations=false \
        action_17f_a_node_b_prewrite_diagnostic_complete=true \
        >>"$destination"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_sources
    [[ "${#assertion_labels[@]}" -eq 55 ]]
    grep -Fq \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" \
        "$0"
    printf 'action_17f_a_node_b_unbound_prewrite_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_live_sources
    printf 'action_17f_a_node_b_unbound_prewrite_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action17f-a-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    all_pass=$contract_dir/all-pass
    mismatch=$contract_dir/mismatch
    write_fixture "$all_pass"
    write_fixture "$mismatch" primary_meta_content_matches
    validate_transcript "$all_pass"
    validate_transcript "$mismatch"

    duplicate=$contract_dir/duplicate
    cp -- "$all_pass" "$duplicate"
    printf 'prewrite_uid_is_root=true\n' >>"$duplicate"
    if validate_transcript "$duplicate"; then
        printf 'Duplicate Action 17f-a assertion was accepted.\n' >&2
        exit 1
    fi

    unsafe=$contract_dir/unsafe
    cp -- "$all_pass" "$unsafe"
    printf '%s\n' 'local-data: "private.example. A 192.0.2.1"' >>"$unsafe"
    if validate_secret_free "$unsafe"; then
        printf 'Private Action 17f-a output was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17f_a_node_b_unbound_prewrite_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_live_sources
"$regression" --production-test >/dev/null
work_dir=$(mktemp -d /tmp/caddy-action17f-a.XXXXXX)
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
        printf 'action_17f_a_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_17f_a_local_cleanup_complete=true\n'
    exit "$status"
}

ssh_status=0
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o "HostKeyAlias=$expected_host_alias" \
    -o StrictHostKeyChecking=yes \
    "$expected_target" \
    "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" \
    <"$inspector" >"$remote_output" 2>"$remote_error" || ssh_status=$?

cat "$remote_output"
cat "$remote_error" >&2
printf 'ssh_exit_status=%s\n' "$ssh_status"
if [[ "$ssh_status" -ne 0 || -s "$remote_error" ]] ||
    ! validate_secret_free "$remote_output" "$remote_error" ||
    ! validate_transcript "$remote_output"; then
    printf 'Action 17f-a evidence contract failed.\n' >&2
    finish 97
fi
printf 'action_17f_a_conclusion=%s\n' \
    "$(value_for action_17f_a_conclusion "$remote_output")"
printf 'action_17f_a_node_b_prewrite_diagnostic_accepted=true\n'
finish 0
