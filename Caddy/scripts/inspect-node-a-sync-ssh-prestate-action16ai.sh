#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly expected_host_key_fingerprint='SHA256:tuPVPiBenlqqCDmfqEFfQMpM0q90zj94QMGlNZNC1QI'
readonly environment_sha256='2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8'
readonly host_key=/etc/ssh/ssh_host_ed25519_key.pub
readonly ssh_dir=/var/lib/caddy-sync/.ssh

readonly -a absent_targets=(
    "$ssh_dir/id_ed25519"
    "$ssh_dir/id_ed25519.pub"
    "$ssh_dir/known_hosts"
    "$ssh_dir/authorized_keys"
    /usr/local/libexec/caddy-sync-rsync-receiver
    /usr/local/libexec/setup-sync-ssh.sh
    /usr/local/libexec/validate-sync-ssh.sh
    /etc/lsyncd/caddy.lua
)

if [[ "${1:-}" == --self-test ]]; then
    [[ "$expected_host_key_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$environment_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "${#absent_targets[@]}" -eq 8 ]]
    printf 'action_16ai_node_a_inspector_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

group_names() {
    id -nG "$1" |
        tr ' ' '\n' |
        sed '/^$/d' |
        sort
}

group_members() {
    getent group "$1" |
        cut -d: -f4 |
        tr ',' '\n' |
        sed '/^$/d' |
        sort
}

[[ "$(hostname)" == j1-svpihole0 ]]
grep -Fq '10.1.0.53/22' < <(ip -o -4 address show dev eth0)
[[ "$(dpkg --print-architecture)" == arm64 ]]
[[ "$(dpkg-query -W -f='${db:Status-Abbrev}:${Version}:${Architecture}' caddy)" == 'ii :2.11.4:arm64' ]]
[[ "$(dpkg-query -W -f='${db:Status-Abbrev}:${Version}:${Architecture}' lsyncd)" == 'ii :2.2.3-1:arm64' ]]
[[ "$(dpkg-query -W -f='${db:Status-Abbrev}:${Version}:${Architecture}' rsync)" == 'ii :3.2.7-1+deb12u6:arm64' ]]
[[ "$(dpkg-query -W -f='${Version}' openssh-client)" == '1:9.2p1-2+deb12u10' ]]
[[ "$(dpkg-query -W -f='${Version}' openssh-server)" == '1:9.2p1-2+deb12u10' ]]

[[ "$(id -u caddy-sync)" -eq 994 ]]
[[ "$(id -g caddy-sync)" -eq 990 ]]
[[ "$(group_names caddy-sync)" == $'caddy-sync\ncaddy-tls' ]]
[[ "$(getent passwd caddy-sync | cut -d: -f6)" == /var/lib/caddy-sync ]]
[[ "$(getent passwd caddy-sync | cut -d: -f7)" == /bin/sh ]]
[[ "$(passwd --status caddy-sync | awk '{ print $2 }')" == L ]]
[[ "$(group_members caddy-tls)" == $'caddy\ncaddy-sync\nkeepalived_script' ]]
[[ "$(stat -c '%U:%G:%a' /var/lib/caddy-sync)" == caddy-sync:caddy-sync:750 ]]
[[ "$(stat -c '%U:%G:%a' "$ssh_dir")" == caddy-sync:caddy-sync:700 ]]

[[ "$(sha256sum /etc/default/caddy-ha | awk '{ print $1 }')" == "$environment_sha256" ]]
[[ -L /etc/caddy/current ]]
[[ "$(readlink /etc/caddy/current)" == /etc/caddy/releases/bootstrap ]]
[[ "$(readlink -e /etc/caddy/current)" == /etc/caddy/releases/bootstrap ]]
[[ "$(stat -c '%U:%G:%a' /etc/caddy/releases/bootstrap)" == root:caddy-tls:750 ]]

for target in "${absent_targets[@]}"; do
    [[ ! -e "$target" && ! -L "$target" ]]
done
mapfile -t action_staging < <(
    find /var/tmp -mindepth 1 -maxdepth 1 \
        -name 'caddy-sync-ssh-node-a-action16ai*' -print |
        sort
)
[[ "${#action_staging[@]}" -eq 0 ]]

[[ "$(systemctl is-active caddy.service 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled caddy.service 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active lsyncd.service 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" == masked ]]
systemctl is-active --quiet ssh.service
[[ "$(systemctl is-enabled ssh.service 2>/dev/null || true)" == enabled ]]

sshd_effective=$(
    /usr/sbin/sshd -T \
        -C user=caddy-sync,host=pihole0.local.theama.co,addr=10.1.0.54
)
grep -Fxq 'pubkeyauthentication yes' <<<"$sshd_effective"
grep -Fxq \
    'authorizedkeysfile .ssh/authorized_keys .ssh/authorized_keys2' \
    <<<"$sshd_effective"

[[ -f "$host_key" && ! -L "$host_key" ]]
[[ "$(stat -c '%U:%G:%a' "$host_key")" == root:root:644 ]]
host_key_value=$(<"$host_key")
[[ "$host_key_value" =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+\ .+$ ]]
host_key_fingerprint=$(ssh-keygen -lf "$host_key" -E sha256 | awk '{ print $2 }')
[[ "$host_key_fingerprint" == "$expected_host_key_fingerprint" ]]

[[ -z "$(dpkg --audit)" ]]

printf 'node_a_host_ed25519_fingerprint=%s\n' "$host_key_fingerprint"
printf 'node_a_host_ed25519_public_key=%s\n' "$host_key_value"
printf 'node_a_sync_private_key_present=false\n'
printf 'node_a_sync_authorized_keys_present=false\n'
printf 'node_a_sync_live_scripts_present=false\n'
printf 'node_a_sync_ssh_prestate_complete=true\n'
