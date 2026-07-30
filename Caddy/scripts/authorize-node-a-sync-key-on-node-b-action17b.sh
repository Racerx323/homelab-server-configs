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
readonly lsyncd_unit=/etc/systemd/system/caddy-lsyncd.service
readonly lsyncd_config=/etc/lsyncd/caddy.lua
readonly accepted_caddy_release=/etc/caddy/releases/action15-health-follow-redirects
readonly receiver_sha256=65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134
readonly setup_helper_sha256=d1d1e4fd0fd3787e43d7801babfbcdec20015b6517282cdba67904aa1b554140
readonly validator_sha256=85df8a934c8dd9561a6f567f42549ebc01ee2605ca630150265004b9ec108072
readonly lsyncd_unit_sha256=93cbc36cea03b8b7e1605c44667463592cf64e0293ded9f816d1e34760a69ac8
readonly node_a_sync_fingerprint='SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0'
readonly node_b_sync_fingerprint='SHA256:ykJmrl499fd2qRm9bYjgyrgeiTCA1rzTelBBKX0gy5g'
readonly node_a_host_fingerprint='SHA256:tuPVPiBenlqqCDmfqEFfQMpM0q90zj94QMGlNZNC1QI'
readonly node_a_public_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG3MEgLhf8tsImyjkCZpQU4H7X8Xdac+iOUCxRTMM0tA caddy-ha-sync'
readonly expected_authorization="from=\"10.1.0.53,fd36:5aa8:6971:1::53\",restrict,command=\"/usr/local/libexec/caddy-sync-rsync-receiver\" $node_a_public_key"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

known_host_fingerprint() {
    ssh-keygen -F pihole0.local.theama.co -f "$known_hosts" |
        sed '/^#/d' |
        ssh-keygen -lf - -E sha256 |
        awk 'NR == 1 { print $2 }'
}

protected_state() {
    stat -c '%n|%U:%G:%a:%s:%i' \
        /var/lib/caddy-sync \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/quarantine \
        "$ssh_dir" \
        "$private_key" \
        "$public_key" \
        "$known_hosts" \
        "$receiver" \
        "$setup_helper" \
        "$validator" \
        "$lsyncd_unit" \
        /etc/default/caddy-ha
    sha256sum \
        "$private_key" \
        "$public_key" \
        "$known_hosts" \
        "$receiver" \
        "$setup_helper" \
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
    if [[ -e "$lsyncd_config" || -L "$lsyncd_config" ]]; then
        printf 'lsyncd_config=present\n'
    else
        printf 'lsyncd_config=absent\n'
    fi
    dpkg --audit
}

validate_common_state() {
    [[ "$(id -u)" -eq 0 ]]
    [[ "$(hostname)" == j1-svpihole00 ]]
    grep -Fq '10.1.0.54/22' < <(ip -o -4 address show dev eth0)
    [[ "$(dpkg --print-architecture)" == arm64 ]]
    [[ "$(getent passwd caddy-sync | cut -d: -f6)" == /var/lib/caddy-sync ]]
    [[ "$(getent passwd caddy-sync | cut -d: -f7)" == /bin/sh ]]
    [[ "$(passwd --status caddy-sync | awk '{ print $2 }')" == L ]]
    [[ "$(stat -c '%U:%G:%a' "$ssh_dir")" == caddy-sync:caddy-sync:700 ]]
    [[ "$(stat -c '%U:%G:%a' "$private_key")" == caddy-sync:caddy-sync:600 ]]
    [[ "$(stat -c '%U:%G:%a' "$public_key")" == caddy-sync:caddy-sync:644 ]]
    [[ "$(stat -c '%U:%G:%a' "$known_hosts")" == caddy-sync:caddy-sync:600 ]]
    [[ "$(ssh-keygen -lf "$public_key" -E sha256 |
        awk '{ print $2 }')" == "$node_b_sync_fingerprint" ]]
    [[ "$(ssh-keygen -y -f "$private_key" |
        awk '{ print $1, $2 }')" == "$(awk '{ print $1, $2 }' "$public_key")" ]]
    [[ "$(known_host_fingerprint)" == "$node_a_host_fingerprint" ]]
    [[ "$(wc -l <"$known_hosts")" -eq 1 ]]

    [[ "$(stat -c '%U:%G:%a' "$receiver")" == root:root:755 ]]
    [[ "$(file_hash "$receiver")" == "$receiver_sha256" ]]
    [[ "$(stat -c '%U:%G:%a' "$setup_helper")" == root:root:755 ]]
    [[ "$(file_hash "$setup_helper")" == "$setup_helper_sha256" ]]
    [[ "$(stat -c '%U:%G:%a' "$validator")" == root:root:755 ]]
    [[ "$(file_hash "$validator")" == "$validator_sha256" ]]
    [[ "$(stat -c '%U:%G:%a' "$lsyncd_unit")" == root:root:644 ]]
    [[ "$(file_hash "$lsyncd_unit")" == "$lsyncd_unit_sha256" ]]
    grep -Fq \
        'exec /usr/bin/rrsync -wo -no-del /var/lib/caddy-sync/incoming' \
        "$receiver"

    grep -Fxq 'NODE_ROLE=node-b' /etc/default/caddy-ha
    grep -Fxq 'PEER_IPV4=10.1.0.53' /etc/default/caddy-ha
    grep -Fxq 'PEER_IPV6=fd36:5aa8:6971:1::53' /etc/default/caddy-ha
    grep -Fxq 'SYNC_TARGET=pihole0.local.theama.co' \
        /etc/default/caddy-ha
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

validate_authorization_absent() {
    [[ ! -e "$authorized_keys" && ! -L "$authorized_keys" ]]
}

validate_authorization_installed() {
    [[ -f "$authorized_keys" && ! -L "$authorized_keys" ]]
    [[ "$(stat -c '%U:%G:%a' "$authorized_keys")" == caddy-sync:caddy-sync:600 ]]
    [[ "$(wc -l <"$authorized_keys")" -eq 1 ]]
    [[ "$(<"$authorized_keys")" == "$expected_authorization" ]]
    authorization_key=$(
        awk '{ print $(NF-2), $(NF-1), $NF }' "$authorized_keys"
    )
    [[ "$(ssh-keygen -lf <(printf '%s\n' "$authorization_key") \
        -E sha256 | awk '{ print $2 }')" == "$node_a_sync_fingerprint" ]]
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for value in \
        "$receiver_sha256" \
        "$setup_helper_sha256" \
        "$validator_sha256" \
        "$lsyncd_unit_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    [[ "$node_a_sync_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$node_b_sync_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$expected_authorization" == "from=\"10.1.0.53,fd36:5aa8:6971:1::53\",restrict,command=\"/usr/local/libexec/caddy-sync-rsync-receiver\" $node_a_public_key" ]]
    printf 'action_17b_authorization_driver_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

state_before=
authorization_stage=
mutation_started=false
transaction_complete=false

cleanup_authorization_stage() {
    if [[ -n "$authorization_stage" &&
        (-e "$authorization_stage" || -L "$authorization_stage") ]]; then
        if [[ -f "$authorization_stage" && ! -L "$authorization_stage" ]]; then
            rm -f -- "$authorization_stage"
        else
            return 1
        fi
    fi
}

rollback() {
    local original_rc=$?
    local rollback_failed=false

    trap - EXIT
    if [[ "$transaction_complete" == true ]]; then
        exit "$original_rc"
    fi

    set +e
    printf 'action_17b_rollback_started=true\n' >&2
    cleanup_authorization_stage || rollback_failed=true
    if [[ "$mutation_started" == true &&
        (-e "$authorized_keys" || -L "$authorized_keys") ]]; then
        if [[ -f "$authorized_keys" && ! -L "$authorized_keys" ]]; then
            rm -f -- "$authorized_keys" || rollback_failed=true
        else
            rollback_failed=true
        fi
    fi
    validate_common_state || rollback_failed=true
    validate_authorization_absent || rollback_failed=true
    if [[ -n "$state_before" &&
        "$(protected_state)" != "$state_before" ]]; then
        rollback_failed=true
    fi

    if [[ "$rollback_failed" == true ]]; then
        printf 'action_17b_rollback_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 125
    fi
    printf 'action_17b_rollback_complete=true\n' >&2
    exit "$original_rc"
}

validate_common_state
validate_authorization_absent
state_before=$(protected_state)
readonly state_before
printf 'action_17b_preflight_complete=true\n'

trap rollback EXIT
mutation_started=true
printf 'action_17b_mutation_started=true\n'
authorization_stage=$(mktemp /run/caddy-action17b-authorized-keys.XXXXXX)
chmod 0600 "$authorization_stage"
printf '%s\n' "$expected_authorization" >"$authorization_stage"
[[ "$(ssh-keygen -lf <(printf '%s\n' "$node_a_public_key") -E sha256 |
    awk '{ print $2 }')" == "$node_a_sync_fingerprint" ]]
install -o caddy-sync -g caddy-sync -m 0600 \
    "$authorization_stage" "$authorized_keys"
cleanup_authorization_stage
authorization_stage=

validate_authorization_installed
validate_common_state
[[ "$(protected_state)" == "$state_before" ]]
printf 'action_17b_authorization_installed=true\n'
printf 'restricted_authorization_count=1\n'
printf 'node_a_sync_ed25519_fingerprint=%s\n' \
    "$node_a_sync_fingerprint"
printf 'persistent_mutation_scope=authorized_keys_only\n'
printf 'peer_connections=false\n'
printf 'synchronization_commands_executed=false\n'
printf 'lsyncd_configuration_installed=false\n'
printf 'service_mutations=false\n'
printf 'protected_state_unchanged=true\n'

transaction_complete=true
trap - EXIT
printf 'action_17b_node_b_authorization_complete=true\n'
