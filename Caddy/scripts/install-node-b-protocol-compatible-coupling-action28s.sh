#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28s_node_b
readonly expected_hostname=j1-svpihole00
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly accepted_main_sha256=9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148
readonly candidate_sha256=034ee9c45acaca4e48e2faeda24cd371e945bdb52a117b5871403958ab36794c
readonly fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
readonly backup_directory=/var/backups/caddy-ha/action28s-node-b-protocol-compatible-coupling
readonly backup_main=$backup_directory/keepalived.conf.before
readonly backup_manifest=$backup_directory/manifest
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/100/IPv4
readonly ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/101/IPv6
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=8192

transaction_root=
source_configuration=
install_stage=
mutation_started=false
transaction_complete=false

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact \
        main_regular main_not_symlink main_metadata main_hash_accepted \
        main_include_absent fragment_regular fragment_not_symlink fragment_hash_exact \
        source_stage_metadata source_regular source_not_symlink source_metadata \
        source_hash_exact source_contract source_advertised_count_exact \
        source_excluded_count_exact source_sender_ttl_exact source_receiver_ttl_exact \
        backup_absent transaction_residue_absent keepalived_active_before \
        caddy_active_before lighttpd_active_before ipv4_query_before_status_zero \
        ipv6_query_before_status_zero ipv4_state_before_status_zero \
        ipv6_state_before_status_zero ipv4_state_backup_before ipv6_state_backup_before \
        dns_ipv4_absent_before dns_ipv6_absent_before caddy_ipv4_absent_before \
        caddy_ipv6_absent_before backup_created backup_main_hash_exact \
        backup_manifest_exact journal_cursor_status_zero journal_cursor_present \
        install_stage_created candidate_installed candidate_renamed reload_status_zero \
        reload_stdout_safe reload_stderr_safe convergence_reached stable_sample_1 \
        stable_sample_2 stable_sample_3 stable_sample_4 stable_sample_5 \
        reload_journal_status_zero reload_journal_safe reload_journal_stderr_safe \
        reload_journal_no_fatal reload_journal_no_address_count_mismatch \
        reload_journal_no_ttl_rejection main_hash_candidate_after \
        fragment_hash_unchanged keepalived_active_after caddy_active_after \
        lighttpd_active_after ipv4_query_after_status_zero ipv6_query_after_status_zero \
        ipv4_state_after_status_zero ipv6_state_after_status_zero \
        ipv4_state_backup_after ipv6_state_backup_after dns_ipv4_absent_after \
        dns_ipv6_absent_after caddy_ipv4_absent_after caddy_ipv6_absent_after \
        node_b_ipv4_ui node_b_ipv6_ui transaction_stage_removed
}
expected_rollback_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact backup_directory_exact \
        backup_main_exact candidate_installed main_restored reload_status_zero \
        reload_stdout_safe reload_stderr_safe convergence_reached keepalived_active \
        ipv4_state_backup ipv6_state_backup dns_ipv4_absent dns_ipv6_absent \
        caddy_ipv4_absent caddy_ipv6_absent
}
record_check() {
    local action28s_node_b_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28s_node_b_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28s_node_b_label" >&2
    return 1
}
rollback_check() {
    local action28s_node_b_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_rollback_check_%s=true\n' "$prefix" "$action28s_node_b_label"
        return 0
    fi
    printf '%s_rollback_check_%s=false\n' "$prefix" "$action28s_node_b_label" >&2
    return 1
}
safe_stream() {
    local action28s_node_b_stream=$1

    [[ "$(wc -c <"$action28s_node_b_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28s_node_b_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28s_node_b_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' \
        "$action28s_node_b_stream"
}
emit_stream() {
    local action28s_node_b_label=$1
    local action28s_node_b_stream=$2

    printf '%s_capture_%s_bytes=%s\n' "$prefix" "$action28s_node_b_label" "$(wc -c <"$action28s_node_b_stream")"
    printf '%s_capture_%s_lines=%s\n' "$prefix" "$action28s_node_b_label" "$(line_count "$action28s_node_b_stream")"
    printf '%s_capture_%s_sha256=%s\n' "$prefix" "$action28s_node_b_label" "$(file_hash "$action28s_node_b_stream")"
    if safe_stream "$action28s_node_b_stream"; then
        printf '%s_capture_%s_classification=bounded_safe\n' "$prefix" "$action28s_node_b_label"
        if [[ -s "$action28s_node_b_stream" ]]; then
            printf '%s_capture_%s_begin\n' "$prefix" "$action28s_node_b_label"
            sed "s/^/${prefix}_capture_${action28s_node_b_label}_content=/" "$action28s_node_b_stream"
            printf '%s_capture_%s_end\n' "$prefix" "$action28s_node_b_label"
        else
            printf '%s_capture_%s_content=empty\n' "$prefix" "$action28s_node_b_label"
        fi
        return 0
    fi
    printf '%s_capture_%s_classification=unsafe_retained\n' "$prefix" "$action28s_node_b_label" >&2
    return 97
}
run_captured() {
    local action28s_node_b_label=$1
    local action28s_node_b_status=0

    shift
    install -m 0600 /dev/null "$transaction_root/$action28s_node_b_label.stdout"
    install -m 0600 /dev/null "$transaction_root/$action28s_node_b_label.stderr"
    "$@" >"$transaction_root/$action28s_node_b_label.stdout" \
        2>"$transaction_root/$action28s_node_b_label.stderr" || action28s_node_b_status=$?
    emit_stream "${action28s_node_b_label}_stdout" "$transaction_root/$action28s_node_b_label.stdout" || return 97
    emit_stream "${action28s_node_b_label}_stderr" "$transaction_root/$action28s_node_b_label.stderr" || return 97
    printf '%s_capture_%s_status=%s\n' "$prefix" "$action28s_node_b_label" "$action28s_node_b_status"
    [[ "$action28s_node_b_status" -eq 0 ]]
}
instance_body() {
    local action28s_node_b_instance=$1
    local action28s_node_b_file=$2

    awk -v wanted="$action28s_node_b_instance" '
        $1 == "vrrp_instance" && $2 == wanted { inside=1; depth=0 }
        inside {
            print
            depth += gsub(/\{/, "{")
            depth -= gsub(/\}/, "}")
            if (depth == 0) exit
        }
    ' "$action28s_node_b_file"
}
candidate_contract() {
    local action28s_node_b_candidate=$1
    local action28s_node_b_ipv4
    local action28s_node_b_ipv6

    action28s_node_b_ipv4=$(instance_body PIHOLE_IPV4 "$action28s_node_b_candidate") || return 1
    action28s_node_b_ipv6=$(instance_body PIHOLE_IPV6 "$action28s_node_b_candidate") || return 1
    [[ "$(grep -Fxc '    unicast_ttl 255' "$action28s_node_b_candidate" || true)" -eq 2 ]] || return 1
    [[ "$(grep -Ec 'min_ttl[[:space:]]+255[[:space:]]+max_ttl[[:space:]]+255' "$action28s_node_b_candidate" || true)" -eq 2 ]] || return 1
    [[ "$(grep -Fxc '    virtual_ipaddress {' "$action28s_node_b_candidate" || true)" -eq 2 ]] || return 1
    [[ "$(grep -Fxc '    virtual_ipaddress_excluded {' "$action28s_node_b_candidate" || true)" -eq 2 ]] || return 1
    [[ "$(grep -Fxc '        10.1.0.55/22 dev eth0' <<<"$action28s_node_b_ipv4" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc '        10.1.0.56/22 dev eth0' <<<"$action28s_node_b_ipv4" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc '        fd36:5aa8:6971:1::55/128 dev eth0 preferred_lft forever' <<<"$action28s_node_b_ipv6" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc '        fd36:5aa8:6971:1::56/128 dev eth0 preferred_lft forever' <<<"$action28s_node_b_ipv6" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'include /etc/keepalived/conf.d/caddy-ha.conf' "$action28s_node_b_candidate" || true)" -eq 0 ]] || return 1
    ! grep -Eq 'vrrp_instance CADDY_|vrrp_script check_caddy' "$action28s_node_b_candidate"
}
address_query() { ip -o "-$1" address show dev eth0; }
address_count_from() {
    local action28s_node_b_cidr=$1
    local action28s_node_b_file=$2

    awk -v expected="$action28s_node_b_cidr" '$4 == expected { count++ } END { print count + 0 }' \
        "$action28s_node_b_file"
}
dbus_state() {
    timeout 3 busctl get-property org.keepalived.Vrrp1 "$1" \
        org.keepalived.Vrrp1.Instance State
}
runtime_backup() {
    local action28s_node_b_ipv4_output
    local action28s_node_b_ipv6_output

    action28s_node_b_ipv4_output=$(address_query 4) || return 1
    action28s_node_b_ipv6_output=$(address_query 6) || return 1
    [[ "$(dbus_state "$ipv4_object")" = '(us) 1 "Backup"' ]] || return 1
    [[ "$(dbus_state "$ipv6_object")" = '(us) 1 "Backup"' ]] || return 1
    [[ "$(awk -v expected="$dns_ipv4_cidr" '$4 == expected { count++ } END { print count+0 }' <<<"$action28s_node_b_ipv4_output")" -eq 0 ]] || return 1
    [[ "$(awk -v expected="$dns_ipv6_cidr" '$4 == expected { count++ } END { print count+0 }' <<<"$action28s_node_b_ipv6_output")" -eq 0 ]] || return 1
    [[ "$(awk -v expected="$caddy_ipv4_cidr" '$4 == expected { count++ } END { print count+0 }' <<<"$action28s_node_b_ipv4_output")" -eq 0 ]] || return 1
    [[ "$(awk -v expected="$caddy_ipv6_cidr" '$4 == expected { count++ } END { print count+0 }' <<<"$action28s_node_b_ipv6_output")" -eq 0 ]]
}
wait_for_backup() {
    local _

    for _ in $(seq 1 30); do
        if systemctl is-active --quiet keepalived.service && runtime_backup; then
            return 0
        fi
        sleep 1
    done
    return 1
}
https_probe() {
    local action28s_node_b_name=$1
    local action28s_node_b_address=$2

    curl --noproxy '*' --insecure --silent --show-error --location --max-redirs 3 \
        --proto-redir '=https' --connect-timeout 3 --max-time 10 \
        --resolve "${action28s_node_b_name}:443:${action28s_node_b_address}" \
        --output /dev/null --write-out '%{http_code}' \
        "https://${action28s_node_b_name}/admin/" | grep -Fqx 200
}
create_backup() {
    install -d -o root -g root -m 0700 /var/backups/caddy-ha
    install -d -o root -g root -m 0700 "$backup_directory"
    install -o root -g root -m 0600 "$main_configuration" "$backup_main"
    {
        printf 'action=28s\n'
        printf 'node=node_b\n'
        printf 'before=%s\n' "$accepted_main_sha256"
        printf 'candidate=%s\n' "$candidate_sha256"
    } | install -o root -g root -m 0600 /dev/stdin "$backup_manifest"
}
backup_manifest_exact() {
    diff -u <(printf '%s\n' 'action=28s' 'node=node_b' \
        "before=$accepted_main_sha256" "candidate=$candidate_sha256") \
        "$backup_manifest" >/dev/null
}
perform_rollback() {
    local action28s_node_b_rollback_failed=false

    printf '%s_rollback_started=true\n' "$prefix" >&2
    rollback_check identity_root test "$(id -u)" -eq 0 || action28s_node_b_rollback_failed=true
    rollback_check working_directory_root test "$(pwd -P)" = / || action28s_node_b_rollback_failed=true
    rollback_check hostname_exact test "$(hostname)" = "$expected_hostname" || action28s_node_b_rollback_failed=true
    rollback_check backup_directory_exact backup_manifest_exact || action28s_node_b_rollback_failed=true
    rollback_check backup_main_exact test "$(file_hash "$backup_main" 2>/dev/null || true)" = "$accepted_main_sha256" || action28s_node_b_rollback_failed=true
    rollback_check candidate_installed test "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$candidate_sha256" || action28s_node_b_rollback_failed=true
    if [[ "$action28s_node_b_rollback_failed" = false ]]; then
        install_stage=$(mktemp /etc/keepalived/.keepalived.conf.action28s-rollback.XXXXXX) || action28s_node_b_rollback_failed=true
        install -o root -g root -m 0644 "$backup_main" "$install_stage" || action28s_node_b_rollback_failed=true
        mv -fT "$install_stage" "$main_configuration" || action28s_node_b_rollback_failed=true
    fi
    rollback_check main_restored test "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$accepted_main_sha256" || action28s_node_b_rollback_failed=true
    if [[ "$action28s_node_b_rollback_failed" = false ]]; then
        run_captured rollback_reload systemctl reload keepalived.service || action28s_node_b_rollback_failed=true
    fi
    rollback_check reload_status_zero test "$action28s_node_b_rollback_failed" = false || action28s_node_b_rollback_failed=true
    rollback_check reload_stdout_safe test -f "$transaction_root/rollback_reload.stdout" || action28s_node_b_rollback_failed=true
    rollback_check reload_stderr_safe test -f "$transaction_root/rollback_reload.stderr" || action28s_node_b_rollback_failed=true
    rollback_check convergence_reached wait_for_backup || action28s_node_b_rollback_failed=true
    rollback_check keepalived_active systemctl is-active --quiet keepalived.service || action28s_node_b_rollback_failed=true
    rollback_check ipv4_state_backup test "$(dbus_state "$ipv4_object" 2>/dev/null || true)" = '(us) 1 "Backup"' || action28s_node_b_rollback_failed=true
    rollback_check ipv6_state_backup test "$(dbus_state "$ipv6_object" 2>/dev/null || true)" = '(us) 1 "Backup"' || action28s_node_b_rollback_failed=true
    local action28s_node_b_rollback_ipv4=$transaction_root/rollback-ipv4
    local action28s_node_b_rollback_ipv6=$transaction_root/rollback-ipv6
    address_query 4 >"$action28s_node_b_rollback_ipv4" || action28s_node_b_rollback_failed=true
    address_query 6 >"$action28s_node_b_rollback_ipv6" || action28s_node_b_rollback_failed=true
    rollback_check dns_ipv4_absent test "$(address_count_from "$dns_ipv4_cidr" "$action28s_node_b_rollback_ipv4")" -eq 0 || action28s_node_b_rollback_failed=true
    rollback_check dns_ipv6_absent test "$(address_count_from "$dns_ipv6_cidr" "$action28s_node_b_rollback_ipv6")" -eq 0 || action28s_node_b_rollback_failed=true
    rollback_check caddy_ipv4_absent test "$(address_count_from "$caddy_ipv4_cidr" "$action28s_node_b_rollback_ipv4")" -eq 0 || action28s_node_b_rollback_failed=true
    rollback_check caddy_ipv6_absent test "$(address_count_from "$caddy_ipv6_cidr" "$action28s_node_b_rollback_ipv6")" -eq 0 || action28s_node_b_rollback_failed=true
    if [[ "$action28s_node_b_rollback_failed" = false ]]; then
        printf '%s_rollback_complete=true\n' "$prefix" >&2
        return 0
    fi
    printf '%s_rollback_complete=false\n' "$prefix" >&2
    return 125
}
cleanup() {
    local action28s_node_b_status=$?

    trap - EXIT INT TERM
    if [[ "$mutation_started" = true && "$transaction_complete" != true ]]; then
        perform_rollback || action28s_node_b_status=125
    fi
    [[ -z "$install_stage" || ! -e "$install_stage" ]] || rm -f -- "$install_stage"
    [[ -z "$transaction_root" || ! -d "$transaction_root" ]] || rm -rf -- "$transaction_root"
    exit "$action28s_node_b_status"
}
self_test() {
    [[ "$(expected_checks | wc -l)" -eq 77 ]] || return 1
    [[ "$(expected_checks | LC_ALL=C sort -u | wc -l)" -eq 77 ]] || return 1
    [[ "$(expected_rollback_checks | wc -l)" -eq 18 ]] || return 1
    [[ "$(expected_rollback_checks | LC_ALL=C sort -u | wc -l)" -eq 18 ]] || return 1
    [[ "$(expected_checks | grep -Evc '^[a-z0-9_]+$')" -eq 0 ]]
}

case "${1:-}" in
    --expected-checks)
        expected_checks
        exit 0
        ;;
    --expected-rollback-checks)
        expected_rollback_checks
        exit 0
        ;;
    --self-test)
        self_test
        exit $?
        ;;
    --stage)
        [[ $# -eq 2 && "$2" = /* ]] || exit 64
        source_configuration=$2/keepalived-pihole00.conf
        ;;
    --rollback)
        [[ $# -eq 1 ]] || exit 64
        transaction_root=$(mktemp -d /run/caddy-action28s-rollback.XXXXXX)
        readonly transaction_root
        chmod 0700 "$transaction_root"
        trap cleanup EXIT INT TERM
        perform_rollback
        transaction_complete=true
        printf '%s_rollback_acceptance=true\n' "$prefix"
        exit 0
        ;;
    *) exit 64 ;;
esac

transaction_root=$(mktemp -d /run/caddy-action28s.XXXXXX)
readonly transaction_root
chmod 0700 "$transaction_root"
trap cleanup EXIT INT TERM

record_check identity_root test "$(id -u)" -eq 0 || exit 1
record_check working_directory_root test "$(pwd -P)" = / || exit 1
record_check hostname_exact test "$(hostname)" = "$expected_hostname" || exit 1
record_check main_regular test -f "$main_configuration" || exit 1
record_check main_not_symlink test ! -L "$main_configuration" || exit 1
record_check main_metadata test "$(stat -c '%U:%G:%a' "$main_configuration" 2>/dev/null || true)" = root:root:644 || exit 1
record_check main_hash_accepted test "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$accepted_main_sha256" || exit 1
record_check main_include_absent test "$(grep -Fxc 'include /etc/keepalived/conf.d/caddy-ha.conf' "$main_configuration" 2>/dev/null || true)" -eq 0 || exit 1
record_check fragment_regular test -f "$fragment" || exit 1
record_check fragment_not_symlink test ! -L "$fragment" || exit 1
record_check fragment_hash_exact test "$(file_hash "$fragment" 2>/dev/null || true)" = "$fragment_sha256" || exit 1
record_check source_stage_metadata test "$(stat -c '%U:%G:%a' "$(dirname "$source_configuration")" 2>/dev/null || true)" = root:root:700 || exit 1
record_check source_regular test -f "$source_configuration" || exit 1
record_check source_not_symlink test ! -L "$source_configuration" || exit 1
record_check source_metadata test "$(stat -c '%U:%G:%a' "$source_configuration" 2>/dev/null || true)" = root:root:600 || exit 1
record_check source_hash_exact test "$(file_hash "$source_configuration" 2>/dev/null || true)" = "$candidate_sha256" || exit 1
record_check source_contract candidate_contract "$source_configuration" || exit 1
record_check source_advertised_count_exact test "$(grep -Fxc '    virtual_ipaddress {' "$source_configuration")" -eq 2 || exit 1
record_check source_excluded_count_exact test "$(grep -Fxc '    virtual_ipaddress_excluded {' "$source_configuration")" -eq 2 || exit 1
record_check source_sender_ttl_exact test "$(grep -Fxc '    unicast_ttl 255' "$source_configuration")" -eq 2 || exit 1
record_check source_receiver_ttl_exact test "$(grep -Ec 'min_ttl 255 max_ttl 255$' "$source_configuration")" -eq 2 || exit 1
record_check backup_absent test ! -e "$backup_directory" || exit 1
record_check transaction_residue_absent test -z "$(find /run -maxdepth 1 -name 'caddy-action28s.*' ! -path "$transaction_root" -print -quit)" || exit 1
record_check keepalived_active_before systemctl is-active --quiet keepalived.service || exit 1
record_check caddy_active_before systemctl is-active --quiet caddy.service || exit 1
record_check lighttpd_active_before systemctl is-active --quiet lighttpd.service || exit 1
ipv4_before=$transaction_root/ipv4.before
ipv6_before=$transaction_root/ipv6.before
ipv4_state_before=$transaction_root/ipv4-state.before
ipv6_state_before=$transaction_root/ipv6-state.before
ipv4_before_status=0
address_query 4 >"$ipv4_before" || ipv4_before_status=$?
ipv6_before_status=0
address_query 6 >"$ipv6_before" || ipv6_before_status=$?
ipv4_state_before_status=0
dbus_state "$ipv4_object" >"$ipv4_state_before" || ipv4_state_before_status=$?
ipv6_state_before_status=0
dbus_state "$ipv6_object" >"$ipv6_state_before" || ipv6_state_before_status=$?
record_check ipv4_query_before_status_zero test "$ipv4_before_status" -eq 0 || exit 1
record_check ipv6_query_before_status_zero test "$ipv6_before_status" -eq 0 || exit 1
record_check ipv4_state_before_status_zero test "$ipv4_state_before_status" -eq 0 || exit 1
record_check ipv6_state_before_status_zero test "$ipv6_state_before_status" -eq 0 || exit 1
record_check ipv4_state_backup_before grep -Fqx '(us) 1 "Backup"' "$ipv4_state_before" || exit 1
record_check ipv6_state_backup_before grep -Fqx '(us) 1 "Backup"' "$ipv6_state_before" || exit 1
record_check dns_ipv4_absent_before test "$(address_count_from "$dns_ipv4_cidr" "$ipv4_before")" -eq 0 || exit 1
record_check dns_ipv6_absent_before test "$(address_count_from "$dns_ipv6_cidr" "$ipv6_before")" -eq 0 || exit 1
record_check caddy_ipv4_absent_before test "$(address_count_from "$caddy_ipv4_cidr" "$ipv4_before")" -eq 0 || exit 1
record_check caddy_ipv6_absent_before test "$(address_count_from "$caddy_ipv6_cidr" "$ipv6_before")" -eq 0 || exit 1
create_backup
record_check backup_created test "$(stat -c '%U:%G:%a' "$backup_directory")" = root:root:700 || exit 1
record_check backup_main_hash_exact test "$(file_hash "$backup_main")" = "$accepted_main_sha256" || exit 1
record_check backup_manifest_exact backup_manifest_exact || exit 1
journal_cursor=$transaction_root/journal.cursor
journal_cursor_status=0
journalctl --show-cursor -n 0 -u keepalived.service --no-pager >"$journal_cursor" || journal_cursor_status=$?
record_check journal_cursor_status_zero test "$journal_cursor_status" -eq 0 || exit 1
cursor=$(sed -n 's/^-- cursor: //p' "$journal_cursor")
record_check journal_cursor_present test -n "$cursor" || exit 1
install_stage=$(mktemp /etc/keepalived/.keepalived.conf.action28s.XXXXXX)
record_check install_stage_created test -f "$install_stage" || exit 1
install -o root -g root -m 0644 "$source_configuration" "$install_stage"
record_check candidate_installed test "$(file_hash "$install_stage")" = "$candidate_sha256" || exit 1
mutation_started=true
mv -fT "$install_stage" "$main_configuration"
install_stage=
record_check candidate_renamed test "$(file_hash "$main_configuration")" = "$candidate_sha256" || exit 1
record_check reload_status_zero run_captured reload systemctl reload keepalived.service || exit 1
record_check reload_stdout_safe safe_stream "$transaction_root/reload.stdout" || exit 1
record_check reload_stderr_safe safe_stream "$transaction_root/reload.stderr" || exit 1
record_check convergence_reached wait_for_backup || exit 1
for action28s_node_b_sample in 1 2 3 4 5; do
    record_check "stable_sample_$action28s_node_b_sample" runtime_backup || exit 1
    sleep 1
done
reload_journal=$transaction_root/reload.journal
reload_journal_stderr=$transaction_root/reload-journal.stderr
reload_journal_status=0
journalctl -u keepalived.service --after-cursor "$cursor" --no-pager -o short-iso-precise \
    >"$reload_journal" 2>"$reload_journal_stderr" || reload_journal_status=$?
emit_stream reload_journal_stdout "$reload_journal" || exit 97
emit_stream reload_journal_stderr "$reload_journal_stderr" || exit 97
record_check reload_journal_status_zero test "$reload_journal_status" -eq 0 || exit 1
record_check reload_journal_safe safe_stream "$reload_journal" || exit 1
record_check reload_journal_stderr_safe safe_stream "$reload_journal_stderr" || exit 1
record_check reload_journal_no_fatal test "$(grep -Eic 'fatal|parse error|configuration error|segfault' "$reload_journal" || true)" -eq 0 || exit 1
record_check reload_journal_no_address_count_mismatch test "$(grep -Fic 'unexpected ip number count' "$reload_journal" || true)" -eq 0 || exit 1
record_check reload_journal_no_ttl_rejection test "$(grep -Eic 'TTL/HL .* not in range' "$reload_journal" || true)" -eq 0 || exit 1
record_check main_hash_candidate_after test "$(file_hash "$main_configuration")" = "$candidate_sha256" || exit 1
record_check fragment_hash_unchanged test "$(file_hash "$fragment")" = "$fragment_sha256" || exit 1
record_check keepalived_active_after systemctl is-active --quiet keepalived.service || exit 1
record_check caddy_active_after systemctl is-active --quiet caddy.service || exit 1
record_check lighttpd_active_after systemctl is-active --quiet lighttpd.service || exit 1
ipv4_after=$transaction_root/ipv4.after
ipv6_after=$transaction_root/ipv6.after
ipv4_state_after=$transaction_root/ipv4-state.after
ipv6_state_after=$transaction_root/ipv6-state.after
ipv4_after_status=0
address_query 4 >"$ipv4_after" || ipv4_after_status=$?
ipv6_after_status=0
address_query 6 >"$ipv6_after" || ipv6_after_status=$?
ipv4_state_after_status=0
dbus_state "$ipv4_object" >"$ipv4_state_after" || ipv4_state_after_status=$?
ipv6_state_after_status=0
dbus_state "$ipv6_object" >"$ipv6_state_after" || ipv6_state_after_status=$?
record_check ipv4_query_after_status_zero test "$ipv4_after_status" -eq 0 || exit 1
record_check ipv6_query_after_status_zero test "$ipv6_after_status" -eq 0 || exit 1
record_check ipv4_state_after_status_zero test "$ipv4_state_after_status" -eq 0 || exit 1
record_check ipv6_state_after_status_zero test "$ipv6_state_after_status" -eq 0 || exit 1
record_check ipv4_state_backup_after grep -Fqx '(us) 1 "Backup"' "$ipv4_state_after" || exit 1
record_check ipv6_state_backup_after grep -Fqx '(us) 1 "Backup"' "$ipv6_state_after" || exit 1
record_check dns_ipv4_absent_after test "$(address_count_from "$dns_ipv4_cidr" "$ipv4_after")" -eq 0 || exit 1
record_check dns_ipv6_absent_after test "$(address_count_from "$dns_ipv6_cidr" "$ipv6_after")" -eq 0 || exit 1
record_check caddy_ipv4_absent_after test "$(address_count_from "$caddy_ipv4_cidr" "$ipv4_after")" -eq 0 || exit 1
record_check caddy_ipv6_absent_after test "$(address_count_from "$caddy_ipv6_cidr" "$ipv6_after")" -eq 0 || exit 1
record_check node_b_ipv4_ui https_probe pihole00.local.theama.co 10.1.0.54 || exit 1
record_check node_b_ipv6_ui https_probe pihole00.local.theama.co fd36:5aa8:6971:1::54 || exit 1
rm -rf -- "$transaction_root/stage" 2>/dev/null || true
record_check transaction_stage_removed test ! -e "$transaction_root/stage" || exit 1
transaction_complete=true
printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
printf '%s_first_failure=none\n' "$prefix"
printf '%s_node=node_b\n' "$prefix"
printf '%s_advertised_ipv4_count=1\n' "$prefix"
printf '%s_advertised_ipv6_count=1\n' "$prefix"
printf '%s_caddy_vips_excluded=true\n' "$prefix"
printf '%s_keepalived_reload=true\n' "$prefix"
printf '%s_mutation=true\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
