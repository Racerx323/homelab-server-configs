#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_26_a
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly accepted_action26_outer=$script_directory/run-workstation-caddy-protocols-action26-outer.sh
readonly accepted_action26_outer_sha256=58edc2c10115dcd2b74e9b1b65e4afda7eaab3d6801301a698991d65ced943fc
readonly hostname=proxy.local.theama.co
readonly node_a_ipv6=fd36:5aa8:6971:1::53
readonly node_b_ipv6=fd36:5aa8:6971:1::54
readonly caddy_vip_ipv6=fd36:5aa8:6971:1::56
readonly maximum_capture_bytes=4096
readonly maximum_capture_lines=32
action26a_work_root=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
check() {
    local action26a_check_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26a_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26a_check_label" >&2
    return 1
}
expected_checks() {
    printf '%s\n' \
        accepted_action26_outer_hash ip_executable curl_executable \
        node_a_route_stdout_safe node_a_route_stderr_safe \
        node_b_route_stdout_safe node_b_route_stderr_safe \
        caddy_vip_route_stdout_safe caddy_vip_route_stderr_safe \
        node_a_neigh_before_stdout_safe node_a_neigh_before_stderr_safe \
        node_b_neigh_before_stdout_safe node_b_neigh_before_stderr_safe \
        caddy_vip_neigh_before_stdout_safe caddy_vip_neigh_before_stderr_safe \
        node_a_probe_stdout_safe node_a_probe_stderr_safe node_a_probe_protocol_present \
        node_a_probe_http_status_present node_a_probe_body_bytes_present \
        node_a_probe_redirects_present \
        node_b_probe_stdout_safe node_b_probe_stderr_safe node_b_probe_protocol_present \
        node_b_probe_http_status_present node_b_probe_body_bytes_present \
        node_b_probe_redirects_present \
        caddy_vip_probe_stdout_safe caddy_vip_probe_stderr_safe \
        caddy_vip_probe_protocol_present caddy_vip_probe_http_status_present \
        caddy_vip_probe_body_bytes_present caddy_vip_probe_redirects_present \
        node_a_neigh_after_stdout_safe node_a_neigh_after_stderr_safe \
        node_b_neigh_after_stdout_safe node_b_neigh_after_stderr_safe \
        caddy_vip_neigh_after_stdout_safe caddy_vip_neigh_after_stderr_safe \
        classification_allowed
}
safe_capture() {
    local action26a_capture_path=$1

    [[ "$(wc -c <"$action26a_capture_path")" -le "$maximum_capture_bytes" ]] || return 1
    [[ "$(line_count "$action26a_capture_path")" -le "$maximum_capture_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action26a_capture_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:' \
        "$action26a_capture_path"
}
emit_capture() {
    local action26a_capture_label=$1
    local action26a_capture_path=$2

    printf '%s_observed_%s_bytes=%s\n' "$prefix" "$action26a_capture_label" \
        "$(wc -c <"$action26a_capture_path")"
    printf '%s_observed_%s_lines=%s\n' "$prefix" "$action26a_capture_label" \
        "$(line_count "$action26a_capture_path")"
    printf '%s_observed_%s_sha256=%s\n' "$prefix" "$action26a_capture_label" \
        "$(file_hash "$action26a_capture_path")"
    if ! safe_capture "$action26a_capture_path"; then
        printf '%s_observed_%s_classification=unsafe_retained\n' \
            "$prefix" "$action26a_capture_label" >&2
        return 97
    fi
    printf '%s_observed_%s_classification=bounded_safe\n' "$prefix" "$action26a_capture_label"
    if [[ -s "$action26a_capture_path" ]]; then
        printf '%s_observed_%s_begin\n' "$prefix" "$action26a_capture_label"
        cat "$action26a_capture_path"
        printf '%s_observed_%s_end\n' "$prefix" "$action26a_capture_label"
    else
        printf '%s_observed_%s_content=empty\n' "$prefix" "$action26a_capture_label"
    fi
}
value_for() {
    local action26a_value_key=$1
    local action26a_value_path=$2

    sed -n "s/^${action26a_value_key}=//p" "$action26a_value_path"
}
run_ip_capture() {
    local action26a_ip_label=$1
    shift
    local action26a_ip_stdout=$action26a_work_root/${action26a_ip_label}.stdout
    local action26a_ip_stderr=$action26a_work_root/${action26a_ip_label}.stderr
    local action26a_ip_status=0

    "${CADDY_ACTION26A_IP_BIN:-ip}" "$@" >"$action26a_ip_stdout" \
        2>"$action26a_ip_stderr" || action26a_ip_status=$?
    printf '%s\n' "$action26a_ip_status" >"$action26a_work_root/${action26a_ip_label}.status"
    printf '%s_observed_%s_status=%s\n' "$prefix" "$action26a_ip_label" "$action26a_ip_status"
    emit_capture "${action26a_ip_label}_stdout" "$action26a_ip_stdout" || return $?
    emit_capture "${action26a_ip_label}_stderr" "$action26a_ip_stderr" || return $?
    check "${action26a_ip_label}_stdout_safe" safe_capture "$action26a_ip_stdout" || return 1
    check "${action26a_ip_label}_stderr_safe" safe_capture "$action26a_ip_stderr" || return 1
}
run_probe() {
    local action26a_probe_label=$1
    local action26a_probe_ip=$2
    local action26a_probe_stdout=$action26a_work_root/${action26a_probe_label}.stdout
    local action26a_probe_stderr=$action26a_work_root/${action26a_probe_label}.stderr
    local action26a_probe_status=0
    local action26a_probe_protocol
    local action26a_probe_http_status
    local action26a_probe_remote_ip
    local action26a_probe_body_bytes
    local action26a_probe_redirects

    "${CADDY_ACTION26A_CURL_BIN:-curl}" --http1.1 --insecure --silent --show-error \
        --connect-timeout 3 --max-time 8 \
        --resolve "$hostname:443:[$action26a_probe_ip]" --output /dev/null \
        --write-out $'protocol=%{http_version}\nstatus=%{http_code}\nremote_ip=%{remote_ip}\nbody_bytes=%{size_download}\nredirects=%{num_redirects}\n' \
        "https://$hostname/" >"$action26a_probe_stdout" 2>"$action26a_probe_stderr" ||
        action26a_probe_status=$?
    printf '%s\n' "$action26a_probe_status" >"$action26a_work_root/${action26a_probe_label}.status"
    printf '%s_observed_%s_command_status=%s\n' "$prefix" "$action26a_probe_label" \
        "$action26a_probe_status"
    emit_capture "${action26a_probe_label}_stdout" "$action26a_probe_stdout" || return $?
    emit_capture "${action26a_probe_label}_stderr" "$action26a_probe_stderr" || return $?
    check "${action26a_probe_label}_stdout_safe" safe_capture "$action26a_probe_stdout" || return 1
    check "${action26a_probe_label}_stderr_safe" safe_capture "$action26a_probe_stderr" || return 1
    action26a_probe_protocol=$(value_for protocol "$action26a_probe_stdout") || return 1
    action26a_probe_http_status=$(value_for status "$action26a_probe_stdout") || return 1
    action26a_probe_remote_ip=$(value_for remote_ip "$action26a_probe_stdout") || return 1
    action26a_probe_body_bytes=$(value_for body_bytes "$action26a_probe_stdout") || return 1
    action26a_probe_redirects=$(value_for redirects "$action26a_probe_stdout") || return 1
    printf '%s_observed_%s_protocol=%s\n' "$prefix" "$action26a_probe_label" \
        "$action26a_probe_protocol"
    printf '%s_observed_%s_http_status=%s\n' "$prefix" "$action26a_probe_label" \
        "$action26a_probe_http_status"
    printf '%s_observed_%s_remote_ip=%s\n' "$prefix" "$action26a_probe_label" \
        "$action26a_probe_remote_ip"
    printf '%s_observed_%s_body_bytes=%s\n' "$prefix" "$action26a_probe_label" \
        "$action26a_probe_body_bytes"
    printf '%s_observed_%s_redirects=%s\n' "$prefix" "$action26a_probe_label" \
        "$action26a_probe_redirects"
    check "${action26a_probe_label}_protocol_present" test -n "$action26a_probe_protocol" || return 1
    check "${action26a_probe_label}_http_status_present" test -n "$action26a_probe_http_status" || return 1
    check "${action26a_probe_label}_body_bytes_present" test -n "$action26a_probe_body_bytes" || return 1
    check "${action26a_probe_label}_redirects_present" test -n "$action26a_probe_redirects" || return 1
}
probe_healthy() {
    local action26a_health_label=$1
    local action26a_health_ip=$2
    local action26a_health_stdout=$action26a_work_root/${action26a_health_label}.stdout

    [[ "$(<"$action26a_work_root/${action26a_health_label}.status")" = 0 ]] || return 1
    [[ "$(value_for protocol "$action26a_health_stdout")" = 1.1 ]] || return 1
    [[ "$(value_for status "$action26a_health_stdout")" = 204 ]] || return 1
    [[ "$(value_for remote_ip "$action26a_health_stdout")" = "$action26a_health_ip" ]]
}
classify_result() {
    local action26a_route_status
    local action26a_node_a_status
    local action26a_node_b_status

    action26a_route_status=$(<"$action26a_work_root/caddy_vip_route.status") || return 1
    action26a_node_a_status=$(<"$action26a_work_root/node_a_probe.status") || return 1
    action26a_node_b_status=$(<"$action26a_work_root/node_b_probe.status") || return 1

    if [[ "$action26a_route_status" -ne 0 ]]; then
        printf 'vip_route_missing\n'
    elif probe_healthy caddy_vip_probe "$caddy_vip_ipv6"; then
        printf 'vip_https_healthy\n'
    elif probe_healthy node_a_probe "$node_a_ipv6" || probe_healthy node_b_probe "$node_b_ipv6"; then
        printf 'vip_specific_https_failure\n'
    elif [[ "$action26a_node_a_status" -ne 0 && "$action26a_node_b_status" -ne 0 ]]; then
        printf 'workstation_ipv6_https_path_failure\n'
    else
        printf 'indeterminate_ipv6_response_path\n'
    fi
}
classification_allowed() {
    case "$1" in
        vip_route_missing | vip_https_healthy | vip_specific_https_failure | \
            workstation_ipv6_https_path_failure | indeterminate_ipv6_response_path) return 0 ;;
        *) return 1 ;;
    esac
}
cleanup() {
    local action26a_cleanup_status=$?

    trap - EXIT INT TERM
    [[ -z "$action26a_work_root" ]] || rm -rf -- "$action26a_work_root"
    exit "$action26a_cleanup_status"
}
run_action() {
    local action26a_classification

    action26a_work_root=$(mktemp -d /tmp/caddy-action26-a.XXXXXX)
    trap cleanup EXIT INT TERM
    check accepted_action26_outer_hash test "$(file_hash "$accepted_action26_outer")" = \
        "$accepted_action26_outer_sha256" || return 1
    check ip_executable test -x "$(command -v "${CADDY_ACTION26A_IP_BIN:-ip}")" || return 1
    check curl_executable test -x "$(command -v "${CADDY_ACTION26A_CURL_BIN:-curl}")" || return 1

    run_ip_capture node_a_route -6 route get "$node_a_ipv6" || return 1
    run_ip_capture node_b_route -6 route get "$node_b_ipv6" || return 1
    run_ip_capture caddy_vip_route -6 route get "$caddy_vip_ipv6" || return 1

    run_ip_capture node_a_neigh_before -6 neigh show to "$node_a_ipv6" || return 1
    run_ip_capture node_b_neigh_before -6 neigh show to "$node_b_ipv6" || return 1
    run_ip_capture caddy_vip_neigh_before -6 neigh show to "$caddy_vip_ipv6" || return 1
    run_probe node_a_probe "$node_a_ipv6" || return 1
    run_probe node_b_probe "$node_b_ipv6" || return 1
    run_probe caddy_vip_probe "$caddy_vip_ipv6" || return 1
    run_ip_capture node_a_neigh_after -6 neigh show to "$node_a_ipv6" || return 1
    run_ip_capture node_b_neigh_after -6 neigh show to "$node_b_ipv6" || return 1
    run_ip_capture caddy_vip_neigh_after -6 neigh show to "$caddy_vip_ipv6" || return 1

    action26a_classification=$(classify_result) || return 1
    printf '%s_observed_classification=%s\n' "$prefix" "$action26a_classification"
    check classification_allowed classification_allowed "$action26a_classification" || return 1
    printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
    printf '%s_endpoint_count=3\n' "$prefix"
    printf '%s_node_ssh=false\n' "$prefix"
    printf '%s_persistent_mutation=false\n' "$prefix"
    printf '%s_diagnostic_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-checks) expected_checks ;;
    '') run_action ;;
    *) exit 64 ;;
esac
