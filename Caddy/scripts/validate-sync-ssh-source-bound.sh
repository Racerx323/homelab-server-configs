#!/usr/bin/env bash

set -euo pipefail
set +x

connect=false
if (($#)); then
    case "$1" in
        --connect)
            [[ $# -eq 1 ]]
            connect=true
            ;;
        --self-test)
            [[ $# -eq 1 ]]
            printf 'source_bound_sync_validator_self_test_complete=true\n'
            exit 0
            ;;
        *)
            printf 'Usage: %s [--connect|--self-test]\n' "${0##*/}" >&2
            exit 2
            ;;
    esac
fi

set -a
# shellcheck disable=SC1091
source /etc/default/caddy-ha
set +a

readonly ssh_dir=/var/lib/caddy-sync/.ssh
readonly private_key="$ssh_dir/id_ed25519"
readonly known_hosts="$ssh_dir/known_hosts"

state_payload() {
    stat -c '%n|%U:%G:%a:%s:%i' \
        /var/lib/caddy-sync \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/quarantine \
        "$ssh_dir" \
        "$private_key" \
        "$private_key.pub" \
        "$known_hosts" \
        /etc/default/caddy-ha
    sha256sum \
        "$private_key" \
        "$private_key.pub" \
        "$known_hosts" \
        /etc/default/caddy-ha
    find \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/quarantine \
        -printf '%p|%y|%U:%G:%m:%s:%i\n' |
        sort
    for unit in lsyncd.service caddy-lsyncd.service; do
        systemctl show "$unit" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts
        printf 'unit_file_state=%s\n' \
            "$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    done
}

[[ "$NODE_ROLE" == node-a || "$NODE_ROLE" == node-b ]]
[[ "$NODE_IPV6" == fd36:5aa8:6971:1::53 ||
    "$NODE_IPV6" == fd36:5aa8:6971:1::54 ]]
[[ "$PEER_IPV6" == fd36:5aa8:6971:1::53 ||
    "$PEER_IPV6" == fd36:5aa8:6971:1::54 ]]
[[ "$NODE_IPV6" != "$PEER_IPV6" ]]
[[ "$SYNC_TARGET" == pihole0.local.theama.co ||
    "$SYNC_TARGET" == pihole00.local.theama.co ]]
[[ -s "$private_key" && -s "$private_key.pub" && -s "$known_hosts" ]]
[[ "$(stat -c %a "$ssh_dir")" == 700 ]]
[[ "$(stat -c %a "$private_key")" == 600 ]]
ssh-keygen -F "$SYNC_TARGET" -f "$known_hosts" >/dev/null

ssh -G \
    -6 \
    -F /dev/null \
    -b "$NODE_IPV6" \
    -i "$private_key" \
    -o BatchMode=yes \
    -o ClearAllForwardings=yes \
    -o GlobalKnownHostsFile=/dev/null \
    -o "HostKeyAlias=$SYNC_TARGET" \
    -o IdentitiesOnly=yes \
    -o KbdInteractiveAuthentication=no \
    -o PasswordAuthentication=no \
    -o PreferredAuthentications=publickey \
    -o StrictHostKeyChecking=yes \
    -o UpdateHostKeys=no \
    -o "UserKnownHostsFile=$known_hosts" \
    "caddy-sync@$SYNC_TARGET" >/dev/null
printf 'source_bound_ssh_configuration_valid=true\n'

if [[ "$connect" == true ]]; then
    state_before=$(state_payload | sha256sum | awk '{ print $1 }')
    readonly state_before
    work_dir=$(mktemp -d "${TMPDIR:-/tmp}/caddy-sync-probe.XXXXXX")
    trap 'rm -rf -- "$work_dir"' EXIT
    empty_dir="$work_dir/empty"
    mkdir -m 0700 -- "$empty_dir"
    probe_output="$work_dir/ssh.out"
    probe_error="$work_dir/ssh.err"
    probe_status=0
    ssh \
        -6 \
        -n \
        -T \
        -F /dev/null \
        -b "$NODE_IPV6" \
        -i "$private_key" \
        -o BatchMode=yes \
        -o ClearAllForwardings=yes \
        -o GlobalKnownHostsFile=/dev/null \
        -o "HostKeyAlias=$SYNC_TARGET" \
        -o IdentitiesOnly=yes \
        -o KbdInteractiveAuthentication=no \
        -o PasswordAuthentication=no \
        -o PreferredAuthentications=publickey \
        -o StrictHostKeyChecking=yes \
        -o UpdateHostKeys=no \
        -o "UserKnownHostsFile=$known_hosts" \
        "caddy-sync@$SYNC_TARGET" \
        caddy-source-bound-denied-probe \
        >"$probe_output" 2>"$probe_error" || probe_status=$?
    [[ "$probe_status" -eq 126 ]]
    [[ ! -s "$probe_output" ]]
    [[ "$(<"$probe_error")" == 'Only the rsync server protocol is permitted.' ]]
    printf 'source_bound_direct_ssh_reached_forced_receiver=true\n'

    remote_shell="ssh -6 -F /dev/null -b $NODE_IPV6 -i $private_key"
    remote_shell+=" -o BatchMode=yes -o ClearAllForwardings=yes"
    remote_shell+=" -o GlobalKnownHostsFile=/dev/null"
    remote_shell+=" -o HostKeyAlias=$SYNC_TARGET -o IdentitiesOnly=yes"
    remote_shell+=" -o KbdInteractiveAuthentication=no"
    remote_shell+=" -o PasswordAuthentication=no"
    remote_shell+=" -o PreferredAuthentications=publickey"
    remote_shell+=" -o StrictHostKeyChecking=yes -o UpdateHostKeys=no"
    remote_shell+=" -o UserKnownHostsFile=$known_hosts"
    rsync \
        --archive \
        --dry-run \
        --rsh="$remote_shell" \
        "$empty_dir/" \
        "caddy-sync@$SYNC_TARGET:/$NODE_ROLE/" >/dev/null
    printf 'source_bound_rsync_dry_run=true\n'
    [[ "$(state_payload | sha256sum | awk '{ print $1 }')" == "$state_before" ]]
    printf 'node_relevant_state_unchanged=true\n'
    printf 'release_payload_transferred=false\n'
fi

printf 'Source-bound synchronization SSH validation passed for %s via %s.\n' \
    "$SYNC_TARGET" "$NODE_IPV6"
