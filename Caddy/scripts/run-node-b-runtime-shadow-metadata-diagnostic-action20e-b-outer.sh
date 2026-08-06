#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20e_b
readonly inspector_sha256=d983cf111b54d8e62a25b55f62c5e2e74423b42fc8a2cfc1de8e4dfb95b1881a
readonly runner_sha256=466c1d14a92b41c5e77383cc929074356470eb00e4f7f109be38af068b7936c0
readonly regression_sha256=4bb993abb023805d72c7e5601cb0e8e8d5979bcf2c88f53b57db193e879099e2
readonly failed_outer_sha256=4b0f4650c8d28d2c6ed6967663a387b2c5681d54fd45e97a7c32818302d66182
readonly collision_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly conditional_sha256=68cd687916f9d8be78f50af7a410d376f457ca74ab906a8e459795de6c495455
readonly transcript_sha256=99e0040d785e70a4f2e8d1796f8c6bf29675593d1ae5d13e54d9ac2dceebe44c
readonly output_sha256=84873a1ad3ee1745fe445f179f6a002c2ccee5b147b93cc3db0d6f17d54d4441
readonly source_context_sha256=e88131df2bdcf1f4e21c85a5fb1909532874eee145681b8014ead9d8f911967c
readonly maximum_stream_bytes=4194304
readonly maximum_stream_lines=16384
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector=$script_directory/inspect-node-b-runtime-shadow-metadata-action20e-b.sh
readonly runner=$script_directory/run-node-b-runtime-shadow-metadata-diagnostic-action20e-b.sh
readonly regression=$caddy_root/tests/action20e-b-node-b-shadow-metadata-diagnostic-regression.sh
readonly failed_outer=$script_directory/run-dual-node-caddy-runtime-directories-action20e-retry-outer.sh
readonly collision=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$caddy_root/tests/conditional-validator-errexit-policy-regression.sh
readonly transcript=$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh
readonly output_policy=$caddy_root/tests/transaction-output-evidence-policy-regression.sh
readonly source_context=$caddy_root/tests/run-source-test-in-context.sh

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
    local inspected_source=$2
    local expected_identity

    expected_identity="$(id -un):$(id -gn):755"
    [[ -f "$inspected_source" && ! -L "$inspected_source" && -x "$inspected_source" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$inspected_source")" = "$expected_identity" ]] || return 1
    [[ "$(file_hash "$inspected_source")" = "$expected_hash" ]] || return 1
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
    local emitted_label=$1
    local emitted_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$emitted_label" "$(wc -c <"$emitted_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$emitted_label" "$(line_count "$emitted_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$emitted_label" "$(file_hash "$emitted_path")"
}
run_local_gates() {
    require_gate working_directory working_directory_approved || return 1
    require_gate inspector_source_exact source_exact "$inspector_sha256" "$inspector" || return 1
    require_gate runner_source_exact source_exact "$runner_sha256" "$runner" || return 1
    require_gate regression_source_exact source_exact "$regression_sha256" "$regression" || return 1
    require_gate failed_outer_immutable source_exact "$failed_outer_sha256" "$failed_outer" || return 1
    require_gate collision_source_exact source_exact "$collision_sha256" "$collision" || return 1
    require_gate conditional_source_exact source_exact "$conditional_sha256" "$conditional" || return 1
    require_gate transcript_source_exact source_exact "$transcript_sha256" "$transcript" || return 1
    require_gate output_source_exact source_exact "$output_sha256" "$output_policy" || return 1
    require_gate source_context_exact source_exact "$source_context_sha256" "$source_context" || return 1
    require_gate sources_syntax /bin/bash -n "$inspector" "$runner" "$regression" || return 1
    require_gate sources_shellcheck shellcheck "$inspector" "$runner" "$regression" || return 1
    require_gate collision_policy /bin/bash "$collision" "$inspector" "$runner" "$regression" || return 1
    require_gate conditional_policy /bin/bash "$conditional" || return 1
    require_gate transcript_policy /bin/bash "$transcript" || return 1
    require_gate output_policy /bin/bash "$output_policy" || return 1
    require_gate inspector_self_test /bin/bash "$inspector" --self-test || return 1
    require_gate runner_source_test /bin/bash "$source_context" --runner "$runner" || return 1
    require_gate runner_contract_test /bin/bash "$runner" --contract-test || return 1
    require_gate regression_production_path /bin/bash "$regression" || return 1
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        printf '%s\n' \
            working_directory inspector_source_exact runner_source_exact \
            regression_source_exact failed_outer_immutable collision_source_exact \
            conditional_source_exact transcript_source_exact output_source_exact \
            source_context_exact sources_syntax sources_shellcheck collision_policy \
            conditional_policy transcript_policy output_policy inspector_self_test \
            runner_source_test runner_contract_test regression_production_path
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
[[ -z "${CADDY_ACTION20EB_INTERCEPTED_TEST:-}" ]]
outer_root=$(mktemp -d /tmp/caddy-action20e-b-outer.XXXXXX)
readonly outer_root
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$outer_root"
}
trap cleanup EXIT
readonly runner_stdout=$outer_root/runner.stdout
readonly runner_stderr=$outer_root/runner.stderr
: >"$runner_stdout"
: >"$runner_stderr"
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
    printf '%s_protected_evidence=%s\n' "$prefix" "$outer_root" >&2
    exit 97
fi
printf '%s_runner_status=%s\n' "$prefix" "$runner_status"
rm -rf -- "$outer_root"
trap - EXIT
printf '%s_outer_cleanup_complete=true\n' "$prefix"
exit "$runner_status"
