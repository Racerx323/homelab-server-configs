#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28m
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly caddy_fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly include_line='include /etc/keepalived/conf.d/caddy-ha.conf'
readonly baseline_main_sha256=8fc9dcf8e079b7131f86a58038ae5543804a5158a02d53a4614452de212ce47c
readonly retired_main_sha256=6162cfb9d83f7e524db1df6a3b041ced90a7639fceaf28eacf713270c2a66a65
readonly fragment_sha256=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
readonly backup_directory=/var/backups/caddy-ha/action28m-node-a-caddy-service-restoration
readonly interface=eth0
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly node_a_fqdn=pihole0.local.theama.co

expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact main_regular main_not_symlink \
        main_metadata main_hash_baseline include_once include_terminal fragment_regular \
        fragment_not_symlink fragment_metadata fragment_hash_exact backup_absent \
        stage_residue_absent keepalived_active_before lighttpd_active_before \
        caddy_inactive_before ipv4_query_before_status_zero ipv6_query_before_status_zero \
        dns_ipv4_owned_before dns_ipv6_owned_before caddy_ipv4_absent_before \
        caddy_ipv6_absent_before candidate_hash_exact candidate_include_absent \
        candidate_dns_instances_retained backup_created backup_main_hash_exact \
        backup_fragment_hash_exact candidate_installed main_hash_retired \
        main_include_absent keepalived_reload_status_zero keepalived_reload_stdout_safe \
        keepalived_reload_stderr_safe keepalived_active_after_reload \
        ipv4_query_after_reload_status_zero ipv6_query_after_reload_status_zero \
        dns_ipv4_owned_after_reload dns_ipv6_owned_after_reload \
        caddy_ipv4_absent_after_reload caddy_ipv6_absent_after_reload \
        caddy_start_status_zero caddy_start_stdout_safe caddy_start_stderr_safe \
        caddy_active_after_start localhost_health_status_204 node_a_ipv4_ui_status_200 \
        node_a_ipv6_ui_status_200 ipv4_query_final_status_zero \
        ipv6_query_final_status_zero dns_ipv4_owned_final dns_ipv6_owned_final \
        caddy_ipv4_absent_final caddy_ipv6_absent_final fragment_still_exact \
        transaction_stage_removed
}

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
address_query() { ip -o "-$1" address show dev "$interface"; }
address_count() {
    local action28m_family=$1
    local action28m_cidr=$2

    address_query "$action28m_family" |
        awk -v expected="$action28m_cidr" '$4 == expected { count++ } END { print count + 0 }'
}
safe_stream() {
    local action28m_stream=$1

    [[ "$(wc -c <"$action28m_stream")" -le 131072 ]] || return 1
    [[ "$(line_count "$action28m_stream")" -le 1024 ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28m_stream" >/dev/null || return 1
}
emit_stream() {
    local action28m_label=$1
    local action28m_stream=$2

    printf '%s_value_%s_bytes=%s\n' "$prefix" "$action28m_label" "$(wc -c <"$action28m_stream")"
    printf '%s_value_%s_lines=%s\n' "$prefix" "$action28m_label" "$(line_count "$action28m_stream")"
    printf '%s_value_%s_sha256=%s\n' "$prefix" "$action28m_label" "$(file_hash "$action28m_stream")"
    if safe_stream "$action28m_stream"; then
        printf '%s_value_%s_classification=bounded_safe\n' "$prefix" "$action28m_label"
        if [[ -s "$action28m_stream" ]]; then
            printf '%s_value_%s_begin\n' "$prefix" "$action28m_label"
            sed "s/^/${prefix}_value_${action28m_label}=/" "$action28m_stream"
            printf '%s_value_%s_end\n' "$prefix" "$action28m_label"
        else
            printf '%s_value_%s_content=empty\n' "$prefix" "$action28m_label"
        fi
        return 0
    fi
    printf '%s_value_%s_classification=unsafe_retained\n' "$prefix" "$action28m_label"
    return 1
}
check() {
    local action28m_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28m_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28m_label"
    return 1
}
require_check() {
    local action28m_required_label=$1

    shift
    check "$action28m_required_label" "$@" || {
        first_failure=$action28m_required_label
        return 1
    }
}
candidate_contract() {
    local action28m_candidate_file=$1

    [[ "$(file_hash "$action28m_candidate_file")" = "$retired_main_sha256" ]] || return 1
    [[ "$(grep -Fxc "$include_line" "$action28m_candidate_file" || true)" -eq 0 ]] || return 1
    [[ "$(grep -Fxc 'vrrp_instance PIHOLE_IPV4 {' "$action28m_candidate_file" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'vrrp_instance PIHOLE_IPV6 {' "$action28m_candidate_file" || true)" -eq 1 ]]
}
https_status() {
    local action28m_fqdn=$1
    local action28m_address=$2
    local action28m_path=$3

    curl --noproxy '*' --insecure --silent --show-error --location --max-redirs 3 \
        --proto-redir '=https' --connect-timeout 3 --max-time 10 \
        --resolve "${action28m_fqdn}:443:${action28m_address}" \
        --output /dev/null --write-out '%{http_code}' \
        "https://${action28m_fqdn}${action28m_path}"
}
rollback() {
    local action28m_rollback_status=0

    rollback_invoked=true
    if [[ "$caddy_start_attempted" = true ]]; then
        systemctl stop caddy.service >"$capture_directory/rollback-caddy.stdout" \
            2>"$capture_directory/rollback-caddy.stderr" || action28m_rollback_status=125
    fi
    if [[ "$main_installed" = true && -f "$backup_directory/keepalived.conf" ]]; then
        install -o root -g root -m 0644 "$backup_directory/keepalived.conf" \
            "$main_configuration" || action28m_rollback_status=125
        systemctl reload keepalived.service >"$capture_directory/rollback-keepalived.stdout" \
            2>"$capture_directory/rollback-keepalived.stderr" || action28m_rollback_status=125
    fi
    [[ "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$baseline_main_sha256" ]] || action28m_rollback_status=125
    [[ "$(systemctl is-active caddy.service 2>/dev/null || true)" = inactive ]] || action28m_rollback_status=125
    [[ "$(systemctl is-active keepalived.service 2>/dev/null || true)" = active ]] || action28m_rollback_status=125
    [[ "$(address_count 4 "$dns_ipv4_cidr" 2>/dev/null || true)" -eq 1 ]] || action28m_rollback_status=125
    [[ "$(address_count 6 "$dns_ipv6_cidr" 2>/dev/null || true)" -eq 1 ]] || action28m_rollback_status=125
    [[ "$(address_count 4 "$caddy_ipv4_cidr" 2>/dev/null || true)" -eq 0 ]] || action28m_rollback_status=125
    [[ "$(address_count 6 "$caddy_ipv6_cidr" 2>/dev/null || true)" -eq 0 ]] || action28m_rollback_status=125
    printf '%s_rollback_status=%s\n' "$prefix" "$action28m_rollback_status"
    return "$action28m_rollback_status"
}
cleanup() {
    local action28m_cleanup_status=$?

    trap - EXIT ERR HUP INT TERM
    if [[ "$action28m_cleanup_status" -ne 0 && "$mutation_started" = true ]]; then
        rollback || action28m_cleanup_status=125
    fi
    [[ -z "$stage_directory" || ! -d "$stage_directory" ]] || rm -rf -- "$stage_directory"
    printf '%s_value_first_failure=%s\n' "$prefix" "$first_failure"
    printf '%s_rollback_invoked=%s\n' "$prefix" "$rollback_invoked"
    printf '%s_node_b_contacted=false\n' "$prefix"
    printf '%s_keepalived_reload_count=%s\n' "$prefix" "$keepalived_reload_count"
    printf '%s_caddy_start_count=%s\n' "$prefix" "$caddy_start_count"
    if [[ "$action28m_cleanup_status" -eq 0 ]]; then
        printf '%s_acceptance=true\n' "$prefix"
    else
        printf '%s_acceptance=false\n' "$prefix"
    fi
    exit "$action28m_cleanup_status"
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]]
        expected_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        labels=$(expected_checks)
        [[ "$(printf '%s\n' "$labels" | wc -l)" -eq "$(printf '%s\n' "$labels" | LC_ALL=C sort -u | wc -l)" ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --candidate-test)
        [[ $# -eq 2 ]]
        candidate_contract "$2"
        printf '%s_candidate_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") ;;
    *) exit 64 ;;
esac

first_failure=none
stage_directory=
capture_directory=
mutation_started=false
main_installed=false
caddy_start_attempted=false
rollback_invoked=false
keepalived_reload_count=0
caddy_start_count=0
trap cleanup EXIT ERR HUP INT TERM

require_check identity_root test "$(id -u)" -eq 0
require_check working_directory_root test "$(pwd -P)" = /
require_check hostname_exact test "$(hostname)" = j1-svpihole0
require_check main_regular test -f "$main_configuration"
require_check main_not_symlink test ! -L "$main_configuration"
require_check main_metadata test "$(stat -c '%U:%G:%a' "$main_configuration")" = root:root:644
require_check main_hash_baseline test "$(file_hash "$main_configuration")" = "$baseline_main_sha256"
require_check include_once test "$(grep -Fxc "$include_line" "$main_configuration")" -eq 1
require_check include_terminal test "$(tail -n 1 "$main_configuration")" = "$include_line"
require_check fragment_regular test -f "$caddy_fragment"
require_check fragment_not_symlink test ! -L "$caddy_fragment"
require_check fragment_metadata test "$(stat -c '%U:%G:%a' "$caddy_fragment")" = root:root:644
require_check fragment_hash_exact test "$(file_hash "$caddy_fragment")" = "$fragment_sha256"
require_check backup_absent test ! -e "$backup_directory"
require_check stage_residue_absent test -z "$(find /run -maxdepth 1 -name 'caddy-action28m-*' -print -quit 2>/dev/null)"
require_check keepalived_active_before systemctl is-active --quiet keepalived.service
require_check lighttpd_active_before systemctl is-active --quiet lighttpd.service
require_check caddy_inactive_before test "$(systemctl is-active caddy.service 2>/dev/null || true)" = inactive
ipv4_status=0
address_query 4 >/dev/null 2>&1 || ipv4_status=$?
require_check ipv4_query_before_status_zero test "$ipv4_status" -eq 0
ipv6_status=0
address_query 6 >/dev/null 2>&1 || ipv6_status=$?
require_check ipv6_query_before_status_zero test "$ipv6_status" -eq 0
require_check dns_ipv4_owned_before test "$(address_count 4 "$dns_ipv4_cidr")" -eq 1
require_check dns_ipv6_owned_before test "$(address_count 6 "$dns_ipv6_cidr")" -eq 1
require_check caddy_ipv4_absent_before test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0
require_check caddy_ipv6_absent_before test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0

stage_directory=$(mktemp -d /run/caddy-action28m-stage.XXXXXX)
chmod 0700 "$stage_directory"
capture_directory=$stage_directory/capture
install -d -o root -g root -m 0700 "$capture_directory"
candidate=$stage_directory/keepalived.conf
head -n -2 "$main_configuration" >"$candidate"
chmod 0600 "$candidate"
require_check candidate_hash_exact test "$(file_hash "$candidate")" = "$retired_main_sha256"
require_check candidate_include_absent test "$(grep -Fxc "$include_line" "$candidate" || true)" -eq 0
require_check candidate_dns_instances_retained candidate_contract "$candidate"

install -d -o root -g root -m 0700 "$backup_directory"
install -o root -g root -m 0600 "$main_configuration" "$backup_directory/keepalived.conf"
install -o root -g root -m 0600 "$caddy_fragment" "$backup_directory/caddy-ha.conf"
printf 'action=28m\nbaseline_main_sha256=%s\nfragment_sha256=%s\nretired_main_sha256=%s\n' \
    "$baseline_main_sha256" "$fragment_sha256" "$retired_main_sha256" \
    >"$backup_directory/manifest"
chmod 0600 "$backup_directory/manifest"
require_check backup_created test -d "$backup_directory"
require_check backup_main_hash_exact test "$(file_hash "$backup_directory/keepalived.conf")" = "$baseline_main_sha256"
require_check backup_fragment_hash_exact test "$(file_hash "$backup_directory/caddy-ha.conf")" = "$fragment_sha256"

mutation_started=true
install -o root -g root -m 0644 "$candidate" "$main_configuration"
main_installed=true
require_check candidate_installed test -f "$main_configuration"
require_check main_hash_retired test "$(file_hash "$main_configuration")" = "$retired_main_sha256"
require_check main_include_absent test "$(grep -Fxc "$include_line" "$main_configuration" || true)" -eq 0

reload_stdout=$capture_directory/keepalived-reload.stdout
reload_stderr=$capture_directory/keepalived-reload.stderr
: >"$reload_stdout"
: >"$reload_stderr"
chmod 0600 "$reload_stdout" "$reload_stderr"
reload_status=0
keepalived_reload_count=1
systemctl reload keepalived.service >"$reload_stdout" 2>"$reload_stderr" || reload_status=$?
emit_stream keepalived_reload_stdout "$reload_stdout"
emit_stream keepalived_reload_stderr "$reload_stderr"
require_check keepalived_reload_status_zero test "$reload_status" -eq 0
require_check keepalived_reload_stdout_safe safe_stream "$reload_stdout"
require_check keepalived_reload_stderr_safe safe_stream "$reload_stderr"
require_check keepalived_active_after_reload systemctl is-active --quiet keepalived.service
sleep 3
ipv4_status=0
address_query 4 >/dev/null 2>&1 || ipv4_status=$?
require_check ipv4_query_after_reload_status_zero test "$ipv4_status" -eq 0
ipv6_status=0
address_query 6 >/dev/null 2>&1 || ipv6_status=$?
require_check ipv6_query_after_reload_status_zero test "$ipv6_status" -eq 0
require_check dns_ipv4_owned_after_reload test "$(address_count 4 "$dns_ipv4_cidr")" -eq 1
require_check dns_ipv6_owned_after_reload test "$(address_count 6 "$dns_ipv6_cidr")" -eq 1
require_check caddy_ipv4_absent_after_reload test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0
require_check caddy_ipv6_absent_after_reload test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0

start_stdout=$capture_directory/caddy-start.stdout
start_stderr=$capture_directory/caddy-start.stderr
: >"$start_stdout"
: >"$start_stderr"
chmod 0600 "$start_stdout" "$start_stderr"
start_status=0
caddy_start_attempted=true
caddy_start_count=1
systemctl start caddy.service >"$start_stdout" 2>"$start_stderr" || start_status=$?
emit_stream caddy_start_stdout "$start_stdout"
emit_stream caddy_start_stderr "$start_stderr"
require_check caddy_start_status_zero test "$start_status" -eq 0
require_check caddy_start_stdout_safe safe_stream "$start_stdout"
require_check caddy_start_stderr_safe safe_stream "$start_stderr"
require_check caddy_active_after_start systemctl is-active --quiet caddy.service
require_check localhost_health_status_204 test "$(https_status localhost 127.0.0.1 /)" = 204
require_check node_a_ipv4_ui_status_200 test "$(https_status "$node_a_fqdn" 10.1.0.53 /admin/)" = 200
require_check node_a_ipv6_ui_status_200 test \
    "$(https_status "$node_a_fqdn" '[fd36:5aa8:6971:1::53]' /admin/)" = 200
ipv4_status=0
address_query 4 >/dev/null 2>&1 || ipv4_status=$?
require_check ipv4_query_final_status_zero test "$ipv4_status" -eq 0
ipv6_status=0
address_query 6 >/dev/null 2>&1 || ipv6_status=$?
require_check ipv6_query_final_status_zero test "$ipv6_status" -eq 0
require_check dns_ipv4_owned_final test "$(address_count 4 "$dns_ipv4_cidr")" -eq 1
require_check dns_ipv6_owned_final test "$(address_count 6 "$dns_ipv6_cidr")" -eq 1
require_check caddy_ipv4_absent_final test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0
require_check caddy_ipv6_absent_final test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0
require_check fragment_still_exact test "$(file_hash "$caddy_fragment")" = "$fragment_sha256"
rm -rf -- "$stage_directory"
stage_directory=
require_check transaction_stage_removed test -z "$(find /run -maxdepth 1 -name 'caddy-action28m-*' -print -quit 2>/dev/null)"
mutation_started=false
printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
printf '%s_value_backup_directory=%s\n' "$prefix" "$backup_directory"
printf '%s_value_baseline_main_sha256=%s\n' "$prefix" "$baseline_main_sha256"
printf '%s_value_retired_main_sha256=%s\n' "$prefix" "$retired_main_sha256"
printf '%s_value_fragment_sha256=%s\n' "$prefix" "$fragment_sha256"
