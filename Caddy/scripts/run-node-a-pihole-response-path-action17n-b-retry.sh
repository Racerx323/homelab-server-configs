#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=9194e329c11e2942f8a4ef4cc179a33c452999716b31a6f7cb8f96381e9e5151
readonly historical_inspector_sha256=533278646571fe5aecea3428d7045ea50557d291fcb2e2fa62e752c403336415
readonly historical_runner_sha256=5e1bf0e8bdcf37c683d45979f5ccdd3ae24f20e7e3b555de71805c3fe29983dd
readonly historical_regression_sha256=522dde7b6aab03526da319ac1b69a0750b105bb87e3d880addf8e6e937a1ecb1
readonly collision_checker_sha256=78b46fcdc6c4ca6b4cfe0121c347e0e101c472d723a891aac2dea7f23f085cd8
readonly expected_target=pi@10.1.0.53
readonly expected_host_alias=pihole0.local.theama.co
readonly expected_assertion_count=62
readonly expected_dns_query_count=6

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly inspector="$script_dir/inspect-node-a-pihole-response-path-action17n-b-retry.sh"
readonly historical_inspector="$script_dir/inspect-node-a-pihole-response-path-action17n-b.sh"
readonly historical_runner="$script_dir/run-node-a-pihole-response-path-action17n-b.sh"
readonly historical_regression="$caddy_root/tests/action17n-b-node-a-pihole-response-path-regression.sh"
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
    verify_file "$historical_inspector" "$historical_inspector_sha256"
    verify_file "$historical_runner" "$historical_runner_sha256"
    verify_file "$historical_regression" "$historical_regression_sha256"
    verify_file "$collision_checker" "$collision_checker_sha256"
    bash -n "$inspector" "$historical_inspector" "$historical_runner" \
        "$historical_regression" "$collision_checker"
    "$inspector" --self-test >/dev/null
    "$collision_checker" "$inspector" "$historical_inspector" \
        "$historical_runner" "$historical_regression" "$0" >/dev/null
}

verify_live_sources() {
    local source_path

    verify_sources
    for source_path in \
        "$inspector" "$historical_inspector" "$historical_runner" \
        "$historical_regression" "$collision_checker" "$0"; do
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

validate_secret_free() {
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|DOPPLER_TOKEN|authorization:[[:space:]]*bearer|password=' \
        "$@"
}

validate_structure() {
    local transcript_path=$1
    local total_assertions unique_assertions false_assertions
    local reported_assertions reported_failures before_state after_state
    local dns_value_count

    validate_secret_free "$transcript_path" || return 1
    ! grep -Ev \
        '^(action_17n_b_retry_(remote_reached|assertion_[a-z0-9_]+|observed_[a-z0-9_]+|value_[a-z0-9_]+|assertion_count|failed_assertion_count|first_failure|before_state_sha256|after_state_sha256|conclusion|remote_complete)|remote_paths_created|dns_queries_performed|peer_connections|synchronization_commands_executed|dns_configuration_mutations|nss_configuration_mutations|pihole_cache_reset_performed|service_mutations|persistent_mutations)=' \
        "$transcript_path" |
        grep -q . || return 1
    total_assertions=$(
        grep -Ec '^action_17n_b_retry_assertion_[a-z0-9_]+=(true|false)$' \
            "$transcript_path"
    )
    unique_assertions=$(
        grep -E '^action_17n_b_retry_assertion_[a-z0-9_]+=(true|false)$' \
            "$transcript_path" |
            cut -d= -f1 |
            LC_ALL=C sort -u |
            wc -l
    )
    false_assertions=$(
        grep -Ec '^action_17n_b_retry_assertion_[a-z0-9_]+=false$' \
            "$transcript_path" || true
    )
    [[ "$total_assertions" -eq "$expected_assertion_count" ]] || return 1
    [[ "$unique_assertions" -eq "$expected_assertion_count" ]] || return 1
    reported_assertions=$(value_for action_17n_b_retry_assertion_count "$transcript_path")
    reported_failures=$(
        value_for action_17n_b_retry_failed_assertion_count "$transcript_path"
    )
    [[ "$reported_assertions" -eq "$expected_assertion_count" ]] || return 1
    [[ "$reported_failures" -eq "$false_assertions" ]] || return 1
    dns_value_count=$(
        grep -Ec '^action_17n_b_retry_value_(direct_unbound|local_pihole)_[a-z0-9_]+_(rcode|answer|ttl)=' \
            "$transcript_path"
    )
    [[ "$dns_value_count" -eq $((expected_dns_query_count * 3)) ]] || return 1
    [[ "$(value_for action_17n_b_retry_remote_reached "$transcript_path")" == true ]]
    [[ "$(value_for action_17n_b_retry_remote_complete "$transcript_path")" == true ]]
    [[ "$(value_for remote_paths_created "$transcript_path")" == false ]]
    [[ "$(value_for dns_queries_performed "$transcript_path")" == true ]]
    [[ "$(value_for peer_connections "$transcript_path")" == false ]]
    [[ "$(value_for synchronization_commands_executed "$transcript_path")" == false ]]
    [[ "$(value_for dns_configuration_mutations "$transcript_path")" == false ]]
    [[ "$(value_for nss_configuration_mutations "$transcript_path")" == false ]]
    [[ "$(value_for pihole_cache_reset_performed "$transcript_path")" == false ]]
    [[ "$(value_for service_mutations "$transcript_path")" == false ]]
    [[ "$(value_for persistent_mutations "$transcript_path")" == false ]]
    before_state=$(value_for action_17n_b_retry_before_state_sha256 "$transcript_path")
    after_state=$(value_for action_17n_b_retry_after_state_sha256 "$transcript_path")
    [[ "$before_state" =~ ^[0-9a-f]{64}$ ]]
    [[ "$after_state" == "$before_state" ]]
}

classify_transcript() {
    local transcript_path=$1
    local ssh_status=$2
    local reported_failures

    validate_structure "$transcript_path" || return 97
    reported_failures=$(
        value_for action_17n_b_retry_failed_assertion_count "$transcript_path"
    )
    if [[ "$reported_failures" -eq 0 && "$ssh_status" -eq 0 ]]; then
        return 0
    fi
    if [[ "$reported_failures" -gt 0 && "$ssh_status" -eq 1 ]]; then
        return 1
    fi
    return 97
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_sources
    grep -Fq \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" "$0"
    printf 'action_17n_b_retry_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_live_sources
    printf 'action_17n_b_retry_runner_source_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_live_sources
work_directory=$(mktemp -d /tmp/caddy-action17n-b-retry.XXXXXX)
readonly work_directory
readonly remote_output_path="$work_directory/remote.out"
readonly remote_error_path="$work_directory/remote.err"

cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

set +e
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias="$expected_host_alias" \
    -o StrictHostKeyChecking=yes \
    "$expected_target" \
    "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" \
    <"$inspector" >"$remote_output_path" 2>"$remote_error_path"
ssh_status=$?
set -e

classification_status=97
if [[ ! -s "$remote_error_path" ]] &&
    validate_secret_free "$remote_output_path" "$remote_error_path"; then
    set +e
    classify_transcript "$remote_output_path" "$ssh_status"
    classification_status=$?
    set -e
fi

if [[ "$classification_status" -eq 0 ||
    "$classification_status" -eq 1 ]]; then
    cat "$remote_output_path"
    printf 'action_17n_b_retry_ssh_status=%s\n' "$ssh_status"
    if [[ "$classification_status" -eq 0 ]]; then
        printf 'action_17n_b_retry_runner_classification=observation_complete\n'
    else
        printf 'action_17n_b_retry_runner_classification=semantic_mismatch\n'
    fi
    printf 'action_17n_b_retry_workstation_cleanup=true\n'
    exit "$classification_status"
fi

printf 'action_17n_b_retry_ssh_status=%s\n' "$ssh_status" >&2
printf 'action_17n_b_retry_remote_stdout_sha256=%s\n' \
    "$(file_hash "$remote_output_path")" >&2
printf 'action_17n_b_retry_remote_stderr_sha256=%s\n' \
    "$(file_hash "$remote_error_path")" >&2
printf 'action_17n_b_retry_runner_classification=evidence_failure\n' >&2
printf 'action_17n_b_retry_workstation_cleanup=true\n' >&2
exit 97
