#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s --node node-a|node-b [--root DIRECTORY] [--dry-run] [--preserve-releases]\n' \
        "${0##*/}"
}

node_role=
root_prefix=/
dry_run=false
preserve_releases=false

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
        --dry-run)
            dry_run=true
            shift
            ;;
        --preserve-releases)
            preserve_releases=true
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

if [[ ! "$node_role" =~ ^node-[ab]$ || "$root_prefix" != /* ]]; then
    usage >&2
    exit 2
fi
if [[ "$root_prefix" == / && "$dry_run" == false && "$EUID" -ne 0 ]]; then
    printf 'Root is required for live filesystem removal.\n' >&2
    exit 1
fi

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly script_directory caddy_root

root_path() {
    local uninstall_path=$1

    if [[ "$root_prefix" == / ]]; then
        printf '%s' "$uninstall_path"
    else
        printf '%s%s' "${root_prefix%/}" "$uninstall_path"
    fi
}

paths=(
    /etc/default/caddy-ha
    /usr/local/share/caddy-ha/lighttpd-desired-state.conf
    /etc/lsyncd/caddy.lua
    /etc/sysctl.d/70-caddy-ha.conf
    /etc/tmpfiles.d/caddy-ha.conf
)

append_registered_paths() {
    local uninstall_registry=$1
    local uninstall_source
    local uninstall_lifecycle
    local uninstall_deployable
    local uninstall_target
    local uninstall_mode
    local uninstall_authority

    while IFS=$'\t' read -r uninstall_source uninstall_lifecycle \
        uninstall_deployable uninstall_target uninstall_mode \
        uninstall_authority; do
        [[ -n "$uninstall_source" && "$uninstall_source" != \#* ]] || continue
        : "$uninstall_mode" "$uninstall_authority"
        [[ "$uninstall_lifecycle" == production-current &&
            "$uninstall_deployable" == yes ]] || continue
        paths+=("$uninstall_target")
    done <"$uninstall_registry"
}

append_registered_paths "$caddy_root/manifests/script-lifecycle.tsv"
append_registered_paths "$caddy_root/manifests/systemd-lifecycle.tsv"

# Remove known obsolete Caddy-owned remnants, but never externally owned
# Keepalived state or deferred Munin configuration.
paths+=(
    /etc/systemd/system/caddy-pihole-backend.service
    /usr/local/libexec/caddy-sync-rsync-receiver
    /usr/local/libexec/lsyncd-ha-failover-notify.sh
    /usr/local/libexec/publish-release.sh
)

if [[ "$preserve_releases" == false ]]; then
    paths+=(/etc/caddy/current /etc/caddy/releases/bootstrap)
fi

changes=0
for path in "${paths[@]}"; do
    target=$(root_path "$path")
    if [[ ! -e "$target" && ! -L "$target" ]]; then
        continue
    fi
    changes=$((changes + 1))
    if [[ "$dry_run" == true ]]; then
        printf 'REMOVE %s\n' "$target" >&2
    elif [[ -d "$target" && ! -L "$target" ]]; then
        find "$target" -depth -mindepth 1 -delete
        rmdir "$target"
    else
        rm -- "$target"
    fi
done

jq -n \
    --arg node "$node_role" \
    --arg root "$root_prefix" \
    --argjson dry_run "$dry_run" \
    --argjson preserve_releases "$preserve_releases" \
    --argjson changes "$changes" \
    '{
        node: $node,
        root: $root,
        dry_run: $dry_run,
        preserve_releases: $preserve_releases,
        changes: $changes,
        service_mutations: false
    }'
