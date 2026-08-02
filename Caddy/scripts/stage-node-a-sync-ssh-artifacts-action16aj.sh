#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly stage=/var/tmp/caddy-sync-ssh-node-a-action16aj
readonly environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly live_lighttpd_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92
readonly candidate_lighttpd_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13
readonly keepalived_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly sysctl_sha256=d7036eaead2f5ef20afa8bdf20a7a353ee700532a095822320a1b9efad4846e8
readonly expected_node_b_host_fingerprint='SHA256:eDdqL/bS/EuVysKQ7yxJ6lpjJWf2PcymtfPwMlzacbo'
readonly expected_node_b_sync_fingerprint='SHA256:ykJmrl499fd2qRm9bYjgyrgeiTCA1rzTelBBKX0gy5g'

readonly -a expected_files=(
    caddy-sync-rsync-receiver
    node-b-host-ed25519.pub
    node-b-sync-ed25519.pub
    setup-sync-ssh.sh
    validate-sync-ssh.sh
)
readonly -a expected_checksums=(
    '65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134  caddy-sync-rsync-receiver'
    '909ee3ca843757d8d956ac6d442d6079134b0235fa7d37c97d80590eb5870fbd  node-b-host-ed25519.pub'
    'c9a2ecfcc6a44c0cd30d06bbb2841ec50ffd11866ce1da77ff69f2b5ff8320b0  node-b-sync-ed25519.pub'
    'd1d1e4fd0fd3787e43d7801babfbcdec20015b6517282cdba67904aa1b554140  setup-sync-ssh.sh'
    '85df8a934c8dd9561a6f567f42549ebc01ee2605ca630150265004b9ec108072  validate-sync-ssh.sh'
)

if [[ "${1:-}" == --self-test ]]; then
    [[ "${#expected_files[@]}" -eq 5 ]]
    [[ "${#expected_checksums[@]}" -eq 5 ]]
    [[ "$expected_node_b_host_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$expected_node_b_sync_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    printf 'action_16aj_sync_ssh_stage_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

package_inventory() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        sort
}

protected_service_state() {
    local service

    for service in \
        lighttpd.service keepalived.service ssh.service unbound.service \
        pihole-FTL.service munin-node.service caddy.service \
        caddy-api.service lsyncd.service uuidd.service uuidd.socket; do
        printf '### %s\n' "$service"
        systemctl show "$service" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts
        printf 'unit_file_state=%s\n' \
            "$(systemctl is-enabled "$service" 2>/dev/null || true)"
    done
}

identity_state() {
    id caddy
    id caddy-sync
    id keepalived_script
    passwd --status caddy-sync
    passwd --status keepalived_script
    getent group caddy-tls
    stat -c '%n|%U:%G:%a:%s:%Y:%i' \
        /etc/caddy/releases \
        /var/lib/caddy-sync \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/quarantine \
        /var/lib/caddy-sync/.ssh
}

tree_state() {
    local root=$1

    find "$root" -printf '%P|%y|%U:%G:%m:%s:%Y:%i\n' | sort
    find "$root" -type f -print0 |
        sort -z |
        xargs -0 -r sha256sum
}

tree_hash() {
    local root=$1

    (
        cd "$root"
        find . -type f -print0 |
            sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

protected_state() {
    package_inventory
    identity_state
    protected_service_state
    ss -H -lntup | sort
    tree_state /etc/caddy/releases/bootstrap
    tree_state /var/tmp/caddy-source-node-a-action16af
    tree_state /var/tmp/caddy-cert-node-a-action16ae
    tree_state /var/lib/caddy
    tree_state /var/log/caddy
    find /var/backups/caddy-ha -mindepth 1 -maxdepth 1 \
        -printf '%f|%y|%U:%G:%m:%s:%Y:%i\n' |
        sort
    sha256sum \
        /etc/default/caddy-ha \
        /etc/lighttpd/lighttpd.conf \
        /etc/lighttpd/conf-enabled/external.conf \
        /var/tmp/caddy-ha-lighttpd-node-a-action16ab/lighttpd.conf \
        /etc/keepalived/keepalived.conf \
        /etc/sysctl.d/70-caddy-ha.conf
    /usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind
    /usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind
    dpkg --audit
}

validate_live_state() {
    local target

    [[ "$(hostname)" == j1-svpihole0 ]]
    grep -Fq '10.1.0.53/22' < <(ip -o -4 address show dev eth0)
    [[ "$(dpkg --print-architecture)" == arm64 ]]
    [[ "$(dpkg-query -W -f='${db:Status-Abbrev}:${Version}:${Architecture}' caddy)" == 'ii :2.11.4:arm64' ]]
    [[ "$(dpkg-query -W -f='${db:Status-Abbrev}:${Version}:${Architecture}' lsyncd)" == 'ii :2.2.3-1:arm64' ]]
    [[ "$(dpkg-query -W -f='${Version}' rsync)" == '3.2.7-1+deb12u6' ]]
    [[ "$(dpkg-query -W -f='${Version}' openssh-server)" == '1:9.2p1-2+deb12u10' ]]

    [[ "$(getent passwd caddy-sync | cut -d: -f6)" == /var/lib/caddy-sync ]]
    [[ "$(getent passwd caddy-sync | cut -d: -f7)" == /bin/sh ]]
    [[ "$(passwd --status caddy-sync | awk '{ print $2 }')" == L ]]
    [[ "$(stat -c '%U:%G:%a' /var/lib/caddy-sync/.ssh)" == caddy-sync:caddy-sync:700 ]]

    [[ "$(sha256sum /etc/default/caddy-ha | awk '{ print $1 }')" == "$environment_sha256" ]]
    [[ -L /etc/caddy/current ]]
    [[ "$(readlink /etc/caddy/current)" == /etc/caddy/releases/bootstrap ]]
    [[ "$(readlink -e /etc/caddy/current)" == /etc/caddy/releases/bootstrap ]]
    [[ "$(stat -c '%U:%G:%a' /etc/caddy/releases/bootstrap)" == root:caddy-tls:750 ]]

    for target in \
        /var/lib/caddy-sync/.ssh/id_ed25519 \
        /var/lib/caddy-sync/.ssh/id_ed25519.pub \
        /var/lib/caddy-sync/.ssh/known_hosts \
        /var/lib/caddy-sync/.ssh/authorized_keys \
        /usr/local/libexec/caddy-sync-rsync-receiver \
        /usr/local/libexec/setup-sync-ssh.sh \
        /usr/local/libexec/validate-sync-ssh.sh \
        /etc/lsyncd/caddy.lua; do
        [[ ! -e "$target" && ! -L "$target" ]]
    done

    [[ "$(systemctl is-active caddy.service 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled caddy.service 2>/dev/null || true)" == masked ]]
    [[ "$(systemctl is-active lsyncd.service 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" == masked ]]
    for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
        systemctl is-active --quiet "$service"
    done

    [[ "$(tree_hash /etc/lighttpd)" == "$live_lighttpd_sha256" ]]
    [[ "$(tree_hash /var/tmp/caddy-ha-lighttpd-node-a-action16ab)" == "$candidate_lighttpd_sha256" ]]
    [[ "$(sha256sum /etc/keepalived/keepalived.conf | awk '{ print $1 }')" == "$keepalived_sha256" ]]
    [[ "$(sha256sum /etc/sysctl.d/70-caddy-ha.conf | awk '{ print $1 }')" == "$sysctl_sha256" ]]
    [[ "$(/usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind)" == 1 ]]
    [[ "$(/usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind)" == 1 ]]
    [[ -z "$(dpkg --audit)" ]]
}

validate_stage() {
    local checksum expected_hash relative_path
    local -a actual_files=()

    [[ -d "$stage" && ! -L "$stage" ]]
    [[ "$(stat -c '%U:%G:%a' "$stage")" == root:root:750 ]]
    if find "$stage" -type l -print -quit | grep -q .; then
        return 1
    fi
    mapfile -t actual_files < <(
        find "$stage" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' |
            sort
    )
    [[ "${actual_files[*]}" == "${expected_files[*]}" ]]

    for checksum in "${expected_checksums[@]}"; do
        expected_hash=${checksum%% *}
        relative_path=${checksum#*  }
        [[ -f "$stage/$relative_path" && ! -L "$stage/$relative_path" ]]
        [[ "$(sha256sum "$stage/$relative_path" |
            awk '{ print $1 }')" == "$expected_hash" ]]
        case "$relative_path" in
            *.sh | caddy-sync-rsync-receiver)
                [[ "$(stat -c '%U:%G:%a' "$stage/$relative_path")" == root:root:750 ]]
                ;;
            *)
                [[ "$(stat -c '%U:%G:%a' "$stage/$relative_path")" == root:root:640 ]]
                ;;
        esac
    done

    [[ "$(ssh-keygen -lf "$stage/node-b-host-ed25519.pub" -E sha256 |
        awk '{ print $2 }')" == "$expected_node_b_host_fingerprint" ]]
    [[ "$(ssh-keygen -lf "$stage/node-b-sync-ed25519.pub" -E sha256 |
        awk '{ print $2 }')" == "$expected_node_b_sync_fingerprint" ]]
}

success=false
stage_created=false
rollback() {
    local original_rc=$?
    local rollback_ok=true

    if [[ "$success" == true ]]; then
        return
    fi

    set +e
    if [[ "$stage_created" == true ]]; then
        rm -rf -- "$stage"
    fi
    if [[ -e "$stage" || -L "$stage" ]]; then
        rollback_ok=false
    fi
    validate_live_state || rollback_ok=false
    [[ "$(protected_state)" == "$protected_before" ]] || rollback_ok=false

    if [[ "$rollback_ok" == true ]]; then
        printf 'action_16aj_stage_rollback_complete=true\n' >&2
        exit "$original_rc"
    fi
    printf 'action_16aj_stage_rollback_complete=false\n' >&2
    printf 'manual_intervention_required=true\n' >&2
    exit 97
}
trap rollback EXIT

validate_live_state
[[ ! -e "$stage" && ! -L "$stage" ]]
protected_before=$(protected_state)
readonly protected_before

install -d -o root -g root -m 0750 "$stage"
stage_created=true
tar --extract --file - --directory "$stage" \
    --no-same-owner --no-same-permissions

find "$stage" -mindepth 1 -maxdepth 1 -type f \
    -exec chown root:root {} +
chmod 0750 \
    "$stage/caddy-sync-rsync-receiver" \
    "$stage/setup-sync-ssh.sh" \
    "$stage/validate-sync-ssh.sh"
chmod 0640 \
    "$stage/node-b-host-ed25519.pub" \
    "$stage/node-b-sync-ed25519.pub"

validate_stage
validate_live_state
[[ "$(protected_state)" == "$protected_before" ]]

printf 'stage_path=%s\n' "$stage"
printf 'stage_owner_mode=root:root:750\n'
printf 'stage_file_count=5\n'
printf 'node_b_host_fingerprint=%s\n' "$expected_node_b_host_fingerprint"
printf 'node_b_sync_fingerprint=%s\n' "$expected_node_b_sync_fingerprint"
printf 'protected_state_unchanged=true\n'
printf 'action_16aj_sync_ssh_stage_complete=true\n'
success=true
