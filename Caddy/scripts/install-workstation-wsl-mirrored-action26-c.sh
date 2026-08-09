#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_26_c
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly accepted_action26b_outer=$script_directory/run-workstation-wsl-ipv6-provenance-action26-b-outer.sh
readonly accepted_action26b_outer_sha256=a97e43703862f75132b7272d43db137b6e1b65daf92505835d97d2e7deb5b6b4
readonly candidate=$caddy_root/configs/wsl/.wslconfig
readonly candidate_sha256=6dffdf2bfc174eaca2a0bfcf8fe224929fd1006fbb48e3ccf34d642d234ab8a7
readonly target=${CADDY_ACTION26C_TARGET:-/mnt/c/Users/aaron/.wslconfig}
readonly backup_root=${CADDY_ACTION26C_BACKUP_ROOT:-/home/aaron/.local/state/caddy-ha/action26c-wsl-mirrored}
readonly proc_version_path=${CADDY_ACTION26C_PROC_VERSION_PATH:-/proc/version}
readonly wslinfo_bin=${CADDY_ACTION26C_WSLINFO_BIN:-wslinfo}
action26c_tmp=
action26c_mutation_started=false
action26c_accepted=false

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local action26c_check_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26c_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26c_check_label" >&2
    return 1
}
expected_checks() {
    printf '%s\n' \
        accepted_action26b_outer_hash candidate_regular candidate_not_symlink candidate_hash \
        candidate_content_exact target_parent_directory target_parent_writable target_absent \
        backup_absent proc_version_readable wsl_kernel wslinfo_executable current_mode_nat \
        backup_created backup_mode backup_manifest_regular backup_manifest_mode \
        backup_manifest_action backup_manifest_baseline backup_manifest_candidate_hash \
        target_installed target_regular target_not_symlink target_hash target_content_exact \
        no_shutdown_invocation dns_configuration_unchanged inactive_install_complete
}
candidate_content_exact() {
    printf '[wsl2]\nnetworkingMode=mirrored\n' | cmp -s - "$candidate"
}
path_absent() {
    [[ ! -e "$1" && ! -L "$1" ]]
}
manifest_value() {
    local action26c_manifest_key=$1

    sed -n "s/^${action26c_manifest_key}=//p" "$backup_root/manifest"
}
rollback() {
    local action26c_rollback_status=0

    printf '%s_rollback_started=true\n' "$prefix" >&2
    if [[ -e "$target" || -L "$target" ]]; then
        if [[ -f "$target" && ! -L "$target" ]] &&
            [[ "$(file_hash "$target")" = "$candidate_sha256" ]]; then
            rm -f -- "$target" || action26c_rollback_status=1
        else
            action26c_rollback_status=1
        fi
    fi
    if [[ -n "$action26c_tmp" && (-e "$action26c_tmp" || -L "$action26c_tmp") ]]; then
        rm -f -- "$action26c_tmp" || action26c_rollback_status=1
    fi
    if [[ ! -e "$target" && ! -L "$target" ]]; then
        printf '%s_rollback_target_absent=true\n' "$prefix" >&2
    else
        printf '%s_rollback_target_absent=false\n' "$prefix" >&2
        action26c_rollback_status=1
    fi
    if [[ "$action26c_rollback_status" -eq 0 ]]; then
        printf '%s_rollback_complete=true\n' "$prefix" >&2
        return 0
    fi
    printf '%s_rollback_complete=false\n' "$prefix" >&2
    return 125
}
cleanup() {
    local action26c_cleanup_status=$?

    trap - EXIT INT TERM
    if [[ "$action26c_accepted" != true && "$action26c_mutation_started" = true ]]; then
        rollback || action26c_cleanup_status=125
    elif [[ -n "$action26c_tmp" && (-e "$action26c_tmp" || -L "$action26c_tmp") ]]; then
        rm -f -- "$action26c_tmp" || action26c_cleanup_status=125
    fi
    exit "$action26c_cleanup_status"
}
run_action() {
    local action26c_mode
    local action26c_target_parent

    trap cleanup EXIT INT TERM
    action26c_target_parent=$(dirname -- "$target")

    check accepted_action26b_outer_hash test "$(file_hash "$accepted_action26b_outer")" = \
        "$accepted_action26b_outer_sha256" || return 1
    check candidate_regular test -f "$candidate" || return 1
    check candidate_not_symlink test ! -L "$candidate" || return 1
    check candidate_hash test "$(file_hash "$candidate")" = "$candidate_sha256" || return 1
    check candidate_content_exact candidate_content_exact || return 1
    check target_parent_directory test -d "$action26c_target_parent" || return 1
    check target_parent_writable test -w "$action26c_target_parent" || return 1
    check target_absent path_absent "$target" || return 1
    check backup_absent path_absent "$backup_root" || return 1
    check proc_version_readable test -r "$proc_version_path" || return 1
    check wsl_kernel grep -Eqi 'microsoft|wsl' "$proc_version_path" || return 1
    check wslinfo_executable test -x "$(command -v "$wslinfo_bin")" || return 1
    action26c_mode=$($wslinfo_bin --networking-mode) || return 1
    printf '%s_observed_preinstall_networking_mode=%s\n' "$prefix" "$action26c_mode"
    check current_mode_nat test "${action26c_mode,,}" = nat || return 1

    install -d -m 0700 "$backup_root" || return 1
    check backup_created test -d "$backup_root" || return 1
    check backup_mode test "$(stat -c %a "$backup_root")" = 700 || return 1
    printf 'action=26c\nbaseline=absent\ncandidate_sha256=%s\n' "$candidate_sha256" \
        >"$backup_root/manifest" || return 1
    chmod 0600 "$backup_root/manifest" || return 1
    check backup_manifest_regular test -f "$backup_root/manifest" || return 1
    check backup_manifest_mode test "$(stat -c %a "$backup_root/manifest")" = 600 || return 1
    check backup_manifest_action test "$(manifest_value action)" = 26c || return 1
    check backup_manifest_baseline test "$(manifest_value baseline)" = absent || return 1
    check backup_manifest_candidate_hash test "$(manifest_value candidate_sha256)" = \
        "$candidate_sha256" || return 1

    action26c_tmp=$(mktemp "${target}.action26c.XXXXXX") || return 1
    cp -- "$candidate" "$action26c_tmp" || return 1
    action26c_mutation_started=true
    mv -f -- "$action26c_tmp" "$target" || return 1
    action26c_tmp=
    check target_installed test -e "$target" || return 1
    check target_regular test -f "$target" || return 1
    check target_not_symlink test ! -L "$target" || return 1
    check target_hash test "$(file_hash "$target")" = "$candidate_sha256" || return 1
    check target_content_exact cmp -s "$candidate" "$target" || return 1
    if [[ "${CADDY_ACTION26C_FORCE_POSTINSTALL_FAILURE:-false}" = true ]]; then
        return 1
    fi
    check no_shutdown_invocation test "${CADDY_ACTION26C_SHUTDOWN_INVOKED:-false}" = false || return 1
    check dns_configuration_unchanged test "${CADDY_ACTION26C_DNS_MUTATION:-false}" = false || return 1
    check inactive_install_complete test "${CADDY_ACTION26C_ACTIVATION_PERFORMED:-false}" = false || return 1
    printf '%s_wsl_shutdown=false\n' "$prefix"
    printf '%s_windows_firewall_mutation=false\n' "$prefix"
    printf '%s_dns_mutation=false\n' "$prefix"
    printf '%s_node_contact=false\n' "$prefix"
    printf '%s_activation_pending=true\n' "$prefix"
    printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
    printf '%s_acceptance=true\n' "$prefix"
    action26c_accepted=true
}

case "${1:-}" in
    --expected-checks) expected_checks ;;
    '') run_action ;;
    *) exit 64 ;;
esac
