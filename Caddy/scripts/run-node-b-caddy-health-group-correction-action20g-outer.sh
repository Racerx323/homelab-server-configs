#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20g_outer
readonly builder_sha256=8171bf8bf9cc881f4939c1589fbae181f95be110c56c4bee596125d1e5f86c5b
readonly baseline_sha256=56471ced5c32b305f9b678cdeb8ed09fbce1a5afe5cd6ef7c6628b63c2ec4b15
readonly candidate_installer_sha256=1961680f2591a988af5203744947455080903ce29e8317cfe678d95dffe78b6c
readonly candidate_runner_sha256=88398dccf48209f63b5765d47886970269668fc486f3573f13ebabce192146ec
readonly regression_sha256=477f2ae9dc66b253ec0044d484c8fc2edddb215efb0c62e93a4fa34da23be66c
readonly maximum_bytes=16777216
readonly maximum_lines=65536

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly builder=$script_directory/build-node-b-caddy-health-group-action20g.sh
readonly baseline=$script_directory/run-dual-node-caddy-postactivation-action20d-retry10-a-retry-outer.sh
readonly regression=${script_directory%/scripts}/tests/action20g-node-b-health-group-definition-regression.sh
export CADDY_ACTION20G_SOURCE_ROOT=${script_directory%/scripts}
readonly CADDY_ACTION20G_SOURCE_ROOT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
            ;;
        *) return 1 ;;
    esac
}
run_gate() {
    local action20g_gate_label=$1
    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20g_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20g_gate_label" >&2
    return 1
}
require_hash() { [[ "$(file_hash "$2")" = "$1" ]]; }
safe_stream() {
    [[ "$(wc -c <"$1")" -le "$maximum_bytes" ]] || return 1
    [[ "$(line_count "$1")" -le "$maximum_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$1" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' "$1"
}
emit_stream() {
    local action20g_stream_label=$1
    local action20g_stream_path=$2
    printf '%s_%s_bytes=%s\n' "$prefix" "$action20g_stream_label" "$(wc -c <"$action20g_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20g_stream_label" "$(line_count "$action20g_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20g_stream_label" "$(file_hash "$action20g_stream_path")"
    safe_stream "$action20g_stream_path" || return 97
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20g_stream_label"
    if [[ -s "$action20g_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action20g_stream_label"
        cat "$action20g_stream_path"
        printf '%s_%s_end\n' "$prefix" "$action20g_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$action20g_stream_label"
    fi
}
local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate builder_hash require_hash "$builder_sha256" "$builder" || return 1
    run_gate baseline_hash require_hash "$baseline_sha256" "$baseline" || return 1
    run_gate regression_hash require_hash "$regression_sha256" "$regression" || return 1
    run_gate syntax /bin/bash -n "$builder" "$baseline" "$regression" "$0" || return 1
    run_gate builder_self_test /bin/bash "$builder" --self-test || return 1
    run_gate regression /bin/bash "$regression" || return 1
}
run_capture() {
    local action20g_capture_label=$1
    local action20g_capture_command=$2
    local action20g_capture_root=$3
    local action20g_capture_status=0
    /bin/bash "$action20g_capture_command" >"$action20g_capture_root/$action20g_capture_label.stdout" \
        2>"$action20g_capture_root/$action20g_capture_label.stderr" || action20g_capture_status=$?
    emit_stream "${action20g_capture_label}_stdout" "$action20g_capture_root/$action20g_capture_label.stdout" || return 97
    emit_stream "${action20g_capture_label}_stderr" "$action20g_capture_root/$action20g_capture_label.stderr" || return 97
    printf '%s_%s_status=%s\n' "$prefix" "$action20g_capture_label" "$action20g_capture_status"
    return "$action20g_capture_status"
}

case "${1:-}" in
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        local_gates
        printf '%s_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

local_gates
work_root=$(mktemp -d /tmp/caddy-action20g-outer.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT
candidate_root=$work_root/candidate
install -d -m 0700 "$candidate_root"
/bin/bash "$builder" --output "$candidate_root" >"$work_root/builder.stdout" 2>"$work_root/builder.stderr"
emit_stream builder_stdout "$work_root/builder.stdout"
emit_stream builder_stderr "$work_root/builder.stderr"
candidate_installer=$candidate_root/install-node-b-caddy-health-group-action20g.sh
candidate_runner=$candidate_root/run-node-b-caddy-health-group-correction-action20g.sh
require_hash "$candidate_installer_sha256" "$candidate_installer"
require_hash "$candidate_runner_sha256" "$candidate_runner"
run_capture baseline "$baseline" "$work_root"
run_capture correction "$candidate_runner" "$work_root"
printf '%s_baseline_accepted=true\n' "$prefix"
printf '%s_correction_accepted=true\n' "$prefix"
printf '%s_node_b_activation_invoked=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
