#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

usage() {
    printf 'Usage: %s --source DIRECTORY --node-role node-a|node-b [--emergency]\n' \
        "${0##*/}" >&2
}

require_check() {
    local check_label=$1

    shift
    if "$@"; then
        return 0
    fi
    printf 'caddy_sync_publish_v2_check_%s=false\n' "$check_label" >&2
    return 1
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
            usage
            exit 2
            ;;
    esac
done

if [[ ! -d "$source_dir" || -L "$source_dir" ||
    ! "$node_role" =~ ^node-[ab]$ ]]; then
    usage
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

require_check source_symlinks_absent \
    test -z "$(find "$source_dir" -type l -print -quit)"
require_check source_hardlinks_absent \
    test -z "$(find "$source_dir" -type f -links +1 -print -quit)"
require_check source_control_files_absent \
    test -z "$(find "$source_dir" \
        \( -name .finalize-request -o -name .complete.pending \) \
        -print -quit)"
require_check source_caddy_configuration_valid \
    env CADDY_CONFIG_ROOT="$source_dir" \
    caddy validate --config "$source_dir/Caddyfile" \
    --adapter caddyfile >/dev/null
require_check source_certificate_parse \
    openssl x509 -in "$source_dir/tls/fullchain.pem" -noout
require_check source_private_key_parse \
    openssl pkey -in "$source_dir/tls/privkey.pem" -noout

revision="$(date -u +%Y%m%dT%H%M%SZ)-$(uuidgen)"
readonly revision
parent_revision=
if [[ -r /etc/caddy/current/release-manifest.json ]]; then
    parent_revision=$(
        jq -r '.revision // ""' /etc/caddy/current/release-manifest.json
    )
fi
readonly parent_revision

readonly outbound_root=/var/lib/caddy-sync/outbound
readonly release_dir="$outbound_root/$revision"
install -d -o caddy-sync -g caddy-sync -m 0750 "$outbound_root"
staging_dir=$(mktemp -d "$outbound_root/.publish-v2.XXXXXX")
readonly staging_dir

cleanup_staging() {
    # shellcheck disable=SC2317
    if [[ -d "$staging_dir" ]]; then
        rm -rf -- "$staging_dir"
    fi
}
trap cleanup_staging EXIT

require_check release_absent_before test ! -e "$release_dir"
cp -a -- "$source_dir/." "$staging_dir/"
rm -f -- \
    "$staging_dir/.complete" \
    "$staging_dir/.complete.pending" \
    "$staging_dir/.finalize-request" \
    "$staging_dir/manifest.sha256" \
    "$staging_dir/release-manifest.json"

jq -n \
    --arg release_revision "$revision" \
    --arg release_parent "$parent_revision" \
    --arg release_source "$node_role" \
    --arg release_created_at "$(date --iso-8601=seconds)" \
    '{
        revision: $release_revision,
        parent_revision: $release_parent,
        source_node: $release_source,
        created_at: $release_created_at
    }' >"$staging_dir/release-manifest.json"

(
    cd "$staging_dir"
    find . -type f \
        ! -path ./manifest.sha256 \
        ! -path ./.finalize-request \
        ! -path ./.complete \
        ! -path ./.complete.pending \
        -print0 |
        LC_ALL=C sort -z |
        xargs -0 sha256sum
) >"$staging_dir/manifest.sha256"

: >"$staging_dir/.finalize-request"
chown -R caddy-sync:caddy-sync "$staging_dir"
find "$staging_dir" -type d -exec chmod 0550 {} +
find "$staging_dir" -type f -exec chmod 0440 {} +
require_check staged_directories_locked \
    test -z "$(find "$staging_dir" -type d ! -perm 0550 -print -quit)"
require_check staged_files_locked \
    test -z "$(find "$staging_dir" -type f ! -perm 0440 -print -quit)"
mv -- "$staging_dir" "$release_dir"
trap - EXIT
require_check release_regular_directory test -d "$release_dir"
require_check release_not_symlink test ! -L "$release_dir"
require_check release_request_regular \
    test -f "$release_dir/.finalize-request"
require_check release_completion_absent test ! -e "$release_dir/.complete"

printf 'Published protocol-v2 release %s for receiver validation.\n' "$revision"
