#!/usr/bin/env bash
set -euo pipefail

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
        -h | --help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$node_role" || -z "$output_dir" ]]; then
    usage >&2
    exit 2
fi

case "$node_role" in
    node-a)
        node_fqdn=pihole0.local.theama.co
        node_ipv4=10.1.0.53
        node_ipv6=fd36:5aa8:6971:1::53
        peer_role=node-b
        peer_fqdn=pihole00.local.theama.co
        peer_ipv4=10.1.0.54
        peer_ipv6=fd36:5aa8:6971:1::54
        caddy_priority=140
        ;;
    node-b)
        node_fqdn=pihole00.local.theama.co
        node_ipv4=10.1.0.54
        node_ipv6=fd36:5aa8:6971:1::54
        peer_role=node-a
        peer_fqdn=pihole0.local.theama.co
        peer_ipv4=10.1.0.53
        peer_ipv6=fd36:5aa8:6971:1::53
        caddy_priority=100
        ;;
    *)
        printf 'Unsupported node role: %s\n' "$node_role" >&2
        exit 2
        ;;
esac

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
caddy_root=$(cd -- "$script_dir/.." && pwd)
manifest_file=${manifest_file:-"$caddy_root/manifests/deployment.yaml"}

if [[ ! -s "$manifest_file" ]]; then
    printf 'Deployment manifest is missing or empty: %s\n' "$manifest_file" >&2
    exit 1
fi
network_interface=$(
    awk '$1 == "interface:" { print $2; exit }' "$manifest_file"
)
if [[ -z "$network_interface" ||
    "$network_interface" == pending_node_preflight ]]; then
    printf 'Deployment manifest requires a validated network interface.\n' >&2
    exit 1
fi
if [[ ! "$network_interface" =~ ^[a-zA-Z0-9_.:-]+$ ]]; then
    printf 'Invalid network interface in deployment manifest.\n' >&2
    exit 1
fi

mkdir -p -- "$output_dir"
chmod 0750 "$output_dir"

render() {
    local source_file=$1
    local destination_file=$2

    sed \
        -e "s|@NODE_ROLE@|$node_role|g" \
        -e "s|@NODE_FQDN@|$node_fqdn|g" \
        -e "s|@NODE_IPV4@|$node_ipv4|g" \
        -e "s|@NODE_IPV6@|$node_ipv6|g" \
        -e "s|@PEER_ROLE@|$peer_role|g" \
        -e "s|@PEER_FQDN@|$peer_fqdn|g" \
        -e "s|@PEER_IPV4@|$peer_ipv4|g" \
        -e "s|@PEER_IPV6@|$peer_ipv6|g" \
        -e "s|@CADDY_PRIORITY@|$caddy_priority|g" \
        -e "s|@NETWORK_INTERFACE@|$network_interface|g" \
        "$source_file" >"$destination_file"
}

render "$caddy_root/templates/caddy-ha.env.in" "$output_dir/caddy-ha.env"
render "$caddy_root/templates/keepalived-caddy-ha.conf.in" \
    "$output_dir/keepalived-caddy-ha.conf"
render "$caddy_root/templates/lsyncd-caddy.lua.in" "$output_dir/lsyncd-caddy.lua"

chmod 0640 "$output_dir/caddy-ha.env"
chmod 0644 \
    "$output_dir/keepalived-caddy-ha.conf" \
    "$output_dir/lsyncd-caddy.lua"

if grep -R -nE '@[A-Z0-9_]+@' "$output_dir"; then
    printf 'Unresolved template placeholder found.\n' >&2
    exit 1
fi

printf 'Rendered configuration for %s in %s\n' "$node_role" "$output_dir"
