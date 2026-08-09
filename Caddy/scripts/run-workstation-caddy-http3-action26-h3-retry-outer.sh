#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/go/bin:/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_26_h3_retry_outer
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly immutable_core=$script_directory/run-workstation-caddy-http3-action26-h3.sh
readonly immutable_validator=$script_directory/run-workstation-caddy-http3-action26-h3-outer.sh
readonly regression=$caddy_root/tests/action26-h3-retry-packet-connection-regression.sh
readonly source_root=$caddy_root/tools/http3-probe-v2
readonly immutable_core_sha256=9ba836518103e5142ee41eb12dc33bf9e20a7cfd07f580fe337a863b4192ab6a
readonly immutable_validator_sha256=94e4adc81918fdef056e720d91df1b26bce57154bd65c15b09e7b16b6d553c9a
readonly regression_sha256=24b2f0f1d34d284bb0775865d969350b7090d339d68d368b601e80ed0f7c23b0
readonly go_mod_sha256=509992ed472701cfb013f8419999e04d97103a29ffc77464cde34c74012d8cdc
readonly go_sum_sha256=9211990e6b4889fa47deae4ee7d1de254e9e53307bcc55e7e36448ac5412b882
readonly main_sha256=3a31f26d61173e3df99578e2b1df3df79f92af73bab64b7c30548a28e914f9ec
readonly main_test_sha256=faaf57f5ffe816a253b02183f2b5ff230db9d352df6506607db8b452fdef0f06
readonly maximum_stream_bytes=65536
readonly maximum_stream_lines=1024
action26_h3_retry_root=

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
    local action26_h3_retry_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action26_h3_retry_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action26_h3_retry_gate_label" >&2
    return 1
}
runtime_check() {
    local action26_h3_retry_check_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26_h3_retry_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26_h3_retry_check_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' working_directory immutable_core_hash immutable_validator_hash \
        regression_hash go_mod_hash go_sum_hash main_hash main_test_hash go_test syntax \
        shellcheck canonical_format collision_policy conditional_policy output_evidence_policy \
        scalar_grep_policy portable_awk_policy regression
}
safe_stream() {
    local action26_h3_retry_stream=$1

    [[ "$(wc -c <"$action26_h3_retry_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action26_h3_retry_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action26_h3_retry_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:' \
        "$action26_h3_retry_stream"
}
emit_stream() {
    local action26_h3_retry_label=$1
    local action26_h3_retry_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action26_h3_retry_label" "$(wc -c <"$action26_h3_retry_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action26_h3_retry_label" "$(line_count "$action26_h3_retry_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action26_h3_retry_label" "$(file_hash "$action26_h3_retry_stream")"
    safe_stream "$action26_h3_retry_stream" || return 97
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action26_h3_retry_label"
    if [[ -s "$action26_h3_retry_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action26_h3_retry_label"
        cat "$action26_h3_retry_stream"
        printf '%s_%s_end\n' "$prefix" "$action26_h3_retry_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action26_h3_retry_label"
    fi
}
run_go_test() {
    local action26_h3_retry_cache=$action26_h3_retry_root/go-cache

    mkdir -m 0700 -- "$action26_h3_retry_cache" || return 1
    (
        cd -- "$source_root"
        GOCACHE=$action26_h3_retry_cache GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off \
            go test -mod=readonly ./...
    )
}
run_gates() {
    local action26_h3_retry_skip_regression=$1

    gate working_directory working_directory_approved || return 1
    gate immutable_core_hash test "$(file_hash "$immutable_core")" = "$immutable_core_sha256" || return 1
    gate immutable_validator_hash test "$(file_hash "$immutable_validator")" = \
        "$immutable_validator_sha256" || return 1
    gate regression_hash test "$(file_hash "$regression")" = "$regression_sha256" || return 1
    gate go_mod_hash test "$(file_hash "$source_root/go.mod")" = "$go_mod_sha256" || return 1
    gate go_sum_hash test "$(file_hash "$source_root/go.sum")" = "$go_sum_sha256" || return 1
    gate main_hash test "$(file_hash "$source_root/main.go")" = "$main_sha256" || return 1
    gate main_test_hash test "$(file_hash "$source_root/main_test.go")" = "$main_test_sha256" || return 1
    if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
        gate go_test test "${CADDY_VALIDATION_CONTAINER:-}" = 1 || return 1
    else
        gate go_test run_go_test || return 1
    fi
    gate syntax /bin/bash -n "$0" "$regression" || return 1
    gate shellcheck shellcheck "$0" "$regression" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check "$0" "$regression" || return 1
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$0" "$regression" || return 1
    gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate output_evidence_policy /bin/bash "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    gate scalar_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$0" "$regression" || return 1
    gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$0" "$regression" || return 1
    if [[ "$action26_h3_retry_skip_regression" = true ]]; then
        gate regression test "$action26_h3_retry_skip_regression" = true || return 1
    else
        gate regression /bin/bash "$regression" || return 1
    fi
}
cleanup() {
    local action26_h3_retry_status=$?

    trap - EXIT INT TERM
    [[ -z "$action26_h3_retry_root" ]] || rm -rf -- "$action26_h3_retry_root"
    exit "$action26_h3_retry_status"
}
run_action() {
    local action26_h3_retry_binary
    local action26_h3_retry_stdout
    local action26_h3_retry_stderr
    local action26_h3_retry_status=0

    action26_h3_retry_root=$(mktemp -d /tmp/caddy-action26-h3-retry.XXXXXX)
    trap cleanup EXIT INT TERM
    run_gates "${CADDY_ACTION26_H3_RETRY_SKIP_REGRESSION:-false}" || return 1
    action26_h3_retry_binary=${CADDY_ACTION26_H3_RETRY_TEST_BIN:-$action26_h3_retry_root/http3-probe-v2}
    if [[ -z "${CADDY_ACTION26_H3_RETRY_TEST_BIN:-}" ]]; then
        (
            cd -- "$source_root"
            GOCACHE=$action26_h3_retry_root/go-cache GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off \
                go build -mod=readonly -o "$action26_h3_retry_binary" .
        ) || return 1
    fi
    runtime_check corrected_binary_regular test -f "$action26_h3_retry_binary" || return 1
    runtime_check corrected_binary_executable test -x "$action26_h3_retry_binary" || return 1
    action26_h3_retry_stdout=$action26_h3_retry_root/core.stdout
    action26_h3_retry_stderr=$action26_h3_retry_root/core.stderr
    CADDY_ACTION26_H3_BIN=$action26_h3_retry_binary /bin/bash "$immutable_core" \
        >"$action26_h3_retry_stdout" 2>"$action26_h3_retry_stderr" || action26_h3_retry_status=$?
    emit_stream core_stdout "$action26_h3_retry_stdout" || return $?
    emit_stream core_stderr "$action26_h3_retry_stderr" || return $?
    /bin/bash "$immutable_validator" --validate-transcript "$action26_h3_retry_stdout" \
        "$action26_h3_retry_status" "$action26_h3_retry_stderr" || return 1
    printf '%s_live_protocol_probe=true\n' "$prefix"
    printf '%s_node_ssh=false\n' "$prefix"
    printf '%s_persistent_mutation=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-local-gates) expected_local_gates ;;
    --self-test)
        action26_h3_retry_root=$(mktemp -d /tmp/caddy-action26-h3-retry-selftest.XXXXXX)
        trap cleanup EXIT INT TERM
        CADDY_ACTION26_H3_RETRY_SKIP_REGRESSION=true run_gates true
        ;;
    "") run_action ;;
    *) exit 64 ;;
esac
