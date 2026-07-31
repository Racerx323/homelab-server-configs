#!/usr/bin/env bash

set -u -o pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly live_root=/etc/unbound/unbound.conf
readonly live_primary=/etc/unbound/unbound.conf.d/pihole.conf
readonly live_local_zone=/etc/unbound/unbound.conf.d/pihole-local-zone.conf
readonly legacy_local_zone=/etc/unbound/unbound.conf.d/pihole0-local-zone.conf
readonly expected_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly expected_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly ssh_dir=/var/lib/caddy-sync/.ssh
readonly private_key_path="$ssh_dir/id_ed25519"
readonly public_key_path="$private_key_path.pub"
readonly known_hosts_path="$ssh_dir/known_hosts"
readonly authorized_keys_path="$ssh_dir/authorized_keys"
readonly receiver_path=/usr/local/libexec/caddy-sync-rsync-receiver
readonly validator_path=/usr/local/libexec/validate-sync-ssh.sh
readonly lsyncd_config_path=/etc/lsyncd/caddy.lua
readonly lsyncd_unit_path=/etc/systemd/system/caddy-lsyncd.service
readonly receiver_sha256=65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134
readonly validator_sha256=85df8a934c8dd9561a6f567f42549ebc01ee2605ca630150265004b9ec108072
readonly lsyncd_unit_sha256=93cbc36cea03b8b7e1605c44667463592cf64e0293ded9f816d1e34760a69ac8
readonly node_a_public_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG3MEgLhf8tsImyjkCZpQU4H7X8Xdac+iOUCxRTMM0tA caddy-ha-sync'
readonly node_b_public_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBwBAlvUOqcazWjzfUOnwk1AHath8Xn8eoUDXBFQIG7e caddy-ha-sync'
readonly dns_vip_ipv4=10.1.0.55
readonly dns_vip_ipv6=fd36:5aa8:6971:1::55
readonly -a required_commands=(
    awk cat cut dig dpkg-query find getent grep hostname id ip passwd readlink
    runuser sed sha256sum sort ssh-keygen stat systemctl unbound-checkconf wc
)
readonly expected_command_assertion_count=22
readonly expected_non_command_assertion_count=89
readonly expected_assertion_count=111

assertion_count=0
failed_assertion_count=0
first_failure=none

file_hash() {
    sha256sum "$1" 2>/dev/null | awk '{ print $1 }'
}

record_assertion() {
    local assertion_label=$1
    local assertion_status=$2

    ((assertion_count += 1))
    printf 'action_17l_assertion_%s=%s\n' \
        "$assertion_label" "$assertion_status"
    if [[ "$assertion_status" != true ]]; then
        ((failed_assertion_count += 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$assertion_label
        fi
    fi
}

assert_equal() {
    local equality_label=$1
    local observed_value=$2
    local expected_value=$3

    if [[ "$observed_value" == "$expected_value" ]]; then
        record_assertion "$equality_label" true
    else
        record_assertion "$equality_label" false
    fi
}

assert_regular_file() {
    local regular_label=$1
    local regular_path=$2

    if [[ -f "$regular_path" && ! -L "$regular_path" ]]; then
        record_assertion "$regular_label" true
    else
        record_assertion "$regular_label" false
    fi
}

assert_absent() {
    local absent_label=$1
    local absent_path=$2

    if [[ ! -e "$absent_path" && ! -L "$absent_path" ]]; then
        record_assertion "$absent_label" true
    else
        record_assertion "$absent_label" false
    fi
}

assert_command() {
    local command_label=$1
    shift

    if "$@" >/dev/null 2>&1; then
        record_assertion "$command_label" true
    else
        record_assertion "$command_label" false
    fi
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
        dig +time=2 +tries=1 +short \
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
    local expected_reverse_answer=$5
    local reverse_status=0
    local reverse_answer

    reverse_answer=$(
        dig +time=2 +tries=1 +short \
            "@$reverse_server" -p "$reverse_port" -x "$reverse_address" |
            sed 's/[.]$//' |
            LC_ALL=C sort -u
    ) || reverse_status=$?
    assert_equal "${reverse_label}_status" "$reverse_status" 0
    assert_equal "${reverse_label}_answer" "$reverse_answer" \
        "$expected_reverse_answer"
}

assert_getent_address() {
    local resolver_label=$1
    local resolver_family=$2
    local resolver_name=$3
    local expected_address=$4
    local resolver_user=${5:-root}
    local resolver_status=0
    local resolver_answers

    if [[ "$resolver_user" == root ]]; then
        resolver_answers=$(
            getent "$resolver_family" "$resolver_name" |
                awk '{ print $1 }' |
                LC_ALL=C sort -u
        ) || resolver_status=$?
    else
        resolver_answers=$(
            runuser -u "$resolver_user" -- \
                getent "$resolver_family" "$resolver_name" |
                awk '{ print $1 }' |
                LC_ALL=C sort -u
        ) || resolver_status=$?
    fi
    assert_equal "${resolver_label}_status" "$resolver_status" 0
    if grep -Fxq "$expected_address" <<<"$resolver_answers"; then
        record_assertion "${resolver_label}_address" true
    else
        record_assertion "${resolver_label}_address" false
    fi
}

state_snapshot() {
    printf '%s\n' \
        "root=$(file_hash "$live_root")" \
        "primary=$(file_hash "$live_primary")" \
        "local_zone=$(file_hash "$live_local_zone")" \
        "unbound=$(systemctl is-active unbound.service 2>/dev/null)" \
        "unbound_pid=$(systemctl show unbound.service -p MainPID --value 2>/dev/null)" \
        "unbound_restarts=$(systemctl show unbound.service -p NRestarts --value 2>/dev/null)" \
        "ftl=$(systemctl is-active pihole-FTL.service 2>/dev/null)" \
        "ftl_pid=$(systemctl show pihole-FTL.service -p MainPID --value 2>/dev/null)" \
        "ftl_restarts=$(systemctl show pihole-FTL.service -p NRestarts --value 2>/dev/null)" \
        "caddy=$(systemctl is-active caddy.service 2>/dev/null)" \
        "caddy_lsyncd=$(systemctl is-active caddy-lsyncd.service 2>/dev/null)" \
        "outbound_files=$(find /var/lib/caddy-sync/outbound -type f 2>/dev/null | wc -l)" \
        "incoming_files=$(find /var/lib/caddy-sync/incoming -type f 2>/dev/null | wc -l)"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "${#required_commands[@]}" -eq "$expected_command_assertion_count" ]]
    [[ "$expected_non_command_assertion_count" -eq 89 ]]
    [[ "$expected_command_assertion_count" -eq 22 ]]
    [[ "$expected_assertion_count" -eq 111 ]]
    ((expected_assertion_count == \
    expected_command_assertion_count + expected_non_command_assertion_count))
    [[ "$live_primary" == /etc/unbound/unbound.conf.d/pihole.conf ]]
    [[ "$live_local_zone" == /etc/unbound/unbound.conf.d/pihole-local-zone.conf ]]
    printf 'action_17l_inspector_self_test_complete=true\n'
    exit 0
elif [[ $# -ne 2 || "$1" != --node ||
    ! "$2" =~ ^node-[ab]$ ]]; then
    printf 'Usage: %s --node node-a|node-b\n' "${0##*/}" >&2
    exit 2
fi

readonly node_role=$2
if [[ "$node_role" == node-a ]]; then
    readonly expected_hostname=j1-svpihole0
    readonly own_name=pihole0.local.theama.co
    readonly own_ipv4=10.1.0.53
    readonly own_ipv6=fd36:5aa8:6971:1::53
    readonly peer_name=pihole00.local.theama.co
    readonly peer_ipv4=10.1.0.54
    readonly peer_ipv6=fd36:5aa8:6971:1::54
    readonly peer_public_key="$node_b_public_key"
    readonly expected_current_target=/etc/caddy/releases/action16ar-retry-node-a-default-deny
else
    readonly expected_hostname=j1-svpihole00
    readonly own_name=pihole00.local.theama.co
    readonly own_ipv4=10.1.0.54
    readonly own_ipv6=fd36:5aa8:6971:1::54
    readonly peer_name=pihole0.local.theama.co
    readonly peer_ipv4=10.1.0.53
    readonly peer_ipv6=fd36:5aa8:6971:1::53
    readonly peer_public_key="$node_a_public_key"
    readonly expected_current_target=/etc/caddy/releases/action15-health-follow-redirects
fi
readonly expected_authorization="from=\"$peer_ipv4,$peer_ipv6\",restrict,command=\"/usr/local/libexec/caddy-sync-rsync-receiver\" $peer_public_key"

printf 'action_17l_remote_reached=true\n'
printf 'action_17l_node_role=%s\n' "$node_role"
before_state=$(state_snapshot | sha256sum | awk '{ print $1 }')
readonly before_state

for required_command in "${required_commands[@]}"; do
    command_label=${required_command//-/_}
    assert_command "command_${command_label}_available" \
        command -v "$required_command"
done

assert_equal uid_is_root "$(id -u)" 0
assert_equal working_directory_is_root "$PWD" /
assert_equal hostname_matches "$(hostname)" "$expected_hostname"
assert_regular_file live_primary_regular "$live_primary"
assert_equal live_primary_hash "$(file_hash "$live_primary")" \
    "$expected_primary_sha256"
assert_equal live_primary_metadata \
    "$(stat -c '%U:%G:%a' "$live_primary" 2>/dev/null)" root:root:644
assert_regular_file live_local_zone_regular "$live_local_zone"
assert_equal live_local_zone_hash "$(file_hash "$live_local_zone")" \
    "$expected_local_zone_sha256"
assert_equal live_local_zone_metadata \
    "$(stat -c '%U:%G:%a' "$live_local_zone" 2>/dev/null)" root:root:644
assert_absent legacy_local_zone_absent "$legacy_local_zone"
parser_status=0
unbound-checkconf "$live_root" >/dev/null 2>&1 || parser_status=$?
assert_equal unbound_parser_status "$parser_status" 0
assert_equal unbound_active \
    "$(systemctl is-active unbound.service 2>/dev/null)" active
assert_equal pihole_ftl_active \
    "$(systemctl is-active pihole-FTL.service 2>/dev/null)" active

assert_equal caddy_sync_home \
    "$(getent passwd caddy-sync 2>/dev/null | cut -d: -f6)" \
    /var/lib/caddy-sync
assert_equal caddy_sync_shell \
    "$(getent passwd caddy-sync 2>/dev/null | cut -d: -f7)" /bin/sh
assert_equal caddy_sync_password_state \
    "$(passwd --status caddy-sync 2>/dev/null | awk '{ print $2 }')" L
for sync_directory in \
    /var/lib/caddy-sync \
    /var/lib/caddy-sync/outbound \
    /var/lib/caddy-sync/incoming \
    /var/lib/caddy-sync/quarantine; do
    sync_label=${sync_directory##*/}
    [[ "$sync_directory" == /var/lib/caddy-sync ]] && sync_label=root
    assert_equal "sync_${sync_label}_directory_metadata" \
        "$(stat -c '%U:%G:%a' "$sync_directory" 2>/dev/null)" \
        caddy-sync:caddy-sync:750
done
assert_equal sync_ssh_directory_metadata \
    "$(stat -c '%U:%G:%a' "$ssh_dir" 2>/dev/null)" \
    caddy-sync:caddy-sync:700
assert_regular_file sync_private_key_regular "$private_key_path"
assert_equal sync_private_key_metadata \
    "$(stat -c '%U:%G:%a' "$private_key_path" 2>/dev/null)" \
    caddy-sync:caddy-sync:600
assert_regular_file sync_public_key_regular "$public_key_path"
assert_equal sync_public_key_metadata \
    "$(stat -c '%U:%G:%a' "$public_key_path" 2>/dev/null)" \
    caddy-sync:caddy-sync:644
assert_equal sync_key_pair_matches \
    "$(ssh-keygen -y -f "$private_key_path" 2>/dev/null |
        awk '{ print $1, $2 }')" \
    "$(awk '{ print $1, $2 }' "$public_key_path" 2>/dev/null)"
assert_regular_file sync_known_hosts_regular "$known_hosts_path"
assert_equal sync_known_hosts_metadata \
    "$(stat -c '%U:%G:%a' "$known_hosts_path" 2>/dev/null)" \
    caddy-sync:caddy-sync:600
assert_equal sync_known_hosts_line_count \
    "$(wc -l <"$known_hosts_path" 2>/dev/null)" 1
assert_equal sync_known_host_peer_match_count \
    "$(ssh-keygen -F "$peer_name" -f "$known_hosts_path" 2>/dev/null |
        grep -vc '^#' || true)" 1
assert_regular_file sync_receiver_regular "$receiver_path"
assert_equal sync_receiver_hash "$(file_hash "$receiver_path")" \
    "$receiver_sha256"
assert_command sync_receiver_no_delete_contract \
    grep -Fq \
    'exec /usr/bin/rrsync -wo -no-del /var/lib/caddy-sync/incoming' \
    "$receiver_path"
assert_regular_file sync_validator_regular "$validator_path"
assert_equal sync_validator_hash "$(file_hash "$validator_path")" \
    "$validator_sha256"
assert_regular_file caddy_lsyncd_unit_regular "$lsyncd_unit_path"
assert_equal caddy_lsyncd_unit_hash "$(file_hash "$lsyncd_unit_path")" \
    "$lsyncd_unit_sha256"
assert_absent lsyncd_configuration_absent "$lsyncd_config_path"
assert_equal lsyncd_active \
    "$(systemctl is-active lsyncd.service 2>/dev/null)" inactive
assert_equal lsyncd_enabled \
    "$(systemctl is-enabled lsyncd.service 2>/dev/null)" masked
assert_equal caddy_lsyncd_active \
    "$(systemctl is-active caddy-lsyncd.service 2>/dev/null)" inactive
assert_equal caddy_lsyncd_enabled \
    "$(systemctl is-enabled caddy-lsyncd.service 2>/dev/null)" disabled
assert_equal caddy_active \
    "$(systemctl is-active caddy.service 2>/dev/null)" active
assert_equal ssh_active \
    "$(systemctl is-active ssh.service 2>/dev/null)" active
assert_equal sync_outbound_regular_file_count \
    "$(find /var/lib/caddy-sync/outbound -type f 2>/dev/null | wc -l)" 0
assert_equal environment_role_count \
    "$(grep -Fxc "NODE_ROLE=$node_role" /etc/default/caddy-ha 2>/dev/null ||
        true)" 1
assert_equal environment_sync_target_count \
    "$(grep -Fxc "SYNC_TARGET=$peer_name" /etc/default/caddy-ha 2>/dev/null ||
        true)" 1
assert_command physical_ipv4_present \
    grep -Fq "$own_ipv4/22" \
    < <(ip -o -4 address show dev eth0 2>/dev/null)
assert_command stable_ipv6_present \
    grep -Fq "$own_ipv6/64" \
    < <(ip -o -6 address show dev eth0 2>/dev/null)
assert_regular_file sync_authorized_keys_regular "$authorized_keys_path"
assert_equal sync_authorized_keys_metadata \
    "$(stat -c '%U:%G:%a' "$authorized_keys_path" 2>/dev/null)" \
    caddy-sync:caddy-sync:600
assert_equal sync_authorized_keys_exact \
    "$(cat "$authorized_keys_path" 2>/dev/null)" "$expected_authorization"
assert_equal caddy_current_target \
    "$(readlink /etc/caddy/current 2>/dev/null)" "$expected_current_target"

query_and_assert unbound_own_a 127.0.0.1 5335 "$own_name" A "$own_ipv4"
query_and_assert unbound_peer_a 127.0.0.1 5335 "$peer_name" A "$peer_ipv4"
query_and_assert unbound_own_aaaa 127.0.0.1 5335 "$own_name" AAAA "$own_ipv6"
query_and_assert unbound_peer_aaaa 127.0.0.1 5335 "$peer_name" AAAA "$peer_ipv6"
reverse_query_and_assert unbound_own_ptr4 127.0.0.1 5335 \
    "$own_ipv4" "$own_name"
reverse_query_and_assert unbound_peer_ptr4 127.0.0.1 5335 \
    "$peer_ipv4" "$peer_name"
reverse_query_and_assert unbound_own_ptr6 127.0.0.1 5335 \
    "$own_ipv6" "$own_name"
reverse_query_and_assert unbound_peer_ptr6 127.0.0.1 5335 \
    "$peer_ipv6" "$peer_name"
query_and_assert pihole_peer_a 127.0.0.1 53 "$peer_name" A "$peer_ipv4"
query_and_assert pihole_peer_aaaa 127.0.0.1 53 "$peer_name" AAAA "$peer_ipv6"
query_and_assert dns_vip_ipv4_peer_a \
    "$dns_vip_ipv4" 53 "$peer_name" A "$peer_ipv4"
query_and_assert dns_vip_ipv4_peer_aaaa \
    "$dns_vip_ipv4" 53 "$peer_name" AAAA "$peer_ipv6"
query_and_assert dns_vip_ipv6_peer_a \
    "$dns_vip_ipv6" 53 "$peer_name" A "$peer_ipv4"
query_and_assert dns_vip_ipv6_peer_aaaa \
    "$dns_vip_ipv6" 53 "$peer_name" AAAA "$peer_ipv6"
assert_getent_address root_peer_ipv4 ahostsv4 "$peer_name" "$peer_ipv4"
assert_getent_address root_peer_ipv6 ahostsv6 "$peer_name" "$peer_ipv6"
assert_getent_address sync_peer_ipv4 ahostsv4 "$peer_name" "$peer_ipv4" caddy-sync
assert_getent_address sync_peer_ipv6 ahostsv6 "$peer_name" "$peer_ipv6" caddy-sync

after_state=$(state_snapshot | sha256sum | awk '{ print $1 }')
readonly after_state
printf '%s\n' \
    "action_17l_assertion_count=$assertion_count" \
    "action_17l_failed_assertion_count=$failed_assertion_count" \
    "action_17l_first_failure=$first_failure" \
    "action_17l_before_state_sha256=$before_state" \
    "action_17l_after_state_sha256=$after_state" \
    dns_queries_performed=true \
    peer_connections=false \
    synchronization_commands_executed=false \
    remote_paths_created=false \
    dns_configuration_mutations=false \
    service_mutations=false \
    filesystem_mutations=false \
    persistent_mutations=false
if [[ "$failed_assertion_count" -eq 0 &&
    "$assertion_count" -eq "$expected_assertion_count" &&
    "$before_state" == "$after_state" ]]; then
    printf '%s\n' \
        action_17l_conclusion=dns_and_sync_prerequisites_ready \
        action_17l_remote_complete=true
    exit 0
fi
printf '%s\n' \
    action_17l_conclusion=dns_or_sync_prerequisite_mismatch \
    action_17l_remote_complete=true
exit 1
