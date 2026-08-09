#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_26_b
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly accepted_action26a_outer=$script_directory/run-workstation-caddy-ipv6-response-path-action26-a-outer.sh
readonly accepted_action26a_outer_sha256=5d7f2c485c8862e188708ce52eba6ac3fd31522fa9e782bc859022fb7f552f15
readonly caddy_vip_ipv6=fd36:5aa8:6971:1::56
readonly router_ipv4=10.1.0.1
readonly maximum_capture_bytes=32768
readonly maximum_capture_lines=512
readonly proc_version_path=${CADDY_ACTION26B_PROC_VERSION_PATH:-/proc/version}
readonly if_inet6_path=${CADDY_ACTION26B_IF_INET6_PATH:-/proc/net/if_inet6}
readonly wsl_conf_path=${CADDY_ACTION26B_WSL_CONF_PATH:-/etc/wsl.conf}
readonly resolv_conf_path=${CADDY_ACTION26B_RESOLV_CONF_PATH:-/etc/resolv.conf}
action26b_work_root=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
check() {
    local action26b_check_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26b_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26b_check_label" >&2
    return 1
}
expected_checks() {
    printf '%s\n' \
        accepted_action26a_outer_hash ip_executable uname_executable sysctl_executable \
        proc_version_readable if_inet6_readable resolv_conf_readable \
        uname_stdout_safe uname_stderr_safe proc_version_stdout_safe proc_version_stderr_safe \
        if_inet6_stdout_safe if_inet6_stderr_safe wsl_conf_stdout_safe wsl_conf_stderr_safe \
        resolv_conf_stdout_safe resolv_conf_stderr_safe \
        ipv4_route_stdout_safe ipv4_route_stderr_safe interface_present interface_safe \
        ipv6_addr_stdout_safe ipv6_addr_stderr_safe ipv6_routes_stdout_safe ipv6_routes_stderr_safe \
        ipv6_rules_stdout_safe ipv6_rules_stderr_safe vip_route_stdout_safe vip_route_stderr_safe \
        all_disable_ipv6_stdout_safe all_disable_ipv6_stderr_safe \
        interface_disable_ipv6_stdout_safe interface_disable_ipv6_stderr_safe \
        interface_accept_ra_stdout_safe interface_accept_ra_stderr_safe \
        all_forwarding_stdout_safe all_forwarding_stderr_safe \
        wslinfo_stdout_safe wslinfo_stderr_safe classification_allowed
}
safe_capture() {
    local action26b_capture_path=$1

    [[ "$(wc -c <"$action26b_capture_path")" -le "$maximum_capture_bytes" ]] || return 1
    [[ "$(line_count "$action26b_capture_path")" -le "$maximum_capture_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action26b_capture_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:' \
        "$action26b_capture_path"
}
emit_capture() {
    local action26b_capture_label=$1
    local action26b_capture_path=$2

    printf '%s_observed_%s_bytes=%s\n' "$prefix" "$action26b_capture_label" \
        "$(wc -c <"$action26b_capture_path")"
    printf '%s_observed_%s_lines=%s\n' "$prefix" "$action26b_capture_label" \
        "$(line_count "$action26b_capture_path")"
    printf '%s_observed_%s_sha256=%s\n' "$prefix" "$action26b_capture_label" \
        "$(file_hash "$action26b_capture_path")"
    if ! safe_capture "$action26b_capture_path"; then
        printf '%s_observed_%s_classification=unsafe_retained\n' \
            "$prefix" "$action26b_capture_label" >&2
        return 97
    fi
    printf '%s_observed_%s_classification=bounded_safe\n' "$prefix" "$action26b_capture_label"
    if [[ -s "$action26b_capture_path" ]]; then
        printf '%s_observed_%s_begin\n' "$prefix" "$action26b_capture_label"
        cat "$action26b_capture_path"
        printf '%s_observed_%s_end\n' "$prefix" "$action26b_capture_label"
    else
        printf '%s_observed_%s_content=empty\n' "$prefix" "$action26b_capture_label"
    fi
}
run_capture() {
    local action26b_run_label=$1
    shift
    local action26b_run_stdout=$action26b_work_root/${action26b_run_label}.stdout
    local action26b_run_stderr=$action26b_work_root/${action26b_run_label}.stderr
    local action26b_run_status=0

    "$@" >"$action26b_run_stdout" 2>"$action26b_run_stderr" || action26b_run_status=$?
    printf '%s\n' "$action26b_run_status" >"$action26b_work_root/${action26b_run_label}.status"
    printf '%s_observed_%s_status=%s\n' "$prefix" "$action26b_run_label" "$action26b_run_status"
    emit_capture "${action26b_run_label}_stdout" "$action26b_run_stdout" || return $?
    emit_capture "${action26b_run_label}_stderr" "$action26b_run_stderr" || return $?
    check "${action26b_run_label}_stdout_safe" safe_capture "$action26b_run_stdout" || return 1
    check "${action26b_run_label}_stderr_safe" safe_capture "$action26b_run_stderr" || return 1
}
capture_optional_file() {
    local action26b_file_label=$1
    local action26b_file_path=$2

    if [[ -f "$action26b_file_path" && -r "$action26b_file_path" ]]; then
        run_capture "$action26b_file_label" /bin/cat "$action26b_file_path"
        return
    fi
    run_capture "$action26b_file_label" /usr/bin/printf 'absent_or_unreadable\n'
}
wslinfo_capture() {
    if command -v "${CADDY_ACTION26B_WSLINFO_BIN:-wslinfo}" >/dev/null 2>&1; then
        run_capture wslinfo "${CADDY_ACTION26B_WSLINFO_BIN:-wslinfo}" --networking-mode
        return
    fi
    run_capture wslinfo /usr/bin/printf 'unavailable\n'
}
interface_name_safe() {
    [[ "$1" =~ ^[a-zA-Z0-9_.:-]+$ ]]
}
classify() {
    local action26b_interface=$1
    local action26b_all_disable
    local action26b_interface_disable
    local action26b_route_status
    local action26b_is_wsl=false
    local action26b_networking_mode

    action26b_all_disable=$(tr -d '[:space:]' <"$action26b_work_root/all_disable_ipv6.stdout") || return 1
    action26b_interface_disable=$(tr -d '[:space:]' \
        <"$action26b_work_root/interface_disable_ipv6.stdout") || return 1
    action26b_route_status=$(<"$action26b_work_root/vip_route.status") || return 1
    action26b_networking_mode=$(tr '[:upper:]' '[:lower:]' \
        <"$action26b_work_root/wslinfo.stdout" | tr -d '[:space:]') || return 1
    if grep -Eqi 'microsoft|wsl' "$action26b_work_root/proc_version.stdout"; then
        action26b_is_wsl=true
    fi
    if [[ "$action26b_all_disable" = 1 || "$action26b_interface_disable" = 1 ]]; then
        printf 'ipv6_disabled\n'
    elif [[ "$action26b_route_status" -eq 0 ]]; then
        printf 'ula_route_present\n'
    elif [[ "$action26b_is_wsl" = true && "$action26b_networking_mode" = nat ]]; then
        printf 'wsl_nat_no_ula_route\n'
    elif [[ "$action26b_is_wsl" = true && "$action26b_networking_mode" = mirrored ]]; then
        printf 'wsl_mirrored_no_ula_route\n'
    elif [[ "$action26b_is_wsl" = true ]]; then
        printf 'wsl_unknown_mode_no_ula_route\n'
    elif interface_name_safe "$action26b_interface"; then
        printf 'native_linux_no_ula_route\n'
    else
        printf 'indeterminate_ipv6_provenance\n'
    fi
}
classification_allowed() {
    case "$1" in
        ipv6_disabled | ula_route_present | wsl_nat_no_ula_route | \
            wsl_mirrored_no_ula_route | wsl_unknown_mode_no_ula_route | \
            native_linux_no_ula_route | indeterminate_ipv6_provenance) return 0 ;;
        *) return 1 ;;
    esac
}
cleanup() {
    local action26b_cleanup_status=$?

    trap - EXIT INT TERM
    [[ -z "$action26b_work_root" ]] || rm -rf -- "$action26b_work_root"
    exit "$action26b_cleanup_status"
}
run_action() {
    local action26b_interface
    local action26b_classification
    local action26b_ip=${CADDY_ACTION26B_IP_BIN:-ip}
    local action26b_uname=${CADDY_ACTION26B_UNAME_BIN:-uname}
    local action26b_sysctl=${CADDY_ACTION26B_SYSCTL_BIN:-sysctl}

    action26b_work_root=$(mktemp -d /tmp/caddy-action26-b.XXXXXX)
    trap cleanup EXIT INT TERM
    check accepted_action26a_outer_hash test "$(file_hash "$accepted_action26a_outer")" = \
        "$accepted_action26a_outer_sha256" || return 1
    check ip_executable test -x "$(command -v "$action26b_ip")" || return 1
    check uname_executable test -x "$(command -v "$action26b_uname")" || return 1
    check sysctl_executable test -x "$(command -v "$action26b_sysctl")" || return 1
    check proc_version_readable test -r "$proc_version_path" || return 1
    check if_inet6_readable test -r "$if_inet6_path" || return 1
    check resolv_conf_readable test -r "$resolv_conf_path" || return 1

    run_capture uname "$action26b_uname" -a || return 1
    run_capture proc_version /bin/cat "$proc_version_path" || return 1
    run_capture if_inet6 /bin/cat "$if_inet6_path" || return 1
    capture_optional_file wsl_conf "$wsl_conf_path" || return 1
    run_capture resolv_conf /bin/cat "$resolv_conf_path" || return 1
    run_capture ipv4_route "$action26b_ip" -4 route get "$router_ipv4" || return 1
    action26b_interface=$(awk '{ for (i=1; i<=NF; i++) if ($i == "dev") { print $(i+1); exit } }' \
        "$action26b_work_root/ipv4_route.stdout") || return 1
    printf '%s_observed_interface=%s\n' "$prefix" "$action26b_interface"
    check interface_present test -n "$action26b_interface" || return 1
    check interface_safe interface_name_safe "$action26b_interface" || return 1

    run_capture ipv6_addr "$action26b_ip" -6 addr show || return 1
    run_capture ipv6_routes "$action26b_ip" -6 route show table all || return 1
    run_capture ipv6_rules "$action26b_ip" -6 rule show || return 1
    run_capture vip_route "$action26b_ip" -6 route get "$caddy_vip_ipv6" || return 1
    run_capture all_disable_ipv6 "$action26b_sysctl" -n net.ipv6.conf.all.disable_ipv6 || return 1
    run_capture interface_disable_ipv6 "$action26b_sysctl" -n \
        "net.ipv6.conf.${action26b_interface}.disable_ipv6" || return 1
    run_capture interface_accept_ra "$action26b_sysctl" -n \
        "net.ipv6.conf.${action26b_interface}.accept_ra" || return 1
    run_capture all_forwarding "$action26b_sysctl" -n net.ipv6.conf.all.forwarding || return 1
    wslinfo_capture || return 1

    action26b_classification=$(classify "$action26b_interface") || return 1
    printf '%s_observed_classification=%s\n' "$prefix" "$action26b_classification"
    check classification_allowed classification_allowed "$action26b_classification" || return 1
    printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
    printf '%s_live_network_probe=false\n' "$prefix"
    printf '%s_node_ssh=false\n' "$prefix"
    printf '%s_persistent_mutation=false\n' "$prefix"
    printf '%s_diagnostic_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-checks) expected_checks ;;
    '') run_action ;;
    *) exit 64 ;;
esac
