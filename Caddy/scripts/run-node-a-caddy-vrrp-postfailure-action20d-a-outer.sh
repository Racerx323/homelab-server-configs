#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_a
readonly inspector_sha256=9e9f12847426c49dbcfda94bb41e90b5bfd523cdf5e0366aba68dc9237294a5b
readonly runner_sha256=b50db75f91c4bd0906dfa74e10e4ec2bfd1373925b27e5f4b1d31f6a1340119a
readonly regression_sha256=ec6c59c85bc1094b3cb2b4be827d00db08b28eff3072d02025b74880e700dc63
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector="$script_directory/inspect-node-a-caddy-vrrp-postfailure-action20d-a.sh"
readonly runner="$script_directory/run-node-a-caddy-vrrp-postfailure-action20d-a.sh"
readonly regression="$caddy_root/tests/action20d-a-node-a-caddy-vrrp-postfailure-regression.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"
readonly conditional_policy="$caddy_root/tests/conditional-validator-errexit-policy-regression.sh"
readonly transcript_policy="$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh"
readonly output_policy="$caddy_root/tests/transaction-output-evidence-policy-regression.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
require_gate() {
    local gate_label=$1

    shift
    if "$@"; then
        printf '%s_outer_gate_%s=true\n' "$prefix" "$gate_label"
        return 0
    fi
    printf '%s_outer_gate_%s=false\n' "$prefix" "$gate_label" >&2
    return 1
}
# Invoked indirectly through require_gate.
# shellcheck disable=SC2317
source_exact() {
    local expected_hash=$1
    local source_path=$2
    local expected_identity

    expected_identity="$(id -un):$(id -gn):755"
    [[ -f "$source_path" && ! -L "$source_path" && -x "$source_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$source_path")" = "$expected_identity" ]] || return 1
    [[ "$(file_hash "$source_path")" = "$expected_hash" ]]
}
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
    local inspected_path=$1

    [[ "$(wc -c <"$inspected_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$inspected_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$inspected_path"
}
emit_stream_metadata() {
    local stream_label=$1
    local stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_label" "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_label" "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_label" "$(file_hash "$stream_path")"
}
run_local_gates() {
    require_gate inspector_source_exact source_exact "$inspector_sha256" "$inspector" || return 1
    require_gate runner_source_exact source_exact "$runner_sha256" "$runner" || return 1
    require_gate regression_source_exact source_exact "$regression_sha256" "$regression" || return 1
    require_gate sources_syntax /bin/bash -n "$inspector" "$runner" "$regression" || return 1
    require_gate sources_shellcheck shellcheck "$inspector" "$runner" "$regression" || return 1
    require_gate collision_policy /bin/bash "$collision_checker" "$inspector" "$runner" "$regression" || return 1
    require_gate conditional_validator_policy /bin/bash "$conditional_policy" || return 1
    require_gate transcript_contract_policy /bin/bash "$transcript_policy" || return 1
    require_gate transaction_output_evidence_policy /bin/bash "$output_policy" || return 1
    require_gate inspector_self_test /bin/bash "$inspector" --self-test || return 1
    require_gate runner_self_test /bin/bash "$runner" --self-test || return 1
    require_gate runner_contract_test /bin/bash "$runner" --contract-test || return 1
    require_gate regression_production_path /bin/bash "$regression" || return 1
    require_gate working_directory working_directory_approved || return 1
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]]
        printf '%s\n' \
            inspector_source_exact runner_source_exact regression_source_exact \
            sources_syntax sources_shellcheck collision_policy \
            conditional_validator_policy transcript_contract_policy \
            transaction_output_evidence_policy inspector_self_test \
            runner_self_test runner_contract_test regression_production_path \
            working_directory
        exit 0
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]]
        run_local_gates
        printf '%s_outer_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test|--source-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

run_local_gates
[[ -z "${CADDY_ACTION20DA_INTERCEPTED_TEST:-}" ]]
work_directory=$(mktemp -d /tmp/caddy-action20d-a-outer.XXXXXX)
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
emit_stream_metadata runner_stdout "$runner_stdout"
emit_stream_metadata runner_stderr "$runner_stderr"
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
