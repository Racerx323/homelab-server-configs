#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28f_outer
readonly driver_sha256=23a36fda7fa4087026678d10305b3d61cd1d4e1193c154d1a68b3ba3c4a700aa
readonly inspector_sha256=3260a3d52884ab141f26356ebecd2699f611dac359d1f921c96a2037234bc906
readonly runner_sha256=9eebe135098792bb8a5f1bbbbfa4a7f6a1e13bf1cfc89be411b22ef4ed45b7ec
readonly regression_sha256=92d4038a236b8bff74fe4f44703a2b60d3e33f70374c53375f2acd96f2acda48
readonly expected_revision=20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63
readonly expected_parent=action16ar-retry-node-a-default-deny
readonly expected_manifest=fdc6ed955f14226ac3e1777eca37507cc8ab6ca16add3135dece9d6964e27568
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=${script_directory%/scripts}
readonly caddy_root
readonly driver=$script_directory/transfer-retained-node-a-release-action28f.sh
readonly inspector=$script_directory/inspect-node-b-incoming-release-action28f.sh
readonly runner=$script_directory/run-node-a-to-node-b-retained-release-action28f.sh
readonly regression=$caddy_root/tests/action28f-retained-release-transfer-regression.sh
readonly source_context=$caddy_root/tests/run-source-test-in-context.sh

expected_local_gates() {
    printf '%s\n' \
        working_directory source_driver source_inspector source_runner source_regression \
        driver_syntax inspector_syntax runner_syntax regression_syntax shellcheck \
        canonical_shfmt collision_policy conditional_policy multifile_grep_policy \
        portable_awk_policy remote_cwd_policy output_evidence_policy regression \
        runner_self_test runner_source_context
}

if [[ "${1:-}" == --expected-local-gates && $# -eq 1 ]]; then
    expected_local_gates
    exit 0
fi
self_test=false
if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    self_test=true
elif [[ $# -ne 0 ]]; then
    printf 'Usage: %s [--expected-local-gates|--self-test]\n' "${0##*/}" >&2
    exit 64
fi

checks_total=0
checks_passed=0
checks_failed=0
first_failure=none
record_result() {
    local action28f_outer_label=$1
    local action28f_outer_value=$2
    checks_total=$((checks_total + 1))
    if [[ "$action28f_outer_value" == true ]]; then
        printf '%s_outer_gate_%s=true\n' "$prefix" "$action28f_outer_label"
        checks_passed=$((checks_passed + 1))
        return 0
    fi
    printf '%s_outer_gate_%s=false\n' "$prefix" "$action28f_outer_label" >&2
    checks_failed=$((checks_failed + 1))
    [[ "$first_failure" != none ]] || first_failure=$action28f_outer_label
}
record_command() {
    local action28f_outer_label=$1
    shift
    if "$@" >/dev/null 2>&1; then record_result "$action28f_outer_label" true; else record_result "$action28f_outer_label" false; fi
}
file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
source_exact() {
    local action28f_outer_path=$1
    local action28f_outer_hash=$2
    [[ -f "$action28f_outer_path" && ! -L "$action28f_outer_path" && -x "$action28f_outer_path" ]] || return 1
    [[ "$(file_hash "$action28f_outer_path")" == "$action28f_outer_hash" ]]
}
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]
            ;;
        *) return 1 ;;
    esac
}
safe_stream() {
    local action28f_outer_stream=$1
    [[ "$(wc -c <"$action28f_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28f_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28f_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|DOPPLER_TOKEN' "$action28f_outer_stream"
}
emit_stream() {
    local action28f_outer_label=$1
    local action28f_outer_stream=$2
    printf '%s_%s_bytes=%s\n' "$prefix" "$action28f_outer_label" "$(wc -c <"$action28f_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action28f_outer_label" "$(line_count "$action28f_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action28f_outer_label" "$(file_hash "$action28f_outer_stream")"
    if ! safe_stream "$action28f_outer_stream"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action28f_outer_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action28f_outer_label"
    printf '%s_%s_content_begin\n' "$prefix" "$action28f_outer_label"
    sed "s/^/${prefix}_${action28f_outer_label}_content=/" "$action28f_outer_stream"
    printf '%s_%s_content_end\n' "$prefix" "$action28f_outer_label"
}

record_command working_directory working_directory_approved
record_command source_driver source_exact "$driver" "$driver_sha256"
record_command source_inspector source_exact "$inspector" "$inspector_sha256"
record_command source_runner source_exact "$runner" "$runner_sha256"
record_command source_regression source_exact "$regression" "$regression_sha256"
record_command driver_syntax /bin/bash -n "$driver"
record_command inspector_syntax /bin/bash -n "$inspector"
record_command runner_syntax /bin/bash -n "$runner"
record_command regression_syntax /bin/bash -n "$regression"
record_command shellcheck shellcheck "$driver" "$inspector" "$runner" "$regression" "$0"
record_command canonical_shfmt "$caddy_root/tests/shfmt-canonical.sh" --check "$driver" "$inspector" "$runner" "$regression" "$0"
record_command collision_policy "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" "$driver" "$inspector" "$runner" "$regression" "$0"
record_command conditional_policy "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh"
record_command multifile_grep_policy "$caddy_root/tests/multifile-grep-count-policy.sh" --check "$driver" "$inspector" "$runner" "$regression" "$0"
record_command portable_awk_policy "$caddy_root/tests/portable-awk-policy.sh" --check "$driver" "$inspector" "$runner" "$regression" "$0"
record_command remote_cwd_policy "$caddy_root/tests/remote-streamed-bash-cwd-policy.sh" --check "$runner"
record_command output_evidence_policy "$caddy_root/tests/transaction-output-evidence-policy-regression.sh"
record_command regression /bin/bash "$regression"
record_command runner_self_test env CADDY_ACTION28F_CADDY_ROOT="$caddy_root" /bin/bash "$runner" --self-test
record_command runner_source_context "$source_context" --runner "$runner"

if [[ "$checks_failed" -ne 0 ]]; then
    printf '%s_local_acceptance=false\n' "$prefix" >&2
    exit 1
fi
if [[ "$self_test" == true ]]; then
    printf '%s_self_test_complete=true\n' "$prefix"
    exit 0
fi

work_root=$(mktemp -d /tmp/caddy-action28f-outer.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT
: >"$work_root/stdout"
: >"$work_root/stderr"
chmod 0600 "$work_root/stdout" "$work_root/stderr"
runner_status=0
CADDY_ACTION28F_CADDY_ROOT=$caddy_root /bin/bash "$runner" \
    >"$work_root/stdout" 2>"$work_root/stderr" || runner_status=$?
emit_stream runner_stdout "$work_root/stdout"
emit_stream runner_stderr "$work_root/stderr"
record_command runner_status_zero test "$runner_status" -eq 0
record_command runner_stderr_empty test ! -s "$work_root/stderr"
record_command revision_exact grep -Fxq "action_28f_value_revision=$expected_revision" "$work_root/stdout"
record_command parent_exact grep -Fxq "action_28f_value_parent_revision=$expected_parent" "$work_root/stdout"
record_command manifest_exact grep -Fxq "action_28f_value_manifest_sha256=$expected_manifest" "$work_root/stdout"
record_command runner_acceptance grep -Fxq 'action_28f_acceptance=true' "$work_root/stdout"

printf '%s_checks_total=%s\n' "$prefix" "$checks_total"
printf '%s_checks_passed=%s\n' "$prefix" "$checks_passed"
printf '%s_checks_failed=%s\n' "$prefix" "$checks_failed"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_action_executed=%s\n' "$prefix" "$([[ "$runner_status" == not_run ]] && printf false || printf true)"
if [[ "$checks_failed" -ne 0 ]]; then
    printf '%s_acceptance=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_acceptance=true\n' "$prefix"
