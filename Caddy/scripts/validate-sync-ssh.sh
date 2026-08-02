#!/usr/bin/env bash
set -euo pipefail

connect=false
if (($#)); then
    if [[ "$1" == --connect && $# -eq 1 ]]; then
        connect=true
    else
        printf 'Usage: %s [--connect]\n' "${0##*/}" >&2
        exit 2
    fi
fi

set -a
# shellcheck disable=SC1091
source /etc/default/caddy-ha
set +a

readonly ssh_dir=/var/lib/caddy-sync/.ssh
readonly private_key="$ssh_dir/id_ed25519"
readonly known_hosts="$ssh_dir/known_hosts"

[[ -s "$private_key" && -s "$private_key.pub" && -s "$known_hosts" ]]
[[ "$(stat -c %a "$ssh_dir")" == 700 ]]
[[ "$(stat -c %a "$private_key")" == 600 ]]
ssh-keygen -F "$SYNC_TARGET" -f "$known_hosts" >/dev/null

ssh -G \
    -F /dev/null \
    -i "$private_key" \
    -o BatchMode=yes \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=yes \
    -o "UserKnownHostsFile=$known_hosts" \
    "caddy-sync@$SYNC_TARGET" >/dev/null

if [[ "$connect" == true ]]; then
    empty_dir=$(mktemp -d "${TMPDIR:-/tmp}/caddy-sync-probe.XXXXXX")
    trap 'rm -rf -- "$empty_dir"' EXIT
    rsync \
        --archive \
        --dry-run \
        --rsh="ssh -F /dev/null -i $private_key -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts" \
        "$empty_dir/" \
        "caddy-sync@$SYNC_TARGET:/$NODE_ROLE/"
fi

printf 'Restricted synchronization SSH validation passed for %s.\n' \
    "$SYNC_TARGET"
