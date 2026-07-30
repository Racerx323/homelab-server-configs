#!/usr/bin/env bash

set -euo pipefail
set +x
umask 027

usage() {
    printf 'Usage: %s --node node-a|node-b --output DIRECTORY [--manifest FILE]\n' \
        "${0##*/}"
}

node_role=
output_dir=
manifest_file=
while (($#)); do
    case "$1" in
        --node)
            node_role=${2:-}
            shift 2
            ;;
        --output)
            output_dir=${2:-}
            shift 2
            ;;
        --manifest)
            manifest_file=${2:-}
            shift 2
            ;;
        --self-test)
            [[ $# -eq 1 ]]
            printf 'action_17c_c_source_bound_renderer_self_test_complete=true\n'
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

[[ "$node_role" == node-a || "$node_role" == node-b ]]
[[ -n "$output_dir" ]]

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly base_renderer="$script_dir/render-node-config.sh"
readonly template="$caddy_root/templates/lsyncd-caddy-source-bound.lua.in"
readonly validator="$script_dir/validate-sync-ssh-source-bound.sh"
manifest_file=${manifest_file:-"$caddy_root/manifests/deployment.yaml"}

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/caddy-action17c-c-render.XXXXXX")
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

"$base_renderer" \
    --node "$node_role" \
    --manifest "$manifest_file" \
    --output "$work_dir/base" >/dev/null

set -a
# shellcheck disable=SC1091
source "$work_dir/base/caddy-ha.env"
set +a
PEER_FQDN=$SYNC_TARGET
readonly PEER_FQDN

# Values are assigned by the rendered, sourced environment file.
# shellcheck disable=SC2153
[[ "$NODE_ROLE" == "$node_role" ]]
[[ "$NODE_IPV6" == fd36:5aa8:6971:1::53 ||
    "$NODE_IPV6" == fd36:5aa8:6971:1::54 ]]
[[ "$PEER_FQDN" == pihole0.local.theama.co ||
    "$PEER_FQDN" == pihole00.local.theama.co ]]

install -d -m 0750 -- "$output_dir"
sed \
    -e "s|@NODE_ROLE@|$NODE_ROLE|g" \
    -e "s|@NODE_IPV6@|$NODE_IPV6|g" \
    -e "s|@PEER_FQDN@|$PEER_FQDN|g" \
    "$template" >"$output_dir/caddy.lua"
install -m 0755 -- "$validator" "$output_dir/validate-sync-ssh.sh"
chmod 0644 "$output_dir/caddy.lua"

if grep -R -nE '@[A-Z0-9_]+@' "$output_dir"; then
    printf 'Unresolved source-binding placeholder found.\n' >&2
    exit 1
fi
grep -Fxq "            BindAddress = \"$NODE_IPV6\"," \
    "$output_dir/caddy.lua"
grep -Fxq "            HostKeyAlias = \"$PEER_FQDN\"," \
    "$output_dir/caddy.lua"

printf 'Rendered source-bound synchronization artifacts for %s in %s\n' \
    "$node_role" "$output_dir"
