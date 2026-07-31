#!/usr/bin/env bash

set -u -o pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly live_local_zone=/etc/unbound/unbound.conf.d/pihole-local-zone.conf
readonly dns_vip_ipv4=10.1.0.55
readonly dns_vip_ipv6=fd36:5aa8:6971:1::55
readonly node_a_fqdn=pihole0.local.theama.co
readonly node_a_ipv6=fd36:5aa8:6971:1::53
readonly node_a_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly node_b_local_zone_sha256=c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4
readonly expected_assertion_count=29

assertion_count=0
failed_assertion_count=0
first_failure=none

record_assertion() {
    local assertion_label=$1
    local assertion_status=$2
    local observed_value=${3:-unavailable}

    ((assertion_count += 1))
    printf 'action_17m_b_assertion_%s=%s\n' \
        "$assertion_label" "$assertion_status"
    if [[ "$assertion_status" != true ]]; then
        ((failed_assertion_count += 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$assertion_label
        fi
        printf 'action_17m_b_observed_%s=%s\n' \
            "$assertion_label" "$observed_value"
    fi
}

assert_equal() {
    local equality_label=$1
    local observed_value=$2
    local expected_value=$3

    if [[ "$observed_value" == "$expected_value" ]]; then
        record_assertion "$equality_label" true
    else
        record_assertion "$equality_label" false "$observed_value"
    fi
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

normalized_answer() {
    local answer_server=$1
    local answer_port=$2
    local answer_name=$3
    local answer_type=$4
    local answer_status=0
    local answer_value

    answer_value=$(
        timeout 5 dig +time=2 +tries=1 +short \
            "@$answer_server" -p "$answer_port" "$answer_name" "$answer_type" |
            sed 's/[.]$//' |
            LC_ALL=C sort -u |
            awk 'BEGIN { separator = "" }
                { printf "%s%s", separator, $0; separator = "," }
                END { print "" }'
    ) || answer_status=$?
    printf '%s|%s\n' "$answer_status" "${answer_value:-none}"
}

normalized_ptr_answer() {
    local answer_server=$1
    local answer_port=$2
    local answer_address=$3
    local answer_status=0
    local answer_value

    answer_value=$(
        timeout 5 dig +time=2 +tries=1 +short \
            "@$answer_server" -p "$answer_port" -x "$answer_address" |
            sed 's/[.]$//' |
            LC_ALL=C sort -u |
            awk 'BEGIN { separator = "" }
                { printf "%s%s", separator, $0; separator = "," }
                END { print "" }'
    ) || answer_status=$?
    printf '%s|%s\n' "$answer_status" "${answer_value:-none}"
}

record_query() {
    local query_label=$1
    local query_result=$2
    local query_status=${query_result%%|*}
    local query_answer=${query_result#*|}

    assert_equal "${query_label}_status" "$query_status" 0
    printf 'action_17m_b_value_%s_answer=%s\n' \
        "$query_label" "$query_answer"
}

vip_owned() {
    local address_family=$1
    local expected_cidr=$2

    if ip -o "$address_family" address show |
        awk -v cidr="$expected_cidr" '$4 == cidr { found = 1 } END { exit !found }'; then
        printf true
    else
        printf false
    fi
}

vip_interface() {
    local address_family=$1
    local expected_cidr=$2

    ip -o "$address_family" address show |
        awk -v cidr="$expected_cidr" '$4 == cidr { print $2; exit }'
}

state_snapshot() {
    printf '%s\n' \
        "local_zone=$(file_hash "$live_local_zone" 2>/dev/null)" \
        "unbound=$(systemctl is-active unbound.service 2>/dev/null)" \
        "unbound_pid=$(systemctl show unbound.service -p MainPID --value 2>/dev/null)" \
        "unbound_restarts=$(systemctl show unbound.service -p NRestarts --value 2>/dev/null)" \
        "ftl=$(systemctl is-active pihole-FTL.service 2>/dev/null)" \
        "ftl_pid=$(systemctl show pihole-FTL.service -p MainPID --value 2>/dev/null)" \
        "ftl_restarts=$(systemctl show pihole-FTL.service -p NRestarts --value 2>/dev/null)" \
        "ipv4_vip_owned=$(vip_owned -4 "$dns_vip_ipv4/22")" \
        "ipv6_vip_owned=$(vip_owned -6 "$dns_vip_ipv6/128")"
}

self_test() {
    [[ "$expected_assertion_count" -eq 29 ]]
    [[ "$node_a_local_zone_sha256" == 8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1 ]]
    [[ "$node_b_local_zone_sha256" == c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4 ]]
    printf 'action_17m_b_inspector_self_test_complete=true\n'
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        self_test
        exit 0
        ;;
    --role)
        [[ $# -eq 2 ]]
        node_role=$2
        ;;
    *)
        printf 'Usage: %s --self-test|--role node-a|node-b\n' "${0##*/}" >&2
        exit 2
        ;;
esac

case "$node_role" in
    node-a)
        expected_hostname=j1-svpihole0
        expected_local_zone_sha256=$node_a_local_zone_sha256
        ;;
    node-b)
        expected_hostname=j1-svpihole00
        expected_local_zone_sha256=$node_b_local_zone_sha256
        ;;
    *)
        printf 'Unsupported node role: %s\n' "$node_role" >&2
        exit 2
        ;;
esac
readonly node_role expected_hostname expected_local_zone_sha256

printf 'action_17m_b_remote_reached=true\n'
printf 'action_17m_b_node_role=%s\n' "$node_role"
for required_command in \
    awk dig grep hostname id ip sed sha256sum sort stat systemctl timeout; do
    command_label=${required_command//-/_}
    if command -v "$required_command" >/dev/null; then
        record_assertion "command_${command_label}_available" true
    else
        record_assertion "command_${command_label}_available" false missing
    fi
done

assert_equal uid_is_root "$(id -u)" 0
assert_equal working_directory_is_root "$PWD" /
assert_equal hostname_matches "$(hostname)" "$expected_hostname"
if [[ -f "$live_local_zone" && ! -L "$live_local_zone" ]]; then
    record_assertion live_local_zone_regular true
else
    record_assertion live_local_zone_regular false \
        "$(stat -c %F "$live_local_zone" 2>/dev/null || printf absent)"
fi
assert_equal live_local_zone_hash \
    "$(file_hash "$live_local_zone" 2>/dev/null)" \
    "$expected_local_zone_sha256"
assert_equal live_local_zone_metadata \
    "$(stat -c '%U:%G:%a' "$live_local_zone" 2>/dev/null)" root:root:644
assert_equal unbound_active "$(systemctl is-active unbound.service 2>/dev/null)" \
    active
assert_equal pihole_ftl_active \
    "$(systemctl is-active pihole-FTL.service 2>/dev/null)" active

ipv4_vip_owned=$(vip_owned -4 "$dns_vip_ipv4/22")
readonly ipv4_vip_owned
ipv6_vip_owned=$(vip_owned -6 "$dns_vip_ipv6/128")
readonly ipv6_vip_owned
ipv4_vip_interface=$(vip_interface -4 "$dns_vip_ipv4/22")
readonly ipv4_vip_interface
ipv6_vip_interface=$(vip_interface -6 "$dns_vip_ipv6/128")
readonly ipv6_vip_interface
printf 'action_17m_b_value_ipv4_vip_owned=%s\n' "$ipv4_vip_owned"
printf 'action_17m_b_value_ipv6_vip_owned=%s\n' "$ipv6_vip_owned"
printf 'action_17m_b_value_ipv4_vip_interface=%s\n' \
    "${ipv4_vip_interface:-none}"
printf 'action_17m_b_value_ipv6_vip_interface=%s\n' \
    "${ipv6_vip_interface:-none}"
printf 'action_17m_b_value_local_zone_sha256=%s\n' \
    "$(file_hash "$live_local_zone" 2>/dev/null)"

before_snapshot=$(state_snapshot)
readonly before_snapshot
before_state_sha256=$(
    printf '%s' "$before_snapshot" | sha256sum | awk '{ print $1 }'
)
readonly before_state_sha256

record_query direct_unbound_node_a_aaaa \
    "$(normalized_answer 127.0.0.1 5335 "$node_a_fqdn" AAAA)"
record_query direct_unbound_node_a_ptr6 \
    "$(normalized_ptr_answer 127.0.0.1 5335 "$node_a_ipv6")"
record_query local_pihole_node_a_aaaa \
    "$(normalized_answer 127.0.0.1 53 "$node_a_fqdn" AAAA)"
record_query local_pihole_node_a_ptr6 \
    "$(normalized_ptr_answer 127.0.0.1 53 "$node_a_ipv6")"
record_query dns_vip_ipv4_node_a_aaaa \
    "$(normalized_answer "$dns_vip_ipv4" 53 "$node_a_fqdn" AAAA)"
record_query dns_vip_ipv4_node_a_ptr6 \
    "$(normalized_ptr_answer "$dns_vip_ipv4" 53 "$node_a_ipv6")"
record_query dns_vip_ipv6_node_a_aaaa \
    "$(normalized_answer "$dns_vip_ipv6" 53 "$node_a_fqdn" AAAA)"
record_query dns_vip_ipv6_node_a_ptr6 \
    "$(normalized_ptr_answer "$dns_vip_ipv6" 53 "$node_a_ipv6")"

after_snapshot=$(state_snapshot)
readonly after_snapshot
after_state_sha256=$(
    printf '%s' "$after_snapshot" | sha256sum | awk '{ print $1 }'
)
readonly after_state_sha256
assert_equal state_unchanged "$after_snapshot" "$before_snapshot"

printf 'action_17m_b_assertion_count=%s\n' "$assertion_count"
printf 'action_17m_b_failed_assertion_count=%s\n' "$failed_assertion_count"
printf 'action_17m_b_first_failure=%s\n' "$first_failure"
printf 'action_17m_b_before_state_sha256=%s\n' "$before_state_sha256"
printf 'action_17m_b_after_state_sha256=%s\n' "$after_state_sha256"
printf 'remote_paths_created=false\n'
printf 'dns_queries_performed=true\n'
printf 'peer_connections=false\n'
printf 'synchronization_commands_executed=false\n'
printf 'dns_configuration_mutations=false\n'
printf 'nss_configuration_mutations=false\n'
printf 'service_mutations=false\n'
printf 'persistent_mutations=false\n'

if [[ "$assertion_count" -ne "$expected_assertion_count" ]]; then
    printf 'action_17m_b_conclusion=node_assertion_contract_mismatch\n'
    printf 'action_17m_b_remote_complete=true\n'
    exit 97
fi
if [[ "$failed_assertion_count" -eq 0 ]]; then
    printf 'action_17m_b_conclusion=node_observation_complete\n'
    printf 'action_17m_b_remote_complete=true\n'
    exit 0
fi
printf 'action_17m_b_conclusion=node_precondition_mismatch\n'
printf 'action_17m_b_remote_complete=true\n'
exit 1
