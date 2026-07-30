#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly ssh_dir=/var/lib/caddy-sync/.ssh
readonly private_key="$ssh_dir/id_ed25519"
readonly public_key="$private_key.pub"
readonly known_hosts="$ssh_dir/known_hosts"
readonly authorized_keys="$ssh_dir/authorized_keys"
readonly receiver=/usr/local/libexec/caddy-sync-rsync-receiver
readonly setup_helper=/usr/local/libexec/setup-sync-ssh.sh
readonly validator=/usr/local/libexec/validate-sync-ssh.sh
readonly lsyncd_config=/etc/lsyncd/caddy.lua
readonly lsyncd_unit=/etc/systemd/system/caddy-lsyncd.service
readonly receiver_sha256=65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134
readonly setup_helper_sha256=d1d1e4fd0fd3787e43d7801babfbcdec20015b6517282cdba67904aa1b554140
readonly validator_sha256=85df8a934c8dd9561a6f567f42549ebc01ee2605ca630150265004b9ec108072
readonly lsyncd_unit_sha256=93cbc36cea03b8b7e1605c44667463592cf64e0293ded9f816d1e34760a69ac8
readonly node_a_sync_fingerprint='SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0'
readonly node_b_sync_fingerprint='SHA256:ykJmrl499fd2qRm9bYjgyrgeiTCA1rzTelBBKX0gy5g'
readonly node_a_host_fingerprint='SHA256:tuPVPiBenlqqCDmfqEFfQMpM0q90zj94QMGlNZNC1QI'
readonly node_b_host_fingerprint='SHA256:eDdqL/bS/EuVysKQ7yxJ6lpjJWf2PcymtfPwMlzacbo'
readonly node_a_public_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG3MEgLhf8tsImyjkCZpQU4H7X8Xdac+iOUCxRTMM0tA caddy-ha-sync'
readonly node_b_public_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBwBAlvUOqcazWjzfUOnwk1AHath8Xn8eoUDXBFQIG7e caddy-ha-sync'

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for value in \
        "$receiver_sha256" \
        "$setup_helper_sha256" \
        "$validator_sha256" \
        "$lsyncd_unit_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    for value in \
        "$node_a_sync_fingerprint" \
        "$node_b_sync_fingerprint" \
        "$node_a_host_fingerprint" \
        "$node_b_host_fingerprint"; do
        [[ "$value" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    done
    printf 'action_17_readiness_inspector_self_test_complete=true\n'
    exit 0
elif [[ $# -ne 2 || "$1" != --node ||
    ! "$2" =~ ^node-[ab]$ ]]; then
    printf 'Usage: %s --node node-a|node-b\n' "${0##*/}" >&2
    exit 2
fi

readonly node_role=$2
check_count=0
true_check_count=0
mismatch_count=0
first_failure=none

record_result() {
    local label=$1
    local matched=$2

    check_count=$((check_count + 1))
    if [[ "$matched" == true ]]; then
        true_check_count=$((true_check_count + 1))
    else
        mismatch_count=$((mismatch_count + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$label
        fi
    fi
    printf 'check_%s=%s\n' "$label" "$matched"
}

record_equal() {
    local label=$1
    local observed=$2
    local expected=$3

    if [[ "$observed" == "$expected" ]]; then
        record_result "$label" true
    else
        record_result "$label" false
    fi
}

record_command() {
    local label=$1
    shift

    if "$@" >/dev/null 2>&1; then
        record_result "$label" true
    else
        record_result "$label" false
    fi
}

record_absent() {
    local label=$1
    local target=$2

    if [[ ! -e "$target" && ! -L "$target" ]]; then
        record_result "$label" true
    else
        record_result "$label" false
    fi
}

file_hash() {
    sha256sum "$1" 2>/dev/null | awk '{ print $1 }'
}

key_fingerprint() {
    ssh-keygen -lf "$1" -E sha256 2>/dev/null | awk '{ print $2 }'
}

known_host_fingerprint() {
    local host=$1

    ssh-keygen -F "$host" -f "$known_hosts" 2>/dev/null |
        sed '/^#/d' |
        ssh-keygen -lf - -E sha256 2>/dev/null |
        awk 'NR == 1 { print $2 }'
}

printf 'action_17_readiness_remote_reached=true\n'
printf 'readiness_node_role=%s\n' "$node_role"
record_equal root_effective_uid "$(id -u 2>/dev/null || true)" 0
record_equal architecture \
    "$(dpkg --print-architecture 2>/dev/null || true)" arm64
record_equal caddy_sync_home \
    "$(getent passwd caddy-sync 2>/dev/null | cut -d: -f6 || true)" \
    /var/lib/caddy-sync
record_equal caddy_sync_shell \
    "$(getent passwd caddy-sync 2>/dev/null | cut -d: -f7 || true)" /bin/sh
record_equal caddy_sync_password_state \
    "$(passwd --status caddy-sync 2>/dev/null | awk '{ print $2 }' || true)" L

for directory in \
    /var/lib/caddy-sync \
    /var/lib/caddy-sync/outbound \
    /var/lib/caddy-sync/incoming \
    /var/lib/caddy-sync/quarantine; do
    label=${directory##*/}
    [[ "$directory" == /var/lib/caddy-sync ]] && label=root
    record_equal "${label}_directory_meta" \
        "$(stat -c '%U:%G:%a' "$directory" 2>/dev/null || true)" \
        caddy-sync:caddy-sync:750
done
record_equal ssh_directory_meta \
    "$(stat -c '%U:%G:%a' "$ssh_dir" 2>/dev/null || true)" \
    caddy-sync:caddy-sync:700

record_equal private_key_meta \
    "$(stat -c '%U:%G:%a' "$private_key" 2>/dev/null || true)" \
    caddy-sync:caddy-sync:600
record_command private_key_regular test -f "$private_key"
record_command private_key_not_symlink test ! -L "$private_key"
record_equal public_key_meta \
    "$(stat -c '%U:%G:%a' "$public_key" 2>/dev/null || true)" \
    caddy-sync:caddy-sync:644
record_command public_key_regular test -f "$public_key"
record_command public_key_not_symlink test ! -L "$public_key"
record_equal private_public_key_match \
    "$(ssh-keygen -y -f "$private_key" 2>/dev/null |
        awk '{ print $1, $2 }')" \
    "$(awk '{ print $1, $2 }' "$public_key" 2>/dev/null || true)"
record_equal known_hosts_meta \
    "$(stat -c '%U:%G:%a' "$known_hosts" 2>/dev/null || true)" \
    caddy-sync:caddy-sync:600
record_command known_hosts_regular test -f "$known_hosts"
record_command known_hosts_not_symlink test ! -L "$known_hosts"
record_equal known_hosts_line_count "$(wc -l <"$known_hosts" 2>/dev/null)" 1

for artifact in \
    "$receiver:$receiver_sha256" \
    "$setup_helper:$setup_helper_sha256" \
    "$validator:$validator_sha256" \
    "$lsyncd_unit:$lsyncd_unit_sha256"; do
    path=${artifact%%:*}
    expected_hash=${artifact##*:}
    label=${path##*/}
    label=${label//[^a-zA-Z0-9]/_}
    record_equal "${label}_meta" \
        "$(stat -c '%U:%G:%a' "$path" 2>/dev/null || true)" \
        "$(if [[ "$path" == "$lsyncd_unit" ]]; then
            printf 'root:root:644'
        else
            printf 'root:root:755'
        fi)"
    record_equal "${label}_hash" "$(file_hash "$path")" "$expected_hash"
done
record_command receiver_no_delete_contract \
    grep -Fq \
    'exec /usr/bin/rrsync -wo -no-del /var/lib/caddy-sync/incoming' \
    "$receiver"
record_absent lsyncd_configuration_absent "$lsyncd_config"
record_equal lsyncd_active \
    "$(systemctl is-active lsyncd.service 2>/dev/null || true)" inactive
record_equal lsyncd_enabled \
    "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" masked
record_equal caddy_lsyncd_active \
    "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" inactive
record_equal caddy_lsyncd_enabled \
    "$(systemctl is-enabled caddy-lsyncd.service 2>/dev/null || true)" disabled
record_equal caddy_active \
    "$(systemctl is-active caddy.service 2>/dev/null || true)" active
record_equal caddy_enabled \
    "$(systemctl is-enabled caddy.service 2>/dev/null || true)" disabled
record_equal ssh_active \
    "$(systemctl is-active ssh.service 2>/dev/null || true)" active
record_equal ssh_enabled \
    "$(systemctl is-enabled ssh.service 2>/dev/null || true)" enabled
record_absent incoming_node_a_absent \
    /var/lib/caddy-sync/incoming/node-a
record_absent incoming_node_b_absent \
    /var/lib/caddy-sync/incoming/node-b
record_equal outbound_regular_file_count \
    "$(find /var/lib/caddy-sync/outbound -type f 2>/dev/null | wc -l)" 0
record_equal dpkg_audit_bytes \
    "$(dpkg --audit 2>/dev/null | wc -c)" 0

if [[ "$node_role" == node-a ]]; then
    record_equal hostname "$(hostname 2>/dev/null || true)" j1-svpihole0
    record_command ipv4_present \
        grep -Fq '10.1.0.53/22' \
        < <(ip -o -4 address show dev eth0 2>/dev/null)
    record_command environment_role \
        grep -Fxq 'NODE_ROLE=node-a' /etc/default/caddy-ha
    record_command environment_sync_target \
        grep -Fxq 'SYNC_TARGET=pihole00.local.theama.co' \
        /etc/default/caddy-ha
    record_equal own_sync_fingerprint "$(key_fingerprint "$public_key")" \
        "$node_a_sync_fingerprint"
    record_equal public_key_exact "$(<"$public_key")" "$node_a_public_key"
    record_equal peer_host_fingerprint \
        "$(known_host_fingerprint pihole00.local.theama.co)" \
        "$node_b_host_fingerprint"
    record_equal authorized_keys_meta \
        "$(stat -c '%U:%G:%a' "$authorized_keys" 2>/dev/null || true)" \
        caddy-sync:caddy-sync:600
    expected_authorization="from=\"10.1.0.54,fd36:5aa8:6971:1::54\",restrict,command=\"/usr/local/libexec/caddy-sync-rsync-receiver\" $node_b_public_key"
    record_equal authorized_keys_exact \
        "$(<"$authorized_keys")" "$expected_authorization"
    record_equal authorized_keys_line_count \
        "$(wc -l <"$authorized_keys" 2>/dev/null)" 1
    record_equal caddy_current_target \
        "$(readlink /etc/caddy/current 2>/dev/null || true)" \
        /etc/caddy/releases/action16ar-retry-node-a-default-deny
    readonly expected_peer_role=node-b
    readonly expected_peer_ip=10.1.0.54
else
    record_equal hostname "$(hostname 2>/dev/null || true)" j1-svpihole00
    record_command ipv4_present \
        grep -Fq '10.1.0.54/22' \
        < <(ip -o -4 address show dev eth0 2>/dev/null)
    record_command environment_role \
        grep -Fxq 'NODE_ROLE=node-b' /etc/default/caddy-ha
    record_command environment_sync_target \
        grep -Fxq 'SYNC_TARGET=pihole0.local.theama.co' \
        /etc/default/caddy-ha
    record_equal own_sync_fingerprint "$(key_fingerprint "$public_key")" \
        "$node_b_sync_fingerprint"
    record_equal public_key_exact "$(<"$public_key")" "$node_b_public_key"
    record_equal peer_host_fingerprint \
        "$(known_host_fingerprint pihole0.local.theama.co)" \
        "$node_a_host_fingerprint"
    record_absent authorized_keys_absent "$authorized_keys"
    record_equal caddy_current_target \
        "$(readlink /etc/caddy/current 2>/dev/null || true)" \
        /etc/caddy/releases/bootstrap
    readonly expected_peer_role=node-a
    readonly expected_peer_ip=10.1.0.53
fi

printf 'package_lsyncd=%s\n' \
    "$(dpkg-query -W -f='${Version}' lsyncd 2>/dev/null || true)"
printf 'package_rsync=%s\n' \
    "$(dpkg-query -W -f='${Version}' rsync 2>/dev/null || true)"
printf 'package_openssh_client=%s\n' \
    "$(dpkg-query -W -f='${Version}' openssh-client 2>/dev/null || true)"
printf 'package_openssh_server=%s\n' \
    "$(dpkg-query -W -f='${Version}' openssh-server 2>/dev/null || true)"
printf 'expected_peer_role=%s\n' "$expected_peer_role"
printf 'expected_peer_ip=%s\n' "$expected_peer_ip"
printf 'readiness_check_count=%s\n' "$check_count"
printf 'readiness_true_check_count=%s\n' "$true_check_count"
printf 'readiness_mismatch_count=%s\n' "$mismatch_count"
printf 'readiness_first_failure=%s\n' "$first_failure"
printf 'peer_connections=false\n'
printf 'synchronization_commands_executed=false\n'
printf 'installed_helper_execution=false\n'
printf 'service_mutations=false\n'
printf 'filesystem_mutations=false\n'
if [[ "$mismatch_count" -eq 0 ]]; then
    printf 'action_17_%s_readiness_valid=true\n' "${node_role//-/_}"
    printf 'action_17_readiness_inspection_complete=true\n'
    exit 0
fi
printf 'action_17_%s_readiness_valid=false\n' "${node_role//-/_}"
printf 'action_17_readiness_inspection_complete=true\n'
exit 1
