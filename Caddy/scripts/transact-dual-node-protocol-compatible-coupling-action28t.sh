#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28t_remote
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly node_a_hostname=j1-svpihole0
readonly node_b_hostname=j1-svpihole00
readonly node_a_baseline_sha256=6162cfb9d83f7e524db1df6a3b041ced90a7639fceaf28eacf713270c2a66a65
readonly node_b_baseline_sha256=9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148
readonly node_a_candidate_sha256=d8f96c4f018f90370aea38fc3ef932af649158f6edc99cc7e95dea1edff4908a
readonly node_b_candidate_sha256=034ee9c45acaca4e48e2faeda24cd371e945bdb52a117b5871403958ab36794c
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/100/IPv4
readonly ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/101/IPv6
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=8192

mode=
role=
candidate=
baseline_sha256=
candidate_sha256=
expected_hostname=
backup_directory=
transaction_root=
install_stage=
mutation_started=false
transaction_complete=false
first_failure=none
expect_caddy=true

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
expected_apply_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact main_regular main_not_symlink \
        main_metadata main_hash_baseline source_stage_metadata source_regular \
        source_not_symlink source_metadata source_hash_exact source_contract backup_absent \
        transaction_residue_absent keepalived_active_before caddy_active_before \
        lighttpd_active_before baseline_state_exact backup_created backup_main_hash_exact \
        backup_manifest_exact journal_cursor_status_zero journal_cursor_present \
        install_stage_created candidate_installed candidate_renamed reload_status_zero \
        reload_stdout_safe reload_stderr_safe keepalived_active_after main_hash_candidate_after \
        apply_state_exact reload_journal_status_zero reload_journal_stdout_safe \
        reload_journal_stderr_safe reload_journal_no_fatal \
        reload_journal_no_address_count_mismatch transitional_ttl_only transaction_stage_removed
}
expected_accept_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact main_hash_candidate \
        keepalived_active caddy_active lighttpd_active acceptance_cursor_status_zero \
        acceptance_cursor_present stable_sample_1 stable_sample_2 stable_sample_3 \
        stable_sample_4 stable_sample_5 journal_status_zero journal_stdout_safe \
        journal_stderr_safe journal_no_fatal journal_no_address_count_mismatch \
        journal_no_ttl_rejection node_ui_ipv4 node_ui_ipv6
}
expected_rollback_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact backup_directory_exact \
        backup_main_exact candidate_installed main_restored reload_status_zero \
        reload_stdout_safe reload_stderr_safe baseline_convergence keepalived_active \
        caddy_active lighttpd_active baseline_state_exact
}
check() {
    local action28t_remote_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_%s_check_%s=true\n' "$prefix" "$mode" "$action28t_remote_label"
        return 0
    fi
    printf '%s_%s_check_%s=false\n' "$prefix" "$mode" "$action28t_remote_label" >&2
    first_failure=$action28t_remote_label
    return 1
}
safe_stream() {
    local action28t_remote_stream=$1

    [[ "$(wc -c <"$action28t_remote_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28t_remote_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28t_remote_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' \
        "$action28t_remote_stream"
}
emit_stream() {
    local action28t_remote_label=$1
    local action28t_remote_stream=$2

    printf '%s_%s_capture_%s_bytes=%s\n' "$prefix" "$mode" "$action28t_remote_label" \
        "$(wc -c <"$action28t_remote_stream")"
    printf '%s_%s_capture_%s_lines=%s\n' "$prefix" "$mode" "$action28t_remote_label" \
        "$(line_count "$action28t_remote_stream")"
    printf '%s_%s_capture_%s_sha256=%s\n' "$prefix" "$mode" "$action28t_remote_label" \
        "$(file_hash "$action28t_remote_stream")"
    if ! safe_stream "$action28t_remote_stream"; then
        printf '%s_%s_capture_%s_classification=unsafe_retained\n' \
            "$prefix" "$mode" "$action28t_remote_label" >&2
        return 97
    fi
    printf '%s_%s_capture_%s_classification=bounded_safe\n' "$prefix" "$mode" "$action28t_remote_label"
    if [[ -s "$action28t_remote_stream" ]]; then
        printf '%s_%s_capture_%s_begin\n' "$prefix" "$mode" "$action28t_remote_label"
        sed "s/^/${prefix}_${mode}_capture_${action28t_remote_label}_content=/" \
            "$action28t_remote_stream"
        printf '%s_%s_capture_%s_end\n' "$prefix" "$mode" "$action28t_remote_label"
    else
        printf '%s_%s_capture_%s_content=empty\n' "$prefix" "$mode" "$action28t_remote_label"
    fi
}
run_captured() {
    local action28t_remote_label=$1
    local action28t_remote_status=0

    shift
    install -m 0600 /dev/null "$transaction_root/$action28t_remote_label.stdout"
    install -m 0600 /dev/null "$transaction_root/$action28t_remote_label.stderr"
    "$@" >"$transaction_root/$action28t_remote_label.stdout" \
        2>"$transaction_root/$action28t_remote_label.stderr" || action28t_remote_status=$?
    emit_stream "${action28t_remote_label}_stdout" "$transaction_root/$action28t_remote_label.stdout" || return 97
    emit_stream "${action28t_remote_label}_stderr" "$transaction_root/$action28t_remote_label.stderr" || return 97
    printf '%s_%s_capture_%s_status=%s\n' "$prefix" "$mode" "$action28t_remote_label" \
        "$action28t_remote_status"
    [[ "$action28t_remote_status" -eq 0 ]]
}
configure_role() {
    case "$role" in
        node_a)
            expected_hostname=$node_a_hostname
            baseline_sha256=$node_a_baseline_sha256
            candidate_sha256=$node_a_candidate_sha256
            ;;
        node_b)
            expected_hostname=$node_b_hostname
            baseline_sha256=$node_b_baseline_sha256
            candidate_sha256=$node_b_candidate_sha256
            ;;
        *) return 1 ;;
    esac
    backup_directory=/var/backups/caddy-ha/action28t-$role-sequential-coupling
    readonly expected_hostname baseline_sha256 candidate_sha256 backup_directory
}
address_query() { ip -o "-$1" address show dev eth0; }
address_count() {
    local action28t_remote_family=$1
    local action28t_remote_cidr=$2

    address_query "$action28t_remote_family" |
        awk -v expected="$action28t_remote_cidr" '$4 == expected { count++ } END { print count + 0 }'
}
dbus_state() {
    timeout 3 busctl get-property org.keepalived.Vrrp1 "$1" \
        org.keepalived.Vrrp1.Instance State
}
role_state() {
    if [[ "$role" = node_a ]]; then
        [[ "$(dbus_state "$ipv4_object")" = '(us) 2 "Master"' ]] || return 1
        [[ "$(dbus_state "$ipv6_object")" = '(us) 2 "Master"' ]] || return 1
        [[ "$(address_count 4 "$dns_ipv4_cidr")" -eq 1 ]] || return 1
        [[ "$(address_count 6 "$dns_ipv6_cidr")" -eq 1 ]] || return 1
        if [[ "$expect_caddy" = true ]]; then
            [[ "$(address_count 4 "$caddy_ipv4_cidr")" -eq 1 ]] || return 1
            [[ "$(address_count 6 "$caddy_ipv6_cidr")" -eq 1 ]] || return 1
        else
            [[ "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0 ]] || return 1
            [[ "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0 ]] || return 1
        fi
        return 0
    fi
    [[ "$(dbus_state "$ipv4_object")" = '(us) 1 "Backup"' ]] || return 1
    [[ "$(dbus_state "$ipv6_object")" = '(us) 1 "Backup"' ]] || return 1
    [[ "$(address_count 4 "$dns_ipv4_cidr")" -eq 0 ]] || return 1
    [[ "$(address_count 6 "$dns_ipv6_cidr")" -eq 0 ]] || return 1
    [[ "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0 ]] || return 1
    [[ "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0 ]]
}
wait_role_state() {
    local action28t_remote_attempt

    for ((action28t_remote_attempt = 1; action28t_remote_attempt <= 30; action28t_remote_attempt++)); do
        if systemctl is-active --quiet keepalived.service && role_state; then
            return 0
        fi
        sleep 1
    done
    return 1
}
candidate_contract() {
    local action28t_remote_file=$1

    [[ "$(file_hash "$action28t_remote_file")" = "$candidate_sha256" ]] || return 1
    [[ "$(grep -Fxc '    unicast_ttl 255' "$action28t_remote_file" || true)" -eq 2 ]] || return 1
    [[ "$(grep -Ec 'min_ttl 255 max_ttl 255$' "$action28t_remote_file" || true)" -eq 2 ]] || return 1
    [[ "$(grep -Fxc '    virtual_ipaddress {' "$action28t_remote_file" || true)" -eq 2 ]] || return 1
    [[ "$(grep -Fxc '    virtual_ipaddress_excluded {' "$action28t_remote_file" || true)" -eq 2 ]] || return 1
    [[ "$(grep -Fxc '        10.1.0.55/22 dev eth0' "$action28t_remote_file" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc '        10.1.0.56/22 dev eth0' "$action28t_remote_file" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc '        fd36:5aa8:6971:1::55/128 dev eth0 preferred_lft forever' "$action28t_remote_file" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc '        fd36:5aa8:6971:1::56/128 dev eth0 preferred_lft forever' "$action28t_remote_file" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'include /etc/keepalived/conf.d/caddy-ha.conf' "$action28t_remote_file" || true)" -eq 0 ]] || return 1
    ! grep -Eq 'vrrp_instance CADDY_|vrrp_script check_caddy' "$action28t_remote_file"
}
backup_manifest_exact() {
    diff -u <(printf '%s\n' 'action=28t' "role=$role" \
        "baseline=$baseline_sha256" "candidate=$candidate_sha256") \
        "$backup_directory/manifest" >/dev/null
}
create_backup() {
    install -d -o root -g root -m 0700 /var/backups/caddy-ha
    install -d -o root -g root -m 0700 "$backup_directory"
    install -o root -g root -m 0600 "$main_configuration" "$backup_directory/keepalived.conf.before"
    printf '%s\n' 'action=28t' "role=$role" "baseline=$baseline_sha256" \
        "candidate=$candidate_sha256" >"$backup_directory/manifest"
    chmod 0600 "$backup_directory/manifest"
}
journal_no_fatal() {
    local action28t_remote_journal=$1

    [[ "$(grep -Eic 'fatal|parse error|configuration error|segfault' "$action28t_remote_journal" || true)" -eq 0 ]]
}
transitional_ttl_only() {
    local action28t_remote_journal=$1
    local action28t_remote_ttl_lines

    action28t_remote_ttl_lines=$(grep -Ei 'TTL/HL .* not in range' "$action28t_remote_journal" || true)
    [[ -z "$action28t_remote_ttl_lines" ]] && return 0
    [[ "$(printf '%s\n' "$action28t_remote_ttl_lines" |
        grep -Evc '\(PIHOLE_IPV6\) TTL/HL 64 not in range 255 - 255$' || true)" -eq 0 ]]
}
https_probe() {
    local action28t_remote_name=$1
    local action28t_remote_address=$2

    curl --noproxy '*' --insecure --silent --show-error --location --max-redirs 3 \
        --proto-redir '=https' --connect-timeout 3 --max-time 10 \
        --resolve "${action28t_remote_name}:443:${action28t_remote_address}" \
        --output /dev/null --write-out '%{http_code}' \
        "https://${action28t_remote_name}/admin/" | grep -Fqx 200
}
perform_rollback() {
    mode=rollback
    expect_caddy=false
    check identity_root test "$(id -u)" -eq 0 || return 125
    check working_directory_root test "$(pwd -P)" = / || return 125
    check hostname_exact test "$(hostname)" = "$expected_hostname" || return 125
    check backup_directory_exact backup_manifest_exact || return 125
    check backup_main_exact test "$(file_hash "$backup_directory/keepalived.conf.before")" = "$baseline_sha256" || return 125
    check candidate_installed test "$(file_hash "$main_configuration")" = "$candidate_sha256" || return 125
    install_stage=$(mktemp /etc/keepalived/.keepalived.conf.action28t-rollback.XXXXXX)
    install -o root -g root -m 0644 "$backup_directory/keepalived.conf.before" "$install_stage"
    mv -fT "$install_stage" "$main_configuration"
    install_stage=
    check main_restored test "$(file_hash "$main_configuration")" = "$baseline_sha256" || return 125
    check reload_status_zero run_captured rollback_reload systemctl reload keepalived.service || return 125
    check reload_stdout_safe safe_stream "$transaction_root/rollback_reload.stdout" || return 125
    check reload_stderr_safe safe_stream "$transaction_root/rollback_reload.stderr" || return 125
    check baseline_convergence wait_role_state || return 125
    check keepalived_active systemctl is-active --quiet keepalived.service || return 125
    check caddy_active systemctl is-active --quiet caddy.service || return 125
    check lighttpd_active systemctl is-active --quiet lighttpd.service || return 125
    check baseline_state_exact role_state || return 125
    printf '%s_rollback_role=%s\n' "$prefix" "$role"
    printf '%s_rollback_acceptance=true\n' "$prefix"
}
cleanup() {
    local action28t_remote_status=$?

    trap - EXIT INT TERM
    if [[ "$mode" = apply && "$mutation_started" = true && "$transaction_complete" != true ]]; then
        perform_rollback || action28t_remote_status=125
    fi
    [[ -z "$install_stage" || ! -e "$install_stage" ]] || rm -f -- "$install_stage"
    [[ -z "$transaction_root" || ! -d "$transaction_root" ]] || rm -rf -- "$transaction_root"
    printf '%s_%s_first_failure=%s\n' "$prefix" "$mode" "$first_failure"
    exit "$action28t_remote_status"
}
apply_candidate() {
    mode=apply
    check identity_root test "$(id -u)" -eq 0 || return 1
    check working_directory_root test "$(pwd -P)" = / || return 1
    check hostname_exact test "$(hostname)" = "$expected_hostname" || return 1
    check main_regular test -f "$main_configuration" || return 1
    check main_not_symlink test ! -L "$main_configuration" || return 1
    check main_metadata test "$(stat -c '%U:%G:%a' "$main_configuration")" = root:root:644 || return 1
    check main_hash_baseline test "$(file_hash "$main_configuration")" = "$baseline_sha256" || return 1
    check source_stage_metadata test "$(stat -c '%U:%G:%a' "$(dirname "$candidate")")" = root:root:700 || return 1
    check source_regular test -f "$candidate" || return 1
    check source_not_symlink test ! -L "$candidate" || return 1
    check source_metadata test "$(stat -c '%U:%G:%a' "$candidate")" = root:root:600 || return 1
    check source_hash_exact test "$(file_hash "$candidate")" = "$candidate_sha256" || return 1
    check source_contract candidate_contract "$candidate" || return 1
    check backup_absent test ! -e "$backup_directory" || return 1
    check transaction_residue_absent test -z "$(find /run -maxdepth 1 -name 'caddy-action28t.*' ! -path "$transaction_root" -print -quit)" || return 1
    check keepalived_active_before systemctl is-active --quiet keepalived.service || return 1
    check caddy_active_before systemctl is-active --quiet caddy.service || return 1
    check lighttpd_active_before systemctl is-active --quiet lighttpd.service || return 1
    expect_caddy=false
    check baseline_state_exact role_state || return 1
    expect_caddy=true
    create_backup
    check backup_created test "$(stat -c '%U:%G:%a' "$backup_directory")" = root:root:700 || return 1
    check backup_main_hash_exact test "$(file_hash "$backup_directory/keepalived.conf.before")" = "$baseline_sha256" || return 1
    check backup_manifest_exact backup_manifest_exact || return 1
    journal_cursor=$transaction_root/journal.cursor
    journal_cursor_status=0
    journalctl --show-cursor -n 0 -u keepalived.service --no-pager >"$journal_cursor" || journal_cursor_status=$?
    check journal_cursor_status_zero test "$journal_cursor_status" -eq 0 || return 1
    cursor=$(sed -n 's/^-- cursor: //p' "$journal_cursor")
    check journal_cursor_present test -n "$cursor" || return 1
    install_stage=$(mktemp /etc/keepalived/.keepalived.conf.action28t.XXXXXX)
    check install_stage_created test -f "$install_stage" || return 1
    install -o root -g root -m 0644 "$candidate" "$install_stage"
    check candidate_installed test "$(file_hash "$install_stage")" = "$candidate_sha256" || return 1
    mutation_started=true
    mv -fT "$install_stage" "$main_configuration"
    install_stage=
    check candidate_renamed test "$(file_hash "$main_configuration")" = "$candidate_sha256" || return 1
    check reload_status_zero run_captured reload systemctl reload keepalived.service || return 1
    check reload_stdout_safe safe_stream "$transaction_root/reload.stdout" || return 1
    check reload_stderr_safe safe_stream "$transaction_root/reload.stderr" || return 1
    check keepalived_active_after systemctl is-active --quiet keepalived.service || return 1
    check main_hash_candidate_after test "$(file_hash "$main_configuration")" = "$candidate_sha256" || return 1
    if [[ "$role" = node_a ]]; then
        check apply_state_exact wait_role_state || return 1
    else
        check apply_state_exact role_state || return 1
    fi
    journal=$transaction_root/reload.journal
    journal_stderr=$transaction_root/reload-journal.stderr
    journal_status=0
    journalctl -u keepalived.service --after-cursor "$cursor" --no-pager -o short-iso-precise \
        >"$journal" 2>"$journal_stderr" || journal_status=$?
    emit_stream reload_journal_stdout "$journal" || return 97
    emit_stream reload_journal_stderr "$journal_stderr" || return 97
    check reload_journal_status_zero test "$journal_status" -eq 0 || return 1
    check reload_journal_stdout_safe safe_stream "$journal" || return 1
    check reload_journal_stderr_safe safe_stream "$journal_stderr" || return 1
    check reload_journal_no_fatal journal_no_fatal "$journal" || return 1
    check reload_journal_no_address_count_mismatch test "$(grep -Fic 'unexpected ip number count' "$journal" || true)" -eq 0 || return 1
    if [[ "$role" = node_b ]]; then
        check transitional_ttl_only transitional_ttl_only "$journal" || return 1
    else
        check transitional_ttl_only test "$(grep -Eic 'TTL/HL .* not in range' "$journal" || true)" -eq 0 || return 1
    fi
    rm -rf -- "$transaction_root/stage" 2>/dev/null || true
    check transaction_stage_removed test ! -e "$transaction_root/stage" || return 1
    transaction_complete=true
    printf '%s_apply_role=%s\n' "$prefix" "$role"
    printf '%s_apply_transition_ttl_permitted=%s\n' "$prefix" "$([[ "$role" = node_b ]] && printf true || printf false)"
    printf '%s_apply_acceptance=true\n' "$prefix"
}
accept_role() {
    local action28t_remote_sample

    mode=accept
    check identity_root test "$(id -u)" -eq 0 || return 1
    check working_directory_root test "$(pwd -P)" = / || return 1
    check hostname_exact test "$(hostname)" = "$expected_hostname" || return 1
    check main_hash_candidate test "$(file_hash "$main_configuration")" = "$candidate_sha256" || return 1
    check keepalived_active systemctl is-active --quiet keepalived.service || return 1
    check caddy_active systemctl is-active --quiet caddy.service || return 1
    check lighttpd_active systemctl is-active --quiet lighttpd.service || return 1
    cursor_file=$transaction_root/accept.cursor
    cursor_status=0
    journalctl --show-cursor -n 0 -u keepalived.service --no-pager >"$cursor_file" || cursor_status=$?
    check acceptance_cursor_status_zero test "$cursor_status" -eq 0 || return 1
    cursor=$(sed -n 's/^-- cursor: //p' "$cursor_file")
    check acceptance_cursor_present test -n "$cursor" || return 1
    for action28t_remote_sample in 1 2 3 4 5; do
        check "stable_sample_$action28t_remote_sample" role_state || return 1
        sleep 1
    done
    journal=$transaction_root/accept.journal
    journal_stderr=$transaction_root/accept-journal.stderr
    journal_status=0
    journalctl -u keepalived.service --after-cursor "$cursor" --no-pager -o short-iso-precise \
        >"$journal" 2>"$journal_stderr" || journal_status=$?
    emit_stream acceptance_journal_stdout "$journal" || return 97
    emit_stream acceptance_journal_stderr "$journal_stderr" || return 97
    check journal_status_zero test "$journal_status" -eq 0 || return 1
    check journal_stdout_safe safe_stream "$journal" || return 1
    check journal_stderr_safe safe_stream "$journal_stderr" || return 1
    check journal_no_fatal journal_no_fatal "$journal" || return 1
    check journal_no_address_count_mismatch test "$(grep -Fic 'unexpected ip number count' "$journal" || true)" -eq 0 || return 1
    check journal_no_ttl_rejection test "$(grep -Eic 'TTL/HL .* not in range' "$journal" || true)" -eq 0 || return 1
    if [[ "$role" = node_a ]]; then
        check node_ui_ipv4 https_probe pihole0.local.theama.co 10.1.0.53 || return 1
        check node_ui_ipv6 https_probe pihole0.local.theama.co fd36:5aa8:6971:1::53 || return 1
    else
        check node_ui_ipv4 https_probe pihole00.local.theama.co 10.1.0.54 || return 1
        check node_ui_ipv6 https_probe pihole00.local.theama.co fd36:5aa8:6971:1::54 || return 1
    fi
    printf '%s_accept_role=%s\n' "$prefix" "$role"
    printf '%s_accept_acceptance=true\n' "$prefix"
}

case "${1:-}" in
    --expected-apply-checks)
        expected_apply_checks
        exit 0
        ;;
    --expected-accept-checks)
        expected_accept_checks
        exit 0
        ;;
    --expected-rollback-checks)
        expected_rollback_checks
        exit 0
        ;;
    --self-test)
        [[ "$(expected_apply_checks | wc -l)" -eq "$(expected_apply_checks | LC_ALL=C sort -u | wc -l)" ]] || exit 1
        [[ "$(expected_accept_checks | wc -l)" -eq "$(expected_accept_checks | LC_ALL=C sort -u | wc -l)" ]] || exit 1
        [[ "$(expected_rollback_checks | wc -l)" -eq "$(expected_rollback_checks | LC_ALL=C sort -u | wc -l)" ]] || exit 1
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --transition-test)
        [[ $# -eq 2 && -f "$2" && ! -L "$2" ]] || exit 64
        transitional_ttl_only "$2"
        exit $?
        ;;
    --apply)
        [[ $# -eq 3 && "$3" = /* ]] || exit 64
        mode=apply
        role=$2
        candidate=$3
        ;;
    --accept)
        [[ $# -eq 2 ]] || exit 64
        mode=accept
        role=$2
        ;;
    --rollback)
        [[ $# -eq 2 ]] || exit 64
        mode=rollback
        role=$2
        ;;
    *) exit 64 ;;
esac
readonly role candidate
configure_role
transaction_root=$(mktemp -d /run/caddy-action28t.XXXXXX)
readonly transaction_root
chmod 0700 "$transaction_root"
trap cleanup EXIT INT TERM

case "$mode" in
    apply) apply_candidate ;;
    accept) accept_role ;;
    rollback)
        perform_rollback
        transaction_complete=true
        ;;
esac
