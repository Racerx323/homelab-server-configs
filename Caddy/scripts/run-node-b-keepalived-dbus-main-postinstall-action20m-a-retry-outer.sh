#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20m_a_retry_boundary_outer
readonly builder_sha256=0722dc42584555fcc5b79db8a6ee7ca558043a85f885e698aad6b3c337798605
readonly generated_inspector_sha256=a40acf039a4be8a47a3deb786ed241baf0c305fd4f8b25c4224781646ffca1df
readonly generated_outer_sha256=aae1b12b8e7da596c549648c156fa1117095f429fe96f78871fe41ffd0455371
readonly generated_regression_sha256=93cb113f60d5b41c6bf880c50d4eff19c371800e0d6bfe42419a42e26953b763
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly builder=$script_directory/build-node-b-keepalived-dbus-main-postinstall-action20m-a-retry.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh
readonly remote_cwd_policy=$caddy_root/tests/remote-streamed-bash-cwd-policy.sh

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
    local action20ma_retry_boundary_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20ma_retry_boundary_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20ma_retry_boundary_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory builder_regular builder_executable builder_hash \
        remote_cwd_policy_regular remote_cwd_policy_executable syntax shellcheck \
        canonical_format collision_policy conditional_policy output_evidence_policy \
        multifile_grep_policy portable_awk_policy remote_cwd_policy_self_test \
        builder_self_test
}
run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate builder_regular test -f "$builder" || return 1
    run_gate builder_executable test -x "$builder" || return 1
    run_gate builder_hash test "$(file_hash "$builder")" = "$builder_sha256" || return 1
    run_gate remote_cwd_policy_regular test -f "$remote_cwd_policy" || return 1
    run_gate remote_cwd_policy_executable test -x "$remote_cwd_policy" || return 1
    run_gate syntax /bin/bash -n "$builder" "$remote_cwd_policy" "$0" || return 1
    run_gate shellcheck shellcheck "$builder" "$remote_cwd_policy" "$0" || return 1
    run_gate canonical_format /bin/bash "$shfmt_canonical" --check \
        "$builder" "$remote_cwd_policy" "$0" || return 1
    run_gate collision_policy /bin/bash \
        "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$builder" "$remote_cwd_policy" "$0" || return 1
    run_gate conditional_policy /bin/bash \
        "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate output_evidence_policy /bin/bash \
        "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    run_gate multifile_grep_policy /bin/bash \
        "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$builder" "$remote_cwd_policy" "$0" || return 1
    run_gate portable_awk_policy /bin/bash \
        "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$builder" "$remote_cwd_policy" "$0" || return 1
    run_gate remote_cwd_policy_self_test /bin/bash "$remote_cwd_policy" --self-test || return 1
    run_gate builder_self_test /bin/bash "$builder" --self-test || return 1
}
safe_stream() {
    local action20ma_retry_boundary_stream=$1

    [[ "$(wc -c <"$action20ma_retry_boundary_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20ma_retry_boundary_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20ma_retry_boundary_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20ma_retry_boundary_stream"
}
emit_stream() {
    local action20ma_retry_boundary_label=$1
    local action20ma_retry_boundary_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20ma_retry_boundary_label" \
        "$(wc -c <"$action20ma_retry_boundary_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20ma_retry_boundary_label" \
        "$(line_count "$action20ma_retry_boundary_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20ma_retry_boundary_label" \
        "$(file_hash "$action20ma_retry_boundary_stream")"
    if safe_stream "$action20ma_retry_boundary_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20ma_retry_boundary_label"
        if [[ -s "$action20ma_retry_boundary_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action20ma_retry_boundary_label"
            cat "$action20ma_retry_boundary_stream"
            printf '%s_%s_end\n' "$prefix" "$action20ma_retry_boundary_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$action20ma_retry_boundary_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20ma_retry_boundary_label" >&2
    return 97
}
verify_generated() {
    local action20ma_retry_boundary_root=$1
    local action20ma_retry_boundary_inspector=$action20ma_retry_boundary_root/scripts/inspect-node-b-keepalived-dbus-main-postinstall-action20m-a.sh
    local action20ma_retry_boundary_outer=$action20ma_retry_boundary_root/scripts/run-node-b-keepalived-dbus-main-postinstall-action20m-a-retry-generated.sh
    local action20ma_retry_boundary_regression=$action20ma_retry_boundary_root/tests/action20m-a-retry-node-b-keepalived-dbus-main-postinstall-regression.sh

    # conditional-validator-explicit-failures-begin
    [[ -f "$action20ma_retry_boundary_inspector" && -x "$action20ma_retry_boundary_inspector" ]] || return 1
    [[ -f "$action20ma_retry_boundary_outer" && -x "$action20ma_retry_boundary_outer" ]] || return 1
    [[ -f "$action20ma_retry_boundary_regression" && -x "$action20ma_retry_boundary_regression" ]] || return 1
    [[ "$(file_hash "$action20ma_retry_boundary_inspector")" = "$generated_inspector_sha256" ]] || return 1
    [[ "$(file_hash "$action20ma_retry_boundary_outer")" = "$generated_outer_sha256" ]] || return 1
    [[ "$(file_hash "$action20ma_retry_boundary_regression")" = "$generated_regression_sha256" ]] || return 1
    /bin/bash -n "$action20ma_retry_boundary_inspector" \
        "$action20ma_retry_boundary_outer" "$action20ma_retry_boundary_regression" || return 1
    shellcheck "$action20ma_retry_boundary_inspector" \
        "$action20ma_retry_boundary_outer" "$action20ma_retry_boundary_regression" || return 1
    shfmt -d -i 4 -ci "$action20ma_retry_boundary_inspector" \
        "$action20ma_retry_boundary_outer" "$action20ma_retry_boundary_regression" >/dev/null || return 1
    /bin/bash "$remote_cwd_policy" --check "$action20ma_retry_boundary_outer" || return 1
    grep -Fq "'cd / && sudo -n /bin/bash -s --'" "$action20ma_retry_boundary_outer" || return 1
    [[ "$(grep -Fc "'sudo -n /bin/bash -s'" "$action20ma_retry_boundary_outer" || true)" -eq 0 ]] || return 1
    # conditional-validator-explicit-failures-end
    return 0
}
run_captured() {
    local action20ma_retry_boundary_capture_label=$1
    local action20ma_retry_boundary_stdout=$2
    local action20ma_retry_boundary_stderr=$3

    shift 3
    ACTION20MA_RETRY_CAPTURE_STATUS=0
    "$@" >"$action20ma_retry_boundary_stdout" 2>"$action20ma_retry_boundary_stderr" ||
        ACTION20MA_RETRY_CAPTURE_STATUS=$?
    emit_stream "${action20ma_retry_boundary_capture_label}_stdout" \
        "$action20ma_retry_boundary_stdout" || return 97
    emit_stream "${action20ma_retry_boundary_capture_label}_stderr" \
        "$action20ma_retry_boundary_stderr" || return 97
    printf '%s_%s_status=%s\n' "$prefix" "$action20ma_retry_boundary_capture_label" \
        "$ACTION20MA_RETRY_CAPTURE_STATUS"
}
run_boundary() (
    local action20ma_retry_boundary_mode=${1:-live}
    local action20ma_retry_boundary_root
    local action20ma_retry_boundary_generated
    local action20ma_retry_boundary_outer
    local action20ma_retry_boundary_regression

    action20ma_retry_boundary_root=$(mktemp -d /tmp/caddy-action20m-a-retry-boundary.XXXXXX) || return 1
    trap 'rm -rf -- "$action20ma_retry_boundary_root"' EXIT
    action20ma_retry_boundary_generated=$action20ma_retry_boundary_root/generated
    for action20ma_retry_boundary_capture in builder regression action; do
        install -m 0600 /dev/null \
            "$action20ma_retry_boundary_root/${action20ma_retry_boundary_capture}.stdout" || return 1
        install -m 0600 /dev/null \
            "$action20ma_retry_boundary_root/${action20ma_retry_boundary_capture}.stderr" || return 1
    done
    run_captured builder "$action20ma_retry_boundary_root/builder.stdout" \
        "$action20ma_retry_boundary_root/builder.stderr" \
        /bin/bash "$builder" --output "$action20ma_retry_boundary_generated" || return $?
    [[ "$ACTION20MA_RETRY_CAPTURE_STATUS" -eq 0 ]] || return "$ACTION20MA_RETRY_CAPTURE_STATUS"
    [[ ! -s "$action20ma_retry_boundary_root/builder.stderr" ]] || return 97
    verify_generated "$action20ma_retry_boundary_generated" || return 97
    action20ma_retry_boundary_outer=$action20ma_retry_boundary_generated/scripts/run-node-b-keepalived-dbus-main-postinstall-action20m-a-retry-generated.sh
    action20ma_retry_boundary_regression=$action20ma_retry_boundary_generated/tests/action20m-a-retry-node-b-keepalived-dbus-main-postinstall-regression.sh
    run_captured regression "$action20ma_retry_boundary_root/regression.stdout" \
        "$action20ma_retry_boundary_root/regression.stderr" env \
        CADDY_ACTION20MA_RETRY_SOURCE_ROOT="$caddy_root" \
        /bin/bash "$action20ma_retry_boundary_regression" || return $?
    [[ "$ACTION20MA_RETRY_CAPTURE_STATUS" -eq 0 ]] || return "$ACTION20MA_RETRY_CAPTURE_STATUS"
    [[ ! -s "$action20ma_retry_boundary_root/regression.stderr" ]] || return 97
    if [[ "$action20ma_retry_boundary_mode" = self-test ]]; then
        run_captured action "$action20ma_retry_boundary_root/action.stdout" \
            "$action20ma_retry_boundary_root/action.stderr" env \
            CADDY_ACTION20MA_RETRY_SOURCE_ROOT="$caddy_root" \
            /bin/bash "$action20ma_retry_boundary_outer" --self-test || return $?
    else
        run_captured action "$action20ma_retry_boundary_root/action.stdout" \
            "$action20ma_retry_boundary_root/action.stderr" env \
            CADDY_ACTION20MA_RETRY_SOURCE_ROOT="$caddy_root" \
            /bin/bash "$action20ma_retry_boundary_outer" || return $?
    fi
    [[ "$ACTION20MA_RETRY_CAPTURE_STATUS" -eq 0 ]] || return "$ACTION20MA_RETRY_CAPTURE_STATUS"
    [[ ! -s "$action20ma_retry_boundary_root/action.stderr" ]] || return 97
    printf '%s_node_b_contacted=%s\n' "$prefix" "$([[ "$action20ma_retry_boundary_mode" = live ]] && printf true || printf false)"
    printf '%s_node_a_contacted=false\n' "$prefix"
    printf '%s_read_only=true\n' "$prefix"
    printf '%s_helper_execution=false\n' "$prefix"
    printf '%s_keepalived_reload=false\n' "$prefix"
    printf '%s_keepalived_restart=false\n' "$prefix"
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
