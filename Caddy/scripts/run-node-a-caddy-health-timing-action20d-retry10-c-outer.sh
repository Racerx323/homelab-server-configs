#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_c_outer
readonly diagnostic_sha256=6d71149eaecbb629be2064d2eeea31b7a6416276568e884633173978b0819034
readonly runner_sha256=d0ae53fe95b29f78c2a1997c3e80a94abf524e5686c2f012a677f2be0f35a751
readonly regression_sha256=e6e1ee10c674148c14e402bc571b5c0bc3f04ec261188d29e43156b97e6298a7
readonly maximum_stream_bytes=16777216
readonly maximum_stream_lines=65536
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly diagnostic=$script_directory/inspect-node-a-caddy-health-timing-action20d-retry10-c.sh
readonly runner=$script_directory/run-node-a-caddy-health-timing-action20d-retry10-c.sh
readonly regression=$caddy_root/tests/action20d-retry10-c-health-timing-regression.sh
readonly collision_policy=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh
readonly conditional_policy=$caddy_root/tests/conditional-validator-errexit-policy-regression.sh
readonly transcript_policy=$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh
readonly output_policy=$caddy_root/tests/transaction-output-evidence-policy-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
# Invoked indirectly through gate.
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
# Invoked indirectly through gate.
# shellcheck disable=SC2317
source_exact() {
    local outer_expected_hash=$1
    local outer_source=$2

    [[ -f "$outer_source" && ! -L "$outer_source" && -x "$outer_source" ]] || return 1
    [[ "$(stat -c '%a' "$outer_source")" = 755 ]] || return 1
    [[ "$(file_hash "$outer_source")" = "$outer_expected_hash" ]] || return 1
}
gate() {
    local outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$outer_gate_label" >&2
    return 1
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
emit_stream() {
    local outer_stream_label=$1
    local outer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$outer_stream_label" \
        "$(wc -c <"$outer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$outer_stream_label" \
        "$(line_count "$outer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$outer_stream_label" \
        "$(file_hash "$outer_stream_path")"
    if ! safe_stream "$outer_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$outer_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$outer_stream_label"
    if [[ -s "$outer_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$outer_stream_label"
        cat "$outer_stream_path"
        printf '%s_%s_end\n' "$prefix" "$outer_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$outer_stream_label"
    fi
}
local_gates() {
    gate working_directory working_directory_approved || return 1
    gate diagnostic_source source_exact "$diagnostic_sha256" "$diagnostic" || return 1
    gate runner_source source_exact "$runner_sha256" "$runner" || return 1
    gate regression_source source_exact "$regression_sha256" "$regression" || return 1
    gate syntax /bin/bash -n "$diagnostic" "$runner" "$regression" "$0" || return 1
    gate shellcheck shellcheck "$diagnostic" "$runner" "$regression" "$0" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$diagnostic" "$runner" "$regression" "$0" || return 1
    gate collision_policy /bin/bash "$collision_policy" \
        "$diagnostic" "$runner" "$regression" "$0" || return 1
    gate conditional_policy /bin/bash "$conditional_policy" || return 1
    gate transcript_policy /bin/bash "$transcript_policy" || return 1
    gate output_policy /bin/bash "$output_policy" || return 1
    gate diagnostic_self_test /bin/bash "$diagnostic" --self-test || return 1
    gate runner_self_test /bin/bash "$runner" --self-test || return 1
    gate production_regression /bin/bash "$regression" || return 1
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        printf '%s\n' \
            working_directory diagnostic_source runner_source regression_source \
            syntax shellcheck canonical_format collision_policy conditional_policy \
            transcript_policy output_policy diagnostic_self_test runner_self_test \
            production_regression
        exit 0
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        local_gates
        printf '%s_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

local_gates
[[ -z "${CADDY_ACTION20D_RETRY10_C_SSH_BINARY:-}" ]]
work_root=$(mktemp -d /tmp/caddy-action20d-retry10-c-outer.XXXXXX)
readonly work_root
# shellcheck disable=SC2317
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
readonly runner_stdout=$work_root/runner.stdout
readonly runner_stderr=$work_root/runner.stderr
: >"$runner_stdout"
: >"$runner_stderr"
chmod 0600 "$runner_stdout" "$runner_stderr"
runner_status=0
/bin/bash "$runner" >"$runner_stdout" 2>"$runner_stderr" || runner_status=$?
readonly runner_status
emit_stream runner_stdout "$runner_stdout" || {
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_root" >&2
    exit 97
}
emit_stream runner_stderr "$runner_stderr" || {
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_root" >&2
    exit 97
}
printf '%s_runner_status=%s\n' "$prefix" "$runner_status"
printf '%s_node_a_contacted=true\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_complete_helper_invoked=false\n' "$prefix"
printf '%s_live_mutations=false\n' "$prefix"
printf '%s_cleanup_complete=true\n' "$prefix"
exit "$runner_status"
