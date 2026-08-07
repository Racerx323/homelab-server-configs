#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20n
readonly production_main_sha256=357eb09c628fa3b78efcaacf53278ab09a6574b991820632ee3ec2614265d8e2
readonly production_source_sha256=6162cfb9d83f7e524db1df6a3b041ced90a7639fceaf28eacf713270c2a66a65
readonly production_candidate_sha256=8fc9dcf8e079b7131f86a58038ae5543804a5158a02d53a4614452de212ce47c
readonly production_fragment_sha256=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
readonly production_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly include_record='include /etc/keepalived/conf.d/caddy-ha.conf'
readonly maximum_capture_bytes=65536
readonly maximum_capture_lines=1024

action20n_root=
action20n_main_configuration=
action20n_fragment=
action20n_health_helper=
action20n_vrrp_state_file=
action20n_rollback_root=
action20n_expected_main_sha256=$production_main_sha256
action20n_expected_source_sha256=$production_source_sha256
action20n_expected_candidate_sha256=$production_candidate_sha256
action20n_expected_fragment_sha256=$production_fragment_sha256
action20n_expected_health_sha256=$production_health_sha256
action20n_expected_owner=root
action20n_expected_group=root
action20n_transaction_root=
action20n_candidate=
action20n_expected_candidate=
action20n_install_stage=
action20n_backup_directory=
action20n_mutation_started=false
action20n_transaction_complete=false
action20n_keepalived_pid_before=
action20n_keepalived_restarts_before=
action20n_continuity_before=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
observed_hostname() {
    if [[ "${ACTION20N_TEST_MODE:-}" = 1 ]]; then
        printf '%s\n' "${ACTION20N_TEST_HOSTNAME:-}"
    else
        hostname
    fi
}
observed_uid() {
    if [[ "${ACTION20N_TEST_MODE:-}" = 1 ]]; then
        printf '0\n'
    else
        id -u
    fi
}
observed_architecture() {
    if [[ "${ACTION20N_TEST_MODE:-}" = 1 ]]; then
        printf '%s\n' "${ACTION20N_TEST_ARCHITECTURE:-}"
    else
        dpkg --print-architecture
    fi
}
service_active() {
    local action20n_service_name=$1

    if [[ "${ACTION20N_TEST_MODE:-}" = 1 ]]; then
        [[ "${ACTION20N_TEST_SERVICES_ACTIVE:-}" = true ]]
    else
        systemctl is-active --quiet "$action20n_service_name"
    fi
}
keepalived_property() {
    local action20n_property_name=$1

    if [[ "${ACTION20N_TEST_MODE:-}" = 1 ]]; then
        case "$action20n_property_name" in
            MainPID) printf '%s\n' "${ACTION20N_TEST_KEEPALIVED_PID:-}" ;;
            NRestarts) printf '%s\n' "${ACTION20N_TEST_KEEPALIVED_RESTARTS:-}" ;;
            *) return 1 ;;
        esac
    else
        systemctl show keepalived.service --property "$action20n_property_name" --value
    fi
}
address_count() {
    local action20n_address_family=$1
    local action20n_expected_cidr=$2

    if [[ "${ACTION20N_TEST_MODE:-}" = 1 ]]; then
        printf '1\n'
        return 0
    fi
    ip -o "-$action20n_address_family" address show dev eth0 2>/dev/null |
        awk -v expected="$action20n_expected_cidr" '$4 == expected { count++ }
            END { print count + 0 }'
}
record_check() {
    local action20n_check_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20n_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20n_check_label" >&2
    return 1
}
expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact architecture_arm64 \
        main_regular main_not_symlink main_metadata \
        main_hash_exact main_enable_dbus_absent main_include_once \
        fragment_hash_exact health_hash_exact keepalived_active_pre \
        caddy_active_pre lighttpd_active_pre keepalived_pid_numeric \
        keepalived_restarts_numeric vrrp_state_master_pre caddy_ipv4_present_pre \
        caddy_ipv6_present_pre dns_ipv4_present_pre dns_ipv6_present_pre \
        stage_directory_metadata source_regular source_not_symlink \
        source_metadata source_hash_exact source_terminal_newline \
        source_global_defs_once source_enable_dbus_once \
        source_enable_dbus_in_global_defs source_dbus_service_name_absent \
        source_include_absent \
        candidate_regular candidate_metadata candidate_hash_exact \
        candidate_global_defs_once candidate_enable_dbus_once \
        candidate_enable_dbus_in_global_defs candidate_dbus_service_name_absent \
        candidate_include_once candidate_include_terminal candidate_exact_derivation \
        rollback_directory_metadata backup_main_metadata backup_main_hash \
        backup_manifest_metadata backup_manifest_lines backup_manifest_action \
        backup_manifest_node backup_manifest_source backup_manifest_before \
        backup_manifest_candidate mutation_started installed_main_metadata \
        installed_main_hash installed_enable_dbus_once installed_include_once \
        fragment_hash_unchanged health_hash_unchanged keepalived_active_post \
        caddy_active_post lighttpd_active_post keepalived_pid_unchanged \
        keepalived_restarts_unchanged vrrp_state_master_post \
        caddy_ipv4_present_post caddy_ipv6_present_post dns_ipv4_present_post \
        dns_ipv6_present_post continuity_unchanged
}
safe_capture() {
    local action20n_capture_path=$1

    [[ "$(wc -c <"$action20n_capture_path")" -le "$maximum_capture_bytes" ]] || return 1
    [[ "$(line_count "$action20n_capture_path")" -le "$maximum_capture_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20n_capture_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20n_capture_path"
}
emit_capture() {
    local action20n_capture_label=$1
    local action20n_capture_path=$2

    printf '%s_capture_%s_bytes=%s\n' "$prefix" "$action20n_capture_label" \
        "$(wc -c <"$action20n_capture_path")"
    printf '%s_capture_%s_lines=%s\n' "$prefix" "$action20n_capture_label" \
        "$(line_count "$action20n_capture_path")"
    printf '%s_capture_%s_sha256=%s\n' "$prefix" "$action20n_capture_label" \
        "$(file_hash "$action20n_capture_path")"
    if safe_capture "$action20n_capture_path"; then
        printf '%s_capture_%s_classification=bounded_safe\n' "$prefix" "$action20n_capture_label"
        if [[ -s "$action20n_capture_path" ]]; then
            printf '%s_capture_%s_begin\n' "$prefix" "$action20n_capture_label"
            cat "$action20n_capture_path"
            printf '%s_capture_%s_end\n' "$prefix" "$action20n_capture_label"
        else
            printf '%s_capture_%s_content_secured=empty\n' "$prefix" "$action20n_capture_label"
        fi
        return 0
    fi
    printf '%s_capture_%s_classification=unsafe_retained\n' "$prefix" "$action20n_capture_label" >&2
    return 97
}
run_captured() {
    local action20n_run_label=$1
    local action20n_run_stdout=$action20n_transaction_root/$action20n_run_label.stdout
    local action20n_run_stderr=$action20n_transaction_root/$action20n_run_label.stderr
    local action20n_run_status=0

    shift
    install -m 0600 /dev/null "$action20n_run_stdout" || return 1
    install -m 0600 /dev/null "$action20n_run_stderr" || return 1
    "$@" >"$action20n_run_stdout" 2>"$action20n_run_stderr" || action20n_run_status=$?
    emit_capture "${action20n_run_label}_stdout" "$action20n_run_stdout" || return 97
    emit_capture "${action20n_run_label}_stderr" "$action20n_run_stderr" || return 97
    printf '%s_capture_%s_status=%s\n' "$prefix" "$action20n_run_label" "$action20n_run_status"
    [[ "$action20n_run_status" -eq 0 ]]
}
global_defs_contains_enable_dbus() {
    local action20n_configuration_path=$1

    awk '
        /^[[:space:]]*global_defs[[:space:]]*\{/ { in_global=1; blocks++; next }
        in_global && /^[[:space:]]*enable_dbus([[:space:]]|$)/ { found++ }
        in_global && /^[[:space:]]*\}[[:space:]]*$/ { in_global=0 }
        END { exit(blocks == 1 && found == 1 ? 0 : 1) }
    ' "$action20n_configuration_path"
}
build_candidate() {
    local action20n_source_path=$1
    local action20n_output_path=$2

    {
        cat "$action20n_source_path"
        printf '\n%s\n' "$include_record"
    } >"$action20n_output_path"
}
continuity_snapshot() {
    printf 'fragment=%s\n' "$(file_hash "$action20n_fragment" 2>/dev/null || true)"
    printf 'health=%s\n' "$(file_hash "$action20n_health_helper" 2>/dev/null || true)"
    printf 'keepalived_active=%s\n' "$(service_active keepalived.service && printf yes || printf no)"
    printf 'caddy_active=%s\n' "$(service_active caddy.service && printf yes || printf no)"
    printf 'lighttpd_active=%s\n' "$(service_active lighttpd.service && printf yes || printf no)"
    printf 'keepalived_pid=%s\n' "$(keepalived_property MainPID 2>/dev/null || true)"
    printf 'keepalived_restarts=%s\n' "$(keepalived_property NRestarts 2>/dev/null || true)"
    printf 'vrrp_state=%s\n' "$(sed -n '1p' "$action20n_vrrp_state_file" 2>/dev/null || true)"
    printf 'caddy_ipv4=%s\n' "$(address_count 4 10.1.0.56/22)"
    printf 'caddy_ipv6=%s\n' "$(address_count 6 fd36:5aa8:6971:1::56/128)"
    printf 'dns_ipv4=%s\n' "$(address_count 4 10.1.0.55/22)"
    printf 'dns_ipv6=%s\n' "$(address_count 6 fd36:5aa8:6971:1::55/128)"
}
configure_paths() {
    if [[ "${ACTION20N_TEST_MODE:-}" = 1 ]]; then
        [[ -n "${ACTION20N_TEST_ROOT:-}" && "$ACTION20N_TEST_ROOT" = /* ]] || return 1
        action20n_root=$ACTION20N_TEST_ROOT
        action20n_expected_owner=$(id -un) || return 1
        action20n_expected_group=$(id -gn) || return 1
    else
        action20n_root=
    fi
    action20n_main_configuration=$action20n_root/etc/keepalived/keepalived.conf
    action20n_fragment=$action20n_root/etc/keepalived/conf.d/caddy-ha.conf
    action20n_health_helper=$action20n_root/usr/local/libexec/check-caddy.sh
    action20n_vrrp_state_file=$action20n_root/run/caddy-ha/vrrp-state
    action20n_rollback_root=$action20n_root/var/backups/caddy-ha
}
configure_expected_hashes_for_test() {
    local action20n_test_source=$1

    [[ "${ACTION20N_TEST_MODE:-}" = 1 ]] || return 0
    action20n_expected_main_sha256=$(file_hash "$action20n_main_configuration") || return 1
    action20n_expected_source_sha256=$(file_hash "$action20n_test_source") || return 1
    action20n_expected_fragment_sha256=$(file_hash "$action20n_fragment") || return 1
    action20n_expected_health_sha256=$(file_hash "$action20n_health_helper") || return 1
    build_candidate "$action20n_test_source" "$action20n_expected_candidate" || return 1
    action20n_expected_candidate_sha256=$(file_hash "$action20n_expected_candidate") || return 1
}
validate_source_and_candidate() {
    local action20n_source_path=$1

    record_check stage_directory_metadata test \
        "$(stat -c '%U:%G:%a' "$(dirname "$action20n_source_path")")" = \
        "$action20n_expected_owner:$action20n_expected_group:700" || return 1
    record_check source_regular test -f "$action20n_source_path" || return 1
    record_check source_not_symlink test ! -L "$action20n_source_path" || return 1
    record_check source_metadata test \
        "$(stat -c '%U:%G:%a' "$action20n_source_path")" = \
        "$action20n_expected_owner:$action20n_expected_group:600" || return 1
    record_check source_hash_exact test \
        "$(file_hash "$action20n_source_path")" = "$action20n_expected_source_sha256" || return 1
    record_check source_terminal_newline test \
        "$(tail -c 1 "$action20n_source_path" | od -An -tuC | tr -d ' ')" = 10 || return 1
    record_check source_global_defs_once test \
        "$(grep -Ec '^[[:space:]]*global_defs[[:space:]]*\{' "$action20n_source_path")" -eq 1 || return 1
    record_check source_enable_dbus_once test \
        "$(grep -Ec '^[[:space:]]*enable_dbus([[:space:]]|$)' "$action20n_source_path")" -eq 1 || return 1
    record_check source_enable_dbus_in_global_defs global_defs_contains_enable_dbus \
        "$action20n_source_path" || return 1
    record_check source_dbus_service_name_absent test \
        "$(grep -Ec '^[[:space:]]*dbus_service_name([[:space:]]|$)' "$action20n_source_path" || true)" -eq 0 || return 1
    record_check source_include_absent test \
        "$(grep -Fxc "$include_record" "$action20n_source_path" || true)" -eq 0 || return 1
    build_candidate "$action20n_source_path" "$action20n_candidate" || return 1
    chown "$action20n_expected_owner:$action20n_expected_group" "$action20n_candidate" || return 1
    chmod 0600 "$action20n_candidate" || return 1
    record_check candidate_regular test -f "$action20n_candidate" || return 1
    record_check candidate_metadata test \
        "$(stat -c '%U:%G:%a' "$action20n_candidate")" = \
        "$action20n_expected_owner:$action20n_expected_group:600" || return 1
    record_check candidate_hash_exact test \
        "$(file_hash "$action20n_candidate")" = "$action20n_expected_candidate_sha256" || return 1
    record_check candidate_global_defs_once test \
        "$(grep -Ec '^[[:space:]]*global_defs[[:space:]]*\{' "$action20n_candidate")" -eq 1 || return 1
    record_check candidate_enable_dbus_once test \
        "$(grep -Ec '^[[:space:]]*enable_dbus([[:space:]]|$)' "$action20n_candidate")" -eq 1 || return 1
    record_check candidate_enable_dbus_in_global_defs global_defs_contains_enable_dbus \
        "$action20n_candidate" || return 1
    record_check candidate_dbus_service_name_absent test \
        "$(grep -Ec '^[[:space:]]*dbus_service_name([[:space:]]|$)' "$action20n_candidate" || true)" -eq 0 || return 1
    record_check candidate_include_once test \
        "$(grep -Fxc "$include_record" "$action20n_candidate")" -eq 1 || return 1
    record_check candidate_include_terminal test \
        "$(tail -n 1 "$action20n_candidate")" = "$include_record" || return 1
    build_candidate "$action20n_source_path" "$action20n_expected_candidate" || return 1
    record_check candidate_exact_derivation cmp -s \
        "$action20n_candidate" "$action20n_expected_candidate" || return 1
}
validate_live_prestate() {
    record_check identity_root test "$(observed_uid)" -eq 0 || return 1
    record_check working_directory_root test "$(pwd -P)" = / || return 1
    record_check hostname_exact test "$(observed_hostname)" = j1-svpihole0 || return 1
    record_check architecture_arm64 test "$(observed_architecture)" = arm64 || return 1
    record_check main_regular test -f "$action20n_main_configuration" || return 1
    record_check main_not_symlink test ! -L "$action20n_main_configuration" || return 1
    record_check main_metadata test \
        "$(stat -c '%U:%G:%a' "$action20n_main_configuration")" = \
        "$action20n_expected_owner:$action20n_expected_group:644" || return 1
    record_check main_hash_exact test \
        "$(file_hash "$action20n_main_configuration")" = "$action20n_expected_main_sha256" || return 1
    record_check main_enable_dbus_absent test \
        "$(grep -Ec '^[[:space:]]*enable_dbus([[:space:]]|$)' "$action20n_main_configuration" || true)" -eq 0 || return 1
    record_check main_include_once test \
        "$(grep -Fxc "$include_record" "$action20n_main_configuration")" -eq 1 || return 1
    record_check fragment_hash_exact test \
        "$(file_hash "$action20n_fragment")" = "$action20n_expected_fragment_sha256" || return 1
    record_check health_hash_exact test \
        "$(file_hash "$action20n_health_helper")" = "$action20n_expected_health_sha256" || return 1
    record_check keepalived_active_pre service_active keepalived.service || return 1
    record_check caddy_active_pre service_active caddy.service || return 1
    record_check lighttpd_active_pre service_active lighttpd.service || return 1
    action20n_keepalived_pid_before=$(keepalived_property MainPID) || return 1
    record_check keepalived_pid_numeric test "$action20n_keepalived_pid_before" -gt 0 || return 1
    action20n_keepalived_restarts_before=$(keepalived_property NRestarts) || return 1
    record_check keepalived_restarts_numeric test "$action20n_keepalived_restarts_before" -ge 0 || return 1
    record_check vrrp_state_master_pre test \
        "$(sed -n '1p' "$action20n_vrrp_state_file")" = MASTER || return 1
    record_check caddy_ipv4_present_pre test "$(address_count 4 10.1.0.56/22)" -eq 1 || return 1
    record_check caddy_ipv6_present_pre test "$(address_count 6 fd36:5aa8:6971:1::56/128)" -eq 1 || return 1
    record_check dns_ipv4_present_pre test "$(address_count 4 10.1.0.55/22)" -eq 1 || return 1
    record_check dns_ipv6_present_pre test "$(address_count 6 fd36:5aa8:6971:1::55/128)" -eq 1 || return 1
    action20n_continuity_before=$(continuity_snapshot | sha256sum | awk '{ print $1 }') || return 1
}
create_backup() {
    install -d -o "$action20n_expected_owner" -g "$action20n_expected_group" \
        -m 0700 "$action20n_rollback_root" || return 1
    action20n_backup_directory=$(mktemp -d \
        "$action20n_rollback_root/action20n-node-a-dbus-main.XXXXXX") || return 1
    chown "$action20n_expected_owner:$action20n_expected_group" "$action20n_backup_directory" || return 1
    chmod 0700 "$action20n_backup_directory" || return 1
    install -o "$action20n_expected_owner" -g "$action20n_expected_group" -m 0600 \
        "$action20n_main_configuration" \
        "$action20n_backup_directory/keepalived.conf.before" || return 1
    {
        printf 'action=20n\n'
        printf 'node=node-a\n'
        printf 'source_sha256=%s\n' "$action20n_expected_source_sha256"
        printf 'before_sha256=%s\n' "$action20n_expected_main_sha256"
        printf 'candidate_sha256=%s\n' "$action20n_expected_candidate_sha256"
    } >"$action20n_backup_directory/manifest" || return 1
    chown "$action20n_expected_owner:$action20n_expected_group" \
        "$action20n_backup_directory/manifest" || return 1
    chmod 0600 "$action20n_backup_directory/manifest" || return 1
    record_check rollback_directory_metadata test \
        "$(stat -c '%U:%G:%a' "$action20n_backup_directory")" = \
        "$action20n_expected_owner:$action20n_expected_group:700" || return 1
    record_check backup_main_metadata test \
        "$(stat -c '%U:%G:%a' "$action20n_backup_directory/keepalived.conf.before")" = \
        "$action20n_expected_owner:$action20n_expected_group:600" || return 1
    record_check backup_main_hash test \
        "$(file_hash "$action20n_backup_directory/keepalived.conf.before")" = "$action20n_expected_main_sha256" || return 1
    record_check backup_manifest_metadata test \
        "$(stat -c '%U:%G:%a' "$action20n_backup_directory/manifest")" = \
        "$action20n_expected_owner:$action20n_expected_group:600" || return 1
    record_check backup_manifest_lines test \
        "$(line_count "$action20n_backup_directory/manifest")" -eq 5 || return 1
    record_check backup_manifest_action grep -Fqx action=20n "$action20n_backup_directory/manifest" || return 1
    record_check backup_manifest_node grep -Fqx node=node-a "$action20n_backup_directory/manifest" || return 1
    record_check backup_manifest_source grep -Fqx \
        "source_sha256=$action20n_expected_source_sha256" "$action20n_backup_directory/manifest" || return 1
    record_check backup_manifest_before grep -Fqx \
        "before_sha256=$action20n_expected_main_sha256" "$action20n_backup_directory/manifest" || return 1
    record_check backup_manifest_candidate grep -Fqx \
        "candidate_sha256=$action20n_expected_candidate_sha256" "$action20n_backup_directory/manifest" || return 1
    printf '%s_backup_path=%s\n' "$prefix" "$action20n_backup_directory"
}
validate_live_poststate() {
    record_check installed_main_metadata test \
        "$(stat -c '%U:%G:%a' "$action20n_main_configuration")" = \
        "$action20n_expected_owner:$action20n_expected_group:644" || return 1
    record_check installed_main_hash test \
        "$(file_hash "$action20n_main_configuration")" = "$action20n_expected_candidate_sha256" || return 1
    record_check installed_enable_dbus_once test \
        "$(grep -Ec '^[[:space:]]*enable_dbus([[:space:]]|$)' "$action20n_main_configuration")" -eq 1 || return 1
    record_check installed_include_once test \
        "$(grep -Fxc "$include_record" "$action20n_main_configuration")" -eq 1 || return 1
    record_check fragment_hash_unchanged test \
        "$(file_hash "$action20n_fragment")" = "$action20n_expected_fragment_sha256" || return 1
    record_check health_hash_unchanged test \
        "$(file_hash "$action20n_health_helper")" = "$action20n_expected_health_sha256" || return 1
    record_check keepalived_active_post service_active keepalived.service || return 1
    record_check caddy_active_post service_active caddy.service || return 1
    record_check lighttpd_active_post service_active lighttpd.service || return 1
    record_check keepalived_pid_unchanged test "$(keepalived_property MainPID)" = "$action20n_keepalived_pid_before" || return 1
    record_check keepalived_restarts_unchanged test "$(keepalived_property NRestarts)" = "$action20n_keepalived_restarts_before" || return 1
    record_check vrrp_state_master_post test "$(sed -n '1p' "$action20n_vrrp_state_file")" = MASTER || return 1
    record_check caddy_ipv4_present_post test "$(address_count 4 10.1.0.56/22)" -eq 1 || return 1
    record_check caddy_ipv6_present_post test "$(address_count 6 fd36:5aa8:6971:1::56/128)" -eq 1 || return 1
    record_check dns_ipv4_present_post test "$(address_count 4 10.1.0.55/22)" -eq 1 || return 1
    record_check dns_ipv6_present_post test "$(address_count 6 fd36:5aa8:6971:1::55/128)" -eq 1 || return 1
    record_check continuity_unchanged test \
        "$(continuity_snapshot | sha256sum | awk '{ print $1 }')" = "$action20n_continuity_before" || return 1
}
rollback() {
    local action20n_rollback_failed=false
    local action20n_rollback_stage

    [[ "$action20n_mutation_started" = true && "$action20n_transaction_complete" != true ]] || return 0
    printf '%s_rollback_started=true\n' "$prefix" >&2
    action20n_rollback_stage=$(mktemp "$(dirname "$action20n_main_configuration")/.keepalived.conf.action20n-rollback.XXXXXX") || return 125
    run_captured rollback_install install -o "$action20n_expected_owner" \
        -g "$action20n_expected_group" -m 0644 \
        "$action20n_backup_directory/keepalived.conf.before" "$action20n_rollback_stage" || action20n_rollback_failed=true
    if [[ "$action20n_rollback_failed" = false ]]; then
        run_captured rollback_rename mv -fT "$action20n_rollback_stage" \
            "$action20n_main_configuration" || action20n_rollback_failed=true
    fi
    [[ "$action20n_rollback_failed" = false ]] || return 125
    [[ "$(file_hash "$action20n_main_configuration" 2>/dev/null || true)" = "$action20n_expected_main_sha256" ]] || return 125
    [[ "$(keepalived_property MainPID 2>/dev/null || true)" = "$action20n_keepalived_pid_before" ]] || return 125
    [[ "$(keepalived_property NRestarts 2>/dev/null || true)" = "$action20n_keepalived_restarts_before" ]] || return 125
    printf '%s_rollback_complete=true\n' "$prefix" >&2
}
cleanup() {
    local action20n_cleanup_status=$?

    trap - EXIT INT TERM
    rollback || action20n_cleanup_status=125
    [[ -z "$action20n_install_stage" || ! -e "$action20n_install_stage" ]] || rm -f -- "$action20n_install_stage"
    [[ -z "$action20n_transaction_root" || ! -d "$action20n_transaction_root" ]] || rm -rf -- "$action20n_transaction_root"
    exit "$action20n_cleanup_status"
}
run_self_test() (
    local action20n_self_root
    local action20n_self_source
    local action20n_self_candidate

    [[ "$(expected_checks | wc -l)" -eq 71 ]] || return 1
    [[ "$(expected_checks | LC_ALL=C sort -u | wc -l)" -eq 71 ]] || return 1
    [[ "$(expected_checks | grep -Evc '^[a-z0-9_]+$')" -eq 0 ]] || return 1
    action20n_self_root=$(mktemp -d /tmp/caddy-action20n-self.XXXXXX) || return 1
    trap 'rm -rf -- "$action20n_self_root"' EXIT
    action20n_self_source=$action20n_self_root/source
    action20n_self_candidate=$action20n_self_root/candidate
    printf '%s\n' 'global_defs {' '    enable_dbus' '}' >"$action20n_self_source"
    build_candidate "$action20n_self_source" "$action20n_self_candidate" || return 1
    [[ "$(tail -n 1 "$action20n_self_candidate")" = "$include_record" ]] || return 1
    global_defs_contains_enable_dbus "$action20n_self_candidate" || return 1
    sed '/enable_dbus/d' "$action20n_self_source" >"$action20n_self_root/missing"
    if global_defs_contains_enable_dbus "$action20n_self_root/missing"; then return 1; fi
    printf '%s_self_test_complete=true\n' "$prefix"
)

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]] || exit 64
        expected_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        run_self_test
        exit 0
        ;;
    --stage)
        [[ $# -eq 2 && "$2" = /* ]] || exit 64
        action20n_source_path=$2/keepalived-pihole0.conf
        ;;
    *)
        printf 'Usage: %s --expected-checks|--self-test|--stage ABSOLUTE_DIRECTORY\n' "${0##*/}" >&2
        exit 64
        ;;
esac

configure_paths
action20n_transaction_root=$(mktemp -d "${action20n_root:-/}/run/caddy-action20n.XXXXXX")
readonly action20n_transaction_root
trap cleanup EXIT INT TERM
chown "$action20n_expected_owner:$action20n_expected_group" "$action20n_transaction_root"
chmod 0700 "$action20n_transaction_root"
action20n_candidate=$action20n_transaction_root/keepalived.conf.candidate
action20n_expected_candidate=$action20n_transaction_root/keepalived.conf.expected
readonly action20n_candidate action20n_expected_candidate
configure_expected_hashes_for_test "$action20n_source_path"
validate_live_prestate
validate_source_and_candidate "$action20n_source_path"
create_backup
action20n_install_stage=$(mktemp "$(dirname "$action20n_main_configuration")/.keepalived.conf.action20n.XXXXXX")
action20n_mutation_started=true
record_check mutation_started test "$action20n_mutation_started" = true
run_captured install_candidate install -o "$action20n_expected_owner" \
    -g "$action20n_expected_group" -m 0644 \
    "$action20n_candidate" "$action20n_install_stage"
run_captured rename_candidate mv -fT "$action20n_install_stage" "$action20n_main_configuration"
if [[ "${ACTION20N_TEST_FAIL_AFTER_INSTALL:-}" = 1 ]]; then
    printf '%s_test_injected_postinstall_failure=true\n' "$prefix" >&2
    exit 1
fi
validate_live_poststate
action20n_transaction_complete=true
printf '%s_node=node-a\n' "$prefix"
printf '%s_main_configuration_mutated=true\n' "$prefix"
printf '%s_backup_retained=true\n' "$prefix"
printf '%s_keepalived_reload=false\n' "$prefix"
printf '%s_keepalived_restart=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_vrrp_transition=false\n' "$prefix"
printf '%s_vip_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
