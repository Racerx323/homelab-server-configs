#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=ba1b49c0f01bf43c25b576d3740ea29f622a7644db016d7b9d6673897bd5f8b4
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co
readonly -a expected_assertions=(
    identity_root
    working_directory_root
    hostname_node_b
    architecture_arm64
    reconcile_path_property_query_status_zero
    reconcile_path_property_query_stderr_empty
    reconcile_path_property_count_positive
    reconcile_path_property_names_hash_format
    reconcile_path_load_state_loaded
    reconcile_path_active_state_inactive
    reconcile_path_sub_state_dead
    reconcile_path_unit_file_state_disabled
    reconcile_path_fragment_path_exact
    reconcile_path_mainpid_presence_boolean
    reconcile_path_nrestarts_presence_boolean
    receiver_v1_regular
    receiver_v1_not_symlink
    receiver_v1_hash_exact
    receiver_v2_regular
    receiver_v2_not_symlink
    receiver_v2_metadata
    receiver_v2_hash_exact
    receiver_v2_syntax
    finalizer_v2_regular
    finalizer_v2_not_symlink
    finalizer_v2_metadata
    finalizer_v2_hash_exact
    finalizer_v2_syntax
    authorized_keys_regular
    authorized_keys_not_symlink
    authorized_keys_metadata
    authorized_keys_hash_exact
    authorized_keys_single_line
    authorized_keys_node_a_fingerprint
    retained_release_directory
    retained_release_not_symlink
    retained_release_metadata
    retained_complete_absent
    retained_complete_not_symlink
    retained_pending_absent
    retained_pending_not_symlink
    retained_finalize_request_absent
    retained_finalize_request_not_symlink
    retained_payload_hash_exact
    retained_manifest_hash_exact
    retained_not_writable_by_sync
    current_link_exact
    current_target_exact
    caddy_active
    lighttpd_active
    lsyncd_inactive
    lsyncd_masked
    caddy_lsyncd_inactive
    caddy_lsyncd_disabled
    reconcile_path_inactive
    reconcile_service_inactive
    lsyncd_configuration_absent
    lsyncd_configuration_not_symlink
    action17q_backup_count_zero
    rollback_directory_regular
    rollback_directory_not_symlink
    rollback_directory_metadata
    rollback_authorization_regular
    rollback_authorization_not_symlink
    rollback_authorization_metadata
    rollback_authorization_hash_exact
    rollback_hash_record_regular
    rollback_hash_record_not_symlink
    rollback_hash_record_metadata
    rollback_hash_record_content_exact
    action17q_retry_backup_count_one
    action17q_retry_stage_count_zero
    before_state_status_zero
    before_state_stderr_empty
    before_state_hash_format
    after_state_status_zero
    after_state_stderr_empty
    after_state_hash_format
    state_unchanged
    conclusion_supported
    assertion_count_nonnegative
)
readonly -a fixed_markers=(
    action_17q_b_helper_execution=false
    action_17q_b_release_mutation=false
    action_17q_b_authorization_mutation=false
    action_17q_b_lsyncd_reconciliation_activation=false
    action_17q_b_service_mutations=false
    action_17q_b_persistent_mutations=false
    action_17q_b_remote_complete=true
)

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly inspector="$script_directory/inspect-node-b-protocol-v2-postinstall-action17q-b.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_inspector() {
    [[ -f "$inspector" && ! -L "$inspector" ]]
    [[ "$(stat -c '%U:%G:%a' "$inspector")" == aaron:aaron:755 ]]
    [[ "$(file_hash "$inspector")" == "$inspector_sha256" ]]
    bash -n "$inspector"
    "$collision_checker" "$inspector" >/dev/null
    "$inspector" --self-test >/dev/null
}

require_one() {
    local required_record=$1
    local required_transcript=$2

    [[ "$(grep -Fxc "$required_record" "$required_transcript")" -eq 1 ]]
}

value_for() {
    local value_key=$1
    local value_transcript=$2
    local value_record

    [[ "$(grep -Ec "^${value_key}=" "$value_transcript")" -eq 1 ]] ||
        return 1
    value_record=$(grep -E "^${value_key}=" "$value_transcript")
    printf '%s\n' "${value_record#*=}"
}

is_nonnegative_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

is_boolean() {
    [[ "$1" =~ ^(true|false)$ ]]
}

is_positive_integer() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

is_sha256() {
    [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

conclusion_matches_presence() {
    local presence_conclusion=$1
    local presence_mainpid=$2
    local presence_nrestarts=$3

    case "$presence_mainpid:$presence_nrestarts:$presence_conclusion" in
        false:false:path_omits_mainpid_and_nrestarts | \
            false:true:path_omits_mainpid | \
            true:false:path_omits_nrestarts | \
            true:true:path_exposes_both_service_properties)
            return 0
            ;;
    esac
    return 1
}

transcript_grammar_valid() {
    local grammar_transcript=$1

    awk '
        index($0, "action_17q_b_") != 1 { invalid++ }
        $0 !~ /^action_17q_b_[a-z0-9_]+=[A-Za-z0-9_.\/:-]+$/ {
            invalid++
        }
        END { exit invalid ? 1 : 0 }
    ' "$grammar_transcript"
}

secret_free() {
    local secret_error=$1
    local secret_output=$2

    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|PRIVATE_KEY=' \
        "$secret_output" "$secret_error"
}

evaluate_contract() {
    local contract_error=$1
    local contract_output=$2
    local contract_ssh_status=$3
    local contract_assertion
    local contract_assertion_count
    local contract_before_hash
    local contract_failed_count
    local contract_first_failure
    local contract_conclusion
    local contract_mainpid_present
    local contract_nrestarts_present
    local contract_observed_assertions
    local contract_expected_status

    secret_free "$contract_error" "$contract_output" || return 97
    [[ ! -s "$contract_error" ]] || return 97
    transcript_grammar_valid "$contract_output" || return 97

    for contract_marker in "${fixed_markers[@]}"; do
        require_one "$contract_marker" "$contract_output" || return 97
    done
    for contract_assertion in "${expected_assertions[@]}"; do
        [[ "$(grep -Ec \
            "^action_17q_b_assertion_${contract_assertion}=(true|false)$" \
            "$contract_output")" -eq 1 ]] || return 97
    done
    contract_observed_assertions=$(
        grep -Ec '^action_17q_b_assertion_[a-z0-9_]+=(true|false)$' \
            "$contract_output"
    )
    [[ "$contract_observed_assertions" -eq "${#expected_assertions[@]}" ]] || return 97

    for contract_value_key in \
        action_17q_b_value_reconcile_path_property_count \
        action_17q_b_value_reconcile_path_property_names_sha256 \
        action_17q_b_value_reconcile_path_load_state \
        action_17q_b_value_reconcile_path_active_state \
        action_17q_b_value_reconcile_path_sub_state \
        action_17q_b_value_reconcile_path_unit_file_state \
        action_17q_b_value_reconcile_path_fragment_path \
        action_17q_b_value_reconcile_path_mainpid_present \
        action_17q_b_value_reconcile_path_nrestarts_present \
        action_17q_b_value_action17q_backup_count \
        action_17q_b_value_action17q_retry_backup_count \
        action_17q_b_value_action17q_retry_stage_count \
        action_17q_b_value_rollback_directory \
        action_17q_b_value_before_state_sha256 \
        action_17q_b_value_after_state_sha256 \
        action_17q_b_value_conclusion \
        action_17q_b_assertion_count \
        action_17q_b_failed_assertion_count \
        action_17q_b_first_failure; do
        [[ "$(grep -Ec "^${contract_value_key}=" "$contract_output")" -eq 1 ]] ||
            return 97
    done

    is_positive_integer \
        "$(value_for \
            action_17q_b_value_reconcile_path_property_count \
            "$contract_output")" || return 97
    is_sha256 \
        "$(value_for \
            action_17q_b_value_reconcile_path_property_names_sha256 \
            "$contract_output")" || return 97
    require_one \
        action_17q_b_value_reconcile_path_load_state=loaded \
        "$contract_output" || return 97
    require_one \
        action_17q_b_value_reconcile_path_active_state=inactive \
        "$contract_output" || return 97
    require_one \
        action_17q_b_value_reconcile_path_sub_state=dead \
        "$contract_output" || return 97
    require_one \
        action_17q_b_value_reconcile_path_unit_file_state=disabled \
        "$contract_output" || return 97
    require_one \
        action_17q_b_value_reconcile_path_fragment_path=/etc/systemd/system/caddy-sync-reconcile.path \
        "$contract_output" || return 97
    contract_mainpid_present=$(
        value_for \
            action_17q_b_value_reconcile_path_mainpid_present \
            "$contract_output"
    ) || return 97
    contract_nrestarts_present=$(
        value_for \
            action_17q_b_value_reconcile_path_nrestarts_present \
            "$contract_output"
    ) || return 97
    is_boolean "$contract_mainpid_present" || return 97
    is_boolean "$contract_nrestarts_present" || return 97
    require_one \
        action_17q_b_value_action17q_backup_count=0 \
        "$contract_output" || return 97
    require_one \
        action_17q_b_value_action17q_retry_backup_count=1 \
        "$contract_output" || return 97
    require_one \
        action_17q_b_value_action17q_retry_stage_count=0 \
        "$contract_output" || return 97
    require_one \
        action_17q_b_value_rollback_directory=/var/backups/caddy-ha/action17q-retry-node-b-protocol-v2.TEhT7k \
        "$contract_output" || return 97
    contract_before_hash=$(
        value_for action_17q_b_value_before_state_sha256 "$contract_output"
    ) || return 97
    is_sha256 "$contract_before_hash" || return 97
    require_one \
        "action_17q_b_value_after_state_sha256=$contract_before_hash" \
        "$contract_output" || return 97
    contract_conclusion=$(
        value_for action_17q_b_value_conclusion "$contract_output"
    ) || return 97
    conclusion_matches_presence \
        "$contract_conclusion" \
        "$contract_mainpid_present" \
        "$contract_nrestarts_present" || return 97

    contract_assertion_count=$(
        value_for action_17q_b_assertion_count "$contract_output"
    ) || return 97
    contract_failed_count=$(
        value_for action_17q_b_failed_assertion_count "$contract_output"
    ) || return 97
    contract_first_failure=$(
        value_for action_17q_b_first_failure "$contract_output"
    ) || return 97
    is_positive_integer "$contract_assertion_count" || return 97
    is_nonnegative_integer "$contract_failed_count" || return 97
    [[ "$contract_assertion_count" -eq "${#expected_assertions[@]}" ]] || return 97
    [[ "$contract_failed_count" -eq "$(grep -Ec '^action_17q_b_assertion_[a-z0-9_]+=false$' \
        "$contract_output")" ]] || return 97

    if [[ "$contract_failed_count" -eq 0 ]]; then
        [[ "$contract_first_failure" == none ]] || return 97
        contract_expected_status=0
    else
        [[ "$contract_first_failure" != none ]] || return 97
        require_one \
            "action_17q_b_assertion_${contract_first_failure}=false" \
            "$contract_output" || return 97
        contract_expected_status=1
    fi
    [[ "$contract_ssh_status" -eq "$contract_expected_status" ]] || return 97
    return "$contract_expected_status"
}

write_contract_fixture() {
    local fixture_destination=$1
    local fixture_assertion

    {
        for fixture_assertion in "${expected_assertions[@]}"; do
            printf 'action_17q_b_assertion_%s=true\n' "$fixture_assertion"
        done
        printf '%s\n' \
            action_17q_b_value_reconcile_path_property_count=190 \
            action_17q_b_value_reconcile_path_property_names_sha256=1111111111111111111111111111111111111111111111111111111111111111 \
            action_17q_b_value_reconcile_path_load_state=loaded \
            action_17q_b_value_reconcile_path_active_state=inactive \
            action_17q_b_value_reconcile_path_sub_state=dead \
            action_17q_b_value_reconcile_path_unit_file_state=disabled \
            action_17q_b_value_reconcile_path_fragment_path=/etc/systemd/system/caddy-sync-reconcile.path \
            action_17q_b_value_reconcile_path_mainpid_present=false \
            action_17q_b_value_reconcile_path_nrestarts_present=false \
            action_17q_b_value_action17q_backup_count=0 \
            action_17q_b_value_action17q_retry_backup_count=1 \
            action_17q_b_value_action17q_retry_stage_count=0 \
            action_17q_b_value_rollback_directory=/var/backups/caddy-ha/action17q-retry-node-b-protocol-v2.TEhT7k \
            action_17q_b_value_before_state_sha256=2222222222222222222222222222222222222222222222222222222222222222 \
            action_17q_b_value_after_state_sha256=2222222222222222222222222222222222222222222222222222222222222222 \
            action_17q_b_value_conclusion=path_omits_mainpid_and_nrestarts \
            "action_17q_b_assertion_count=${#expected_assertions[@]}" \
            action_17q_b_failed_assertion_count=0 \
            action_17q_b_first_failure=none \
            "${fixed_markers[@]}"
    } >"$fixture_destination"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$expected_target" == pi@10.1.0.54 ]]
        [[ "$expected_host_alias" == pihole00.local.theama.co ]]
        [[ "${#expected_assertions[@]}" -eq 81 ]]
        [[ "${#fixed_markers[@]}" -eq 7 ]]
        printf 'action_17q_b_runner_self_test_complete=true\n'
        exit 0
        ;;
    --source-test)
        [[ $# -eq 1 ]]
        verify_inspector
        printf 'action_17q_b_runner_source_test_complete=true\n'
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]]
        conclusion_matches_presence \
            path_omits_mainpid_and_nrestarts false false
        conclusion_matches_presence path_omits_mainpid false true
        conclusion_matches_presence path_omits_nrestarts true false
        conclusion_matches_presence \
            path_exposes_both_service_properties true true
        if conclusion_matches_presence path_omits_mainpid true false; then
            printf 'Contradictory path-property classification accepted.\n' \
                >&2
            exit 1
        fi
        contract_directory=$(mktemp -d /tmp/caddy-action17q-b-contract.XXXXXX)
        trap 'rm -rf -- "$contract_directory"' EXIT
        : >"$contract_directory/error"
        write_contract_fixture "$contract_directory/output"
        evaluate_contract \
            "$contract_directory/error" "$contract_directory/output" 0
        sed \
            -e 's/action_17q_b_assertion_state_unchanged=true/action_17q_b_assertion_state_unchanged=false/' \
            -e 's/action_17q_b_failed_assertion_count=0/action_17q_b_failed_assertion_count=1/' \
            -e 's/action_17q_b_first_failure=none/action_17q_b_first_failure=state_unchanged/' \
            "$contract_directory/output" >"$contract_directory/mismatch"
        set +e
        evaluate_contract \
            "$contract_directory/error" "$contract_directory/mismatch" 1
        mismatch_status=$?
        set -e
        [[ "$mismatch_status" -eq 1 ]]
        printf 'action_17q_b_runner_contract_test_complete=true\n'
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 2
        ;;
esac

verify_inspector
work_directory=$(mktemp -d /tmp/caddy-action17q-b-runner.XXXXXX)
readonly work_directory
readonly output_path="$work_directory/remote.out"
readonly error_path="$work_directory/remote.err"

cleanup() {
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

finish() {
    local finish_status=$1

    cleanup
    trap - EXIT
    if [[ -e "$work_directory" || -L "$work_directory" ]]; then
        printf 'action_17q_b_workstation_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_17q_b_workstation_cleanup_complete=true\n'
    exit "$finish_status"
}

ssh_status=0
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o "HostKeyAlias=$expected_host_alias" \
    -o StrictHostKeyChecking=yes \
    "$expected_target" \
    'cd / && sudo -n /bin/bash -s --' \
    <"$inspector" >"$output_path" 2>"$error_path" || ssh_status=$?

cat "$output_path"
cat "$error_path" >&2
printf 'action_17q_b_ssh_status=%s\n' "$ssh_status"
set +e
evaluate_contract "$error_path" "$output_path" "$ssh_status"
contract_status=$?
set -e
if [[ "$contract_status" -eq 97 ]]; then
    printf 'Action 17q-b transcript contract failed.\n' >&2
    printf 'action_17q_b_runner_contract_valid=false\n' >&2
    finish 97
fi
printf 'action_17q_b_runner_contract_valid=true\n'
if [[ "$contract_status" -eq 0 ]]; then
    printf 'action_17q_b_runner_acceptance=true\n'
else
    printf 'action_17q_b_runner_acceptance=false\n'
fi
finish "$contract_status"
