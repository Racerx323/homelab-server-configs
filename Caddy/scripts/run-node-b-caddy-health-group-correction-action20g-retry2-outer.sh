#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20g_retry2_outer
readonly previous_outer_sha256=b22d7f7332215f4b0021759bb56cf4b6bb3cb8cdec4386b3330530a53786702b
readonly regression_sha256=5d112b404b723967c228ab1beb0964ec0dddc5aa0908b737c39fe5754b61fd1c
readonly maximum_bytes=16777216
readonly maximum_lines=65536

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly previous_outer=$script_directory/run-node-b-caddy-health-group-correction-action20g-retry-outer.sh
readonly regression=$caddy_root/tests/action20g-retry2-source-root-boundary-regression.sh
export CADDY_ACTION20G_SOURCE_ROOT=$caddy_root
readonly CADDY_ACTION20G_SOURCE_ROOT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
            return 0
            ;;
        *) return 1 ;;
    esac
}
require_hash() {
    local action20g_retry2_expected_hash=$1
    local action20g_retry2_path=$2

    [[ -f "$action20g_retry2_path" && ! -L "$action20g_retry2_path" ]] || return 1
    [[ "$(file_hash "$action20g_retry2_path")" = "$action20g_retry2_expected_hash" ]]
}
source_root_value_exact() {
    [[ "$CADDY_ACTION20G_SOURCE_ROOT" = "$caddy_root" ]]
}
source_root_export_exact() {
    /usr/bin/env | grep -Fqx "CADDY_ACTION20G_SOURCE_ROOT=$caddy_root"
}
run_gate() {
    local action20g_retry2_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20g_retry2_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20g_retry2_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory previous_outer_hash regression_hash syntax \
        collision_policy conditional_policy output_evidence_policy \
        multifile_grep_policy source_root_value source_root_export regression
}
run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate previous_outer_hash require_hash "$previous_outer_sha256" "$previous_outer" || return 1
    run_gate regression_hash require_hash "$regression_sha256" "$regression" || return 1
    run_gate syntax /bin/bash -n "$regression" "$0" || return 1
    run_gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$regression" "$0" || return 1
    run_gate conditional_policy /bin/bash \
        "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate output_evidence_policy /bin/bash \
        "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    run_gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" \
        --check "$regression" "$0" || return 1
    run_gate source_root_value source_root_value_exact || return 1
    run_gate source_root_export source_root_export_exact || return 1
    run_gate regression /bin/bash "$regression" || return 1
}
safe_stream() {
    local action20g_retry2_stream=$1

    [[ "$(wc -c <"$action20g_retry2_stream")" -le "$maximum_bytes" ]] || return 1
    [[ "$(line_count "$action20g_retry2_stream")" -le "$maximum_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20g_retry2_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20g_retry2_stream"
}
emit_stream() {
    local action20g_retry2_stream_label=$1
    local action20g_retry2_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20g_retry2_stream_label" \
        "$(wc -c <"$action20g_retry2_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20g_retry2_stream_label" \
        "$(line_count "$action20g_retry2_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20g_retry2_stream_label" \
        "$(file_hash "$action20g_retry2_stream_path")"
    if safe_stream "$action20g_retry2_stream_path"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20g_retry2_stream_label"
        if [[ -s "$action20g_retry2_stream_path" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action20g_retry2_stream_label"
            cat "$action20g_retry2_stream_path"
            printf '%s_%s_end\n' "$prefix" "$action20g_retry2_stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$action20g_retry2_stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20g_retry2_stream_label" >&2
    return 97
}
run_successor_capture() {
    local action20g_retry2_runner=$1
    local action20g_retry2_capture_root=$2
    local action20g_retry2_status=0

    source_root_value_exact || return 1
    source_root_export_exact || return 1
    /usr/bin/env CADDY_ACTION20G_SOURCE_ROOT="$caddy_root" /bin/bash "$action20g_retry2_runner" \
        >"$action20g_retry2_capture_root/successor.stdout" \
        2>"$action20g_retry2_capture_root/successor.stderr" || action20g_retry2_status=$?
    emit_stream successor_stdout "$action20g_retry2_capture_root/successor.stdout" || return 97
    emit_stream successor_stderr "$action20g_retry2_capture_root/successor.stderr" || return 97
    printf '%s_successor_status=%s\n' "$prefix" "$action20g_retry2_status"
    return "$action20g_retry2_status"
}
prepare_capture_root() {
    local action20g_retry2_capture_root=$1

    [[ -d "$action20g_retry2_capture_root" && ! -L "$action20g_retry2_capture_root" ]] || return 1
    : >"$action20g_retry2_capture_root/successor.stdout"
    : >"$action20g_retry2_capture_root/successor.stderr"
    chmod 0600 "$action20g_retry2_capture_root/successor.stdout" \
        "$action20g_retry2_capture_root/successor.stderr"
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        expected_local_gates
        exit 0
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates
        printf '%s_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    --production-path-test)
        [[ $# -eq 3 ]] || exit 64
        readonly test_successor=$2
        readonly test_capture_root=$3
        [[ -f "$test_successor" && ! -L "$test_successor" ]] || exit 1
        prepare_capture_root "$test_capture_root"
        run_successor_capture "$test_successor" "$test_capture_root"
        printf '%s_production_path_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test|--source-test|--contract-test|--production-path-test RUNNER CAPTURE_ROOT]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

run_local_gates
work_root=$(mktemp -d /tmp/caddy-action20g-retry2-outer.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT
prepare_capture_root "$work_root"
run_successor_capture "$previous_outer" "$work_root"
printf '%s_previous_outer_accepted=true\n' "$prefix"
printf '%s_node_b_activation_invoked=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
