#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28d_outer
readonly builder_sha256=5f7cf9afe81b142ecab17f4fc07570f62cf63a535c710ecf59f443d819d92f4f
readonly regression_sha256=038f5a26ee825f2068c1aa2ede798211dc11b438fdff0a0e220d93b33b1a03a8
readonly generated_driver_sha256=be998f395d430bfc537227cd5ebc45a7fe60b60a3b7653189e0ee839aeee6d58
readonly generated_inspector_sha256=4e4b88ab315a7ed74c6e78350745c33b788f761372a19b8f8ca5f9c5434b8482
readonly generated_runner_sha256=df6847bac598b8cd8453809a1fdddf6e28cabcfe45352ed6ed03ffb45aa429cc
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=${script_directory%/scripts}
readonly caddy_root
readonly builder=$script_directory/build-node-a-to-node-b-release-transfer-action28d.sh
readonly regression=$caddy_root/tests/action28d-node-a-to-node-b-release-transfer-regression.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
valid_sha256() {
    [[ ${#1} -eq 64 ]] || return 1
    [[ "$1" != *[!0-9a-f]* ]]
}
require_source() {
    local action28d_outer_expected_hash=$1
    local action28d_outer_source=$2

    [[ -f "$action28d_outer_source" && ! -L "$action28d_outer_source" &&
        -x "$action28d_outer_source" ]] || return 1
    [[ "$(file_hash "$action28d_outer_source")" = "$action28d_outer_expected_hash" ]]
}
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
    local action28d_outer_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action28d_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action28d_outer_label" >&2
    return 1
}
build_successor() {
    local action28d_outer_output=$1

    /bin/bash "$builder" "$action28d_outer_output" || return 1
    [[ "$(file_hash "$action28d_outer_output/transfer-node-a-release-to-node-b-action28d.sh")" = "$generated_driver_sha256" ]] || return 1
    [[ "$(file_hash "$action28d_outer_output/inspect-node-b-incoming-release-action28d.sh")" = "$generated_inspector_sha256" ]] || return 1
    [[ "$(file_hash "$action28d_outer_output/run-node-a-to-node-b-release-transfer-action28d.sh")" = "$generated_runner_sha256" ]] || return 1
}
run_local_gates() {
    local action28d_outer_skip_regression=$1
    local action28d_outer_generated

    run_gate working_directory working_directory_approved || return 1
    run_gate builder_regular test -f "$builder" || return 1
    run_gate builder_executable test -x "$builder" || return 1
    run_gate builder_hash require_source "$builder_sha256" "$builder" || return 1
    run_gate regression_regular test -f "$regression" || return 1
    run_gate regression_executable test -x "$regression" || return 1
    run_gate regression_hash require_source "$regression_sha256" "$regression" || return 1
    run_gate syntax /bin/bash -n "$builder" "$regression" "$0" || return 1
    run_gate shellcheck shellcheck "$builder" "$regression" "$0" || return 1
    run_gate canonical_format /bin/bash "$shfmt_canonical" --check \
        "$builder" "$regression" "$0" || return 1
    run_gate collision_policy /bin/bash \
        "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$builder" "$regression" "$0" || return 1
    run_gate conditional_policy /bin/bash \
        "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate output_evidence_policy /bin/bash \
        "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    run_gate scalar_grep_policy /bin/bash \
        "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$builder" "$regression" "$0" || return 1
    run_gate portable_awk_policy /bin/bash \
        "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$builder" "$regression" "$0" || return 1
    action28d_outer_generated=$(mktemp -d /tmp/caddy-action28d-outer-build.XXXXXX) || return 1
    if build_successor "$action28d_outer_generated"; then
        rm -rf -- "$action28d_outer_generated"
        run_gate generated_successor true || return 1
    else
        rm -rf -- "$action28d_outer_generated"
        run_gate generated_successor false || return 1
    fi
    if [[ "$action28d_outer_skip_regression" = true ]]; then
        run_gate regression test "$action28d_outer_skip_regression" = true || return 1
    else
        run_gate regression /bin/bash "$regression" || return 1
    fi
}
safe_stream() {
    local action28d_outer_stream=$1

    [[ "$(wc -c <"$action28d_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28d_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28d_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action28d_outer_stream"
}
emit_stream() {
    local action28d_outer_label=$1
    local action28d_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action28d_outer_label" \
        "$(wc -c <"$action28d_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action28d_outer_label" \
        "$(line_count "$action28d_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action28d_outer_label" \
        "$(file_hash "$action28d_outer_stream")"
    if safe_stream "$action28d_outer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action28d_outer_label"
        if [[ -s "$action28d_outer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action28d_outer_label"
            cat "$action28d_outer_stream"
            printf '%s_%s_end\n' "$prefix" "$action28d_outer_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$action28d_outer_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action28d_outer_label" >&2
    return 97
}
require_one() {
    local action28d_outer_line=$1
    local action28d_outer_transcript=$2

    [[ "$(grep -Fxc "$action28d_outer_line" "$action28d_outer_transcript" || true)" -eq 1 ]]
}
validate_assert() {
    local action28d_outer_label=$1

    shift
    if "$@"; then
        printf '%s_validation_%s=true\n' "$prefix" "$action28d_outer_label"
        return 0
    fi
    printf '%s_validation_%s=false\n' "$prefix" "$action28d_outer_label" >&2
    return 1
}
validate_success() {
    local action28d_outer_stdout=$1
    local action28d_outer_stderr=$2
    local action28d_outer_status=$3
    local action28d_outer_revision
    local action28d_outer_parent
    local action28d_outer_manifest

    action28d_outer_revision=$(sed -n 's/^action_28d_value_revision=//p' "$action28d_outer_stdout") || return 1
    action28d_outer_parent=$(sed -n 's/^action_28d_value_parent_revision=//p' "$action28d_outer_stdout") || return 1
    action28d_outer_manifest=$(sed -n 's/^action_28d_value_manifest_sha256=//p' "$action28d_outer_stdout") || return 1
    # conditional-validator-explicit-failures-begin
    validate_assert status_zero test "$action28d_outer_status" -eq 0 || return 1
    validate_assert stderr_empty test ! -s "$action28d_outer_stderr" || return 1
    validate_assert revision_single test "$(printf '%s\n' "$action28d_outer_revision" | wc -l)" -eq 1 || return 1
    validate_assert revision_valid test "$(printf '%s' "$action28d_outer_revision" | grep -Ec '^[A-Za-z0-9][A-Za-z0-9._-]*$')" -eq 1 || return 1
    validate_assert parent_single test "$(printf '%s\n' "$action28d_outer_parent" | wc -l)" -eq 1 || return 1
    validate_assert parent_valid test "$(printf '%s' "$action28d_outer_parent" | grep -Ec '^[A-Za-z0-9][A-Za-z0-9._-]*$')" -eq 1 || return 1
    validate_assert manifest_single test "$(printf '%s\n' "$action28d_outer_manifest" | wc -l)" -eq 1 || return 1
    validate_assert manifest_valid valid_sha256 "$action28d_outer_manifest" || return 1
    validate_assert checks_failed_zero require_one 'action_28d_checks_failed=0' "$action28d_outer_stdout" || return 1
    validate_assert lsyncd_not_enabled require_one 'action_28d_lsyncd_enabled=false' "$action28d_outer_stdout" || return 1
    validate_assert reconciliation_not_executed require_one 'action_28d_reconciliation_executed=false' "$action28d_outer_stdout" || return 1
    validate_assert services_not_mutated require_one 'action_28d_service_mutations=false' "$action28d_outer_stdout" || return 1
    validate_assert remote_delete_not_executed require_one 'action_28d_remote_delete_executed=false' "$action28d_outer_stdout" || return 1
    validate_assert acceptance require_one 'action_28d_acceptance=true' "$action28d_outer_stdout" || return 1
    # conditional-validator-explicit-failures-end
}
cleanup() {
    local action28d_outer_status=$?

    if [[ -n "${work_root:-}" && -d "$work_root" ]]; then
        rm -rf -- "$work_root"
    fi
    exit "$action28d_outer_status"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        run_local_gates true
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --test-validate)
        [[ $# -eq 4 && "${CADDY_ACTION28D_TEST_MODE:-}" = 1 ]] || exit 64
        validate_success "$2" "$3" "$4" || exit 97
        printf '%s_test_validation_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *) exit 64 ;;
esac

run_local_gates false
work_root=$(mktemp -d /tmp/caddy-action28d-execution.XXXXXX)
readonly work_root
trap cleanup EXIT
readonly generated=$work_root/generated
readonly stdout_capture=$work_root/runner.stdout
readonly stderr_capture=$work_root/runner.stderr
mkdir -m 0700 "$generated"
build_successor "$generated"
: >"$stdout_capture"
: >"$stderr_capture"
runner_status=0
CADDY_ACTION28D_CADDY_ROOT="$caddy_root" \
    /bin/bash "$generated/run-node-a-to-node-b-release-transfer-action28d.sh" \
    >"$stdout_capture" 2>"$stderr_capture" || runner_status=$?
readonly runner_status
emit_stream runner_stdout "$stdout_capture" || exit $?
emit_stream runner_stderr "$stderr_capture" || exit $?
validate_success "$stdout_capture" "$stderr_capture" "$runner_status" || exit 97
printf '%s_action_28c_rerun=false\n' "$prefix"
printf '%s_node_a_contacted=true\n' "$prefix"
printf '%s_node_b_contacted=true\n' "$prefix"
printf '%s_lsyncd_enabled=false\n' "$prefix"
printf '%s_reconciliation_executed=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
