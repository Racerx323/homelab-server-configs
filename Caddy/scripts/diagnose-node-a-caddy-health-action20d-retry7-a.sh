#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry7_a
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly include_record='include /etc/keepalived/conf.d/caddy-ha.conf'
readonly health_helper=/usr/local/libexec/check-caddy.sh
readonly environment_file=/etc/default/caddy-ha
readonly expected_main_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly expected_fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5
readonly expected_health_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly backup_pattern='action20d-retry-node-a-caddy-vrrp.*'
readonly caddy_ipv4=10.1.0.56/22
readonly caddy_ipv6=fd36:5aa8:6971:1::56/128
readonly dns_ipv4=10.1.0.55/22
readonly dns_ipv6=fd36:5aa8:6971:1::55/128
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=8192

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
file_hash_or_empty() {
    local diagnostic_hash_path=$1

    if [[ -f "$diagnostic_hash_path" ]]; then
        file_hash "$diagnostic_hash_path"
    fi
}
metadata_or_empty() {
    local diagnostic_metadata_format=$1
    local diagnostic_metadata_path=$2

    stat -c "$diagnostic_metadata_format" "$diagnostic_metadata_path" \
        2>/dev/null || true
}
line_count() { awk 'END { print NR }' "$1"; }
address_count() {
    local diagnostic_address_family=$1
    local diagnostic_address_cidr=$2

    ip -o "$diagnostic_address_family" address show dev eth0 |
        awk -v address="$diagnostic_address_cidr" \
            '$4 == address { count++ } END { print count + 0 }'
}
expected_assertions() {
    printf '%s\n' \
        identity_root working_directory_root hostname_node_a architecture_arm64 \
        main_regular main_not_symlink main_metadata_exact main_hash_restored \
        main_include_absent fragment_regular fragment_not_symlink \
        fragment_metadata_exact fragment_hash_exact fragment_health_command_exact \
        fragment_health_user_exact fragment_timeout_exact fragment_rise_exact \
        fragment_fall_exact helper_regular helper_not_symlink \
        helper_metadata_exact helper_hash_exact environment_regular \
        environment_not_symlink keepalived_script_identity_exact \
        keepalived_script_group_exact keepalived_script_caddy_tls_member \
        backup_count_exact backup_path_absolute backup_regular \
        backup_not_symlink backup_metadata_exact backup_file_regular \
        backup_file_not_symlink backup_file_metadata_exact backup_file_hash_exact \
        backup_manifest_regular backup_manifest_not_symlink \
        backup_manifest_metadata_exact backup_manifest_action_exact \
        backup_manifest_node_exact backup_manifest_main_hash_exact \
        keepalived_active caddy_active lighttpd_active \
        keepalived_pid_numeric keepalived_restart_count_numeric \
        caddy_ipv4_absent caddy_ipv6_absent dns_ipv4_present dns_ipv6_present \
        journal_status_zero journal_output_safe journal_reload_observed \
        journal_health_status_one_observed journal_fault_observed \
        journal_dualstack_fault_observed identity_probe_captured \
        full_helper_probe_captured timeout_helper_probe_captured \
        service_probe_captured validate_probe_captured curl_probe_captured \
        full_helper_status_numeric timeout_helper_status_numeric \
        service_status_numeric validate_status_numeric curl_status_numeric \
        full_helper_duration_numeric timeout_helper_duration_numeric \
        service_duration_numeric validate_duration_numeric curl_duration_numeric \
        helper_transient_residue_absent before_state_status_zero \
        before_state_stderr_empty after_state_status_zero \
        after_state_stderr_empty state_unchanged
}
safe_stream() {
    local diagnostic_stream_path=$1

    [[ "$(wc -c <"$diagnostic_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$diagnostic_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$diagnostic_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$diagnostic_stream_path" || return 1
    return 0
}
emit_capture() {
    local diagnostic_capture_label=$1
    local diagnostic_capture_path=$2

    printf '%s_capture_%s_bytes=%s\n' "$prefix" "$diagnostic_capture_label" \
        "$(wc -c <"$diagnostic_capture_path")"
    printf '%s_capture_%s_lines=%s\n' "$prefix" "$diagnostic_capture_label" \
        "$(line_count "$diagnostic_capture_path")"
    printf '%s_capture_%s_sha256=%s\n' "$prefix" "$diagnostic_capture_label" \
        "$(file_hash "$diagnostic_capture_path")"
    if ! safe_stream "$diagnostic_capture_path"; then
        printf '%s_capture_%s_classification=unsafe\n' "$prefix" \
            "$diagnostic_capture_label"
        return 1
    fi
    printf '%s_capture_%s_classification=bounded_safe\n' "$prefix" \
        "$diagnostic_capture_label"
    if [[ -s "$diagnostic_capture_path" ]]; then
        printf '%s_capture_%s_begin\n' "$prefix" "$diagnostic_capture_label"
        sed "s/^/${prefix}_capture_${diagnostic_capture_label}_content=/" \
            "$diagnostic_capture_path"
        printf '%s_capture_%s_end\n' "$prefix" "$diagnostic_capture_label"
    else
        printf '%s_capture_%s_content_secured=empty\n' "$prefix" \
            "$diagnostic_capture_label"
    fi
    return 0
}
record_assertion() {
    local diagnostic_assertion_label=$1

    shift
    if "$@"; then
        printf '%s_assertion_%s=true\n' "$prefix" "$diagnostic_assertion_label"
        return 0
    fi
    printf '%s_assertion_%s=false\n' "$prefix" "$diagnostic_assertion_label"
    return 1
}
snapshot_state() {
    printf 'main_sha256=%s\n' "$(file_hash "$main_configuration")"
    printf 'main_include_count=%s\n' \
        "$(grep -Fxc "$include_record" "$main_configuration" || true)"
    printf 'fragment_sha256=%s\n' "$(file_hash "$fragment")"
    printf 'helper_sha256=%s\n' "$(file_hash "$health_helper")"
    printf 'backup_path=%s\n' "$backup_path"
    printf 'backup_tree_sha256=%s\n' "$backup_tree_sha256"
    printf 'keepalived_active=%s\n' "$(systemctl is-active keepalived.service)"
    printf 'keepalived_pid=%s\n' \
        "$(systemctl show keepalived.service --property MainPID --value)"
    printf 'keepalived_restarts=%s\n' \
        "$(systemctl show keepalived.service --property NRestarts --value)"
    printf 'caddy_active=%s\n' "$(systemctl is-active caddy.service)"
    printf 'lighttpd_active=%s\n' "$(systemctl is-active lighttpd.service)"
    printf 'caddy_ipv4_count=%s\n' "$(address_count -4 "$caddy_ipv4")"
    printf 'caddy_ipv6_count=%s\n' "$(address_count -6 "$caddy_ipv6")"
    printf 'dns_ipv4_count=%s\n' "$(address_count -4 "$dns_ipv4")"
    printf 'dns_ipv6_count=%s\n' "$(address_count -6 "$dns_ipv6")"
}
run_probe() {
    local diagnostic_probe_label=$1
    local diagnostic_probe_started
    local diagnostic_probe_ended
    local diagnostic_probe_status=0

    shift
    diagnostic_probe_started=$(date +%s%3N)
    "$@" >"$work_directory/$diagnostic_probe_label.stdout" \
        2>"$work_directory/$diagnostic_probe_label.stderr" || diagnostic_probe_status=$?
    diagnostic_probe_ended=$(date +%s%3N)
    printf '%s\n' "$diagnostic_probe_status" \
        >"$work_directory/$diagnostic_probe_label.status"
    printf '%s\n' "$((diagnostic_probe_ended - diagnostic_probe_started))" \
        >"$work_directory/$diagnostic_probe_label.duration_ms"
    emit_capture "${diagnostic_probe_label}_stdout" \
        "$work_directory/$diagnostic_probe_label.stdout" || return 1
    emit_capture "${diagnostic_probe_label}_stderr" \
        "$work_directory/$diagnostic_probe_label.stderr" || return 1
    printf '%s_value_%s_status=%s\n' "$prefix" "$diagnostic_probe_label" \
        "$diagnostic_probe_status"
    printf '%s_value_%s_duration_ms=%s\n' "$prefix" "$diagnostic_probe_label" \
        "$((diagnostic_probe_ended - diagnostic_probe_started))"
    return 0
}
# Invoked indirectly through run_probe.
# shellcheck disable=SC2317
probe_validate() {
    local diagnostic_runtime_root=$1

    runuser -u keepalived_script -- env \
        HOME="$diagnostic_runtime_root/home" \
        XDG_CONFIG_HOME="$diagnostic_runtime_root/config" \
        XDG_DATA_HOME="$diagnostic_runtime_root/data" \
        /bin/bash -c \
        'set -a; source /etc/default/caddy-ha; set +a; exec /usr/bin/caddy validate --config /etc/caddy/current/Caddyfile --adapter caddyfile'
}
# Invoked indirectly through run_assertion.
# shellcheck disable=SC2317
is_unsigned_integer() {
    [[ $1 =~ ^[0-9]+$ ]]
}
# Invoked indirectly through run_assertion.
# shellcheck disable=SC2317
is_positive_integer() {
    [[ $1 =~ ^[1-9][0-9]*$ ]]
}
# Invoked indirectly through run_assertion.
# shellcheck disable=SC2317
backup_path_approved() {
    [[ $1 == /var/backups/caddy-ha/action20d-retry-node-a-caddy-vrrp.* ]]
}
classify_observation() {
    local diagnostic_full_status=$1
    local diagnostic_timeout_status=$2
    local diagnostic_service_status=$3
    local diagnostic_validate_status=$4
    local diagnostic_curl_status=$5
    local diagnostic_timeout_duration=$6

    if [[ "$diagnostic_timeout_status" -eq 124 ]] ||
        [[ "$diagnostic_timeout_duration" -ge 4000 ]]; then
        printf 'helper_exceeds_four_second_boundary\n'
    elif [[ "$diagnostic_service_status" -ne 0 ]]; then
        printf 'systemd_activity_check_failed\n'
    elif [[ "$diagnostic_validate_status" -ne 0 ]]; then
        printf 'caddy_validate_failed\n'
    elif [[ "$diagnostic_curl_status" -ne 0 ]]; then
        printf 'localhost_https_check_failed\n'
    elif [[ "$diagnostic_full_status" -ne 0 || "$diagnostic_timeout_status" -ne 0 ]]; then
        printf 'combined_helper_failed_with_isolated_stages_passing\n'
    else
        printf 'runtime_failure_not_reproduced_post_rollback\n'
    fi
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]] || exit 64
        expected_assertions
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test_root=$(mktemp -d /tmp/caddy-action20d-retry7-a-self.XXXXXX)
        trap 'rm -rf -- "$self_test_root"' EXIT
        expected_assertions >"$self_test_root/labels"
        [[ "$(wc -l <"$self_test_root/labels")" -gt 0 ]]
        [[ "$(wc -l <"$self_test_root/labels")" -eq "$(LC_ALL=C sort -u "$self_test_root/labels" | wc -l)" ]]
        ! grep -Ev '^[a-z0-9_]+$' "$self_test_root/labels" | grep -q .
        printf '%s_diagnostic_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--expected-assertions|--self-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

work_directory=$(mktemp -d /tmp/caddy-action20d-retry7-a-diagnostic.XXXXXX)
readonly work_directory
# shellcheck disable=SC2317
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT INT TERM
chmod 0700 "$work_directory"

backup_inventory=$(find /var/backups/caddy-ha -mindepth 1 -maxdepth 1 \
    -type d -name "$backup_pattern" -print 2>/dev/null | LC_ALL=C sort)
readonly backup_inventory
backup_path=$(printf '%s\n' "$backup_inventory" | sed '/^$/d' | head -n 1)
readonly backup_path
if [[ -d "$backup_path" ]]; then
    backup_tree_sha256=$(find "$backup_path" -mindepth 1 -maxdepth 1 -type f \
        -printf '%f\0' 2>/dev/null | LC_ALL=C sort -z |
        while IFS= read -r -d '' backup_file_name; do
            printf '%s %s\n' "$backup_file_name" \
                "$(file_hash "$backup_path/$backup_file_name")"
        done | sha256sum | awk '{ print $1 }')
else
    backup_tree_sha256=$(printf '' | sha256sum | awk '{ print $1 }')
fi
readonly backup_tree_sha256

touch "$work_directory/before.stdout" "$work_directory/before.stderr" \
    "$work_directory/after.stdout" "$work_directory/after.stderr" \
    "$work_directory/journal.stdout" "$work_directory/journal.stderr"
chmod 0600 "$work_directory"/*

before_status=0
snapshot_state >"$work_directory/before.stdout" \
    2>"$work_directory/before.stderr" || before_status=$?
readonly before_status

failed_count=0
first_failure=none
run_assertion() {
    local diagnostic_run_label=$1

    shift
    if ! record_assertion "$diagnostic_run_label" "$@"; then
        failed_count=$((failed_count + 1))
        if [[ "$first_failure" = none ]]; then
            first_failure=$diagnostic_run_label
        fi
    fi
}

run_assertion identity_root test "$(id -u)" -eq 0
run_assertion working_directory_root test "$(pwd -P)" = /
run_assertion hostname_node_a test "$(hostname -s)" = j1-svpihole0
run_assertion architecture_arm64 test "$(dpkg --print-architecture)" = arm64
run_assertion main_regular test -f "$main_configuration"
run_assertion main_not_symlink test ! -L "$main_configuration"
run_assertion main_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$main_configuration")" = root:root:644
run_assertion main_hash_restored test "$(file_hash "$main_configuration")" = \
    "$expected_main_sha256"
run_assertion main_include_absent test \
    "$(grep -Fxc "$include_record" "$main_configuration" || true)" -eq 0
run_assertion fragment_regular test -f "$fragment"
run_assertion fragment_not_symlink test ! -L "$fragment"
run_assertion fragment_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$fragment")" = root:root:644
run_assertion fragment_hash_exact test "$(file_hash "$fragment")" = \
    "$expected_fragment_sha256"
run_assertion fragment_health_command_exact test \
    "$(grep -Fxc '    script "/usr/local/libexec/check-caddy.sh"' "$fragment")" -eq 1
run_assertion fragment_health_user_exact test \
    "$(grep -Fxc '    user keepalived_script' "$fragment")" -eq 1
run_assertion fragment_timeout_exact test \
    "$(grep -Fxc '    timeout 4' "$fragment")" -eq 1
run_assertion fragment_rise_exact test "$(grep -Fxc '    rise 3' "$fragment")" -eq 1
run_assertion fragment_fall_exact test "$(grep -Fxc '    fall 3' "$fragment")" -eq 1
run_assertion helper_regular test -f "$health_helper"
run_assertion helper_not_symlink test ! -L "$health_helper"
run_assertion helper_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$health_helper")" = root:root:755
run_assertion helper_hash_exact test "$(file_hash "$health_helper")" = \
    "$expected_health_sha256"
run_assertion environment_regular test -f "$environment_file"
run_assertion environment_not_symlink test ! -L "$environment_file"
run_assertion keepalived_script_identity_exact test \
    "$(id -u keepalived_script):$(id -g keepalived_script)" = 993:989
run_assertion keepalived_script_group_exact test \
    "$(id -gn keepalived_script)" = keepalived_script
run_assertion keepalived_script_caddy_tls_member test \
    "$(id -Gn keepalived_script | tr ' ' '\n' | grep -Fxc caddy-tls)" -eq 1
run_assertion backup_count_exact test \
    "$(printf '%s\n' "$backup_inventory" | sed '/^$/d' | wc -l)" -eq 1
run_assertion backup_path_absolute backup_path_approved "$backup_path"
run_assertion backup_regular test -d "$backup_path"
run_assertion backup_not_symlink test ! -L "$backup_path"
run_assertion backup_metadata_exact test \
    "$(metadata_or_empty '%U:%G:%a' "$backup_path")" = root:root:700
run_assertion backup_file_regular test -f "$backup_path/keepalived.conf.before"
run_assertion backup_file_not_symlink test ! -L "$backup_path/keepalived.conf.before"
run_assertion backup_file_metadata_exact test \
    "$(metadata_or_empty '%U:%G:%a' "$backup_path/keepalived.conf.before")" = \
    root:root:600
run_assertion backup_file_hash_exact test \
    "$(file_hash_or_empty "$backup_path/keepalived.conf.before")" = \
    "$expected_main_sha256"
run_assertion backup_manifest_regular test -f "$backup_path/manifest"
run_assertion backup_manifest_not_symlink test ! -L "$backup_path/manifest"
run_assertion backup_manifest_metadata_exact test \
    "$(metadata_or_empty '%U:%G:%a' "$backup_path/manifest")" = root:root:600
run_assertion backup_manifest_action_exact grep -Fxq 'action=20d-retry7' \
    "$backup_path/manifest"
run_assertion backup_manifest_node_exact grep -Fxq 'node=node-a' \
    "$backup_path/manifest"
run_assertion backup_manifest_main_hash_exact grep -Fxq \
    "main_sha256=$expected_main_sha256" "$backup_path/manifest"
run_assertion keepalived_active test "$(systemctl is-active keepalived.service)" = active
run_assertion caddy_active test "$(systemctl is-active caddy.service)" = active
run_assertion lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
keepalived_pid=$(systemctl show keepalived.service --property MainPID --value)
readonly keepalived_pid
keepalived_restarts=$(systemctl show keepalived.service --property NRestarts --value)
readonly keepalived_restarts
run_assertion keepalived_pid_numeric is_positive_integer "$keepalived_pid"
run_assertion keepalived_restart_count_numeric is_unsigned_integer \
    "$keepalived_restarts"
run_assertion caddy_ipv4_absent test "$(address_count -4 "$caddy_ipv4")" -eq 0
run_assertion caddy_ipv6_absent test "$(address_count -6 "$caddy_ipv6")" -eq 0
run_assertion dns_ipv4_present test "$(address_count -4 "$dns_ipv4")" -eq 1
run_assertion dns_ipv6_present test "$(address_count -6 "$dns_ipv6")" -eq 1

journal_status=0
journalctl -u keepalived.service --since '2026-08-05 19:42:25' \
    --until '2026-08-05 19:43:20' --no-pager --output short-iso-precise \
    >"$work_directory/journal.stdout" 2>"$work_directory/journal.stderr" || journal_status=$?
readonly journal_status
run_assertion journal_status_zero test "$journal_status" -eq 0
run_assertion journal_output_safe safe_stream "$work_directory/journal.stdout"
run_assertion journal_reload_observed grep -Fq 'Reload complete' \
    "$work_directory/journal.stdout"
# Backticks are literal journal text.
# shellcheck disable=SC2016
run_assertion journal_health_status_one_observed grep -Fq \
    'Script `check_caddy` now returning 1' "$work_directory/journal.stdout"
run_assertion journal_fault_observed grep -Fq \
    '(CADDY_IPV4) Entering FAULT STATE' "$work_directory/journal.stdout"
run_assertion journal_dualstack_fault_observed grep -Fq \
    'VRRP_Group(CADDY_DUALSTACK) Syncing instances to FAULT state' \
    "$work_directory/journal.stdout"
emit_capture journal_stdout "$work_directory/journal.stdout" || exit 97
emit_capture journal_stderr "$work_directory/journal.stderr" || exit 97

runtime_root=$work_directory/runtime
readonly runtime_root
install -d -o keepalived_script -g keepalived_script -m 0700 \
    "$runtime_root" "$runtime_root/home" "$runtime_root/config" "$runtime_root/data"

run_probe identity runuser -u keepalived_script -- id
run_assertion identity_probe_captured test -f "$work_directory/identity.status"
run_probe full_helper runuser -u keepalived_script -- "$health_helper"
run_assertion full_helper_probe_captured test -f "$work_directory/full_helper.status"
run_probe timeout_helper runuser -u keepalived_script -- \
    timeout --signal=TERM --kill-after=1s 4s "$health_helper"
run_assertion timeout_helper_probe_captured test -f "$work_directory/timeout_helper.status"
run_probe service runuser -u keepalived_script -- \
    systemctl is-active --quiet caddy.service
run_assertion service_probe_captured test -f "$work_directory/service.status"
run_probe validate probe_validate "$runtime_root"
run_assertion validate_probe_captured test -f "$work_directory/validate.status"
run_probe curl runuser -u keepalived_script -- curl --insecure --head --fail \
    --silent --show-error --max-time 3 https://localhost
run_assertion curl_probe_captured test -f "$work_directory/curl.status"

full_helper_status=$(<"$work_directory/full_helper.status")
timeout_helper_status=$(<"$work_directory/timeout_helper.status")
service_status=$(<"$work_directory/service.status")
validate_status=$(<"$work_directory/validate.status")
curl_status=$(<"$work_directory/curl.status")
full_helper_duration=$(<"$work_directory/full_helper.duration_ms")
timeout_helper_duration=$(<"$work_directory/timeout_helper.duration_ms")
service_duration=$(<"$work_directory/service.duration_ms")
validate_duration=$(<"$work_directory/validate.duration_ms")
curl_duration=$(<"$work_directory/curl.duration_ms")
readonly full_helper_status timeout_helper_status service_status validate_status curl_status
readonly full_helper_duration timeout_helper_duration service_duration validate_duration curl_duration

run_assertion full_helper_status_numeric is_unsigned_integer "$full_helper_status"
run_assertion timeout_helper_status_numeric is_unsigned_integer \
    "$timeout_helper_status"
run_assertion service_status_numeric is_unsigned_integer "$service_status"
run_assertion validate_status_numeric is_unsigned_integer "$validate_status"
run_assertion curl_status_numeric is_unsigned_integer "$curl_status"
run_assertion full_helper_duration_numeric is_unsigned_integer \
    "$full_helper_duration"
run_assertion timeout_helper_duration_numeric is_unsigned_integer \
    "$timeout_helper_duration"
run_assertion service_duration_numeric is_unsigned_integer "$service_duration"
run_assertion validate_duration_numeric is_unsigned_integer "$validate_duration"
run_assertion curl_duration_numeric is_unsigned_integer "$curl_duration"
run_assertion helper_transient_residue_absent test -z \
    "$(find /tmp -mindepth 1 -maxdepth 1 -name 'caddy-health.*' -print -quit 2>/dev/null)"

after_status=0
snapshot_state >"$work_directory/after.stdout" \
    2>"$work_directory/after.stderr" || after_status=$?
readonly after_status
run_assertion before_state_status_zero test "$before_status" -eq 0
run_assertion before_state_stderr_empty test ! -s "$work_directory/before.stderr"
run_assertion after_state_status_zero test "$after_status" -eq 0
run_assertion after_state_stderr_empty test ! -s "$work_directory/after.stderr"
run_assertion state_unchanged cmp -s "$work_directory/before.stdout" \
    "$work_directory/after.stdout"

before_state_sha256=$(file_hash "$work_directory/before.stdout")
after_state_sha256=$(file_hash "$work_directory/after.stdout")
classification=$(classify_observation "$full_helper_status" \
    "$timeout_helper_status" "$service_status" "$validate_status" \
    "$curl_status" "$timeout_helper_duration")
readonly before_state_sha256 after_state_sha256 classification

printf '%s_value_backup_path=%s\n' "$prefix" "$backup_path"
printf '%s_value_backup_tree_sha256=%s\n' "$prefix" "$backup_tree_sha256"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$before_state_sha256"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$after_state_sha256"
printf '%s_value_classification=%s\n' "$prefix" "$classification"
printf '%s_assertion_count=%s\n' "$prefix" "$(expected_assertions | wc -l)"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_helper_invoked=true\n' "$prefix"
printf '%s_notification_invoked=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_keepalived_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

if [[ "$failed_count" -ne 0 ]]; then
    exit 1
fi
exit 0
