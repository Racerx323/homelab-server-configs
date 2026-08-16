#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s --node node-a|node-b --output DIRECTORY\n' \
        "${0##*/}"
}

node_role=
output_dir=

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
        ;;
    node-b)
        node_fqdn=pihole00.local.theama.co
        node_ipv4=10.1.0.54
        node_ipv6=fd36:5aa8:6971:1::54
        ;;
    *)
        printf 'Unsupported node role: %s\n' "$node_role" >&2
        exit 2
        ;;
esac

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
caddy_root=$(cd -- "$script_dir/.." && pwd)

mkdir -p -- "$output_dir"
chmod 0750 "$output_dir"

render() {
    local source_file=$1
    local destination_file=$2

    sed \
        -e "s|@NODE_FQDN@|$node_fqdn|g" \
        -e "s|@NODE_IPV4@|$node_ipv4|g" \
        -e "s|@NODE_IPV6@|$node_ipv6|g" \
        "$source_file" >"$destination_file"
}

render "$caddy_root/templates/caddy-ha.env-v2.in" "$output_dir/caddy-ha.env"
chmod 0640 "$output_dir/caddy-ha.env"

if grep -R -nE '@[A-Z0-9_]+@' "$output_dir"; then
    printf 'Unresolved template placeholder found.\n' >&2
    exit 1
fi

printf 'Rendered production environment for %s in %s\n' "$node_role" "$output_dir"
