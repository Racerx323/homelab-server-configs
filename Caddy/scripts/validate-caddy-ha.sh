#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s --node node-a|node-b [--root DIRECTORY]\n' "${0##*/}"
}

node_role=
root_prefix=/

while (($#)); do
    case "$1" in
        --node)
            node_role=${2:-}
            shift 2
            ;;
        --root)
            root_prefix=${2:-}
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

if [[ ! "$node_role" =~ ^node-[ab]$ || "$root_prefix" != /* ]]; then
    usage >&2
    exit 2
fi

root_path() {
    if [[ "$root_prefix" == / ]]; then
        printf '%s' "$1"
    else
        printf '%s%s' "${root_prefix%/}" "$1"
    fi
}

required_paths=(
    /etc/default/caddy-ha
    /etc/caddy/current
    /etc/keepalived/conf.d/caddy-ha.conf
    /usr/local/share/caddy-ha/lighttpd-desired-state.conf
    /etc/lsyncd/caddy.lua
    /etc/sysctl.d/70-caddy-ha.conf
)

for required_path in "${required_paths[@]}"; do
    if [[ ! -e "$(root_path "$required_path")" &&
    ! -L "$(root_path "$required_path")" ]]; then
        printf 'Missing installed path: %s\n' "$required_path" >&2
        exit 1
    fi
done

environment_file=$(root_path /etc/default/caddy-ha)
grep -Fxq "NODE_ROLE=$node_role" "$environment_file"

if grep -R -nE '@[A-Z0-9_]+@' \
    "$(root_path /etc/default/caddy-ha)" \
    "$(root_path /etc/keepalived/conf.d/caddy-ha.conf)" \
    "$(root_path /etc/lsyncd/caddy.lua)"; then
    printf 'Unresolved template placeholders found.\n' >&2
    exit 1
fi

if [[ "$root_prefix" == / ]]; then
    set -a
    # shellcheck disable=SC1091
    source /etc/default/caddy-ha
    set +a
    caddy validate \
        --config /etc/caddy/current/Caddyfile \
        --adapter caddyfile >/dev/null
    keepalived --config-test \
        --log-console \
        -f /etc/keepalived/conf.d/caddy-ha.conf >/dev/null
fi

printf 'Validated installed Caddy HA artifacts for %s under %s\n' \
    "$node_role" "$root_prefix"
