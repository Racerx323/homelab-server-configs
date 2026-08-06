#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry8_a
readonly diagnostic_sha256=ea1aa14bbf8721a8c4b369a7887b6cee512fbaf39197ebe40689cebfbd5c1490
readonly runner_sha256=fd829bc9c391fb5c520cc923a5149ac81938c19a1983d6ce803d9f7c25a4ebf7
readonly regression_sha256=e228d671f20d28c0a1c2900f2db1b8e12f54ccb21310d9319c3ea64193206329
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=8192
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly diagnostic="$script_directory/diagnose-node-a-caddy-managed-context-action20d-retry8-a.sh"
readonly runner="$script_directory/run-node-a-caddy-managed-context-action20d-retry8-a.sh"
readonly regression="$caddy_root/tests/action20d-retry8-a-managed-context-regression.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"
readonly conditional_policy="$caddy_root/tests/conditional-validator-errexit-policy-regression.sh"
readonly transcript_policy="$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh"
readonly output_policy="$caddy_root/tests/transaction-output-evidence-policy-regression.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
require_gate() {
    local outer_gate_label=$1

    shift
    if "$@"; then
        printf '%s_outer_gate_%s=true\n' "$prefix" "$outer_gate_label"
        return 0
    fi
    printf '%s_outer_gate_%s=false\n' "$prefix" "$outer_gate_label" >&2
    return 1
}
# Invoked indirectly through require_gate.
# shellcheck disable=SC2317
source_exact() {
    local outer_expected_hash=$1
    local outer_source_path=$2
    local outer_expected_identity

    outer_expected_identity="$(id -un):$(id -gn):755"
    [[ -f "$outer_source_path" && ! -L "$outer_source_path" && -x "$outer_source_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$outer_source_path")" = "$outer_expected_identity" ]] || return 1
    [[ "$(file_hash "$outer_source_path")" = "$outer_expected_hash" ]] || return 1
}
# Invoked indirectly through require_gate.
# shellcheck disable=SC2317
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
            ;;
        *) return 1 ;;
    esac
}
safe_stream() {
    local outer_stream_path=$1

    [[ "$(wc -c <"$outer_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$outer_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$outer_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$outer_stream_path"
}
run_local_gates() {
    require_gate diagnostic_source_exact source_exact "$diagnostic_sha256" "$diagnostic" || return 1
    require_gate runner_source_exact source_exact "$runner_sha256" "$runner" || return 1
    require_gate regression_source_exact source_exact "$regression_sha256" "$regression" || return 1
    require_gate sources_syntax /bin/bash -n "$diagnostic" "$runner" "$regression" || return 1
    require_gate sources_shellcheck shellcheck "$diagnostic" "$runner" "$regression" || return 1
    require_gate sources_canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" \
        --check "$diagnostic" "$runner" "$regression" || return 1
    require_gate collision_policy /bin/bash "$collision_checker" \
        "$diagnostic" "$runner" "$regression" || return 1
    require_gate conditional_validator_policy /bin/bash "$conditional_policy" || return 1
    require_gate transcript_contract_policy /bin/bash "$transcript_policy" || return 1
    require_gate transaction_output_evidence_policy /bin/bash "$output_policy" || return 1
    require_gate diagnostic_self_test /bin/bash "$diagnostic" --self-test || return 1
    require_gate runner_self_test /bin/bash "$runner" --self-test || return 1
    require_gate managed_context_regression /bin/bash "$regression" || return 1
    require_gate working_directory working_directory_approved || return 1
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        printf '%s\n' \
            diagnostic_source_exact runner_source_exact regression_source_exact \
            sources_syntax sources_shellcheck sources_canonical_format \
            collision_policy conditional_validator_policy \
            transcript_contract_policy transaction_output_evidence_policy \
            diagnostic_self_test runner_self_test managed_context_regression \
            working_directory
        exit 0
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates
        printf '%s_outer_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

run_local_gates
[[ -z "${CADDY_ACTION20D_RETRY8_A_SSH_BINARY:-}" ]]
work_directory=$(mktemp -d /tmp/caddy-action20d-retry8-a-outer.XXXXXX)
readonly work_directory
# shellcheck disable=SC2317
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT
readonly runner_stdout=$work_directory/runner.stdout
readonly runner_stderr=$work_directory/runner.stderr
touch "$runner_stdout" "$runner_stderr"
chmod 0600 "$runner_stdout" "$runner_stderr"
runner_status=0
/bin/bash "$runner" >"$runner_stdout" 2>"$runner_stderr" || runner_status=$?
readonly runner_status
printf '%s_runner_stdout_bytes=%s\n' "$prefix" "$(wc -c <"$runner_stdout")"
printf '%s_runner_stdout_lines=%s\n' "$prefix" "$(line_count "$runner_stdout")"
printf '%s_runner_stdout_sha256=%s\n' "$prefix" "$(file_hash "$runner_stdout")"
printf '%s_runner_stderr_bytes=%s\n' "$prefix" "$(wc -c <"$runner_stderr")"
printf '%s_runner_stderr_lines=%s\n' "$prefix" "$(line_count "$runner_stderr")"
printf '%s_runner_stderr_sha256=%s\n' "$prefix" "$(file_hash "$runner_stderr")"
if safe_stream "$runner_stdout" && safe_stream "$runner_stderr"; then
    printf '%s_outer_stream_classification=bounded_safe\n' "$prefix"
    printf '%s_runner_stdout_begin\n' "$prefix"
    cat "$runner_stdout"
    printf '%s_runner_stdout_end\n' "$prefix"
    if [[ -s "$runner_stderr" ]]; then
        printf '%s_runner_stderr_begin\n' "$prefix" >&2
        cat "$runner_stderr" >&2
        printf '%s_runner_stderr_end\n' "$prefix" >&2
    else
        printf '%s_runner_stderr_content_secured=empty\n' "$prefix"
    fi
else
    printf '%s_outer_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
printf '%s_runner_status=%s\n' "$prefix" "$runner_status"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_outer_cleanup_complete=true\n' "$prefix"
exit "$runner_status"
