#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/go/bin:/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_26_retry_outer
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly adapter=$script_directory/run-workstation-caddy-protocols-action26-retry.sh
readonly immutable_validator=$script_directory/run-workstation-caddy-protocols-action26-outer.sh
readonly accepted_ipv6_outer=$script_directory/run-workstation-wsl-mirrored-postrestart-action26-e-retry-outer.sh
readonly regression=$caddy_root/tests/action26-retry-protocol-negotiation-regression.sh
readonly adapter_sha256=f167e5a8d735025e46a3f4cc213d62fc603358b004c13f9ecee364439f8fcd51
readonly immutable_validator_sha256=58edc2c10115dcd2b74e9b1b65e4afda7eaab3d6801301a698991d65ced943fc
readonly accepted_ipv6_outer_sha256=b2f313b4713c9af2c668d21130642838522d6e921fb959387d93ab50191f0270
readonly regression_sha256=2ae39beaaa08a4c135d7f7eba025185cee0b94f79c787023a1c462b36f73cd4d
readonly maximum_stream_bytes=262144
readonly maximum_stream_lines=4000
action26_retry_outer_root=

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
    local action26_retry_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action26_retry_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action26_retry_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' working_directory adapter_regular adapter_executable adapter_hash \
        validator_regular validator_executable validator_hash accepted_ipv6_outer_hash \
        regression_regular regression_executable regression_hash immutable_self_test syntax \
        shellcheck canonical_format collision_policy conditional_policy output_evidence_policy \
        scalar_grep_policy portable_awk_policy regression
}
safe_stream() {
    local action26_retry_stream=$1

    [[ "$(wc -c <"$action26_retry_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action26_retry_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action26_retry_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:' \
        "$action26_retry_stream"
}
emit_stream() {
    local action26_retry_label=$1
    local action26_retry_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action26_retry_label" "$(wc -c <"$action26_retry_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action26_retry_label" "$(line_count "$action26_retry_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action26_retry_label" "$(file_hash "$action26_retry_stream")"
    safe_stream "$action26_retry_stream" || return 97
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action26_retry_label"
    if [[ -s "$action26_retry_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action26_retry_label"
        cat "$action26_retry_stream"
        printf '%s_%s_end\n' "$prefix" "$action26_retry_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action26_retry_label"
    fi
}
run_gates() {
    local action26_retry_skip_regression=$1

    gate working_directory working_directory_approved || return 1
    gate adapter_regular test -f "$adapter" || return 1
    gate adapter_executable test -x "$adapter" || return 1
    gate adapter_hash test "$(file_hash "$adapter")" = "$adapter_sha256" || return 1
    gate validator_regular test -f "$immutable_validator" || return 1
    gate validator_executable test -x "$immutable_validator" || return 1
    gate validator_hash test "$(file_hash "$immutable_validator")" = "$immutable_validator_sha256" || return 1
    gate accepted_ipv6_outer_hash test "$(file_hash "$accepted_ipv6_outer")" = \
        "$accepted_ipv6_outer_sha256" || return 1
    gate regression_regular test -f "$regression" || return 1
    gate regression_executable test -x "$regression" || return 1
    gate regression_hash test "$(file_hash "$regression")" = "$regression_sha256" || return 1
    gate immutable_self_test env CADDY_ACTION26_CONTAINER_NO_GO_TOOLCHAIN="${CADDY_ACTION26_CONTAINER_NO_GO_TOOLCHAIN:-false}" \
        /bin/bash "$immutable_validator" --self-test || return 1
    gate syntax /bin/bash -n "$adapter" "$regression" "$0" || return 1
    gate shellcheck shellcheck "$adapter" "$regression" "$0" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$adapter" "$regression" "$0" || return 1
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$adapter" "$regression" "$0" || return 1
    gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate output_evidence_policy /bin/bash "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    gate scalar_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$adapter" "$regression" "$0" || return 1
    gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$adapter" "$regression" "$0" || return 1
    if [[ "$action26_retry_skip_regression" = true ]]; then
        gate regression test "$action26_retry_skip_regression" = true || return 1
    else
        gate regression /bin/bash "$regression" || return 1
    fi
}
normalize_transcript() {
    local action26_retry_transcript=$1
    local action26_retry_normalized=$2

    test "$(sed -n '/^action_26_/ { /^action_26_retry_/!p }' "$action26_retry_transcript" | wc -l)" \
        -eq 0 || return 1
    sed 's/^action_26_retry_/action_26_/' "$action26_retry_transcript" >"$action26_retry_normalized"
}
validate_transcript() {
    local action26_retry_transcript=$1
    local action26_retry_status=$2
    local action26_retry_stderr=$3
    local action26_retry_normalized
    local action26_retry_expected_adapter
    local action26_retry_actual_adapter
    local action26_retry_validation_status=0

    action26_retry_expected_adapter=$(/bin/bash "$adapter" --expected-checks) || return 1
    action26_retry_actual_adapter=$(sed -n 's/^action_26_retry_adapter_check_\([^=]*\)=true$/\1/p' \
        "$action26_retry_transcript") || return 1
    test "$action26_retry_actual_adapter" = "$action26_retry_expected_adapter" || return 1
    action26_retry_normalized=$(mktemp /tmp/caddy-action26-retry-normalized.XXXXXX)
    if ! normalize_transcript "$action26_retry_transcript" "$action26_retry_normalized"; then
        rm -f -- "$action26_retry_normalized"
        return 1
    fi
    /bin/bash "$immutable_validator" --validate-transcript "$action26_retry_normalized" \
        "$action26_retry_status" "$action26_retry_stderr" || action26_retry_validation_status=$?
    rm -f -- "$action26_retry_normalized"
    return "$action26_retry_validation_status"
}
cleanup() {
    local action26_retry_status=$?

    trap - EXIT INT TERM
    [[ -z "$action26_retry_outer_root" ]] || rm -rf -- "$action26_retry_outer_root"
    exit "$action26_retry_status"
}
run_action() {
    local action26_retry_status=0
    local action26_retry_stdout
    local action26_retry_stderr

    action26_retry_outer_root=$(mktemp -d /tmp/caddy-action26-retry-outer.XXXXXX)
    trap cleanup EXIT INT TERM
    action26_retry_stdout=$action26_retry_outer_root/adapter.stdout
    action26_retry_stderr=$action26_retry_outer_root/adapter.stderr
    run_gates "${CADDY_ACTION26_RETRY_SKIP_REGRESSION:-false}" || return 1
    /bin/bash "$adapter" >"$action26_retry_stdout" 2>"$action26_retry_stderr" || action26_retry_status=$?
    emit_stream adapter_stdout "$action26_retry_stdout" || return $?
    emit_stream adapter_stderr "$action26_retry_stderr" || return $?
    validate_transcript "$action26_retry_stdout" "$action26_retry_status" "$action26_retry_stderr" || return 1
    printf '%s_workstation_network_contact=true\n' "$prefix"
    printf '%s_node_ssh=false\n' "$prefix"
    printf '%s_read_only=true\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-local-gates) expected_local_gates ;;
    --validate-transcript) validate_transcript "${2:?}" "${3:?}" "${4:?}" ;;
    --self-test) CADDY_ACTION26_RETRY_SKIP_REGRESSION=true run_gates true ;;
    "") run_action ;;
    *) exit 64 ;;
esac
