#!/usr/bin/env bash

set -euo pipefail

usage() {
    printf 'Usage: %s --node node-a|node-b\n' "${0##*/}" >&2
}

node_role=
while (($# > 0)); do
    case "$1" in
        --node)
            node_role=${2:-}
            shift 2
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

case "$node_role" in
    node-a)
        expected_hostname=j1-svpihole0
        expected_ipv4=10.1.0.53
        ;;
    node-b)
        expected_hostname=j1-svpihole00
        expected_ipv4=10.1.0.54
        ;;
    *)
        usage
        exit 2
        ;;
esac

((EUID == 0)) || {
    printf 'Root is required to create a complete rollback backup.\n' >&2
    exit 1
}

[[ "$(hostname)" == "$expected_hostname" ]] || {
    printf 'Refusing backup on unexpected hostname: %s\n' "$(hostname)" >&2
    exit 1
}

ip -o -4 address show dev eth0 |
    grep -Fq "$expected_ipv4/22" || {
    printf 'Refusing backup: %s address is not present on eth0.\n' \
        "$node_role" >&2
    exit 1
}

umask 077
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_parent=/var/backups/caddy-ha
backup_root="$backup_parent/predeploy-$node_role-$timestamp"
install -d -o root -g root -m 0700 "$backup_parent"
stage=$(mktemp -d "$backup_parent/.predeploy-$node_role-$timestamp.XXXXXX")
cleanup_stage=true

cleanup() {
    if [[ "$cleanup_stage" == true && -d "$stage" ]]; then
        rm -rf -- "$stage"
    fi
}
trap cleanup EXIT

candidate_paths=(
    /etc/caddy
    /etc/default/caddy-ha
    /etc/keepalived
    /etc/lighttpd
    /etc/lsyncd/caddy.lua
    /etc/munin/plugin-conf.d/caddy-ha
    /etc/sysctl.d/70-caddy-ha.conf
    /etc/systemd/system/caddy.service.d/override.conf
    /etc/systemd/system/caddy-cert-expiry.service
    /etc/systemd/system/caddy-cert-expiry.timer
    /etc/systemd/system/caddy-lsyncd.service
    /etc/systemd/system/caddy-sync-failure@.service
    /etc/systemd/system/caddy-sync-health.service
    /etc/systemd/system/caddy-sync-health.timer
    /etc/systemd/system/caddy-sync-reconcile.path
    /etc/systemd/system/caddy-sync-reconcile.service
    /etc/systemd/system/caddy-validate-reload.path
    /etc/systemd/system/caddy-validate-reload.service
    /etc/systemd/system/lighttpd.service.d/caddy-ha.conf
    /usr/local/libexec/caddy-sync-rsync-receiver
    /usr/local/libexec/check-caddy.sh
    /usr/local/libexec/check-certificate-expiry.sh
    /usr/local/libexec/lsyncd-ha-failover-notify.sh
    /usr/local/libexec/lsyncd-sync-failure-notify.sh
    /usr/local/libexec/prepare-lighttpd-config.sh
    /usr/local/libexec/publish-release.sh
    /usr/local/libexec/reconcile-release.sh
    /usr/local/libexec/setup-sync-ssh.sh
    /usr/local/libexec/validate-journald-retention.sh
    /usr/local/libexec/validate-sync-health.sh
    /usr/local/libexec/validate-sync-ssh.sh
    /usr/local/share/caddy-ha
    /var/lib/caddy-sync
)

archive_paths=()
existing_paths=()
: >"$stage/path-state.tsv"
for path in "${candidate_paths[@]}"; do
    if [[ -e "$path" || -L "$path" ]]; then
        printf 'present\t%s\n' "$path" >>"$stage/path-state.tsv"
        archive_paths+=("${path#/}")
        existing_paths+=("$path")
    else
        printf 'absent\t%s\n' "$path" >>"$stage/path-state.tsv"
    fi
done

((${#archive_paths[@]} > 0)) || {
    printf 'No rollback paths were found.\n' >&2
    exit 1
}

tar \
    --create \
    --file "$stage/configuration.tar" \
    --directory / \
    "${archive_paths[@]}"

(
    cd -- "$stage"
    sha256sum configuration.tar >configuration.tar.sha256
    sha256sum --check --status configuration.tar.sha256
    tar --list --file configuration.tar >/dev/null
)

find "${existing_paths[@]}" \
    -xdev -type f -print0 2>/dev/null |
    sort -z |
    xargs -0 -r sha256sum >"$stage/configuration-files.sha256"

dpkg-query -W \
    -f='${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' \
    >"$stage/packages.tsv"
apt-mark showmanual | sort >"$stage/apt-manual.txt"
systemctl list-unit-files --no-pager >"$stage/systemd-unit-files.txt"

for service in \
    keepalived.service lighttpd.service munin-node.service ssh.service \
    unbound.service caddy.service; do
    {
        printf '### %s\n' "$service"
        systemctl show "$service" \
            -p LoadState -p ActiveState -p SubState -p UnitFileState \
            -p FragmentPath -p DropInPaths
    } >>"$stage/service-state.txt"
done

sysctl \
    net.ipv4.ip_nonlocal_bind \
    net.ipv6.ip_nonlocal_bind \
    net.ipv6.conf.all.disable_ipv6 \
    >"$stage/sysctl-state.txt"
ip -details -4 address show >"$stage/ip-addresses-v4.txt"
ip -details -6 address show >"$stage/ip-addresses-v6.txt"
ip -4 route show table all >"$stage/ip-routes-v4.txt"
ip -6 route show table all >"$stage/ip-routes-v6.txt"
ss -H -lntup >"$stage/listeners.txt"

{
    printf 'created_utc=%s\n' "$timestamp"
    printf 'node_role=%s\n' "$node_role"
    printf 'hostname=%s\n' "$(hostname)"
    printf 'backup_complete=true\n'
} >"$stage/backup-manifest.txt"

chmod -R go-rwx "$stage"
mv -- "$stage" "$backup_root"
cleanup_stage=false

(
    cd -- "$backup_root"
    sha256sum --check --status configuration.tar.sha256
    grep -Fxq 'backup_complete=true' backup-manifest.txt
)

printf 'backup_root=%s\n' "$backup_root"
printf 'backup_complete=true\n'
