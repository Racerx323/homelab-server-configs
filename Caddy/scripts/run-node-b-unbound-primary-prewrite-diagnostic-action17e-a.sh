#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=4d61418345542d51b72a7b9dfe48ce84cbca4c4c356db601a1baf6c9331dd29e
readonly regression_sha256=a18751cd0085412c7c025681e5088ba68deaa17fc2800d8225104c1b4efb8aaf
readonly failed_runner_sha256=d38a963934d3e063481e8f81a189fe432cd7002683ae6349d341cbde27c0e5e5
readonly failed_driver_sha256=b67d9fe11d535c1767a1a70c8fe334bf74e007ec2915dd19ca254e72bb99121b
readonly accepted_action17d_state_sha256=31862f7b0f86a6cddc9057501fffeff872bc3747a0144bb7d062fddcced9992c
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly inspector="$script_dir/diagnose-node-b-unbound-primary-prewrite-action17e-a.sh"
readonly regression="$caddy_root/tests/action17e-a-node-b-unbound-prewrite-diagnostic-regression.sh"
readonly failed_runner="$script_dir/run-node-b-unbound-primary-stage-action17e.sh"
readonly failed_driver="$script_dir/stage-node-b-unbound-primary-action17e.sh"

readonly -a assertion_prefixes=(
    prewrite_uid_is_root
    prewrite_working_directory_is_root
    prewrite_hostname_matches
    prewrite_live_root_regular
    prewrite_live_root_hash_matches
    prewrite_live_primary_regular
    prewrite_live_primary_hash_matches
    prewrite_live_primary_metadata_matches
    prewrite_live_local_zone_absent
    prewrite_action17d_snapshot_one_collected
    prewrite_action17d_snapshot_two_collected
    prewrite_action17d_snapshot_one_matches
    prewrite_action17d_snapshot_two_matches
    prewrite_action17d_snapshots_stable
    prewrite_unbound_active
    prewrite_pihole_ftl_active
    prewrite_live_checkconf_valid
    prewrite_primary_stage_absent
    prewrite_local_zone_stage_absent
    prewrite_transaction_stage_count_zero
    prewrite_live_state_one_collected
    prewrite_live_state_two_collected
    prewrite_live_state_snapshots_stable
)
readonly -a required_prefixes=(
    action_17e_a_remote_reached
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
    action17d_snapshot_one_status
    action17d_snapshot_one_sha256
    action17d_snapshot_two_status
    action17d_snapshot_two_sha256
    unbound_active_status
    unbound_active
    pihole_ftl_active_status
    pihole_ftl_active
    live_checkconf_status
    live_checkconf_output_sha256
    primary_stage_state
    local_zone_stage_state
    transaction_stage_count
    live_state_one_status
    live_state_one_sha256
    live_state_two_status
    live_state_two_sha256
    prewrite_assertion_count
    prewrite_failed_assertion_count
    action_17e_a_conclusion
    remote_paths_created
    dns_queries_performed
    dns_configuration_mutations
    service_mutations
    persistent_mutations
    action_17e_a_node_b_prewrite_diagnostic_complete
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
    bash -n "$inspector" "$regression"
}

verify_live_sources() {
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

require_boolean() {
    local value

    value=$(value_for "$1" "$2") || return 1
    [[ "$value" == true || "$value" == false ]]
}

derive_conclusion() {
    local transcript=$1
    local failed

    if ! require_value prewrite_action17d_snapshot_one_collected true \
        "$transcript" ||
        ! require_value prewrite_action17d_snapshot_two_collected true \
            "$transcript" ||
        ! require_value prewrite_action17d_snapshots_stable true \
            "$transcript"; then
        printf 'action17d_snapshot_collection_unstable\n'
        return
    fi
    if ! require_value prewrite_live_state_one_collected true "$transcript" ||
        ! require_value prewrite_live_state_two_collected true "$transcript"; then
        printf 'live_state_collection_failed\n'
        return
    fi
    if ! require_value prewrite_live_state_snapshots_stable true "$transcript"; then
        printf 'live_state_collection_unstable\n'
        return
    fi
    failed=$(value_for prewrite_failed_assertion_count "$transcript")
    if [[ "$failed" -ne 0 ]]; then
        printf 'prewrite_assertion_mismatch\n'
    else
        printf 'all_prewrite_assertions_pass_and_collectors_stable\n'
    fi
}

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=|private-domain:|local-data(-ptr)?:' \
        "$@"
}

validate_transcript() {
    local transcript=$1
    local prefix value false_count expected_conclusion

    if grep -Evq '^[a-z0-9_]+=[A-Za-z0-9_:+./=-]*$' "$transcript"; then
        return 1
    fi
    for prefix in "${required_prefixes[@]}" "${assertion_prefixes[@]}"; do
        [[ "$(grep -Ec "^${prefix}=" "$transcript")" -eq 1 ]] || return 1
    done
    for prefix in "${assertion_prefixes[@]}"; do
        require_boolean "$prefix" "$transcript" || return 1
    done
    for prefix in \
        working_directory_is_root \
        remote_paths_created \
        dns_queries_performed \
        dns_configuration_mutations \
        service_mutations \
        persistent_mutations; do
        require_boolean "$prefix" "$transcript" || return 1
    done

    require_value action_17e_a_remote_reached true "$transcript"
    require_value prewrite_assertion_count \
        "${#assertion_prefixes[@]}" "$transcript"
    require_value remote_paths_created false "$transcript"
    require_value dns_queries_performed false "$transcript"
    require_value dns_configuration_mutations false "$transcript"
    require_value service_mutations false "$transcript"
    require_value persistent_mutations false "$transcript"
    require_value \
        action_17e_a_node_b_prewrite_diagnostic_complete true "$transcript"

    for prefix in \
        live_root_sha256 \
        live_primary_sha256 \
        action17d_snapshot_one_sha256 \
        action17d_snapshot_two_sha256 \
        live_checkconf_output_sha256 \
        live_state_one_sha256 \
        live_state_two_sha256; do
        value=$(value_for "$prefix" "$transcript")
        [[ "$value" == unavailable || "$value" =~ ^[0-9a-f]{64}$ ]] ||
            return 1
    done
    for prefix in \
        effective_uid_status \
        effective_uid \
        working_directory_status \
        hostname_status \
        action17d_snapshot_one_status \
        action17d_snapshot_two_status \
        unbound_active_status \
        pihole_ftl_active_status \
        live_checkconf_status \
        transaction_stage_count \
        live_state_one_status \
        live_state_two_status \
        prewrite_assertion_count \
        prewrite_failed_assertion_count; do
        [[ "$(value_for "$prefix" "$transcript")" =~ ^[0-9]+$ ]] ||
            return 1
    done

    false_count=0
    for prefix in "${assertion_prefixes[@]}"; do
        if [[ "$(value_for "$prefix" "$transcript")" == false ]]; then
            false_count=$((false_count + 1))
        fi
    done
    require_value prewrite_failed_assertion_count \
        "$false_count" "$transcript"
    expected_conclusion=$(derive_conclusion "$transcript")
    require_value action_17e_a_conclusion \
        "$expected_conclusion" "$transcript"
}

write_fixture() {
    local destination=$1
    local pwd_assertion=$2
    local failed_count=$3
    local conclusion=$4
    local prefix

    printf '%s\n' \
        action_17e_a_remote_reached=true \
        effective_uid_status=0 \
        effective_uid=0 \
        working_directory_status=0 \
        "working_directory_is_root=$pwd_assertion" \
        hostname_status=0 \
        hostname_b64=ajEtc3ZwaWhvbGUwMA== \
        live_root_state=regular \
        live_root_sha256=8808b474175ff8eeebecbf407f9091fd73f65c4a43a6ee212e8ae2d9f80778f8 \
        live_primary_state=regular \
        live_primary_sha256=017aa2556346c93a64a3571dcb49046fb858edd358937339bc5f7e60d145fac7 \
        live_primary_metadata=root:root:644:34342 \
        live_local_zone_state=absent \
        action17d_snapshot_one_status=0 \
        "action17d_snapshot_one_sha256=$accepted_action17d_state_sha256" \
        action17d_snapshot_two_status=0 \
        "action17d_snapshot_two_sha256=$accepted_action17d_state_sha256" \
        unbound_active_status=0 \
        unbound_active=active \
        pihole_ftl_active_status=0 \
        pihole_ftl_active=active \
        live_checkconf_status=0 \
        live_checkconf_output_sha256=0587b1b39305ac2174a276e279821294ae8dfe6756b8d5ba844703f19e4b2b73 \
        primary_stage_state=absent \
        local_zone_stage_state=absent \
        transaction_stage_count=0 \
        live_state_one_status=0 \
        live_state_one_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        live_state_two_status=0 \
        live_state_two_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        >"$destination"
    for prefix in "${assertion_prefixes[@]}"; do
        if [[ "$prefix" == prewrite_working_directory_is_root ]]; then
            printf '%s=%s\n' "$prefix" "$pwd_assertion"
        else
            printf '%s=true\n' "$prefix"
        fi
    done >>"$destination"
    printf '%s\n' \
        "prewrite_assertion_count=${#assertion_prefixes[@]}" \
        "prewrite_failed_assertion_count=$failed_count" \
        "action_17e_a_conclusion=$conclusion" \
        remote_paths_created=false \
        dns_queries_performed=false \
        dns_configuration_mutations=false \
        service_mutations=false \
        persistent_mutations=false \
        action_17e_a_node_b_prewrite_diagnostic_complete=true \
        >>"$destination"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "${#assertion_prefixes[@]}" -eq 23 ]]
    for value in \
        "$inspector_sha256" \
        "$regression_sha256" \
        "$failed_runner_sha256" \
        "$failed_driver_sha256" \
        "$accepted_action17d_state_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    verify_sources
    "$inspector" --self-test >/dev/null
    printf 'action_17e_a_node_b_prewrite_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_live_sources
    printf 'action_17e_a_node_b_prewrite_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action17e-a-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    success=$contract_dir/success
    mismatch=$contract_dir/mismatch
    empty_error=$contract_dir/error
    : >"$empty_error"
    write_fixture \
        "$success" true 0 all_prewrite_assertions_pass_and_collectors_stable
    validate_transcript "$success"
    validate_secret_free "$success" "$empty_error"
    write_fixture \
        "$mismatch" false 1 prewrite_assertion_mismatch
    validate_transcript "$mismatch"

    duplicate=$contract_dir/duplicate
    cp -- "$success" "$duplicate"
    printf 'prewrite_uid_is_root=true\n' >>"$duplicate"
    if validate_transcript "$duplicate"; then
        printf 'Duplicate Action 17e-a marker was accepted.\n' >&2
        exit 1
    fi
    unsafe=$contract_dir/unsafe
    cp -- "$success" "$unsafe"
    printf '%s\n' 'local-data: "private.example. A 192.0.2.1"' >>"$unsafe"
    if validate_secret_free "$unsafe" "$empty_error"; then
        printf 'Private Action 17e-a output was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17e_a_node_b_prewrite_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_live_sources
work_dir=$(mktemp -d /tmp/caddy-action17e-a.XXXXXX)
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
        printf 'action_17e_a_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_17e_a_local_cleanup_complete=true\n'
    exit "$status"
}

ssh_status=0
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o "HostKeyAlias=$expected_host_alias" \
    -o StrictHostKeyChecking=yes \
    "$expected_target" \
    'sudo -n /bin/bash -s --' \
    <"$inspector" >"$remote_output" 2>"$remote_error" || ssh_status=$?

cat "$remote_output"
cat "$remote_error" >&2
printf 'ssh_exit_status=%s\n' "$ssh_status"
if [[ "$ssh_status" -ne 0 || -s "$remote_error" ]] ||
    ! validate_secret_free "$remote_output" "$remote_error" ||
    ! validate_transcript "$remote_output"; then
    printf 'Action 17e-a evidence contract failed.\n' >&2
    finish 97
fi
printf 'action_17e_a_conclusion=%s\n' \
    "$(value_for action_17e_a_conclusion "$remote_output")"
printf 'action_17e_a_node_b_prewrite_diagnostic_accepted=true\n'
finish 0
