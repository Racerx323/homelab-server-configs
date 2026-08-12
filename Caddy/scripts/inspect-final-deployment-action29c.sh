#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_29c_remote
readonly schema_version=action29c-node-snapshot-v2
readonly expected_revision=20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04
readonly expected_source=node-a
readonly expected_payload_sha256=fdc6ed955f14226ac3e1777eca37507cc8ab6ca16add3135dece9d6964e27568
readonly node_a_keepalived_sha256=d8f96c4f018f90370aea38fc3ef932af649158f6edc99cc7e95dea1edff4908a
readonly node_b_keepalived_sha256=034ee9c45acaca4e48e2faeda24cd371e945bdb52a117b5871403958ab36794c
readonly pihole_ftl_target_sha256=a1dc88b1f696a6870e38025be113ff8664750fca6265c79a2aee12f80898cfa3
readonly pihole_domain_target_sha256=39fa219a7d1c81c7fb36d89bc17ba1caae26f3472eb861a750a8ba03ae55b026
readonly action29b_before_ftl_sha256=ac049a0845974bb39186f5b32a76dfe0512ff537e59142bd9d4f648febba8114
readonly action29b_before_domain_sha256=f998ee0e6f9409fbb1e5108e14f982acce4ff8b36fd33f0f0f372e07003dfb01
readonly unbound_zone_sha256=fa9f4850386ab1328f323c7c88bd9fa9ad0d5a84994b3066b6874deb5beb569c
readonly health_helper_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly publisher_sha256=4a1cbeca92babe731528e4901e7164a876ab7d52a668390d311bedc11238b513
readonly reconciler_sha256=1aab5c5029fb028f4832a52ade12a47e2f30a0716903eedab4fc6afded2034b4
readonly finalizer_sha256=fcff15db5b4ea971846a798028f40d2dce86db9cc331825d046dd5321d5f33bd
readonly node_a_lsyncd_sha256=d09a5d74434ed5ec4c48f65f718907c583461f9124e6309b20417c7f748f2365
readonly node_b_lsyncd_sha256=cae04b74475a567e75f4ec4e9e4db305990f45df2c0dede1439f3e945a22c136
readonly lsyncd_unit_sha256=93cbc36cea03b8b7e1605c44667463592cf64e0293ded9f816d1e34760a69ac8
readonly reconcile_path_sha256=c8c11582580326300035c1b6e8dc97cb6b90052683b57836cc3afdcdd436f295
readonly reconcile_service_sha256=848787b77cc03fe3855961cc94ad2e6aa4e05934851a98643edcdf17d84bf8eb
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/100/IPv4
readonly ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/101/IPv6
readonly releases_root=/etc/caddy/releases
readonly current_link=/etc/caddy/current
readonly publisher=/usr/local/libexec/publish-release-v2.sh
readonly reconciler=/usr/local/libexec/reconcile-release.sh
readonly finalizer=/usr/local/libexec/finalize-incoming-release-v2.sh
readonly lsyncd_config=/etc/lsyncd/caddy.lua
readonly lsyncd_unit=/etc/systemd/system/caddy-lsyncd.service
readonly reconcile_path=/etc/systemd/system/caddy-sync-reconcile.path
readonly reconcile_service=/etc/systemd/system/caddy-sync-reconcile.service
readonly pihole_ftl=/etc/pihole/pihole-FTL.conf
readonly pihole_domain=/etc/dnsmasq.d/local.theama.co.conf
readonly unbound_zone=/etc/unbound/unbound.conf.d/pihole-local-zone.conf
readonly health_helper=/usr/local/libexec/check-caddy.sh
readonly maximum_web_body_bytes=1048576

node_token=
expected_hostname=
expected_state=
expected_vip_count=
expected_keepalived_sha256=
expected_lsyncd_sha256=
expected_action29b_backup=
first_failure=none
action29c_remote_versions=
action29c_remote_web_body=

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
valid_sha256() {
    local action29_remote_hash=$1

    [[ ${#action29_remote_hash} -eq 64 ]] || return 1
    [[ "$action29_remote_hash" != *[!0-9a-f]* ]]
}
check() {
    local action29_remote_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_%s_check_%s=true\n' "$prefix" "$node_token" "$action29_remote_label"
        return 0
    fi
    first_failure=$action29_remote_label
    printf '%s_%s_check_%s=false\n' "$prefix" "$node_token" "$action29_remote_label" >&2
    return 1
}
configure_node() {
    case "$1" in
        node-a)
            node_token=node_a
            expected_hostname=j1-svpihole0
            expected_state=Master
            expected_vip_count=1
            expected_keepalived_sha256=$node_a_keepalived_sha256
            expected_lsyncd_sha256=$node_a_lsyncd_sha256
            expected_action29b_backup=/var/backups/caddy-ha/action29b-node-a-pihole-v5-config
            ;;
        node-b)
            node_token=node_b
            expected_hostname=j1-svpihole00
            expected_state=Backup
            expected_vip_count=0
            expected_keepalived_sha256=$node_b_keepalived_sha256
            expected_lsyncd_sha256=$node_b_lsyncd_sha256
            expected_action29b_backup=/var/backups/caddy-ha/action29b-node-b-pihole-v5-config
            ;;
        *) return 64 ;;
    esac
    readonly node_token expected_hostname expected_state expected_vip_count
    readonly expected_keepalived_sha256 expected_lsyncd_sha256 expected_action29b_backup
}
address_count() {
    local action29_remote_family=$1
    local action29_remote_cidr=$2

    ip -o "$action29_remote_family" addr show |
        awk -v expected="$action29_remote_cidr" '$4 == expected { count++ } END { print count + 0 }'
}
dbus_state() {
    busctl get-property org.keepalived.Vrrp1 "$1" org.keepalived.Vrrp1.Instance State |
        awk -F '"' 'NF == 3 { print $2 }'
}
metadata_exact() {
    local action29_remote_path=$1
    local action29_remote_mode=$2

    [[ -f "$action29_remote_path" && ! -L "$action29_remote_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$action29_remote_path")" = "root:root:$action29_remote_mode" ]]
}
metadata_owner_exact() {
    local action29_remote_path=$1
    local action29_remote_owner=$2
    local action29_remote_group=$3
    local action29_remote_mode=$4

    [[ -f "$action29_remote_path" && ! -L "$action29_remote_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$action29_remote_path")" = "$action29_remote_owner:$action29_remote_group:$action29_remote_mode" ]]
}
action29b_backup_valid() {
    local action29c_remote_backup=${1:-$expected_action29b_backup}
    local action29c_remote_owner=${2:-root}
    local action29c_remote_group=${3:-root}
    local action29c_remote_before_ftl=${4:-$action29b_before_ftl_sha256}
    local action29c_remote_before_domain=${5:-$action29b_before_domain_sha256}
    local action29c_remote_expected_manifest

    [[ -d "$action29c_remote_backup" && ! -L "$action29c_remote_backup" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$action29c_remote_backup")" = "$action29c_remote_owner:$action29c_remote_group:700" ]] || return 1
    metadata_owner_exact "$action29c_remote_backup/manifest" \
        "$action29c_remote_owner" "$action29c_remote_group" 600 || return 1
    metadata_owner_exact "$action29c_remote_backup/pihole-FTL.conf.before" \
        "$action29c_remote_owner" "$action29c_remote_group" 600 || return 1
    metadata_owner_exact "$action29c_remote_backup/local.theama.co.conf.before" \
        "$action29c_remote_owner" "$action29c_remote_group" 600 || return 1
    metadata_owner_exact "$action29c_remote_backup/transaction.complete" \
        "$action29c_remote_owner" "$action29c_remote_group" 600 || return 1
    [[ "$(file_hash "$action29c_remote_backup/pihole-FTL.conf.before")" = "$action29c_remote_before_ftl" ]] || return 1
    [[ "$(file_hash "$action29c_remote_backup/local.theama.co.conf.before")" = "$action29c_remote_before_domain" ]] || return 1
    [[ "$(<"$action29c_remote_backup/transaction.complete")" = committed ]] || return 1
    action29c_remote_expected_manifest=$(printf '%s\n' \
        'action=29b' "role=${node_token//_/-}" \
        "before_ftl_sha256=$action29c_remote_before_ftl" \
        "before_domain_sha256=$action29c_remote_before_domain" \
        "target_ftl_sha256=$pihole_ftl_target_sha256" \
        "target_domain_sha256=$pihole_domain_target_sha256") || return 1
    [[ "$(<"$action29c_remote_backup/manifest")" = "$action29c_remote_expected_manifest" ]]
}
pihole_ftl_v5_semantics_exact() {
    local action29c_remote_file=${1:-$pihole_ftl}
    local action29c_remote_observed
    local action29c_remote_expected

    action29c_remote_observed=$(grep -Ev '^[[:space:]]*(#|$)' "$action29c_remote_file") || return 1
    action29c_remote_expected=$'PRIVACYLEVEL=0\nRATE_LIMIT=1000/60\nRESOLVE_IPV6=YES\nPIHOLE_PTR=NONE'
    [[ "$action29c_remote_observed" = "$action29c_remote_expected" ]]
}
pihole_domain_v5_semantics_exact() {
    local action29c_remote_file=${1:-$pihole_domain}
    local action29c_remote_observed
    local action29c_remote_expected

    action29c_remote_observed=$(grep -Ev '^[[:space:]]*(#|$)' "$action29c_remote_file") || return 1
    action29c_remote_expected=$'domain=local.theama.co\nserver=/local.theama.co/127.0.0.1#5335\nserver=/local.theama.co/::1#5335\nserver=/0.1.10.in-addr.arpa/127.0.0.1#5335\nserver=/0.1.10.in-addr.arpa/::1#5335\nserver=/1.1.10.in-addr.arpa/127.0.0.1#5335\nserver=/1.1.10.in-addr.arpa/::1#5335\nserver=/2.1.10.in-addr.arpa/127.0.0.1#5335\nserver=/2.1.10.in-addr.arpa/::1#5335\nserver=/3.1.10.in-addr.arpa/127.0.0.1#5335\nserver=/3.1.10.in-addr.arpa/::1#5335\nserver=/1.0.0.0.1.7.9.6.8.a.a.5.6.3.d.f.ip6.arpa/127.0.0.1#5335\nserver=/1.0.0.0.1.7.9.6.8.a.a.5.6.3.d.f.ip6.arpa/::1#5335'
    [[ "$action29c_remote_observed" = "$action29c_remote_expected" ]]
}
endpoint_specs() {
    printf '%s\n' \
        'shared_ipv4|pihole-admin.local.theama.co|10.1.0.56|10.1.0.56' \
        'shared_ipv6|pihole-admin.local.theama.co|[fd36:5aa8:6971:1::56]|fd36:5aa8:6971:1::56' \
        'node_a_ipv4|pihole0.local.theama.co|10.1.0.53|10.1.0.53' \
        'node_a_ipv6|pihole0.local.theama.co|[fd36:5aa8:6971:1::53]|fd36:5aa8:6971:1::53' \
        'node_b_ipv4|pihole00.local.theama.co|10.1.0.54|10.1.0.54' \
        'node_b_ipv6|pihole00.local.theama.co|[fd36:5aa8:6971:1::54]|fd36:5aa8:6971:1::54'
}
probe_web_endpoint() {
    local action29c_remote_label=$1
    local action29c_remote_fqdn=$2
    local action29c_remote_resolve=$3
    local action29c_remote_expected_ip=$4
    local action29c_remote_status=0
    local action29c_remote_metadata
    local action29c_remote_http_code
    local action29c_remote_effective_url
    local action29c_remote_remote_ip
    local action29c_remote_redirects
    local action29c_remote_body_bytes
    local action29c_remote_body_sha256

    : >"$action29c_remote_web_body" || return 1
    action29c_remote_metadata=$(/usr/bin/curl --noproxy '*' --insecure --silent --show-error \
        --http1.1 --location --max-redirs 3 --proto-redir '=https' \
        --connect-timeout 3 --max-time 10 \
        --resolve "${action29c_remote_fqdn}:443:${action29c_remote_resolve}" \
        --output "$action29c_remote_web_body" \
        --write-out '%{http_code}|%{url_effective}|%{remote_ip}|%{num_redirects}' \
        "https://${action29c_remote_fqdn}/admin/") || action29c_remote_status=$?
    IFS='|' read -r action29c_remote_http_code action29c_remote_effective_url \
        action29c_remote_remote_ip action29c_remote_redirects <<<"$action29c_remote_metadata"
    action29c_remote_body_bytes=$(wc -c <"$action29c_remote_web_body") || return 1
    action29c_remote_body_sha256=$(file_hash "$action29c_remote_web_body") || return 1
    printf '%s_%s_observed_web_%s_status=%s\n' "$prefix" "$node_token" "$action29c_remote_label" "$action29c_remote_status"
    printf '%s_%s_observed_web_%s_http_code=%s\n' "$prefix" "$node_token" "$action29c_remote_label" "$action29c_remote_http_code"
    printf '%s_%s_observed_web_%s_effective_url=%s\n' "$prefix" "$node_token" "$action29c_remote_label" "$action29c_remote_effective_url"
    printf '%s_%s_observed_web_%s_remote_ip=%s\n' "$prefix" "$node_token" "$action29c_remote_label" "$action29c_remote_remote_ip"
    printf '%s_%s_observed_web_%s_redirects=%s\n' "$prefix" "$node_token" "$action29c_remote_label" "$action29c_remote_redirects"
    printf '%s_%s_observed_web_%s_body_bytes=%s\n' "$prefix" "$node_token" "$action29c_remote_label" "$action29c_remote_body_bytes"
    printf '%s_%s_observed_web_%s_body_sha256=%s\n' "$prefix" "$node_token" "$action29c_remote_label" "$action29c_remote_body_sha256"
    check "web_${action29c_remote_label}_status" test "$action29c_remote_status" -eq 0 || return 1
    check "web_${action29c_remote_label}_http_200" test "$action29c_remote_http_code" = 200 || return 1
    check "web_${action29c_remote_label}_effective_url" test "$action29c_remote_effective_url" = \
        "https://${action29c_remote_fqdn}/admin/login.php" || return 1
    check "web_${action29c_remote_label}_remote_ip" test "$action29c_remote_remote_ip" = \
        "$action29c_remote_expected_ip" || return 1
    check "web_${action29c_remote_label}_redirect_once" test "$action29c_remote_redirects" = 1 || return 1
    check "web_${action29c_remote_label}_body_nonempty" test "$action29c_remote_body_bytes" -gt 0 || return 1
    check "web_${action29c_remote_label}_body_bounded" test "$action29c_remote_body_bytes" -le \
        "$maximum_web_body_bytes" || return 1
    check "web_${action29c_remote_label}_body_pihole" grep -Fqi Pi-hole \
        "$action29c_remote_web_body" || return 1
}
manifest_valid() {
    local action29_remote_release=$1

    [[ -d "$action29_remote_release" && ! -L "$action29_remote_release" ]] || return 1
    [[ -f "$action29_remote_release/release-manifest.json" ]] || return 1
    [[ -f "$action29_remote_release/manifest.sha256" ]] || return 1
    [[ -f "$action29_remote_release/.complete" ]] || return 1
    [[ "$(jq -r '.revision // empty' "$action29_remote_release/release-manifest.json")" = "$expected_revision" ]] || return 1
    [[ "$(jq -r '.source_node // empty' "$action29_remote_release/release-manifest.json")" = "$expected_source" ]] || return 1
    [[ "$(file_hash "$action29_remote_release/manifest.sha256")" = "$expected_payload_sha256" ]] || return 1
    (cd -- "$action29_remote_release" && sha256sum --check --status manifest.sha256)
}
service_active() { systemctl is-active --quiet "$1"; }
service_not_failed() { [[ "$(systemctl is-failed "$1" 2>/dev/null || true)" != failed ]]; }
expected_checks() {
    printf '%s\n' \
        uid_root working_directory_root hostname_exact keepalived_hash_exact \
        pihole_ftl_regular pihole_ftl_not_symlink pihole_ftl_metadata_exact \
        pihole_ftl_hash_exact pihole_ftl_v5_semantics_exact pihole_domain_regular \
        pihole_domain_not_symlink pihole_domain_metadata_exact pihole_domain_hash_exact \
        pihole_domain_v5_semantics_exact action29b_backup_valid unbound_zone_hash_exact \
        health_helper_hash_exact publisher_hash_exact reconciler_hash_exact \
        finalizer_hash_exact lsyncd_config_hash_exact lsyncd_unit_hash_exact \
        reconcile_path_hash_exact reconcile_service_hash_exact \
        publisher_metadata_exact reconciler_metadata_exact finalizer_metadata_exact \
        lsyncd_config_metadata_exact lsyncd_unit_metadata_exact \
        reconcile_path_metadata_exact reconcile_service_metadata_exact \
        keepalived_active caddy_active lighttpd_active unbound_active pihole_ftl_active \
        lsyncd_active reconcile_path_active reconcile_service_not_failed \
        lsyncd_running lsyncd_result_success lsyncd_pid_valid lsyncd_restarts_valid \
        dbus_ipv4_state_exact dbus_ipv6_state_exact dns_ipv4_ownership_exact \
        dns_ipv6_ownership_exact caddy_ipv4_ownership_exact caddy_ipv6_ownership_exact \
        current_link_symlink current_release_resolved current_revision_exact \
        current_source_exact current_manifest_valid backup_marker_exact \
        transient_stage_absent failed_units_absent state_snapshot_valid state_unchanged \
        version_inventory_status version_inventory_nonempty version_inventory_safe
    while IFS='|' read -r action29c_remote_endpoint _ _ _; do
        printf '%s\n' \
            "web_${action29c_remote_endpoint}_status" \
            "web_${action29c_remote_endpoint}_http_200" \
            "web_${action29c_remote_endpoint}_effective_url" \
            "web_${action29c_remote_endpoint}_remote_ip" \
            "web_${action29c_remote_endpoint}_redirect_once" \
            "web_${action29c_remote_endpoint}_body_nonempty" \
            "web_${action29c_remote_endpoint}_body_bounded" \
            "web_${action29c_remote_endpoint}_body_pihole"
    done < <(endpoint_specs)
}
state_snapshot() {
    printf 'files=%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$(file_hash /etc/keepalived/keepalived.conf)" "$(file_hash "$pihole_ftl")" \
        "$(file_hash "$pihole_domain")" "$(file_hash "$unbound_zone")" \
        "$(file_hash "$health_helper")" "$(file_hash "$publisher")" \
        "$(file_hash "$reconciler")" "$(file_hash "$finalizer")" \
        "$(file_hash "$lsyncd_config")" "$(file_hash "$lsyncd_unit")" \
        "$(file_hash "$reconcile_path")" "$(file_hash "$reconcile_service")" \
        "$(readlink -- "$current_link")"
    printf 'services=%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$(systemctl is-active keepalived.service)" "$(systemctl is-active caddy.service)" \
        "$(systemctl is-active lighttpd.service)" "$(systemctl is-active unbound.service)" \
        "$(systemctl is-active pihole-FTL.service)" "$(systemctl is-active caddy-lsyncd.service)" \
        "$(systemctl is-active caddy-sync-reconcile.path)" \
        "$(systemctl is-failed caddy-sync-reconcile.service 2>/dev/null || true)"
    printf 'ownership=%s|%s|%s|%s|%s|%s\n' \
        "$(dbus_state "$ipv4_object")" "$(dbus_state "$ipv6_object")" \
        "$(address_count -4 "$dns_ipv4_cidr")" "$(address_count -6 "$dns_ipv6_cidr")" \
        "$(address_count -4 "$caddy_ipv4_cidr")" "$(address_count -6 "$caddy_ipv6_cidr")"
}
version_inventory() {
    printf 'caddy=%s\n' "$(caddy version | head -n 1)"
    printf 'keepalived=%s\n' "$(keepalived --version 2>&1 | head -n 1)"
    printf 'lsyncd=%s\n' "$(lsyncd --version 2>&1 | head -n 1)"
    printf 'unbound=%s\n' "$(unbound -V 2>&1 | head -n 1)"
    printf 'pihole=%s\n' "$(/usr/local/bin/pihole -v 2>&1 | tr '\n' ';' | cut -c 1-1024)"
}
safe_version_inventory() {
    local action29_remote_file=$1

    [[ "$(wc -c <"$action29_remote_file")" -le 4096 ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action29_remote_file" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action29_remote_file" >/dev/null || return 1
    ! grep -Eqi 'PRIVATE KEY|Authorization:|WEBPASSWORD' "$action29_remote_file"
}
cleanup() {
    local action29c_remote_cleanup_status=$?

    trap - EXIT INT TERM
    if [[ -n ${action29c_remote_versions:-} ]]; then
        rm -f -- "$action29c_remote_versions"
    fi
    if [[ -n ${action29c_remote_web_body:-} ]]; then
        rm -f -- "$action29c_remote_web_body"
    fi
    exit "$action29c_remote_cleanup_status"
}
run_inspection() {
    local action29_remote_started_ns
    local action29_remote_finished_ns
    local action29_remote_before
    local action29_remote_after
    local action29_remote_release
    local action29_remote_version_status=0
    local action29_remote_lsyncd_pid
    local action29_remote_lsyncd_restarts
    local action29_remote_lsyncd_result
    local action29c_remote_observed_ftl_sha256
    local action29c_remote_observed_domain_sha256
    local action29c_remote_endpoint
    local action29c_remote_fqdn
    local action29c_remote_resolve
    local action29c_remote_expected_ip

    trap cleanup EXIT INT TERM
    action29_remote_started_ns=$(date +%s%N) || return 1
    action29c_remote_versions=$(mktemp /tmp/action29c-versions.XXXXXX) || return 1
    action29c_remote_web_body=$(mktemp /tmp/action29c-web-body.XXXXXX) || return 1
    action29_remote_before=$(state_snapshot | sha256sum | awk '{ print $1 }') || return 1
    action29_remote_release=$(readlink -f -- "$current_link") || return 1
    action29_remote_lsyncd_pid=$(systemctl show caddy-lsyncd.service --property MainPID --value) || return 1
    action29_remote_lsyncd_restarts=$(systemctl show caddy-lsyncd.service --property NRestarts --value) || return 1
    action29_remote_lsyncd_result=$(systemctl show caddy-lsyncd.service --property Result --value) || return 1

    # conditional-validator-explicit-failures-begin
    check uid_root test "$(id -u)" -eq 0 || return 1
    check working_directory_root test "$PWD" = / || return 1
    check hostname_exact test "$(hostname)" = "$expected_hostname" || return 1
    check keepalived_hash_exact test "$(file_hash /etc/keepalived/keepalived.conf)" = "$expected_keepalived_sha256" || return 1
    check pihole_ftl_regular test -f "$pihole_ftl" || return 1
    check pihole_ftl_not_symlink test ! -L "$pihole_ftl" || return 1
    check pihole_ftl_metadata_exact metadata_owner_exact "$pihole_ftl" pihole root 664 || return 1
    action29c_remote_observed_ftl_sha256=$(file_hash "$pihole_ftl") || return 1
    printf '%s_%s_expected_pihole_ftl_sha256=%s\n' "$prefix" "$node_token" "$pihole_ftl_target_sha256"
    printf '%s_%s_observed_pihole_ftl_sha256=%s\n' "$prefix" "$node_token" "$action29c_remote_observed_ftl_sha256"
    check pihole_ftl_hash_exact test "$action29c_remote_observed_ftl_sha256" = "$pihole_ftl_target_sha256" || return 1
    check pihole_ftl_v5_semantics_exact pihole_ftl_v5_semantics_exact || return 1
    check pihole_domain_regular test -f "$pihole_domain" || return 1
    check pihole_domain_not_symlink test ! -L "$pihole_domain" || return 1
    check pihole_domain_metadata_exact metadata_owner_exact "$pihole_domain" root root 644 || return 1
    action29c_remote_observed_domain_sha256=$(file_hash "$pihole_domain") || return 1
    printf '%s_%s_expected_pihole_domain_sha256=%s\n' "$prefix" "$node_token" "$pihole_domain_target_sha256"
    printf '%s_%s_observed_pihole_domain_sha256=%s\n' "$prefix" "$node_token" "$action29c_remote_observed_domain_sha256"
    check pihole_domain_hash_exact test "$action29c_remote_observed_domain_sha256" = "$pihole_domain_target_sha256" || return 1
    check pihole_domain_v5_semantics_exact pihole_domain_v5_semantics_exact || return 1
    check action29b_backup_valid action29b_backup_valid || return 1
    check unbound_zone_hash_exact test "$(file_hash "$unbound_zone")" = "$unbound_zone_sha256" || return 1
    check health_helper_hash_exact test "$(file_hash "$health_helper")" = "$health_helper_sha256" || return 1
    check publisher_hash_exact test "$(file_hash "$publisher")" = "$publisher_sha256" || return 1
    check reconciler_hash_exact test "$(file_hash "$reconciler")" = "$reconciler_sha256" || return 1
    check finalizer_hash_exact test "$(file_hash "$finalizer")" = "$finalizer_sha256" || return 1
    check lsyncd_config_hash_exact test "$(file_hash "$lsyncd_config")" = "$expected_lsyncd_sha256" || return 1
    check lsyncd_unit_hash_exact test "$(file_hash "$lsyncd_unit")" = "$lsyncd_unit_sha256" || return 1
    check reconcile_path_hash_exact test "$(file_hash "$reconcile_path")" = "$reconcile_path_sha256" || return 1
    check reconcile_service_hash_exact test "$(file_hash "$reconcile_service")" = "$reconcile_service_sha256" || return 1
    for action29_remote_spec in \
        "publisher:$publisher:755" "reconciler:$reconciler:755" "finalizer:$finalizer:755" \
        "lsyncd_config:$lsyncd_config:644" "lsyncd_unit:$lsyncd_unit:644" \
        "reconcile_path:$reconcile_path:644" "reconcile_service:$reconcile_service:644"; do
        IFS=: read -r action29_remote_label action29_remote_path action29_remote_mode <<<"$action29_remote_spec"
        check "${action29_remote_label}_metadata_exact" metadata_exact \
            "$action29_remote_path" "$action29_remote_mode" || return 1
    done
    for action29_remote_service in keepalived caddy lighttpd unbound pihole-FTL caddy-lsyncd; do
        check "${action29_remote_service//-/_}_active" service_active \
            "$action29_remote_service.service" || return 1
    done
    check reconcile_path_active service_active caddy-sync-reconcile.path || return 1
    check reconcile_service_not_failed service_not_failed caddy-sync-reconcile.service || return 1
    check lsyncd_running test "$(systemctl show caddy-lsyncd.service --property SubState --value)" = running || return 1
    check lsyncd_result_success test "$action29_remote_lsyncd_result" = success || return 1
    check lsyncd_pid_valid test "$action29_remote_lsyncd_pid" -gt 0 || return 1
    check lsyncd_restarts_valid test "$action29_remote_lsyncd_restarts" -ge 0 || return 1
    check dbus_ipv4_state_exact test "$(dbus_state "$ipv4_object")" = "$expected_state" || return 1
    check dbus_ipv6_state_exact test "$(dbus_state "$ipv6_object")" = "$expected_state" || return 1
    check dns_ipv4_ownership_exact test "$(address_count -4 "$dns_ipv4_cidr")" -eq "$expected_vip_count" || return 1
    check dns_ipv6_ownership_exact test "$(address_count -6 "$dns_ipv6_cidr")" -eq "$expected_vip_count" || return 1
    check caddy_ipv4_ownership_exact test "$(address_count -4 "$caddy_ipv4_cidr")" -eq "$expected_vip_count" || return 1
    check caddy_ipv6_ownership_exact test "$(address_count -6 "$caddy_ipv6_cidr")" -eq "$expected_vip_count" || return 1
    check current_link_symlink test -L "$current_link" || return 1
    check current_release_resolved test "$action29_remote_release" = "$releases_root/$expected_revision" || return 1
    check current_revision_exact test "${action29_remote_release##*/}" = "$expected_revision" || return 1
    check current_source_exact test "$(jq -r '.source_node' "$action29_remote_release/release-manifest.json")" = "$expected_source" || return 1
    check current_manifest_valid manifest_valid "$action29_remote_release" || return 1
    check backup_marker_exact test -f "/var/backups/caddy-ha/action28ah-${node_token//_/-}-go-live/transaction.complete" || return 1
    check transient_stage_absent test -z "$(find /run -maxdepth 1 -name 'caddy-action28ah-bundle.*' -print -quit 2>/dev/null)" || return 1
    check failed_units_absent test -z "$(systemctl --failed --no-legend --plain | awk '$1 ~ /^(caddy|keepalived|pihole|unbound|lighttpd)/ { print $1 }')" || return 1
    check state_snapshot_valid valid_sha256 "$action29_remote_before" || return 1
    while IFS='|' read -r action29c_remote_endpoint action29c_remote_fqdn \
        action29c_remote_resolve action29c_remote_expected_ip; do
        probe_web_endpoint "$action29c_remote_endpoint" "$action29c_remote_fqdn" \
            "$action29c_remote_resolve" "$action29c_remote_expected_ip" || return 1
    done < <(endpoint_specs)
    version_inventory >"$action29c_remote_versions" 2>&1 || action29_remote_version_status=$?
    check version_inventory_status test "$action29_remote_version_status" -eq 0 || return 1
    check version_inventory_nonempty test -s "$action29c_remote_versions" || return 1
    check version_inventory_safe safe_version_inventory "$action29c_remote_versions" || return 1
    action29_remote_after=$(state_snapshot | sha256sum | awk '{ print $1 }') || return 1
    check state_unchanged test "$action29_remote_before" = "$action29_remote_after" || return 1
    # conditional-validator-explicit-failures-end

    action29_remote_finished_ns=$(date +%s%N) || return 1
    printf '%s_%s_schema=%s\n' "$prefix" "$node_token" "$schema_version"
    printf '%s_%s_observed_revision=%s\n' "$prefix" "$node_token" "$expected_revision"
    printf '%s_%s_observed_source=%s\n' "$prefix" "$node_token" "$expected_source"
    printf '%s_%s_observed_dbus_state=%s\n' "$prefix" "$node_token" "$expected_state"
    printf '%s_%s_observed_lsyncd_pid=%s\n' "$prefix" "$node_token" "$action29_remote_lsyncd_pid"
    printf '%s_%s_observed_lsyncd_restarts=%s\n' "$prefix" "$node_token" "$action29_remote_lsyncd_restarts"
    printf '%s_%s_observed_state_sha256=%s\n' "$prefix" "$node_token" "$action29_remote_after"
    printf '%s_%s_observed_versions_begin\n' "$prefix" "$node_token"
    sed "s/^/${prefix}_${node_token}_observed_version=/" "$action29c_remote_versions"
    printf '%s_%s_observed_versions_end\n' "$prefix" "$node_token"
    printf '%s_%s_observed_elapsed_ms=%s\n' "$prefix" "$node_token" \
        "$(((action29_remote_finished_ns - action29_remote_started_ns) / 1000000))"
    printf '%s_%s_first_failure=%s\n' "$prefix" "$node_token" "$first_failure"
    printf '%s_%s_read_only=true\n' "$prefix" "$node_token"
    printf '%s_%s_complete=true\n' "$prefix" "$node_token"
}
self_test() {
    while IFS= read -r action29_remote_label; do
        printf '%s_%s_check_%s=true\n' "$prefix" "$node_token" "$action29_remote_label"
    done < <(expected_checks)
    printf '%s_%s_expected_pihole_ftl_sha256=%s\n' "$prefix" "$node_token" "$pihole_ftl_target_sha256"
    printf '%s_%s_observed_pihole_ftl_sha256=%s\n' "$prefix" "$node_token" "$pihole_ftl_target_sha256"
    printf '%s_%s_expected_pihole_domain_sha256=%s\n' "$prefix" "$node_token" "$pihole_domain_target_sha256"
    printf '%s_%s_observed_pihole_domain_sha256=%s\n' "$prefix" "$node_token" "$pihole_domain_target_sha256"
    printf '%s_%s_schema=%s\n' "$prefix" "$node_token" "$schema_version"
    printf '%s_%s_observed_revision=%s\n' "$prefix" "$node_token" "$expected_revision"
    printf '%s_%s_observed_source=%s\n' "$prefix" "$node_token" "$expected_source"
    printf '%s_%s_observed_dbus_state=%s\n' "$prefix" "$node_token" "$expected_state"
    printf '%s_%s_observed_lsyncd_pid=1234\n' "$prefix" "$node_token"
    printf '%s_%s_observed_lsyncd_restarts=0\n' "$prefix" "$node_token"
    printf '%s_%s_observed_state_sha256=%s\n' "$prefix" "$node_token" "$expected_payload_sha256"
    printf '%s_%s_observed_versions_begin\n' "$prefix" "$node_token"
    printf '%s_%s_observed_version=caddy=v2.test\n' "$prefix" "$node_token"
    printf '%s_%s_observed_versions_end\n' "$prefix" "$node_token"
    printf '%s_%s_observed_elapsed_ms=1\n' "$prefix" "$node_token"
    printf '%s_%s_first_failure=none\n' "$prefix" "$node_token"
    printf '%s_%s_read_only=true\n' "$prefix" "$node_token"
    printf '%s_%s_complete=true\n' "$prefix" "$node_token"
}
cleanup_self_test() {
    action29c_remote_versions=
    action29c_remote_web_body=
    trap cleanup EXIT INT TERM
    printf '%s_cleanup_unset_safe=true\n' "$prefix"
}

case "${1:-}" in
    --expected-checks)
        configure_node "${2:-}" || exit $?
        expected_checks
        ;;
    --self-test-node)
        configure_node "${2:-}" || exit $?
        self_test
        ;;
    --cleanup-self-test) cleanup_self_test ;;
    --validate-ftl-v5) pihole_ftl_v5_semantics_exact "${2:?}" ;;
    --validate-domain-v5) pihole_domain_v5_semantics_exact "${2:?}" ;;
    --validate-action29b-backup)
        configure_node "${2:-}" || exit $?
        action29b_backup_valid "${3:?}" "${4:?}" "${5:?}" "${6:?}" "${7:?}"
        ;;
    --node)
        configure_node "${2:-}" || exit $?
        run_inspection
        ;;
    *) exit 64 ;;
esac
