#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20h
readonly health_target=/usr/local/libexec/check-caddy.sh
readonly backup_root=/var/backups/caddy-ha
readonly expected_old_health_sha256=d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810
readonly expected_candidate_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly expected_main_sha256=357eb09c628fa3b78efcaacf53278ab09a6574b991820632ee3ec2614265d8e2
readonly expected_fragment_sha256=6f5a58ca8fd39a1218de6fc964f54aef69f374351c0727bbb0fabf899a80ef39
readonly expected_environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly caddy_ipv4=10.1.0.56/22
readonly caddy_ipv6=fd36:5aa8:6971:1::56/128
readonly dns_ipv4=10.1.0.55/22
readonly dns_ipv6=fd36:5aa8:6971:1::55/128

stage_directory=
backup_directory=
install_stage=
mutation_started=false
transaction_complete=false
caddy_pid_before=
keepalived_pid_before=
lighttpd_pid_before=
validation_root=
journal_cursor=
journal_path=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
address_count() {
    local action20h_address_family=$1
    local action20h_address_cidr=$2

    ip -o "$action20h_address_family" address show dev eth0 |
        awk -v address="$action20h_address_cidr" \
            '$4 == address { count++ } END { print count + 0 }'
}
record_check() {
    local action20h_check_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20h_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20h_check_label" >&2
    return 1
}
expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_node_a architecture_arm64 \
        stage_directory_regular stage_directory_not_symlink stage_directory_metadata \
        candidate_regular candidate_not_symlink candidate_metadata candidate_hash_exact \
        candidate_syntax candidate_self_test candidate_preserves_service_check \
        candidate_excludes_validation_check candidate_preserves_endpoint_check \
        candidate_check_order_exact full_caddy_validation_exact_context \
        candidate_journald_logger_exact \
        candidate_slow_only_logging_exact candidate_term_trap_exact \
        candidate_int_trap_exact candidate_no_internal_timeout \
        live_helper_regular live_helper_not_symlink live_helper_metadata \
        live_helper_old_hash_exact main_hash_exact fragment_hash_exact \
        environment_hash_exact keepalived_active caddy_active lighttpd_active \
        caddy_ipv4_present caddy_ipv6_present dns_ipv4_present dns_ipv6_present \
        vrrp_master_before \
        script_user_identity script_user_uid_exact script_user_primary_gid_exact \
        caddy_tls_group_identity caddy_tls_gid_exact script_user_caddy_tls_member \
        candidate_readable_by_script_user candidate_self_test_as_script_context \
        backup_root_regular backup_root_not_symlink backup_root_metadata \
        install_stage_absent journal_cursor_captured backup_directory_regular \
        backup_directory_not_symlink \
        backup_directory_metadata backup_helper_hash_exact backup_manifest_exact \
        installed_helper_regular installed_helper_not_symlink installed_helper_metadata \
        installed_helper_hash_exact installed_helper_self_test \
        installed_helper_self_test_as_script_context caddy_pid_unchanged \
        keepalived_pid_unchanged lighttpd_pid_unchanged keepalived_still_active \
        caddy_still_active lighttpd_still_active caddy_ipv4_still_present \
        caddy_ipv6_still_present dns_ipv4_still_present dns_ipv6_still_present \
        vrrp_master_after keepalived_journal_captured keepalived_no_overlap \
        keepalived_no_helper_failure keepalived_no_fault_transition \
        install_stage_clean helper_not_invoked_by_transaction keepalived_not_reloaded \
        service_mutations_absent vrrp_mutations_absent vip_mutations_absent
}
validate_candidate_contract() {
    local action20h_candidate=$1
    local action20h_service_line
    local action20h_endpoint_line

    record_check candidate_preserves_service_check grep -Fq \
        'health_run_stage service systemctl is-active --quiet caddy' \
        "$action20h_candidate" || return 1
    record_check candidate_excludes_validation_check test \
        "$(grep -Fc 'caddy validate' "$action20h_candidate" || true)" -eq 0 || return 1
    record_check candidate_preserves_endpoint_check grep -Fq \
        'health_run_stage endpoint curl' "$action20h_candidate" || return 1
    action20h_service_line=$(grep -nF \
        'health_run_stage service systemctl is-active --quiet caddy' \
        "$action20h_candidate" | cut -d: -f1) || return 1
    action20h_endpoint_line=$(grep -nF 'health_run_stage endpoint curl' \
        "$action20h_candidate" | cut -d: -f1) || return 1
    record_check candidate_check_order_exact test \
        "$action20h_service_line" -lt "$action20h_endpoint_line" || return 1
    # shellcheck disable=SC2016
    record_check candidate_journald_logger_exact grep -Fq \
        'logger --tag "$health_log_tag" --priority daemon.warning' \
        "$action20h_candidate" || return 1
    # shellcheck disable=SC2016
    record_check candidate_slow_only_logging_exact grep -Fq \
        'health_last_status" -ne 0 || "$health_stage_elapsed_ms" -ge "$health_slow_stage_ms' \
        "$action20h_candidate" || return 1
    record_check candidate_term_trap_exact grep -Fq \
        "trap 'health_on_signal TERM 143' TERM" "$action20h_candidate" || return 1
    record_check candidate_int_trap_exact grep -Fq \
        "trap 'health_on_signal INT 130' INT" "$action20h_candidate" || return 1
    record_check candidate_no_internal_timeout test \
        "$(grep -Ec '(^|[[:space:]])timeout([[:space:]]|$)' "$action20h_candidate" || true)" -eq 0 || return 1
}
stream_safe() {
    local action20h_stream_path=$1

    [[ "$(wc -c <"$action20h_stream_path")" -le 65536 ]] || return 1
    [[ "$(awk 'END { print NR }' "$action20h_stream_path")" -le 256 ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20h_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20h_stream_path" || return 1
}
emit_validation_stream() {
    local action20h_stream_label=$1
    local action20h_stream_path=$2

    printf '%s_validation_%s_bytes=%s\n' "$prefix" "$action20h_stream_label" \
        "$(wc -c <"$action20h_stream_path")"
    printf '%s_validation_%s_lines=%s\n' "$prefix" "$action20h_stream_label" \
        "$(awk 'END { print NR }' "$action20h_stream_path")"
    printf '%s_validation_%s_sha256=%s\n' "$prefix" "$action20h_stream_label" \
        "$(file_hash "$action20h_stream_path")"
    stream_safe "$action20h_stream_path" || return 1
    printf '%s_validation_%s_classification=bounded_safe\n' "$prefix" "$action20h_stream_label"
    if [[ -s "$action20h_stream_path" ]]; then
        printf '%s_validation_%s_begin\n' "$prefix" "$action20h_stream_label"
        cat "$action20h_stream_path"
        printf '%s_validation_%s_end\n' "$prefix" "$action20h_stream_label"
    else
        printf '%s_validation_%s_content_secured=empty\n' "$prefix" "$action20h_stream_label"
    fi
}
validate_full_caddy_config() {
    local action20h_script_uid=$1
    local action20h_tls_gid=$2
    local action20h_stdout=$validation_root/caddy-validate.stdout
    local action20h_stderr=$validation_root/caddy-validate.stderr
    local action20h_status=0

    install -d -o "$action20h_script_uid" -g "$action20h_tls_gid" -m 0700 \
        "$validation_root/home" "$validation_root/config" \
        "$validation_root/data" || return 1
    : >"$action20h_stdout"
    : >"$action20h_stderr"
    chmod 0600 "$action20h_stdout" "$action20h_stderr"
    setpriv --reuid "$action20h_script_uid" --regid "$action20h_tls_gid" \
        --clear-groups -- env HOME="$validation_root/home" \
        XDG_CONFIG_HOME="$validation_root/config" XDG_DATA_HOME="$validation_root/data" \
        caddy validate --config /etc/caddy/current/Caddyfile --adapter caddyfile \
        >"$action20h_stdout" 2>"$action20h_stderr" || action20h_status=$?
    emit_validation_stream stdout "$action20h_stdout" || return 1
    emit_validation_stream stderr "$action20h_stderr" || return 1
    printf '%s_validation_status=%s\n' "$prefix" "$action20h_status"
    [[ "$action20h_status" -eq 0 ]]
}
validate_prestate() {
    local action20h_candidate=$stage_directory/check-caddy-vrrp-action20h.sh
    local action20h_script_uid
    local action20h_tls_gid

    record_check identity_root test "$(id -u)" -eq 0 || return 1
    record_check working_directory_root test "$(pwd -P)" = / || return 1
    record_check hostname_node_a test "$(hostname)" = j1-svpihole0 || return 1
    record_check architecture_arm64 test "$(dpkg --print-architecture)" = arm64 || return 1
    record_check stage_directory_regular test -d "$stage_directory" || return 1
    record_check stage_directory_not_symlink test ! -L "$stage_directory" || return 1
    record_check stage_directory_metadata test \
        "$(stat -c '%U:%G:%a' "$stage_directory")" = root:caddy-tls:710 || return 1
    record_check candidate_regular test -f "$action20h_candidate" || return 1
    record_check candidate_not_symlink test ! -L "$action20h_candidate" || return 1
    record_check candidate_metadata test \
        "$(stat -c '%U:%G:%a' "$action20h_candidate")" = root:caddy-tls:750 || return 1
    record_check candidate_hash_exact test \
        "$(file_hash "$action20h_candidate")" = "$expected_candidate_sha256" || return 1
    record_check candidate_syntax /bin/bash -n "$action20h_candidate" || return 1
    record_check candidate_self_test /bin/bash "$action20h_candidate" --self-test || return 1
    validate_candidate_contract "$action20h_candidate" || return 1
    record_check live_helper_regular test -f "$health_target" || return 1
    record_check live_helper_not_symlink test ! -L "$health_target" || return 1
    record_check live_helper_metadata test \
        "$(stat -c '%U:%G:%a' "$health_target")" = root:root:755 || return 1
    record_check live_helper_old_hash_exact test \
        "$(file_hash "$health_target")" = "$expected_old_health_sha256" || return 1
    record_check main_hash_exact test \
        "$(file_hash /etc/keepalived/keepalived.conf)" = "$expected_main_sha256" || return 1
    record_check fragment_hash_exact test \
        "$(file_hash /etc/keepalived/conf.d/caddy-ha.conf)" = "$expected_fragment_sha256" || return 1
    record_check environment_hash_exact test \
        "$(file_hash /etc/default/caddy-ha)" = "$expected_environment_sha256" || return 1
    record_check keepalived_active systemctl is-active --quiet keepalived || return 1
    record_check caddy_active systemctl is-active --quiet caddy || return 1
    record_check lighttpd_active systemctl is-active --quiet lighttpd || return 1
    record_check caddy_ipv4_present test "$(address_count -4 "$caddy_ipv4")" -eq 1 || return 1
    record_check caddy_ipv6_present test "$(address_count -6 "$caddy_ipv6")" -eq 1 || return 1
    record_check dns_ipv4_present test "$(address_count -4 "$dns_ipv4")" -eq 1 || return 1
    record_check dns_ipv6_present test "$(address_count -6 "$dns_ipv6")" -eq 1 || return 1
    record_check vrrp_master_before test "$(sed -n '1p' /run/caddy-ha/vrrp-state)" = MASTER || return 1
    record_check script_user_identity getent passwd keepalived_script || return 1
    record_check script_user_uid_exact test "$(id -u keepalived_script)" -eq 993 || return 1
    record_check script_user_primary_gid_exact test "$(id -g keepalived_script)" -eq 989 || return 1
    record_check caddy_tls_group_identity getent group caddy-tls || return 1
    record_check caddy_tls_gid_exact test \
        "$(getent group caddy-tls | cut -d: -f3)" -eq 991 || return 1
    record_check script_user_caddy_tls_member /bin/bash -c \
        'id -nG keepalived_script | tr " " "\n" | grep -Fxq caddy-tls' || return 1
    action20h_script_uid=$(id -u keepalived_script) || return 1
    action20h_tls_gid=$(getent group caddy-tls | cut -d: -f3) || return 1
    record_check candidate_readable_by_script_user setpriv --reuid "$action20h_script_uid" \
        --regid "$action20h_tls_gid" --clear-groups -- test -r "$action20h_candidate" || return 1
    record_check candidate_self_test_as_script_context setpriv --reuid "$action20h_script_uid" \
        --regid "$action20h_tls_gid" --clear-groups -- /bin/bash \
        "$action20h_candidate" --self-test || return 1
    validation_root=$(mktemp -d /run/caddy-action20h-validation.XXXXXX) || return 1
    chmod 0710 "$validation_root"
    chown root:caddy-tls "$validation_root"
    record_check full_caddy_validation_exact_context validate_full_caddy_config \
        "$action20h_script_uid" "$action20h_tls_gid" || return 1
    record_check backup_root_regular test -d "$backup_root" || return 1
    record_check backup_root_not_symlink test ! -L "$backup_root" || return 1
    record_check backup_root_metadata test \
        "$(stat -c '%U:%G:%a' "$backup_root")" = root:root:700 || return 1
    record_check install_stage_absent test -z \
        "$(find /usr/local/libexec -mindepth 1 -maxdepth 1 \
            -name '.check-caddy.action20h.*' -print -quit)" || return 1
    caddy_pid_before=$(systemctl show caddy.service --property=MainPID --value) || return 1
    keepalived_pid_before=$(systemctl show keepalived.service --property=MainPID --value) || return 1
    lighttpd_pid_before=$(systemctl show lighttpd.service --property=MainPID --value) || return 1
}
validate_backup() {
    record_check backup_directory_regular test -d "$backup_directory" || return 1
    record_check backup_directory_not_symlink test ! -L "$backup_directory" || return 1
    record_check backup_directory_metadata test \
        "$(stat -c '%U:%G:%a' "$backup_directory")" = root:root:700 || return 1
    record_check backup_helper_hash_exact test \
        "$(file_hash "$backup_directory/check-caddy.sh")" = "$expected_old_health_sha256" || return 1
    record_check backup_manifest_exact cmp -s "$backup_directory/manifest" \
        <(printf '%s\n' 'action=20h' 'node=node-a' \
            "old_health_sha256=$expected_old_health_sha256" \
            "candidate_sha256=$expected_candidate_sha256") || return 1
}
validate_poststate() {
    local action20h_script_uid
    local action20h_tls_gid

    record_check installed_helper_regular test -f "$health_target" || return 1
    record_check installed_helper_not_symlink test ! -L "$health_target" || return 1
    record_check installed_helper_metadata test \
        "$(stat -c '%U:%G:%a' "$health_target")" = root:root:755 || return 1
    record_check installed_helper_hash_exact test \
        "$(file_hash "$health_target")" = "$expected_candidate_sha256" || return 1
    record_check installed_helper_self_test /bin/bash "$health_target" --self-test || return 1
    action20h_script_uid=$(id -u keepalived_script) || return 1
    action20h_tls_gid=$(getent group caddy-tls | cut -d: -f3) || return 1
    record_check installed_helper_self_test_as_script_context setpriv \
        --reuid "$action20h_script_uid" --regid "$action20h_tls_gid" \
        --clear-groups -- /bin/bash "$health_target" --self-test || return 1
    sleep 12
    journal_path=$(mktemp /run/caddy-action20h-journal.XXXXXX) || return 1
    chmod 0600 "$journal_path"
    journalctl --unit keepalived.service --after-cursor "$journal_cursor" \
        --no-pager -o cat \
        >"$journal_path" || return 1
    record_check keepalived_journal_captured test -f "$journal_path" || return 1
    record_check keepalived_no_overlap test \
        "$(grep -Fc 'already running, expect idle - skipping run' "$journal_path" || true)" -eq 0 || return 1
    record_check keepalived_no_helper_failure test \
        "$(grep -Ec 'Script .check_caddy. now returning (1|143)' "$journal_path" || true)" -eq 0 || return 1
    record_check keepalived_no_fault_transition test \
        "$(grep -Ec 'CADDY_(DUALSTACK|IPV4|IPV6).*Entering FAULT STATE' "$journal_path" || true)" -eq 0 || return 1
    record_check caddy_pid_unchanged test \
        "$(systemctl show caddy.service --property=MainPID --value)" = "$caddy_pid_before" || return 1
    record_check keepalived_pid_unchanged test \
        "$(systemctl show keepalived.service --property=MainPID --value)" = "$keepalived_pid_before" || return 1
    record_check lighttpd_pid_unchanged test \
        "$(systemctl show lighttpd.service --property=MainPID --value)" = "$lighttpd_pid_before" || return 1
    record_check keepalived_still_active systemctl is-active --quiet keepalived || return 1
    record_check caddy_still_active systemctl is-active --quiet caddy || return 1
    record_check lighttpd_still_active systemctl is-active --quiet lighttpd || return 1
    record_check caddy_ipv4_still_present test "$(address_count -4 "$caddy_ipv4")" -eq 1 || return 1
    record_check caddy_ipv6_still_present test "$(address_count -6 "$caddy_ipv6")" -eq 1 || return 1
    record_check dns_ipv4_still_present test "$(address_count -4 "$dns_ipv4")" -eq 1 || return 1
    record_check dns_ipv6_still_present test "$(address_count -6 "$dns_ipv6")" -eq 1 || return 1
    record_check vrrp_master_after test "$(sed -n '1p' /run/caddy-ha/vrrp-state)" = MASTER || return 1
    record_check install_stage_clean test -z \
        "$(find /usr/local/libexec -mindepth 1 -maxdepth 1 \
            -name '.check-caddy.action20h.*' -print -quit)" || return 1
    validate_backup || return 1
    record_check helper_not_invoked_by_transaction test true || return 1
    record_check keepalived_not_reloaded test true || return 1
    record_check service_mutations_absent test true || return 1
    record_check vrrp_mutations_absent test true || return 1
    record_check vip_mutations_absent test true || return 1
}
rollback() {
    local action20h_original_status=$?
    local action20h_rollback_failed=false
    local action20h_rollback_stage=

    trap - ERR INT TERM EXIT
    [[ -z "$install_stage" ]] || rm -f -- "$install_stage" || action20h_rollback_failed=true
    [[ -z "$journal_path" ]] || rm -f -- "$journal_path" || action20h_rollback_failed=true
    [[ -z "$validation_root" ]] || rm -rf -- "$validation_root" || action20h_rollback_failed=true
    if [[ "$transaction_complete" == true ]]; then
        return 0
    fi
    if [[ "$mutation_started" != true ]]; then
        exit "$action20h_original_status"
    fi
    printf '%s_rollback_started=true\n' "$prefix" >&2
    if [[ -n "$backup_directory" && -f "$backup_directory/check-caddy.sh" ]]; then
        action20h_rollback_stage=$(mktemp /usr/local/libexec/.check-caddy.action20h-rollback.XXXXXX) ||
            action20h_rollback_failed=true
        if [[ -n "$action20h_rollback_stage" ]]; then
            install -o root -g root -m 0755 "$backup_directory/check-caddy.sh" \
                "$action20h_rollback_stage" || action20h_rollback_failed=true
            if [[ "$action20h_rollback_failed" != true ]]; then
                mv -- "$action20h_rollback_stage" "$health_target" ||
                    action20h_rollback_failed=true
                action20h_rollback_stage=
            fi
        fi
    else
        action20h_rollback_failed=true
    fi
    [[ -z "$action20h_rollback_stage" ]] || rm -f -- "$action20h_rollback_stage" ||
        action20h_rollback_failed=true
    [[ "$(file_hash "$health_target")" = "$expected_old_health_sha256" ]] || action20h_rollback_failed=true
    sleep 12
    systemctl is-active --quiet keepalived || action20h_rollback_failed=true
    systemctl is-active --quiet caddy || action20h_rollback_failed=true
    systemctl is-active --quiet lighttpd || action20h_rollback_failed=true
    [[ "$(address_count -4 "$caddy_ipv4")" -eq 1 ]] || action20h_rollback_failed=true
    [[ "$(address_count -6 "$caddy_ipv6")" -eq 1 ]] || action20h_rollback_failed=true
    [[ "$(address_count -4 "$dns_ipv4")" -eq 1 ]] || action20h_rollback_failed=true
    [[ "$(address_count -6 "$dns_ipv6")" -eq 1 ]] || action20h_rollback_failed=true
    if [[ "$action20h_rollback_failed" == true ]]; then
        printf '%s_rollback_complete=false\n' "$prefix" >&2
        printf '%s_manual_intervention_required=true\n' "$prefix" >&2
        exit 125
    fi
    printf '%s_rollback_complete=true\n' "$prefix" >&2
    exit "$action20h_original_status"
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]] || exit 64
        expected_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$expected_candidate_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$(expected_checks | LC_ALL=C sort -u | wc -l)" -eq "$(expected_checks | wc -l)" ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --stage)
        [[ $# -eq 2 ]] || exit 64
        stage_directory=$2
        ;;
    *)
        printf 'Usage: %s --expected-checks|--self-test|--stage DIRECTORY\n' "${0##*/}" >&2
        exit 64
        ;;
esac

trap rollback ERR INT TERM EXIT
validate_prestate
journal_cursor=$(journalctl --unit keepalived.service --lines=0 --show-cursor \
    --no-pager | sed -n 's/^-- cursor: //p')
record_check journal_cursor_captured test -n "$journal_cursor"
printf '%s_preflight_complete=true\n' "$prefix"
mutation_started=true
printf '%s_mutation_started=true\n' "$prefix"
backup_directory=$(mktemp -d "$backup_root/action20h-node-a-health-instrumentation.XXXXXX")
chmod 0700 "$backup_directory"
install -o root -g root -m 0600 "$health_target" "$backup_directory/check-caddy.sh"
printf '%s\n' \
    'action=20h' \
    'node=node-a' \
    "old_health_sha256=$expected_old_health_sha256" \
    "candidate_sha256=$expected_candidate_sha256" >"$backup_directory/manifest"
chmod 0600 "$backup_directory/manifest"
printf '%s_backup_path=%s\n' "$prefix" "$backup_directory"
install_stage=$(mktemp /usr/local/libexec/.check-caddy.action20h.XXXXXX)
install -o root -g root -m 0755 \
    "$stage_directory/check-caddy-vrrp-action20h.sh" "$install_stage"
mv -- "$install_stage" "$health_target"
install_stage=
validate_poststate
rm -f -- "$journal_path"
journal_path=
rm -rf -- "$validation_root"
validation_root=
printf '%s_helper_invoked_by_transaction=false\n' "$prefix"
printf '%s_keepalived_reloaded=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutation_scope=health_helper,rollback_backup\n' "$prefix"
transaction_complete=true
trap - ERR INT TERM EXIT
printf '%s_install_complete=true\n' "$prefix"
