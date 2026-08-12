#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_29b_remote
readonly ftl_path=/etc/pihole/pihole-FTL.conf
readonly domain_path=/etc/dnsmasq.d/local.theama.co.conf
readonly ftl_sha256=a1dc88b1f696a6870e38025be113ff8664750fca6265c79a2aee12f80898cfa3
readonly domain_sha256=39fa219a7d1c81c7fb36d89bc17ba1caae26f3472eb861a750a8ba03ae55b026
readonly ftl_base64='IzsgUGktaG9sZSBGVEwgY29uZmlnIGZpbGUKIzsgQ29tbWVudHMgc2hvdWxkIHN0YXJ0IHdpdGggIzsgdG8gYXZvaWQgaXNzdWVzIHdpdGggUEhQIGFuZCBiYXNoIHJlYWRpbmcgdGhpcyBmaWxlCiM7IExvY2F0aW9uOiAvZXRjL3BpaG9sZS9waWhvbGUtRlRMLmNvbmYKUFJJVkFDWUxFVkVMPTAKUkFURV9MSU1JVD0xMDAwLzYwCiM7IFByZXNlcnZlIGF1dGhvcml0YXRpdmUgcmV2ZXJzZSBhbnN3ZXJzIGZyb20gdGhlIGxvY2FsIFVuYm91bmQgem9uZS4KUkVTT0xWRV9JUFY2PVlFUwojOyBQaS1ob2xlIHY1IFBUUiBwb2xpY3kuClBJSE9MRV9QVFI9Tk9ORQ=='
readonly domain_base64='IyBMb2NhbCBkb21haW4gc3VwcGxpZWQgdG8gUGktaG9sZSB2NSBkbnNtYXNxL0ZUTC4KIyBsb2NhdGlvbjogL2V0Yy9kbnNtYXNxLmQvbG9jYWwudGhlYW1hLmNvLmNvbmYKZG9tYWluPWxvY2FsLnRoZWFtYS5jbwoKIyBGb3J3YXJkIHRoZSBsb2NhbCBkb21haW4gdG8gVW5ib3VuZApzZXJ2ZXI9L2xvY2FsLnRoZWFtYS5jby8xMjcuMC4wLjEjNTMzNQpzZXJ2ZXI9L2xvY2FsLnRoZWFtYS5jby86OjEjNTMzNQoKIyBGb3J3YXJkIElQdjQgbG9jYWwgUFRSIHJldmVyc2UgbG9va3VwcyBmb3IgMTAuMS4wLjAvMjIKc2VydmVyPS8wLjEuMTAuaW4tYWRkci5hcnBhLzEyNy4wLjAuMSM1MzM1CnNlcnZlcj0vMC4xLjEwLmluLWFkZHIuYXJwYS86OjEjNTMzNQoKc2VydmVyPS8xLjEuMTAuaW4tYWRkci5hcnBhLzEyNy4wLjAuMSM1MzM1CnNlcnZlcj0vMS4xLjEwLmluLWFkZHIuYXJwYS86OjEjNTMzNQoKc2VydmVyPS8yLjEuMTAuaW4tYWRkci5hcnBhLzEyNy4wLjAuMSM1MzM1CnNlcnZlcj0vMi4xLjEwLmluLWFkZHIuYXJwYS86OjEjNTMzNQoKc2VydmVyPS8zLjEuMTAuaW4tYWRkci5hcnBhLzEyNy4wLjAuMSM1MzM1CnNlcnZlcj0vMy4xLjEwLmluLWFkZHIuYXJwYS86OjEjNTMzNQoKIyBGb3J3YXJkIFVMQSAvNjQgbG9jYWwgUFRSIHJldmVyc2UgbG9va3VwcyB0byBVbmJvdW5kCnNlcnZlcj0vMS4wLjAuMC4xLjcuOS42LjguYS5hLjUuNi4zLmQuZi5pcDYuYXJwYS8xMjcuMC4wLjEjNTMzNQpzZXJ2ZXI9LzEuMC4wLjAuMS43LjkuNi44LmEuYS41LjYuMy5kLmYuaXA2LmFycGEvOjoxIzUzMzU='
readonly dns_ipv4=10.1.0.55
readonly dns_ipv6=fd36:5aa8:6971:1::55
readonly caddy_ipv4=10.1.0.56
readonly caddy_ipv6=fd36:5aa8:6971:1::56

role=
node_token=
expected_hostname=
expected_state=
expected_vip_count=
backup_dir=
stage_dir=
mutation_started=false
transaction_complete=false

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
manifest_value() {
    local action29b_key=$1

    awk -F= -v wanted="$action29b_key" '$1 == wanted { print substr($0, index($0, "=") + 1) }' \
        "$backup_dir/manifest"
}
check() {
    local action29b_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_%s_check_%s=true\n' "$prefix" "$node_token" "$action29b_label"
        return 0
    fi
    printf '%s_%s_check_%s=false\n' "$prefix" "$node_token" "$action29b_label" >&2
    return 1
}
configure_node() {
    role=$1
    case "$role" in
        node-a)
            node_token=node_a
            expected_hostname=j1-svpihole0
            expected_state=Master
            expected_vip_count=1
            ;;
        node-b)
            node_token=node_b
            expected_hostname=j1-svpihole00
            expected_state=Backup
            expected_vip_count=0
            ;;
        *) return 64 ;;
    esac
    backup_dir=/var/backups/caddy-ha/action29b-${role}-pihole-v5-config
}
dbus_state() {
    busctl get-property org.keepalived.Vrrp1 "$1" org.keepalived.Vrrp1.Instance State |
        awk -F '"' 'NF == 3 { print $2 }'
}
address_count() {
    local action29b_family=$1
    local action29b_address=$2

    ip -o "$action29b_family" addr show |
        awk -v wanted="$action29b_address" '$4 ~ ("^" wanted "/") { count++ } END { print count + 0 }'
}
query_exact() {
    local action29b_name=$1
    local action29b_type=$2
    local action29b_expected=$3
    local action29b_answer

    if [[ "$action29b_type" = PTR ]]; then
        action29b_answer=$(timeout 5 dig +time=2 +tries=1 +short @127.0.0.1 -x "$action29b_name") || return 1
    else
        action29b_answer=$(timeout 5 dig +time=2 +tries=1 +short @127.0.0.1 "$action29b_name" "$action29b_type") || return 1
    fi
    action29b_answer=$(printf '%s\n' "$action29b_answer" | sed '/^$/d' | sort -u)
    [[ "$action29b_answer" = "$action29b_expected" ]]
}
pihole_v5() {
    local action29b_version

    action29b_version=$(/usr/local/bin/pihole -v 2>&1) || return 1
    grep -Eq 'Pi-hole version is v5([.]|$)' <<<"$action29b_version" || return 1
    grep -Eq 'FTL version is v5([.]|$)' <<<"$action29b_version"
}
validate_dns() {
    query_exact pihole.local.theama.co A 10.1.0.55 || return 1
    query_exact pihole.local.theama.co AAAA fd36:5aa8:6971:1::55 || return 1
    query_exact proxy.local.theama.co A 10.1.0.56 || return 1
    query_exact proxy.local.theama.co AAAA fd36:5aa8:6971:1::56 || return 1
    query_exact 10.1.0.55 PTR pihole.local.theama.co. || return 1
    query_exact fd36:5aa8:6971:1::55 PTR pihole.local.theama.co. || return 1
    query_exact 10.1.0.56 PTR proxy.local.theama.co. || return 1
    query_exact fd36:5aa8:6971:1::56 PTR proxy.local.theama.co. || return 1
    query_exact _https._tcp.proxy.local.theama.co SRV '0 0 443 proxy.local.theama.co.'
}
verify_continuity() {
    check uid_root test "$(id -u)" -eq 0 || return 1
    check working_directory_root test "$PWD" = / || return 1
    check hostname_exact test "$(hostname)" = "$expected_hostname" || return 1
    check pihole_v5 pihole_v5 || return 1
    check pihole_ftl_active systemctl is-active --quiet pihole-FTL.service || return 1
    check unbound_active systemctl is-active --quiet unbound.service || return 1
    check keepalived_active systemctl is-active --quiet keepalived.service || return 1
    check caddy_active systemctl is-active --quiet caddy.service || return 1
    check ipv4_state test "$(dbus_state /org/keepalived/Vrrp1/Instance/eth0/100/IPv4)" = "$expected_state" || return 1
    check ipv6_state test "$(dbus_state /org/keepalived/Vrrp1/Instance/eth0/101/IPv6)" = "$expected_state" || return 1
    check dns_ipv4_count test "$(address_count -4 "$dns_ipv4")" -eq "$expected_vip_count" || return 1
    check dns_ipv6_count test "$(address_count -6 "$dns_ipv6")" -eq "$expected_vip_count" || return 1
    check caddy_ipv4_count test "$(address_count -4 "$caddy_ipv4")" -eq "$expected_vip_count" || return 1
    check caddy_ipv6_count test "$(address_count -6 "$caddy_ipv6")" -eq "$expected_vip_count" || return 1
    check dns_record_families validate_dns || return 1
}
restore_backup() {
    local action29b_backup_ftl_sha256
    local action29b_backup_domain_sha256

    check backup_manifest_regular test -f "$backup_dir/manifest" || return 1
    check backup_manifest_not_symlink test ! -L "$backup_dir/manifest" || return 1
    check backup_ftl_regular test -f "$backup_dir/pihole-FTL.conf.before" || return 1
    check backup_ftl_not_symlink test ! -L "$backup_dir/pihole-FTL.conf.before" || return 1
    check backup_domain_regular test -f "$backup_dir/local.theama.co.conf.before" || return 1
    check backup_domain_not_symlink test ! -L "$backup_dir/local.theama.co.conf.before" || return 1
    action29b_backup_ftl_sha256=$(manifest_value before_ftl_sha256) || return 1
    action29b_backup_domain_sha256=$(manifest_value before_domain_sha256) || return 1
    check backup_ftl_manifest_unique test \
        "$(grep -Fxc "before_ftl_sha256=$action29b_backup_ftl_sha256" "$backup_dir/manifest")" -eq 1 || return 1
    check backup_domain_manifest_unique test \
        "$(grep -Fxc "before_domain_sha256=$action29b_backup_domain_sha256" "$backup_dir/manifest")" -eq 1 || return 1
    check backup_ftl_hash test \
        "$(file_hash "$backup_dir/pihole-FTL.conf.before")" = "$action29b_backup_ftl_sha256" || return 1
    check backup_domain_hash test \
        "$(file_hash "$backup_dir/local.theama.co.conf.before")" = "$action29b_backup_domain_sha256" || return 1
    install -o pihole -g root -m 0664 "$backup_dir/pihole-FTL.conf.before" \
        /etc/pihole/.pihole-FTL.conf.action29b.rollback || return 1
    install -o root -g root -m 0644 "$backup_dir/local.theama.co.conf.before" \
        /etc/dnsmasq.d/.local.theama.co.conf.action29b.rollback || return 1
    mv -fT /etc/pihole/.pihole-FTL.conf.action29b.rollback "$ftl_path" || return 1
    mv -fT /etc/dnsmasq.d/.local.theama.co.conf.action29b.rollback "$domain_path" || return 1
    check restored_ftl_hash test "$(file_hash "$ftl_path")" = "$action29b_backup_ftl_sha256" || return 1
    check restored_domain_hash test "$(file_hash "$domain_path")" = "$action29b_backup_domain_sha256" || return 1
    /usr/bin/pihole-FTL --test >/dev/null 2>&1 || return 1
    timeout 20 /usr/local/bin/pihole restartdns >/dev/null 2>&1 || return 1
    systemctl is-active --quiet pihole-FTL.service || return 1
}
rollback_on_error() {
    local action29b_status=$?
    local action29b_recovery_failed=false

    trap - EXIT INT TERM
    [[ -z ${stage_dir:-} || ! -d $stage_dir ]] || rm -rf -- "$stage_dir"
    if [[ "$transaction_complete" = true || "$mutation_started" = false ]]; then
        exit "$action29b_status"
    fi
    printf '%s_%s_rollback_started=true\n' "$prefix" "$node_token" >&2
    set +e
    restore_backup || action29b_recovery_failed=true
    verify_continuity || action29b_recovery_failed=true
    set -e
    if [[ "$action29b_recovery_failed" = true ]]; then
        printf '%s_%s_manual_intervention_required=true\n' "$prefix" "$node_token" >&2
        exit 125
    fi
    printf '%s_%s_rollback_complete=true\n' "$prefix" "$node_token" >&2
    exit "$action29b_status"
}
apply_config() {
    local action29b_ftl_candidate
    local action29b_domain_candidate
    local action29b_before_ftl
    local action29b_before_domain

    trap rollback_on_error EXIT INT TERM
    verify_continuity || return 1
    check ftl_regular test -f "$ftl_path" || return 1
    check ftl_not_symlink test ! -L "$ftl_path" || return 1
    check ftl_metadata test "$(stat -c '%U:%G:%a' "$ftl_path")" = pihole:root:664 || return 1
    check domain_regular test -f "$domain_path" || return 1
    check domain_not_symlink test ! -L "$domain_path" || return 1
    check domain_metadata test "$(stat -c '%U:%G:%a' "$domain_path")" = root:root:644 || return 1
    check backup_absent test ! -e "$backup_dir" || return 1
    action29b_before_ftl=$(file_hash "$ftl_path") || return 1
    action29b_before_domain=$(file_hash "$domain_path") || return 1
    printf '%s_%s_observed_before_ftl_sha256=%s\n' "$prefix" "$node_token" "$action29b_before_ftl"
    printf '%s_%s_observed_before_domain_sha256=%s\n' "$prefix" "$node_token" "$action29b_before_domain"

    stage_dir=$(mktemp -d /run/caddy-action29b.XXXXXX) || return 1
    chmod 0700 "$stage_dir" || return 1
    check stage_metadata test "$(stat -c '%U:%G:%a' "$stage_dir")" = root:root:700 || return 1
    action29b_ftl_candidate=$stage_dir/pihole-FTL.conf
    action29b_domain_candidate=$stage_dir/local.theama.co.conf
    printf '%s' "$ftl_base64" | base64 -d >"$action29b_ftl_candidate" || return 1
    printf '%s' "$domain_base64" | base64 -d >"$action29b_domain_candidate" || return 1
    check candidate_ftl_hash test "$(file_hash "$action29b_ftl_candidate")" = "$ftl_sha256" || return 1
    check candidate_domain_hash test "$(file_hash "$action29b_domain_candidate")" = "$domain_sha256" || return 1

    install -d -o root -g root -m 0700 "$backup_dir" || return 1
    install -o root -g root -m 0600 "$ftl_path" "$backup_dir/pihole-FTL.conf.before" || return 1
    install -o root -g root -m 0600 "$domain_path" "$backup_dir/local.theama.co.conf.before" || return 1
    {
        printf 'action=29b\nrole=%s\n' "$role"
        printf 'before_ftl_sha256=%s\n' "$action29b_before_ftl"
        printf 'before_domain_sha256=%s\n' "$action29b_before_domain"
        printf 'target_ftl_sha256=%s\n' "$ftl_sha256"
        printf 'target_domain_sha256=%s\n' "$domain_sha256"
    } >"$backup_dir/manifest"
    chmod 0600 "$backup_dir/manifest" || return 1
    check backup_complete test -s "$backup_dir/manifest" || return 1

    install -o pihole -g root -m 0664 "$action29b_ftl_candidate" \
        /etc/pihole/.pihole-FTL.conf.action29b.new || return 1
    install -o root -g root -m 0644 "$action29b_domain_candidate" \
        /etc/dnsmasq.d/.local.theama.co.conf.action29b.new || return 1
    mutation_started=true
    mv -fT /etc/pihole/.pihole-FTL.conf.action29b.new "$ftl_path" || return 1
    mv -fT /etc/dnsmasq.d/.local.theama.co.conf.action29b.new "$domain_path" || return 1
    check installed_ftl_hash test "$(file_hash "$ftl_path")" = "$ftl_sha256" || return 1
    check installed_domain_hash test "$(file_hash "$domain_path")" = "$domain_sha256" || return 1
    check ftl_configuration_test /usr/bin/pihole-FTL --test || return 1
    check restartdns timeout 20 /usr/local/bin/pihole restartdns || return 1
    sleep 2
    verify_continuity || return 1
    printf '%s\n' committed >"$backup_dir/transaction.complete"
    chmod 0600 "$backup_dir/transaction.complete" || return 1
    transaction_complete=true
    rm -rf -- "$stage_dir"
    stage_dir=
    printf '%s_%s_target_ftl_sha256=%s\n' "$prefix" "$node_token" "$ftl_sha256"
    printf '%s_%s_target_domain_sha256=%s\n' "$prefix" "$node_token" "$domain_sha256"
    printf '%s_%s_mutation=true\n' "$prefix" "$node_token"
    printf '%s_%s_complete=true\n' "$prefix" "$node_token"
}
verify_target() {
    verify_continuity || return 1
    check target_ftl_hash test "$(file_hash "$ftl_path")" = "$ftl_sha256" || return 1
    check target_domain_hash test "$(file_hash "$domain_path")" = "$domain_sha256" || return 1
    check transaction_complete_marker test -s "$backup_dir/transaction.complete" || return 1
    printf '%s_%s_verify_target_complete=true\n' "$prefix" "$node_token"
}
rollback_committed() {
    check backup_manifest test -s "$backup_dir/manifest" || return 1
    restore_backup || return 1
    verify_continuity || return 1
    printf '%s\n' rolled-back >"$backup_dir/rollback.complete"
    chmod 0600 "$backup_dir/rollback.complete" || return 1
    printf '%s_%s_rollback_committed_complete=true\n' "$prefix" "$node_token"
}
self_test() {
    local action29b_root

    action29b_root=$(mktemp -d /tmp/action29b-selftest.XXXXXX) || return 1
    trap 'rm -rf -- "$action29b_root"' RETURN
    printf '%s' "$ftl_base64" | base64 -d >"$action29b_root/ftl" || return 1
    printf '%s' "$domain_base64" | base64 -d >"$action29b_root/domain" || return 1
    check selftest_ftl_hash test "$(file_hash "$action29b_root/ftl")" = "$ftl_sha256" || return 1
    check selftest_domain_hash test "$(file_hash "$action29b_root/domain")" = "$domain_sha256" || return 1
    printf '%s_%s_self_test_complete=true\n' "$prefix" "$node_token"
}

mode=${1:-}
configure_node "${2:-}" || exit $?
case "$mode" in
    --apply) apply_config ;;
    --verify-continuity) verify_continuity ;;
    --verify-target) verify_target ;;
    --rollback-committed) rollback_committed ;;
    --self-test) self_test ;;
    *) exit 64 ;;
esac
