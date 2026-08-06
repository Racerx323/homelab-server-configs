#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry8_a
readonly diagnostic_sha256=ea1aa14bbf8721a8c4b369a7887b6cee512fbaf39197ebe40689cebfbd5c1490
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=8192
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly diagnostic="$script_directory/diagnose-node-a-caddy-managed-context-action20d-retry8-a.sh"
readonly ssh_binary=${CADDY_ACTION20D_RETRY8_A_SSH_BINARY:-/usr/bin/ssh}

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
safe_stream() {
    local runner_stream_path=$1

    [[ "$(wc -c <"$runner_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$runner_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$runner_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$runner_stream_path"
}
require_one() {
    local runner_expected_line=$1
    local runner_transcript_path=$2

    [[ "$(grep -Fxc "$runner_expected_line" "$runner_transcript_path" || true)" -eq 1 ]]
}
require_one_pattern() {
    local runner_expected_pattern=$1
    local runner_transcript_path=$2

    [[ "$(grep -Ec "$runner_expected_pattern" "$runner_transcript_path" || true)" -eq 1 ]]
}
verify_source() {
    [[ -f "$diagnostic" && ! -L "$diagnostic" && -x "$diagnostic" ]] || return 1
    [[ "$(file_hash "$diagnostic")" = "$diagnostic_sha256" ]] || return 1
    /bin/bash -n "$diagnostic" || return 1
}
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
            ;;
        *) return 1 ;;
    esac
}
classify_probe_statuses() {
    local runner_sourced_root=$1
    local runner_full_group=$2
    local runner_interpreter=$3
    local runner_environment=$4
    local runner_service=$5
    local runner_caddy=$6
    local runner_curl=$7
    local runner_primary_helper=$8

    if [[ "$runner_sourced_root" -ne 0 ]]; then
        printf 'sourced_root_caddy_validate_failed\n'
    elif [[ "$runner_full_group" -ne 0 ]]; then
        printf 'current_health_failure_prevents_context_comparison\n'
    elif [[ "$runner_interpreter" -ne 0 ]]; then
        printf 'primary_group_interpreter_failed\n'
    elif [[ "$runner_environment" -ne 0 ]]; then
        printf 'primary_group_environment_failed\n'
    elif [[ "$runner_service" -ne 0 ]]; then
        printf 'primary_group_service_failed\n'
    elif [[ "$runner_caddy" -ne 0 && "$runner_primary_helper" -ne 0 ]]; then
        printf 'supplementary_group_boundary_reproduced_at_caddy_validate\n'
    elif [[ "$runner_curl" -ne 0 ]]; then
        printf 'primary_group_curl_failed\n'
    elif [[ "$runner_primary_helper" -ne 0 ]]; then
        printf 'primary_group_full_helper_failed_without_component_failure\n'
    else
        printf 'managed_failure_not_reproduced_by_read_only_context_probe\n'
    fi
}
validate_capture_contract() {
    local runner_capture_label=$1
    local runner_capture_transcript=$2
    local runner_capture_bytes
    local runner_capture_lines

    require_one_pattern \
        "^${prefix}_capture_${runner_capture_label}_bytes=[0-9]+$" \
        "$runner_capture_transcript" || return 1
    require_one_pattern \
        "^${prefix}_capture_${runner_capture_label}_lines=[0-9]+$" \
        "$runner_capture_transcript" || return 1
    require_one_pattern \
        "^${prefix}_capture_${runner_capture_label}_sha256=[0-9a-f]{64}$" \
        "$runner_capture_transcript" || return 1
    require_one "${prefix}_capture_${runner_capture_label}_classification=bounded_safe" \
        "$runner_capture_transcript" || return 1
    runner_capture_bytes=$(sed -n \
        "s/^${prefix}_capture_${runner_capture_label}_bytes=//p" \
        "$runner_capture_transcript")
    runner_capture_lines=$(sed -n \
        "s/^${prefix}_capture_${runner_capture_label}_lines=//p" \
        "$runner_capture_transcript")
    [[ "$runner_capture_bytes" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$runner_capture_lines" -le "$maximum_stream_lines" ]] || return 1
    if [[ "$runner_capture_bytes" -eq 0 ]]; then
        require_one "${prefix}_capture_${runner_capture_label}_content_secured=empty" \
            "$runner_capture_transcript" || return 1
    else
        require_one "${prefix}_capture_${runner_capture_label}_begin" \
            "$runner_capture_transcript" || return 1
        require_one "${prefix}_capture_${runner_capture_label}_end" \
            "$runner_capture_transcript" || return 1
    fi
}
validate_transcript() {
    local runner_stderr_path=$1
    local runner_stdout_path=$2
    local runner_remote_status=$3
    local runner_contract_root
    local runner_expected_count
    local runner_observed_count
    local runner_reported_count
    local runner_reported_failed
    local runner_actual_failed
    local runner_first_failure
    local runner_before_hash
    local runner_after_hash
    local runner_bare_root_status
    local runner_sourced_root_status
    local runner_full_group_status
    local runner_interpreter_status
    local runner_environment_status
    local runner_service_status
    local runner_caddy_status
    local runner_curl_status
    local runner_primary_helper_status
    local runner_reported_classification
    local runner_expected_classification
    local runner_capture_name

    [[ ! -s "$runner_stderr_path" ]] || return 97
    [[ "$runner_remote_status" -eq 0 ]] || return 1
    runner_contract_root=$(mktemp -d /tmp/caddy-action20d-retry8-a-contract.XXXXXX) || return 97
    /bin/bash "$diagnostic" --expected-assertions | LC_ALL=C sort \
        >"$runner_contract_root/expected" || {
        rm -rf -- "$runner_contract_root"
        return 97
    }
    sed -n "s/^${prefix}_assertion_\([a-z0-9_]*\)=\(true\|false\)$/\1/p" \
        "$runner_stdout_path" | LC_ALL=C sort >"$runner_contract_root/observed"
    runner_expected_count=$(wc -l <"$runner_contract_root/expected")
    runner_observed_count=$(wc -l <"$runner_contract_root/observed")
    [[ "$runner_expected_count" -gt 0 ]] || {
        rm -rf -- "$runner_contract_root"
        return 97
    }
    [[ "$runner_observed_count" -eq "$runner_expected_count" ]] || {
        rm -rf -- "$runner_contract_root"
        return 97
    }
    [[ "$runner_observed_count" -eq "$(LC_ALL=C sort -u "$runner_contract_root/observed" | wc -l)" ]] || {
        rm -rf -- "$runner_contract_root"
        return 97
    }
    cmp -s "$runner_contract_root/expected" "$runner_contract_root/observed" || {
        rm -rf -- "$runner_contract_root"
        return 97
    }
    rm -rf -- "$runner_contract_root"

    runner_reported_count=$(sed -n "s/^${prefix}_assertion_count=//p" "$runner_stdout_path")
    runner_reported_failed=$(sed -n "s/^${prefix}_failed_assertion_count=//p" "$runner_stdout_path")
    runner_actual_failed=$(grep -Ec "^${prefix}_assertion_[a-z0-9_]+=false$" \
        "$runner_stdout_path" || true)
    runner_first_failure=$(sed -n "s/^${prefix}_first_failure=//p" "$runner_stdout_path")
    [[ "$runner_reported_count" =~ ^[0-9]+$ ]] || return 97
    [[ "$runner_reported_count" -eq "$runner_expected_count" ]] || return 97
    [[ "$runner_reported_failed" = 0 && "$runner_actual_failed" -eq 0 ]] || return 1
    [[ "$runner_first_failure" = none ]] || return 1
    ! grep -Eq "^${prefix}_assertion_[a-z0-9_]+=false$" "$runner_stdout_path" || return 1

    for runner_capture_name in \
        bare_root_caddy_stdout bare_root_caddy_stderr \
        sourced_root_caddy_stdout sourced_root_caddy_stderr \
        full_group_helper_stdout full_group_helper_stderr \
        primary_group_interpreter_stdout primary_group_interpreter_stderr \
        primary_group_environment_stdout primary_group_environment_stderr \
        primary_group_service_stdout primary_group_service_stderr \
        primary_group_caddy_stdout primary_group_caddy_stderr \
        primary_group_curl_stdout primary_group_curl_stderr \
        primary_group_helper_stdout primary_group_helper_stderr \
        vrrp_environment_names vrrp_status vrrp_context; do
        validate_capture_contract "$runner_capture_name" "$runner_stdout_path" || return 97
    done

    runner_bare_root_status=$(sed -n "s/^${prefix}_value_bare_root_caddy_status=//p" "$runner_stdout_path")
    runner_sourced_root_status=$(sed -n "s/^${prefix}_value_sourced_root_caddy_status=//p" "$runner_stdout_path")
    runner_full_group_status=$(sed -n "s/^${prefix}_value_full_group_helper_status=//p" "$runner_stdout_path")
    runner_interpreter_status=$(sed -n "s/^${prefix}_value_primary_group_interpreter_status=//p" "$runner_stdout_path")
    runner_environment_status=$(sed -n "s/^${prefix}_value_primary_group_environment_status=//p" "$runner_stdout_path")
    runner_service_status=$(sed -n "s/^${prefix}_value_primary_group_service_status=//p" "$runner_stdout_path")
    runner_caddy_status=$(sed -n "s/^${prefix}_value_primary_group_caddy_status=//p" "$runner_stdout_path")
    runner_curl_status=$(sed -n "s/^${prefix}_value_primary_group_curl_status=//p" "$runner_stdout_path")
    runner_primary_helper_status=$(sed -n "s/^${prefix}_value_primary_group_helper_status=//p" "$runner_stdout_path")
    for runner_probe_status in "$runner_bare_root_status" "$runner_sourced_root_status" \
        "$runner_full_group_status" \
        "$runner_interpreter_status" \
        "$runner_environment_status" "$runner_service_status" "$runner_caddy_status" \
        "$runner_curl_status" "$runner_primary_helper_status"; do
        [[ "$runner_probe_status" =~ ^[0-9]+$ ]] || return 97
    done
    runner_reported_classification=$(sed -n "s/^${prefix}_value_classification=//p" "$runner_stdout_path")
    runner_expected_classification=$(classify_probe_statuses \
        "$runner_sourced_root_status" "$runner_full_group_status" \
        "$runner_interpreter_status" \
        "$runner_environment_status" "$runner_service_status" \
        "$runner_caddy_status" "$runner_curl_status" "$runner_primary_helper_status")
    [[ "$runner_reported_classification" = "$runner_expected_classification" ]] || return 97

    require_one "${prefix}_value_environment_scope=vrrp_parent_inherited_environment" \
        "$runner_stdout_path" || return 97
    require_one "${prefix}_value_historical_check_child_environment_recoverable=false" \
        "$runner_stdout_path" || return 97
    if [[ "$runner_bare_root_status" -ne 0 && "$runner_sourced_root_status" -eq 0 ]]; then
        require_one "${prefix}_value_bare_root_environment_dependency=true" \
            "$runner_stdout_path" || return 97
    else
        require_one "${prefix}_value_bare_root_environment_dependency=false" \
            "$runner_stdout_path" || return 97
    fi
    require_one "${prefix}_health_helper_invoked_read_only=true" "$runner_stdout_path" || return 97
    require_one "${prefix}_notification_invoked=false" "$runner_stdout_path" || return 97
    require_one "${prefix}_node_b_contacted=false" "$runner_stdout_path" || return 97
    require_one "${prefix}_filesystem_mutations=false" "$runner_stdout_path" || return 97
    require_one "${prefix}_service_mutations=false" "$runner_stdout_path" || return 97
    require_one "${prefix}_keepalived_mutations=false" "$runner_stdout_path" || return 97
    require_one "${prefix}_vrrp_mutations=false" "$runner_stdout_path" || return 97
    require_one "${prefix}_vip_mutations=false" "$runner_stdout_path" || return 97
    require_one "${prefix}_persistent_mutations=false" "$runner_stdout_path" || return 97
    require_one "${prefix}_remote_complete=true" "$runner_stdout_path" || return 97
    runner_before_hash=$(sed -n "s/^${prefix}_value_before_state_sha256=//p" "$runner_stdout_path")
    runner_after_hash=$(sed -n "s/^${prefix}_value_after_state_sha256=//p" "$runner_stdout_path")
    [[ "$runner_before_hash" =~ ^[0-9a-f]{64}$ ]] || return 97
    [[ "$runner_after_hash" = "$runner_before_hash" ]] || return 1
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_source
        working_directory_approved
        /bin/bash "$diagnostic" --self-test
        printf '%s_runner_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --classification-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$(classify_probe_statuses 0 0 0 0 0 1 0 1)" = supplementary_group_boundary_reproduced_at_caddy_validate ]]
        [[ "$(classify_probe_statuses 0 0 0 0 0 0 0 0)" = managed_failure_not_reproduced_by_read_only_context_probe ]]
        printf '%s_runner_classification_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--self-test|--classification-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

verify_source
working_directory_approved
work_directory=$(mktemp -d /tmp/caddy-action20d-retry8-a-runner.XXXXXX)
readonly work_directory
# shellcheck disable=SC2317
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT
readonly remote_stdout=$work_directory/remote.stdout
readonly remote_stderr=$work_directory/remote.stderr
touch "$remote_stdout" "$remote_stderr"
chmod 0600 "$remote_stdout" "$remote_stderr"
remote_status=0
"$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no \
    -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole0.local.theama.co \
    pi@10.1.0.53 'cd / && sudo -n /bin/bash -s --' <"$diagnostic" \
    >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
readonly remote_status
printf '%s_remote_stdout_bytes=%s\n' "$prefix" "$(wc -c <"$remote_stdout")"
printf '%s_remote_stdout_lines=%s\n' "$prefix" "$(line_count "$remote_stdout")"
printf '%s_remote_stdout_sha256=%s\n' "$prefix" "$(file_hash "$remote_stdout")"
printf '%s_remote_stderr_bytes=%s\n' "$prefix" "$(wc -c <"$remote_stderr")"
printf '%s_remote_stderr_lines=%s\n' "$prefix" "$(line_count "$remote_stderr")"
printf '%s_remote_stderr_sha256=%s\n' "$prefix" "$(file_hash "$remote_stderr")"
if safe_stream "$remote_stdout" && safe_stream "$remote_stderr"; then
    printf '%s_remote_stream_classification=bounded_safe\n' "$prefix"
    printf '%s_remote_stdout_begin\n' "$prefix"
    cat "$remote_stdout"
    printf '%s_remote_stdout_end\n' "$prefix"
    if [[ -s "$remote_stderr" ]]; then
        printf '%s_remote_stderr_begin\n' "$prefix" >&2
        cat "$remote_stderr" >&2
        printf '%s_remote_stderr_end\n' "$prefix" >&2
    else
        printf '%s_remote_stderr_content_secured=empty\n' "$prefix"
    fi
else
    printf '%s_remote_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
validation_status=0
validate_transcript "$remote_stderr" "$remote_stdout" "$remote_status" || validation_status=$?
readonly validation_status
printf '%s_remote_status=%s\n' "$prefix" "$remote_status"
printf '%s_validation_status=%s\n' "$prefix" "$validation_status"
if [[ "$validation_status" -eq 97 ]]; then
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_runner_cleanup_complete=true\n' "$prefix"
exit "$validation_status"
