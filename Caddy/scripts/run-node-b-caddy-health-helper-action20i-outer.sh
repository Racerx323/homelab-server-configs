#!/usr/bin/env bash
# shellcheck disable=SC2317

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20i_outer
readonly baseline_sha256=e354b32749698c83cfe432b1684a384117e134e52fd2341bd7c201431a1e2e4a
readonly builder_sha256=1c64a013da42f07ce2add60d66159f4d7f591b6db91a30bfb2aaa49c427ff421
readonly regression_sha256=c43edd357c26e14f8c08972652ccdaad11be77a126b2306a14be8521e684d952
readonly outer_regression_sha256=f6d980fe48e9d1df42bedb9dfcd563783f9ce3d3c402dfb02d2dec82e74f32a3
readonly generated_candidate_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly generated_stager_sha256=9596a34fb816d8e15068741875ab5ee4435d3a006fcf4812bb601ff2f6d4d295
readonly generated_installer_sha256=e4c3284a4c75ff40935c0d57b533e298e9f18fb3fece5e0626eff9f6e5784025
readonly generated_runner_sha256=326e30073aaee39ea0516195ba06eb0622f58d0f726e5b0ceb53000b17f8b04e
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=32768

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly baseline=$script_directory/run-node-b-caddy-health-group-postinstall-action20g-a-outer.sh
readonly builder=$script_directory/build-node-b-caddy-health-helper-action20i.sh
readonly regression=$caddy_root/tests/action20i-node-b-health-helper-regression.sh
readonly outer_regression=$caddy_root/tests/action20i-outer-production-path-regression.sh

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
    local action20i_outer_expected_hash=$1
    local action20i_outer_source_path=$2

    [[ -f "$action20i_outer_source_path" && ! -L "$action20i_outer_source_path" ]] || return 1
    [[ "$(stat -c '%a' "$action20i_outer_source_path")" = 755 ]] || return 1
    [[ "$(file_hash "$action20i_outer_source_path")" = "$action20i_outer_expected_hash" ]]
}
gate() {
    local action20i_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20i_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20i_outer_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory baseline_hash builder_hash regression_hash \
        outer_regression_hash syntax shellcheck canonical_format executable_policy \
        collision_policy conditional_policy multifile_grep_policy portable_awk_policy \
        transcript_policy output_policy builder_self_test production_regression \
        outer_production_regression
}
safe_stream() {
    local action20i_outer_stream_path=$1

    [[ "$(wc -c <"$action20i_outer_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20i_outer_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20i_outer_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20i_outer_stream_path"
}
emit_stream() {
    local action20i_outer_stream_label=$1
    local action20i_outer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20i_outer_stream_label" \
        "$(wc -c <"$action20i_outer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20i_outer_stream_label" \
        "$(line_count "$action20i_outer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20i_outer_stream_label" \
        "$(file_hash "$action20i_outer_stream_path")"
    if ! safe_stream "$action20i_outer_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" \
            "$action20i_outer_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20i_outer_stream_label"
    if [[ -s "$action20i_outer_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action20i_outer_stream_label"
        cat "$action20i_outer_stream_path"
        printf '%s_%s_end\n' "$prefix" "$action20i_outer_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$action20i_outer_stream_label"
    fi
}
run_local_gates() {
    gate working_directory working_directory_approved || return 1
    gate baseline_hash source_exact "$baseline_sha256" "$baseline" || return 1
    gate builder_hash source_exact "$builder_sha256" "$builder" || return 1
    gate regression_hash source_exact "$regression_sha256" "$regression" || return 1
    gate outer_regression_hash source_exact "$outer_regression_sha256" \
        "$outer_regression" || return 1
    gate syntax /bin/bash -n "$builder" "$regression" "$outer_regression" "$0" || return 1
    gate shellcheck shellcheck "$builder" "$regression" "$outer_regression" "$0" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$builder" "$regression" "$outer_regression" "$0" || return 1
    gate executable_policy /bin/bash \
        "$caddy_root/tests/executable-wrapper-policy-regression.sh" || return 1
    gate collision_policy /bin/bash \
        "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$builder" "$regression" "$outer_regression" "$0" || return 1
    gate conditional_policy /bin/bash \
        "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate multifile_grep_policy /bin/bash \
        "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$builder" "$regression" "$outer_regression" "$0" || return 1
    gate portable_awk_policy /bin/bash \
        "$caddy_root/tests/portable-awk-policy-regression.sh" || return 1
    gate transcript_policy /bin/bash \
        "$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh" || return 1
    gate output_policy /bin/bash \
        "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    gate builder_self_test /bin/bash "$builder" --self-test || return 1
    gate production_regression /bin/bash "$regression" || return 1
    gate outer_production_regression /bin/bash "$outer_regression" || return 1
}
verify_generated() {
    local action20i_outer_generated_root=$1

    source_exact "$generated_candidate_sha256" \
        "$action20i_outer_generated_root/check-caddy-vrrp-action20i.sh" || return 1
    source_exact "$generated_stager_sha256" \
        "$action20i_outer_generated_root/stage-node-b-caddy-health-helper-action20i.sh" || return 1
    source_exact "$generated_installer_sha256" \
        "$action20i_outer_generated_root/install-node-b-caddy-health-helper-action20i.sh" || return 1
    source_exact "$generated_runner_sha256" \
        "$action20i_outer_generated_root/run-node-b-caddy-health-helper-action20i.sh"
}
run_capture() {
    local action20i_outer_capture_label=$1
    local action20i_outer_capture_script=$2
    local action20i_outer_capture_root=$3
    local action20i_outer_capture_stdout=$action20i_outer_capture_root/$action20i_outer_capture_label.stdout
    local action20i_outer_capture_stderr=$action20i_outer_capture_root/$action20i_outer_capture_label.stderr

    : >"$action20i_outer_capture_stdout"
    : >"$action20i_outer_capture_stderr"
    chmod 0600 "$action20i_outer_capture_stdout" "$action20i_outer_capture_stderr"
    capture_status=0
    /bin/bash "$action20i_outer_capture_script" >"$action20i_outer_capture_stdout" \
        2>"$action20i_outer_capture_stderr" || capture_status=$?
    emit_stream "${action20i_outer_capture_label}_stdout" \
        "$action20i_outer_capture_stdout" || return 97
    emit_stream "${action20i_outer_capture_label}_stderr" \
        "$action20i_outer_capture_stderr" || return 97
    printf '%s_%s_status=%s\n' "$prefix" "$action20i_outer_capture_label" \
        "$capture_status"
}
execute_two_stage() {
    local action20i_outer_baseline_script=$1
    local action20i_outer_transaction_script=$2
    local action20i_outer_capture_root=$3

    run_capture baseline "$action20i_outer_baseline_script" \
        "$action20i_outer_capture_root" || return $?
    [[ "$capture_status" -eq 0 ]] || return "$capture_status"
    printf '%s_baseline_accepted=true\n' "$prefix"
    run_capture transaction "$action20i_outer_transaction_script" \
        "$action20i_outer_capture_root" || return $?
    return "$capture_status"
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        expected_local_gates
        exit 0
        ;;
    --production-path-test)
        [[ $# -eq 3 ]] || exit 64
        working_directory_approved
        [[ -f "$2" && ! -L "$2" ]] || exit 1
        [[ -f "$3" && ! -L "$3" ]] || exit 1
        production_test_root=$(mktemp -d /tmp/caddy-action20i-production-test.XXXXXX)
        readonly production_test_root
        trap 'rm -rf -- "$production_test_root"' EXIT INT TERM
        execute_two_stage "$2" "$3" "$production_test_root"
        exit $?
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates
        printf '%s_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--production-path-test BASELINE TRANSACTION|--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

run_local_gates
work_root=$(mktemp -d /tmp/caddy-action20i-outer.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
run_capture baseline "$baseline" "$work_root" || exit $?
[[ "$capture_status" -eq 0 ]] || exit "$capture_status"
printf '%s_baseline_accepted=true\n' "$prefix"

readonly generated_root=$work_root/generated
readonly builder_stdout=$work_root/builder.stdout
readonly builder_stderr=$work_root/builder.stderr
: >"$builder_stdout"
: >"$builder_stderr"
chmod 0600 "$builder_stdout" "$builder_stderr"
builder_status=0
/bin/bash "$builder" --output "$generated_root" >"$builder_stdout" \
    2>"$builder_stderr" || builder_status=$?
readonly builder_status
emit_stream builder_stdout "$builder_stdout" || exit $?
emit_stream builder_stderr "$builder_stderr" || exit $?
printf '%s_builder_status=%s\n' "$prefix" "$builder_status"
[[ "$builder_status" -eq 0 ]]
verify_generated "$generated_root"

readonly transaction=$generated_root/run-node-b-caddy-health-helper-action20i.sh
run_capture transaction "$transaction" "$work_root" || exit $?
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=true\n' "$prefix"
printf '%s_keepalived_reloaded=false\n' "$prefix"
printf '%s_node_b_activation=false\n' "$prefix"
printf '%s_cleanup_complete=true\n' "$prefix"
exit "$capture_status"
