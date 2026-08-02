#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=7b40a70f7ef2f90d7b46d9d960444ab9b0e8fd13582f19540014ef3d7f9b0f78
readonly collision_checker_sha256=78b46fcdc6c4ca6b4cfe0121c347e0e101c472d723a891aac2dea7f23f085cd8
readonly expected_assertion_count=29
readonly expected_transcript_lines=59
readonly node_a_ipv6=fd36:5aa8:6971:1::53
readonly node_a_fqdn=pihole0.local.theama.co

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly inspector="$script_dir/inspect-dns-vip-response-path-action17m-b.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"
readonly -a assertion_labels=(
    command_awk_available
    command_dig_available
    command_grep_available
    command_hostname_available
    command_id_available
    command_ip_available
    command_sed_available
    command_sha256sum_available
    command_sort_available
    command_stat_available
    command_systemctl_available
    command_timeout_available
    uid_is_root
    working_directory_is_root
    hostname_matches
    live_local_zone_regular
    live_local_zone_hash
    live_local_zone_metadata
    unbound_active
    pihole_ftl_active
    direct_unbound_node_a_aaaa_status
    direct_unbound_node_a_ptr6_status
    local_pihole_node_a_aaaa_status
    local_pihole_node_a_ptr6_status
    dns_vip_ipv4_node_a_aaaa_status
    dns_vip_ipv4_node_a_ptr6_status
    dns_vip_ipv6_node_a_aaaa_status
    dns_vip_ipv6_node_a_ptr6_status
    state_unchanged
)

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
        'BEGIN [A-Z ]*PRIVATE KEY|DOPPLER_TOKEN|authorization:[[:space:]]*bearer|password=' \
        "$@"
}

validate_node_transcript() {
    local expected_role=$1
    local transcript_path=$2
    local assertion_total assertion_unique before_state after_state
    local expected_local_zone_hash required_value_label

    validate_secret_free "$transcript_path" || return 1
    [[ "$(wc -l <"$transcript_path")" -eq "$expected_transcript_lines" ]] ||
        return 1
    ! grep -Ev \
        '^(action_17m_b_(remote_reached|node_role|assertion_[a-z0-9_]+|value_[a-z0-9_]+|assertion_count|failed_assertion_count|first_failure|before_state_sha256|after_state_sha256|conclusion|remote_complete)|remote_paths_created|dns_queries_performed|peer_connections|synchronization_commands_executed|dns_configuration_mutations|nss_configuration_mutations|service_mutations|persistent_mutations)=' \
        "$transcript_path" |
        grep -q . || return 1
    assertion_total=$(
        grep -Ec '^action_17m_b_assertion_[a-z0-9_]+=true$' \
            "$transcript_path"
    )
    assertion_unique=$(
        grep -E '^action_17m_b_assertion_[a-z0-9_]+=true$' \
            "$transcript_path" |
            cut -d= -f1 |
            LC_ALL=C sort -u |
            wc -l
    )
    [[ "$assertion_total" -eq "$expected_assertion_count" ]] || return 1
    [[ "$assertion_unique" -eq "$expected_assertion_count" ]] || return 1
    ! grep -Eq '^action_17m_b_(assertion_[a-z0-9_]+=false|observed_)' \
        "$transcript_path" || return 1
    require_value action_17m_b_node_role "$expected_role" "$transcript_path" ||
        return 1
    require_value action_17m_b_assertion_count 29 "$transcript_path" ||
        return 1
    require_value action_17m_b_failed_assertion_count 0 "$transcript_path" ||
        return 1
    require_value action_17m_b_first_failure none "$transcript_path" ||
        return 1
    require_value action_17m_b_conclusion node_observation_complete \
        "$transcript_path" || return 1
    require_value action_17m_b_remote_reached true "$transcript_path" ||
        return 1
    require_value action_17m_b_remote_complete true "$transcript_path" ||
        return 1
    if [[ "$expected_role" == node-a ]]; then
        expected_local_zone_hash=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
    else
        expected_local_zone_hash=c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4
    fi
    require_value action_17m_b_value_local_zone_sha256 \
        "$expected_local_zone_hash" "$transcript_path" || return 1
    for required_value_label in \
        ipv4_vip_owned ipv6_vip_owned ipv4_vip_interface \
        ipv6_vip_interface direct_unbound_node_a_aaaa_answer \
        direct_unbound_node_a_ptr6_answer local_pihole_node_a_aaaa_answer \
        local_pihole_node_a_ptr6_answer dns_vip_ipv4_node_a_aaaa_answer \
        dns_vip_ipv4_node_a_ptr6_answer dns_vip_ipv6_node_a_aaaa_answer \
        dns_vip_ipv6_node_a_ptr6_answer; do
        value_for "action_17m_b_value_$required_value_label" \
            "$transcript_path" >/dev/null || return 1
    done
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
    before_state=$(
        value_for action_17m_b_before_state_sha256 "$transcript_path"
    )
    after_state=$(
        value_for action_17m_b_after_state_sha256 "$transcript_path"
    )
    [[ "$before_state" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$after_state" == "$before_state" ]] || return 1
}

answer_for() {
    local node_prefix=$1
    local answer_label=$2
    local node_a_transcript=$3
    local node_b_transcript=$4

    if [[ "$node_prefix" == node_a ]]; then
        value_for "action_17m_b_value_${answer_label}_answer" \
            "$node_a_transcript"
    else
        value_for "action_17m_b_value_${answer_label}_answer" \
            "$node_b_transcript"
    fi
}

matches_node_a_pending_zone() {
    local node_a_transcript=$1
    local node_b_transcript=$2
    local vip_label caller_prefix local_answer vip_answer

    require_value action_17m_b_value_ipv4_vip_owned true \
        "$node_a_transcript" || return 1
    require_value action_17m_b_value_ipv6_vip_owned true \
        "$node_a_transcript" || return 1
    require_value action_17m_b_value_ipv4_vip_owned false \
        "$node_b_transcript" || return 1
    require_value action_17m_b_value_ipv6_vip_owned false \
        "$node_b_transcript" || return 1
    require_value action_17m_b_value_direct_unbound_node_a_aaaa_answer \
        "$node_a_ipv6" "$node_b_transcript" || return 1
    require_value action_17m_b_value_direct_unbound_node_a_ptr6_answer \
        "$node_a_fqdn" "$node_b_transcript" || return 1
    [[ "$(value_for action_17m_b_value_direct_unbound_node_a_aaaa_answer \
        "$node_a_transcript")" != "$node_a_ipv6" ]] || return 1
    [[ "$(value_for action_17m_b_value_direct_unbound_node_a_ptr6_answer \
        "$node_a_transcript")" != "$node_a_fqdn" ]] || return 1

    for caller_prefix in node_a node_b; do
        for vip_label in node_a_aaaa node_a_ptr6; do
            local_answer=$(
                answer_for node_a "local_pihole_${vip_label}" \
                    "$node_a_transcript" "$node_b_transcript"
            )
            vip_answer=$(
                answer_for "$caller_prefix" "dns_vip_ipv4_${vip_label}" \
                    "$node_a_transcript" "$node_b_transcript"
            )
            [[ "$vip_answer" == "$local_answer" ]] || return 1
            vip_answer=$(
                answer_for "$caller_prefix" "dns_vip_ipv6_${vip_label}" \
                    "$node_a_transcript" "$node_b_transcript"
            )
            [[ "$vip_answer" == "$local_answer" ]] || return 1
        done
    done
}

classify_complete_evidence() {
    local node_a_transcript=$1
    local node_b_transcript=$2
    local a_v4 a_v6 b_v4 b_v6

    a_v4=$(value_for action_17m_b_value_ipv4_vip_owned "$node_a_transcript")
    a_v6=$(value_for action_17m_b_value_ipv6_vip_owned "$node_a_transcript")
    b_v4=$(value_for action_17m_b_value_ipv4_vip_owned "$node_b_transcript")
    b_v6=$(value_for action_17m_b_value_ipv6_vip_owned "$node_b_transcript")
    if matches_node_a_pending_zone "$node_a_transcript" "$node_b_transcript"; then
        printf 'node_a_vip_owner_pending_local_zone_advance\n'
        return 0
    fi
    if [[ "$a_v4" == true && "$a_v6" == true &&
        "$b_v4" == false && "$b_v6" == false ]]; then
        printf 'node_a_owner_response_path_not_explained\n'
    elif [[ "$a_v4" == false && "$a_v6" == false &&
        "$b_v4" == true && "$b_v6" == true ]]; then
        printf 'node_b_vip_owner_unexpected_response\n'
    elif [[ "$a_v4" != "$a_v6" || "$b_v4" != "$b_v6" ]]; then
        printf 'split_dual_stack_vip_ownership\n'
    else
        printf 'invalid_or_duplicate_vip_ownership\n'
    fi
    return 1
}

write_fixture() {
    local fixture_role=$1
    local fixture_path=$2
    local assertion_label fixture_owner fixture_hash direct_aaaa direct_ptr

    if [[ "$fixture_role" == node-a ]]; then
        fixture_owner=true
        fixture_hash=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
        direct_aaaa=none
        direct_ptr=none
    else
        fixture_owner=false
        fixture_hash=c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4
        direct_aaaa=$node_a_ipv6
        direct_ptr=$node_a_fqdn
    fi
    {
        printf 'action_17m_b_remote_reached=true\n'
        printf 'action_17m_b_node_role=%s\n' "$fixture_role"
        for assertion_label in "${assertion_labels[@]}"; do
            printf 'action_17m_b_assertion_%s=true\n' "$assertion_label"
        done
        printf 'action_17m_b_value_ipv4_vip_owned=%s\n' "$fixture_owner"
        printf 'action_17m_b_value_ipv6_vip_owned=%s\n' "$fixture_owner"
        printf 'action_17m_b_value_ipv4_vip_interface=%s\n' \
            "$(if [[ "$fixture_owner" == true ]]; then printf eth0; else printf none; fi)"
        printf 'action_17m_b_value_ipv6_vip_interface=%s\n' \
            "$(if [[ "$fixture_owner" == true ]]; then printf eth0; else printf none; fi)"
        printf 'action_17m_b_value_local_zone_sha256=%s\n' "$fixture_hash"
        printf 'action_17m_b_value_direct_unbound_node_a_aaaa_answer=%s\n' "$direct_aaaa"
        printf 'action_17m_b_value_direct_unbound_node_a_ptr6_answer=%s\n' "$direct_ptr"
        printf 'action_17m_b_value_local_pihole_node_a_aaaa_answer=none\n'
        printf 'action_17m_b_value_local_pihole_node_a_ptr6_answer=pi.hole\n'
        printf 'action_17m_b_value_dns_vip_ipv4_node_a_aaaa_answer=none\n'
        printf 'action_17m_b_value_dns_vip_ipv4_node_a_ptr6_answer=pi.hole\n'
        printf 'action_17m_b_value_dns_vip_ipv6_node_a_aaaa_answer=none\n'
        printf 'action_17m_b_value_dns_vip_ipv6_node_a_ptr6_answer=pi.hole\n'
        printf 'action_17m_b_assertion_count=29\n'
        printf 'action_17m_b_failed_assertion_count=0\n'
        printf 'action_17m_b_first_failure=none\n'
        printf 'action_17m_b_before_state_sha256=%064d\n' 0
        printf 'action_17m_b_after_state_sha256=%064d\n' 0
        printf 'remote_paths_created=false\n'
        printf 'dns_queries_performed=true\n'
        printf 'peer_connections=false\n'
        printf 'synchronization_commands_executed=false\n'
        printf 'dns_configuration_mutations=false\n'
        printf 'nss_configuration_mutations=false\n'
        printf 'service_mutations=false\n'
        printf 'persistent_mutations=false\n'
        printf 'action_17m_b_conclusion=node_observation_complete\n'
        printf 'action_17m_b_remote_complete=true\n'
    } >"$fixture_path"
}

contract_test() {
    local contract_conclusion contract_directory contract_status duplicate_fixture
    local node_a_fixture node_b_fixture split_fixture unsafe_fixture

    contract_directory=$(mktemp -d /tmp/caddy-action17m-b-contract.XXXXXX)
    node_a_fixture="$contract_directory/node-a"
    node_b_fixture="$contract_directory/node-b"
    trap 'rm -rf -- "$contract_directory"' RETURN
    write_fixture node-a "$node_a_fixture"
    write_fixture node-b "$node_b_fixture"
    validate_node_transcript node-a "$node_a_fixture"
    validate_node_transcript node-b "$node_b_fixture"
    contract_conclusion=$(
        classify_complete_evidence "$node_a_fixture" "$node_b_fixture"
    )
    [[ "$contract_conclusion" == node_a_vip_owner_pending_local_zone_advance ]]
    duplicate_fixture="$contract_directory/duplicate"
    cp -- "$node_a_fixture" "$duplicate_fixture"
    printf 'action_17m_b_assertion_uid_is_root=true\n' >>"$duplicate_fixture"
    if validate_node_transcript node-a "$duplicate_fixture"; then
        return 1
    fi
    unsafe_fixture="$contract_directory/unsafe"
    cp -- "$node_a_fixture" "$unsafe_fixture"
    sed -i \
        's/action_17m_b_value_ipv4_vip_interface=eth0/password=secret/' \
        "$unsafe_fixture"
    if validate_node_transcript node-a "$unsafe_fixture"; then
        return 1
    fi
    split_fixture="$contract_directory/split"
    cp -- "$node_a_fixture" "$split_fixture"
    sed -i \
        's/action_17m_b_value_ipv6_vip_owned=true/action_17m_b_value_ipv6_vip_owned=false/' \
        "$split_fixture"
    set +e
    contract_conclusion=$(
        classify_complete_evidence "$split_fixture" "$node_b_fixture"
    )
    contract_status=$?
    set -e
    [[ "$contract_status" -eq 1 ]]
    [[ "$contract_conclusion" == split_dual_stack_vip_ownership ]]
    printf 'action_17m_b_runner_contract_test_complete=true\n'
}

self_test() {
    [[ "$expected_assertion_count" -eq 29 ]]
    [[ "$expected_transcript_lines" -eq 59 ]]
    [[ "${#assertion_labels[@]}" -eq 29 ]]
    verify_sources
    printf 'action_17m_b_runner_self_test_complete=true\n'
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        self_test
        exit 0
        ;;
    --source-test)
        [[ $# -eq 1 ]]
        verify_live_sources
        printf 'action_17m_b_runner_source_test_complete=true\n'
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]]
        contract_test
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 2
        ;;
esac

verify_live_sources
work_directory=$(mktemp -d /tmp/caddy-action17m-b.XXXXXX)
readonly work_directory
trap 'rm -rf -- "$work_directory"' EXIT
node_a_remote_transcript="$work_directory/node-a.transcript"
readonly node_a_remote_transcript
node_b_remote_transcript="$work_directory/node-b.transcript"
readonly node_b_remote_transcript

run_remote() {
    local remote_role=$1
    local remote_target=$2
    local remote_alias=$3
    local transcript_path=$4
    local remote_status=0

    set +e
    ssh -T \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o HostKeyAlias="$remote_alias" \
        -o StrictHostKeyChecking=yes \
        "$remote_target" \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s -- --role $remote_role'" \
        <"$inspector" >"$transcript_path" 2>&1
    remote_status=$?
    set -e
    [[ "$remote_status" -eq 0 ]] || return 97
    validate_node_transcript "$remote_role" "$transcript_path" || return 97
}

runner_status=97
if run_remote node-a pi@10.1.0.53 pihole0.local.theama.co \
    "$node_a_remote_transcript" &&
    run_remote node-b pi@10.1.0.54 pihole00.local.theama.co \
        "$node_b_remote_transcript"; then
    set +e
    runner_conclusion=$(
        classify_complete_evidence \
            "$node_a_remote_transcript" "$node_b_remote_transcript"
    )
    runner_status=$?
    set -e
else
    runner_conclusion=evidence_failure
fi
readonly runner_conclusion runner_status

if [[ -f "$node_a_remote_transcript" ]]; then
    printf 'action_17m_b_node_a_transcript_begin=true\n'
    cat "$node_a_remote_transcript"
    printf 'action_17m_b_node_a_transcript_end=true\n'
fi
if [[ -f "$node_b_remote_transcript" ]]; then
    printf 'action_17m_b_node_b_transcript_begin=true\n'
    cat "$node_b_remote_transcript"
    printf 'action_17m_b_node_b_transcript_end=true\n'
fi
printf 'action_17m_b_runner_conclusion=%s\n' "$runner_conclusion"
printf 'action_17m_b_workstation_cleanup=true\n'
exit "$runner_status"
