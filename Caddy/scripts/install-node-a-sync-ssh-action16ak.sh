#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly retained_stage=/var/tmp/caddy-sync-ssh-node-a-action16aj-e
readonly ssh_dir=/var/lib/caddy-sync/.ssh
readonly private_key="$ssh_dir/id_ed25519"
readonly public_key="$private_key.pub"
readonly known_hosts="$ssh_dir/known_hosts"
readonly authorized_keys="$ssh_dir/authorized_keys"
readonly libexec=/usr/local/libexec
readonly receiver="$libexec/caddy-sync-rsync-receiver"
readonly setup_helper="$libexec/setup-sync-ssh.sh"
readonly validator="$libexec/validate-sync-ssh.sh"
readonly lsyncd_config=/etc/lsyncd/caddy.lua

readonly expected_stage_inode=1670964
readonly expected_stage_device=66306
readonly environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly live_lighttpd_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92
readonly candidate_lighttpd_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13
readonly keepalived_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly sysctl_sha256=d7036eaead2f5ef20afa8bdf20a7a353ee700532a095822320a1b9efad4846e8
readonly package_inventory_sha256=6377ab1492b2da992dce53199e359c5a2faf3563abd8bf766e6d6967fa07da5c
readonly expected_node_b_host_fingerprint='SHA256:eDdqL/bS/EuVysKQ7yxJ6lpjJWf2PcymtfPwMlzacbo'
readonly expected_node_b_sync_fingerprint='SHA256:ykJmrl499fd2qRm9bYjgyrgeiTCA1rzTelBBKX0gy5g'

readonly -a expected_stage_files=(
    caddy-sync-rsync-receiver
    node-b-host-ed25519.pub
    node-b-sync-ed25519.pub
    setup-sync-ssh.sh
    validate-sync-ssh.sh
)
readonly -a expected_stage_checksums=(
    '65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134  caddy-sync-rsync-receiver'
    '909ee3ca843757d8d956ac6d442d6079134b0235fa7d37c97d80590eb5870fbd  node-b-host-ed25519.pub'
    'c9a2ecfcc6a44c0cd30d06bbb2841ec50ffd11866ce1da77ff69f2b5ff8320b0  node-b-sync-ed25519.pub'
    'd1d1e4fd0fd3787e43d7801babfbcdec20015b6517282cdba67904aa1b554140  setup-sync-ssh.sh'
    '85df8a934c8dd9561a6f567f42549ebc01ee2605ca630150265004b9ec108072  validate-sync-ssh.sh'
)
readonly -a live_targets=(
    "$private_key"
    "$public_key"
    "$known_hosts"
    "$authorized_keys"
    "$receiver"
    "$setup_helper"
    "$validator"
    "$lsyncd_config"
)

tree_hash() {
    local root=$1

    (
        cd "$root"
        find . -type f -print0 |
            sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

stage_state() {
    find "$retained_stage" -printf '%P|%y|%U:%G:%m:%s:%T@:%i\n' |
        sort
    find "$retained_stage" -type f -print0 |
        sort -z |
        xargs -0 -r sha256sum
}

service_state() {
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

protected_state() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        sort
    id caddy
    id caddy-sync
    id keepalived_script
    passwd --status caddy-sync
    passwd --status keepalived_script
    getent group caddy-tls
    stat -c '%n|%U:%G:%a:%s:%i' \
        /etc/caddy/releases \
        /var/lib/caddy-sync \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/quarantine
    service_state
    ss -H -lntup | sort
    stage_state
    sha256sum \
        /etc/default/caddy-ha \
        /etc/lighttpd/lighttpd.conf \
        /etc/lighttpd/conf-enabled/external.conf \
        /var/tmp/caddy-ha-lighttpd-node-a-action16ab/lighttpd.conf \
        /etc/keepalived/keepalived.conf \
        /etc/sysctl.d/70-caddy-ha.conf
    readlink /etc/caddy/current
    readlink -e /etc/caddy/current
    /usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind
    /usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind
    dpkg --audit
}

validate_stage() {
    local checksum expected_hash expected_mode relative_path
    local -a actual_files=()

    [[ -d "$retained_stage" && ! -L "$retained_stage" ]]
    [[ "$(stat -c '%U:%G:%a' "$retained_stage")" == root:root:750 ]]
    [[ "$(stat -c '%i' "$retained_stage")" == "$expected_stage_inode" ]]
    [[ "$(stat -c '%d' "$retained_stage")" == "$expected_stage_device" ]]
    if find "$retained_stage" -type l -print -quit | grep -q .; then
        return 1
    fi
    mapfile -t actual_files < <(
        find "$retained_stage" -mindepth 1 -maxdepth 1 -type f \
            -printf '%f\n' |
            sort
    )
    [[ "${actual_files[*]}" == "${expected_stage_files[*]}" ]]

    for checksum in "${expected_stage_checksums[@]}"; do
        expected_hash=${checksum%% *}
        relative_path=${checksum#*  }
        [[ -f "$retained_stage/$relative_path" &&
            ! -L "$retained_stage/$relative_path" ]]
        [[ "$(sha256sum "$retained_stage/$relative_path" |
            awk '{ print $1 }')" == "$expected_hash" ]]
        case "$relative_path" in
            *.sh | caddy-sync-rsync-receiver)
                expected_mode=750
                ;;
            *)
                expected_mode=640
                ;;
        esac
        [[ "$(stat -c '%U:%G:%a' "$retained_stage/$relative_path")" == "root:root:$expected_mode" ]]
    done

    [[ "$(ssh-keygen -lf "$retained_stage/node-b-host-ed25519.pub" \
        -E sha256 | awk '{ print $2 }')" == "$expected_node_b_host_fingerprint" ]]
    [[ "$(ssh-keygen -lf "$retained_stage/node-b-sync-ed25519.pub" \
        -E sha256 | awk '{ print $2 }')" == "$expected_node_b_sync_fingerprint" ]]
    [[ "$(wc -l <"$retained_stage/node-b-host-ed25519.pub")" -eq 1 ]]
    [[ "$(wc -l <"$retained_stage/node-b-sync-ed25519.pub")" -eq 1 ]]
    [[ "$(<"$retained_stage/node-b-host-ed25519.pub")" == ssh-ed25519\ * ]]
    [[ "$(<"$retained_stage/node-b-sync-ed25519.pub")" == ssh-ed25519\ * ]]
}

validate_accepted_state() {
    local service

    [[ "$(id -u)" -eq 0 ]]
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
    [[ "$(stat -c '%U:%G:%a' "$ssh_dir")" == caddy-sync:caddy-sync:700 ]]
    [[ "$(sha256sum /etc/default/caddy-ha |
        awk '{ print $1 }')" == "$environment_sha256" ]]
    grep -Fxq 'NODE_ROLE=node-a' /etc/default/caddy-ha
    grep -Fxq 'PEER_IPV4=10.1.0.54' /etc/default/caddy-ha
    grep -Fxq 'PEER_IPV6=fd36:5aa8:6971:1::54' /etc/default/caddy-ha
    grep -Fxq 'SYNC_TARGET=pihole00.local.theama.co' /etc/default/caddy-ha
    [[ "$(readlink /etc/caddy/current)" == /etc/caddy/releases/bootstrap ]]
    [[ "$(readlink -e /etc/caddy/current)" == /etc/caddy/releases/bootstrap ]]
    [[ "$(tree_hash /etc/lighttpd)" == "$live_lighttpd_sha256" ]]
    [[ "$(tree_hash /var/tmp/caddy-ha-lighttpd-node-a-action16ab)" == "$candidate_lighttpd_sha256" ]]
    [[ "$(sha256sum /etc/keepalived/keepalived.conf |
        awk '{ print $1 }')" == "$keepalived_sha256" ]]
    [[ "$(sha256sum /etc/sysctl.d/70-caddy-ha.conf |
        awk '{ print $1 }')" == "$sysctl_sha256" ]]
    [[ "$(/usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind)" == 1 ]]
    [[ "$(/usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind)" == 1 ]]
    [[ -z "$(dpkg --audit)" ]]
    [[ "$(dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        sort |
        sha256sum |
        awk '{ print $1 }')" == "$package_inventory_sha256" ]]

    [[ "$(systemctl is-active caddy.service 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled caddy.service 2>/dev/null || true)" == masked ]]
    [[ "$(systemctl is-active lsyncd.service 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" == masked ]]
    for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
        systemctl is-active --quiet "$service"
    done
    if pgrep -x caddy >/dev/null || pgrep -x lsyncd >/dev/null; then
        return 1
    fi

    validate_stage
}

validate_targets_absent() {
    local target

    for target in "${live_targets[@]}"; do
        [[ ! -e "$target" && ! -L "$target" ]]
    done
}

validate_libexec_prestate() {
    if [[ -e "$libexec" || -L "$libexec" ]]; then
        [[ -d "$libexec" && ! -L "$libexec" ]]
        [[ "$(stat -c '%U:%G:%a' "$libexec")" == root:root:755 ]]
    fi
}

validate_installed_state() {
    local derived_public recorded_public
    local node_b_host_key node_b_sync_key expected_authorization

    validate_stage
    [[ -d "$libexec" && ! -L "$libexec" ]]
    [[ "$(stat -c '%U:%G:%a' "$libexec")" == root:root:755 ]]
    [[ "$(stat -c '%U:%G:%a' "$receiver")" == root:root:755 ]]
    [[ "$(stat -c '%U:%G:%a' "$setup_helper")" == root:root:755 ]]
    [[ "$(stat -c '%U:%G:%a' "$validator")" == root:root:755 ]]
    [[ "$(sha256sum "$receiver" | awk '{ print $1 }')" == 65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134 ]]
    [[ "$(sha256sum "$setup_helper" | awk '{ print $1 }')" == d1d1e4fd0fd3787e43d7801babfbcdec20015b6517282cdba67904aa1b554140 ]]
    [[ "$(sha256sum "$validator" | awk '{ print $1 }')" == 85df8a934c8dd9561a6f567f42549ebc01ee2605ca630150265004b9ec108072 ]]

    [[ "$(stat -c '%U:%G:%a' "$ssh_dir")" == caddy-sync:caddy-sync:700 ]]
    [[ "$(stat -c '%U:%G:%a' "$private_key")" == caddy-sync:caddy-sync:600 ]]
    [[ "$(stat -c '%U:%G:%a' "$public_key")" == caddy-sync:caddy-sync:644 ]]
    [[ "$(stat -c '%U:%G:%a' "$known_hosts")" == caddy-sync:caddy-sync:600 ]]
    [[ "$(stat -c '%U:%G:%a' "$authorized_keys")" == caddy-sync:caddy-sync:600 ]]

    derived_public=$(ssh-keygen -y -f "$private_key" |
        awk '{ print $1, $2 }')
    recorded_public=$(awk '{ print $1, $2 }' "$public_key")
    [[ "$derived_public" == "$recorded_public" ]]
    [[ "$(wc -l <"$public_key")" -eq 1 ]]

    node_b_host_key=$(awk '{ print $1, $2 }' \
        "$retained_stage/node-b-host-ed25519.pub")
    [[ "$(<"$known_hosts")" == "pihole00.local.theama.co $node_b_host_key" ]]
    [[ "$(wc -l <"$known_hosts")" -eq 1 ]]
    ssh-keygen -F pihole00.local.theama.co -f "$known_hosts" >/dev/null

    node_b_sync_key=$(<"$retained_stage/node-b-sync-ed25519.pub")
    expected_authorization="from=\"10.1.0.54,fd36:5aa8:6971:1::54\",restrict,command=\"/usr/local/libexec/caddy-sync-rsync-receiver\" $node_b_sync_key"
    [[ "$(<"$authorized_keys")" == "$expected_authorization" ]]
    [[ "$(wc -l <"$authorized_keys")" -eq 1 ]]
    grep -Fq 'exec /usr/bin/rrsync -wo -no-del /var/lib/caddy-sync/incoming' \
        "$receiver"
    [[ ! -e "$lsyncd_config" && ! -L "$lsyncd_config" ]]

    "$validator" >/dev/null
}

if [[ "${1:-}" == --self-test ]]; then
    [[ "${#expected_stage_files[@]}" -eq 5 ]]
    [[ "${#expected_stage_checksums[@]}" -eq 5 ]]
    [[ "${#live_targets[@]}" -eq 8 ]]
    [[ "$expected_stage_inode" =~ ^[0-9]+$ ]]
    [[ "$expected_stage_device" =~ ^[0-9]+$ ]]
    [[ "$package_inventory_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$retained_stage" == /var/tmp/caddy-sync-ssh-node-a-action16aj-e ]]
    [[ "$expected_node_b_host_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$expected_node_b_sync_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    printf 'action_16ak_sync_ssh_install_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

state_before=
mutation_started=false
libexec_created=false
transaction_complete=false
rollback() {
    local original_rc=$?
    local rollback_failed=false

    trap - EXIT
    if [[ "$transaction_complete" == true ]]; then
        exit "$original_rc"
    fi

    set +e
    printf 'action_16ak_rollback_started=true\n' >&2
    if [[ "$mutation_started" == true ]]; then
        for target in \
            "$authorized_keys" "$known_hosts" "$public_key" "$private_key" \
            "$validator" "$setup_helper" "$receiver"; do
            if [[ -e "$target" || -L "$target" ]]; then
                if [[ -f "$target" || -L "$target" ]]; then
                    rm -f -- "$target" || rollback_failed=true
                else
                    rollback_failed=true
                fi
            fi
        done
        if [[ "$libexec_created" == true ]]; then
            rmdir -- "$libexec" 2>/dev/null || rollback_failed=true
        fi
    fi

    validate_targets_absent || rollback_failed=true
    validate_accepted_state || rollback_failed=true
    if [[ -n "$state_before" &&
        "$(protected_state)" != "$state_before" ]]; then
        rollback_failed=true
    fi

    if [[ "$rollback_failed" == true ]]; then
        printf 'action_16ak_rollback_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 97
    fi
    printf 'action_16ak_rollback_complete=true\n' >&2
    exit "$original_rc"
}

validate_accepted_state
validate_targets_absent
validate_libexec_prestate
state_before=$(protected_state)
readonly state_before
printf 'action_16ak_preflight_complete=true\n'

trap rollback EXIT
mutation_started=true
printf 'action_16ak_mutation_started=true\n'
if [[ ! -d "$libexec" ]]; then
    install -d -o root -g root -m 0755 "$libexec"
    libexec_created=true
fi
install -o root -g root -m 0755 \
    "$retained_stage/caddy-sync-rsync-receiver" "$receiver"
install -o root -g root -m 0755 \
    "$retained_stage/setup-sync-ssh.sh" "$setup_helper"
install -o root -g root -m 0755 \
    "$retained_stage/validate-sync-ssh.sh" "$validator"
printf 'action_16ak_helpers_installed=true\n'

node_b_host_key=$(awk '{ print $1, $2 }' \
    "$retained_stage/node-b-host-ed25519.pub")
printf 'pihole00.local.theama.co %s\n' "$node_b_host_key" >"$known_hosts"
chown caddy-sync:caddy-sync "$known_hosts"
chmod 0600 "$known_hosts"
printf 'action_16ak_known_hosts_installed=true\n'

setup_output=$(
    "$setup_helper" \
        --authorize-peer-key "$retained_stage/node-b-sync-ed25519.pub"
)
printf 'action_16ak_identity_and_authorization_installed=true\n'
validate_installed_state
printf 'action_16ak_initial_validation_complete=true\n'
first_key_hash=$(sha256sum "$private_key" | awk '{ print $1 }')
readonly first_key_hash
first_public_hash=$(sha256sum "$public_key" | awk '{ print $1 }')
readonly first_public_hash
first_known_hosts_hash=$(sha256sum "$known_hosts" | awk '{ print $1 }')
readonly first_known_hosts_hash
first_authorized_keys_hash=$(sha256sum "$authorized_keys" |
    awk '{ print $1 }')
readonly first_authorized_keys_hash

setup_output=$(
    "$setup_helper" \
        --authorize-peer-key "$retained_stage/node-b-sync-ed25519.pub"
)
readonly setup_output
validate_installed_state
[[ "$(sha256sum "$private_key" | awk '{ print $1 }')" == "$first_key_hash" ]]
[[ "$(sha256sum "$public_key" | awk '{ print $1 }')" == "$first_public_hash" ]]
[[ "$(sha256sum "$known_hosts" | awk '{ print $1 }')" == "$first_known_hosts_hash" ]]
[[ "$(sha256sum "$authorized_keys" | awk '{ print $1 }')" == "$first_authorized_keys_hash" ]]
[[ "$setup_output" == *'Public key for peer authorization:'* ]]
[[ "$(protected_state)" == "$state_before" ]]
printf 'action_16ak_repeat_validation_complete=true\n'

printf 'node_a_sync_ed25519_fingerprint=%s\n' \
    "$(ssh-keygen -lf "$public_key" -E sha256 | awk '{ print $2 }')"
printf 'node_a_sync_ed25519_public_key=%s\n' "$(<"$public_key")"
printf 'node_b_host_ed25519_fingerprint=%s\n' \
    "$expected_node_b_host_fingerprint"
printf 'node_b_sync_ed25519_fingerprint=%s\n' \
    "$expected_node_b_sync_fingerprint"
printf 'restricted_authorization_count=1\n'
printf 'non_connecting_validation=true\n'
printf 'idempotency_validation=true\n'
printf 'retained_stage_preserved=true\n'
printf 'lsyncd_configuration_installed=false\n'
printf 'service_mutations=false\n'
printf 'action_16ak_sync_ssh_install_complete=true\n'
transaction_complete=true
