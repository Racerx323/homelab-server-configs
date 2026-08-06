#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_d_retry2_a
readonly health_helper=/usr/local/libexec/check-caddy.sh
readonly backup_root=/var/backups/caddy-ha
readonly expected_backup_path=/var/backups/caddy-ha/action20d-retry10-d-retry2-node-a-health-instrumentation.18d7kI
readonly expected_health_sha256=d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810
readonly expected_old_health_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
address_count() {
    local action20d_retry2_a_address_family=$1
    local action20d_retry2_a_expected_cidr=$2

    ip -o "-$action20d_retry2_a_address_family" address show dev eth0 2>/dev/null |
        awk -v expected="$action20d_retry2_a_expected_cidr" \
            '$4 == expected { count++ } END { print count + 0 }'
}
unit_state() {
    local action20d_retry2_a_unit_name=$1

    printf '%s:%s:%s' \
        "$(systemctl is-active "$action20d_retry2_a_unit_name" 2>/dev/null || true)" \
        "$(systemctl show -p MainPID --value "$action20d_retry2_a_unit_name" 2>/dev/null || true)" \
        "$(systemctl show -p NRestarts --value "$action20d_retry2_a_unit_name" 2>/dev/null || true)"
}
tree_hash() {
    local action20d_retry2_a_tree_root=$1

    (
        cd "$action20d_retry2_a_tree_root"
        find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}
snapshot_state() {
    printf 'health=%s\n' "$(file_hash "$health_helper" 2>/dev/null || true)"
    printf 'health_metadata=%s\n' \
        "$(stat -c '%U:%G:%a' "$health_helper" 2>/dev/null || true)"
    printf 'backup=%s\n' "$(tree_hash "$expected_backup_path" 2>/dev/null || true)"
    printf 'addresses=%s:%s:%s:%s\n' \
        "$(address_count 4 "$caddy_ipv4_cidr")" \
        "$(address_count 6 "$caddy_ipv6_cidr")" \
        "$(address_count 4 "$dns_ipv4_cidr")" \
        "$(address_count 6 "$dns_ipv6_cidr")"
    printf 'vrrp_state=%s\n' "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)"
    printf 'keepalived=%s\n' "$(unit_state keepalived.service)"
    printf 'caddy=%s\n' "$(unit_state caddy.service)"
    printf 'lighttpd=%s\n' "$(unit_state lighttpd.service)"
}
expected_assertions() {
    printf '%s\n' \
        identity_root working_directory_root hostname_node_a architecture_arm64 \
        health_regular health_not_symlink health_metadata_exact health_hash_exact \
        health_syntax health_root_self_test_status_zero \
        health_root_self_test_stdout_exact health_root_self_test_stderr_empty \
        keepalived_script_uid_exact caddy_tls_gid_exact \
        keepalived_script_caddy_tls_member exact_context_readable \
        exact_context_executable exact_context_self_test_status_zero \
        exact_context_self_test_stdout_exact exact_context_self_test_stderr_empty \
        health_service_check_preserved health_validation_check_preserved \
        health_endpoint_check_preserved health_check_order_exact \
        health_journald_logger_exact health_term_trap_exact health_int_trap_exact \
        health_no_internal_timeout backup_count_exact backup_path_regular \
        backup_path_not_symlink backup_path_metadata_exact backup_helper_regular \
        backup_helper_not_symlink backup_helper_metadata_exact backup_helper_hash_exact \
        backup_manifest_regular backup_manifest_not_symlink \
        backup_manifest_metadata_exact backup_manifest_line_count_exact \
        backup_manifest_action_exact backup_manifest_node_exact \
        backup_manifest_old_hash_exact backup_manifest_candidate_hash_exact \
        payload_stage_residue_absent candidate_stage_residue_absent \
        install_stage_residue_absent keepalived_active caddy_active lighttpd_active \
        keepalived_pid_numeric caddy_pid_numeric lighttpd_pid_numeric \
        caddy_ipv4_count_exact caddy_ipv6_count_exact dns_ipv4_count_exact \
        dns_ipv6_count_exact vrrp_state_master before_snapshot_complete \
        after_snapshot_complete state_unchanged
}
record_assertion() {
    local action20d_retry2_a_assertion_label=$1

    shift
    if "$@"; then
        printf '%s_assertion_%s=true\n' "$prefix" \
            "$action20d_retry2_a_assertion_label"
        return 0
    fi
    printf '%s_assertion_%s=false\n' "$prefix" \
        "$action20d_retry2_a_assertion_label"
    return 1
}
safe_stream() {
    local action20d_retry2_a_stream_path=$1

    [[ "$(wc -c <"$action20d_retry2_a_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20d_retry2_a_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20d_retry2_a_stream_path" \
        >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20d_retry2_a_stream_path"
}
emit_stream() {
    local action20d_retry2_a_stream_label=$1
    local action20d_retry2_a_stream_path=$2

    printf '%s_capture_%s_bytes=%s\n' "$prefix" "$action20d_retry2_a_stream_label" \
        "$(wc -c <"$action20d_retry2_a_stream_path")"
    printf '%s_capture_%s_lines=%s\n' "$prefix" "$action20d_retry2_a_stream_label" \
        "$(line_count "$action20d_retry2_a_stream_path")"
    printf '%s_capture_%s_sha256=%s\n' "$prefix" "$action20d_retry2_a_stream_label" \
        "$(file_hash "$action20d_retry2_a_stream_path")"
    if ! safe_stream "$action20d_retry2_a_stream_path"; then
        printf '%s_capture_%s_classification=unsafe_retained\n' \
            "$prefix" "$action20d_retry2_a_stream_label" >&2
        return 97
    fi
    printf '%s_capture_%s_classification=bounded_safe\n' \
        "$prefix" "$action20d_retry2_a_stream_label"
    if [[ -s "$action20d_retry2_a_stream_path" ]]; then
        printf '%s_capture_%s_begin\n' "$prefix" "$action20d_retry2_a_stream_label"
        sed "s/^/${prefix}_capture_${action20d_retry2_a_stream_label}_content=/" \
            "$action20d_retry2_a_stream_path"
        printf '%s_capture_%s_end\n' "$prefix" "$action20d_retry2_a_stream_label"
    else
        printf '%s_capture_%s_content_secured=empty\n' \
            "$prefix" "$action20d_retry2_a_stream_label"
    fi
}
validate_health_contract() {
    local action20d_retry2_a_service_line
    local action20d_retry2_a_validation_line
    local action20d_retry2_a_endpoint_line

    run_assertion health_service_check_preserved grep -Fq \
        'health_run_stage service systemctl is-active --quiet caddy' "$health_helper"
    run_assertion health_validation_check_preserved grep -Fq \
        'health_run_stage validation caddy validate' "$health_helper"
    run_assertion health_endpoint_check_preserved grep -Fq \
        'health_run_stage endpoint curl' "$health_helper"
    action20d_retry2_a_service_line=$(grep -nF \
        'health_run_stage service systemctl is-active --quiet caddy' \
        "$health_helper" | cut -d: -f1) || return 1
    action20d_retry2_a_validation_line=$(grep -nF \
        'health_run_stage validation caddy validate' "$health_helper" | cut -d: -f1) || return 1
    action20d_retry2_a_endpoint_line=$(grep -nF \
        'health_run_stage endpoint curl' "$health_helper" | cut -d: -f1) || return 1
    run_assertion health_check_order_exact test \
        "$action20d_retry2_a_service_line" -lt "$action20d_retry2_a_validation_line" \
        -a "$action20d_retry2_a_validation_line" -lt "$action20d_retry2_a_endpoint_line"
    # Dollar-prefixed tokens are matched as literal helper source text.
    # shellcheck disable=SC2016
    run_assertion health_journald_logger_exact grep -Fq \
        'logger --tag "$health_log_tag" --priority daemon.warning' "$health_helper"
    run_assertion health_term_trap_exact grep -Fq \
        "trap 'health_on_signal TERM 143' TERM" "$health_helper"
    run_assertion health_int_trap_exact grep -Fq \
        "trap 'health_on_signal INT 130' INT" "$health_helper"
    run_assertion health_no_internal_timeout test \
        "$(grep -Ec '(^|[[:space:]])timeout([[:space:]]|$)' "$health_helper" || true)" -eq 0
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]] || exit 64
        expected_assertions
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$(expected_assertions | wc -l)" -gt 0 ]]
        [[ "$(expected_assertions | wc -l)" -eq "$(expected_assertions | LC_ALL=C sort -u | wc -l)" ]]
        [[ "$(expected_assertions | grep -Evc '^[a-z0-9_]+$')" -eq 0 ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --inspect)
        [[ $# -eq 1 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s --expected-assertions|--self-test|--inspect\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

work_root=$(mktemp -d /run/caddy-action20d-retry10-d-retry2-a-inspect.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
readonly root_stdout=$work_root/root-self-test.stdout
readonly root_stderr=$work_root/root-self-test.stderr
readonly context_stdout=$work_root/context-self-test.stdout
readonly context_stderr=$work_root/context-self-test.stderr
install -o root -g root -m 0600 /dev/null "$root_stdout"
install -o root -g root -m 0600 /dev/null "$root_stderr"
install -o root -g root -m 0600 /dev/null "$context_stdout"
install -o root -g root -m 0600 /dev/null "$context_stderr"

before_snapshot_status=0
before_snapshot=$(snapshot_state) || before_snapshot_status=$?
before_snapshot_sha256=$(printf '%s\n' "$before_snapshot" | sha256sum | awk '{ print $1 }')
readonly before_snapshot_status before_snapshot before_snapshot_sha256

root_self_test_status=0
/bin/bash "$health_helper" --self-test >"$root_stdout" 2>"$root_stderr" ||
    root_self_test_status=$?
readonly root_self_test_status

script_uid=$(id -u keepalived_script 2>/dev/null || true)
tls_gid=$(getent group caddy-tls 2>/dev/null | cut -d: -f3 || true)
readonly script_uid tls_gid
context_self_test_status=0
if [[ "$script_uid" =~ ^[0-9]+$ && "$tls_gid" =~ ^[0-9]+$ ]]; then
    setpriv --reuid "$script_uid" --regid "$tls_gid" --clear-groups -- \
        /bin/bash "$health_helper" --self-test \
        >"$context_stdout" 2>"$context_stderr" || context_self_test_status=$?
else
    context_self_test_status=97
fi
readonly context_self_test_status

emit_stream root_self_test_stdout "$root_stdout"
emit_stream root_self_test_stderr "$root_stderr"
emit_stream exact_context_self_test_stdout "$context_stdout"
emit_stream exact_context_self_test_stderr "$context_stderr"

failed_assertion_count=0
first_failure=none
run_assertion() {
    local action20d_retry2_a_run_label=$1

    shift
    if ! record_assertion "$action20d_retry2_a_run_label" "$@"; then
        failed_assertion_count=$((failed_assertion_count + 1))
        if [[ "$first_failure" = none ]]; then
            first_failure=$action20d_retry2_a_run_label
        fi
    fi
}

run_assertion identity_root test "$(id -u)" -eq 0
run_assertion working_directory_root test "$(pwd -P)" = /
run_assertion hostname_node_a test "$(hostname -s)" = j1-svpihole0
run_assertion architecture_arm64 test "$(dpkg --print-architecture)" = arm64
run_assertion health_regular test -f "$health_helper"
run_assertion health_not_symlink test ! -L "$health_helper"
run_assertion health_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$health_helper" 2>/dev/null || true)" = root:root:755
run_assertion health_hash_exact test \
    "$(file_hash "$health_helper" 2>/dev/null || true)" = "$expected_health_sha256"
run_assertion health_syntax /bin/bash -n "$health_helper"
run_assertion health_root_self_test_status_zero test "$root_self_test_status" -eq 0
run_assertion health_root_self_test_stdout_exact grep -Fxq \
    'caddy_ha_health_instrumentation_self_test_complete=true' "$root_stdout"
run_assertion health_root_self_test_stderr_empty test ! -s "$root_stderr"
run_assertion keepalived_script_uid_exact test "$script_uid" = 993
run_assertion caddy_tls_gid_exact test "$tls_gid" = 991
run_assertion keepalived_script_caddy_tls_member /bin/bash -c \
    'id -nG keepalived_script | tr " " "\n" | grep -Fxq caddy-tls'
run_assertion exact_context_readable setpriv --reuid "$script_uid" \
    --regid "$tls_gid" --clear-groups -- test -r "$health_helper"
run_assertion exact_context_executable setpriv --reuid "$script_uid" \
    --regid "$tls_gid" --clear-groups -- test -x "$health_helper"
run_assertion exact_context_self_test_status_zero test "$context_self_test_status" -eq 0
run_assertion exact_context_self_test_stdout_exact grep -Fxq \
    'caddy_ha_health_instrumentation_self_test_complete=true' "$context_stdout"
run_assertion exact_context_self_test_stderr_empty test ! -s "$context_stderr"
validate_health_contract
run_assertion backup_count_exact test \
    "$(find "$backup_root" -mindepth 1 -maxdepth 1 -type d \
        -name 'action20d-retry10-d-retry2-node-a-health-instrumentation.*' \
        -printf . 2>/dev/null | wc -c)" -eq 1
run_assertion backup_path_regular test -d "$expected_backup_path"
run_assertion backup_path_not_symlink test ! -L "$expected_backup_path"
run_assertion backup_path_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$expected_backup_path" 2>/dev/null || true)" = root:root:700
run_assertion backup_helper_regular test -f "$expected_backup_path/check-caddy.sh"
run_assertion backup_helper_not_symlink test ! -L "$expected_backup_path/check-caddy.sh"
run_assertion backup_helper_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$expected_backup_path/check-caddy.sh" 2>/dev/null || true)" = root:root:600
run_assertion backup_helper_hash_exact test \
    "$(file_hash "$expected_backup_path/check-caddy.sh" 2>/dev/null || true)" = \
    "$expected_old_health_sha256"
run_assertion backup_manifest_regular test -f "$expected_backup_path/manifest"
run_assertion backup_manifest_not_symlink test ! -L "$expected_backup_path/manifest"
run_assertion backup_manifest_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$expected_backup_path/manifest" 2>/dev/null || true)" = root:root:600
run_assertion backup_manifest_line_count_exact test \
    "$(wc -l <"$expected_backup_path/manifest" 2>/dev/null || true)" -eq 4
run_assertion backup_manifest_action_exact grep -Fxq \
    'action=20d-retry10-d' "$expected_backup_path/manifest"
run_assertion backup_manifest_node_exact grep -Fxq \
    'node=node-a' "$expected_backup_path/manifest"
run_assertion backup_manifest_old_hash_exact grep -Fxq \
    "old_health_sha256=$expected_old_health_sha256" "$expected_backup_path/manifest"
run_assertion backup_manifest_candidate_hash_exact grep -Fxq \
    "candidate_sha256=$expected_health_sha256" "$expected_backup_path/manifest"
run_assertion payload_stage_residue_absent test \
    "$(find /run -mindepth 1 -maxdepth 1 \
        -name 'caddy-action20d-retry10-d-retry2-payload.*' -printf . 2>/dev/null | wc -c)" -eq 0
run_assertion candidate_stage_residue_absent test \
    "$(find /run -mindepth 1 -maxdepth 1 \
        -name 'caddy-action20d-retry10-d-retry2-candidate.*' -printf . 2>/dev/null | wc -c)" -eq 0
run_assertion install_stage_residue_absent test \
    "$(find /usr/local/libexec -mindepth 1 -maxdepth 1 \
        -name '.check-caddy.action20d-retry10-d-retry2.*' -printf . 2>/dev/null | wc -c)" -eq 0
run_assertion keepalived_active systemctl is-active --quiet keepalived.service
run_assertion caddy_active systemctl is-active --quiet caddy.service
run_assertion lighttpd_active systemctl is-active --quiet lighttpd.service
run_assertion keepalived_pid_numeric test \
    "$(systemctl show -p MainPID --value keepalived.service)" -gt 0
run_assertion caddy_pid_numeric test \
    "$(systemctl show -p MainPID --value caddy.service)" -gt 0
run_assertion lighttpd_pid_numeric test \
    "$(systemctl show -p MainPID --value lighttpd.service)" -gt 0
run_assertion caddy_ipv4_count_exact test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 1
run_assertion caddy_ipv6_count_exact test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 1
run_assertion dns_ipv4_count_exact test "$(address_count 4 "$dns_ipv4_cidr")" -eq 1
run_assertion dns_ipv6_count_exact test "$(address_count 6 "$dns_ipv6_cidr")" -eq 1
run_assertion vrrp_state_master test \
    "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = MASTER
run_assertion before_snapshot_complete test "$before_snapshot_status" -eq 0

after_snapshot_status=0
after_snapshot=$(snapshot_state) || after_snapshot_status=$?
after_snapshot_sha256=$(printf '%s\n' "$after_snapshot" | sha256sum | awk '{ print $1 }')
readonly after_snapshot_status after_snapshot after_snapshot_sha256
run_assertion after_snapshot_complete test "$after_snapshot_status" -eq 0
run_assertion state_unchanged test "$before_snapshot_sha256" = "$after_snapshot_sha256"

printf '%s_value_expected_assertion_count=%s\n' "$prefix" \
    "$(expected_assertions | wc -l)"
printf '%s_value_health_sha256=%s\n' "$prefix" "$expected_health_sha256"
printf '%s_value_backup_path=%s\n' "$prefix" "$expected_backup_path"
printf '%s_value_before_snapshot_sha256=%s\n' "$prefix" "$before_snapshot_sha256"
printf '%s_value_after_snapshot_sha256=%s\n' "$prefix" "$after_snapshot_sha256"
printf '%s_assertion_count=%s\n' "$prefix" "$(expected_assertions | wc -l)"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_assertion_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_full_health_helper_invoked=false\n' "$prefix"
printf '%s_notification_helper_invoked=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_keepalived_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_network_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_remote_cleanup_complete=true\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

rm -rf -- "$work_root"
trap - EXIT INT TERM
[[ "$failed_assertion_count" -eq 0 ]]
