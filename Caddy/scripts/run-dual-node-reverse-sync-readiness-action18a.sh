#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly action_prefix=action_18a
readonly inspector_sha256=209eadc6ff077e829c0b5fc2f3c867728b9ad279372e663cb9f6eebf09a45673
readonly node_a_alias=pihole0.local.theama.co
readonly node_a_target=pi@10.1.0.53
readonly node_b_alias=pihole00.local.theama.co
readonly node_b_target=pi@10.1.0.54
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly inspector="$script_directory/inspect-reverse-sync-readiness-action18a.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

require_one() {
    local exact_line=$1
    local transcript_path=$2

    [[ "$(grep -Fxc "$exact_line" "$transcript_path")" -eq 1 ]]
}

safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le 65536 ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null || return 1
    ! grep -Eq 'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN' \
        "$stream_path"
}

validate_transcript() {
    local validation_role=$1
    local transcript_path=$2
    local error_path=$3
    local remote_status=$4
    local validation_prefix="${action_prefix}_${validation_role//-/_}"
    local count_value failed_value first_value

    [[ "$remote_status" -eq 0 || "$remote_status" -eq 1 ]] || return 97
    [[ ! -s "$error_path" ]] || return 97
    safe_stream "$transcript_path" || return 97
    safe_stream "$error_path" || return 97
    require_one "${validation_prefix}_remote_complete=true" "$transcript_path" || return 97
    for marker_name in peer_connection_executed restricted_command_executed \
        release_transfer_executed finalizer_invoked lsyncd_enabled \
        reconciliation_enabled service_mutations filesystem_mutations; do
        require_one "${validation_prefix}_${marker_name}=false" "$transcript_path" || return 97
    done
    for value_name in revision parent_revision payload_sha256 manifest_sha256 \
        before_state_sha256 after_state_sha256 assertion_count \
        failed_assertion_count first_failure; do
        [[ "$(grep -c "^${validation_prefix}_value_${value_name}=" "$transcript_path")" -eq 1 ||
        ("$value_name" =~ ^(assertion_count|failed_assertion_count|first_failure)$ &&
        "$(grep -c "^${validation_prefix}_${value_name}=" "$transcript_path")" -eq 1) ]] || return 97
    done
    count_value=$(sed -n "s/^${validation_prefix}_assertion_count=//p" "$transcript_path")
    failed_value=$(sed -n "s/^${validation_prefix}_failed_assertion_count=//p" "$transcript_path")
    first_value=$(sed -n "s/^${validation_prefix}_first_failure=//p" "$transcript_path")
    [[ "$count_value" =~ ^[1-9][0-9]*$ && "$failed_value" =~ ^[0-9]+$ ]] || return 97
    [[ "$(grep -Ec "^${validation_prefix}_assertion_[a-z0-9_]+=(true|false)$" "$transcript_path")" -eq "$count_value" ]] || return 97
    [[ "$(grep -Ec "^${validation_prefix}_assertion_[a-z0-9_]+=false$" "$transcript_path")" -eq "$failed_value" ]] || return 97
    [[ "$(grep "^${validation_prefix}_assertion_" "$transcript_path" | cut -d= -f1 | sort | uniq -d | wc -l)" -eq 0 ]] || return 97
    require_one "${validation_prefix}_value_before_state_sha256=$(sed -n "s/^${validation_prefix}_value_after_state_sha256=//p" "$transcript_path")" "$transcript_path" || return 97
    if [[ "$failed_value" -eq 0 ]]; then
        [[ "$first_value" == none && "$remote_status" -eq 0 ]] || return 97
        return 0
    fi
    [[ "$first_value" != none && "$remote_status" -eq 1 ]] || return 97
    return 1
}

verify_source() {
    [[ -f "$inspector" && ! -L "$inspector" ]] || return 1
    [[ "$(file_hash "$inspector")" == "$inspector_sha256" ]] || return 1
    bash -n "$inspector" || return 1
    "$inspector" --self-test >/dev/null || return 1
}

write_fixture() {
    local fixture_role=$1
    local fixture_failed=$2
    local fixture_path=$3
    local fixture_prefix="${action_prefix}_${fixture_role//-/_}"
    local fixture_status=true
    local fixture_first=none

    if [[ "$fixture_failed" -eq 1 ]]; then
        fixture_status=false
        fixture_first=receiver_v2_regular
    fi
    {
        printf '%s\n' \
            "${fixture_prefix}_assertion_identity_root=true" \
            "${fixture_prefix}_assertion_receiver_v2_regular=$fixture_status" \
            "${fixture_prefix}_value_revision=action17p-node-a-to-node-b-bootstrap" \
            "${fixture_prefix}_value_parent_revision=action15-health-follow-redirects" \
            "${fixture_prefix}_value_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e" \
            "${fixture_prefix}_value_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8" \
            "${fixture_prefix}_value_before_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
            "${fixture_prefix}_value_after_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
            "${fixture_prefix}_assertion_count=2" \
            "${fixture_prefix}_failed_assertion_count=$fixture_failed" \
            "${fixture_prefix}_first_failure=$fixture_first" \
            "${fixture_prefix}_peer_connection_executed=false" \
            "${fixture_prefix}_restricted_command_executed=false" \
            "${fixture_prefix}_release_transfer_executed=false" \
            "${fixture_prefix}_finalizer_invoked=false" \
            "${fixture_prefix}_lsyncd_enabled=false" \
            "${fixture_prefix}_reconciliation_enabled=false" \
            "${fixture_prefix}_service_mutations=false" \
            "${fixture_prefix}_filesystem_mutations=false" \
            "${fixture_prefix}_remote_complete=true"
    } >"$fixture_path"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_source
        printf '%s_runner_self_test_complete=true\n' "$action_prefix"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_source
        contract_directory=$(mktemp -d /tmp/caddy-action18a-contract.XXXXXX)
        trap 'rm -rf -- "$contract_directory"' EXIT
        : >"$contract_directory/error"
        for contract_role in node-a node-b; do
            write_fixture "$contract_role" 0 "$contract_directory/success"
            validate_transcript "$contract_role" "$contract_directory/success" \
                "$contract_directory/error" 0
            write_fixture "$contract_role" 1 "$contract_directory/mismatch"
            if validate_transcript "$contract_role" "$contract_directory/mismatch" \
                "$contract_directory/error" 1; then
                exit 1
            elif [[ $? -ne 1 ]]; then
                exit 1
            fi
            cp "$contract_directory/success" "$contract_directory/duplicate"
            printf '%s\n' "${action_prefix}_${contract_role//-/_}_assertion_identity_root=true" >>"$contract_directory/duplicate"
            if validate_transcript "$contract_role" "$contract_directory/duplicate" \
                "$contract_directory/error" 0; then
                exit 1
            fi
        done
        printf '%s_runner_contract_test_complete=true\n' "$action_prefix"
        exit 0
        ;;
    --source-test)
        [[ $# -eq 1 ]] || exit 64
        verify_source
        [[ "$(stat -c '%U:%G:%a' "$inspector")" == aaron:aaron:755 ]]
        printf '%s_runner_source_test_complete=true\n' "$action_prefix"
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

verify_source
[[ "$PWD" == /home/aaron/code/homelab-server-configs ]]
work_directory=$(mktemp -d /tmp/caddy-action18a-runner.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

overall_status=0
for node_role in node-a node-b; do
    if [[ "$node_role" == node-a ]]; then
        host_alias=$node_a_alias
        target=$node_a_target
    else
        host_alias=$node_b_alias
        target=$node_b_target
    fi
    stdout_path="$work_directory/$node_role.stdout"
    stderr_path="$work_directory/$node_role.stderr"
    : >"$stdout_path"
    : >"$stderr_path"
    chmod 0600 "$stdout_path" "$stderr_path"
    remote_status=0
    ssh -T -o BatchMode=yes -o ConnectTimeout=5 \
        -o "HostKeyAlias=$host_alias" -o StrictHostKeyChecking=yes \
        "$target" "cd / && sudo -n /bin/bash -s -- --node $node_role" \
        <"$inspector" >"$stdout_path" 2>"$stderr_path" || remote_status=$?
    printf '%s_%s_stdout_bytes=%s\n' "$action_prefix" "${node_role//-/_}" \
        "$(wc -c <"$stdout_path")"
    printf '%s_%s_stdout_lines=%s\n' "$action_prefix" "${node_role//-/_}" \
        "$(wc -l <"$stdout_path")"
    printf '%s_%s_stdout_sha256=%s\n' "$action_prefix" "${node_role//-/_}" \
        "$(file_hash "$stdout_path")"
    printf '%s_%s_stderr_bytes=%s\n' "$action_prefix" "${node_role//-/_}" \
        "$(wc -c <"$stderr_path")"
    printf '%s_%s_stderr_lines=%s\n' "$action_prefix" "${node_role//-/_}" \
        "$(wc -l <"$stderr_path")"
    printf '%s_%s_stderr_sha256=%s\n' "$action_prefix" "${node_role//-/_}" \
        "$(file_hash "$stderr_path")"
    if safe_stream "$stdout_path" && safe_stream "$stderr_path"; then
        printf '%s_%s_stream_classification=bounded_safe\n' \
            "$action_prefix" "${node_role//-/_}"
        printf '%s_%s_stdout_begin\n' "$action_prefix" "${node_role//-/_}"
        cat "$stdout_path"
        printf '%s_%s_stdout_end\n' "$action_prefix" "${node_role//-/_}"
        if [[ -s "$stderr_path" ]]; then
            printf '%s_%s_stderr_begin\n' "$action_prefix" "${node_role//-/_}" >&2
            cat "$stderr_path" >&2
            printf '%s_%s_stderr_end\n' "$action_prefix" "${node_role//-/_}" >&2
        fi
    else
        printf '%s_%s_stream_classification=unsafe_retained\n' \
            "$action_prefix" "${node_role//-/_}"
        trap - EXIT
        printf '%s_protected_evidence=%s\n' "$action_prefix" "$work_directory" >&2
        exit 97
    fi
    validation_status=0
    validate_transcript "$node_role" "$stdout_path" "$stderr_path" \
        "$remote_status" || validation_status=$?
    printf '%s_%s_remote_status=%s\n' "$action_prefix" \
        "${node_role//-/_}" "$remote_status"
    printf '%s_%s_validation_status=%s\n' "$action_prefix" \
        "${node_role//-/_}" "$validation_status"
    if [[ "$validation_status" -eq 97 ]]; then
        exit 97
    elif [[ "$validation_status" -eq 1 ]]; then
        overall_status=1
    fi
done

node_a_stdout="$work_directory/node-a.stdout"
node_b_stdout="$work_directory/node-b.stdout"
for ancestry_field in revision parent_revision payload_sha256 manifest_sha256; do
    node_a_value=$(sed -n "s/^${action_prefix}_node_a_value_${ancestry_field}=//p" "$node_a_stdout")
    node_b_value=$(sed -n "s/^${action_prefix}_node_b_value_${ancestry_field}=//p" "$node_b_stdout")
    if [[ "$node_a_value" == "$node_b_value" && -n "$node_a_value" ]]; then
        printf '%s_cross_node_%s_exact=true\n' "$action_prefix" "$ancestry_field"
    else
        printf '%s_cross_node_%s_exact=false\n' "$action_prefix" "$ancestry_field"
        overall_status=1
    fi
done
printf '%s_peer_connection_executed=false\n' "$action_prefix"
printf '%s_reverse_synchronization_executed=false\n' "$action_prefix"
printf '%s_service_mutations=false\n' "$action_prefix"
printf '%s_persistent_mutations=false\n' "$action_prefix"
if [[ "$overall_status" -eq 0 ]]; then
    printf '%s_readiness=ready_for_separately_authorized_action18\n' "$action_prefix"
else
    printf '%s_readiness=prerequisites_required_before_action18\n' "$action_prefix"
fi
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_cleanup_complete=true\n' "$action_prefix"
exit "$overall_status"
