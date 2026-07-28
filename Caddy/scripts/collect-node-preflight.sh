#!/usr/bin/env bash
set -uo pipefail

section() {
    printf '\n### %s\n' "$1"
}

run() {
    local label=$1
    shift
    printf '\n--- %s\n' "$label"
    "$@"
    local status=$?
    printf '[exit_status=%s]\n' "$status"
    return 0
}

section identity
run utc-date date --utc --iso-8601=seconds
run hostname hostname
run hostname-fqdn hostname --fqdn
run hostnamectl hostnamectl
run kernel uname -a
run architecture dpkg --print-architecture
run os-release sed -n \
    -e '/^PRETTY_NAME=/p' \
    -e '/^VERSION_ID=/p' \
    -e '/^VERSION_CODENAME=/p' \
    /etc/os-release
run uptime uptime

section hardware
run cpu lscpu
run memory free --bytes
run filesystems df --output=source,fstype,size,used,avail,pcent,target

section network
run links ip -details -brief link show
run ipv4-addresses ip -4 -brief address show
run ipv6-addresses ip -6 -brief address show
run ipv4-routes ip -4 route show table all
run ipv6-routes ip -6 route show table all
run local-bind-sysctls sysctl \
    net.ipv4.ip_nonlocal_bind \
    net.ipv6.ip_nonlocal_bind \
    net.ipv6.conf.all.disable_ipv6
run listeners ss --no-header --listening --numeric --tcp --udp --processes

section packages
# shellcheck disable=SC2016
run package-versions dpkg-query -W \
    '-f=${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' \
    caddy \
    keepalived \
    lighttpd \
    lsyncd \
    munin-node \
    openssh-client \
    openssh-server \
    pihole-FTL \
    rsync \
    unbound

section services
for unit in \
    caddy.service \
    keepalived.service \
    lighttpd.service \
    munin-node.service \
    ssh.service \
    unbound.service; do
    run "$unit-active" systemctl is-active "$unit"
    run "$unit-enabled" systemctl is-enabled "$unit"
    run "$unit-properties" systemctl show "$unit" \
        --property=LoadState \
        --property=ActiveState \
        --property=SubState \
        --property=FragmentPath \
        --property=DropInPaths \
        --property=ExecStart \
        --property=MainPID
done

section identities
run caddy-user getent passwd caddy
run caddy-sync-user getent passwd caddy-sync
run keepalived-script-user getent passwd keepalived_script
run caddy-tls-group getent group caddy-tls

section keepalived
run keepalived-file-metadata find /etc/keepalived \
    -xdev -type f \
    -printf '%M %u:%g %s %TY-%Tm-%TdT%TH:%TM:%TS %p\n'
run keepalived-file-hashes find /etc/keepalived \
    -xdev -type f -exec sha256sum -- {} +
run keepalived-ha-directives grep -R -nE \
    '^[[:space:]]*(global_defs|enable_script_security|script_user|include|vrrp_instance|vrrp_sync_group|virtual_router_id|interface|unicast_src_ip|unicast_peer|virtual_ipaddress)' \
    /etc/keepalived

section lighttpd
run lighttpd-file-metadata find /etc/lighttpd \
    -xdev -type f \
    -printf '%M %u:%g %s %TY-%Tm-%TdT%TH:%TM:%TS %p\n'
run lighttpd-file-hashes find /etc/lighttpd \
    -xdev -type f -exec sha256sum -- {} +
run lighttpd-enabled-links find /etc/lighttpd/conf-enabled \
    -maxdepth 1 -type l -printf '%f -> %l\n'
# shellcheck disable=SC2016
run lighttpd-relevant-directives grep -R -nE \
    '^[[:space:]]*(server\.(bind|port|modules|errorlog)|accesslog\.filename|ssl\.engine|include|include_shell|\$SERVER\["socket"\])' \
    /etc/lighttpd
run lighttpd-config-test lighttpd -tt -f /etc/lighttpd/lighttpd.conf

section unbound-and-pihole
run unbound-file-metadata find /etc/unbound \
    -xdev -type f \
    -printf '%M %u:%g %s %TY-%Tm-%TdT%TH:%TM:%TS %p\n'
run unbound-file-hashes find /etc/unbound \
    -xdev -type f -exec sha256sum -- {} +
run pihole-config-metadata find /etc/pihole \
    -xdev -maxdepth 2 -type f \
    -printf '%M %u:%g %s %TY-%Tm-%TdT%TH:%TM:%TS %p\n'

section journald
run journal-disk-usage journalctl --disk-usage
run journald-effective-config systemd-analyze cat-config systemd/journald.conf

section host-firewall
run nftables-service-active systemctl is-active nftables.service
run nftables-tables nft list tables

section caddy-target-paths
for path in \
    /etc/caddy \
    /etc/default/caddy-ha \
    /etc/lsyncd/caddy.lua \
    /etc/sysctl.d/70-caddy-ha.conf \
    /var/lib/caddy-sync; do
    run "target-$path" stat --format='%A %U:%G %s %n' "$path"
done

section complete
printf 'node_preflight_complete=true\n'
