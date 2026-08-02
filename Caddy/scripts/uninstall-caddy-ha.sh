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

root_path() {
    if [[ "$root_prefix" == / ]]; then
        printf '%s' "$1"
    else
        printf '%s%s' "${root_prefix%/}" "$1"
    fi
}

paths=(
    /etc/default/caddy-ha
    /etc/keepalived/conf.d/caddy-ha.conf
    /usr/local/share/caddy-ha/lighttpd-desired-state.conf
    /etc/lsyncd/caddy.lua
    /etc/sysctl.d/70-caddy-ha.conf
    /etc/munin/plugin-conf.d/caddy-ha
    /etc/systemd/system/caddy.service.d/override.conf
    /etc/systemd/system/lighttpd.service.d/caddy-ha.conf
    /etc/systemd/system/caddy-lsyncd.service
    /etc/systemd/system/caddy-sync-failure@.service
    /etc/systemd/system/caddy-sync-reconcile.path
    /etc/systemd/system/caddy-sync-reconcile.service
    /etc/systemd/system/caddy-validate-reload.path
    /etc/systemd/system/caddy-validate-reload.service
    /etc/systemd/system/caddy-sync-health.service
    /etc/systemd/system/caddy-sync-health.timer
    /etc/systemd/system/caddy-cert-expiry.service
    /etc/systemd/system/caddy-cert-expiry.timer
)

for executable in \
    caddy-sync-rsync-receiver \
    check-caddy.sh \
    check-certificate-expiry.sh \
    lsyncd-ha-failover-notify.sh \
    lsyncd-sync-failure-notify.sh \
    prepare-lighttpd-config.sh \
    publish-release.sh \
    reconcile-release.sh \
    setup-sync-ssh.sh \
    validate-sync-ssh.sh \
    validate-journald-retention.sh \
    validate-sync-health.sh; do
    paths+=("/usr/local/libexec/$executable")
done

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
