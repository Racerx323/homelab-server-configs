#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_18b_a
readonly inspector_sha256=f893c433739b0b7c115b7d46c9e13dfd38338f2edbe7259ab3fae52a68545c0a
readonly collision_checker_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly expected_target=pi@10.1.0.53
readonly expected_host_alias=pihole0.local.theama.co
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096
readonly -a expected_assertions=(
    identity_root working_directory_root hostname_node_a architecture_arm64
    before_state_status_zero before_state_stderr_empty before_state_hash_format
    receiver_v1_regular receiver_v1_not_symlink receiver_v1_hash_exact
    receiver_v2_absent receiver_v2_not_symlink finalizer_v2_absent
    finalizer_v2_not_symlink authorized_keys_regular authorized_keys_not_symlink
    authorized_keys_metadata authorized_keys_single_line authorized_keys_hash_exact
    authorized_keys_node_b_fingerprint release_regular_directory release_not_symlink
    release_metadata manifest_regular manifest_not_symlink manifest_hash_exact
    payload_hash_exact complete_regular complete_not_symlink complete_empty
    complete_owner_observed complete_group_observed complete_mode_0440
    complete_bytes_zero complete_lines_zero complete_empty_sha256
    pending_marker_absent pending_marker_not_symlink finalize_request_absent
    finalize_request_not_symlink marker_classification_sender_build_complete
    current_link_exact current_target_exact caddy_active lighttpd_active
    lsyncd_inactive lsyncd_masked caddy_lsyncd_inactive caddy_lsyncd_disabled
    reconcile_path_inactive reconcile_service_inactive lsyncd_configuration_absent
    lsyncd_configuration_not_symlink action18b_backup_count_zero
    action18b_stage_count_zero after_state_status_zero after_state_stderr_empty
    after_state_hash_format state_unchanged
)
readonly -a fixed_markers=(
    action_18b_a_receiver_invoked=false
    action_18b_a_finalizer_invoked=false
    action_18b_a_release_mutated=false
    action_18b_a_authorization_mutated=false
    action_18b_a_service_mutations=false
    action_18b_a_synchronization_mutations=false
    action_18b_a_persistent_mutations=false
    action_18b_a_remote_complete=true
)

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector="$script_directory/inspect-node-a-action18b-postfailure-action18b-a.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

line_count() {
    awk 'END { print NR }' "$1"
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

    [[ "$(grep -Ec "^${value_key}=" "$value_transcript")" -eq 1 ]] || return 1
    value_record=$(grep -E "^${value_key}=" "$value_transcript")
    printf '%s\n' "${value_record#*=}"
}

is_sha256() {
    [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$stream_path"
}

transcript_grammar_valid() {
    local transcript_path=$1

    awk '
        index($0, "action_18b_a_") != 1 { invalid++ }
        $0 !~ /^action_18b_a_[a-z0-9_]+=[A-Za-z0-9_.:+\/-]+$/ { invalid++ }
        END { exit invalid ? 1 : 0 }
    ' "$transcript_path"
}

# conditional-validator-explicit-failures-begin
validate_transcript() {
    local error_path=$1
    local output_path=$2
    local contract_remote_status=$3
    local assertion_label
    local observed_count
    local reported_count
    local reported_failed
    local first_failure
    local before_hash
    local after_hash

    [[ ! -s "$error_path" ]] || return 97
    transcript_grammar_valid "$output_path" || return 97
    for assertion_label in "${expected_assertions[@]}"; do
        [[ "$(grep -Ec "^${prefix}_assertion_${assertion_label}=(true|false)$" "$output_path")" -eq 1 ]] || return 97
    done
    for fixed_marker in "${fixed_markers[@]}"; do
        require_one "$fixed_marker" "$output_path" || return 97
    done
    observed_count=$(grep -Ec "^${prefix}_assertion_[a-z0-9_]+=(true|false)$" \
        "$output_path") || return 97
    [[ "$observed_count" -eq "${#expected_assertions[@]}" ]] || return 97
    [[ "$(sed -n "s/^${prefix}_assertion_\([a-z0-9_]*\)=\(true\|false\)$/\1/p" "$output_path" | LC_ALL=C sort -u | wc -l)" -eq "$observed_count" ]] || return 97
    for value_key in marker_classification marker_owner marker_group marker_mode \
        marker_bytes marker_lines marker_sha256 action18b_backup_count \
        action18b_stage_count before_state_sha256 after_state_sha256; do
        [[ "$(grep -Ec "^${prefix}_value_${value_key}=" "$output_path")" -eq 1 ]] || return 97
    done
    for value_key in assertion_count failed_assertion_count first_failure; do
        [[ "$(grep -Ec "^${prefix}_${value_key}=" "$output_path")" -eq 1 ]] || return 97
    done
    require_one "${prefix}_value_marker_classification=sender_build_complete" "$output_path" || return 1
    require_one "${prefix}_value_marker_bytes=0" "$output_path" || return 1
    require_one "${prefix}_value_marker_lines=0" "$output_path" || return 1
    require_one "${prefix}_value_marker_mode=440" "$output_path" || return 1
    require_one "${prefix}_value_marker_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" "$output_path" || return 1
    before_hash=$(value_for "${prefix}_value_before_state_sha256" "$output_path") || return 97
    after_hash=$(value_for "${prefix}_value_after_state_sha256" "$output_path") || return 97
    is_sha256 "$before_hash" || return 97
    [[ "$after_hash" == "$before_hash" ]] || return 1
    reported_count=$(value_for "${prefix}_assertion_count" "$output_path") || return 97
    reported_failed=$(value_for "${prefix}_failed_assertion_count" "$output_path") || return 97
    first_failure=$(value_for "${prefix}_first_failure" "$output_path") || return 97
    [[ "$reported_count" =~ ^[1-9][0-9]*$ && "$reported_failed" =~ ^[0-9]+$ ]] || return 97
    [[ "$reported_count" -eq "$observed_count" ]] || return 97
    [[ "$reported_failed" -eq "$(grep -Ec "^${prefix}_assertion_[a-z0-9_]+=false$" "$output_path")" ]] || return 97
    if test "$reported_failed" -eq 0; then
        [[ "$first_failure" == none && "$contract_remote_status" -eq 0 ]] || return 97
        return 0
    fi
    [[ "$first_failure" != none && "$contract_remote_status" -eq 1 ]] || return 97
    return 1
}
# conditional-validator-explicit-failures-end

verify_sources() {
    [[ -f "$inspector" && ! -L "$inspector" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$inspector")" == aaron:aaron:755 ]] || return 1
    [[ "$(file_hash "$inspector")" == "$inspector_sha256" ]] || return 1
    [[ "$(file_hash "$collision_checker")" == "$collision_checker_sha256" ]] || return 1
    bash -n "$inspector" "$0" || return 1
    "$collision_checker" "$inspector" "$0" >/dev/null || return 1
    "$inspector" --self-test >/dev/null || return 1
}

write_fixture() {
    local fixture_path=$1
    local fixture_label

    {
        for fixture_label in "${expected_assertions[@]}"; do
            printf '%s_assertion_%s=true\n' "$prefix" "$fixture_label"
        done
        printf '%s\n' \
            action_18b_a_value_marker_classification=sender_build_complete \
            action_18b_a_value_marker_owner=caddy-sync \
            action_18b_a_value_marker_group=caddy-sync \
            action_18b_a_value_marker_mode=440 \
            action_18b_a_value_marker_bytes=0 \
            action_18b_a_value_marker_lines=0 \
            action_18b_a_value_marker_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 \
            action_18b_a_value_action18b_backup_count=0 \
            action_18b_a_value_action18b_stage_count=0 \
            action_18b_a_value_before_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
            action_18b_a_value_after_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
            "action_18b_a_assertion_count=${#expected_assertions[@]}" \
            action_18b_a_failed_assertion_count=0 \
            action_18b_a_first_failure=none
        printf '%s\n' "${fixed_markers[@]}"
    } >"$fixture_path"
}

case "${1:-}" in
    --self-test | --source-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        printf '%s_runner_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        contract_directory=$(mktemp -d /tmp/caddy-action18b-a-contract.XXXXXX)
        readonly contract_directory
        trap 'rm -rf -- "$contract_directory"' EXIT
        : >"$contract_directory/error"
        write_fixture "$contract_directory/success"
        validate_transcript "$contract_directory/error" "$contract_directory/success" 0
        cp "$contract_directory/success" "$contract_directory/semantic"
        sed -i 's/assertion_receiver_v2_absent=true/assertion_receiver_v2_absent=false/; s/failed_assertion_count=0/failed_assertion_count=1/; s/first_failure=none/first_failure=receiver_v2_absent/' "$contract_directory/semantic"
        if validate_transcript "$contract_directory/error" "$contract_directory/semantic" 1; then
            exit 1
        elif [[ $? -ne 1 ]]; then
            exit 1
        fi
        cp "$contract_directory/success" "$contract_directory/duplicate"
        printf 'action_18b_a_assertion_identity_root=true\n' >>"$contract_directory/duplicate"
        if validate_transcript "$contract_directory/error" "$contract_directory/duplicate" 0; then
            exit 1
        elif [[ $? -ne 97 ]]; then
            exit 1
        fi
        printf '%s_contract_false_negative_valid_success_accepted=true\n' "$prefix"
        printf '%s_contract_false_negative_semantic_mismatch_preserved=true\n' "$prefix"
        printf '%s_contract_false_positive_duplicate_rejected=true\n' "$prefix"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
[[ "$PWD" == /home/aaron/code/homelab-server-configs ]]
work_directory=$(mktemp -d /tmp/caddy-action18b-a-runner.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly stdout_path="$work_directory/node-a.stdout"
readonly stderr_path="$work_directory/node-a.stderr"
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"

remote_status=0
ssh -T -o BatchMode=yes -o ConnectTimeout=5 \
    -o "HostKeyAlias=$expected_host_alias" -o StrictHostKeyChecking=yes \
    "$expected_target" 'cd / && sudo -n /bin/bash -s' \
    <"$inspector" >"$stdout_path" 2>"$stderr_path" || remote_status=$?
readonly remote_status
printf '%s_stdout_bytes=%s\n' "$prefix" "$(wc -c <"$stdout_path")"
printf '%s_stdout_lines=%s\n' "$prefix" "$(line_count "$stdout_path")"
printf '%s_stdout_sha256=%s\n' "$prefix" "$(file_hash "$stdout_path")"
printf '%s_stderr_bytes=%s\n' "$prefix" "$(wc -c <"$stderr_path")"
printf '%s_stderr_lines=%s\n' "$prefix" "$(line_count "$stderr_path")"
printf '%s_stderr_sha256=%s\n' "$prefix" "$(file_hash "$stderr_path")"
if ! safe_stream "$stdout_path" || ! safe_stream "$stderr_path"; then
    trap - EXIT
    printf '%s_stream_classification=unsafe_retained\n' "$prefix" >&2
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
printf '%s_stream_classification=bounded_safe\n' "$prefix"
printf '%s_stdout_begin\n' "$prefix"
cat "$stdout_path"
printf '%s_stdout_end\n' "$prefix"
if [[ -s "$stderr_path" ]]; then
    printf '%s_stderr_begin\n' "$prefix" >&2
    cat "$stderr_path" >&2
    printf '%s_stderr_end\n' "$prefix" >&2
fi

set +e
validate_transcript "$stderr_path" "$stdout_path" "$remote_status"
validation_status=$?
set -e
printf '%s_validation_status=%s\n' "$prefix" "$validation_status"
if [[ "$validation_status" -eq 0 ]]; then
    printf '%s_runner_classification=state_verified\n' "$prefix"
elif [[ "$validation_status" -eq 1 ]]; then
    printf '%s_runner_classification=semantic_mismatch\n' "$prefix"
else
    printf '%s_runner_classification=evidence_failure\n' "$prefix"
fi
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_workstation_cleanup_complete=true\n' "$prefix"
exit "$validation_status"
