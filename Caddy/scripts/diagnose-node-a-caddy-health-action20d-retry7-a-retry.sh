#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry7_a_retry
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly health_helper=/usr/local/libexec/check-caddy.sh
readonly expected_main_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly expected_fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5
readonly expected_health_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly caddy_ipv4=10.1.0.56/22
readonly caddy_ipv6=fd36:5aa8:6971:1::56/128
readonly dns_ipv4=10.1.0.55/22
readonly dns_ipv6=fd36:5aa8:6971:1::55/128
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=8192

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
address_count() {
    local diagnostic_address_family=$1
    local diagnostic_address_cidr=$2

    ip -o "$diagnostic_address_family" address show dev eth0 |
        awk -v address="$diagnostic_address_cidr" \
            '$4 == address { count++ } END { print count + 0 }'
}
is_unsigned_integer() { [[ $1 =~ ^[0-9]+$ ]]; }
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
        printf '%s_capture_%s_classification=unsafe\n' "$prefix" "$diagnostic_capture_label"
        return 1
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
        main_regular main_hash_restored main_include_absent fragment_regular \
        fragment_hash_exact helper_regular helper_hash_exact keepalived_active \
        caddy_active lighttpd_active caddy_ipv4_absent caddy_ipv6_absent \
        dns_ipv4_present dns_ipv6_present ancestry_root_searchable \
        ancestry_tmp_searchable ancestry_work_searchable ancestry_runtime_searchable \
        ancestry_home_searchable ancestry_config_searchable ancestry_data_searchable \
        ancestry_work_metadata_exact ancestry_runtime_metadata_exact \
        ancestry_home_metadata_exact ancestry_config_metadata_exact \
        ancestry_data_metadata_exact ancestry_gate_complete validate_probe_captured \
        validate_status_numeric validate_output_safe before_state_status_zero \
        before_state_stderr_empty after_state_status_zero after_state_stderr_empty \
        state_unchanged transient_residue_absent
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
run_ancestry_assertion() {
    local diagnostic_ancestry_label=$1

    shift
    if ! record_assertion "$diagnostic_ancestry_label" "$@"; then
        ancestry_failed_count=$((ancestry_failed_count + 1))
        failed_count=$((failed_count + 1))
        if [[ "$first_failure" = none ]]; then
            first_failure=$diagnostic_ancestry_label
        fi
    fi
}
snapshot_state() {
    printf 'main=%s\n' "$(file_hash "$main_configuration")"
    printf 'fragment=%s\n' "$(file_hash "$fragment")"
    printf 'helper=%s\n' "$(file_hash "$health_helper")"
    printf 'keepalived=%s\n' "$(systemctl is-active keepalived.service)"
    printf 'caddy=%s\n' "$(systemctl is-active caddy.service)"
    printf 'lighttpd=%s\n' "$(systemctl is-active lighttpd.service)"
    printf 'caddy4=%s\n' "$(address_count -4 "$caddy_ipv4")"
    printf 'caddy6=%s\n' "$(address_count -6 "$caddy_ipv6")"
    printf 'dns4=%s\n' "$(address_count -4 "$dns_ipv4")"
    printf 'dns6=%s\n' "$(address_count -6 "$dns_ipv6")"
}
path_searchable_as() {
    local diagnostic_search_user=$1
    local diagnostic_search_path=$2

    runuser -u "$diagnostic_search_user" -- test -x "$diagnostic_search_path"
}
ancestry_contract_test() (
    local diagnostic_contract_root
    local diagnostic_contract_user=nobody

    [[ "$(id -u)" -eq 0 ]] || {
        printf '%s_ancestry_contract_skipped_nonroot=true\n' "$prefix"
        return 0
    }
    getent passwd "$diagnostic_contract_user" >/dev/null
    diagnostic_contract_root=$(mktemp -d /tmp/caddy-action20d-retry7-a-retry-contract.XXXXXX)
    trap 'rm -rf -- "$diagnostic_contract_root"' EXIT
    install -d -o "$diagnostic_contract_user" -g "$(id -gn "$diagnostic_contract_user")" \
        -m 0700 "$diagnostic_contract_root/runtime"
    if path_searchable_as "$diagnostic_contract_user" "$diagnostic_contract_root"; then
        return 1
    fi
    printf '%s_ancestry_contract_root0700_rejected=true\n' "$prefix"
    chown root:"$(id -gn "$diagnostic_contract_user")" "$diagnostic_contract_root"
    chmod 0710 "$diagnostic_contract_root"
    path_searchable_as "$diagnostic_contract_user" "$diagnostic_contract_root"
    path_searchable_as "$diagnostic_contract_user" "$diagnostic_contract_root/runtime"
    printf '%s_ancestry_contract_searchable_parent_accepted=true\n' "$prefix"
)

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]] || exit 64
        expected_assertions
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test_root=$(mktemp -d /tmp/caddy-action20d-retry7-a-retry-self.XXXXXX)
        trap 'rm -rf -- "$self_test_root"' EXIT
        expected_assertions >"$self_test_root/labels"
        [[ "$(wc -l <"$self_test_root/labels")" -eq "$(LC_ALL=C sort -u "$self_test_root/labels" | wc -l)" ]]
        ! grep -Ev '^[a-z0-9_]+$' "$self_test_root/labels" | grep -q .
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --ancestry-contract-test)
        [[ $# -eq 1 ]] || exit 64
        ancestry_contract_test
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--expected-assertions|--self-test|--ancestry-contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

work_directory=$(mktemp -d /tmp/caddy-action20d-retry7-a-retry.XXXXXX)
readonly work_directory
# shellcheck disable=SC2317
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT INT TERM
chown root:keepalived_script "$work_directory"
chmod 0710 "$work_directory"
runtime_root=$work_directory/runtime
readonly runtime_root
install -d -o keepalived_script -g keepalived_script -m 0700 \
    "$runtime_root" "$runtime_root/home" "$runtime_root/config" "$runtime_root/data"
touch "$work_directory/before.stdout" "$work_directory/before.stderr" \
    "$work_directory/after.stdout" "$work_directory/after.stderr" \
    "$work_directory/validate.stdout" "$work_directory/validate.stderr"
chmod 0600 "$work_directory"/*.stdout "$work_directory"/*.stderr

before_status=0
snapshot_state >"$work_directory/before.stdout" \
    2>"$work_directory/before.stderr" || before_status=$?
readonly before_status
failed_count=0
first_failure=none
ancestry_failed_count=0

run_assertion identity_root test "$(id -u)" -eq 0
run_assertion working_directory_root test "$(pwd -P)" = /
run_assertion hostname_node_a test "$(hostname -s)" = j1-svpihole0
run_assertion architecture_arm64 test "$(dpkg --print-architecture)" = arm64
run_assertion main_regular test -f "$main_configuration"
run_assertion main_hash_restored test "$(file_hash "$main_configuration")" = "$expected_main_sha256"
run_assertion main_include_absent test \
    "$(grep -Fxc 'include /etc/keepalived/conf.d/caddy-ha.conf' "$main_configuration" || true)" -eq 0
run_assertion fragment_regular test -f "$fragment"
run_assertion fragment_hash_exact test "$(file_hash "$fragment")" = "$expected_fragment_sha256"
run_assertion helper_regular test -f "$health_helper"
run_assertion helper_hash_exact test "$(file_hash "$health_helper")" = "$expected_health_sha256"
run_assertion keepalived_active test "$(systemctl is-active keepalived.service)" = active
run_assertion caddy_active test "$(systemctl is-active caddy.service)" = active
run_assertion lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
run_assertion caddy_ipv4_absent test "$(address_count -4 "$caddy_ipv4")" -eq 0
run_assertion caddy_ipv6_absent test "$(address_count -6 "$caddy_ipv6")" -eq 0
run_assertion dns_ipv4_present test "$(address_count -4 "$dns_ipv4")" -eq 1
run_assertion dns_ipv6_present test "$(address_count -6 "$dns_ipv6")" -eq 1

run_ancestry_assertion ancestry_root_searchable path_searchable_as keepalived_script /
run_ancestry_assertion ancestry_tmp_searchable path_searchable_as keepalived_script /tmp
run_ancestry_assertion ancestry_work_searchable path_searchable_as keepalived_script "$work_directory"
run_ancestry_assertion ancestry_runtime_searchable path_searchable_as keepalived_script "$runtime_root"
run_ancestry_assertion ancestry_home_searchable path_searchable_as keepalived_script "$runtime_root/home"
run_ancestry_assertion ancestry_config_searchable path_searchable_as keepalived_script "$runtime_root/config"
run_ancestry_assertion ancestry_data_searchable path_searchable_as keepalived_script "$runtime_root/data"
run_ancestry_assertion ancestry_work_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$work_directory")" = root:keepalived_script:710
run_ancestry_assertion ancestry_runtime_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$runtime_root")" = keepalived_script:keepalived_script:700
run_ancestry_assertion ancestry_home_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$runtime_root/home")" = keepalived_script:keepalived_script:700
run_ancestry_assertion ancestry_config_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$runtime_root/config")" = keepalived_script:keepalived_script:700
run_ancestry_assertion ancestry_data_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$runtime_root/data")" = keepalived_script:keepalived_script:700
run_assertion ancestry_gate_complete test "$ancestry_failed_count" -eq 0

validate_status=not_run
if [[ "$ancestry_failed_count" -eq 0 ]]; then
    validate_status=0
    runuser -u keepalived_script -- env \
        HOME="$runtime_root/home" XDG_CONFIG_HOME="$runtime_root/config" \
        XDG_DATA_HOME="$runtime_root/data" /bin/bash -c \
        'set -a; source /etc/default/caddy-ha; set +a; exec /usr/bin/caddy validate --config /etc/caddy/current/Caddyfile --adapter caddyfile' \
        >"$work_directory/validate.stdout" 2>"$work_directory/validate.stderr" || validate_status=$?
fi
readonly validate_status
run_assertion validate_probe_captured test "$validate_status" != not_run
run_assertion validate_status_numeric is_unsigned_integer "$validate_status"
validate_output_safe=true
safe_stream "$work_directory/validate.stdout" || validate_output_safe=false
safe_stream "$work_directory/validate.stderr" || validate_output_safe=false
run_assertion validate_output_safe test "$validate_output_safe" = true
emit_capture validate_stdout "$work_directory/validate.stdout" || exit 97
emit_capture validate_stderr "$work_directory/validate.stderr" || exit 97

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
    "$(find /tmp -mindepth 1 -maxdepth 1 -name 'caddy-health.*' -print -quit 2>/dev/null)"

if [[ "$ancestry_failed_count" -ne 0 ]]; then
    classification=ancestry_gate_failed
elif [[ "$validate_status" -eq 0 ]]; then
    classification=caddy_validate_passed_after_searchable_ancestry
else
    classification=caddy_validate_failed_after_searchable_ancestry
fi
readonly classification
printf '%s_value_validate_status=%s\n' "$prefix" "$validate_status"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$(file_hash "$work_directory/before.stdout")"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$(file_hash "$work_directory/after.stdout")"
printf '%s_value_ancestry_failed_count=%s\n' "$prefix" "$ancestry_failed_count"
printf '%s_value_classification=%s\n' "$prefix" "$classification"
printf '%s_assertion_count=%s\n' "$prefix" "$(expected_assertions | wc -l)"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_caddy_validate_invoked=%s\n' "$prefix" "$([[ "$validate_status" != not_run ]] && printf true || printf false)"
printf '%s_health_helper_invoked=false\n' "$prefix"
printf '%s_notification_invoked=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_keepalived_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

[[ "$failed_count" -eq 0 ]]
