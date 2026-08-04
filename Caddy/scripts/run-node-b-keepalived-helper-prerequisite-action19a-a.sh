#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19a_a
readonly inspector_sha256=162f153d116e53aba95775836c4a5cb6677ad7fd080c673ca6c5ac8fb0092a0f
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co
readonly expected_assertion_count=61
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector="$script_directory/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"
readonly ssh_binary=${CADDY_ACTION19AA_SSH_BINARY:-ssh}

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
is_nonnegative_integer() { [[ "$1" =~ ^[0-9]+$ ]]; }
is_sha256() { [[ "$1" =~ ^[0-9a-f]{64}$ ]]; }
is_helper_state() { [[ "$1" == absent || "$1" == exact ]]; }
is_observed_helper_hash() { [[ "$1" == absent || "$1" =~ ^[0-9a-f]{64}$ ]]; }

require_local_check() {
    local check_label=$1

    shift
    if "$@"; then
        printf '%s_local_check_%s=true\n' "$prefix" "$check_label"
        return 0
    fi
    printf '%s_local_check_%s=false\n' "$prefix" "$check_label" >&2
    return 1
}

verify_sources() {
    require_local_check inspector_regular test -f "$inspector" || return 1
    require_local_check inspector_not_symlink test ! -L "$inspector" || return 1
    require_local_check inspector_hash_exact test \
        "$(file_hash "$inspector")" = "$inspector_sha256" || return 1
    require_local_check inspector_syntax bash -n "$inspector" || return 1
    require_local_check collision_checker_executable test -x "$collision_checker" ||
        return 1
    require_local_check inspector_collision_policy \
        "$collision_checker" "$inspector" >/dev/null || return 1
    require_local_check inspector_self_test \
        "$inspector" --self-test >/dev/null || return 1
}

# Invoked indirectly through require_local_check.
# shellcheck disable=SC2317
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs)
            return 0
            ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
            return
            ;;
    esac
    return 1
}

safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] ||
        return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null ||
        return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$stream_path"
}

emit_stream_metadata() {
    local stream_name=$1
    local stream_path=$2

    printf '%s_remote_%s_bytes=%s\n' "$prefix" "$stream_name" \
        "$(wc -c <"$stream_path")"
    printf '%s_remote_%s_lines=%s\n' "$prefix" "$stream_name" \
        "$(line_count "$stream_path")"
    printf '%s_remote_%s_sha256=%s\n' "$prefix" "$stream_name" \
        "$(file_hash "$stream_path")"
}

require_one() {
    local required_record=$1
    local transcript_path=$2

    [[ "$(grep -Fxc "$required_record" "$transcript_path")" -eq 1 ]]
}

value_for() {
    local value_key=$1
    local transcript_path=$2
    local value_record

    [[ "$(grep -Ec "^${value_key}=" "$transcript_path")" -eq 1 ]] || return 1
    value_record=$(grep -E "^${value_key}=" "$transcript_path")
    printf '%s\n' "${value_record#*=}"
}

validate_assertion_set() {
    local transcript_path=$1
    local assertion_label
    local expected_path
    local observed_path
    local validation_root

    validation_root=$(mktemp -d /tmp/caddy-action19a-a-labels.XXXXXX) || return 1
    expected_path=$validation_root/expected
    observed_path=$validation_root/observed
    "$inspector" --expected-assertions | LC_ALL=C sort >"$expected_path"
    sed -n "s/^${prefix}_assertion_\([a-z0-9_]*\)=\(true\|false\)$/\1/p" \
        "$transcript_path" | LC_ALL=C sort >"$observed_path"
    if [[ "$(wc -l <"$expected_path")" -ne "$expected_assertion_count" ||
    "$(sort -u "$expected_path" | wc -l)" -ne "$expected_assertion_count" ||
    "$(wc -l <"$observed_path")" -ne "$expected_assertion_count" ||
    "$(sort -u "$observed_path" | wc -l)" -ne "$expected_assertion_count" ]] ||
        ! cmp -s "$expected_path" "$observed_path"; then
        rm -rf -- "$validation_root"
        return 1
    fi
    while IFS= read -r assertion_label; do
        [[ "$(grep -Ec "^${prefix}_assertion_${assertion_label}=(true|false)$" \
            "$transcript_path")" -eq 1 ]] || {
            rm -rf -- "$validation_root"
            return 1
        }
    done <"$expected_path"
    rm -rf -- "$validation_root"
}

evaluate_contract() {
    local error_path=$1
    local output_path=$2
    local observed_remote_status=$3
    local assertion_count
    local failed_count
    local first_failure
    local observed_false_count
    local observed_first_failure
    local health_hash
    local health_state
    local notification_hash
    local notification_state
    local value_key
    local value_record

    [[ "$observed_remote_status" -eq 0 || "$observed_remote_status" -eq 1 ]] ||
        return 1
    [[ ! -s "$error_path" ]] || return 1
    validate_assertion_set "$output_path" || return 1
    assertion_count=$(value_for "${prefix}_assertion_count" "$output_path") ||
        return 1
    failed_count=$(value_for "${prefix}_failed_assertion_count" "$output_path") ||
        return 1
    first_failure=$(value_for "${prefix}_first_failure" "$output_path") ||
        return 1
    is_nonnegative_integer "$assertion_count" || return 1
    is_nonnegative_integer "$failed_count" || return 1
    [[ "$assertion_count" -eq "$expected_assertion_count" ]] || return 1
    observed_false_count=$(grep -Ec \
        "^${prefix}_assertion_[a-z0-9_]+=false$" "$output_path" || true)
    [[ "$failed_count" -eq "$observed_false_count" ]] || return 1
    if [[ "$failed_count" -eq 0 ]]; then
        [[ "$first_failure" == none && "$observed_remote_status" -eq 0 ]] ||
            return 1
    else
        observed_first_failure=$(sed -n \
            "s/^${prefix}_assertion_\([a-z0-9_]*\)=false$/\1/p" \
            "$output_path" | head -n 1)
        [[ "$first_failure" == "$observed_first_failure" &&
            "$observed_remote_status" -eq 1 ]] || return 1
    fi

    health_state=$(value_for "${prefix}_value_health_state" "$output_path") ||
        return 1
    health_hash=$(value_for \
        "${prefix}_value_health_observed_sha256" "$output_path") || return 1
    notification_state=$(value_for \
        "${prefix}_value_notification_state" "$output_path") || return 1
    notification_hash=$(value_for \
        "${prefix}_value_notification_observed_sha256" "$output_path") ||
        return 1
    is_helper_state "$health_state" || return 1
    is_observed_helper_hash "$health_hash" || return 1
    is_helper_state "$notification_state" || return 1
    is_observed_helper_hash "$notification_hash" || return 1
    [[ "$health_state" != absent || "$health_hash" == absent ]] || return 1
    [[ "$health_state" != exact || "$health_hash" != absent ]] || return 1
    [[ "$notification_state" != absent || "$notification_hash" == absent ]] ||
        return 1
    [[ "$notification_state" != exact || "$notification_hash" != absent ]] ||
        return 1

    for value_key in \
        action19a_backup_count action19a_run_stage_count \
        action19a_tmp_stage_count action19a_install_stage_count \
        dns_ipv4_vip_count dns_ipv6_vip_count; do
        value_record=$(value_for "${prefix}_value_${value_key}" "$output_path") ||
            return 1
        is_nonnegative_integer "$value_record" || return 1
    done
    for value_key in before_state_sha256 after_state_sha256; do
        value_record=$(value_for "${prefix}_value_${value_key}" "$output_path") ||
            return 1
        is_sha256 "$value_record" || return 1
    done
    [[ "$(value_for "${prefix}_value_before_state_sha256" "$output_path")" = "$(value_for "${prefix}_value_after_state_sha256" "$output_path")" ]] ||
        return 1

    for value_record in \
        "${prefix}_helper_execution=false" \
        "${prefix}_filesystem_mutations=false" \
        "${prefix}_service_mutations=false" \
        "${prefix}_vrrp_mutations=false" \
        "${prefix}_vip_mutations=false" \
        "${prefix}_persistent_mutations=false" \
        "${prefix}_remote_complete=true"; do
        require_one "$value_record" "$output_path" || return 1
    done
}

write_contract_fixture() {
    local fixture_path=$1
    local fixture_assertion

    {
        while IFS= read -r fixture_assertion; do
            printf '%s_assertion_%s=true\n' "$prefix" "$fixture_assertion"
        done < <("$inspector" --expected-assertions)
        printf '%s\n' \
            "${prefix}_value_health_state=absent" \
            "${prefix}_value_health_observed_sha256=absent" \
            "${prefix}_value_notification_state=absent" \
            "${prefix}_value_notification_observed_sha256=absent" \
            "${prefix}_value_action19a_backup_count=0" \
            "${prefix}_value_action19a_run_stage_count=0" \
            "${prefix}_value_action19a_tmp_stage_count=0" \
            "${prefix}_value_action19a_install_stage_count=0" \
            "${prefix}_value_dns_ipv4_vip_count=0" \
            "${prefix}_value_dns_ipv6_vip_count=0" \
            "${prefix}_value_before_state_sha256=1111111111111111111111111111111111111111111111111111111111111111" \
            "${prefix}_value_after_state_sha256=1111111111111111111111111111111111111111111111111111111111111111" \
            "${prefix}_assertion_count=$expected_assertion_count" \
            "${prefix}_failed_assertion_count=0" \
            "${prefix}_first_failure=none" \
            "${prefix}_helper_execution=false" \
            "${prefix}_filesystem_mutations=false" \
            "${prefix}_service_mutations=false" \
            "${prefix}_vrrp_mutations=false" \
            "${prefix}_vip_mutations=false" \
            "${prefix}_persistent_mutations=false" \
            "${prefix}_remote_complete=true"
    } >"$fixture_path"
}

case "${1:-}" in
    --self-test | --source-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        [[ "$expected_target" = pi@10.1.0.54 ]]
        [[ "$expected_host_alias" = pihole00.local.theama.co ]]
        [[ "$("$inspector" --expected-assertions | wc -l)" -eq "$expected_assertion_count" ]]
        printf '%s_runner_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        contract_directory=$(mktemp -d /tmp/caddy-action19a-a-contract.XXXXXX)
        trap 'rm -rf -- "$contract_directory"' EXIT
        : >"$contract_directory/error"
        write_contract_fixture "$contract_directory/output"
        evaluate_contract "$contract_directory/error" \
            "$contract_directory/output" 0
        sed \
            -e "s/${prefix}_assertion_state_unchanged=true/${prefix}_assertion_state_unchanged=false/" \
            -e "s/${prefix}_failed_assertion_count=0/${prefix}_failed_assertion_count=1/" \
            -e "s/${prefix}_first_failure=none/${prefix}_first_failure=state_unchanged/" \
            "$contract_directory/output" >"$contract_directory/mismatch"
        evaluate_contract "$contract_directory/error" \
            "$contract_directory/mismatch" 1
        printf '%s_runner_contract_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
require_local_check working_directory_approved working_directory_approved
if [[ "$ssh_binary" != ssh ]]; then
    require_local_check intercepted_test_explicit test \
        "${CADDY_ACTION19AA_INTERCEPTED_TEST:-}" = 1
else
    require_local_check production_ssh_binary_exact test "$ssh_binary" = ssh
fi
work_directory=$(mktemp -d /tmp/caddy-action19a-a-runner.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly remote_output_path="$work_directory/remote.stdout"
readonly remote_error_path="$work_directory/remote.stderr"
: >"$remote_output_path"
: >"$remote_error_path"
chmod 0600 "$remote_output_path" "$remote_error_path"

remote_status=0
"$ssh_binary" -T \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=yes \
    -o "HostKeyAlias=$expected_host_alias" \
    "$expected_target" 'cd / && sudo -n /bin/bash -s --' \
    <"$inspector" >"$remote_output_path" 2>"$remote_error_path" ||
    remote_status=$?
readonly remote_status
emit_stream_metadata stdout "$remote_output_path"
emit_stream_metadata stderr "$remote_error_path"
if safe_stream "$remote_output_path" && safe_stream "$remote_error_path"; then
    printf '%s_remote_stream_classification=bounded_safe\n' "$prefix"
    printf '%s_remote_stdout_begin\n' "$prefix"
    cat "$remote_output_path"
    printf '%s_remote_stdout_end\n' "$prefix"
    if [[ -s "$remote_error_path" ]]; then
        printf '%s_remote_stderr_begin\n' "$prefix" >&2
        cat "$remote_error_path" >&2
        printf '%s_remote_stderr_end\n' "$prefix" >&2
    fi
else
    printf '%s_remote_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi

contract_status=0
evaluate_contract "$remote_error_path" "$remote_output_path" "$remote_status" ||
    contract_status=$?
if [[ "$contract_status" -ne 0 ]]; then
    printf '%s_runner_contract_valid=false\n' "$prefix" >&2
    exit 97
fi
printf '%s_runner_contract_valid=true\n' "$prefix"
printf '%s_remote_status=%s\n' "$prefix" "$remote_status"
if [[ "$remote_status" -eq 0 ]]; then
    printf '%s_runner_acceptance=accepted\n' "$prefix"
else
    printf '%s_runner_acceptance=semantic_mismatch\n' "$prefix"
fi
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_workstation_cleanup_complete=true\n' "$prefix"
exit "$remote_status"
