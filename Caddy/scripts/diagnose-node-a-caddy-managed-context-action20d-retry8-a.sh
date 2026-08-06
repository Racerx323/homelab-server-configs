#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry8_a
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly health_helper=/usr/local/libexec/check-caddy.sh
readonly caddy_environment=/etc/default/caddy-ha
readonly retry8_backup=/var/backups/caddy-ha/action20d-retry8-node-a-caddy-vrrp.GLxmKH
readonly expected_main_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly expected_fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5
readonly expected_health_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly caddy_ipv4=10.1.0.56/22
readonly caddy_ipv6=fd36:5aa8:6971:1::56/128
readonly dns_ipv4=10.1.0.55/22
readonly dns_ipv6=fd36:5aa8:6971:1::55/128
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=8192
declare -A probe_statuses=()

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
is_unsigned_integer() { [[ $1 =~ ^[0-9]+$ ]]; }
address_count() {
    local diagnostic_address_family=$1
    local diagnostic_address_cidr=$2

    ip -o "$diagnostic_address_family" address show dev eth0 |
        awk -v address="$diagnostic_address_cidr" \
            '$4 == address { count++ } END { print count + 0 }'
}
safe_stream() {
    local diagnostic_stream_path=$1

    [[ "$(wc -c <"$diagnostic_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$diagnostic_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$diagnostic_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$diagnostic_stream_path"
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
        printf '%s_capture_%s_classification=unsafe_retained\n' \
            "$prefix" "$diagnostic_capture_label" >&2
        return 97
    fi
    printf '%s_capture_%s_classification=bounded_safe\n' "$prefix" "$diagnostic_capture_label"
    if [[ -s "$diagnostic_capture_path" ]]; then
        printf '%s_capture_%s_begin\n' "$prefix" "$diagnostic_capture_label"
        sed "s/^/${prefix}_capture_${diagnostic_capture_label}_content=/" \
            "$diagnostic_capture_path"
        printf '%s_capture_%s_end\n' "$prefix" "$diagnostic_capture_label"
    else
        printf '%s_capture_%s_content_secured=empty\n' "$prefix" "$diagnostic_capture_label"
    fi
}
expected_assertions() {
    printf '%s\n' \
        identity_root working_directory_root hostname_node_a architecture_arm64 \
        main_regular main_not_symlink main_metadata_exact main_hash_restored \
        main_include_absent fragment_regular fragment_not_symlink \
        fragment_metadata_exact fragment_hash_exact helper_regular \
        helper_not_symlink helper_metadata_exact helper_hash_exact \
        caddy_environment_regular backup_regular backup_not_symlink \
        backup_metadata_exact backup_main_exact backup_manifest_exact \
        keepalived_active caddy_active lighttpd_active caddy_ipv4_absent \
        caddy_ipv6_absent dns_ipv4_present dns_ipv6_present \
        keepalived_main_pid_numeric keepalived_main_pid_live \
        keepalived_vrrp_pid_unique keepalived_vrrp_pid_live \
        vrrp_environment_readable vrrp_environment_names_safe \
        vrrp_environment_sensitive_names_absent vrrp_status_readable \
        vrrp_context_readable script_user_identity script_user_primary_gid \
        script_user_caddy_tls_membership setpriv_available \
        bare_root_caddy_captured sourced_root_caddy_captured \
        full_group_helper_captured primary_group_interpreter_captured \
        primary_group_environment_captured primary_group_service_captured \
        primary_group_caddy_captured primary_group_curl_captured \
        primary_group_helper_captured all_probe_statuses_numeric \
        all_probe_outputs_safe before_state_status_zero \
        before_state_stderr_empty after_state_status_zero \
        after_state_stderr_empty state_unchanged transient_residue_absent
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
snapshot_state() {
    printf 'main=%s\n' "$(file_hash "$main_configuration")"
    printf 'fragment=%s\n' "$(file_hash "$fragment")"
    printf 'helper=%s\n' "$(file_hash "$health_helper")"
    printf 'backup=%s\n' "$(file_hash "$retry8_backup/keepalived.conf.before")"
    printf 'keepalived=%s\n' "$(systemctl is-active keepalived.service)"
    printf 'caddy=%s\n' "$(systemctl is-active caddy.service)"
    printf 'lighttpd=%s\n' "$(systemctl is-active lighttpd.service)"
    printf 'caddy4=%s\n' "$(address_count -4 "$caddy_ipv4")"
    printf 'caddy6=%s\n' "$(address_count -6 "$caddy_ipv6")"
    printf 'dns4=%s\n' "$(address_count -4 "$dns_ipv4")"
    printf 'dns6=%s\n' "$(address_count -6 "$dns_ipv6")"
}
run_probe() {
    local diagnostic_probe_label=$1
    local diagnostic_probe_status=0

    shift
    : >"$work_directory/$diagnostic_probe_label.stdout"
    : >"$work_directory/$diagnostic_probe_label.stderr"
    chmod 0600 "$work_directory/$diagnostic_probe_label.stdout" \
        "$work_directory/$diagnostic_probe_label.stderr"
    "$@" >"$work_directory/$diagnostic_probe_label.stdout" \
        2>"$work_directory/$diagnostic_probe_label.stderr" || diagnostic_probe_status=$?
    probe_statuses["$diagnostic_probe_label"]=$diagnostic_probe_status
    emit_capture "${diagnostic_probe_label}_stdout" \
        "$work_directory/$diagnostic_probe_label.stdout" || return 97
    emit_capture "${diagnostic_probe_label}_stderr" \
        "$work_directory/$diagnostic_probe_label.stderr" || return 97
    printf '%s_value_%s_status=%s\n' "$prefix" "$diagnostic_probe_label" \
        "$diagnostic_probe_status"
}
classify_probe_statuses() {
    local classification_sourced_root=$1
    local classification_full_group=$2
    local classification_interpreter=$3
    local classification_environment=$4
    local classification_service=$5
    local classification_caddy=$6
    local classification_curl=$7
    local classification_primary_helper=$8

    if [[ "$classification_sourced_root" -ne 0 ]]; then
        printf 'sourced_root_caddy_validate_failed\n'
    elif [[ "$classification_full_group" -ne 0 ]]; then
        printf 'current_health_failure_prevents_context_comparison\n'
    elif [[ "$classification_interpreter" -ne 0 ]]; then
        printf 'primary_group_interpreter_failed\n'
    elif [[ "$classification_environment" -ne 0 ]]; then
        printf 'primary_group_environment_failed\n'
    elif [[ "$classification_service" -ne 0 ]]; then
        printf 'primary_group_service_failed\n'
    elif [[ "$classification_caddy" -ne 0 && "$classification_primary_helper" -ne 0 ]]; then
        printf 'supplementary_group_boundary_reproduced_at_caddy_validate\n'
    elif [[ "$classification_curl" -ne 0 ]]; then
        printf 'primary_group_curl_failed\n'
    elif [[ "$classification_primary_helper" -ne 0 ]]; then
        printf 'primary_group_full_helper_failed_without_component_failure\n'
    else
        printf 'managed_failure_not_reproduced_by_read_only_context_probe\n'
    fi
}
classification_contract_test() {
    [[ "$(classify_probe_statuses 0 0 0 0 0 1 0 1)" = supplementary_group_boundary_reproduced_at_caddy_validate ]] || return 1
    [[ "$(classify_probe_statuses 0 0 0 0 0 0 0 0)" = managed_failure_not_reproduced_by_read_only_context_probe ]] || return 1
    [[ "$(classify_probe_statuses 0 1 0 0 0 0 0 0)" = current_health_failure_prevents_context_comparison ]] || return 1
    [[ "$(classify_probe_statuses 0 0 1 0 0 0 0 1)" = primary_group_interpreter_failed ]] || return 1
    [[ "$(classify_probe_statuses 0 0 0 1 0 0 0 1)" = primary_group_environment_failed ]] || return 1
    [[ "$(classify_probe_statuses 0 0 0 0 1 0 0 1)" = primary_group_service_failed ]] || return 1
    [[ "$(classify_probe_statuses 0 0 0 0 0 0 1 1)" = primary_group_curl_failed ]] || return 1
    [[ "$(classify_probe_statuses 0 0 0 0 0 0 0 1)" = primary_group_full_helper_failed_without_component_failure ]] || return 1
    [[ "$(classify_probe_statuses 1 0 0 0 0 0 0 0)" = sourced_root_caddy_validate_failed ]] || return 1
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]] || exit 64
        expected_assertions
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test_root=$(mktemp -d /tmp/caddy-action20d-retry8-a-self.XXXXXX)
        trap 'rm -rf -- "$self_test_root"' EXIT
        expected_assertions >"$self_test_root/labels"
        [[ "$(wc -l <"$self_test_root/labels")" -eq "$(LC_ALL=C sort -u "$self_test_root/labels" | wc -l)" ]]
        ! grep -Ev '^[a-z0-9_]+$' "$self_test_root/labels" | grep -q .
        classification_contract_test
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --classification-test)
        [[ $# -eq 1 ]] || exit 64
        classification_contract_test
        printf '%s_classification_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--expected-assertions|--self-test|--classification-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

work_directory=$(mktemp -d /tmp/caddy-action20d-retry8-a.XXXXXX)
readonly work_directory
# shellcheck disable=SC2317
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT INT TERM
touch "$work_directory/before.stdout" "$work_directory/before.stderr" \
    "$work_directory/after.stdout" "$work_directory/after.stderr"
chmod 0600 "$work_directory"/*.stdout "$work_directory"/*.stderr

before_status=0
snapshot_state >"$work_directory/before.stdout" \
    2>"$work_directory/before.stderr" || before_status=$?
readonly before_status
failed_count=0
first_failure=none

run_assertion identity_root test "$(id -u)" -eq 0
run_assertion working_directory_root test "$(pwd -P)" = /
run_assertion hostname_node_a test "$(hostname -s)" = j1-svpihole0
run_assertion architecture_arm64 test "$(dpkg --print-architecture)" = arm64
run_assertion main_regular test -f "$main_configuration"
run_assertion main_not_symlink test ! -L "$main_configuration"
run_assertion main_metadata_exact test "$(stat -c '%U:%G:%a' "$main_configuration")" = root:root:644
run_assertion main_hash_restored test "$(file_hash "$main_configuration")" = "$expected_main_sha256"
run_assertion main_include_absent test \
    "$(grep -Fxc 'include /etc/keepalived/conf.d/caddy-ha.conf' "$main_configuration" || true)" -eq 0
run_assertion fragment_regular test -f "$fragment"
run_assertion fragment_not_symlink test ! -L "$fragment"
run_assertion fragment_metadata_exact test "$(stat -c '%U:%G:%a' "$fragment")" = root:root:644
run_assertion fragment_hash_exact test "$(file_hash "$fragment")" = "$expected_fragment_sha256"
run_assertion helper_regular test -f "$health_helper"
run_assertion helper_not_symlink test ! -L "$health_helper"
run_assertion helper_metadata_exact test "$(stat -c '%U:%G:%a' "$health_helper")" = root:root:755
run_assertion helper_hash_exact test "$(file_hash "$health_helper")" = "$expected_health_sha256"
run_assertion caddy_environment_regular test -f "$caddy_environment"
run_assertion backup_regular test -d "$retry8_backup"
run_assertion backup_not_symlink test ! -L "$retry8_backup"
run_assertion backup_metadata_exact test "$(stat -c '%U:%G:%a' "$retry8_backup")" = root:root:700
run_assertion backup_main_exact test \
    "$(file_hash "$retry8_backup/keepalived.conf.before")" = "$expected_main_sha256"
# The child Bash expands its first positional parameter.
# shellcheck disable=SC2016
run_assertion backup_manifest_exact /bin/bash -c \
    '[[ $(grep -Fxc "action=20d-retry8" "$1") -eq 1 && $(grep -Fxc "node=node-a" "$1") -eq 1 && $(grep -Fxc "main_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2" "$1") -eq 1 && $(wc -l <"$1") -eq 7 ]]' \
    _ "$retry8_backup/manifest"
run_assertion keepalived_active systemctl is-active --quiet keepalived.service
run_assertion caddy_active systemctl is-active --quiet caddy.service
run_assertion lighttpd_active systemctl is-active --quiet lighttpd.service
run_assertion caddy_ipv4_absent test "$(address_count -4 "$caddy_ipv4")" -eq 0
run_assertion caddy_ipv6_absent test "$(address_count -6 "$caddy_ipv6")" -eq 0
run_assertion dns_ipv4_present test "$(address_count -4 "$dns_ipv4")" -eq 1
run_assertion dns_ipv6_present test "$(address_count -6 "$dns_ipv6")" -eq 1

keepalived_main_pid=$(systemctl show -p MainPID --value keepalived.service)
readonly keepalived_main_pid
run_assertion keepalived_main_pid_numeric is_unsigned_integer "$keepalived_main_pid"
run_assertion keepalived_main_pid_live test -d "/proc/$keepalived_main_pid"
mapfile -t vrrp_pids < <(pgrep -P "$keepalived_main_pid" -x Keepalived_vrrp || true)
run_assertion keepalived_vrrp_pid_unique test "${#vrrp_pids[@]}" -eq 1
vrrp_pid=${vrrp_pids[0]:-0}
readonly vrrp_pid
run_assertion keepalived_vrrp_pid_live test -d "/proc/$vrrp_pid"

vrrp_environment_raw=$work_directory/vrrp.environment.raw
vrrp_environment_names=$work_directory/vrrp.environment.names
vrrp_status_safe=$work_directory/vrrp.status.safe
vrrp_context_safe=$work_directory/vrrp.context.safe
readonly vrrp_environment_raw vrrp_environment_names vrrp_status_safe vrrp_context_safe
if [[ -r "/proc/$vrrp_pid/environ" ]]; then
    cp -- "/proc/$vrrp_pid/environ" "$vrrp_environment_raw"
else
    : >"$vrrp_environment_raw"
fi
run_assertion vrrp_environment_readable test -r "/proc/$vrrp_pid/environ"
tr '\0' '\n' <"$vrrp_environment_raw" | sed '/^$/d; s/=.*//' | LC_ALL=C sort -u \
    >"$vrrp_environment_names"
run_assertion vrrp_environment_names_safe test \
    "$(grep -Evc '^[A-Za-z_][A-Za-z0-9_]*$' "$vrrp_environment_names" || true)" -eq 0
run_assertion vrrp_environment_sensitive_names_absent test \
    "$(grep -Eic 'PRIVATE|SECRET|TOKEN|PASSWORD|CREDENTIAL|CADDY_TLS' \
        "$vrrp_environment_names" || true)" -eq 0
grep -E '^(Name|Umask|State|Pid|PPid|Uid|Gid|Groups|Cap(Inh|Prm|Eff|Bnd|Amb)|NoNewPrivs|Seccomp):' \
    "/proc/$vrrp_pid/status" >"$vrrp_status_safe" || true
run_assertion vrrp_status_readable test -s "$vrrp_status_safe"
{
    printf 'cwd=%s\n' "$(readlink -e "/proc/$vrrp_pid/cwd")"
    printf 'root=%s\n' "$(readlink -e "/proc/$vrrp_pid/root")"
    printf 'exe=%s\n' "$(readlink -e "/proc/$vrrp_pid/exe")"
    printf 'apparmor=%s\n' "$(cat "/proc/$vrrp_pid/attr/current" 2>/dev/null || printf unavailable)"
} >"$vrrp_context_safe"
run_assertion vrrp_context_readable test "$(grep -Ec '^(cwd|root|exe|apparmor)=' "$vrrp_context_safe")" -eq 4
run_assertion script_user_identity getent passwd keepalived_script
script_uid=$(id -u keepalived_script)
script_gid=$(id -g keepalived_script)
readonly script_uid script_gid
run_assertion script_user_primary_gid test "$script_gid" = "$(getent passwd keepalived_script | cut -d: -f4)"
run_assertion script_user_caddy_tls_membership test \
    "$(id -Gn keepalived_script | tr ' ' '\n' | grep -Fxc caddy-tls)" -eq 1
run_assertion setpriv_available test -x /usr/bin/setpriv

managed_path=$(tr '\0' '\n' <"$vrrp_environment_raw" | sed -n 's/^PATH=//p' | head -n 1)
managed_path=${managed_path:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}
readonly managed_path
# The child Bash expands its runtime path and first positional parameter.
# shellcheck disable=SC2016
probe_shell='set -Eeuo pipefail; runtime=$(mktemp -d /tmp/caddy-action20d-retry8-a-component.XXXXXX); trap '\''rm -rf -- "$runtime"'\'' EXIT; install -d -m 0700 "$runtime/home" "$runtime/config" "$runtime/data"; export HOME="$runtime/home" XDG_CONFIG_HOME="$runtime/config" XDG_DATA_HOME="$runtime/data"; set -a; source /etc/default/caddy-ha; set +a; case "$1" in environment) : ;; service) systemctl is-active --quiet caddy ;; caddy) caddy validate --config /etc/caddy/current/Caddyfile --adapter caddyfile ;; curl) curl --insecure --head --fail --silent --show-error --max-time 3 https://localhost >/dev/null ;; *) exit 64 ;; esac'
readonly probe_shell

run_probe bare_root_caddy caddy validate \
    --config /etc/caddy/current/Caddyfile --adapter caddyfile
run_assertion bare_root_caddy_captured is_unsigned_integer "${probe_statuses[bare_root_caddy]}"
run_probe sourced_root_caddy /bin/bash -c "$probe_shell" _ caddy
run_assertion sourced_root_caddy_captured is_unsigned_integer "${probe_statuses[sourced_root_caddy]}"
run_probe full_group_helper runuser -u keepalived_script -- "$health_helper"
run_assertion full_group_helper_captured is_unsigned_integer "${probe_statuses[full_group_helper]}"
run_probe primary_group_interpreter /usr/bin/setpriv --reuid="$script_uid" \
    --regid="$script_gid" --clear-groups /usr/bin/env -i PATH="$managed_path" \
    /usr/bin/env bash -c 'exit 0'
run_assertion primary_group_interpreter_captured is_unsigned_integer "${probe_statuses[primary_group_interpreter]}"
run_probe primary_group_environment /usr/bin/setpriv --reuid="$script_uid" \
    --regid="$script_gid" --clear-groups /usr/bin/env -i PATH="$managed_path" \
    /bin/bash -c "$probe_shell" _ environment
run_assertion primary_group_environment_captured is_unsigned_integer "${probe_statuses[primary_group_environment]}"
run_probe primary_group_service /usr/bin/setpriv --reuid="$script_uid" \
    --regid="$script_gid" --clear-groups /usr/bin/env -i PATH="$managed_path" \
    /bin/bash -c "$probe_shell" _ service
run_assertion primary_group_service_captured is_unsigned_integer "${probe_statuses[primary_group_service]}"
run_probe primary_group_caddy /usr/bin/setpriv --reuid="$script_uid" \
    --regid="$script_gid" --clear-groups /usr/bin/env -i PATH="$managed_path" \
    /bin/bash -c "$probe_shell" _ caddy
run_assertion primary_group_caddy_captured is_unsigned_integer "${probe_statuses[primary_group_caddy]}"
run_probe primary_group_curl /usr/bin/setpriv --reuid="$script_uid" \
    --regid="$script_gid" --clear-groups /usr/bin/env -i PATH="$managed_path" \
    /bin/bash -c "$probe_shell" _ curl
run_assertion primary_group_curl_captured is_unsigned_integer "${probe_statuses[primary_group_curl]}"
run_probe primary_group_helper /usr/bin/setpriv --reuid="$script_uid" \
    --regid="$script_gid" --clear-groups /usr/bin/env -i PATH="$managed_path" \
    "$health_helper"
run_assertion primary_group_helper_captured is_unsigned_integer "${probe_statuses[primary_group_helper]}"

all_statuses_numeric=true
for probe_status_value in \
    "${probe_statuses[bare_root_caddy]}" "${probe_statuses[sourced_root_caddy]}" \
    "${probe_statuses[full_group_helper]}" "${probe_statuses[primary_group_interpreter]}" \
    "${probe_statuses[primary_group_environment]}" "${probe_statuses[primary_group_service]}" \
    "${probe_statuses[primary_group_caddy]}" "${probe_statuses[primary_group_curl]}" \
    "${probe_statuses[primary_group_helper]}"; do
    is_unsigned_integer "$probe_status_value" || all_statuses_numeric=false
done
run_assertion all_probe_statuses_numeric test "$all_statuses_numeric" = true
all_outputs_safe=true
for probe_output_path in "$work_directory"/bare_root_caddy.* \
    "$work_directory"/sourced_root_caddy.* "$work_directory"/full_group_helper.* \
    "$work_directory"/primary_group_*.*; do
    safe_stream "$probe_output_path" || all_outputs_safe=false
done
run_assertion all_probe_outputs_safe test "$all_outputs_safe" = true

emit_capture vrrp_environment_names "$vrrp_environment_names" || exit 97
emit_capture vrrp_status "$vrrp_status_safe" || exit 97
emit_capture vrrp_context "$vrrp_context_safe" || exit 97

after_status=0
snapshot_state >"$work_directory/after.stdout" \
    2>"$work_directory/after.stderr" || after_status=$?
readonly after_status
run_assertion before_state_status_zero test "$before_status" -eq 0
run_assertion before_state_stderr_empty test ! -s "$work_directory/before.stderr"
run_assertion after_state_status_zero test "$after_status" -eq 0
run_assertion after_state_stderr_empty test ! -s "$work_directory/after.stderr"
run_assertion state_unchanged cmp -s "$work_directory/before.stdout" "$work_directory/after.stdout"
run_assertion transient_residue_absent test -z \
    "$(find /tmp -mindepth 1 -maxdepth 1 \
        \( -name 'caddy-health.*' -o -name 'caddy-action20d-retry8-a-component.*' \) \
        -print -quit 2>/dev/null)"

classification=$(classify_probe_statuses \
    "${probe_statuses[sourced_root_caddy]}" "${probe_statuses[full_group_helper]}" \
    "${probe_statuses[primary_group_interpreter]}" \
    "${probe_statuses[primary_group_environment]}" "${probe_statuses[primary_group_service]}" \
    "${probe_statuses[primary_group_caddy]}" "${probe_statuses[primary_group_curl]}" \
    "${probe_statuses[primary_group_helper]}")
readonly classification
printf '%s_value_environment_scope=vrrp_parent_inherited_environment\n' "$prefix"
printf '%s_value_historical_check_child_environment_recoverable=false\n' "$prefix"
printf '%s_value_bare_root_environment_dependency=%s\n' "$prefix" \
    "$([[ "${probe_statuses[bare_root_caddy]}" -ne 0 &&
        "${probe_statuses[sourced_root_caddy]}" -eq 0 ]] && printf true || printf false)"
printf '%s_value_vrrp_pid=%s\n' "$prefix" "$vrrp_pid"
printf '%s_value_vrrp_environment_bytes=%s\n' "$prefix" "$(wc -c <"$vrrp_environment_raw")"
printf '%s_value_vrrp_environment_entries=%s\n' "$prefix" "$(line_count "$vrrp_environment_names")"
printf '%s_value_vrrp_environment_sha256=%s\n' "$prefix" "$(file_hash "$vrrp_environment_raw")"
printf '%s_value_script_uid=%s\n' "$prefix" "$script_uid"
printf '%s_value_script_primary_gid=%s\n' "$prefix" "$script_gid"
printf '%s_value_script_supplementary_gids=%s\n' "$prefix" \
    "$(id -G keepalived_script | tr ' ' ',')"
printf '%s_value_classification=%s\n' "$prefix" "$classification"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$(file_hash "$work_directory/before.stdout")"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$(file_hash "$work_directory/after.stdout")"
printf '%s_assertion_count=%s\n' "$prefix" "$(expected_assertions | wc -l)"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_health_helper_invoked_read_only=true\n' "$prefix"
printf '%s_notification_invoked=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_keepalived_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

[[ "$failed_count" -eq 0 ]]
