#!/usr/bin/env bash

set -u -o pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly expected_hostname=j1-svpihole0
readonly live_primary=/etc/unbound/unbound.conf.d/pihole.conf
readonly live_local_zone=/etc/unbound/unbound.conf.d/pihole-local-zone.conf
readonly pihole_cli=/usr/local/bin/pihole
readonly setup_vars=/etc/pihole/setupVars.conf
readonly dnsmasq_dir=/etc/dnsmasq.d
readonly expected_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly expected_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly peer_fqdn=pihole00.local.theama.co
readonly peer_ipv6=fd36:5aa8:6971:1::54
readonly expected_assertion_count=62

assertion_count=0
failed_assertion_count=0
first_failure=none
declare -A emitted_assertion_labels=()

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

record_assertion() {
    local assertion_label=$1
    local assertion_status=$2
    local assertion_observed=${3:-unavailable}

    if [[ ! "$assertion_label" =~ ^[a-z0-9_]+$ ]] ||
        [[ -n "${emitted_assertion_labels[$assertion_label]+present}" ]]; then
        printf 'action_17n_b_assertion_contract_failure=true\n' >&2
        exit 97
    fi
    emitted_assertion_labels[$assertion_label]=1
    ((assertion_count += 1))
    printf 'action_17n_b_assertion_%s=%s\n' \
        "$assertion_label" "$assertion_status"
    if [[ "$assertion_status" != true ]]; then
        ((failed_assertion_count += 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$assertion_label
        fi
        printf 'action_17n_b_observed_%s=%s\n' \
            "$assertion_label" "$assertion_observed"
    fi
}

assert_equal() {
    local equality_label=$1
    local equality_observed=$2
    local equality_expected=$3

    if [[ "$equality_observed" == "$equality_expected" ]]; then
        record_assertion "$equality_label" true
    else
        record_assertion "$equality_label" false "$equality_observed"
    fi
}

assert_regular_file() {
    local regular_label=$1
    local regular_path=$2

    if [[ -f "$regular_path" ]]; then
        record_assertion "${regular_label}_regular" true
    else
        record_assertion "${regular_label}_regular" false \
            "$(stat -c %F "$regular_path" 2>/dev/null || printf absent)"
    fi
    if [[ ! -L "$regular_path" ]]; then
        record_assertion "${regular_label}_not_symlink" true
    else
        record_assertion "${regular_label}_not_symlink" false symlink
    fi
}

safe_count() {
    local count_value=$1

    if [[ "$count_value" =~ ^[0-9]+$ ]]; then
        printf '%s' "$count_value"
    else
        printf invalid
    fi
}

record_dns_query() {
    local query_label=$1
    local query_server=$2
    local query_port=$3
    local query_name=$4
    local query_type=$5
    local query_status=0
    local query_output query_rcode query_answer query_ttl

    query_output=$(
        timeout 5 dig +time=2 +tries=1 +noall +comments +answer \
            "@$query_server" -p "$query_port" "$query_name" "$query_type"
    ) || query_status=$?
    assert_equal "${query_label}_command_status" "$query_status" 0

    query_rcode=$(
        sed -n 's/.*status: \([A-Z][A-Z]*\),.*/\1/p' <<<"$query_output" |
            head -n 1
    )
    query_rcode=${query_rcode:-missing}
    if [[ "$query_rcode" =~ ^[A-Z]+$ ]]; then
        record_assertion "${query_label}_rcode_safe" true
    else
        record_assertion "${query_label}_rcode_safe" false "$query_rcode"
    fi

    query_answer=$(
        awk '!/^;/ && NF >= 5 { print $NF }' <<<"$query_output" |
            sed 's/[.]$//' |
            LC_ALL=C sort -u |
            awk 'BEGIN { separator = "" }
                NF { printf "%s%s", separator, $0; separator = "," }
                END { print "" }'
    )
    query_answer=${query_answer:-none}
    if [[ "$query_answer" =~ ^[0-9A-Za-z:._,-]+$ ]]; then
        record_assertion "${query_label}_answer_safe" true
    else
        record_assertion "${query_label}_answer_safe" false unsafe
        query_answer=unsafe
    fi

    query_ttl=$(
        awk '!/^;/ && NF >= 5 { print $2; exit }' <<<"$query_output"
    )
    query_ttl=${query_ttl:-none}
    if [[ "$query_ttl" == none || "$query_ttl" =~ ^[0-9]+$ ]]; then
        record_assertion "${query_label}_ttl_safe" true
    else
        record_assertion "${query_label}_ttl_safe" false "$query_ttl"
        query_ttl=unsafe
    fi

    printf 'action_17n_b_value_%s_rcode=%s\n' "$query_label" "$query_rcode"
    printf 'action_17n_b_value_%s_answer=%s\n' "$query_label" "$query_answer"
    printf 'action_17n_b_value_%s_ttl=%s\n' "$query_label" "$query_ttl"
}

state_snapshot() {
    printf '%s\n' \
        "primary=$(file_hash "$live_primary" 2>/dev/null)" \
        "local_zone=$(file_hash "$live_local_zone" 2>/dev/null)" \
        "pihole_cli=$(file_hash "$pihole_cli" 2>/dev/null)" \
        "setup_vars=$(file_hash "$setup_vars" 2>/dev/null)" \
        "unbound=$(systemctl is-active unbound.service 2>/dev/null)" \
        "unbound_pid=$(systemctl show unbound.service -p MainPID --value 2>/dev/null)" \
        "unbound_restarts=$(systemctl show unbound.service -p NRestarts --value 2>/dev/null)" \
        "ftl=$(systemctl is-active pihole-FTL.service 2>/dev/null)" \
        "ftl_pid=$(systemctl show pihole-FTL.service -p MainPID --value 2>/dev/null)" \
        "ftl_restarts=$(systemctl show pihole-FTL.service -p NRestarts --value 2>/dev/null)"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$expected_assertion_count" -eq 62 ]]
    [[ "$peer_fqdn" == pihole00.local.theama.co ]]
    [[ "$peer_ipv6" == fd36:5aa8:6971:1::54 ]]
    printf 'action_17n_b_inspector_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

printf 'action_17n_b_remote_reached=true\n'
for required_command in \
    awk dig find grep head hostname id pihole sed sha256sum sort stat \
    systemctl timeout wc; do
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
assert_regular_file live_primary "$live_primary"
assert_equal live_primary_hash \
    "$(file_hash "$live_primary" 2>/dev/null)" "$expected_primary_sha256"
assert_regular_file live_local_zone "$live_local_zone"
assert_equal live_local_zone_hash \
    "$(file_hash "$live_local_zone" 2>/dev/null)" \
    "$expected_local_zone_sha256"
assert_regular_file pihole_cli "$pihole_cli"
assert_equal pihole_cli_metadata \
    "$(stat -c '%U:%G:%a' "$pihole_cli" 2>/dev/null)" root:root:755
assert_regular_file setup_vars "$setup_vars"
assert_equal unbound_active \
    "$(systemctl is-active unbound.service 2>/dev/null)" active
assert_equal pihole_ftl_active \
    "$(systemctl is-active pihole-FTL.service 2>/dev/null)" active

before_snapshot=$(state_snapshot)
readonly before_snapshot
before_state_sha256=$(
    printf '%s' "$before_snapshot" | sha256sum | awk '{ print $1 }'
)
readonly before_state_sha256

pihole_version_status=0
pihole_version_output=$(pihole -v 2>&1) || pihole_version_status=$?
readonly pihole_version_status pihole_version_output
assert_equal pihole_version_command_status "$pihole_version_status" 0
if grep -Eq 'Pi-hole version is v5([.]|$)' <<<"$pihole_version_output"; then
    record_assertion pihole_core_major_is_v5 true
else
    record_assertion pihole_core_major_is_v5 false \
        "$(printf '%s' "$pihole_version_output" | sha256sum | awk '{ print $1 }')"
fi
if grep -Eq 'FTL version is v5([.]|$)' <<<"$pihole_version_output"; then
    record_assertion pihole_ftl_major_is_v5 true
else
    record_assertion pihole_ftl_major_is_v5 false \
        "$(printf '%s' "$pihole_version_output" | sha256sum | awk '{ print $1 }')"
fi
printf 'action_17n_b_value_pihole_version_output_sha256=%s\n' \
    "$(printf '%s' "$pihole_version_output" | sha256sum | awk '{ print $1 }')"

restartdns_token_count=$(
    grep -Ec '(^|[^[:alnum:]_])restartdns([^[:alnum:]_]|$)' "$pihole_cli" ||
        true
)
readonly restartdns_token_count
if ((restartdns_token_count > 0)); then
    record_assertion pihole_restartdns_interface_present true
else
    record_assertion pihole_restartdns_interface_present false 0
fi
printf 'action_17n_b_value_pihole_restartdns_token_count=%s\n' \
    "$(safe_count "$restartdns_token_count")"

dnsmasq_local_v4_count=$(
    find "$dnsmasq_dir" -maxdepth 1 -type f -name '*.conf' -exec \
        grep -Eh '^[[:space:]]*server=127[.]0[.]0[.]1#5335[[:space:]]*$' \
        {} + 2>/dev/null |
        wc -l
)
readonly dnsmasq_local_v4_count
if ((dnsmasq_local_v4_count > 0)); then
    record_assertion dnsmasq_local_unbound_ipv4_upstream_present true
else
    record_assertion dnsmasq_local_unbound_ipv4_upstream_present false 0
fi
printf 'action_17n_b_value_dnsmasq_local_unbound_ipv4_count=%s\n' \
    "$(safe_count "$dnsmasq_local_v4_count")"

setup_vars_local_v4_count=$(
    grep -Ec '^PIHOLE_DNS_[0-9]+=127[.]0[.]0[.]1#5335$' "$setup_vars" ||
        true
)
readonly setup_vars_local_v4_count
if ((setup_vars_local_v4_count > 0)); then
    record_assertion setup_vars_local_unbound_ipv4_upstream_present true
else
    record_assertion setup_vars_local_unbound_ipv4_upstream_present false 0
fi
printf 'action_17n_b_value_setup_vars_local_unbound_ipv4_count=%s\n' \
    "$(safe_count "$setup_vars_local_v4_count")"

record_dns_query direct_unbound_peer_aaaa \
    127.0.0.1 5335 "$peer_fqdn" AAAA
record_dns_query direct_unbound_peer_ptr6 \
    127.0.0.1 5335 \
    4.5.0.0.0.0.0.0.0.0.0.0.0.0.0.0.1.0.0.0.1.7.9.6.8.a.a.5.6.3.d.f.ip6.arpa PTR
record_dns_query local_pihole_peer_aaaa_first \
    127.0.0.1 53 "$peer_fqdn" AAAA
record_dns_query local_pihole_peer_ptr6_first \
    127.0.0.1 53 \
    4.5.0.0.0.0.0.0.0.0.0.0.0.0.0.0.1.0.0.0.1.7.9.6.8.a.a.5.6.3.d.f.ip6.arpa PTR
record_dns_query local_pihole_peer_aaaa_second \
    127.0.0.1 53 "$peer_fqdn" AAAA
record_dns_query local_pihole_peer_ptr6_second \
    127.0.0.1 53 \
    4.5.0.0.0.0.0.0.0.0.0.0.0.0.0.0.1.0.0.0.1.7.9.6.8.a.a.5.6.3.d.f.ip6.arpa PTR

after_snapshot=$(state_snapshot)
readonly after_snapshot
after_state_sha256=$(
    printf '%s' "$after_snapshot" | sha256sum | awk '{ print $1 }'
)
readonly after_state_sha256
assert_equal persistent_state_unchanged "$after_snapshot" "$before_snapshot"

printf 'action_17n_b_assertion_count=%s\n' "$assertion_count"
printf 'action_17n_b_failed_assertion_count=%s\n' "$failed_assertion_count"
printf 'action_17n_b_first_failure=%s\n' "$first_failure"
printf 'action_17n_b_before_state_sha256=%s\n' "$before_state_sha256"
printf 'action_17n_b_after_state_sha256=%s\n' "$after_state_sha256"
printf 'remote_paths_created=false\n'
printf 'dns_queries_performed=true\n'
printf 'peer_connections=false\n'
printf 'synchronization_commands_executed=false\n'
printf 'dns_configuration_mutations=false\n'
printf 'nss_configuration_mutations=false\n'
printf 'pihole_cache_reset_performed=false\n'
printf 'service_mutations=false\n'
printf 'persistent_mutations=false\n'
if ((failed_assertion_count == 0)); then
    printf 'action_17n_b_conclusion=pihole_v5_response_path_observation_complete\n'
    printf 'action_17n_b_remote_complete=true\n'
    exit 0
fi
printf 'action_17n_b_conclusion=pihole_v5_response_path_semantic_mismatch\n'
printf 'action_17n_b_remote_complete=true\n'
exit 1
