#!/usr/bin/env bash

set -u -o pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly expected_hostname=j1-svpihole00
readonly live_root=/etc/unbound/unbound.conf
readonly live_primary=/etc/unbound/unbound.conf.d/pihole.conf
readonly live_local_zone=/etc/unbound/unbound.conf.d/pihole-local-zone.conf
readonly live_hosts=/etc/hosts
readonly backup_dir=/var/backups/caddy-ha/action17m-node-b-dns-nss
readonly backup_local_zone="$backup_dir/pihole-local-zone.conf.before"
readonly backup_hosts="$backup_dir/hosts.before"
readonly backup_manifest="$backup_dir/manifest"
readonly local_zone_transaction=/etc/unbound/unbound.conf.d/.pihole-local-zone.conf.action17m.new
readonly hosts_transaction=/etc/.hosts.action17m.new
readonly expected_root_sha256=8808b474175ff8eeebecbf407f9091fd73f65c4a43a6ee212e8ae2d9f80778f8
readonly expected_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly expected_previous_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly expected_live_local_zone_sha256=c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4
readonly peer_ipv4=10.1.0.53
readonly peer_ipv6=fd36:5aa8:6971:1::53
readonly peer_fqdn=pihole0.local.theama.co
readonly marker_begin='# BEGIN CADDY HA SYNC PEER'
readonly marker_end='# END CADDY HA SYNC PEER'
readonly expected_assertion_count=98

assertion_count=0
failed_assertion_count=0
first_failure=none

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

record_assertion() {
    local assertion_label=$1
    local assertion_status=$2
    local observed_value=${3:-unavailable}

    ((assertion_count += 1))
    printf 'action_17m_a_assertion_%s=%s\n' \
        "$assertion_label" "$assertion_status"
    if [[ "$assertion_status" != true ]]; then
        ((failed_assertion_count += 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$assertion_label
        fi
        printf 'action_17m_a_observed_%s=%s\n' \
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

assert_regular_file() {
    local regular_label=$1
    local regular_path=$2

    if [[ -f "$regular_path" && ! -L "$regular_path" ]]; then
        record_assertion "$regular_label" true
    else
        record_assertion "$regular_label" false \
            "$(stat -c %F "$regular_path" 2>/dev/null || printf absent)"
    fi
}

assert_absent() {
    local absent_label=$1
    local absent_path=$2

    if [[ ! -e "$absent_path" && ! -L "$absent_path" ]]; then
        record_assertion "$absent_label" true
    else
        record_assertion "$absent_label" false \
            "$(stat -c %F "$absent_path" 2>/dev/null || printf present)"
    fi
}

manifest_value() {
    local manifest_key=$1

    awk -F= -v key="$manifest_key" '$1 == key { print substr($0, index($0, "=") + 1) }' \
        "$backup_manifest" 2>/dev/null
}

query_and_assert() {
    local query_label=$1
    local query_server=$2
    local query_port=$3
    local query_name=$4
    local query_type=$5
    local expected_answer=$6
    local query_status=0
    local query_answer

    query_answer=$(
        timeout 5 dig +time=2 +tries=1 +short \
            "@$query_server" -p "$query_port" "$query_name" "$query_type" |
            sed 's/[.]$//' |
            LC_ALL=C sort -u
    ) || query_status=$?
    assert_equal "${query_label}_status" "$query_status" 0
    assert_equal "${query_label}_answer" "$query_answer" "$expected_answer"
}

reverse_query_and_assert() {
    local reverse_label=$1
    local reverse_server=$2
    local reverse_port=$3
    local reverse_address=$4
    local expected_answer=$5
    local reverse_status=0
    local reverse_answer

    reverse_answer=$(
        timeout 5 dig +time=2 +tries=1 +short \
            "@$reverse_server" -p "$reverse_port" -x "$reverse_address" |
            sed 's/[.]$//' |
            LC_ALL=C sort -u
    ) || reverse_status=$?
    assert_equal "${reverse_label}_status" "$reverse_status" 0
    assert_equal "${reverse_label}_answer" "$reverse_answer" "$expected_answer"
}

state_snapshot() {
    printf '%s\n' \
        "root=$(file_hash "$live_root" 2>/dev/null)" \
        "primary=$(file_hash "$live_primary" 2>/dev/null)" \
        "local_zone=$(file_hash "$live_local_zone" 2>/dev/null)" \
        "hosts=$(file_hash "$live_hosts" 2>/dev/null)" \
        "backup_local_zone=$(file_hash "$backup_local_zone" 2>/dev/null)" \
        "backup_hosts=$(file_hash "$backup_hosts" 2>/dev/null)" \
        "backup_manifest=$(file_hash "$backup_manifest" 2>/dev/null)" \
        "unbound=$(systemctl is-active unbound.service 2>/dev/null)" \
        "unbound_pid=$(systemctl show unbound.service -p MainPID --value 2>/dev/null)" \
        "unbound_restarts=$(systemctl show unbound.service -p NRestarts --value 2>/dev/null)" \
        "ftl=$(systemctl is-active pihole-FTL.service 2>/dev/null)" \
        "ftl_pid=$(systemctl show pihole-FTL.service -p MainPID --value 2>/dev/null)" \
        "ftl_restarts=$(systemctl show pihole-FTL.service -p NRestarts --value 2>/dev/null)" \
        "local_zone_transaction=$(stat -c %F "$local_zone_transaction" 2>/dev/null || printf absent)" \
        "hosts_transaction=$(stat -c %F "$hosts_transaction" 2>/dev/null || printf absent)"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$expected_assertion_count" -eq 98 ]]
    [[ "$expected_live_local_zone_sha256" == c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4 ]]
    [[ "$peer_fqdn" == pihole0.local.theama.co ]]
    printf 'action_17m_a_inspector_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

printf 'action_17m_a_remote_reached=true\n'
for required_command in \
    awk cat cut dig find getent grep hostname id readlink runuser sed \
    sha256sum sort stat systemctl timeout unbound-checkconf wc; do
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
assert_regular_file live_root_regular "$live_root"
assert_equal live_root_hash "$(file_hash "$live_root" 2>/dev/null)" \
    "$expected_root_sha256"
assert_regular_file live_primary_regular "$live_primary"
assert_equal live_primary_hash "$(file_hash "$live_primary" 2>/dev/null)" \
    "$expected_primary_sha256"
assert_equal live_primary_metadata \
    "$(stat -c '%U:%G:%a' "$live_primary" 2>/dev/null)" root:root:644
assert_regular_file live_local_zone_regular "$live_local_zone"
assert_equal live_local_zone_hash \
    "$(file_hash "$live_local_zone" 2>/dev/null)" \
    "$expected_live_local_zone_sha256"
assert_equal live_local_zone_metadata \
    "$(stat -c '%U:%G:%a' "$live_local_zone" 2>/dev/null)" root:root:644
assert_regular_file live_hosts_regular "$live_hosts"
live_hosts_metadata=$(stat -c '%U:%G:%a' "$live_hosts" 2>/dev/null)
readonly live_hosts_metadata
assert_equal live_hosts_metadata "$live_hosts_metadata" root:root:644

if [[ -d "$backup_dir" && ! -L "$backup_dir" ]]; then
    record_assertion backup_directory true
else
    record_assertion backup_directory false absent
fi
assert_equal backup_directory_metadata \
    "$(stat -c '%U:%G:%a' "$backup_dir" 2>/dev/null)" root:root:700
assert_equal backup_entry_count \
    "$(find "$backup_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null |
        wc -l)" 3
assert_equal backup_entries \
    "$(find "$backup_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null |
        LC_ALL=C sort)" \
    "$(printf '%s\n' hosts.before manifest pihole-local-zone.conf.before)"
assert_regular_file backup_local_zone_regular "$backup_local_zone"
assert_equal backup_local_zone_hash \
    "$(file_hash "$backup_local_zone" 2>/dev/null)" \
    "$expected_previous_local_zone_sha256"
assert_equal backup_local_zone_metadata \
    "$(stat -c '%U:%G:%a' "$backup_local_zone" 2>/dev/null)" root:root:600
assert_regular_file backup_hosts_regular "$backup_hosts"
assert_equal backup_hosts_metadata \
    "$(stat -c '%U:%G:%a' "$backup_hosts" 2>/dev/null)" "$live_hosts_metadata"
assert_regular_file backup_manifest_regular "$backup_manifest"
assert_equal backup_manifest_metadata \
    "$(stat -c '%U:%G:%a' "$backup_manifest" 2>/dev/null)" root:root:600
assert_equal backup_manifest_action "$(manifest_value action)" 17m
assert_equal backup_manifest_node "$(manifest_value node)" "$expected_hostname"
assert_equal backup_manifest_before_hash \
    "$(manifest_value local_zone_before_sha256)" \
    "$expected_previous_local_zone_sha256"
assert_equal backup_manifest_after_hash \
    "$(manifest_value local_zone_after_sha256)" \
    "$expected_live_local_zone_sha256"
assert_equal backup_manifest_hosts_hash \
    "$(manifest_value hosts_before_sha256)" \
    "$(file_hash "$backup_hosts" 2>/dev/null)"

assert_absent local_zone_transaction_absent "$local_zone_transaction"
assert_absent hosts_transaction_absent "$hosts_transaction"
assert_equal hosts_marker_begin_exact_once \
    "$(grep -Fxc "$marker_begin" "$live_hosts" || true)" 1
assert_equal hosts_marker_end_exact_once \
    "$(grep -Fxc "$marker_end" "$live_hosts" || true)" 1
assert_equal hosts_peer_ipv4_exact_once \
    "$(grep -Fxc "$peer_ipv4 $peer_fqdn" "$live_hosts" || true)" 1
assert_equal hosts_peer_ipv6_exact_once \
    "$(grep -Fxc "$peer_ipv6 $peer_fqdn" "$live_hosts" || true)" 1
managed_block=$(
    awk -v begin="$marker_begin" -v end="$marker_end" '
        $0 == begin { capture = 1 }
        capture { print }
        $0 == end && capture { exit }
    ' "$live_hosts"
)
readonly managed_block
assert_equal hosts_managed_block_exact "$managed_block" \
    "$(printf '%s\n' \
        "$marker_begin" \
        "$peer_ipv4 $peer_fqdn" \
        "$peer_ipv6 $peer_fqdn" \
        "$marker_end")"
assert_equal hosts_peer_name_count \
    "$(awk -v name="$peer_fqdn" '
        /^[[:space:]]*#/ { next }
        {
            for (field = 2; field <= NF; field++) {
                if ($field == name) {
                    count++
                }
            }
        }
        END { print count + 0 }
    ' "$live_hosts")" 2
assert_equal hosts_vip_mapping_absent \
    "$(grep -Ec '^(10[.]1[.]0[.](55|56)|fd36:5aa8:6971:1::(55|56))[[:space:]]' \
        "$live_hosts" || true)" 0
assert_equal local_zone_homeassistant_a_absent \
    "$(grep -Fc 'homeassistant.local.theama.co. IN A ' \
        "$live_local_zone" || true)" 0
assert_equal local_zone_homeassistant_ptr_absent \
    "$(grep -Fc 'homeassistant.local.theama.co."' \
        "$live_local_zone" || true)" 0
assert_equal local_zone_caddy_records_absent \
    "$(grep -Ec 'proxy[.]local[.]theama[.]co|pihole-admin[.]local[.]theama[.]co|::56|10[.]1[.]0[.]56' \
        "$live_local_zone" || true)" 0

readonly -a expected_record_labels=(
    pihole_vip_aaaa
    node_a_aaaa
    node_b_aaaa
    pihole_vip_ptr6
    node_a_ptr6
    node_b_ptr6
)
readonly -a expected_record_texts=(
    '    local-data: "pihole.local.theama.co. IN AAAA fd36:5aa8:6971:1::55"'
    '    local-data: "pihole0.local.theama.co. IN AAAA fd36:5aa8:6971:1::53"'
    '    local-data: "pihole00.local.theama.co. IN AAAA fd36:5aa8:6971:1::54"'
    '    local-data-ptr: "fd36:5aa8:6971:1::55 pihole.local.theama.co."'
    '    local-data-ptr: "fd36:5aa8:6971:1::53 pihole0.local.theama.co."'
    '    local-data-ptr: "fd36:5aa8:6971:1::54 pihole00.local.theama.co."'
)
for record_index in "${!expected_record_labels[@]}"; do
    assert_equal \
        "local_zone_${expected_record_labels[$record_index]}_exact_once" \
        "$(grep -Fxc "${expected_record_texts[$record_index]}" \
            "$live_local_zone" || true)" 1
done

before_snapshot=$(state_snapshot)
readonly before_snapshot
before_snapshot_sha256=$(
    printf '%s' "$before_snapshot" | sha256sum | awk '{ print $1 }'
)
readonly before_snapshot_sha256

parser_status=0
unbound-checkconf "$live_root" >/dev/null 2>&1 || parser_status=$?
assert_equal live_parser_status "$parser_status" 0
assert_equal unbound_active "$(systemctl is-active unbound.service 2>/dev/null)" \
    active
assert_equal pihole_ftl_active \
    "$(systemctl is-active pihole-FTL.service 2>/dev/null)" active

query_and_assert direct_pihole_vip_aaaa \
    127.0.0.1 5335 pihole.local.theama.co AAAA fd36:5aa8:6971:1::55
query_and_assert direct_node_a_aaaa \
    127.0.0.1 5335 pihole0.local.theama.co AAAA "$peer_ipv6"
query_and_assert direct_node_b_aaaa \
    127.0.0.1 5335 pihole00.local.theama.co AAAA fd36:5aa8:6971:1::54
reverse_query_and_assert direct_pihole_vip_ptr6 \
    127.0.0.1 5335 fd36:5aa8:6971:1::55 pihole.local.theama.co
reverse_query_and_assert direct_node_a_ptr6 \
    127.0.0.1 5335 "$peer_ipv6" "$peer_fqdn"
reverse_query_and_assert direct_node_b_ptr6 \
    127.0.0.1 5335 fd36:5aa8:6971:1::54 pihole00.local.theama.co
query_and_assert pihole_local_node_a_aaaa \
    127.0.0.1 53 "$peer_fqdn" AAAA "$peer_ipv6"
reverse_query_and_assert pihole_local_node_a_ptr6 \
    127.0.0.1 53 "$peer_ipv6" "$peer_fqdn"
query_and_assert dns_vip_ipv4_node_a_aaaa \
    10.1.0.55 53 "$peer_fqdn" AAAA "$peer_ipv6"
reverse_query_and_assert dns_vip_ipv4_node_a_ptr6 \
    10.1.0.55 53 "$peer_ipv6" "$peer_fqdn"
query_and_assert dns_vip_ipv6_node_a_aaaa \
    fd36:5aa8:6971:1::55 53 "$peer_fqdn" AAAA "$peer_ipv6"
reverse_query_and_assert dns_vip_ipv6_node_a_ptr6 \
    fd36:5aa8:6971:1::55 53 "$peer_ipv6" "$peer_fqdn"

assert_equal root_peer_ipv4 \
    "$(getent ahostsv4 "$peer_fqdn" | awk 'NR == 1 { print $1 }')" "$peer_ipv4"
assert_equal root_peer_ipv6 \
    "$(getent ahostsv6 "$peer_fqdn" | awk 'NR == 1 { print $1 }')" "$peer_ipv6"
assert_equal caddy_sync_peer_ipv4 \
    "$(runuser -u caddy-sync -- getent ahostsv4 "$peer_fqdn" |
        awk 'NR == 1 { print $1 }')" "$peer_ipv4"
assert_equal caddy_sync_peer_ipv6 \
    "$(runuser -u caddy-sync -- getent ahostsv6 "$peer_fqdn" |
        awk 'NR == 1 { print $1 }')" "$peer_ipv6"

after_snapshot=$(state_snapshot)
readonly after_snapshot
after_snapshot_sha256=$(
    printf '%s' "$after_snapshot" | sha256sum | awk '{ print $1 }'
)
readonly after_snapshot_sha256
assert_equal state_unchanged "$after_snapshot" "$before_snapshot"

printf 'action_17m_a_assertion_count=%s\n' "$assertion_count"
printf 'action_17m_a_failed_assertion_count=%s\n' "$failed_assertion_count"
printf 'action_17m_a_first_failure=%s\n' "$first_failure"
printf 'action_17m_a_before_state_sha256=%s\n' "$before_snapshot_sha256"
printf 'action_17m_a_after_state_sha256=%s\n' "$after_snapshot_sha256"
printf 'remote_paths_created=false\n'
printf 'dns_queries_performed=true\n'
printf 'peer_connections=false\n'
printf 'synchronization_commands_executed=false\n'
printf 'dns_configuration_mutations=false\n'
printf 'nss_configuration_mutations=false\n'
printf 'service_mutations=false\n'
printf 'persistent_mutations=false\n'

if [[ "$assertion_count" -ne "$expected_assertion_count" ]]; then
    printf 'action_17m_a_conclusion=inspector_assertion_contract_mismatch\n'
    printf 'action_17m_a_remote_complete=true\n'
    exit 97
fi
if [[ "$failed_assertion_count" -eq 0 ]]; then
    printf 'action_17m_a_conclusion=post_correction_state_verified\n'
    printf 'action_17m_a_remote_complete=true\n'
    exit 0
fi
printf 'action_17m_a_conclusion=post_correction_state_mismatch\n'
printf 'action_17m_a_remote_complete=true\n'
exit 1
