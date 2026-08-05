#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_a
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly include_record='include /etc/keepalived/conf.d/caddy-ha.conf'
readonly expected_main_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly expected_fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5
readonly caddy_ipv4=10.1.0.56/22
readonly caddy_ipv6=fd36:5aa8:6971:1::56/128
readonly dns_ipv4=10.1.0.55/22
readonly dns_ipv6=fd36:5aa8:6971:1::55/128
readonly maximum_stream_bytes=262144
readonly maximum_stream_lines=2048

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
address_count() {
    local address_family=$1
    local address_cidr=$2

    ip -o "$address_family" address show dev eth0 |
        awk -v address="$address_cidr" '$4 == address { count++ } END { print count + 0 }'
}
expected_assertions() {
    printf '%s\n' \
        identity_root working_directory_root hostname_node_a architecture_arm64 \
        main_regular main_not_symlink main_metadata_exact main_hash_exact \
        main_include_absent fragment_regular fragment_not_symlink \
        fragment_metadata_exact fragment_hash_exact action20d_backup_absent \
        action20d_run_residue_absent action20d_tmp_residue_absent \
        keepalived_active caddy_active lighttpd_active \
        keepalived_main_pid_numeric keepalived_restart_count_numeric \
        keepalived_execstart_observed keepalived_executable_regular \
        keepalived_executable_not_symlink keepalived_executable_owner_root \
        keepalived_process_executable_exact keepalived_process_args_observed \
        keepalived_process_args_main_config pid_files_inventory_bounded \
        pid_files_coherent keepalived_version_status_zero \
        keepalived_version_output_safe keepalived_help_status_zero \
        keepalived_help_output_safe help_config_test_supported \
        help_dont_fork_supported candidate_validation_not_invoked \
        action19_parser_context_observed action19_parser_sanitizes_health \
        action19_parser_sanitizes_notify journal_status_zero \
        journal_output_safe caddy_ipv4_absent caddy_ipv6_absent \
        dns_ipv4_present dns_ipv6_present before_state_status_zero \
        before_state_stderr_empty after_state_status_zero \
        after_state_stderr_empty state_unchanged
}
record_command() {
    local assertion_label=$1

    shift
    if "$@"; then
        printf '%s_assertion_%s=true\n' "$prefix" "$assertion_label"
        return 0
    fi
    printf '%s_assertion_%s=false\n' "$prefix" "$assertion_label"
    return 1
}
safe_stream() {
    local inspected_path=$1

    [[ "$(wc -c <"$inspected_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$inspected_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$inspected_path"
}
emit_capture() {
    local capture_label=$1
    local capture_path=$2

    printf '%s_capture_%s_bytes=%s\n' "$prefix" "$capture_label" "$(wc -c <"$capture_path")"
    printf '%s_capture_%s_lines=%s\n' "$prefix" "$capture_label" "$(line_count "$capture_path")"
    printf '%s_capture_%s_sha256=%s\n' "$prefix" "$capture_label" "$(file_hash "$capture_path")"
    if safe_stream "$capture_path"; then
        printf '%s_capture_%s_classification=bounded_safe\n' "$prefix" "$capture_label"
        if [[ -s "$capture_path" ]]; then
            printf '%s_capture_%s_begin\n' "$prefix" "$capture_label"
            sed "s/^/${prefix}_capture_${capture_label}_content=/" "$capture_path"
            printf '%s_capture_%s_end\n' "$prefix" "$capture_label"
        else
            printf '%s_capture_%s_content_secured=empty\n' "$prefix" "$capture_label"
        fi
        return 0
    fi
    printf '%s_capture_%s_classification=unsafe\n' "$prefix" "$capture_label"
    return 1
}
snapshot_state() {
    local snapshot_keepalived_pid

    snapshot_keepalived_pid=$(systemctl show keepalived.service --property MainPID --value)
    printf 'main_sha256=%s\n' "$(file_hash "$main_configuration")"
    printf 'main_include_count=%s\n' "$(grep -Fxc "$include_record" "$main_configuration" || true)"
    printf 'fragment_sha256=%s\n' "$(file_hash "$fragment")"
    printf 'keepalived_active=%s\n' "$(systemctl is-active keepalived.service)"
    printf 'keepalived_main_pid=%s\n' "$snapshot_keepalived_pid"
    printf 'keepalived_restarts=%s\n' "$(systemctl show keepalived.service --property NRestarts --value)"
    printf 'caddy_active=%s\n' "$(systemctl is-active caddy.service)"
    printf 'lighttpd_active=%s\n' "$(systemctl is-active lighttpd.service)"
    printf 'caddy_ipv4_count=%s\n' "$(address_count -4 "$caddy_ipv4")"
    printf 'caddy_ipv6_count=%s\n' "$(address_count -6 "$caddy_ipv6")"
    printf 'dns_ipv4_count=%s\n' "$(address_count -4 "$dns_ipv4")"
    printf 'dns_ipv6_count=%s\n' "$(address_count -6 "$dns_ipv6")"
    printf 'action20d_backup_count=%s\n' "$(find /var/backups/caddy-ha -mindepth 1 -maxdepth 1 -type d -name 'action20d-node-a-caddy-vrrp.*' -printf . 2>/dev/null | wc -c)"
    printf 'action20d_run_count=%s\n' "$(find /run -mindepth 1 -maxdepth 1 -name 'caddy-action20d-node.*' -printf . 2>/dev/null | wc -c)"
    printf 'action20d_tmp_count=%s\n' "$(find /tmp -mindepth 1 -maxdepth 1 -name 'caddy-action20d-*' -printf . 2>/dev/null | wc -c)"
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]]
        expected_assertions
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        self_root=$(mktemp -d /tmp/caddy-action20d-a-self.XXXXXX)
        trap 'rm -rf -- "$self_root"' EXIT
        expected_assertions >"$self_root/labels"
        [[ -s "$self_root/labels" ]]
        [[ "$(wc -l <"$self_root/labels")" -eq "$(LC_ALL=C sort -u "$self_root/labels" | wc -l)" ]]
        ! grep -Ev '^[a-z0-9_]+$' "$self_root/labels" | grep -q .
        printf '%s_inspector_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] ;;
    *)
        printf 'Usage: %s [--self-test|--expected-assertions]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

work_directory=$(mktemp -d /tmp/caddy-action20d-a-inspector.XXXXXX)
readonly work_directory
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT
readonly before_stdout=$work_directory/before.stdout
readonly before_stderr=$work_directory/before.stderr
readonly after_stdout=$work_directory/after.stdout
readonly after_stderr=$work_directory/after.stderr
readonly version_stdout=$work_directory/version.stdout
readonly version_stderr=$work_directory/version.stderr
readonly help_stdout=$work_directory/help.stdout
readonly help_stderr=$work_directory/help.stderr
readonly journal_stdout=$work_directory/journal.stdout
readonly journal_stderr=$work_directory/journal.stderr
touch "$before_stdout" "$before_stderr" "$after_stdout" "$after_stderr" \
    "$version_stdout" "$version_stderr" "$help_stdout" "$help_stderr" \
    "$journal_stdout" "$journal_stderr"
chmod 0600 "$work_directory"/*

before_status=0
snapshot_state >"$before_stdout" 2>"$before_stderr" || before_status=$?
readonly before_status
failed_count=0
first_failure=none
run_assertion() {
    local assertion_label=$1

    shift
    if ! record_command "$assertion_label" "$@"; then
        failed_count=$((failed_count + 1))
        if [[ "$first_failure" == none ]]; then first_failure=$assertion_label; fi
    fi
}

run_assertion identity_root test "$(id -u)" -eq 0
run_assertion working_directory_root test "$(pwd -P)" = /
run_assertion hostname_node_a test "$(hostname -s)" = j1-svpihole0
run_assertion architecture_arm64 test "$(dpkg --print-architecture)" = arm64
run_assertion main_regular test -f "$main_configuration"
run_assertion main_not_symlink test ! -L "$main_configuration"
run_assertion main_metadata_exact test "$(stat -c '%U:%G:%a' "$main_configuration")" = root:root:644
run_assertion main_hash_exact test "$(file_hash "$main_configuration")" = "$expected_main_sha256"
run_assertion main_include_absent test "$(grep -Fxc "$include_record" "$main_configuration" || true)" -eq 0
run_assertion fragment_regular test -f "$fragment"
run_assertion fragment_not_symlink test ! -L "$fragment"
run_assertion fragment_metadata_exact test "$(stat -c '%U:%G:%a' "$fragment")" = root:root:644
run_assertion fragment_hash_exact test "$(file_hash "$fragment")" = "$expected_fragment_sha256"
run_assertion action20d_backup_absent test "$(find /var/backups/caddy-ha -mindepth 1 -maxdepth 1 -type d -name 'action20d-node-a-caddy-vrrp.*' -printf . 2>/dev/null | wc -c)" -eq 0
run_assertion action20d_run_residue_absent test "$(find /run -mindepth 1 -maxdepth 1 -name 'caddy-action20d-node.*' -printf . 2>/dev/null | wc -c)" -eq 0
run_assertion action20d_tmp_residue_absent test "$(find /tmp -mindepth 1 -maxdepth 1 -name 'caddy-action20d-*' ! -path "$work_directory" -printf . 2>/dev/null | wc -c)" -eq 0
run_assertion keepalived_active test "$(systemctl is-active keepalived.service)" = active
run_assertion caddy_active test "$(systemctl is-active caddy.service)" = active
run_assertion lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
keepalived_pid=$(systemctl show keepalived.service --property MainPID --value)
readonly keepalived_pid
keepalived_restarts=$(systemctl show keepalived.service --property NRestarts --value)
readonly keepalived_restarts
keepalived_execstart=$(systemctl show keepalived.service --property ExecStart --value)
readonly keepalived_execstart
keepalived_executable=$(readlink -f /usr/sbin/keepalived)
readonly keepalived_executable
process_executable=$(readlink -f "/proc/$keepalived_pid/exe")
readonly process_executable
process_args=$(tr '\0' ' ' <"/proc/$keepalived_pid/cmdline")
readonly process_args
# The child Bash expands its positional parameter.
# shellcheck disable=SC2016
run_assertion keepalived_main_pid_numeric bash -c '[[ "$1" =~ ^[1-9][0-9]*$ ]]' _ "$keepalived_pid"
# shellcheck disable=SC2016
run_assertion keepalived_restart_count_numeric bash -c '[[ "$1" =~ ^[0-9]+$ ]]' _ "$keepalived_restarts"
run_assertion keepalived_execstart_observed test -n "$keepalived_execstart"
run_assertion keepalived_executable_regular test -f "$keepalived_executable"
run_assertion keepalived_executable_not_symlink test ! -L "$keepalived_executable"
run_assertion keepalived_executable_owner_root test "$(stat -c '%U:%G' "$keepalived_executable")" = root:root
run_assertion keepalived_process_executable_exact test "$process_executable" = "$keepalived_executable"
run_assertion keepalived_process_args_observed test -n "$process_args"
# shellcheck disable=SC2016
run_assertion keepalived_process_args_main_config bash -c '[[ "$1" == *"/etc/keepalived/keepalived.conf"* || "$1" != *" -f "* ]]' _ "$process_args"
pid_inventory=$(find /run -maxdepth 1 -type f -name 'keepalived*.pid' -printf '%f\n' 2>/dev/null | LC_ALL=C sort)
readonly pid_inventory
run_assertion pid_files_inventory_bounded test "$(printf '%s\n' "$pid_inventory" | sed '/^$/d' | wc -l)" -le 8
pid_files_coherent=true
while IFS= read -r pid_file_name; do
    [[ -z "$pid_file_name" ]] && continue
    [[ "$(cat "/run/$pid_file_name")" =~ ^[0-9]+$ ]] || pid_files_coherent=false
done <<<"$pid_inventory"
readonly pid_files_coherent
run_assertion pid_files_coherent test "$pid_files_coherent" = true

version_status=0
keepalived --version >"$version_stdout" 2>"$version_stderr" || version_status=$?
readonly version_status
help_status=0
keepalived --help >"$help_stdout" 2>"$help_stderr" || help_status=$?
readonly help_status
cat "$version_stdout" "$version_stderr" >"$work_directory/version.combined"
cat "$help_stdout" "$help_stderr" >"$work_directory/help.combined"
run_assertion keepalived_version_status_zero test "$version_status" -eq 0
run_assertion keepalived_version_output_safe safe_stream "$work_directory/version.combined"
run_assertion keepalived_help_status_zero test "$help_status" -eq 0
run_assertion keepalived_help_output_safe safe_stream "$work_directory/help.combined"
run_assertion help_config_test_supported grep -Fq -- '--config-test' "$work_directory/help.combined"
run_assertion help_dont_fork_supported grep -Fq -- '--dont-fork' "$work_directory/help.combined"
run_assertion candidate_validation_not_invoked test ! -e "$work_directory/keepalived.log"

readonly action19_sanitized_fragment=$work_directory/action19-sanitized-fragment.conf
action19_sanitize_status=0
sed -e '/^[[:space:]]*notify "/d' \
    -e 's/user keepalived_script/user root/' \
    -e 's#script "/usr/local/libexec/check-caddy.sh"#script "/bin/true"#' \
    "$fragment" >"$action19_sanitized_fragment" || action19_sanitize_status=$?
readonly action19_sanitize_status
run_assertion action19_parser_context_observed test "$action19_sanitize_status" -eq 0
run_assertion action19_parser_sanitizes_health grep -Fq 'script "/bin/true"' "$action19_sanitized_fragment"
run_assertion action19_parser_sanitizes_notify test "$(grep -Fc 'notify "' "$action19_sanitized_fragment" || true)" -eq 0
journal_status=0
journalctl -u keepalived.service --since '2026-08-04 22:00:00' \
    --until '2026-08-04 22:15:00' --no-pager --output short-iso \
    >"$journal_stdout" 2>"$journal_stderr" || journal_status=$?
readonly journal_status
cat "$journal_stdout" "$journal_stderr" >"$work_directory/journal.combined"
run_assertion journal_status_zero test "$journal_status" -eq 0
run_assertion journal_output_safe safe_stream "$work_directory/journal.combined"
run_assertion caddy_ipv4_absent test "$(address_count -4 "$caddy_ipv4")" -eq 0
run_assertion caddy_ipv6_absent test "$(address_count -6 "$caddy_ipv6")" -eq 0
run_assertion dns_ipv4_present test "$(address_count -4 "$dns_ipv4")" -eq 1
run_assertion dns_ipv6_present test "$(address_count -6 "$dns_ipv6")" -eq 1
run_assertion before_state_status_zero test "$before_status" -eq 0
run_assertion before_state_stderr_empty test ! -s "$before_stderr"

after_status=0
snapshot_state >"$after_stdout" 2>"$after_stderr" || after_status=$?
readonly after_status
run_assertion after_state_status_zero test "$after_status" -eq 0
run_assertion after_state_stderr_empty test ! -s "$after_stderr"
run_assertion state_unchanged cmp -s "$before_stdout" "$after_stdout"

emit_capture version "$work_directory/version.combined" || true
emit_capture help "$work_directory/help.combined" || true
emit_capture journal "$work_directory/journal.combined" || true
printf '%s_value_keepalived_main_pid=%s\n' "$prefix" "$keepalived_pid"
printf '%s_value_keepalived_restarts=%s\n' "$prefix" "$keepalived_restarts"
printf '%s_value_keepalived_execstart=%q\n' "$prefix" "$keepalived_execstart"
printf '%s_value_keepalived_process_args=%q\n' "$prefix" "$process_args"
printf '%s_value_pid_files=%q\n' "$prefix" "${pid_inventory:-none}"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$(file_hash "$before_stdout")"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$(file_hash "$after_stdout")"
printf '%s_assertion_count=%s\n' "$prefix" "$(expected_assertions | wc -l)"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_candidate_validation_invoked=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_keepalived_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

[[ "$failed_count" -eq 0 ]]
