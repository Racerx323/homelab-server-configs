#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20l_retry_outer_boundary
readonly builder_sha256=466bf864675f0f1033314b70ac033d636aa3e8bbc313674346565e5caaf76fb7
readonly generated_inspector_sha256=a1358c58fb2a322f828a018b1e7094160b4d4f80bd926f13b5524128b5d88171
readonly generated_outer_sha256=6a0b44d1e6b5affedb3f8d1cd4d607e8d14e41777810d87fb59a32487320c92a
readonly generated_regression_sha256=6c536a34131f2e0782b3c9bc8bebb878c24cc674f98482a9563ac1abe71c0c35
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly builder=$script_directory/build-keepalived-dbus-readiness-action20l-retry.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh

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
run_gate() {
    local action20l_retry_boundary_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20l_retry_boundary_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20l_retry_boundary_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory builder_regular builder_executable builder_hash \
        syntax shellcheck canonical_format builder_self_test
}
run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate builder_regular test -f "$builder" || return 1
    run_gate builder_executable test -x "$builder" || return 1
    run_gate builder_hash test "$(file_hash "$builder")" = "$builder_sha256" || return 1
    run_gate syntax /bin/bash -n "$builder" "$0" || return 1
    run_gate shellcheck shellcheck "$builder" "$0" || return 1
    run_gate canonical_format /bin/bash "$shfmt_canonical" --check "$builder" "$0" || return 1
    run_gate builder_self_test /bin/bash "$builder" --self-test || return 1
}
safe_stream() {
    local action20l_retry_boundary_stream=$1

    [[ "$(wc -c <"$action20l_retry_boundary_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20l_retry_boundary_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20l_retry_boundary_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20l_retry_boundary_stream"
}
emit_stream() {
    local action20l_retry_boundary_label=$1
    local action20l_retry_boundary_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20l_retry_boundary_label" \
        "$(wc -c <"$action20l_retry_boundary_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20l_retry_boundary_label" \
        "$(line_count "$action20l_retry_boundary_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20l_retry_boundary_label" \
        "$(file_hash "$action20l_retry_boundary_stream")"
    if safe_stream "$action20l_retry_boundary_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20l_retry_boundary_label"
        if [[ -s "$action20l_retry_boundary_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action20l_retry_boundary_label"
            cat "$action20l_retry_boundary_stream"
            printf '%s_%s_end\n' "$prefix" "$action20l_retry_boundary_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$action20l_retry_boundary_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20l_retry_boundary_label" >&2
    return 97
}
verify_generated() {
    local action20l_retry_boundary_root=$1
    local action20l_retry_boundary_inspector=$action20l_retry_boundary_root/scripts/inspect-keepalived-dbus-readiness-action20l-retry.sh
    local action20l_retry_boundary_outer=$action20l_retry_boundary_root/scripts/run-dual-node-keepalived-dbus-readiness-action20l-retry-generated.sh
    local action20l_retry_boundary_regression=$action20l_retry_boundary_root/tests/action20l-retry-keepalived-dbus-readiness-regression.sh

    [[ -f "$action20l_retry_boundary_inspector" && -x "$action20l_retry_boundary_inspector" ]] || return 1
    [[ -f "$action20l_retry_boundary_outer" && -x "$action20l_retry_boundary_outer" ]] || return 1
    [[ -f "$action20l_retry_boundary_regression" && -x "$action20l_retry_boundary_regression" ]] || return 1
    [[ "$(file_hash "$action20l_retry_boundary_inspector")" = "$generated_inspector_sha256" ]] || return 1
    [[ "$(file_hash "$action20l_retry_boundary_outer")" = "$generated_outer_sha256" ]] || return 1
    [[ "$(file_hash "$action20l_retry_boundary_regression")" = "$generated_regression_sha256" ]] || return 1
    /bin/bash -n "$action20l_retry_boundary_inspector" \
        "$action20l_retry_boundary_outer" "$action20l_retry_boundary_regression" || return 1
    shellcheck "$action20l_retry_boundary_inspector" \
        "$action20l_retry_boundary_outer" "$action20l_retry_boundary_regression" || return 1
    shfmt -d -i 4 -ci "$action20l_retry_boundary_inspector" \
        "$action20l_retry_boundary_outer" "$action20l_retry_boundary_regression" >/dev/null
}
run_captured() {
    local action20l_retry_boundary_capture_prefix=$1
    local action20l_retry_boundary_stdout=$2
    local action20l_retry_boundary_stderr=$3

    shift 3
    ACTION20L_RETRY_CAPTURE_STATUS=0
    "$@" >"$action20l_retry_boundary_stdout" 2>"$action20l_retry_boundary_stderr" ||
        ACTION20L_RETRY_CAPTURE_STATUS=$?
    emit_stream "${action20l_retry_boundary_capture_prefix}_stdout" \
        "$action20l_retry_boundary_stdout" || return 97
    emit_stream "${action20l_retry_boundary_capture_prefix}_stderr" \
        "$action20l_retry_boundary_stderr" || return 97
    printf '%s_%s_status=%s\n' "$prefix" "$action20l_retry_boundary_capture_prefix" \
        "$ACTION20L_RETRY_CAPTURE_STATUS"
}
run_boundary() (
    local action20l_retry_boundary_mode=${1:-live}
    local action20l_retry_boundary_work_root
    local action20l_retry_boundary_generated
    local action20l_retry_boundary_generated_outer
    local action20l_retry_boundary_generated_regression

    action20l_retry_boundary_work_root=$(mktemp -d /tmp/caddy-action20l-retry-boundary.XXXXXX) || return 1
    trap 'rm -rf -- "$action20l_retry_boundary_work_root"' EXIT
    action20l_retry_boundary_generated=$action20l_retry_boundary_work_root/generated
    install -m 0600 /dev/null "$action20l_retry_boundary_work_root/builder.stdout" || return 1
    install -m 0600 /dev/null "$action20l_retry_boundary_work_root/builder.stderr" || return 1
    install -m 0600 /dev/null "$action20l_retry_boundary_work_root/regression.stdout" || return 1
    install -m 0600 /dev/null "$action20l_retry_boundary_work_root/regression.stderr" || return 1
    install -m 0600 /dev/null "$action20l_retry_boundary_work_root/action.stdout" || return 1
    install -m 0600 /dev/null "$action20l_retry_boundary_work_root/action.stderr" || return 1
    run_captured builder "$action20l_retry_boundary_work_root/builder.stdout" \
        "$action20l_retry_boundary_work_root/builder.stderr" \
        /bin/bash "$builder" --output "$action20l_retry_boundary_generated" || return $?
    [[ "$ACTION20L_RETRY_CAPTURE_STATUS" -eq 0 ]] || return "$ACTION20L_RETRY_CAPTURE_STATUS"
    [[ ! -s "$action20l_retry_boundary_work_root/builder.stderr" ]] || return 97
    verify_generated "$action20l_retry_boundary_generated" || return 97
    action20l_retry_boundary_generated_outer=$action20l_retry_boundary_generated/scripts/run-dual-node-keepalived-dbus-readiness-action20l-retry-generated.sh
    action20l_retry_boundary_generated_regression=$action20l_retry_boundary_generated/tests/action20l-retry-keepalived-dbus-readiness-regression.sh
    run_captured regression "$action20l_retry_boundary_work_root/regression.stdout" \
        "$action20l_retry_boundary_work_root/regression.stderr" \
        /bin/bash "$action20l_retry_boundary_generated_regression" || return $?
    [[ "$ACTION20L_RETRY_CAPTURE_STATUS" -eq 0 ]] || return "$ACTION20L_RETRY_CAPTURE_STATUS"
    [[ ! -s "$action20l_retry_boundary_work_root/regression.stderr" ]] || return 97
    if [[ "$action20l_retry_boundary_mode" = self-test ]]; then
        run_captured generated_outer_self_test "$action20l_retry_boundary_work_root/action.stdout" \
            "$action20l_retry_boundary_work_root/action.stderr" \
            /bin/bash "$action20l_retry_boundary_generated_outer" --self-test || return $?
    else
        run_captured generated_outer "$action20l_retry_boundary_work_root/action.stdout" \
            "$action20l_retry_boundary_work_root/action.stderr" \
            /bin/bash "$action20l_retry_boundary_generated_outer" || return $?
    fi
    [[ "$ACTION20L_RETRY_CAPTURE_STATUS" -eq 0 ]] || return "$ACTION20L_RETRY_CAPTURE_STATUS"
    [[ ! -s "$action20l_retry_boundary_work_root/action.stderr" ]] || return 97
    printf '%s_read_only=true\n' "$prefix"
    printf '%s_dbus_deployment=false\n' "$prefix"
    printf '%s_keepalived_reload=false\n' "$prefix"
    printf '%s_service_mutation=false\n' "$prefix"
    printf '%s_vrrp_mutation=false\n' "$prefix"
    printf '%s_vip_mutation=false\n' "$prefix"
    printf '%s_persistent_live_mutations=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
)

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        expected_local_gates
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates || exit $?
        run_boundary self-test || exit $?
        printf '%s_self_test_complete=true\n' "$prefix"
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        run_local_gates || exit $?
        run_boundary live || exit $?
        ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac
