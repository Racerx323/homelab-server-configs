#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s --source DIRECTORY --node-role node-a|node-b [--emergency]\n' \
        "${0##*/}"
}

source_dir=
node_role=
emergency=false

while (($#)); do
    case "$1" in
        --source)
            source_dir=${2:-}
            shift 2
            ;;
        --node-role)
            node_role=${2:-}
            shift 2
            ;;
        --emergency)
            emergency=true
            shift
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

if [[ ! -d "$source_dir" || ! "$node_role" =~ ^node-[ab]$ ]]; then
    usage >&2
    exit 2
fi

if [[ -r /etc/default/caddy-ha ]]; then
    set -a
    # shellcheck disable=SC1091
    source /etc/default/caddy-ha
    set +a
fi

if [[ "$node_role" == node-b ]]; then
    if [[ "$emergency" != true ]]; then
        printf 'Node B publishing requires --emergency.\n' >&2
        exit 1
    fi
    if [[ ! -r /run/caddy-ha/vrrp-state ]] ||
        [[ "$(</run/caddy-ha/vrrp-state)" != MASTER ]]; then
        printf 'Node B may publish only while CADDY_DUALSTACK is MASTER.\n' >&2
        exit 1
    fi
fi

for required_path in Caddyfile conf.d tls/fullchain.pem tls/privkey.pem; do
    if [[ ! -e "$source_dir/$required_path" ]]; then
        printf 'Incomplete release: missing %s\n' "$required_path" >&2
        exit 1
    fi
done

CADDY_CONFIG_ROOT="$source_dir" \
    caddy validate --config "$source_dir/Caddyfile" --adapter caddyfile >/dev/null
openssl x509 -in "$source_dir/tls/fullchain.pem" -noout >/dev/null
openssl pkey -in "$source_dir/tls/privkey.pem" -noout >/dev/null

revision="$(date -u +%Y%m%dT%H%M%SZ)-$(uuidgen)"
parent_revision=
if [[ -r /etc/caddy/current/release-manifest.json ]]; then
    parent_revision=$(
        jq -r '.revision // ""' /etc/caddy/current/release-manifest.json
    )
fi

outbound_root=/var/lib/caddy-sync/outbound
release_dir="$outbound_root/$revision"
install -d -m 0750 "$release_dir"
cp -a -- "$source_dir/." "$release_dir/"

jq -n \
    --arg revision "$revision" \
    --arg parent_revision "$parent_revision" \
    --arg source_node "$node_role" \
    --arg created_at "$(date --iso-8601=seconds)" \
    '{
        revision: $revision,
        parent_revision: $parent_revision,
        source_node: $source_node,
        created_at: $created_at
    }' >"$release_dir/release-manifest.json"

manifest_temp=$(mktemp "${TMPDIR:-/tmp}/caddy-manifest.XXXXXX")
trap 'rm -f -- "$manifest_temp"' EXIT
(
    cd "$release_dir"
    find . -type f \
        ! -name manifest.sha256 \
        ! -name .complete \
        -print0 |
        sort -z |
        xargs -0 sha256sum
) >"$manifest_temp"
mv -- "$manifest_temp" "$release_dir/manifest.sha256"
trap - EXIT

touch "$release_dir/.complete"
chown -R root:caddy-sync "$release_dir"
find "$release_dir" -type d -exec chmod 0550 {} +
find "$release_dir" -type f -exec chmod 0440 {} +

local_incoming_root="/var/lib/caddy-sync/incoming/$node_role"
local_staging="$local_incoming_root/.$revision.staging"
install -d -o caddy-sync -g caddy-sync -m 0750 "$local_incoming_root"
cp -a -- "$release_dir" "$local_staging"
mv -- "$local_staging" "$local_incoming_root/$revision"
printf 'Published release %s\n' "$revision"
