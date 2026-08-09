#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_26_c_a
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly accepted_action26c_outer=$script_directory/run-workstation-wsl-mirrored-action26-c-outer.sh
readonly accepted_action26c_outer_sha256=2c02b10f4d8ef5dcee3a9d240d10aed33c1451a9bdd92b5677cc69cfdc685e99
readonly candidate=$caddy_root/configs/wsl/.wslconfig
readonly candidate_sha256=6dffdf2bfc174eaca2a0bfcf8fe224929fd1006fbb48e3ccf34d642d234ab8a7
readonly target=${CADDY_ACTION26CA_TARGET:-/mnt/c/Users/aaron/.wslconfig}
readonly backup_root=${CADDY_ACTION26CA_BACKUP_ROOT:-/home/aaron/.local/state/caddy-ha/action26c-wsl-mirrored}
readonly proc_version_path=${CADDY_ACTION26CA_PROC_VERSION_PATH:-/proc/version}
readonly wsl_conf_path=${CADDY_ACTION26CA_WSL_CONF_PATH:-/etc/wsl.conf}
readonly resolv_conf_path=${CADDY_ACTION26CA_RESOLV_CONF_PATH:-/etc/resolv.conf}
readonly resolv_link_target=${CADDY_ACTION26CA_RESOLV_LINK_TARGET:-/mnt/wsl/resolv.conf}
readonly accepted_wsl_conf_sha256=616b2737cc3d88d0075942849f438fb161e3bad7ccb9970580dd21434cbbda55
readonly accepted_resolv_conf_sha256=9e0e2f98735e119102ea8b675021e263fa6a226c8dc6c09b127dfebf16ca4bd5
readonly caddy_vip_ipv6=fd36:5aa8:6971:1::56
readonly maximum_capture_bytes=32768
readonly maximum_capture_lines=512
action26ca_work_root=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
check() {
    local action26ca_check_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26ca_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26ca_check_label" >&2
    return 1
}
expected_checks() {
    printf '%s\n' \
        accepted_action26c_outer_hash candidate_hash target_regular target_not_symlink \
        target_hash target_content_exact backup_directory backup_not_symlink backup_mode \
        manifest_regular manifest_not_symlink manifest_mode manifest_line_count \
        manifest_action manifest_baseline manifest_candidate_hash transaction_residue_absent \
        proc_version_readable wsl_kernel wsl_conf_regular wsl_conf_not_symlink wsl_conf_hash \
        resolv_conf_symlink resolv_link_target resolv_canonical_regular resolv_canonical_not_symlink \
        resolv_conf_hash resolv_nameserver_exact \
        resolv_search_exact wslinfo_executable wslinfo_stdout_safe wslinfo_stderr_safe \
        wslinfo_status_zero current_mode_nat route_stdout_safe route_stderr_safe \
        route_status_two route_stdout_empty route_error_exact no_shutdown no_node_contact \
        no_persistent_mutation acceptance
}
safe_capture() {
    local action26ca_capture_path=$1

    [[ "$(wc -c <"$action26ca_capture_path")" -le "$maximum_capture_bytes" ]] || return 1
    [[ "$(line_count "$action26ca_capture_path")" -le "$maximum_capture_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action26ca_capture_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:' \
        "$action26ca_capture_path"
}
emit_capture() {
    local action26ca_capture_label=$1
    local action26ca_capture_path=$2

    printf '%s_observed_%s_bytes=%s\n' "$prefix" "$action26ca_capture_label" \
        "$(wc -c <"$action26ca_capture_path")"
    printf '%s_observed_%s_lines=%s\n' "$prefix" "$action26ca_capture_label" \
        "$(line_count "$action26ca_capture_path")"
    printf '%s_observed_%s_sha256=%s\n' "$prefix" "$action26ca_capture_label" \
        "$(file_hash "$action26ca_capture_path")"
    safe_capture "$action26ca_capture_path" || return 97
    printf '%s_observed_%s_classification=bounded_safe\n' "$prefix" "$action26ca_capture_label"
    if [[ -s "$action26ca_capture_path" ]]; then
        printf '%s_observed_%s_begin\n' "$prefix" "$action26ca_capture_label"
        cat "$action26ca_capture_path"
        printf '%s_observed_%s_end\n' "$prefix" "$action26ca_capture_label"
    else
        printf '%s_observed_%s_content=empty\n' "$prefix" "$action26ca_capture_label"
    fi
}
run_capture() {
    local action26ca_run_label=$1
    shift
    local action26ca_run_stdout=$action26ca_work_root/${action26ca_run_label}.stdout
    local action26ca_run_stderr=$action26ca_work_root/${action26ca_run_label}.stderr
    local action26ca_run_status=0

    "$@" >"$action26ca_run_stdout" 2>"$action26ca_run_stderr" || action26ca_run_status=$?
    printf '%s\n' "$action26ca_run_status" >"$action26ca_work_root/${action26ca_run_label}.status"
    printf '%s_observed_%s_status=%s\n' "$prefix" "$action26ca_run_label" "$action26ca_run_status"
    emit_capture "${action26ca_run_label}_stdout" "$action26ca_run_stdout" || return $?
    emit_capture "${action26ca_run_label}_stderr" "$action26ca_run_stderr" || return $?
    check "${action26ca_run_label}_stdout_safe" safe_capture "$action26ca_run_stdout" || return 1
    check "${action26ca_run_label}_stderr_safe" safe_capture "$action26ca_run_stderr" || return 1
}
manifest_value() {
    local action26ca_manifest_key=$1

    sed -n "s/^${action26ca_manifest_key}=//p" "$backup_root/manifest"
}
transaction_residue_absent() {
    local action26ca_target_parent
    local action26ca_target_name

    action26ca_target_parent=$(dirname -- "$target") || return 1
    action26ca_target_name=$(basename -- "$target") || return 1
    ! find "$action26ca_target_parent" -maxdepth 1 \
        \( -name "${action26ca_target_name}.action26c.*" -o -name '.wslconfig.action26c.*' \) \
        -print -quit | grep -q .
}
cleanup() {
    local action26ca_cleanup_status=$?

    trap - EXIT INT TERM
    [[ -z "$action26ca_work_root" ]] || rm -rf -- "$action26ca_work_root"
    exit "$action26ca_cleanup_status"
}
run_action() {
    local action26ca_ip=${CADDY_ACTION26CA_IP_BIN:-ip}
    local action26ca_wslinfo=${CADDY_ACTION26CA_WSLINFO_BIN:-wslinfo}
    local action26ca_mode

    action26ca_work_root=$(mktemp -d /tmp/caddy-action26-c-a.XXXXXX)
    trap cleanup EXIT INT TERM
    check accepted_action26c_outer_hash test "$(file_hash "$accepted_action26c_outer")" = \
        "$accepted_action26c_outer_sha256" || return 1
    check candidate_hash test "$(file_hash "$candidate")" = "$candidate_sha256" || return 1
    check target_regular test -f "$target" || return 1
    check target_not_symlink test ! -L "$target" || return 1
    check target_hash test "$(file_hash "$target")" = "$candidate_sha256" || return 1
    check target_content_exact cmp -s "$candidate" "$target" || return 1
    check backup_directory test -d "$backup_root" || return 1
    check backup_not_symlink test ! -L "$backup_root" || return 1
    check backup_mode test "$(stat -c %a "$backup_root")" = 700 || return 1
    check manifest_regular test -f "$backup_root/manifest" || return 1
    check manifest_not_symlink test ! -L "$backup_root/manifest" || return 1
    check manifest_mode test "$(stat -c %a "$backup_root/manifest")" = 600 || return 1
    check manifest_line_count test "$(line_count "$backup_root/manifest")" -eq 3 || return 1
    check manifest_action test "$(manifest_value action)" = 26c || return 1
    check manifest_baseline test "$(manifest_value baseline)" = absent || return 1
    check manifest_candidate_hash test "$(manifest_value candidate_sha256)" = \
        "$candidate_sha256" || return 1
    check transaction_residue_absent transaction_residue_absent || return 1
    check proc_version_readable test -r "$proc_version_path" || return 1
    check wsl_kernel grep -Eqi 'microsoft|wsl' "$proc_version_path" || return 1
    check wsl_conf_regular test -f "$wsl_conf_path" || return 1
    check wsl_conf_not_symlink test ! -L "$wsl_conf_path" || return 1
    check wsl_conf_hash test "$(file_hash "$wsl_conf_path")" = "$accepted_wsl_conf_sha256" || return 1
    check resolv_conf_symlink test -L "$resolv_conf_path" || return 1
    check resolv_link_target test "$(readlink "$resolv_conf_path")" = "$resolv_link_target" || return 1
    check resolv_canonical_regular test -f "$(readlink -f "$resolv_conf_path")" || return 1
    check resolv_canonical_not_symlink test ! -L "$(readlink -f "$resolv_conf_path")" || return 1
    check resolv_conf_hash test "$(file_hash "$resolv_conf_path")" = \
        "$accepted_resolv_conf_sha256" || return 1
    check resolv_nameserver_exact grep -Fqx 'nameserver 10.255.255.254' "$resolv_conf_path" || return 1
    check resolv_search_exact grep -Fqx 'search local.theama.co' "$resolv_conf_path" || return 1
    check wslinfo_executable test -x "$(command -v "$action26ca_wslinfo")" || return 1
    run_capture wslinfo "$action26ca_wslinfo" --networking-mode || return 1
    check wslinfo_status_zero test "$(<"$action26ca_work_root/wslinfo.status")" -eq 0 || return 1
    action26ca_mode=$(tr -d '[:space:]' <"$action26ca_work_root/wslinfo.stdout") || return 1
    printf '%s_observed_networking_mode=%s\n' "$prefix" "$action26ca_mode"
    check current_mode_nat test "${action26ca_mode,,}" = nat || return 1
    run_capture route "$action26ca_ip" -6 route get "$caddy_vip_ipv6" || return 1
    check route_status_two test "$(<"$action26ca_work_root/route.status")" -eq 2 || return 1
    check route_stdout_empty test ! -s "$action26ca_work_root/route.stdout" || return 1
    check route_error_exact grep -Fqx 'RTNETLINK answers: Network is unreachable' \
        "$action26ca_work_root/route.stderr" || return 1
    check no_shutdown test "${CADDY_ACTION26CA_SHUTDOWN_INVOKED:-false}" = false || return 1
    check no_node_contact test "${CADDY_ACTION26CA_NODE_CONTACT:-false}" = false || return 1
    check no_persistent_mutation test "${CADDY_ACTION26CA_PERSISTENT_MUTATION:-false}" = false || return 1
    check acceptance true || return 1
    printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
    printf '%s_wsl_shutdown=false\n' "$prefix"
    printf '%s_node_contact=false\n' "$prefix"
    printf '%s_persistent_mutation=false\n' "$prefix"
    printf '%s_acceptance=true\n' "$prefix"
}

case "${1:-}" in
    --expected-checks) expected_checks ;;
    '') run_action ;;
    *) exit 64 ;;
esac
