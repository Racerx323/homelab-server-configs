#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_c
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly health_helper=/usr/local/libexec/check-caddy.sh
readonly environment_file=/etc/default/caddy-ha
readonly active_release=/etc/caddy/releases/action16ar-retry-node-a-default-deny
readonly expected_main_sha256=357eb09c628fa3b78efcaacf53278ab09a6574b991820632ee3ec2614265d8e2
readonly expected_fragment_sha256=6f5a58ca8fd39a1218de6fc964f54aef69f374351c0727bbb0fabf899a80ef39
readonly expected_health_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly expected_environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly keepalived_interval_ms=2000
readonly keepalived_timeout_ms=4000
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=8192
declare -A probe_statuses=()
declare -A probe_elapsed_ms=()

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
is_unsigned_integer() { [[ $1 =~ ^[0-9]+$ ]]; }
address_count() {
    local timing_address_family=$1
    local timing_expected_cidr=$2

    ip -o "-$timing_address_family" address show dev eth0 2>/dev/null |
        awk -v expected="$timing_expected_cidr" '$4 == expected { count++ }
            END { print count + 0 }'
}
unit_state() {
    local timing_unit=$1

    printf '%s:%s:%s:%s\n' \
        "$(systemctl is-active "$timing_unit" 2>/dev/null || true)" \
        "$(systemctl is-enabled "$timing_unit" 2>/dev/null || true)" \
        "$(systemctl show -p MainPID --value "$timing_unit" 2>/dev/null || true)" \
        "$(systemctl show -p NRestarts --value "$timing_unit" 2>/dev/null || true)"
}
snapshot_state() {
    printf 'main=%s\n' "$(file_hash "$main_configuration" 2>/dev/null || true)"
    printf 'fragment=%s\n' "$(file_hash "$fragment" 2>/dev/null || true)"
    printf 'health=%s\n' "$(file_hash "$health_helper" 2>/dev/null || true)"
    printf 'environment=%s\n' "$(file_hash "$environment_file" 2>/dev/null || true)"
    printf 'addresses=%s:%s:%s:%s\n' \
        "$(address_count 4 "$caddy_ipv4_cidr")" \
        "$(address_count 6 "$caddy_ipv6_cidr")" \
        "$(address_count 4 "$dns_ipv4_cidr")" \
        "$(address_count 6 "$dns_ipv6_cidr")"
    printf 'vrrp_state=%s\n' "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)"
    printf 'keepalived=%s\n' "$(unit_state keepalived.service)"
    printf 'caddy=%s\n' "$(unit_state caddy.service)"
    printf 'lighttpd=%s\n' "$(unit_state lighttpd.service)"
    printf 'lsyncd=%s\n' "$(unit_state lsyncd.service)"
}
safe_stream() {
    local timing_stream_path=$1

    [[ "$(wc -c <"$timing_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$timing_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$timing_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$timing_stream_path"
}
emit_stream() {
    local timing_stream_label=$1
    local timing_stream_path=$2

    printf '%s_capture_%s_bytes=%s\n' "$prefix" "$timing_stream_label" \
        "$(wc -c <"$timing_stream_path")"
    printf '%s_capture_%s_lines=%s\n' "$prefix" "$timing_stream_label" \
        "$(line_count "$timing_stream_path")"
    printf '%s_capture_%s_sha256=%s\n' "$prefix" "$timing_stream_label" \
        "$(file_hash "$timing_stream_path")"
    if ! safe_stream "$timing_stream_path"; then
        printf '%s_capture_%s_classification=unsafe_retained\n' \
            "$prefix" "$timing_stream_label" >&2
        return 97
    fi
    printf '%s_capture_%s_classification=bounded_safe\n' "$prefix" "$timing_stream_label"
    if [[ -s "$timing_stream_path" ]]; then
        printf '%s_capture_%s_begin\n' "$prefix" "$timing_stream_label"
        sed "s/^/${prefix}_capture_${timing_stream_label}_content=/" "$timing_stream_path"
        printf '%s_capture_%s_end\n' "$prefix" "$timing_stream_label"
    else
        printf '%s_capture_%s_content_secured=empty\n' "$prefix" "$timing_stream_label"
    fi
}
capture_command() {
    local timing_probe_label=$1
    local timing_probe_status=0
    local timing_probe_started_ns
    local timing_probe_finished_ns
    local timing_probe_stdout=$work_root/$timing_probe_label.stdout
    local timing_probe_stderr=$work_root/$timing_probe_label.stderr

    shift
    : >"$timing_probe_stdout"
    : >"$timing_probe_stderr"
    chmod 0600 "$timing_probe_stdout" "$timing_probe_stderr"
    timing_probe_started_ns=$(date +%s%N)
    "$@" >"$timing_probe_stdout" 2>"$timing_probe_stderr" || timing_probe_status=$?
    timing_probe_finished_ns=$(date +%s%N)
    probe_statuses["$timing_probe_label"]=$timing_probe_status
    probe_elapsed_ms["$timing_probe_label"]=$(((timing_probe_finished_ns - timing_probe_started_ns) / 1000000))
    emit_stream "${timing_probe_label}_stdout" "$timing_probe_stdout" || return 97
    emit_stream "${timing_probe_label}_stderr" "$timing_probe_stderr" || return 97
    printf '%s_value_%s_status=%s\n' "$prefix" "$timing_probe_label" "$timing_probe_status"
    printf '%s_value_%s_elapsed_ms=%s\n' "$prefix" "$timing_probe_label" \
        "${probe_elapsed_ms[$timing_probe_label]}"
}
historical_journal() {
    local timing_unit=$1
    local timing_since=$2
    local timing_until=$3

    journalctl --no-pager --quiet -o short-iso-precise -u "$timing_unit" \
        --since "$timing_since" --until "$timing_until" -n 400
}
expected_assertions() {
    printf '%s\n' \
        identity_root working_directory_root hostname_node_a architecture_arm64 \
        main_hash_exact fragment_hash_exact helper_hash_exact environment_hash_exact \
        keepalived_active caddy_active caddy_ipv4_exact caddy_ipv6_exact \
        dns_ipv4_exact dns_ipv6_exact vrrp_master \
        interval_exact timeout_exact rise_exact fall_exact health_user_group_exact \
        script_identity_exact script_uid_exact script_gid_exact \
        context_runtime_metadata environment_access fullchain_access private_key_access \
        before_snapshot_status_zero before_snapshot_hash_format \
        journal_keepalived_0732_status_zero journal_caddy_0732_status_zero \
        journal_keepalived_0736_status_zero journal_caddy_0736_status_zero \
        journal_keepalived_0841_status_zero journal_caddy_0841_status_zero \
        historical_overrun_present historical_returning_one_present \
        historical_returning_zero_present \
        service_probe_status_zero service_probe_elapsed_numeric \
        caddy_validate_probe_status_zero caddy_validate_probe_elapsed_numeric \
        curl_probe_status_zero curl_probe_elapsed_numeric curl_http_204 curl_http_version_observed \
        current_keepalived_journal_status_zero current_caddy_journal_status_zero \
        configuration_reload_classification_emitted certificate_access_classification_emitted \
        network_classification_emitted timeout_classification_emitted \
        after_snapshot_status_zero \
        after_snapshot_hash_format state_unchanged context_runtime_removed
}
record_assertion() {
    local timing_assertion_label=$1

    shift
    if "$@"; then
        printf '%s_assertion_%s=true\n' "$prefix" "$timing_assertion_label"
        return 0
    fi
    printf '%s_assertion_%s=false\n' "$prefix" "$timing_assertion_label"
    return 1
}
run_assertion() {
    local timing_run_label=$1

    shift
    if ! record_assertion "$timing_run_label" "$@"; then
        failed_count=$((failed_count + 1))
        if [[ "$first_failure" = none ]]; then
            first_failure=$timing_run_label
        fi
    fi
}
classify_timeout() {
    local timing_service_ms=$1
    local timing_caddy_ms=$2
    local timing_curl_ms=$3
    local timing_overrun_count=$4
    local timing_total_ms=$((timing_service_ms + timing_caddy_ms + timing_curl_ms))

    if [[ "$timing_total_ms" -ge "$keepalived_timeout_ms" ]]; then
        printf 'measured_components_exceed_timeout'
    elif [[ "$timing_total_ms" -ge "$keepalived_interval_ms" ]]; then
        printf 'measured_components_exceed_interval'
    elif [[ "$timing_overrun_count" -gt 0 ]]; then
        printf 'historical_overrun_not_reproduced'
    else
        printf 'no_overrun_evidence_observed'
    fi
}
classification_test() {
    [[ "$(classify_timeout 10 1200 900 2)" = measured_components_exceed_interval ]] || return 1
    [[ "$(classify_timeout 10 2200 2000 2)" = measured_components_exceed_timeout ]] || return 1
    [[ "$(classify_timeout 10 200 300 2)" = historical_overrun_not_reproduced ]] || return 1
    [[ "$(classify_timeout 10 200 300 0)" = no_overrun_evidence_observed ]] || return 1
}
emit_fixture_success() {
    local timing_fixture_label

    while IFS= read -r timing_fixture_label; do
        printf '%s_assertion_%s=true\n' "$prefix" "$timing_fixture_label"
    done < <(expected_assertions)
    printf '%s_value_before_snapshot_sha256=%064d\n' "$prefix" 0
    printf '%s_value_after_snapshot_sha256=%064d\n' "$prefix" 0
    printf '%s_complete_helper_invoked=false\n' "$prefix"
    printf '%s_node_b_contacted=false\n' "$prefix"
    printf '%s_service_mutations=false\n' "$prefix"
    printf '%s_keepalived_mutations=false\n' "$prefix"
    printf '%s_vrrp_mutations=false\n' "$prefix"
    printf '%s_vip_mutations=false\n' "$prefix"
    printf '%s_persistent_mutations=false\n' "$prefix"
    printf '%s_remote_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]] || exit 64
        expected_assertions
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$(expected_assertions | wc -l)" -eq "$(expected_assertions | LC_ALL=C sort -u | wc -l)" ]]
        [[ "$(expected_assertions | grep -Evc '^[a-z0-9_]+$')" -eq 0 ]]
        classification_test
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --classification-test)
        [[ $# -eq 1 ]] || exit 64
        classification_test
        printf '%s_classification_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --fixture-success)
        [[ $# -eq 1 && "${CADDY_ACTION20D_RETRY10_C_REGRESSION:-}" = 1 ]] || exit 64
        emit_fixture_success
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--expected-assertions|--self-test|--classification-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

work_root=$(mktemp -d /run/caddy-action20d-retry10-c.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
failed_count=0
first_failure=none

before_snapshot_status=0
before_snapshot=$(snapshot_state) || before_snapshot_status=$?
before_snapshot_sha256=$(printf '%s\n' "$before_snapshot" | sha256sum | awk '{ print $1 }')
readonly before_snapshot_status before_snapshot before_snapshot_sha256

run_assertion identity_root test "$(id -u)" -eq 0
run_assertion working_directory_root test "$(pwd -P)" = /
run_assertion hostname_node_a test "$(hostname -s)" = j1-svpihole0
run_assertion architecture_arm64 test "$(dpkg --print-architecture)" = arm64
run_assertion main_hash_exact test "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$expected_main_sha256"
run_assertion fragment_hash_exact test "$(file_hash "$fragment" 2>/dev/null || true)" = "$expected_fragment_sha256"
run_assertion helper_hash_exact test "$(file_hash "$health_helper" 2>/dev/null || true)" = "$expected_health_sha256"
run_assertion environment_hash_exact test "$(file_hash "$environment_file" 2>/dev/null || true)" = "$expected_environment_sha256"
run_assertion keepalived_active systemctl is-active --quiet keepalived.service
run_assertion caddy_active systemctl is-active --quiet caddy.service
run_assertion caddy_ipv4_exact test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 1
run_assertion caddy_ipv6_exact test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 1
run_assertion dns_ipv4_exact test "$(address_count 4 "$dns_ipv4_cidr")" -eq 1
run_assertion dns_ipv6_exact test "$(address_count 6 "$dns_ipv6_cidr")" -eq 1
run_assertion vrrp_master test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = MASTER
run_assertion interval_exact test "$(grep -Fxc '    interval 2' "$fragment" || true)" -eq 1
run_assertion timeout_exact test "$(grep -Fxc '    timeout 4' "$fragment" || true)" -eq 1
run_assertion rise_exact test "$(grep -Fxc '    rise 3' "$fragment" || true)" -eq 1
run_assertion fall_exact test "$(grep -Fxc '    fall 3' "$fragment" || true)" -eq 1
run_assertion health_user_group_exact test \
    "$(grep -Fxc '    user keepalived_script caddy-tls' "$fragment" || true)" -eq 1
run_assertion script_identity_exact getent passwd keepalived_script
run_assertion script_uid_exact test "$(id -u keepalived_script)" -eq 993
run_assertion script_gid_exact test "$(getent group caddy-tls | cut -d: -f3)" -eq 991

context_root=$(mktemp -d /run/caddy-action20d-retry10-c-context.XXXXXX)
readonly context_root
chown 993:991 "$context_root"
chmod 0700 "$context_root"
install -d -o 993 -g 991 -m 0700 "$context_root/home" "$context_root/config" "$context_root/data"
run_assertion context_runtime_metadata test "$(stat -c '%u:%g:%a' "$context_root")" = 993:991:700
readonly -a exact_context=(/usr/bin/setpriv --reuid=993 --regid=991 --clear-groups --)
run_assertion environment_access "${exact_context[@]}" test -r "$environment_file"
run_assertion fullchain_access "${exact_context[@]}" test -r "$active_release/tls/fullchain.pem"
run_assertion private_key_access "${exact_context[@]}" test -r "$active_release/tls/privkey.pem"
run_assertion before_snapshot_status_zero test "$before_snapshot_status" -eq 0
run_assertion before_snapshot_hash_format test "${#before_snapshot_sha256}" -eq 64

capture_command journal_keepalived_0732 historical_journal keepalived.service \
    '2026-08-06 07:31:30' '2026-08-06 07:33:00'
capture_command journal_caddy_0732 historical_journal caddy.service \
    '2026-08-06 07:31:30' '2026-08-06 07:33:00'
capture_command journal_keepalived_0736 historical_journal keepalived.service \
    '2026-08-06 07:36:20' '2026-08-06 07:37:15'
capture_command journal_caddy_0736 historical_journal caddy.service \
    '2026-08-06 07:36:20' '2026-08-06 07:37:15'
capture_command journal_keepalived_0841 historical_journal keepalived.service \
    '2026-08-06 08:41:15' '2026-08-06 08:42:15'
capture_command journal_caddy_0841 historical_journal caddy.service \
    '2026-08-06 08:41:15' '2026-08-06 08:42:15'

for journal_label in journal_keepalived_0732 journal_caddy_0732 \
    journal_keepalived_0736 journal_caddy_0736 \
    journal_keepalived_0841 journal_caddy_0841; do
    run_assertion "${journal_label}_status_zero" test "${probe_statuses[$journal_label]}" -eq 0
done

cat "$work_root"/journal_keepalived_*.stdout >"$work_root/historical.keepalived"
historical_overrun_count=$(grep -Fc 'already running, expect idle - skipping run' \
    "$work_root/historical.keepalived" || true)
# Backticks are literal journal content.
# shellcheck disable=SC2016
historical_returning_one_count=$(grep -Ec 'Script `check_caddy` now returning 1' \
    "$work_root/historical.keepalived" || true)
# Backticks are literal journal content.
# shellcheck disable=SC2016
historical_returning_zero_count=$(grep -Ec 'Script `check_caddy` now returning 0' \
    "$work_root/historical.keepalived" || true)
readonly historical_overrun_count historical_returning_one_count historical_returning_zero_count
printf '%s_value_historical_overrun_count=%s\n' "$prefix" "$historical_overrun_count"
printf '%s_value_historical_returning_one_count=%s\n' "$prefix" "$historical_returning_one_count"
printf '%s_value_historical_returning_zero_count=%s\n' "$prefix" "$historical_returning_zero_count"
run_assertion historical_overrun_present test "$historical_overrun_count" -gt 0
run_assertion historical_returning_one_present test "$historical_returning_one_count" -gt 0
run_assertion historical_returning_zero_present test "$historical_returning_zero_count" -gt 0

observation_start=$(date '+%Y-%m-%d %H:%M:%S')
readonly observation_start
capture_command service_probe "${exact_context[@]}" /usr/bin/systemctl is-active --quiet caddy.service
capture_command caddy_validate_probe "${exact_context[@]}" /usr/bin/env \
    HOME="$context_root/home" XDG_CONFIG_HOME="$context_root/config" \
    XDG_DATA_HOME="$context_root/data" /bin/bash -c \
    'set -a; source /etc/default/caddy-ha; set +a; exec /usr/bin/caddy validate --config /etc/caddy/current/Caddyfile --adapter caddyfile'
capture_command curl_probe "${exact_context[@]}" /usr/bin/curl --insecure --head \
    --fail --silent --show-error --max-time 3 --output /dev/null \
    --write-out 'http_version=%{http_version}\nhttp_code=%{http_code}\nremote_ip=%{remote_ip}\n' \
    https://localhost
run_assertion service_probe_status_zero test "${probe_statuses[service_probe]}" -eq 0
run_assertion service_probe_elapsed_numeric is_unsigned_integer "${probe_elapsed_ms[service_probe]}"
run_assertion caddy_validate_probe_status_zero test "${probe_statuses[caddy_validate_probe]}" -eq 0
run_assertion caddy_validate_probe_elapsed_numeric is_unsigned_integer "${probe_elapsed_ms[caddy_validate_probe]}"
run_assertion curl_probe_status_zero test "${probe_statuses[curl_probe]}" -eq 0
run_assertion curl_probe_elapsed_numeric is_unsigned_integer "${probe_elapsed_ms[curl_probe]}"
run_assertion curl_http_204 grep -Fqx 'http_code=204' "$work_root/curl_probe.stdout"
run_assertion curl_http_version_observed grep -Eq '^http_version=(1\.1|2|3)$' "$work_root/curl_probe.stdout"

capture_command current_keepalived_journal historical_journal keepalived.service \
    "$observation_start" 'now'
capture_command current_caddy_journal historical_journal caddy.service \
    "$observation_start" 'now'
run_assertion current_keepalived_journal_status_zero test "${probe_statuses[current_keepalived_journal]}" -eq 0
run_assertion current_caddy_journal_status_zero test "${probe_statuses[current_caddy_journal]}" -eq 0

reload_count=0
for reload_capture in "$work_root"/journal_*.stdout "$work_root"/current_*_journal.stdout; do
    reload_capture_count=$(grep -Eic 'reload|reloading|configuration loaded' \
        "$reload_capture" || true)
    reload_count=$((reload_count + reload_capture_count))
done
certificate_classification=access_succeeded
if [[ "${probe_statuses[caddy_validate_probe]}" -ne 0 ]]; then
    certificate_classification=validation_failed_after_access_succeeded
fi
network_classification=localhost_http_204_succeeded
if [[ "${probe_statuses[curl_probe]}" -ne 0 ]]; then
    network_classification=localhost_request_failed
fi
timeout_classification=$(classify_timeout "${probe_elapsed_ms[service_probe]}" \
    "${probe_elapsed_ms[caddy_validate_probe]}" "${probe_elapsed_ms[curl_probe]}" \
    "$historical_overrun_count")
total_component_ms=$((probe_elapsed_ms[service_probe] + \
    probe_elapsed_ms[caddy_validate_probe] + probe_elapsed_ms[curl_probe]))
readonly reload_count certificate_classification network_classification
readonly timeout_classification total_component_ms
printf '%s_value_configuration_reload_count=%s\n' "$prefix" "$reload_count"
printf '%s_value_configuration_reload_correlation=%s\n' "$prefix" \
    "$([[ "$reload_count" -gt 0 ]] && printf observed || printf not_observed)"
printf '%s_value_certificate_access_correlation=%s\n' "$prefix" "$certificate_classification"
printf '%s_value_network_correlation=%s\n' "$prefix" "$network_classification"
printf '%s_value_timeout_correlation=%s\n' "$prefix" "$timeout_classification"
printf '%s_value_total_component_elapsed_ms=%s\n' "$prefix" "$total_component_ms"
run_assertion configuration_reload_classification_emitted is_unsigned_integer "$reload_count"
run_assertion certificate_access_classification_emitted test -n "$certificate_classification"
run_assertion network_classification_emitted test -n "$network_classification"
run_assertion timeout_classification_emitted test -n "$timeout_classification"

rm -rf -- "$context_root"
after_snapshot_status=0
after_snapshot=$(snapshot_state) || after_snapshot_status=$?
after_snapshot_sha256=$(printf '%s\n' "$after_snapshot" | sha256sum | awk '{ print $1 }')
readonly after_snapshot_status after_snapshot after_snapshot_sha256
run_assertion after_snapshot_status_zero test "$after_snapshot_status" -eq 0
run_assertion after_snapshot_hash_format test "${#after_snapshot_sha256}" -eq 64
run_assertion state_unchanged test "$after_snapshot_sha256" = "$before_snapshot_sha256"
run_assertion context_runtime_removed test ! -e "$context_root"

printf '%s_value_before_snapshot_sha256=%s\n' "$prefix" "$before_snapshot_sha256"
printf '%s_value_after_snapshot_sha256=%s\n' "$prefix" "$after_snapshot_sha256"
printf '%s_complete_helper_invoked=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_keepalived_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_remote_complete=true\n' "$prefix"
[[ "$failed_count" -eq 0 ]]
