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
readonly validator=/usr/local/libexec/validate-sync-ssh.sh
readonly lsyncd_unit=/etc/systemd/system/caddy-lsyncd.service
readonly lsyncd_config=/etc/lsyncd/caddy.lua
readonly accepted_caddy_release=/etc/caddy/releases/action16ar-retry-node-a-default-deny
readonly receiver_sha256=65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134
readonly validator_sha256=85df8a934c8dd9561a6f567f42549ebc01ee2605ca630150265004b9ec108072
readonly lsyncd_unit_sha256=93cbc36cea03b8b7e1605c44667463592cf64e0293ded9f816d1e34760a69ac8
readonly node_a_sync_fingerprint='SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0'
readonly node_b_sync_fingerprint='SHA256:ykJmrl499fd2qRm9bYjgyrgeiTCA1rzTelBBKX0gy5g'
readonly node_b_host_fingerprint='SHA256:eDdqL/bS/EuVysKQ7yxJ6lpjJWf2PcymtfPwMlzacbo'
readonly node_b_public_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBwBAlvUOqcazWjzfUOnwk1AHath8Xn8eoUDXBFQIG7e caddy-ha-sync'
readonly expected_authorization="from=\"10.1.0.54,fd36:5aa8:6971:1::54\",restrict,command=\"/usr/local/libexec/caddy-sync-rsync-receiver\" $node_b_public_key"
readonly node_b_ipv4=10.1.0.54
readonly node_b_ipv6=fd36:5aa8:6971:1::54
readonly node_b_host_alias=pihole00.local.theama.co
readonly denied_command=caddy-action17c-denied-probe
readonly denied_message='Only the rsync server protocol is permitted.'

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

known_host_fingerprint() {
    ssh-keygen -F "$node_b_host_alias" -f "$known_hosts" |
        sed '/^#/d' |
        ssh-keygen -lf - -E sha256 |
        awk 'NR == 1 { print $2 }'
}

state_payload() {
    stat -c '%n|%U:%G:%a:%s:%i' \
        /var/lib/caddy-sync \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/quarantine \
        "$ssh_dir" \
        "$private_key" \
        "$public_key" \
        "$known_hosts" \
        "$authorized_keys" \
        "$receiver" \
        "$validator" \
        "$lsyncd_unit" \
        /etc/default/caddy-ha
    sha256sum \
        "$private_key" \
        "$public_key" \
        "$known_hosts" \
        "$authorized_keys" \
        "$receiver" \
        "$validator" \
        "$lsyncd_unit" \
        /etc/default/caddy-ha
    find \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/quarantine \
        -printf '%p|%y|%U:%G:%m:%s:%i\n' |
        sort
    readlink /etc/caddy/current
    readlink -e /etc/caddy/current
    for unit in \
        caddy.service \
        lighttpd.service \
        keepalived.service \
        ssh.service \
        lsyncd.service \
        caddy-lsyncd.service; do
        printf '### %s\n' "$unit"
        systemctl show "$unit" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts
        printf 'unit_file_state=%s\n' \
            "$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    done
    printf 'lsyncd_config=absent\n'
    dpkg --audit
}

validate_state() {
    [[ "$(id -u)" -eq 0 ]]
    [[ "$(hostname)" == j1-svpihole0 ]]
    grep -Fq '10.1.0.53/22' < <(ip -o -4 address show dev eth0)
    grep -Fq 'fd36:5aa8:6971:1::53/64' < <(ip -o -6 address show dev eth0)
    [[ "$(dpkg --print-architecture)" == arm64 ]]
    [[ "$(getent passwd caddy-sync | cut -d: -f6)" == /var/lib/caddy-sync ]]
    [[ "$(getent passwd caddy-sync | cut -d: -f7)" == /bin/sh ]]
    [[ "$(passwd --status caddy-sync | awk '{ print $2 }')" == L ]]
    [[ "$(id -nG caddy-sync | tr ' ' '\n' | sort)" == $'caddy-sync\ncaddy-tls' ]]
    [[ "$(stat -c '%U:%G:%a' "$ssh_dir")" == caddy-sync:caddy-sync:700 ]]
    [[ "$(stat -c '%U:%G:%a' "$private_key")" == caddy-sync:caddy-sync:600 ]]
    [[ "$(stat -c '%U:%G:%a' "$public_key")" == caddy-sync:caddy-sync:644 ]]
    [[ "$(stat -c '%U:%G:%a' "$known_hosts")" == caddy-sync:caddy-sync:600 ]]
    [[ "$(stat -c '%U:%G:%a' "$authorized_keys")" == caddy-sync:caddy-sync:600 ]]
    [[ "$(ssh-keygen -lf "$public_key" -E sha256 |
        awk '{ print $2 }')" == "$node_a_sync_fingerprint" ]]
    [[ "$(ssh-keygen -y -f "$private_key" |
        awk '{ print $1, $2 }')" == "$(awk '{ print $1, $2 }' "$public_key")" ]]
    [[ "$(known_host_fingerprint)" == "$node_b_host_fingerprint" ]]
    [[ "$(wc -l <"$known_hosts")" -eq 1 ]]
    [[ "$(wc -l <"$authorized_keys")" -eq 1 ]]
    [[ "$(<"$authorized_keys")" == "$expected_authorization" ]]
    authorization_key=$(awk '{ print $(NF-2), $(NF-1), $NF }' "$authorized_keys")
    [[ "$(ssh-keygen -lf <(printf '%s\n' "$authorization_key") \
        -E sha256 | awk '{ print $2 }')" == "$node_b_sync_fingerprint" ]]

    [[ "$(stat -c '%U:%G:%a' "$receiver")" == root:root:755 ]]
    [[ "$(file_hash "$receiver")" == "$receiver_sha256" ]]
    [[ "$(stat -c '%U:%G:%a' "$validator")" == root:root:755 ]]
    [[ "$(file_hash "$validator")" == "$validator_sha256" ]]
    [[ "$(stat -c '%U:%G:%a' "$lsyncd_unit")" == root:root:644 ]]
    [[ "$(file_hash "$lsyncd_unit")" == "$lsyncd_unit_sha256" ]]
    grep -Fq \
        'exec /usr/bin/rrsync -wo -no-del /var/lib/caddy-sync/incoming' \
        "$receiver"

    grep -Fxq 'NODE_ROLE=node-a' /etc/default/caddy-ha
    grep -Fxq 'PEER_IPV4=10.1.0.54' /etc/default/caddy-ha
    grep -Fxq 'PEER_IPV6=fd36:5aa8:6971:1::54' /etc/default/caddy-ha
    grep -Fxq 'SYNC_TARGET=pihole00.local.theama.co' /etc/default/caddy-ha
    [[ "$(readlink /etc/caddy/current)" == "$accepted_caddy_release" ]]
    [[ "$(readlink -e /etc/caddy/current)" == "$accepted_caddy_release" ]]

    [[ ! -e "$lsyncd_config" && ! -L "$lsyncd_config" ]]
    [[ "$(systemctl is-active lsyncd.service 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" == masked ]]
    [[ "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled caddy-lsyncd.service 2>/dev/null || true)" == disabled ]]
    [[ "$(systemctl is-active caddy.service 2>/dev/null || true)" == active ]]
    [[ "$(systemctl is-enabled caddy.service 2>/dev/null || true)" == disabled ]]
    [[ "$(systemctl is-active ssh.service 2>/dev/null || true)" == active ]]
    [[ "$(systemctl is-enabled ssh.service 2>/dev/null || true)" == enabled ]]
    [[ ! -e /var/lib/caddy-sync/incoming/node-a &&
        ! -L /var/lib/caddy-sync/incoming/node-a ]]
    [[ ! -e /var/lib/caddy-sync/incoming/node-b &&
        ! -L /var/lib/caddy-sync/incoming/node-b ]]
    [[ "$(find /var/lib/caddy-sync/outbound -type f | wc -l)" -eq 0 ]]
    [[ -z "$(dpkg --audit)" ]]
}

run_denied_probe() {
    local address_family=$1
    local target=$2
    local output_file=$3
    local error_file=$4
    local status=0

    runuser -u caddy-sync -- \
        ssh "$address_family" -T \
        -F /dev/null \
        -i "$private_key" \
        -o BatchMode=yes \
        -o IdentitiesOnly=yes \
        -o PreferredAuthentications=publickey \
        -o PasswordAuthentication=no \
        -o KbdInteractiveAuthentication=no \
        -o StrictHostKeyChecking=yes \
        -o UpdateHostKeys=no \
        -o GlobalKnownHostsFile=/dev/null \
        -o "UserKnownHostsFile=$known_hosts" \
        -o "HostKeyAlias=$node_b_host_alias" \
        -o ClearAllForwardings=yes \
        -o ConnectTimeout=5 \
        -o ServerAliveInterval=2 \
        -o ServerAliveCountMax=2 \
        "caddy-sync@$target" \
        "$denied_command" >"$output_file" 2>"$error_file" || status=$?

    [[ "$status" -eq 126 ]] || return 1
    [[ ! -s "$output_file" ]] || return 1
    [[ "$(<"$error_file")" == "$denied_message" ]] || return 1
}

run_rsync_dry_run() {
    local output_file=$1
    local error_file=$2
    local status=0
    local remote_shell

    remote_shell="ssh -4 -T -F /dev/null -i $private_key"
    remote_shell+=" -o BatchMode=yes -o IdentitiesOnly=yes"
    remote_shell+=" -o PreferredAuthentications=publickey"
    remote_shell+=" -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no"
    remote_shell+=" -o StrictHostKeyChecking=yes -o UpdateHostKeys=no"
    remote_shell+=" -o GlobalKnownHostsFile=/dev/null"
    remote_shell+=" -o UserKnownHostsFile=$known_hosts"
    remote_shell+=" -o HostKeyAlias=$node_b_host_alias"
    remote_shell+=" -o ClearAllForwardings=yes -o ConnectTimeout=5"
    remote_shell+=" -o ServerAliveInterval=2 -o ServerAliveCountMax=2"

    runuser -u caddy-sync -- \
        rsync \
        --archive \
        --dry-run \
        --itemize-changes \
        --no-motd \
        --timeout=10 \
        --rsh="$remote_shell" \
        /var/lib/caddy-sync/outbound/ \
        "caddy-sync@$node_b_ipv4:/node-a/" \
        >"$output_file" 2>"$error_file" || status=$?

    [[ "$status" -eq 0 ]] || return 1
    [[ ! -s "$error_file" ]] || return 1
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for value in \
        "$receiver_sha256" \
        "$validator_sha256" \
        "$lsyncd_unit_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    [[ "$node_a_sync_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$node_b_sync_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$node_b_ipv4" == 10.1.0.54 ]]
    [[ "$node_b_ipv6" == fd36:5aa8:6971:1::54 ]]
    [[ "$denied_command" != rsync\ --server\ * ]]
    printf 'action_17c_restricted_transport_driver_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

validate_state
state_before=$(state_payload | sha256sum | awk '{ print $1 }')
readonly state_before
printf 'action_17c_node_a_preflight_complete=true\n'

work_dir=$(mktemp -d /run/caddy-action17c-transport.XXXXXX)
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

ipv4_restricted_authentication=false
ipv4_forced_receiver_rejection=false
ipv6_restricted_authentication=false
ipv6_forced_receiver_rejection=false
ipv4_rsync_dry_run=false
first_failure=none

if run_denied_probe -4 "$node_b_ipv4" \
    "$work_dir/ipv4.out" "$work_dir/ipv4.err"; then
    ipv4_restricted_authentication=true
    ipv4_forced_receiver_rejection=true
else
    first_failure=ipv4_forced_receiver_rejection
fi

if [[ "$first_failure" == none ]]; then
    if run_denied_probe -6 "$node_b_ipv6" \
        "$work_dir/ipv6.out" "$work_dir/ipv6.err"; then
        ipv6_restricted_authentication=true
        ipv6_forced_receiver_rejection=true
    else
        first_failure=ipv6_forced_receiver_rejection
    fi
fi

if [[ "$first_failure" == none ]]; then
    if run_rsync_dry_run "$work_dir/rsync.out" "$work_dir/rsync.err"; then
        ipv4_rsync_dry_run=true
    else
        first_failure=ipv4_rsync_dry_run
    fi
fi

printf 'ipv4_restricted_authentication=%s\n' \
    "$ipv4_restricted_authentication"
printf 'ipv4_forced_receiver_rejection=%s\n' \
    "$ipv4_forced_receiver_rejection"
printf 'ipv6_restricted_authentication=%s\n' \
    "$ipv6_restricted_authentication"
printf 'ipv6_forced_receiver_rejection=%s\n' \
    "$ipv6_forced_receiver_rejection"
printf 'ipv4_rsync_dry_run=%s\n' "$ipv4_rsync_dry_run"

validate_state
[[ "$(state_payload | sha256sum | awk '{ print $1 }')" == "$state_before" ]]
printf 'node_a_protected_state_unchanged=true\n'
printf 'release_payload_transferred=false\n'
printf 'incoming_node_a_present=false\n'
printf 'incoming_node_b_present=false\n'
printf 'outbound_file_count=0\n'
printf 'lsyncd_configuration_present=false\n'
printf 'service_mutations=false\n'
printf 'first_failure=%s\n' "$first_failure"

cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf 'action_17c_node_a_cleanup_complete=true\n'
if [[ "$first_failure" != none ]]; then
    printf 'action_17c_restricted_transport_validation_complete=false\n'
    exit 1
fi
printf 'action_17c_restricted_transport_validation_complete=true\n'
