#!/usr/bin/env bash
# shellcheck disable=SC2317

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20h_retry2_outer
readonly previous_outer_sha256=e72b77ba02bdf7e0ae868e59bb695028419a4253ba777b0c1b66a0d6f29160ff
readonly builder_sha256=272c45dff2975f3b6f0fbbcae39b5054fd25ec4302c73f2213d7cda44094787d
readonly regression_sha256=1b281b216fe18355899556268de04336b71c498929522368995e88ad35c85313
readonly generated_candidate_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly generated_stager_sha256=41ef10df5c02a058742b2e4c2d5183cd1c35c74ec63d103d1b5ff0ed8ba52e71
readonly generated_installer_sha256=702f4ed558dccf213a0d24d1587118eabc3fe5da5c1d342a0c8ddac8a8d14dc2
readonly generated_runner_sha256=aff13c6c73cce6ce5f6067f0b10b8c33e3a20b33e1358a3fe4e7f742602cdb3a
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=32768

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly previous_outer=$script_directory/run-node-a-caddy-health-helper-action20h-retry-outer.sh
readonly builder=$script_directory/build-node-a-caddy-health-helper-action20h-retry2.sh
readonly regression=$caddy_root/tests/action20h-retry2-environment-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
            ;;
        *) return 1 ;;
    esac
}
source_exact() {
    local action20h_retry2_outer_expected_hash=$1
    local action20h_retry2_outer_source_path=$2

    [[ -f "$action20h_retry2_outer_source_path" && ! -L "$action20h_retry2_outer_source_path" ]] || return 1
    [[ "$(stat -c '%a' "$action20h_retry2_outer_source_path")" = 755 ]] || return 1
    [[ "$(file_hash "$action20h_retry2_outer_source_path")" = "$action20h_retry2_outer_expected_hash" ]]
}
gate() {
    local action20h_retry2_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20h_retry2_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20h_retry2_outer_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory previous_outer_hash builder_hash regression_hash \
        syntax shellcheck canonical_format executable_policy collision_policy \
        conditional_policy multi_file_grep_policy portable_awk_policy \
        transcript_policy output_policy builder_self_test \
        production_regression
}
safe_stream() {
    local action20h_retry2_outer_stream_path=$1

    [[ "$(wc -c <"$action20h_retry2_outer_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20h_retry2_outer_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20h_retry2_outer_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20h_retry2_outer_stream_path"
}
emit_stream() {
    local action20h_retry2_outer_stream_label=$1
    local action20h_retry2_outer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20h_retry2_outer_stream_label" \
        "$(wc -c <"$action20h_retry2_outer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20h_retry2_outer_stream_label" \
        "$(line_count "$action20h_retry2_outer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20h_retry2_outer_stream_label" \
        "$(file_hash "$action20h_retry2_outer_stream_path")"
    if ! safe_stream "$action20h_retry2_outer_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" \
            "$action20h_retry2_outer_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20h_retry2_outer_stream_label"
    if [[ -s "$action20h_retry2_outer_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action20h_retry2_outer_stream_label"
        cat "$action20h_retry2_outer_stream_path"
        printf '%s_%s_end\n' "$prefix" "$action20h_retry2_outer_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$action20h_retry2_outer_stream_label"
    fi
}
run_local_gates() {
    gate working_directory working_directory_approved || return 1
    gate previous_outer_hash source_exact "$previous_outer_sha256" "$previous_outer" || return 1
    gate builder_hash source_exact "$builder_sha256" "$builder" || return 1
    gate regression_hash source_exact "$regression_sha256" "$regression" || return 1
    gate syntax /bin/bash -n "$builder" "$regression" "$0" || return 1
    gate shellcheck shellcheck "$builder" "$regression" "$0" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$builder" "$regression" "$0" || return 1
    gate executable_policy /bin/bash \
        "$caddy_root/tests/executable-wrapper-policy-regression.sh" || return 1
    gate collision_policy /bin/bash \
        "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$builder" "$regression" "$0" || return 1
    gate conditional_policy /bin/bash \
        "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate multi_file_grep_policy /bin/bash \
        "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$builder" "$regression" "$0" || return 1
    gate portable_awk_policy /bin/bash \
        "$caddy_root/tests/portable-awk-policy-regression.sh" || return 1
    gate transcript_policy /bin/bash \
        "$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh" || return 1
    gate output_policy /bin/bash \
        "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    gate builder_self_test /bin/bash "$builder" --self-test || return 1
    gate production_regression /bin/bash "$regression" || return 1
}
verify_generated() {
    local action20h_retry2_generated_root=$1

    source_exact "$generated_candidate_sha256" \
        "$action20h_retry2_generated_root/check-caddy-vrrp-action20h.sh" || return 1
    source_exact "$generated_stager_sha256" \
        "$action20h_retry2_generated_root/stage-node-a-caddy-health-helper-action20h.sh" || return 1
    source_exact "$generated_installer_sha256" \
        "$action20h_retry2_generated_root/install-node-a-caddy-health-helper-action20h-retry2.sh" || return 1
    source_exact "$generated_runner_sha256" \
        "$action20h_retry2_generated_root/run-node-a-caddy-health-helper-action20h-retry2.sh"
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        expected_local_gates
        exit 0
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates
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

run_local_gates
work_root=$(mktemp -d /tmp/caddy-action20h-retry2-outer.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
readonly generated_root=$work_root/generated
readonly builder_stdout=$work_root/builder.stdout
readonly builder_stderr=$work_root/builder.stderr
readonly runner_stdout=$work_root/runner.stdout
readonly runner_stderr=$work_root/runner.stderr
for action20h_retry2_outer_stream in \
    "$builder_stdout" "$builder_stderr" "$runner_stdout" "$runner_stderr"; do
    : >"$action20h_retry2_outer_stream"
    chmod 0600 "$action20h_retry2_outer_stream"
done

builder_status=0
/bin/bash "$builder" --output "$generated_root" \
    >"$builder_stdout" 2>"$builder_stderr" || builder_status=$?
readonly builder_status
emit_stream builder_stdout "$builder_stdout"
emit_stream builder_stderr "$builder_stderr"
[[ "$builder_status" -eq 0 ]]
verify_generated "$generated_root"

readonly generated_runner=$generated_root/run-node-a-caddy-health-helper-action20h-retry2.sh
runner_status=0
/bin/bash "$generated_runner" >"$runner_stdout" 2>"$runner_stderr" || runner_status=$?
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
printf '%s_keepalived_reloaded=false\n' "$prefix"
printf '%s_node_b_activation=false\n' "$prefix"
printf '%s_cleanup_complete=true\n' "$prefix"
exit "$runner_status"
