#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20k
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly health_helper=/usr/local/libexec/check-caddy.sh
readonly rollback_root=/var/backups/caddy-ha
readonly health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly node_a_source_sha256=6f5a58ca8fd39a1218de6fc964f54aef69f374351c0727bbb0fabf899a80ef39
readonly node_a_candidate_sha256=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
readonly node_a_main_sha256=357eb09c628fa3b78efcaacf53278ab09a6574b991820632ee3ec2614265d8e2
readonly node_b_source_sha256=7b42e1296bd06768b96e1097fe1e6546fcdc9fb4e249eaa7b0bbaffa85b3b270
readonly node_b_candidate_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
readonly node_b_main_sha256=8b260315628888c937c6f7eaf21f63e73eb52cfd9cd6e9c0d9d90fa9cf9fbd3f
readonly vip_ipv4_cidr=10.1.0.56/22
readonly vip_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128

action20k_node_role=
action20k_expected_hostname=
action20k_source_sha256=
action20k_candidate_sha256=
action20k_main_sha256=
action20k_expected_vrrp_state=
action20k_expected_caddy_count=
action20k_expected_dns_count=
action20k_transaction_root=
action20k_candidate=
action20k_roundtrip=
action20k_install_stage=
action20k_backup_directory=
action20k_mutation_started=false
action20k_transaction_complete=false
action20k_keepalived_pid_before=
action20k_keepalived_restarts_before=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
address_count() {
    local action20k_address_family=$1
    local action20k_expected_cidr=$2

    ip -o "-$action20k_address_family" address show dev eth0 2>/dev/null |
        awk -v expected="$action20k_expected_cidr" '$4 == expected { count++ }
            END { print count + 0 }'
}
record_check() {
    local action20k_check_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20k_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20k_check_label" >&2
    return 1
}
expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact fragment_regular \
        fragment_not_symlink fragment_metadata source_hash_exact \
        main_regular main_not_symlink main_hash_exact health_hash_exact \
        keepalived_active caddy_active lighttpd_active keepalived_pid_numeric \
        keepalived_restarts_numeric caddy_ipv4_count_pre caddy_ipv6_count_pre \
        dns_ipv4_count_pre dns_ipv6_count_pre vrrp_state_pre \
        source_unicast_ttl_absent source_hoplimit_absent source_peer_ttl_count \
        candidate_created candidate_metadata candidate_hash_exact \
        candidate_unicast_ttl_count candidate_ipv4_adjacency \
        candidate_ipv6_adjacency candidate_peer_ttl_count \
        candidate_hoplimit_absent candidate_roundtrip_exact \
        rollback_directory_metadata backup_fragment_metadata \
        backup_fragment_hash backup_manifest_metadata backup_manifest_lines \
        backup_manifest_action backup_manifest_node backup_manifest_source \
        backup_manifest_candidate mutation_started installed_metadata \
        installed_hash_exact installed_unicast_ttl_count main_hash_unchanged \
        health_hash_unchanged keepalived_active_post caddy_active_post \
        lighttpd_active_post keepalived_pid_unchanged \
        keepalived_restarts_unchanged caddy_ipv4_count_post \
        caddy_ipv6_count_post dns_ipv4_count_post dns_ipv6_count_post \
        vrrp_state_post
}
configure_node() {
    local action20k_configure_role=$1

    case "$action20k_configure_role" in
        node-a)
            action20k_expected_hostname=j1-svpihole0
            action20k_source_sha256=$node_a_source_sha256
            action20k_candidate_sha256=$node_a_candidate_sha256
            action20k_main_sha256=$node_a_main_sha256
            action20k_expected_vrrp_state=MASTER
            action20k_expected_caddy_count=1
            action20k_expected_dns_count=1
            ;;
        node-b)
            action20k_expected_hostname=j1-svpihole00
            action20k_source_sha256=$node_b_source_sha256
            action20k_candidate_sha256=$node_b_candidate_sha256
            action20k_main_sha256=$node_b_main_sha256
            action20k_expected_vrrp_state=BACKUP
            action20k_expected_caddy_count=0
            action20k_expected_dns_count=0
            ;;
        *) return 1 ;;
    esac
    action20k_node_role=$action20k_configure_role
}
build_candidate() {
    local action20k_source=$1
    local action20k_output=$2

    awk '
        { print }
        /^    unicast_src_ip[[:space:]]/ {
            print "    unicast_ttl 255"
            inserted++
        }
        END { if (inserted != 2) exit 1 }
    ' "$action20k_source" >"$action20k_output"
}
build_roundtrip() {
    local action20k_input=$1
    local action20k_output=$2

    awk '$0 != "    unicast_ttl 255" { print }' \
        "$action20k_input" >"$action20k_output"
}
validate_candidate_contract() {
    local action20k_contract_candidate=$1
    local action20k_contract_source=$2

    record_check candidate_created test -f "$action20k_contract_candidate" || return 1
    record_check candidate_metadata test \
        "$(stat -c '%U:%G:%a' "$action20k_contract_candidate")" = root:root:600 || return 1
    record_check candidate_hash_exact test \
        "$(file_hash "$action20k_contract_candidate")" = "$action20k_candidate_sha256" || return 1
    record_check candidate_unicast_ttl_count test \
        "$(grep -Fxc '    unicast_ttl 255' "$action20k_contract_candidate")" -eq 2 || return 1
    # The dollar expression belongs to the literal awk program.
    # shellcheck disable=SC2016
    record_check candidate_ipv4_adjacency awk '
        /vrrp_instance CADDY_IPV4 \{/ { in_instance=1 }
        /vrrp_instance CADDY_IPV6 \{/ { in_instance=0 }
        in_instance && /unicast_src_ip/ {
            getline
            if ($0 == "    unicast_ttl 255") found++
        }
        END { exit(found == 1 ? 0 : 1) }
    ' "$action20k_contract_candidate" || return 1
    # The dollar expression belongs to the literal awk program.
    # shellcheck disable=SC2016
    record_check candidate_ipv6_adjacency awk '
        /vrrp_instance CADDY_IPV6 \{/ { in_instance=1 }
        in_instance && /unicast_src_ip/ {
            getline
            if ($0 == "    unicast_ttl 255") found++
        }
        END { exit(found == 1 ? 0 : 1) }
    ' "$action20k_contract_candidate" || return 1
    record_check candidate_peer_ttl_count test \
        "$(grep -Ec 'min_ttl 255 max_ttl 255$' "$action20k_contract_candidate")" -eq 2 || return 1
    record_check candidate_hoplimit_absent test \
        "$(grep -Ec '^[[:space:]]*hoplimit([[:space:]]|$)' "$action20k_contract_candidate" || true)" -eq 0 || return 1
    build_roundtrip "$action20k_contract_candidate" "$action20k_roundtrip" || return 1
    chmod 0600 "$action20k_roundtrip" || return 1
    record_check candidate_roundtrip_exact cmp -s \
        "$action20k_contract_source" "$action20k_roundtrip" || return 1
}
validate_live_prestate() {
    record_check identity_root test "$(id -u)" -eq 0 || return 1
    record_check working_directory_root test "$(pwd -P)" = / || return 1
    record_check hostname_exact test "$(hostname)" = "$action20k_expected_hostname" || return 1
    record_check fragment_regular test -f "$fragment" || return 1
    record_check fragment_not_symlink test ! -L "$fragment" || return 1
    record_check fragment_metadata test \
        "$(stat -c '%U:%G:%a' "$fragment")" = root:root:644 || return 1
    record_check source_hash_exact test \
        "$(file_hash "$fragment")" = "$action20k_source_sha256" || return 1
    record_check main_regular test -f "$main_configuration" || return 1
    record_check main_not_symlink test ! -L "$main_configuration" || return 1
    record_check main_hash_exact test \
        "$(file_hash "$main_configuration")" = "$action20k_main_sha256" || return 1
    record_check health_hash_exact test \
        "$(file_hash "$health_helper")" = "$health_sha256" || return 1
    record_check keepalived_active systemctl is-active --quiet keepalived.service || return 1
    record_check caddy_active systemctl is-active --quiet caddy.service || return 1
    record_check lighttpd_active systemctl is-active --quiet lighttpd.service || return 1
    action20k_keepalived_pid_before=$(systemctl show keepalived.service --property MainPID --value) || return 1
    record_check keepalived_pid_numeric test "$action20k_keepalived_pid_before" -gt 0 || return 1
    action20k_keepalived_restarts_before=$(systemctl show keepalived.service --property NRestarts --value) || return 1
    record_check keepalived_restarts_numeric test \
        "$action20k_keepalived_restarts_before" -ge 0 || return 1
    record_check caddy_ipv4_count_pre test \
        "$(address_count 4 "$vip_ipv4_cidr")" -eq "$action20k_expected_caddy_count" || return 1
    record_check caddy_ipv6_count_pre test \
        "$(address_count 6 "$vip_ipv6_cidr")" -eq "$action20k_expected_caddy_count" || return 1
    record_check dns_ipv4_count_pre test \
        "$(address_count 4 "$dns_ipv4_cidr")" -eq "$action20k_expected_dns_count" || return 1
    record_check dns_ipv6_count_pre test \
        "$(address_count 6 "$dns_ipv6_cidr")" -eq "$action20k_expected_dns_count" || return 1
    record_check vrrp_state_pre test \
        "$(sed -n '1p' /run/caddy-ha/vrrp-state)" = "$action20k_expected_vrrp_state" || return 1
    record_check source_unicast_ttl_absent test \
        "$(grep -Fxc '    unicast_ttl 255' "$fragment" || true)" -eq 0 || return 1
    record_check source_hoplimit_absent test \
        "$(grep -Ec '^[[:space:]]*hoplimit([[:space:]]|$)' "$fragment" || true)" -eq 0 || return 1
    record_check source_peer_ttl_count test \
        "$(grep -Ec 'min_ttl 255 max_ttl 255$' "$fragment")" -eq 2 || return 1
}
create_backup() {
    install -d -o root -g root -m 0700 "$rollback_root" || return 1
    action20k_backup_directory=$(mktemp -d \
        "$rollback_root/action20k-${action20k_node_role}-unicast-ttl.XXXXXX") || return 1
    chown root:root "$action20k_backup_directory" || return 1
    chmod 0700 "$action20k_backup_directory" || return 1
    install -o root -g root -m 0600 "$fragment" \
        "$action20k_backup_directory/caddy-ha.conf.before" || return 1
    {
        printf 'action=20k\n'
        printf 'node=%s\n' "$action20k_node_role"
        printf 'source_sha256=%s\n' "$action20k_source_sha256"
        printf 'candidate_sha256=%s\n' "$action20k_candidate_sha256"
    } >"$action20k_backup_directory/manifest" || return 1
    chown root:root "$action20k_backup_directory/manifest" || return 1
    chmod 0600 "$action20k_backup_directory/manifest" || return 1
    record_check rollback_directory_metadata test \
        "$(stat -c '%U:%G:%a' "$action20k_backup_directory")" = root:root:700 || return 1
    record_check backup_fragment_metadata test \
        "$(stat -c '%U:%G:%a' "$action20k_backup_directory/caddy-ha.conf.before")" = root:root:600 || return 1
    record_check backup_fragment_hash test \
        "$(file_hash "$action20k_backup_directory/caddy-ha.conf.before")" = "$action20k_source_sha256" || return 1
    record_check backup_manifest_metadata test \
        "$(stat -c '%U:%G:%a' "$action20k_backup_directory/manifest")" = root:root:600 || return 1
    record_check backup_manifest_lines test \
        "$(wc -l <"$action20k_backup_directory/manifest")" -eq 4 || return 1
    record_check backup_manifest_action grep -Fqx action=20k \
        "$action20k_backup_directory/manifest" || return 1
    record_check backup_manifest_node grep -Fqx \
        "node=$action20k_node_role" "$action20k_backup_directory/manifest" || return 1
    record_check backup_manifest_source grep -Fqx \
        "source_sha256=$action20k_source_sha256" "$action20k_backup_directory/manifest" || return 1
    record_check backup_manifest_candidate grep -Fqx \
        "candidate_sha256=$action20k_candidate_sha256" "$action20k_backup_directory/manifest" || return 1
    printf '%s_backup_path=%s\n' "$prefix" "$action20k_backup_directory"
}
validate_live_poststate() {
    record_check installed_metadata test \
        "$(stat -c '%U:%G:%a' "$fragment")" = root:root:644 || return 1
    record_check installed_hash_exact test \
        "$(file_hash "$fragment")" = "$action20k_candidate_sha256" || return 1
    record_check installed_unicast_ttl_count test \
        "$(grep -Fxc '    unicast_ttl 255' "$fragment")" -eq 2 || return 1
    record_check main_hash_unchanged test \
        "$(file_hash "$main_configuration")" = "$action20k_main_sha256" || return 1
    record_check health_hash_unchanged test \
        "$(file_hash "$health_helper")" = "$health_sha256" || return 1
    record_check keepalived_active_post systemctl is-active --quiet keepalived.service || return 1
    record_check caddy_active_post systemctl is-active --quiet caddy.service || return 1
    record_check lighttpd_active_post systemctl is-active --quiet lighttpd.service || return 1
    record_check keepalived_pid_unchanged test \
        "$(systemctl show keepalived.service --property MainPID --value)" = \
        "$action20k_keepalived_pid_before" || return 1
    record_check keepalived_restarts_unchanged test \
        "$(systemctl show keepalived.service --property NRestarts --value)" = \
        "$action20k_keepalived_restarts_before" || return 1
    record_check caddy_ipv4_count_post test \
        "$(address_count 4 "$vip_ipv4_cidr")" -eq "$action20k_expected_caddy_count" || return 1
    record_check caddy_ipv6_count_post test \
        "$(address_count 6 "$vip_ipv6_cidr")" -eq "$action20k_expected_caddy_count" || return 1
    record_check dns_ipv4_count_post test \
        "$(address_count 4 "$dns_ipv4_cidr")" -eq "$action20k_expected_dns_count" || return 1
    record_check dns_ipv6_count_post test \
        "$(address_count 6 "$dns_ipv6_cidr")" -eq "$action20k_expected_dns_count" || return 1
    record_check vrrp_state_post test \
        "$(sed -n '1p' /run/caddy-ha/vrrp-state)" = "$action20k_expected_vrrp_state" || return 1
}
rollback() {
    local action20k_rollback_status=0

    if [[ "$action20k_mutation_started" = true && "$action20k_transaction_complete" != true ]]; then
        if [[ -n "$action20k_backup_directory" &&
            -f "$action20k_backup_directory/caddy-ha.conf.before" ]]; then
            install -o root -g root -m 0644 \
                "$action20k_backup_directory/caddy-ha.conf.before" \
                "$action20k_install_stage" || action20k_rollback_status=1
            if [[ "$action20k_rollback_status" -eq 0 ]]; then
                mv -fT "$action20k_install_stage" "$fragment" || action20k_rollback_status=1
            fi
        else
            action20k_rollback_status=1
        fi
        if [[ "$action20k_rollback_status" -eq 0 &&
            "$(file_hash "$fragment" 2>/dev/null || true)" = "$action20k_source_sha256" ]]; then
            printf '%s_rollback_complete=true\n' "$prefix" >&2
        else
            printf '%s_rollback_complete=false\n' "$prefix" >&2
            return 125
        fi
    fi
}
cleanup() {
    local action20k_cleanup_status=$?

    trap - EXIT INT TERM
    rollback || action20k_cleanup_status=125
    if [[ -n "$action20k_install_stage" && -e "$action20k_install_stage" ]]; then
        rm -f -- "$action20k_install_stage"
    fi
    if [[ "$action20k_mutation_started" != true &&
        "$action20k_transaction_complete" != true &&
        -n "$action20k_backup_directory" &&
        -d "$action20k_backup_directory" ]]; then
        rm -rf -- "$action20k_backup_directory"
    fi
    if [[ -n "$action20k_transaction_root" && -d "$action20k_transaction_root" ]]; then
        rm -rf -- "$action20k_transaction_root"
    fi
    exit "$action20k_cleanup_status"
}
run_fixture_test() {
    local action20k_fixture_root
    local action20k_fixture_source
    local action20k_fixture_candidate
    local action20k_fixture_roundtrip

    action20k_fixture_root=$(mktemp -d /tmp/caddy-action20k-fixture.XXXXXX) || return 1
    trap 'rm -rf -- "$action20k_fixture_root"' RETURN
    action20k_fixture_source=$action20k_fixture_root/source
    action20k_fixture_candidate=$action20k_fixture_root/candidate
    action20k_fixture_roundtrip=$action20k_fixture_root/roundtrip
    printf '%s\n' \
        'vrrp_instance CADDY_IPV4 {' \
        '    unicast_src_ip 10.1.0.53' \
        '}' \
        'vrrp_instance CADDY_IPV6 {' \
        '    unicast_src_ip fd36:5aa8:6971:1::53' \
        '}' >"$action20k_fixture_source"
    build_candidate "$action20k_fixture_source" "$action20k_fixture_candidate" || return 1
    [[ "$(grep -Fxc '    unicast_ttl 255' "$action20k_fixture_candidate")" -eq 2 ]] || return 1
    build_roundtrip "$action20k_fixture_candidate" "$action20k_fixture_roundtrip" || return 1
    cmp -s "$action20k_fixture_source" "$action20k_fixture_roundtrip" || return 1
    printf '%s_fixture_test_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]] || exit 64
        expected_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$(expected_checks | wc -l)" -eq 58 ]]
        [[ "$(expected_checks | LC_ALL=C sort -u | wc -l)" -eq 58 ]]
        [[ "$(expected_checks | grep -Evc '^[a-z0-9_]+$')" -eq 0 ]]
        run_fixture_test
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --node)
        [[ $# -eq 2 ]] || exit 64
        configure_node "$2" || exit 64
        ;;
    *)
        printf 'Usage: %s --expected-checks|--self-test|--node node-a|node-b\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

action20k_transaction_root=$(mktemp -d /run/caddy-action20k.XXXXXX)
readonly action20k_transaction_root
trap cleanup EXIT INT TERM
chown root:root "$action20k_transaction_root"
chmod 0700 "$action20k_transaction_root"
action20k_candidate=$action20k_transaction_root/caddy-ha.conf.candidate
action20k_roundtrip=$action20k_transaction_root/caddy-ha.conf.roundtrip
readonly action20k_candidate action20k_roundtrip

validate_live_prestate
build_candidate "$fragment" "$action20k_candidate"
chown root:root "$action20k_candidate"
chmod 0600 "$action20k_candidate"
validate_candidate_contract "$action20k_candidate" "$fragment"
create_backup
action20k_install_stage=$(mktemp \
    /etc/keepalived/conf.d/.caddy-ha.conf.action20k.XXXXXX)
action20k_mutation_started=true
record_check mutation_started test "$action20k_mutation_started" = true
install -o root -g root -m 0644 "$action20k_candidate" "$action20k_install_stage"
mv -fT "$action20k_install_stage" "$fragment"
validate_live_poststate
action20k_transaction_complete=true
printf '%s_node=%s\n' "$prefix" "$action20k_node_role"
printf '%s_keepalived_reload=false\n' "$prefix"
printf '%s_keepalived_restart=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_vrrp_transition=false\n' "$prefix"
printf '%s_vip_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
