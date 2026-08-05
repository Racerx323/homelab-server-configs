#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_b
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly include_record='include /etc/keepalived/conf.d/caddy-ha.conf'
readonly expected_main_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly expected_fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5
readonly caddy_ipv4=10.1.0.56/22
readonly caddy_ipv6=fd36:5aa8:6971:1::56/128
readonly dns_ipv4=10.1.0.55/22
readonly dns_ipv6=fd36:5aa8:6971:1::55/128
readonly maximum_stream_bytes=524288
readonly maximum_stream_lines=4096
readonly probe_timeout_seconds=15
readonly probe_kill_after_seconds=2

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
        action20d_residue_absent keepalived_active caddy_active \
        lighttpd_active caddy_ipv4_absent caddy_ipv6_absent \
        dns_ipv4_present dns_ipv6_present timeout_available \
        candidate_regular candidate_not_symlink candidate_metadata_exact \
        candidate_include_once candidate_main_prefix_exact \
        exact_probe_status_numeric exact_probe_classification_known \
        exact_probe_duration_bounded exact_probe_stdout_safe \
        exact_probe_stderr_safe exact_probe_log_safe exact_probe_trace_safe \
        exact_probe_process_reaped minimal_probe_status_numeric \
        minimal_probe_classification_known minimal_probe_duration_bounded \
        minimal_probe_stdout_safe minimal_probe_stderr_safe \
        minimal_probe_log_safe minimal_probe_trace_safe \
        minimal_probe_process_reaped keepalived_active_post \
        keepalived_pid_unchanged keepalived_restarts_unchanged \
        main_hash_unchanged main_include_still_absent fragment_hash_unchanged \
        caddy_ipv4_still_absent caddy_ipv6_still_absent \
        dns_ipv4_still_present dns_ipv6_still_present before_state_status_zero \
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
    printf '%s_capture_%s_classification=unsafe_retained\n' "$prefix" "$capture_label"
    return 1
}
snapshot_state() {
    printf 'main_sha256=%s\n' "$(file_hash "$main_configuration")"
    printf 'main_include_count=%s\n' "$(grep -Fxc "$include_record" "$main_configuration" || true)"
    printf 'fragment_sha256=%s\n' "$(file_hash "$fragment")"
    printf 'keepalived_active=%s\n' "$(systemctl is-active keepalived.service)"
    printf 'keepalived_main_pid=%s\n' "$(systemctl show keepalived.service --property MainPID --value)"
    printf 'keepalived_restarts=%s\n' "$(systemctl show keepalived.service --property NRestarts --value)"
    printf 'caddy_active=%s\n' "$(systemctl is-active caddy.service)"
    printf 'lighttpd_active=%s\n' "$(systemctl is-active lighttpd.service)"
    printf 'caddy_ipv4_count=%s\n' "$(address_count -4 "$caddy_ipv4")"
    printf 'caddy_ipv6_count=%s\n' "$(address_count -6 "$caddy_ipv6")"
    printf 'dns_ipv4_count=%s\n' "$(address_count -4 "$dns_ipv4")"
    printf 'dns_ipv6_count=%s\n' "$(address_count -6 "$dns_ipv6")"
    printf 'action20d_backup_count=%s\n' "$(find /var/backups/caddy-ha -mindepth 1 -maxdepth 1 -type d -name 'action20d-node-a-caddy-vrrp.*' -printf . 2>/dev/null | wc -c)"
}
classify_probe_status() {
    local observed_status=$1

    case "$observed_status" in
        0) printf 'config_valid\n' ;;
        124) printf 'timeout_term\n' ;;
        137) printf 'timeout_kill\n' ;;
        143) printf 'terminated_sigterm\n' ;;
        *)
            if [[ "$observed_status" =~ ^[0-9]+$ ]] &&
                [[ "$observed_status" -ge 1 && "$observed_status" -le 127 ]]; then
                printf 'config_error_or_command_failure\n'
            elif [[ "$observed_status" =~ ^[0-9]+$ ]] &&
                [[ "$observed_status" -ge 128 && "$observed_status" -le 255 ]]; then
                printf 'terminated_other_signal_or_wrapper\n'
            else
                printf 'unexpected_status\n'
            fi
            ;;
    esac
}
run_probe() {
    local probe_label=$1
    local probe_mode=$2
    local probe_root=$3
    local candidate_path=$4
    local probe_pid
    local probe_status=0
    local probe_iteration=0
    local probe_started_ns
    local probe_finished_ns
    local probe_duration_ms
    local probe_classification
    local -a probe_command

    probe_command=(timeout --foreground --signal=TERM
        --kill-after="${probe_kill_after_seconds}s" "${probe_timeout_seconds}s"
        keepalived)
    if [[ "$probe_mode" = exact ]]; then
        probe_command+=(--dont-fork)
    fi
    probe_command+=("--config-test=$probe_root/$probe_label.log" -f "$candidate_path")
    : >"$probe_root/$probe_label.stdout"
    : >"$probe_root/$probe_label.stderr"
    : >"$probe_root/$probe_label.trace"
    : >"$probe_root/$probe_label.log"
    chmod 0600 "$probe_root/$probe_label.stdout" \
        "$probe_root/$probe_label.stderr" "$probe_root/$probe_label.trace" \
        "$probe_root/$probe_label.log"
    probe_started_ns=$(date +%s%N)
    "${probe_command[@]}" >"$probe_root/$probe_label.stdout" \
        2>"$probe_root/$probe_label.stderr" &
    probe_pid=$!
    printf '%s\n' "$probe_pid" >"$probe_root/$probe_label.pid"
    chmod 0600 "$probe_root/$probe_label.pid"
    while kill -0 "$probe_pid" 2>/dev/null && [[ "$probe_iteration" -lt 40 ]]; do
        probe_iteration=$((probe_iteration + 1))
        printf 'iteration=%s elapsed_half_seconds=%s\n' \
            "$probe_iteration" "$probe_iteration" >>"$probe_root/$probe_label.trace"
        ps -o pid=,ppid=,stat=,wchan=,comm=,args= -p "$probe_pid" \
            --ppid "$probe_pid" >>"$probe_root/$probe_label.trace" 2>/dev/null || true
        sleep 0.5
    done
    wait "$probe_pid" || probe_status=$?
    probe_finished_ns=$(date +%s%N)
    probe_duration_ms=$(((probe_finished_ns - probe_started_ns) / 1000000))
    probe_classification=$(classify_probe_status "$probe_status")
    printf '%s\n' "$probe_status" >"$probe_root/$probe_label.status"
    printf '%s\n' "$probe_classification" >"$probe_root/$probe_label.classification"
    printf '%s\n' "$probe_duration_ms" >"$probe_root/$probe_label.duration_ms"
    chmod 0600 "$probe_root/$probe_label.status" \
        "$probe_root/$probe_label.classification" \
        "$probe_root/$probe_label.duration_ms"
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]]
        expected_assertions
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        self_root=$(mktemp -d /tmp/caddy-action20d-b-self.XXXXXX)
        trap 'rm -rf -- "$self_root"' EXIT
        expected_assertions >"$self_root/labels"
        [[ -s "$self_root/labels" ]]
        [[ "$(wc -l <"$self_root/labels")" -eq "$(LC_ALL=C sort -u "$self_root/labels" | wc -l)" ]]
        ! grep -Ev '^[a-z0-9_]+$' "$self_root/labels" | grep -q .
        [[ "$(classify_probe_status 0)" = config_valid ]]
        [[ "$(classify_probe_status 124)" = timeout_term ]]
        [[ "$(classify_probe_status 143)" = terminated_sigterm ]]
        [[ "$(classify_probe_status 130)" = terminated_other_signal_or_wrapper ]]
        [[ "$(classify_probe_status 255)" = terminated_other_signal_or_wrapper ]]
        [[ "$(classify_probe_status invalid)" = unexpected_status ]]
        printf '%s_inspector_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] ;;
    *)
        printf 'Usage: %s [--self-test|--expected-assertions]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

work_directory=$(mktemp -d /run/caddy-action20d-b.XXXXXX)
readonly work_directory
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT
readonly before_stdout=$work_directory/before.stdout
readonly before_stderr=$work_directory/before.stderr
readonly after_stdout=$work_directory/after.stdout
readonly after_stderr=$work_directory/after.stderr
readonly candidate_configuration=$work_directory/keepalived.conf.candidate
touch "$before_stdout" "$before_stderr" "$after_stdout" "$after_stderr"
chmod 0600 "$before_stdout" "$before_stderr" "$after_stdout" "$after_stderr"

before_status=0
snapshot_state >"$before_stdout" 2>"$before_stderr" || before_status=$?
readonly before_status
before_pid=$(systemctl show keepalived.service --property MainPID --value)
readonly before_pid
before_restarts=$(systemctl show keepalived.service --property NRestarts --value)
readonly before_restarts
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
run_assertion action20d_residue_absent test "$(find /run -mindepth 1 -maxdepth 1 -name 'caddy-action20d-*' ! -path "$work_directory" -printf . 2>/dev/null | wc -c)" -eq 0
run_assertion keepalived_active test "$(systemctl is-active keepalived.service)" = active
run_assertion caddy_active test "$(systemctl is-active caddy.service)" = active
run_assertion lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
run_assertion caddy_ipv4_absent test "$(address_count -4 "$caddy_ipv4")" -eq 0
run_assertion caddy_ipv6_absent test "$(address_count -6 "$caddy_ipv6")" -eq 0
run_assertion dns_ipv4_present test "$(address_count -4 "$dns_ipv4")" -eq 1
run_assertion dns_ipv6_present test "$(address_count -6 "$dns_ipv6")" -eq 1
run_assertion timeout_available test -x /usr/bin/timeout

cp --preserve=mode,ownership,timestamps "$main_configuration" "$candidate_configuration"
printf '\n%s\n' "$include_record" >>"$candidate_configuration"
chmod 0600 "$candidate_configuration"
run_assertion candidate_regular test -f "$candidate_configuration"
run_assertion candidate_not_symlink test ! -L "$candidate_configuration"
run_assertion candidate_metadata_exact test "$(stat -c '%U:%G:%a' "$candidate_configuration")" = root:root:600
run_assertion candidate_include_once test "$(grep -Fxc "$include_record" "$candidate_configuration")" -eq 1
# The child Bash expands its positional parameters.
# shellcheck disable=SC2016
run_assertion candidate_main_prefix_exact bash -c \
    'head -c "$(stat -c %s "$1")" "$2" | cmp -s "$1" -' _ \
    "$main_configuration" "$candidate_configuration"

run_probe exact exact "$work_directory" "$candidate_configuration"
run_probe minimal minimal "$work_directory" "$candidate_configuration"
exact_status=$(<"$work_directory/exact.status")
readonly exact_status
exact_classification=$(<"$work_directory/exact.classification")
readonly exact_classification
exact_duration_ms=$(<"$work_directory/exact.duration_ms")
readonly exact_duration_ms
exact_pid=$(<"$work_directory/exact.pid")
readonly exact_pid
minimal_status=$(<"$work_directory/minimal.status")
readonly minimal_status
minimal_classification=$(<"$work_directory/minimal.classification")
readonly minimal_classification
minimal_duration_ms=$(<"$work_directory/minimal.duration_ms")
readonly minimal_duration_ms
minimal_pid=$(<"$work_directory/minimal.pid")
readonly minimal_pid

# shellcheck disable=SC2016
run_assertion exact_probe_status_numeric bash -c '[[ "$1" =~ ^[0-9]+$ ]]' _ "$exact_status"
run_assertion exact_probe_classification_known test "$exact_classification" != unexpected_status
run_assertion exact_probe_duration_bounded test "$exact_duration_ms" -le 20000
run_assertion exact_probe_stdout_safe safe_stream "$work_directory/exact.stdout"
run_assertion exact_probe_stderr_safe safe_stream "$work_directory/exact.stderr"
run_assertion exact_probe_log_safe safe_stream "$work_directory/exact.log"
run_assertion exact_probe_trace_safe safe_stream "$work_directory/exact.trace"
run_assertion exact_probe_process_reaped test ! -e "/proc/$exact_pid"
# shellcheck disable=SC2016
run_assertion minimal_probe_status_numeric bash -c '[[ "$1" =~ ^[0-9]+$ ]]' _ "$minimal_status"
run_assertion minimal_probe_classification_known test "$minimal_classification" != unexpected_status
run_assertion minimal_probe_duration_bounded test "$minimal_duration_ms" -le 20000
run_assertion minimal_probe_stdout_safe safe_stream "$work_directory/minimal.stdout"
run_assertion minimal_probe_stderr_safe safe_stream "$work_directory/minimal.stderr"
run_assertion minimal_probe_log_safe safe_stream "$work_directory/minimal.log"
run_assertion minimal_probe_trace_safe safe_stream "$work_directory/minimal.trace"
run_assertion minimal_probe_process_reaped test ! -e "/proc/$minimal_pid"
run_assertion keepalived_active_post test "$(systemctl is-active keepalived.service)" = active
run_assertion keepalived_pid_unchanged test "$(systemctl show keepalived.service --property MainPID --value)" = "$before_pid"
run_assertion keepalived_restarts_unchanged test "$(systemctl show keepalived.service --property NRestarts --value)" = "$before_restarts"
run_assertion main_hash_unchanged test "$(file_hash "$main_configuration")" = "$expected_main_sha256"
run_assertion main_include_still_absent test "$(grep -Fxc "$include_record" "$main_configuration" || true)" -eq 0
run_assertion fragment_hash_unchanged test "$(file_hash "$fragment")" = "$expected_fragment_sha256"
run_assertion caddy_ipv4_still_absent test "$(address_count -4 "$caddy_ipv4")" -eq 0
run_assertion caddy_ipv6_still_absent test "$(address_count -6 "$caddy_ipv6")" -eq 0
run_assertion dns_ipv4_still_present test "$(address_count -4 "$dns_ipv4")" -eq 1
run_assertion dns_ipv6_still_present test "$(address_count -6 "$dns_ipv6")" -eq 1
run_assertion before_state_status_zero test "$before_status" -eq 0
run_assertion before_state_stderr_empty test ! -s "$before_stderr"
after_status=0
snapshot_state >"$after_stdout" 2>"$after_stderr" || after_status=$?
readonly after_status
run_assertion after_state_status_zero test "$after_status" -eq 0
run_assertion after_state_stderr_empty test ! -s "$after_stderr"
run_assertion state_unchanged cmp -s "$before_stdout" "$after_stdout"

for capture_name in exact.stdout exact.stderr exact.log exact.trace \
    minimal.stdout minimal.stderr minimal.log minimal.trace; do
    emit_capture "${capture_name//./_}" "$work_directory/$capture_name" || true
done
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$(file_hash "$before_stdout")"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$(file_hash "$after_stdout")"
printf '%s_value_candidate_sha256=%s\n' "$prefix" "$(file_hash "$candidate_configuration")"
printf '%s_value_exact_status=%s\n' "$prefix" "$exact_status"
printf '%s_value_exact_classification=%s\n' "$prefix" "$exact_classification"
printf '%s_value_exact_duration_ms=%s\n' "$prefix" "$exact_duration_ms"
printf '%s_value_minimal_status=%s\n' "$prefix" "$minimal_status"
printf '%s_value_minimal_classification=%s\n' "$prefix" "$minimal_classification"
printf '%s_value_minimal_duration_ms=%s\n' "$prefix" "$minimal_duration_ms"
printf '%s_assertion_count=%s\n' "$prefix" "$(expected_assertions | wc -l)"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_candidate_validation_invoked=true\n' "$prefix"
printf '%s_candidate_installed=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_transient_filesystem_activity=true\n' "$prefix"
printf '%s_persistent_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_keepalived_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

[[ "$failed_count" -eq 0 ]]
