#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/go/bin:/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_26_h3_outer
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly core=$script_directory/run-workstation-caddy-http3-action26-h3.sh
readonly regression=$caddy_root/tests/action26-h3-http3-evidence-regression.sh
readonly http3_source_root=$caddy_root/tools/http3-probe
readonly core_sha256=9ba836518103e5142ee41eb12dc33bf9e20a7cfd07f580fe337a863b4192ab6a
readonly regression_sha256=0228bdb586bdd811fd32ffbba1bdff6bb014890df024d1b9f8c5cf9881cf5e7f
readonly http3_go_mod_sha256=49abe4ff921b27a9fbf6dfcd2f4aa183187385454ff00a8bdf098eafb90588b3
readonly http3_go_sum_sha256=9211990e6b4889fa47deae4ee7d1de254e9e53307bcc55e7e36448ac5412b882
readonly http3_main_sha256=e4e3d9390f13e080d3de742c7e247587a07c156a0f0083b3974100950c349f75
readonly http3_test_sha256=22a1a7b52fc8d2c2da9ca6fd6e5263588a7e6e850444931571b8419a8179fdef
readonly maximum_stream_bytes=65536
readonly maximum_stream_lines=1024
action26_h3_outer_root=

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
gate() {
    local action26_h3_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action26_h3_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action26_h3_gate_label" >&2
    return 1
}
http3_go_test() {
    (
        cd -- "$http3_source_root"
        GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go test -mod=readonly ./...
    )
}
expected_local_gates() {
    printf '%s\n' working_directory core_regular core_executable core_hash regression_regular \
        regression_executable regression_hash http3_go_mod_hash http3_go_sum_hash \
        http3_main_hash http3_test_hash http3_go_test syntax shellcheck canonical_format collision_policy \
        conditional_policy output_evidence_policy scalar_grep_policy portable_awk_policy regression
}
safe_stream() {
    local action26_h3_stream=$1

    [[ "$(wc -c <"$action26_h3_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action26_h3_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action26_h3_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:' \
        "$action26_h3_stream"
}
emit_stream() {
    local action26_h3_label=$1
    local action26_h3_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action26_h3_label" "$(wc -c <"$action26_h3_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action26_h3_label" "$(line_count "$action26_h3_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action26_h3_label" "$(file_hash "$action26_h3_stream")"
    safe_stream "$action26_h3_stream" || return 97
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action26_h3_label"
    if [[ -s "$action26_h3_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action26_h3_label"
        cat "$action26_h3_stream"
        printf '%s_%s_end\n' "$prefix" "$action26_h3_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action26_h3_label"
    fi
}
run_gates() {
    local action26_h3_skip_regression=$1

    gate working_directory working_directory_approved || return 1
    gate core_regular test -f "$core" || return 1
    gate core_executable test -x "$core" || return 1
    gate core_hash test "$(file_hash "$core")" = "$core_sha256" || return 1
    gate regression_regular test -f "$regression" || return 1
    gate regression_executable test -x "$regression" || return 1
    gate regression_hash test "$(file_hash "$regression")" = "$regression_sha256" || return 1
    gate http3_go_mod_hash test "$(file_hash "$http3_source_root/go.mod")" = "$http3_go_mod_sha256" || return 1
    gate http3_go_sum_hash test "$(file_hash "$http3_source_root/go.sum")" = "$http3_go_sum_sha256" || return 1
    gate http3_main_hash test "$(file_hash "$http3_source_root/main.go")" = "$http3_main_sha256" || return 1
    gate http3_test_hash test "$(file_hash "$http3_source_root/main_test.go")" = "$http3_test_sha256" || return 1
    if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
        gate http3_go_test test "${CADDY_VALIDATION_CONTAINER:-}" = 1 || return 1
    else
        gate http3_go_test http3_go_test || return 1
    fi
    gate syntax /bin/bash -n "$core" "$regression" "$0" || return 1
    gate shellcheck shellcheck "$core" "$regression" "$0" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$core" "$regression" "$0" || return 1
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$core" "$regression" "$0" || return 1
    gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate output_evidence_policy /bin/bash "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    gate scalar_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$core" "$regression" "$0" || return 1
    gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$core" "$regression" "$0" || return 1
    if [[ "$action26_h3_skip_regression" = true ]]; then
        gate regression test "$action26_h3_skip_regression" = true || return 1
    else
        gate regression /bin/bash "$regression" || return 1
    fi
}
validate_transcript() {
    local action26_h3_stdout=$1
    local action26_h3_status=$2
    local action26_h3_stderr=$3
    local action26_h3_expected
    local action26_h3_actual

    test "$action26_h3_status" -eq 0 || return 1
    test ! -s "$action26_h3_stderr" || return 1
    action26_h3_expected=$(/bin/bash "$core" --expected-checks) || return 1
    action26_h3_actual=$(sed -n 's/^action_26_h3_check_\([^=]*\)=true$/\1/p' "$action26_h3_stdout") || return 1
    test "$action26_h3_actual" = "$action26_h3_expected" || return 1
    test "$(grep -Ec '^action_26_h3_check_.*=(true|false)$' "$action26_h3_stdout" || true)" \
        -eq "$(printf '%s\n' "$action26_h3_expected" | wc -l)" || return 1
    grep -Fqx 'action_26_h3_probe_count=2' "$action26_h3_stdout" || return 1
    grep -Fqx 'action_26_h3_http11_http2_evidence_preserved=true' "$action26_h3_stdout" || return 1
    grep -Fqx 'action_26_h3_complete=true' "$action26_h3_stdout" || return 1
}
cleanup() {
    local action26_h3_status=$?

    trap - EXIT INT TERM
    [[ -z "$action26_h3_outer_root" ]] || rm -rf -- "$action26_h3_outer_root"
    exit "$action26_h3_status"
}
run_action() {
    local action26_h3_status=0
    local action26_h3_stdout
    local action26_h3_stderr

    action26_h3_outer_root=$(mktemp -d /tmp/caddy-action26-h3-outer.XXXXXX)
    trap cleanup EXIT INT TERM
    action26_h3_stdout=$action26_h3_outer_root/core.stdout
    action26_h3_stderr=$action26_h3_outer_root/core.stderr
    run_gates "${CADDY_ACTION26_H3_SKIP_REGRESSION:-false}" || return 1
    /bin/bash "$core" >"$action26_h3_stdout" 2>"$action26_h3_stderr" || action26_h3_status=$?
    emit_stream core_stdout "$action26_h3_stdout" || return $?
    emit_stream core_stderr "$action26_h3_stderr" || return $?
    validate_transcript "$action26_h3_stdout" "$action26_h3_status" "$action26_h3_stderr" || return 1
    printf '%s_live_protocol_probe=true\n' "$prefix"
    printf '%s_node_ssh=false\n' "$prefix"
    printf '%s_read_only=true\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-local-gates) expected_local_gates ;;
    --validate-transcript) validate_transcript "${2:?}" "${3:?}" "${4:?}" ;;
    --self-test) CADDY_ACTION26_H3_SKIP_REGRESSION=true run_gates true ;;
    "") run_action ;;
    *) exit 64 ;;
esac
