#!/usr/bin/env bash
# shellcheck disable=SC2016 # Assert literal remote shell source.

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=75986f675f0805bea87c7ce01b37fdb6c778575b14e98442556511d73b5044c5
readonly regression_sha256=8fbf93af2f2f13a0e5e991d7f55242aa1f3baab9b4eee69cfd53e8bd4b1b38d3
readonly action17i_runner_sha256=a5d1212984b505e52392f2fcf36ba874a14fd6b075c9b7062fb507527675bac3
readonly action17j_runner_sha256=d13108ab496b2829e750c8a475225e5fdd448f9cf47bdaac8d96efecc53a00e6
readonly collision_checker_sha256=78b46fcdc6c4ca6b4cfe0121c347e0e101c472d723a891aac2dea7f23f085cd8
readonly accepted_live_state_sha256=7b00e0d91512674b446e3b783db77351f8686b867ccf8ccd02283aa7abba6b74
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly candidate_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly expected_assertion_count=70
readonly expected_target=pi@10.1.0.53
readonly expected_host_alias=pihole0.local.theama.co

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly inspector="$script_dir/inspect-node-a-unbound-dual-stage-action17j-a.sh"
readonly regression="$caddy_root/tests/action17j-a-node-a-dual-stage-acceptance-regression.sh"
readonly action17i_runner="$script_dir/run-node-a-unbound-primary-stage-action17i.sh"
readonly action17j_runner="$script_dir/run-node-a-unbound-local-zone-stage-action17j.sh"
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
    verify_file "$action17i_runner" "$action17i_runner_sha256"
    verify_file "$action17j_runner" "$action17j_runner_sha256"
    verify_file "$collision_checker" "$collision_checker_sha256"
    bash -n \
        "$inspector" "$regression" "$action17i_runner" "$action17j_runner" \
        "$collision_checker"
    "$inspector" --self-test >/dev/null
    "$collision_checker" "$inspector" "$0" "$regression" >/dev/null
}

verify_live_sources() {
    local verified_source

    verify_sources
    for verified_source in \
        "$inspector" "$regression" "$action17i_runner" "$action17j_runner" \
        "$collision_checker" "$0"; do
        [[ "$(stat -c '%U:%G:%a' "$verified_source")" == aaron:aaron:755 ]]
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

validate_safe_output() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=|private-domain:|local-data(-ptr)?:' \
        "$@"
}

validate_structure() {
    local transcript_path=$1
    local assertion_lines unique_assertion_lines
    local assertion_failures reported_failures
    local first_failure conclusion
    local required_key
    local -a required_keys=(
        action_17j_a_remote_reached
        live_primary_sha256
        live_parser_status
        primary_candidate_sha256
        primary_manifest_check_status
        local_zone_candidate_sha256
        local_zone_manifest_check_status
        combined_parser_status
        live_state_one_status
        live_state_one_sha256
        live_state_two_status
        live_state_two_sha256
        action_17j_a_assertion_count
        action_17j_a_failed_assertion_count
        action_17j_a_first_failure
        action_17j_a_conclusion
        remote_paths_created
        dns_queries_performed
        dns_configuration_mutations
        service_mutations
        persistent_mutations
        action_17j_a_remote_complete
    )

    for required_key in "${required_keys[@]}"; do
        [[ "$(grep -Ec "^${required_key}=" "$transcript_path")" -eq 1 ]] ||
            return 1
    done
    assertion_lines=$(
        grep -Ec '^action_17j_a_assertion_[a-z0-9_]+=((true)|(false))$' \
            "$transcript_path"
    )
    unique_assertion_lines=$(
        grep -E '^action_17j_a_assertion_[a-z0-9_]+=((true)|(false))$' \
            "$transcript_path" |
            cut -d= -f1 |
            LC_ALL=C sort -u |
            wc -l
    )
    assertion_failures=$(
        grep -Ec '^action_17j_a_assertion_[a-z0-9_]+=false$' \
            "$transcript_path" || true
    )
    reported_failures=$(
        value_for action_17j_a_failed_assertion_count "$transcript_path"
    )
    first_failure=$(value_for action_17j_a_first_failure "$transcript_path")
    conclusion=$(value_for action_17j_a_conclusion "$transcript_path")

    [[ "$assertion_lines" -eq "$expected_assertion_count" ]] || return 1
    [[ "$unique_assertion_lines" -eq "$expected_assertion_count" ]] ||
        return 1
    [[ "$reported_failures" =~ ^[0-9]+$ ]] || return 1
    [[ "$assertion_failures" -eq "$reported_failures" ]] || return 1
    require_value action_17j_a_assertion_count \
        "$expected_assertion_count" "$transcript_path" || return 1
    if [[ "$reported_failures" -eq 0 ]]; then
        [[ "$first_failure" == none ]] || return 1
        [[ "$conclusion" == dual_stage_and_live_continuity_verified ]] ||
            return 1
    else
        [[ "$first_failure" =~ ^[a-z0-9_]+$ ]] || return 1
        [[ "$(grep -Fxc \
            "action_17j_a_assertion_${first_failure}=false" \
            "$transcript_path")" -eq 1 ]] || return 1
        [[ "$conclusion" == dual_stage_or_live_continuity_mismatch ]] ||
            return 1
    fi

    require_value primary_candidate_sha256 \
        "$candidate_primary_sha256" "$transcript_path" || return 1
    require_value local_zone_candidate_sha256 \
        "$candidate_local_zone_sha256" "$transcript_path" || return 1
    require_value live_state_one_sha256 \
        "$accepted_live_state_sha256" "$transcript_path" || return 1
    require_value live_state_two_sha256 \
        "$accepted_live_state_sha256" "$transcript_path" || return 1
    require_value remote_paths_created false "$transcript_path" || return 1
    require_value dns_queries_performed false "$transcript_path" || return 1
    require_value dns_configuration_mutations false "$transcript_path" ||
        return 1
    require_value service_mutations false "$transcript_path" || return 1
    require_value persistent_mutations false "$transcript_path" || return 1
    require_value action_17j_a_remote_complete true "$transcript_path" ||
        return 1
}

classify_transcript() {
    local transcript_path=$1
    local ssh_exit_status=$2
    local reported_failures

    validate_structure "$transcript_path" || return 97
    reported_failures=$(
        value_for action_17j_a_failed_assertion_count "$transcript_path"
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
    local false_index=${2:-0}
    local fixture_index fixture_value
    local failure_count=0
    local first_failure=none
    local conclusion=dual_stage_and_live_continuity_verified

    printf '%s\n' \
        action_17j_a_remote_reached=true \
        live_primary_sha256=dd5af7ccbbac11324921e1d447d753dbab33b633bc4cb1db248ee0574825d3ae \
        live_parser_status=0 \
        "primary_candidate_sha256=$candidate_primary_sha256" \
        primary_manifest_check_status=0 \
        "local_zone_candidate_sha256=$candidate_local_zone_sha256" \
        local_zone_manifest_check_status=0 \
        combined_parser_status=0 \
        live_state_one_status=0 \
        "live_state_one_sha256=$accepted_live_state_sha256" \
        live_state_two_status=0 \
        "live_state_two_sha256=$accepted_live_state_sha256" \
        >"$fixture_path"
    for ((fixture_index = 1; fixture_index <= expected_assertion_count; fixture_index += 1)); do
        fixture_value=true
        if [[ "$fixture_index" -eq "$false_index" ]]; then
            fixture_value=false
            failure_count=1
            first_failure="fixture_${fixture_index}"
            conclusion=dual_stage_or_live_continuity_mismatch
        fi
        printf 'action_17j_a_assertion_fixture_%s=%s\n' \
            "$fixture_index" "$fixture_value"
    done >>"$fixture_path"
    printf '%s\n' \
        "action_17j_a_assertion_count=$expected_assertion_count" \
        "action_17j_a_failed_assertion_count=$failure_count" \
        "action_17j_a_first_failure=$first_failure" \
        "action_17j_a_conclusion=$conclusion" \
        remote_paths_created=false \
        dns_queries_performed=false \
        dns_configuration_mutations=false \
        service_mutations=false \
        persistent_mutations=false \
        action_17j_a_remote_complete=true \
        >>"$fixture_path"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_sources
    grep -Fq \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" \
        "$0"
    printf 'action_17j_a_node_a_dual_stage_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_live_sources
    printf 'action_17j_a_node_a_dual_stage_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_directory=$(mktemp -d /tmp/caddy-action17j-a-contract.XXXXXX)
    trap 'rm -rf -- "$contract_directory"' EXIT
    success_fixture="$contract_directory/success"
    mismatch_fixture="$contract_directory/mismatch"
    duplicate_fixture="$contract_directory/duplicate"
    unsafe_fixture="$contract_directory/unsafe"
    write_fixture "$success_fixture"
    classify_transcript "$success_fixture" 0

    write_fixture "$mismatch_fixture" 17
    set +e
    classify_transcript "$mismatch_fixture" 1
    mismatch_status=$?
    set -e
    [[ "$mismatch_status" -eq 1 ]]

    cp -- "$success_fixture" "$duplicate_fixture"
    printf 'action_17j_a_assertion_fixture_1=true\n' >>"$duplicate_fixture"
    set +e
    classify_transcript "$duplicate_fixture" 0
    duplicate_status=$?
    set -e
    [[ "$duplicate_status" -eq 97 ]]

    cp -- "$success_fixture" "$unsafe_fixture"
    printf '%s\n' 'local-data: "private.example. A 192.0.2.1"' \
        >>"$unsafe_fixture"
    if validate_safe_output "$unsafe_fixture"; then
        printf 'Private Action 17j-a output was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17j_a_node_a_dual_stage_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_live_sources
work_directory=$(mktemp -d /tmp/caddy-action17j-a.XXXXXX)
readonly work_directory
readonly remote_output="$work_directory/remote.out"
readonly remote_error="$work_directory/remote.err"

cleanup() {
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

finish() {
    local finish_status=$1

    cleanup
    trap - EXIT
    if [[ -e "$work_directory" || -L "$work_directory" ]]; then
        printf 'action_17j_a_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_17j_a_local_cleanup_complete=true\n'
    exit "$finish_status"
}

ssh_status=0
set +e
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o "HostKeyAlias=$expected_host_alias" \
    -o StrictHostKeyChecking=yes \
    "$expected_target" \
    "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" \
    <"$inspector" >"$remote_output" 2>"$remote_error"
ssh_status=$?
set -e

cat "$remote_output"
cat "$remote_error" >&2
printf 'ssh_exit_status=%s\n' "$ssh_status"
if ! validate_safe_output "$remote_output" "$remote_error"; then
    printf 'Unsafe Action 17j-a output detected.\n' >&2
    finish 97
fi
set +e
classify_transcript "$remote_output" "$ssh_status"
classification_status=$?
set -e
case "$classification_status" in
    0)
        [[ ! -s "$remote_error" ]] || {
            printf 'Action 17j-a emitted unexpected stderr.\n' >&2
            finish 97
        }
        printf 'action_17j_a_node_a_dual_stage_accepted=true\n'
        finish 0
        ;;
    1)
        printf 'action_17j_a_node_a_dual_stage_accepted=false\n'
        finish 1
        ;;
    *)
        printf 'Action 17j-a authoritative evidence contract failed.\n' >&2
        finish 97
        ;;
esac
