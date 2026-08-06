#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry5_a_probe
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly expected_main_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly expected_fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5
readonly expected_candidate_sha256=ea8fc2aaba014fa65296e7a6e15ae1fcb9a108d2487b3f5166a36dd3f30785b7
readonly expected_hostname=j1-svpihole0
readonly include_record='include /etc/keepalived/conf.d/caddy-ha.conf'
readonly caddy_ipv4=10.1.0.56/22
readonly caddy_ipv6=fd36:5aa8:6971:1::56/128
readonly dns_ipv4=10.1.0.55/22
readonly dns_ipv6=fd36:5aa8:6971:1::55/128
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

diagnostic_root=
failure_count=0
first_failure=none

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
address_count() {
    local inspected_family=$1
    local inspected_address=$2

    ip -o "$inspected_family" address show dev eth0 |
        awk -v address="$inspected_address" '$4 == address { count++ } END { print count + 0 }'
}
record_assertion() {
    local assertion_label=$1
    local assertion_status=0

    shift
    "$@" || assertion_status=$?
    if [[ "$assertion_status" -eq 0 ]]; then
        printf '%s_assertion_%s=true\n' "$prefix" "$assertion_label"
        return 0
    fi
    printf '%s_assertion_%s=false\n' "$prefix" "$assertion_label" >&2
    failure_count=$((failure_count + 1))
    if [[ "$first_failure" = none ]]; then
        first_failure=$assertion_label
    fi
    return 1
}
safe_stream() {
    local inspected_stream_path=$1

    [[ "$(wc -c <"$inspected_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$inspected_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$inspected_stream_path"
}
emit_stream() {
    local emitted_stream_label=$1
    local emitted_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$emitted_stream_label" \
        "$(wc -c <"$emitted_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$emitted_stream_label" \
        "$(line_count "$emitted_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$emitted_stream_label" \
        "$(file_hash "$emitted_stream_path")"
    if ! safe_stream "$emitted_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' \
            "$prefix" "$emitted_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$emitted_stream_label"
    if [[ -s "$emitted_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$emitted_stream_label"
        sed "s/^/${prefix}_${emitted_stream_label}_content=/" "$emitted_stream_path"
        printf '%s_%s_end\n' "$prefix" "$emitted_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$emitted_stream_label"
    fi
}
stable_snapshot() {
    local snapshot_output=$1

    {
        sha256sum "$main_configuration" "$fragment"
        grep -Fxc "$include_record" "$main_configuration" || true
        systemctl show keepalived.service \
            -p ActiveState -p SubState -p MainPID -p NRestarts -p CanReload
        systemctl is-active caddy.service lighttpd.service
        printf 'caddy_ipv4=%s\n' "$(address_count -4 "$caddy_ipv4")"
        printf 'caddy_ipv6=%s\n' "$(address_count -6 "$caddy_ipv6")"
        printf 'dns_ipv4=%s\n' "$(address_count -4 "$dns_ipv4")"
        printf 'dns_ipv6=%s\n' "$(address_count -6 "$dns_ipv6")"
        if [[ -r /run/keepalived.pid ]]; then
            printf 'keepalived_pid=%s\n' "$(</run/keepalived.pid)"
        else
            printf 'keepalived_pid=absent\n'
        fi
    } >"$snapshot_output"
}
classify_probe() {
    local classified_status=$1

    case "$classified_status" in
        0) printf 'pidfile_isolation_resolved_sigterm\n' ;;
        124) printf 'pidfile_isolation_timeout_term\n' ;;
        137) printf 'pidfile_isolation_timeout_kill\n' ;;
        143) printf 'pidfile_isolation_did_not_resolve_sigterm\n' ;;
        [1-9] | [1-9][0-9] | 1[01][0-9] | 12[0-7])
            printf 'config_test_error_or_command_failure\n'
            ;;
        *) return 1 ;;
    esac
}
expected_assertions() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact main_regular \
        main_not_symlink main_hash_exact fragment_regular fragment_not_symlink \
        fragment_hash_exact include_absent keepalived_active caddy_active \
        lighttpd_active caddy_ipv4_absent caddy_ipv6_absent dns_ipv4_owned \
        dns_ipv6_owned timeout_available diagnostic_root_metadata \
        help_status_zero help_config_test_option help_parent_pid_option \
        help_vrrp_pid_option help_checkers_pid_option before_snapshot_complete \
        candidate_regular candidate_not_symlink candidate_metadata_exact \
        candidate_hash_exact probe_status_numeric probe_classification_known \
        probe_duration_bounded isolated_parent_pid_absent \
        isolated_vrrp_pid_absent isolated_checkers_pid_absent \
        after_snapshot_complete state_unchanged
}
source_contract() {
    local inspected_source=$1

    # The dollar-prefixed text is literal production source.
    # shellcheck disable=SC2016
    grep -Fq -- '--pid="$diagnostic_root/parent.pid"' "$inspected_source" || return 1
    # The dollar-prefixed text is literal production source.
    # shellcheck disable=SC2016
    grep -Fq -- '--vrrp_pid="$diagnostic_root/vrrp.pid"' "$inspected_source" || return 1
    # The dollar-prefixed text is literal production source.
    # shellcheck disable=SC2016
    grep -Fq -- '--checkers_pid="$diagnostic_root/checkers.pid"' "$inspected_source" || return 1
    grep -Fq 'keepalived --config-test=' "$inspected_source" || return 1
    ! grep -Eq 'systemctl (reload|restart|start|stop)|ip address (add|del)|install .*keepalived\.conf' \
        "$inspected_source" || return 1
    return 0
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]] || exit 64
        expected_assertions
        exit 0
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        source_contract "$0"
        printf '%s_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    node-a) [[ $# -eq 1 ]] || exit 64 ;;
    *)
        printf 'Usage: %s node-a|--expected-assertions|--self-test|--source-test|--contract-test\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

cd /
record_assertion identity_root test "$(id -u)" -eq 0 || exit 1
record_assertion working_directory_root test "$PWD" = / || exit 1
record_assertion hostname_exact test "$(hostname -s)" = "$expected_hostname" || exit 1
record_assertion main_regular test -f "$main_configuration" || exit 1
record_assertion main_not_symlink test ! -L "$main_configuration" || exit 1
record_assertion main_hash_exact test "$(file_hash "$main_configuration")" = \
    "$expected_main_sha256" || exit 1
record_assertion fragment_regular test -f "$fragment" || exit 1
record_assertion fragment_not_symlink test ! -L "$fragment" || exit 1
record_assertion fragment_hash_exact test "$(file_hash "$fragment")" = \
    "$expected_fragment_sha256" || exit 1
record_assertion include_absent test \
    "$(grep -Fxc "$include_record" "$main_configuration" || true)" -eq 0 || exit 1
record_assertion keepalived_active test "$(systemctl is-active keepalived.service)" = active || exit 1
record_assertion caddy_active test "$(systemctl is-active caddy.service)" = active || exit 1
record_assertion lighttpd_active test "$(systemctl is-active lighttpd.service)" = active || exit 1
record_assertion caddy_ipv4_absent test "$(address_count -4 "$caddy_ipv4")" -eq 0 || exit 1
record_assertion caddy_ipv6_absent test "$(address_count -6 "$caddy_ipv6")" -eq 0 || exit 1
record_assertion dns_ipv4_owned test "$(address_count -4 "$dns_ipv4")" -eq 1 || exit 1
record_assertion dns_ipv6_owned test "$(address_count -6 "$dns_ipv6")" -eq 1 || exit 1
record_assertion timeout_available test -x /usr/bin/timeout || exit 1

diagnostic_root=$(mktemp -d /run/caddy-action20d-retry5-a.XXXXXX)
readonly diagnostic_root
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$diagnostic_root"
}
trap cleanup EXIT
record_assertion diagnostic_root_metadata test \
    "$(stat -c '%U:%G:%a' "$diagnostic_root")" = root:root:700 || exit 1

readonly help_stdout=$diagnostic_root/help.stdout
readonly help_stderr=$diagnostic_root/help.stderr
help_status=0
keepalived --help >"$help_stdout" 2>"$help_stderr" || help_status=$?
readonly help_status
emit_stream help_stdout "$help_stdout" || exit 97
emit_stream help_stderr "$help_stderr" || exit 97
record_assertion help_status_zero test "$help_status" -eq 0 || exit 1
record_assertion help_config_test_option grep -Eq -- '(^|[[:space:]])-t,.*--config-test' \
    "$help_stderr" || exit 1
record_assertion help_parent_pid_option grep -Eq -- '(^|[[:space:]])-p,.*--pid' \
    "$help_stderr" || exit 1
record_assertion help_vrrp_pid_option grep -Eq -- '(^|[[:space:]])-r,.*--vrrp[_-]pid' \
    "$help_stderr" || exit 1
record_assertion help_checkers_pid_option grep -Eq -- '(^|[[:space:]])-c,.*--checkers[_-]pid' \
    "$help_stderr" || exit 1

readonly before_snapshot=$diagnostic_root/before.snapshot
readonly after_snapshot=$diagnostic_root/after.snapshot
stable_snapshot "$before_snapshot"
record_assertion before_snapshot_complete test -s "$before_snapshot" || exit 1

readonly candidate=$diagnostic_root/keepalived.sanitized.conf
{
    sed -e '/^[[:space:]]*notify "/d' \
        -e 's#^[[:space:]]*script "[^"]*"#    script "/bin/true"#' \
        "$main_configuration"
    printf '\n'
    sed -e '/^[[:space:]]*notify "/d' \
        -e 's#^[[:space:]]*script "[^"]*"#    script "/bin/true"#' \
        -e 's/^[[:space:]]*user keepalived_script/    user root/' \
        "$fragment"
} >"$candidate"
chmod 0600 "$candidate"
record_assertion candidate_regular test -f "$candidate" || exit 1
record_assertion candidate_not_symlink test ! -L "$candidate" || exit 1
record_assertion candidate_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$candidate")" = root:root:600 || exit 1
record_assertion candidate_hash_exact test "$(file_hash "$candidate")" = \
    "$expected_candidate_sha256" || exit 1

readonly probe_stdout=$diagnostic_root/probe.stdout
readonly probe_stderr=$diagnostic_root/probe.stderr
readonly probe_log=$diagnostic_root/probe.log
probe_status=0
probe_started_ns=$(date +%s%N)
timeout --foreground --signal=TERM --kill-after=2s 15s \
    keepalived --config-test="$probe_log" \
    --pid="$diagnostic_root/parent.pid" \
    --vrrp_pid="$diagnostic_root/vrrp.pid" \
    --checkers_pid="$diagnostic_root/checkers.pid" \
    -f "$candidate" >"$probe_stdout" 2>"$probe_stderr" || probe_status=$?
probe_finished_ns=$(date +%s%N)
readonly probe_status probe_started_ns probe_finished_ns
readonly probe_duration_ms=$(((probe_finished_ns - probe_started_ns) / 1000000))
probe_classification=$(classify_probe "$probe_status") || probe_classification=unknown
readonly probe_classification probe_duration_ms
emit_stream probe_stdout "$probe_stdout" || exit 97
emit_stream probe_stderr "$probe_stderr" || exit 97
emit_stream probe_log "$probe_log" || exit 97
printf '%s_value_probe_status=%s\n' "$prefix" "$probe_status"
printf '%s_value_probe_duration_ms=%s\n' "$prefix" "$probe_duration_ms"
printf '%s_value_probe_classification=%s\n' "$prefix" "$probe_classification"
record_assertion probe_status_numeric test "$probe_status" -ge 0 || exit 1
record_assertion probe_classification_known test "$probe_classification" != unknown || exit 1
record_assertion probe_duration_bounded test "$probe_duration_ms" -le 17000 || exit 1
record_assertion isolated_parent_pid_absent test ! -e "$diagnostic_root/parent.pid" || exit 1
record_assertion isolated_vrrp_pid_absent test ! -e "$diagnostic_root/vrrp.pid" || exit 1
record_assertion isolated_checkers_pid_absent test ! -e "$diagnostic_root/checkers.pid" || exit 1

stable_snapshot "$after_snapshot"
record_assertion after_snapshot_complete test -s "$after_snapshot" || exit 1
record_assertion state_unchanged cmp -s "$before_snapshot" "$after_snapshot" || exit 1
printf '%s_value_before_snapshot_sha256=%s\n' "$prefix" "$(file_hash "$before_snapshot")"
printf '%s_value_after_snapshot_sha256=%s\n' "$prefix" "$(file_hash "$after_snapshot")"
printf '%s_value_assertion_count=%s\n' "$prefix" "$(expected_assertions | wc -l)"
printf '%s_value_failure_count=%s\n' "$prefix" "$failure_count"
printf '%s_value_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_notification_invoked=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_keepalived_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
rm -rf -- "$diagnostic_root"
trap - EXIT
printf '%s_cleanup_complete=true\n' "$prefix"
printf '%s_diagnostic_complete=true\n' "$prefix"
