#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=1fb69afe566147e0b471641f62387fe06bb6b0fb1ed1d600cfab5b08f3ba0f80
readonly collision_checker_sha256=78b46fcdc6c4ca6b4cfe0121c347e0e101c472d723a891aac2dea7f23f085cd8
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co
readonly expected_assertion_count=98

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly inspector="$script_dir/inspect-node-b-dns-nss-post-correction-action17m-a.sh"
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
    verify_file "$collision_checker" "$collision_checker_sha256"
    bash -n "$inspector" "$collision_checker"
    "$inspector" --self-test >/dev/null
    "$collision_checker" "$inspector" "$0" >/dev/null
}

verify_live_sources() {
    local source_path

    verify_sources
    for source_path in "$inspector" "$collision_checker" "$0"; do
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
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=|authorization:[[:space:]]*bearer|password=' \
        "$@"
}

validate_line_grammar() {
    local grammar_transcript=$1

    ! grep -Ev \
        '^(action_17m_a_(remote_reached|assertion_[a-z0-9_]+|observed_[a-z0-9_]+|assertion_count|failed_assertion_count|first_failure|before_state_sha256|after_state_sha256|conclusion|remote_complete)|remote_paths_created|dns_queries_performed|peer_connections|synchronization_commands_executed|dns_configuration_mutations|nss_configuration_mutations|service_mutations|persistent_mutations)=' \
        "$grammar_transcript" |
        grep -q .
}

validate_structure() {
    local transcript_path=$1
    local total_assertions unique_assertions false_assertions
    local observed_assertions reported_assertions reported_failures
    local reported_first_failure before_state after_state expected_first_failure

    validate_secret_free "$transcript_path" || return 1
    validate_line_grammar "$transcript_path" || return 1
    total_assertions=$(
        grep -Ec '^action_17m_a_assertion_[a-z0-9_]+=(true|false)$' \
            "$transcript_path"
    )
    unique_assertions=$(
        grep -E '^action_17m_a_assertion_[a-z0-9_]+=(true|false)$' \
            "$transcript_path" |
            cut -d= -f1 |
            LC_ALL=C sort -u |
            wc -l
    )
    false_assertions=$(
        grep -Ec '^action_17m_a_assertion_[a-z0-9_]+=false$' \
            "$transcript_path" || true
    )
    observed_assertions=$(
        grep -Ec '^action_17m_a_observed_[a-z0-9_]+=' \
            "$transcript_path" || true
    )
    [[ "$total_assertions" -eq "$expected_assertion_count" ]] || return 1
    [[ "$unique_assertions" -eq "$expected_assertion_count" ]] || return 1
    [[ "$observed_assertions" -eq "$false_assertions" ]] || return 1

    reported_assertions=$(value_for action_17m_a_assertion_count "$transcript_path")
    reported_failures=$(
        value_for action_17m_a_failed_assertion_count "$transcript_path"
    )
    reported_first_failure=$(
        value_for action_17m_a_first_failure "$transcript_path"
    )
    [[ "$reported_assertions" -eq "$expected_assertion_count" ]] || return 1
    [[ "$reported_failures" -eq "$false_assertions" ]] || return 1
    if [[ "$false_assertions" -eq 0 ]]; then
        [[ "$reported_first_failure" == none ]] || return 1
        require_value action_17m_a_conclusion \
            post_correction_state_verified "$transcript_path" || return 1
    else
        expected_first_failure=$(
            grep -E '^action_17m_a_assertion_[a-z0-9_]+=false$' \
                "$transcript_path" |
                head -n 1 |
                sed 's/^action_17m_a_assertion_//; s/=false$//'
        )
        [[ "$reported_first_failure" == "$expected_first_failure" ]] ||
            return 1
        require_value action_17m_a_conclusion \
            post_correction_state_mismatch "$transcript_path" || return 1
    fi

    require_value action_17m_a_remote_reached true "$transcript_path" ||
        return 1
    require_value action_17m_a_remote_complete true "$transcript_path" ||
        return 1
    require_value remote_paths_created false "$transcript_path" || return 1
    require_value dns_queries_performed true "$transcript_path" || return 1
    require_value peer_connections false "$transcript_path" || return 1
    require_value synchronization_commands_executed false \
        "$transcript_path" || return 1
    require_value dns_configuration_mutations false "$transcript_path" ||
        return 1
    require_value nss_configuration_mutations false "$transcript_path" ||
        return 1
    require_value service_mutations false "$transcript_path" || return 1
    require_value persistent_mutations false "$transcript_path" || return 1

    before_state=$(value_for action_17m_a_before_state_sha256 "$transcript_path")
    after_state=$(value_for action_17m_a_after_state_sha256 "$transcript_path")
    [[ "$before_state" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$after_state" == "$before_state" ]] || return 1
}

classify_transcript() {
    local transcript_path=$1
    local ssh_exit_status=$2
    local reported_failures

    validate_structure "$transcript_path" || return 97
    reported_failures=$(
        value_for action_17m_a_failed_assertion_count "$transcript_path"
    )
    if [[ "$reported_failures" -eq 0 && "$ssh_exit_status" -eq 0 ]]; then
        return 0
    fi
    if [[ "$reported_failures" -gt 0 && "$ssh_exit_status" -eq 1 ]]; then
        return 1
    fi
    return 97
}

write_fixture() {
    local fixture_path=$1
    local false_label=${2:-}
    local fixture_index fixture_value
    local failed_count=0
    local first_failure=none
    local conclusion=post_correction_state_verified

    printf 'action_17m_a_remote_reached=true\n' >"$fixture_path"
    for ((fixture_index = 1; fixture_index <= expected_assertion_count; fixture_index += 1)); do
        fixture_value=true
        if [[ "$false_label" == "fixture_${fixture_index}" ]]; then
            fixture_value=false
            failed_count=1
            first_failure=$false_label
            conclusion=post_correction_state_mismatch
        fi
        printf 'action_17m_a_assertion_fixture_%02d=%s\n' \
            "$fixture_index" "$fixture_value"
        if [[ "$fixture_value" == false ]]; then
            printf 'action_17m_a_observed_fixture_%02d=mismatch\n' \
                "$fixture_index"
        fi
    done >>"$fixture_path"
    printf '%s\n' \
        "action_17m_a_assertion_count=$expected_assertion_count" \
        "action_17m_a_failed_assertion_count=$failed_count" \
        "action_17m_a_first_failure=$first_failure" \
        action_17m_a_before_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        action_17m_a_after_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        remote_paths_created=false \
        dns_queries_performed=true \
        peer_connections=false \
        synchronization_commands_executed=false \
        dns_configuration_mutations=false \
        nss_configuration_mutations=false \
        service_mutations=false \
        persistent_mutations=false \
        "action_17m_a_conclusion=$conclusion" \
        action_17m_a_remote_complete=true \
        >>"$fixture_path"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_sources
    grep -Fq \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" "$0"
    printf 'action_17m_a_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_live_sources
    printf 'action_17m_a_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_directory=$(mktemp -d /tmp/caddy-action17m-a-contract.XXXXXX)
    trap 'rm -rf -- "$contract_directory"' EXIT
    success_fixture="$contract_directory/success"
    mismatch_fixture="$contract_directory/mismatch"
    duplicate_fixture="$contract_directory/duplicate"
    unsafe_fixture="$contract_directory/unsafe"
    malformed_fixture="$contract_directory/malformed"

    write_fixture "$success_fixture"
    classify_transcript "$success_fixture" 0
    write_fixture "$mismatch_fixture" fixture_17
    set +e
    classify_transcript "$mismatch_fixture" 1
    mismatch_status=$?
    set -e
    [[ "$mismatch_status" -eq 1 ]]
    cp -- "$success_fixture" "$duplicate_fixture"
    printf 'action_17m_a_assertion_fixture_01=true\n' >>"$duplicate_fixture"
    set +e
    classify_transcript "$duplicate_fixture" 0
    duplicate_status=$?
    set -e
    [[ "$duplicate_status" -eq 97 ]]
    cp -- "$success_fixture" "$unsafe_fixture"
    printf 'DOPPLER_TOKEN=not-a-real-secret\n' >>"$unsafe_fixture"
    set +e
    classify_transcript "$unsafe_fixture" 0
    unsafe_status=$?
    set -e
    [[ "$unsafe_status" -eq 97 ]]
    cp -- "$success_fixture" "$malformed_fixture"
    printf 'unexpected_line=true\n' >>"$malformed_fixture"
    set +e
    classify_transcript "$malformed_fixture" 0
    malformed_status=$?
    set -e
    [[ "$malformed_status" -eq 97 ]]
    printf 'action_17m_a_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_live_sources
work_directory=$(mktemp -d /tmp/caddy-action17m-a.XXXXXX)
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
    printf 'action_17m_a_ssh_status=%s\n' "$ssh_status"
    printf 'action_17m_a_runner_classification=%s\n' \
        "$(if [[ "$classification_status" -eq 0 ]]; then
            printf verified
        else
            printf semantic_mismatch
        fi)"
    printf 'action_17m_a_workstation_cleanup=true\n'
    exit "$classification_status"
fi

printf 'action_17m_a_ssh_status=%s\n' "$ssh_status" >&2
printf 'action_17m_a_remote_stdout_sha256=%s\n' \
    "$(file_hash "$remote_output_path")" >&2
printf 'action_17m_a_remote_stderr_sha256=%s\n' \
    "$(file_hash "$remote_error_path")" >&2
printf 'action_17m_a_runner_classification=evidence_failure\n' >&2
printf 'action_17m_a_workstation_cleanup=true\n' >&2
exit 97
