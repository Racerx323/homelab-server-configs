#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s [--dry-run] [--authorize-peer-key FILE]\n' "${0##*/}"
}

dry_run=false
peer_public_key=
while (($#)); do
    case "$1" in
        --dry-run)
            dry_run=true
            shift
            ;;
        --authorize-peer-key)
            peer_public_key=${2:-}
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

key_path=/var/lib/caddy-sync/.ssh/id_ed25519

if [[ "$dry_run" == true ]]; then
    printf 'Would create a node-local Ed25519 key at %s\n' "$key_path"
    if [[ -n "$peer_public_key" ]]; then
        printf 'Would authorize the public key from %s for the configured peer addresses.\n' \
            "$peer_public_key"
    else
        printf 'Would not authorize or contact a peer.\n'
    fi
    exit 0
fi

if ((EUID != 0)); then
    printf 'Root is required.\n' >&2
    exit 1
fi

install -d -o caddy-sync -g caddy-sync -m 0700 "$(dirname "$key_path")"
if [[ ! -f "$key_path" ]]; then
    runuser -u caddy-sync -- \
        ssh-keygen -q -t ed25519 -N '' -C caddy-ha-sync -f "$key_path"
fi
chmod 0600 "$key_path"
chmod 0644 "$key_path.pub"

if [[ -n "$peer_public_key" ]]; then
    if [[ ! -s "$peer_public_key" ]]; then
        printf 'Peer public key is missing or empty: %s\n' \
            "$peer_public_key" >&2
        exit 1
    fi
    ssh-keygen -l -f "$peer_public_key" >/dev/null
    if [[ "$(wc -l <"$peer_public_key")" -ne 1 ]] ||
        [[ "$(<"$peer_public_key")" != ssh-ed25519\ * ]]; then
        printf 'Peer public key must contain exactly one Ed25519 key.\n' >&2
        exit 1
    fi
    set -a
    # shellcheck disable=SC1091
    source /etc/default/caddy-ha
    set +a
    authorized_keys=/var/lib/caddy-sync/.ssh/authorized_keys
    public_key=$(<"$peer_public_key")
    authorization="from=\"$PEER_IPV4,$PEER_IPV6\",restrict,command=\"/usr/local/libexec/caddy-sync-rsync-receiver\" $public_key"
    touch "$authorized_keys"
    if ! grep -Fxq "$authorization" "$authorized_keys"; then
        printf '%s\n' "$authorization" >>"$authorized_keys"
    fi
    chown caddy-sync:caddy-sync "$authorized_keys"
    chmod 0600 "$authorized_keys"
fi

printf 'Public key for peer authorization:\n'
cat "$key_path.pub"
