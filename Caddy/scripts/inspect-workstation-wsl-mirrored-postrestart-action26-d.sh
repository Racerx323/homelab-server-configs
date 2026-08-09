#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_26_d_linux
readonly target=${CADDY_ACTION26D_TARGET:-/mnt/c/Users/aaron/.wslconfig}
readonly backup_root=${CADDY_ACTION26D_BACKUP_ROOT:-/home/aaron/.local/state/caddy-ha/action26c-wsl-mirrored}
readonly candidate_sha256=6dffdf2bfc174eaca2a0bfcf8fe224929fd1006fbb48e3ccf34d642d234ab8a7
readonly hostname=proxy.local.theama.co
readonly node_a_ipv6=fd36:5aa8:6971:1::53
readonly node_b_ipv6=fd36:5aa8:6971:1::54
readonly caddy_vip_ipv6=fd36:5aa8:6971:1::56
readonly maximum_capture_bytes=32768
readonly maximum_capture_lines=512
action26d_work_root=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
check() {
    local action26d_check_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26d_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26d_check_label" >&2
    return 1
}
safe_capture() {
    local action26d_capture_path=$1

    [[ "$(wc -c <"$action26d_capture_path")" -le "$maximum_capture_bytes" ]] || return 1
    [[ "$(line_count "$action26d_capture_path")" -le "$maximum_capture_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action26d_capture_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:' \
        "$action26d_capture_path"
}
emit_capture() {
    local action26d_capture_label=$1
    local action26d_capture_path=$2

    printf '%s_observed_%s_bytes=%s\n' "$prefix" "$action26d_capture_label" \
        "$(wc -c <"$action26d_capture_path")"
    printf '%s_observed_%s_lines=%s\n' "$prefix" "$action26d_capture_label" \
        "$(line_count "$action26d_capture_path")"
    printf '%s_observed_%s_sha256=%s\n' "$prefix" "$action26d_capture_label" \
        "$(file_hash "$action26d_capture_path")"
    safe_capture "$action26d_capture_path" || return 97
    printf '%s_observed_%s_classification=bounded_safe\n' "$prefix" "$action26d_capture_label"
    if [[ -s "$action26d_capture_path" ]]; then
        printf '%s_observed_%s_begin\n' "$prefix" "$action26d_capture_label"
        cat "$action26d_capture_path"
        printf '%s_observed_%s_end\n' "$prefix" "$action26d_capture_label"
    else
        printf '%s_observed_%s_content=empty\n' "$prefix" "$action26d_capture_label"
    fi
}
run_capture() {
    local action26d_run_label=$1
    shift
    local action26d_run_stdout=$action26d_work_root/${action26d_run_label}.stdout
    local action26d_run_stderr=$action26d_work_root/${action26d_run_label}.stderr
    local action26d_run_status=0

    "$@" >"$action26d_run_stdout" 2>"$action26d_run_stderr" || action26d_run_status=$?
    printf '%s\n' "$action26d_run_status" >"$action26d_work_root/${action26d_run_label}.status"
    printf '%s_observed_%s_status=%s\n' "$prefix" "$action26d_run_label" "$action26d_run_status"
    emit_capture "${action26d_run_label}_stdout" "$action26d_run_stdout" || return $?
    emit_capture "${action26d_run_label}_stderr" "$action26d_run_stderr" || return $?
    check "${action26d_run_label}_stdout_safe" safe_capture "$action26d_run_stdout" || return 1
    check "${action26d_run_label}_stderr_safe" safe_capture "$action26d_run_stderr" || return 1
}
value_for() {
    local action26d_value_key=$1
    local action26d_value_path=$2

    sed -n "s/^${action26d_value_key}=//p" "$action26d_value_path"
}
route_source() {
    awk '{ for (i=1; i<=NF; i++) if ($i == "src") { print $(i+1); exit } }' "$1"
}
manifest_value() {
    local action26d_manifest_key=$1

    sed -n "s/^${action26d_manifest_key}=//p" "$backup_root/manifest"
}
path_absent() {
    [[ ! -e "$1" && ! -L "$1" ]]
}
cleanup() {
    local action26d_cleanup_status=$?

    trap - EXIT INT TERM
    [[ -z "$action26d_work_root" ]] || rm -rf -- "$action26d_work_root"
    exit "$action26d_cleanup_status"
}
run_mirrored_acceptance() {
    local action26d_mode
    local action26d_route_ip
    local action26d_route_name
    local action26d_source

    check target_regular test -f "$target" || return 1
    check target_not_symlink test ! -L "$target" || return 1
    check target_hash test "$(file_hash "$target")" = "$candidate_sha256" || return 1
    check backup_manifest_regular test -f "$backup_root/manifest" || return 1
    check backup_manifest_action test "$(manifest_value action)" = 26c || return 1
    check backup_manifest_baseline test "$(manifest_value baseline)" = absent || return 1
    run_capture wslinfo "${CADDY_ACTION26D_WSLINFO_BIN:-wslinfo}" --networking-mode || return 1
    check wslinfo_status_zero test "$(<"$action26d_work_root/wslinfo.status")" -eq 0 || return 1
    action26d_mode=$(tr -d '[:space:]' <"$action26d_work_root/wslinfo.stdout") || return 1
    printf '%s_observed_networking_mode=%s\n' "$prefix" "$action26d_mode"
    check networking_mode_mirrored test "${action26d_mode,,}" = mirrored || return 1
    run_capture ipv6_addr "${CADDY_ACTION26D_IP_BIN:-ip}" -6 addr show || return 1
    check ipv6_addr_status_zero test "$(<"$action26d_work_root/ipv6_addr.status")" -eq 0 || return 1
    check ula_address_present grep -Eq 'inet6 fd36:5aa8:6971:1:[0-9a-f:]*/[0-9]+' \
        "$action26d_work_root/ipv6_addr.stdout" || return 1
    for action26d_route_name in node_a node_b caddy_vip; do
        case "$action26d_route_name" in
            node_a) action26d_route_ip=$node_a_ipv6 ;;
            node_b) action26d_route_ip=$node_b_ipv6 ;;
            caddy_vip) action26d_route_ip=$caddy_vip_ipv6 ;;
        esac
        run_capture "${action26d_route_name}_route" "${CADDY_ACTION26D_IP_BIN:-ip}" \
            -6 route get "$action26d_route_ip" || return 1
        check "${action26d_route_name}_route_status_zero" test \
            "$(<"$action26d_work_root/${action26d_route_name}_route.status")" -eq 0 || return 1
        action26d_source=$(route_source \
            "$action26d_work_root/${action26d_route_name}_route.stdout") || return 1
        printf '%s_observed_%s_route_source=%s\n' "$prefix" "$action26d_route_name" "$action26d_source"
        check "${action26d_route_name}_route_source_ula" grep -Eq \
            '^fd36:5aa8:6971:1:[0-9a-f:]+$' <<<"$action26d_source" || return 1
    done
    run_capture dns "${CADDY_ACTION26D_DIG_BIN:-dig}" +time=2 +tries=1 +short \
        "$hostname" AAAA || return 1
    check dns_status_zero test "$(<"$action26d_work_root/dns.status")" -eq 0 || return 1
    check dns_answer_count_exact test "$(wc -l <"$action26d_work_root/dns.stdout")" -eq 1 || return 1
    check dns_answer_exact grep -Fqx "$caddy_vip_ipv6" "$action26d_work_root/dns.stdout" || return 1
    run_capture https "${CADDY_ACTION26D_CURL_BIN:-curl}" --http1.1 --insecure --silent \
        --show-error --connect-timeout 3 --max-time 8 \
        --resolve "$hostname:443:[$caddy_vip_ipv6]" --output /dev/null \
        --write-out $'protocol=%{http_version}\nstatus=%{http_code}\nremote_ip=%{remote_ip}\nbody_bytes=%{size_download}\nredirects=%{num_redirects}\n' \
        "https://$hostname/" || return 1
    check https_status_zero test "$(<"$action26d_work_root/https.status")" -eq 0 || return 1
    check https_protocol_exact test "$(value_for protocol "$action26d_work_root/https.stdout")" = 1.1 || return 1
    check https_http_status_exact test "$(value_for status "$action26d_work_root/https.stdout")" = 204 || return 1
    check https_remote_ip_exact test "$(value_for remote_ip "$action26d_work_root/https.stdout")" = \
        "$caddy_vip_ipv6" || return 1
    check https_body_empty test "$(value_for body_bytes "$action26d_work_root/https.stdout")" = 0 || return 1
    check https_redirects_zero test "$(value_for redirects "$action26d_work_root/https.stdout")" = 0 || return 1
    printf '%s_rollback_mode=false\n' "$prefix"
    printf '%s_persistent_mutation=false\n' "$prefix"
    printf '%s_acceptance=true\n' "$prefix"
}
run_nat_rollback_acceptance() {
    local action26d_mode

    check rollback_target_absent path_absent "$target" || return 1
    check rollback_backup_manifest_retained test -f "$backup_root/manifest" || return 1
    run_capture rollback_wslinfo "${CADDY_ACTION26D_WSLINFO_BIN:-wslinfo}" --networking-mode || return 1
    check rollback_wslinfo_status_zero test \
        "$(<"$action26d_work_root/rollback_wslinfo.status")" -eq 0 || return 1
    action26d_mode=$(tr -d '[:space:]' <"$action26d_work_root/rollback_wslinfo.stdout") || return 1
    printf '%s_observed_networking_mode=%s\n' "$prefix" "$action26d_mode"
    check rollback_networking_mode_nat test "${action26d_mode,,}" = nat || return 1
    run_capture rollback_route "${CADDY_ACTION26D_IP_BIN:-ip}" -6 route get \
        "$caddy_vip_ipv6" || return 1
    check rollback_route_status_two test "$(<"$action26d_work_root/rollback_route.status")" -eq 2 || return 1
    check rollback_route_error_exact grep -Fqx 'RTNETLINK answers: Network is unreachable' \
        "$action26d_work_root/rollback_route.stderr" || return 1
    printf '%s_rollback_mode=true\n' "$prefix"
    printf '%s_persistent_mutation=false\n' "$prefix"
    printf '%s_rollback_acceptance=true\n' "$prefix"
}

action26d_work_root=$(mktemp -d /tmp/caddy-action26-d-linux.XXXXXX)
trap cleanup EXIT INT TERM
case "${1:-}" in
    --expect-mirrored) run_mirrored_acceptance ;;
    --expect-nat) run_nat_rollback_acceptance ;;
    *) exit 64 ;;
esac
