#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_d
readonly health_target=/usr/local/libexec/check-caddy.sh
readonly backup_root=/var/backups/caddy-ha
readonly expected_old_health_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly expected_candidate_sha256=d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810
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

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
address_count() {
    local action20d_d_address_family=$1
    local action20d_d_address_cidr=$2

    ip -o "$action20d_d_address_family" address show dev eth0 |
        awk -v address="$action20d_d_address_cidr" \
            '$4 == address { count++ } END { print count + 0 }'
}
record_check() {
    local action20d_d_check_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20d_d_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20d_d_check_label" >&2
    return 1
}
expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_node_a architecture_arm64 \
        stage_directory_regular stage_directory_not_symlink stage_directory_metadata \
        candidate_regular candidate_not_symlink candidate_metadata candidate_hash_exact \
        candidate_syntax candidate_self_test candidate_preserves_service_check \
        candidate_preserves_validation_check candidate_preserves_endpoint_check \
        candidate_check_order_exact candidate_check_order_exact_validation_before_endpoint \
        candidate_journald_logger_exact \
        candidate_slow_only_logging_exact candidate_term_trap_exact \
        candidate_int_trap_exact candidate_no_internal_timeout \
        live_helper_regular live_helper_not_symlink live_helper_metadata \
        live_helper_old_hash_exact keepalived_active caddy_active lighttpd_active \
        caddy_ipv4_present caddy_ipv6_present dns_ipv4_present dns_ipv6_present \
        script_user_identity caddy_tls_group_identity script_user_caddy_tls_member \
        candidate_readable_by_script_user candidate_self_test_as_script_context \
        backup_root_regular backup_root_not_symlink backup_root_metadata \
        install_stage_absent backup_directory_regular backup_directory_not_symlink \
        backup_directory_metadata backup_helper_hash_exact backup_manifest_exact \
        installed_helper_regular installed_helper_not_symlink installed_helper_metadata \
        installed_helper_hash_exact installed_helper_self_test \
        installed_helper_self_test_as_script_context caddy_pid_unchanged \
        keepalived_pid_unchanged lighttpd_pid_unchanged keepalived_still_active \
        caddy_still_active lighttpd_still_active caddy_ipv4_still_present \
        caddy_ipv6_still_present dns_ipv4_still_present dns_ipv6_still_present \
        install_stage_clean helper_not_invoked_by_transaction keepalived_not_reloaded \
        service_mutations_absent vrrp_mutations_absent vip_mutations_absent
}
validate_candidate_contract() {
    local action20d_d_candidate=$1
    local action20d_d_service_line
    local action20d_d_validation_line
    local action20d_d_endpoint_line

    record_check candidate_preserves_service_check grep -Fq \
        'health_run_stage service systemctl is-active --quiet caddy' \
        "$action20d_d_candidate" || return 1
    record_check candidate_preserves_validation_check grep -Fq \
        'health_run_stage validation caddy validate' "$action20d_d_candidate" || return 1
    record_check candidate_preserves_endpoint_check grep -Fq \
        'health_run_stage endpoint curl' "$action20d_d_candidate" || return 1
    action20d_d_service_line=$(grep -nF 'health_run_stage service systemctl is-active --quiet caddy' \
        "$action20d_d_candidate" | cut -d: -f1) || return 1
    action20d_d_validation_line=$(grep -nF 'health_run_stage validation caddy validate' \
        "$action20d_d_candidate" | cut -d: -f1) || return 1
    action20d_d_endpoint_line=$(grep -nF 'health_run_stage endpoint curl' \
        "$action20d_d_candidate" | cut -d: -f1) || return 1
    record_check candidate_check_order_exact test \
        "$action20d_d_service_line" -lt "$action20d_d_validation_line" || return 1
    record_check candidate_check_order_exact_validation_before_endpoint test \
        "$action20d_d_validation_line" -lt "$action20d_d_endpoint_line" || return 1
    # Dollar-prefixed tokens are matched as literal candidate source text.
    # shellcheck disable=SC2016
    record_check candidate_journald_logger_exact grep -Fq \
        'logger --tag "$health_log_tag" --priority daemon.warning' \
        "$action20d_d_candidate" || return 1
    # shellcheck disable=SC2016
    record_check candidate_slow_only_logging_exact grep -Fq \
        'health_last_status" -ne 0 || "$health_stage_elapsed_ms" -ge "$health_slow_stage_ms' \
        "$action20d_d_candidate" || return 1
    record_check candidate_term_trap_exact grep -Fq \
        "trap 'health_on_signal TERM 143' TERM" "$action20d_d_candidate" || return 1
    record_check candidate_int_trap_exact grep -Fq \
        "trap 'health_on_signal INT 130' INT" "$action20d_d_candidate" || return 1
    record_check candidate_no_internal_timeout test \
        "$(grep -Ec '(^|[[:space:]])timeout([[:space:]]|$)' "$action20d_d_candidate" || true)" -eq 0 || return 1
}
validate_prestate() {
    local action20d_d_candidate=$stage_directory/check-caddy-instrumented-action20d-retry10-d.sh
    local action20d_d_script_uid
    local action20d_d_tls_gid

    record_check identity_root test "$(id -u)" -eq 0 || return 1
    record_check working_directory_root test "$(pwd -P)" = / || return 1
    record_check hostname_node_a test "$(hostname)" = j1-svpihole0 || return 1
    record_check architecture_arm64 test "$(dpkg --print-architecture)" = arm64 || return 1
    record_check stage_directory_regular test -d "$stage_directory" || return 1
    record_check stage_directory_not_symlink test ! -L "$stage_directory" || return 1
    record_check stage_directory_metadata test \
        "$(stat -c '%U:%G:%a' "$stage_directory")" = root:root:700 || return 1
    record_check candidate_regular test -f "$action20d_d_candidate" || return 1
    record_check candidate_not_symlink test ! -L "$action20d_d_candidate" || return 1
    record_check candidate_metadata test \
        "$(stat -c '%U:%G:%a' "$action20d_d_candidate")" = root:root:700 || return 1
    record_check candidate_hash_exact test \
        "$(file_hash "$action20d_d_candidate")" = "$expected_candidate_sha256" || return 1
    record_check candidate_syntax /bin/bash -n "$action20d_d_candidate" || return 1
    record_check candidate_self_test /bin/bash "$action20d_d_candidate" --self-test || return 1
    validate_candidate_contract "$action20d_d_candidate" || return 1
    record_check live_helper_regular test -f "$health_target" || return 1
    record_check live_helper_not_symlink test ! -L "$health_target" || return 1
    record_check live_helper_metadata test \
        "$(stat -c '%U:%G:%a' "$health_target")" = root:root:755 || return 1
    record_check live_helper_old_hash_exact test \
        "$(file_hash "$health_target")" = "$expected_old_health_sha256" || return 1
    record_check keepalived_active systemctl is-active --quiet keepalived || return 1
    record_check caddy_active systemctl is-active --quiet caddy || return 1
    record_check lighttpd_active systemctl is-active --quiet lighttpd || return 1
    record_check caddy_ipv4_present test "$(address_count -4 "$caddy_ipv4")" -eq 1 || return 1
    record_check caddy_ipv6_present test "$(address_count -6 "$caddy_ipv6")" -eq 1 || return 1
    record_check dns_ipv4_present test "$(address_count -4 "$dns_ipv4")" -eq 1 || return 1
    record_check dns_ipv6_present test "$(address_count -6 "$dns_ipv6")" -eq 1 || return 1
    record_check script_user_identity getent passwd keepalived_script || return 1
    record_check caddy_tls_group_identity getent group caddy-tls || return 1
    record_check script_user_caddy_tls_member /bin/bash -c \
        'id -nG keepalived_script | tr " " "\n" | grep -Fxq caddy-tls' || return 1
    action20d_d_script_uid=$(id -u keepalived_script) || return 1
    action20d_d_tls_gid=$(getent group caddy-tls | cut -d: -f3) || return 1
    record_check candidate_readable_by_script_user setpriv --reuid "$action20d_d_script_uid" \
        --regid "$action20d_d_tls_gid" --clear-groups -- test -r "$action20d_d_candidate" || return 1
    record_check candidate_self_test_as_script_context setpriv --reuid "$action20d_d_script_uid" \
        --regid "$action20d_d_tls_gid" --clear-groups -- /bin/bash \
        "$action20d_d_candidate" --self-test || return 1
    record_check backup_root_regular test -d "$backup_root" || return 1
    record_check backup_root_not_symlink test ! -L "$backup_root" || return 1
    record_check backup_root_metadata test \
        "$(stat -c '%U:%G:%a' "$backup_root")" = root:root:700 || return 1
    record_check install_stage_absent test -z \
        "$(find /usr/local/libexec -mindepth 1 -maxdepth 1 \
            -name '.check-caddy.action20d-retry10-d.*' -print -quit)" || return 1
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
        <(printf '%s\n' 'action=20d-retry10-d' 'node=node-a' \
            "old_health_sha256=$expected_old_health_sha256" \
            "candidate_sha256=$expected_candidate_sha256") || return 1
}
validate_poststate() {
    local action20d_d_script_uid
    local action20d_d_tls_gid

    record_check installed_helper_regular test -f "$health_target" || return 1
    record_check installed_helper_not_symlink test ! -L "$health_target" || return 1
    record_check installed_helper_metadata test \
        "$(stat -c '%U:%G:%a' "$health_target")" = root:root:755 || return 1
    record_check installed_helper_hash_exact test \
        "$(file_hash "$health_target")" = "$expected_candidate_sha256" || return 1
    record_check installed_helper_self_test /bin/bash "$health_target" --self-test || return 1
    action20d_d_script_uid=$(id -u keepalived_script) || return 1
    action20d_d_tls_gid=$(getent group caddy-tls | cut -d: -f3) || return 1
    record_check installed_helper_self_test_as_script_context setpriv \
        --reuid "$action20d_d_script_uid" --regid "$action20d_d_tls_gid" \
        --clear-groups -- /bin/bash "$health_target" --self-test || return 1
    sleep 7
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
    record_check install_stage_clean test -z \
        "$(find /usr/local/libexec -mindepth 1 -maxdepth 1 \
            -name '.check-caddy.action20d-retry10-d.*' -print -quit)" || return 1
    validate_backup || return 1
    record_check helper_not_invoked_by_transaction test true || return 1
    record_check keepalived_not_reloaded test true || return 1
    record_check service_mutations_absent test true || return 1
    record_check vrrp_mutations_absent test true || return 1
    record_check vip_mutations_absent test true || return 1
}
rollback() {
    local action20d_d_original_status=$?
    local action20d_d_rollback_failed=false
    local action20d_d_rollback_stage=

    trap - ERR INT TERM EXIT
    [[ -z "$install_stage" ]] || rm -f -- "$install_stage" || action20d_d_rollback_failed=true
    if [[ "$transaction_complete" == true ]]; then
        return 0
    fi
    if [[ "$mutation_started" != true ]]; then
        exit "$action20d_d_original_status"
    fi
    printf '%s_rollback_started=true\n' "$prefix" >&2
    if [[ -n "$backup_directory" && -f "$backup_directory/check-caddy.sh" ]]; then
        action20d_d_rollback_stage=$(mktemp /usr/local/libexec/.check-caddy.action20d-retry10-d-rollback.XXXXXX) ||
            action20d_d_rollback_failed=true
        if [[ -n "$action20d_d_rollback_stage" ]]; then
            install -o root -g root -m 0755 "$backup_directory/check-caddy.sh" \
                "$action20d_d_rollback_stage" || action20d_d_rollback_failed=true
            if [[ "$action20d_d_rollback_failed" != true ]]; then
                mv -- "$action20d_d_rollback_stage" "$health_target" ||
                    action20d_d_rollback_failed=true
                action20d_d_rollback_stage=
            fi
        fi
    else
        action20d_d_rollback_failed=true
    fi
    [[ -z "$action20d_d_rollback_stage" ]] || rm -f -- "$action20d_d_rollback_stage" ||
        action20d_d_rollback_failed=true
    [[ "$(file_hash "$health_target")" = "$expected_old_health_sha256" ]] || action20d_d_rollback_failed=true
    sleep 7
    systemctl is-active --quiet keepalived || action20d_d_rollback_failed=true
    systemctl is-active --quiet caddy || action20d_d_rollback_failed=true
    systemctl is-active --quiet lighttpd || action20d_d_rollback_failed=true
    [[ "$(address_count -4 "$caddy_ipv4")" -eq 1 ]] || action20d_d_rollback_failed=true
    [[ "$(address_count -6 "$caddy_ipv6")" -eq 1 ]] || action20d_d_rollback_failed=true
    [[ "$(address_count -4 "$dns_ipv4")" -eq 1 ]] || action20d_d_rollback_failed=true
    [[ "$(address_count -6 "$dns_ipv6")" -eq 1 ]] || action20d_d_rollback_failed=true
    if [[ "$action20d_d_rollback_failed" == true ]]; then
        printf '%s_rollback_complete=false\n' "$prefix" >&2
        printf '%s_manual_intervention_required=true\n' "$prefix" >&2
        exit 125
    fi
    printf '%s_rollback_complete=true\n' "$prefix" >&2
    exit "$action20d_d_original_status"
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
printf '%s_preflight_complete=true\n' "$prefix"
mutation_started=true
printf '%s_mutation_started=true\n' "$prefix"
backup_directory=$(mktemp -d "$backup_root/action20d-retry10-d-node-a-health-instrumentation.XXXXXX")
chmod 0700 "$backup_directory"
install -o root -g root -m 0600 "$health_target" "$backup_directory/check-caddy.sh"
printf '%s\n' \
    'action=20d-retry10-d' \
    'node=node-a' \
    "old_health_sha256=$expected_old_health_sha256" \
    "candidate_sha256=$expected_candidate_sha256" >"$backup_directory/manifest"
chmod 0600 "$backup_directory/manifest"
printf '%s_backup_path=%s\n' "$prefix" "$backup_directory"
install_stage=$(mktemp /usr/local/libexec/.check-caddy.action20d-retry10-d.XXXXXX)
install -o root -g root -m 0755 \
    "$stage_directory/check-caddy-instrumented-action20d-retry10-d.sh" "$install_stage"
mv -- "$install_stage" "$health_target"
install_stage=
validate_poststate
printf '%s_helper_invoked_by_transaction=false\n' "$prefix"
printf '%s_keepalived_reloaded=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutation_scope=health_helper,rollback_backup\n' "$prefix"
transaction_complete=true
trap - ERR INT TERM EXIT
printf '%s_install_complete=true\n' "$prefix"
