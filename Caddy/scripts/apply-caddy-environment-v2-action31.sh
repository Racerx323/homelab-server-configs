#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_31_remote
readonly environment_path=/etc/default/caddy-ha
readonly dns_ipv4=10.1.0.55
readonly dns_ipv6=fd36:5aa8:6971:1::55
readonly caddy_ipv4=10.1.0.56
readonly caddy_ipv6=fd36:5aa8:6971:1::56
readonly ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/100/IPv4
readonly ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/101/IPv6

mode=${1:-}
role=${2:-}
node_token=
expected_hostname=
expected_fqdn=
expected_ipv4=
expected_ipv6=
expected_state=
expected_vip_count=
expected_legacy_sha256=
candidate_sha256=
candidate_base64=
backup_directory=
stage_directory=
mutation_started=false
transaction_complete=false

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
check() {
    local action31_check_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_%s_check_%s=true\n' "$prefix" "$node_token" "$action31_check_label"
        return 0
    fi
    printf '%s_%s_check_%s=false\n' "$prefix" "$node_token" "$action31_check_label" >&2
    return 1
}
configure_node() {
    role=$1
    case "$role" in
        node-a)
            node_token=node_a
            expected_hostname=j1-svpihole0
            expected_fqdn=pihole0.local.theama.co
            expected_ipv4=10.1.0.53
            expected_ipv6=fd36:5aa8:6971:1::53
            expected_state=Master
            expected_vip_count=1
            expected_legacy_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
            candidate_sha256=209e31e11a72660b7ebada372278c8482d9d1e65c6d83f6aa9510634d78f5ee3
            candidate_base64=Tk9ERV9GUUROPXBpaG9sZTAubG9jYWwudGhlYW1hLmNvCk5PREVfSVBWND0xMC4xLjAuNTMKTk9ERV9JUFY2PWZkMzY6NWFhODo2OTcxOjE6OjUzCg==
            ;;
        node-b)
            node_token=node_b
            expected_hostname=j1-svpihole00
            expected_fqdn=pihole00.local.theama.co
            expected_ipv4=10.1.0.54
            expected_ipv6=fd36:5aa8:6971:1::54
            expected_state=Backup
            expected_vip_count=0
            expected_legacy_sha256=f692d5b7e0a7e0f0ab142e36face6a8cc8c6680a44a2bcaf6a992247ec4c8113
            candidate_sha256=580d79608bb99567c1831d073785cdba9d9d02efeaa33717c8f8e0dca266b226
            candidate_base64=Tk9ERV9GUUROPXBpaG9sZTAwLmxvY2FsLnRoZWFtYS5jbwpOT0RFX0lQVjQ9MTAuMS4wLjU0Ck5PREVfSVBWNj1mZDM2OjVhYTg6Njk3MToxOjo1NAo=
            ;;
        *) return 64 ;;
    esac
    backup_directory=/var/backups/caddy-ha/action31-$role-environment-v2
}
dbus_state() {
    busctl get-property org.keepalived.Vrrp1 "$1" \
        org.keepalived.Vrrp1.Instance State |
        awk -F '"' 'NF == 3 { print $2 }'
}
address_count() {
    local action31_family=$1
    local action31_address=$2

    ip -o "$action31_family" address show |
        awk -v wanted="$action31_address" \
            '$4 ~ ("^" wanted "/") { count++ } END { print count + 0 }'
}
environment_contract() {
    local action31_candidate=$1

    # conditional-validator-explicit-failures-begin
    [[ -f "$action31_candidate" && ! -L "$action31_candidate" ]] || return 1
    [[ "$(file_hash "$action31_candidate")" = "$candidate_sha256" ]] || return 1
    [[ "$(wc -l <"$action31_candidate")" -eq 3 ]] || return 1
    [[ "$(grep -Fxc "NODE_FQDN=$expected_fqdn" "$action31_candidate")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc "NODE_IPV4=$expected_ipv4" "$action31_candidate")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc "NODE_IPV6=$expected_ipv6" "$action31_candidate")" -eq 1 ]] || return 1
    ! grep -Eq 'NODE_ROLE|PEER_|CADDY_PRIORITY|NETWORK_INTERFACE|SYNC_TARGET' \
        "$action31_candidate" || return 1
    # conditional-validator-explicit-failures-end
}
validate_candidate_caddy() {
    local action31_candidate=$1
    local action31_validation_root=$stage_directory/validation

    install -d -m 0700 "$action31_validation_root" \
        "$action31_validation_root/home" \
        "$action31_validation_root/config" \
        "$action31_validation_root/data" || return 1
    # shellcheck disable=SC2016
    env -i \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        HOME="$action31_validation_root/home" \
        XDG_CONFIG_HOME="$action31_validation_root/config" \
        XDG_DATA_HOME="$action31_validation_root/data" \
        /bin/bash -c \
        'set -Eeuo pipefail; set -a; source "$1"; set +a; exec caddy validate --config /etc/caddy/current/Caddyfile --adapter caddyfile' \
        _ "$action31_candidate" >/dev/null 2>&1
}
trusted_https() {
    curl --fail --silent --show-error --max-time 8 \
        --resolve "$expected_fqdn:443:$expected_ipv4" \
        "https://$expected_fqdn/admin/login.php" -o /dev/null || return 1
    curl --fail --silent --show-error --max-time 8 \
        --resolve "pihole-admin.local.theama.co:443:$caddy_ipv4" \
        https://pihole-admin.local.theama.co/admin/login.php -o /dev/null
}
verify_state() {
    local action31_expected_environment_sha256=$1

    # conditional-validator-explicit-failures-begin
    check uid_root test "$(id -u)" -eq 0 || return 1
    check working_directory_root test "$PWD" = / || return 1
    check hostname_exact test "$(hostname)" = "$expected_hostname" || return 1
    check environment_regular test -f "$environment_path" || return 1
    check environment_not_symlink test ! -L "$environment_path" || return 1
    check environment_metadata test "$(stat -c '%U:%G:%a' "$environment_path")" = root:caddy-tls:640 || return 1
    check environment_hash test "$(file_hash "$environment_path")" = "$action31_expected_environment_sha256" || return 1
    check caddy_active systemctl is-active --quiet caddy.service || return 1
    check keepalived_active systemctl is-active --quiet keepalived.service || return 1
    check lsyncd_active systemctl is-active --quiet caddy-lsyncd.service || return 1
    check reconciliation_path_active systemctl is-active --quiet caddy-sync-reconcile.path || return 1
    check ipv4_state test "$(dbus_state "$ipv4_object")" = "$expected_state" || return 1
    check ipv6_state test "$(dbus_state "$ipv6_object")" = "$expected_state" || return 1
    check dns_ipv4_count test "$(address_count -4 "$dns_ipv4")" -eq "$expected_vip_count" || return 1
    check dns_ipv6_count test "$(address_count -6 "$dns_ipv6")" -eq "$expected_vip_count" || return 1
    check caddy_ipv4_count test "$(address_count -4 "$caddy_ipv4")" -eq "$expected_vip_count" || return 1
    check caddy_ipv6_count test "$(address_count -6 "$caddy_ipv6")" -eq "$expected_vip_count" || return 1
    check current_release_directory test -d "$(readlink -f /etc/caddy/current)" || return 1
    check trusted_https trusted_https || return 1
    if [[ "$action31_expected_environment_sha256" = "$candidate_sha256" ]]; then
        check environment_contract environment_contract "$environment_path" || return 1
        check health_helper setpriv --reuid keepalived_script --regid caddy-tls \
            --clear-groups /usr/local/libexec/check-caddy.sh || return 1
    fi
    # conditional-validator-explicit-failures-end
}
restore_backup() {
    local action31_before_hash
    local action31_before_release

    [[ -f "$backup_directory/manifest" && ! -L "$backup_directory/manifest" ]] || return 1
    [[ -f "$backup_directory/caddy-ha.before" && ! -L "$backup_directory/caddy-ha.before" ]] || return 1
    action31_before_hash=$(awk -F= '$1 == "before_sha256" { print $2 }' "$backup_directory/manifest") || return 1
    action31_before_release=$(awk -F= '$1 == "before_release" { print $2 }' "$backup_directory/manifest") || return 1
    [[ "$action31_before_hash" = "$expected_legacy_sha256" ]] || return 1
    [[ "$(file_hash "$backup_directory/caddy-ha.before")" = "$action31_before_hash" ]] || return 1
    [[ "$(readlink -f /etc/caddy/current)" = "$action31_before_release" ]] || return 1
    install -o root -g caddy-tls -m 0640 "$backup_directory/caddy-ha.before" \
        /etc/default/.caddy-ha.action31.rollback || return 1
    mv -fT /etc/default/.caddy-ha.action31.rollback "$environment_path" || return 1
    systemctl reload caddy.service || return 1
    verify_state "$expected_legacy_sha256"
}
rollback_committed() {
    if [[ ! -e "$backup_directory" && ! -L "$backup_directory" ]]; then
        verify_state "$expected_legacy_sha256"
        return
    fi
    restore_backup
}
rollback_on_error() {
    local action31_status=$?
    local action31_recovery_failed=false

    trap - EXIT INT TERM
    [[ -z ${stage_directory:-} || ! -d $stage_directory ]] || rm -rf -- "$stage_directory"
    if [[ "$transaction_complete" = true || "$mutation_started" = false ]]; then
        exit "$action31_status"
    fi
    printf '%s_%s_rollback_started=true\n' "$prefix" "$node_token" >&2
    set +e
    restore_backup || action31_recovery_failed=true
    set -e
    if [[ "$action31_recovery_failed" = true ]]; then
        printf '%s_%s_manual_intervention_required=true\n' "$prefix" "$node_token" >&2
        exit 125
    fi
    printf '%s_%s_rollback_complete=true\n' "$prefix" "$node_token" >&2
    exit "$action31_status"
}
apply_candidate() {
    local action31_before_release
    local action31_staged_backup

    verify_state "$expected_legacy_sha256" || return 1
    [[ ! -e "$backup_directory" && ! -L "$backup_directory" ]] || return 1
    stage_directory=$(mktemp -d /run/caddy-env-action31.XXXXXX) || return 1
    chmod 0700 "$stage_directory" || return 1
    trap rollback_on_error EXIT INT TERM
    printf '%s' "$candidate_base64" | base64 -d >"$stage_directory/caddy-ha.candidate" || return 1
    chmod 0600 "$stage_directory/caddy-ha.candidate" || return 1
    check candidate_contract environment_contract "$stage_directory/caddy-ha.candidate" || return 1
    check candidate_caddy_validation validate_candidate_caddy "$stage_directory/caddy-ha.candidate" || return 1
    action31_before_release=$(readlink -f /etc/caddy/current) || return 1
    action31_staged_backup=$stage_directory/backup
    install -d -o root -g root -m 0700 "$action31_staged_backup" || return 1
    install -o root -g root -m 0600 "$environment_path" \
        "$action31_staged_backup/caddy-ha.before" || return 1
    printf 'before_sha256=%s\nbefore_release=%s\n' \
        "$expected_legacy_sha256" "$action31_before_release" \
        >"$action31_staged_backup/manifest" || return 1
    chmod 0600 "$action31_staged_backup/manifest" || return 1
    mv -- "$action31_staged_backup" "$backup_directory" || return 1
    mutation_started=true
    install -o root -g caddy-tls -m 0640 "$stage_directory/caddy-ha.candidate" \
        /etc/default/.caddy-ha.action31.new || return 1
    mv -fT /etc/default/.caddy-ha.action31.new "$environment_path" || return 1
    systemctl reload caddy.service || return 1
    verify_state "$candidate_sha256" || return 1
    [[ "$(readlink -f /etc/caddy/current)" = "$action31_before_release" ]] || return 1
    transaction_complete=true
    trap - EXIT INT TERM
    rm -rf -- "$stage_directory"
    printf '%s_%s_apply_complete=true\n' "$prefix" "$node_token"
}
self_test() {
    stage_directory=$(mktemp -d /tmp/caddy-env-action31-selftest.XXXXXX) || return 1
    trap 'rm -rf -- "$stage_directory"' EXIT INT TERM
    printf '%s' "$candidate_base64" | base64 -d >"$stage_directory/candidate"
    environment_contract "$stage_directory/candidate"
    printf '%s_%s_self_test_complete=true\n' "$prefix" "$node_token"
}

configure_node "$role"
case "$mode" in
    --self-test) self_test ;;
    --apply) apply_candidate ;;
    --verify-current)
        verify_state "$candidate_sha256"
        printf '%s_%s_verify_current_complete=true\n' "$prefix" "$node_token"
        ;;
    --verify-legacy)
        verify_state "$expected_legacy_sha256"
        printf '%s_%s_verify_legacy_complete=true\n' "$prefix" "$node_token"
        ;;
    --rollback-committed)
        rollback_committed
        printf '%s_%s_rollback_committed_complete=true\n' "$prefix" "$node_token"
        ;;
    *) exit 64 ;;
esac
