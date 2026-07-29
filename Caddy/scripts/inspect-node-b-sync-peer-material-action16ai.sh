#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly expected_sync_fingerprint='SHA256:ykJmrl499fd2qRm9bYjgyrgeiTCA1rzTelBBKX0gy5g'
readonly expected_node_a_host_fingerprint='SHA256:tuPVPiBenlqqCDmfqEFfQMpM0q90zj94QMGlNZNC1QI'
readonly ssh_dir=/var/lib/caddy-sync/.ssh
readonly private_key="$ssh_dir/id_ed25519"
readonly public_key="$private_key.pub"
readonly known_hosts="$ssh_dir/known_hosts"
readonly host_key=/etc/ssh/ssh_host_ed25519_key.pub

readonly -a script_checksums=(
    '65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134  /usr/local/libexec/caddy-sync-rsync-receiver'
    'd1d1e4fd0fd3787e43d7801babfbcdec20015b6517282cdba67904aa1b554140  /usr/local/libexec/setup-sync-ssh.sh'
    '85df8a934c8dd9561a6f567f42549ebc01ee2605ca630150265004b9ec108072  /usr/local/libexec/validate-sync-ssh.sh'
)

if [[ "${1:-}" == --self-test ]]; then
    [[ "$expected_sync_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$expected_node_a_host_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "${#script_checksums[@]}" -eq 3 ]]
    printf 'action_16ai_node_b_inspector_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(hostname)" == j1-svpihole00 ]]
grep -Fq '10.1.0.54/22' < <(ip -o -4 address show dev eth0)
[[ "$(dpkg --print-architecture)" == arm64 ]]
[[ "$(dpkg-query -W -f='${Version}' rsync)" == '3.2.7-1+deb12u6' ]]
[[ "$(dpkg-query -W -f='${Version}' openssh-client)" == '1:9.2p1-2+deb12u10' ]]
[[ "$(dpkg-query -W -f='${Version}' openssh-server)" == '1:9.2p1-2+deb12u10' ]]

[[ "$(getent passwd caddy-sync | cut -d: -f6)" == /var/lib/caddy-sync ]]
[[ "$(getent passwd caddy-sync | cut -d: -f7)" == /bin/sh ]]
[[ "$(passwd --status caddy-sync | awk '{ print $2 }')" == L ]]
[[ "$(stat -c '%U:%G:%a' "$ssh_dir")" == caddy-sync:caddy-sync:700 ]]
[[ -f "$private_key" && ! -L "$private_key" ]]
[[ -f "$public_key" && ! -L "$public_key" ]]
[[ -f "$known_hosts" && ! -L "$known_hosts" ]]
[[ "$(stat -c '%U:%G:%a' "$private_key")" == caddy-sync:caddy-sync:600 ]]
[[ "$(stat -c '%U:%G:%a' "$public_key")" == caddy-sync:caddy-sync:644 ]]
[[ "$(stat -c '%U:%G:%a' "$known_hosts")" == caddy-sync:caddy-sync:600 ]]

public_key_value=$(<"$public_key")
[[ "$public_key_value" =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+\ .+$ ]]
derived_public_key=$(
    ssh-keygen -y -f "$private_key" |
        awk '{ print $1, $2 }'
)
recorded_public_key=$(
    awk '{ print $1, $2 }' "$public_key"
)
[[ "$derived_public_key" == "$recorded_public_key" ]]
sync_fingerprint=$(ssh-keygen -lf "$public_key" -E sha256 | awk '{ print $2 }')
[[ "$sync_fingerprint" == "$expected_sync_fingerprint" ]]

for checksum in "${script_checksums[@]}"; do
    printf '%s\n' "$checksum" | sha256sum --check --status
    script_path=${checksum#*  }
    [[ "$(stat -c '%U:%G:%a' "$script_path")" == root:root:755 ]]
done

ssh-keygen -F pihole0.local.theama.co -f "$known_hosts" >/dev/null
known_node_a_fingerprint=$(
    ssh-keygen -F pihole0.local.theama.co -f "$known_hosts" |
        sed '/^#/d' |
        ssh-keygen -lf - -E sha256 |
        awk 'NR == 1 { print $2 }'
)
[[ "$known_node_a_fingerprint" == "$expected_node_a_host_fingerprint" ]]

[[ ! -e "$ssh_dir/authorized_keys" && ! -L "$ssh_dir/authorized_keys" ]]
[[ ! -e /etc/lsyncd/caddy.lua && ! -L /etc/lsyncd/caddy.lua ]]
[[ "$(systemctl is-active lsyncd.service 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" == masked ]]
systemctl is-active --quiet caddy.service
systemctl is-active --quiet ssh.service
[[ "$(systemctl is-enabled ssh.service 2>/dev/null || true)" == enabled ]]

[[ -f "$host_key" && ! -L "$host_key" ]]
[[ "$(stat -c '%U:%G:%a' "$host_key")" == root:root:644 ]]
host_key_value=$(<"$host_key")
[[ "$host_key_value" =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+\ .+$ ]]
host_key_fingerprint=$(ssh-keygen -lf "$host_key" -E sha256 | awk '{ print $2 }')
[[ "$host_key_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]

[[ -z "$(dpkg --audit)" ]]

printf 'node_b_host_ed25519_fingerprint=%s\n' "$host_key_fingerprint"
printf 'node_b_host_ed25519_public_key=%s\n' "$host_key_value"
printf 'node_b_sync_ed25519_fingerprint=%s\n' "$sync_fingerprint"
printf 'node_b_sync_ed25519_public_key=%s\n' "$public_key_value"
printf 'node_b_authorized_keys_present=false\n'
printf 'node_b_sync_peer_material_complete=true\n'
