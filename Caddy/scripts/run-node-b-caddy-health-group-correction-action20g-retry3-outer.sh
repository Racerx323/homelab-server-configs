#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20g_retry3_outer
readonly previous_outer_sha256=e9f6bf413f2a5aacbd6070b7f130753d52205ef2c9e8823d0f9e6522d082bf99
readonly baseline_builder_sha256=dfbd052e6e71747e16a7018301740cac3b0db5c04b69b7bc85095e0faf684b8b
readonly correction_builder_sha256=3940963da753e6052b541058d2d362c9a4d3505f3db02c2c4daf6dfbafbbf39e
readonly regression_sha256=3996bd09d3823b582be8bac0d64384eb6d1a5d7a2b8a0a1fb8ad8b5a2c559ae1
readonly baseline_probe_sha256=0b0176222c78dad4726c4094f0378b6edb1bc22e6ec2011b2ebebd616ed9626d
readonly baseline_runner_sha256=55e465174151ddc40b577fc806079c48c0bcc70ea0e65b89d3f33552ce4f3f3e
readonly correction_installer_sha256=17c086a840aa6d85a21cf89cc6d7e7fedc473d4790c5f197472bb72cf2eacd3c
readonly correction_runner_sha256=47a315adc3ad8895fee987bec73b83489e392f06007f85641dd2f65ca8916d4b
readonly maximum_bytes=16777216
readonly maximum_lines=65536

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly previous_outer=$script_directory/run-node-b-caddy-health-group-correction-action20g-retry2-outer.sh
readonly baseline_builder=$script_directory/build-action20g-retry-baseline.sh
readonly correction_builder=$script_directory/build-node-b-caddy-health-group-action20g-retry3.sh
readonly regression=$caddy_root/tests/action20g-retry3-primary-gid-regression.sh
export CADDY_ACTION20G_SOURCE_ROOT=$caddy_root
readonly CADDY_ACTION20G_SOURCE_ROOT

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
require_hash() {
    local action20g_retry3_expected_hash=$1
    local action20g_retry3_path=$2

    [[ -f "$action20g_retry3_path" && ! -L "$action20g_retry3_path" ]] || return 1
    [[ "$(file_hash "$action20g_retry3_path")" = "$action20g_retry3_expected_hash" ]]
}
source_root_exact() {
    [[ "$CADDY_ACTION20G_SOURCE_ROOT" = "$caddy_root" ]] || return 1
    /usr/bin/env | grep -Fqx "CADDY_ACTION20G_SOURCE_ROOT=$caddy_root"
}
run_gate() {
    local action20g_retry3_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20g_retry3_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20g_retry3_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory previous_outer_hash baseline_builder_hash \
        correction_builder_hash regression_hash syntax collision_policy \
        conditional_policy output_evidence_policy multifile_grep_policy \
        accepted_live_hash_policy portable_awk_policy source_root \
        baseline_builder_self_test correction_builder_self_test regression
}
run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate previous_outer_hash require_hash "$previous_outer_sha256" "$previous_outer" || return 1
    run_gate baseline_builder_hash require_hash "$baseline_builder_sha256" "$baseline_builder" || return 1
    run_gate correction_builder_hash require_hash "$correction_builder_sha256" "$correction_builder" || return 1
    run_gate regression_hash require_hash "$regression_sha256" "$regression" || return 1
    run_gate syntax /bin/bash -n "$baseline_builder" "$correction_builder" "$regression" "$0" || return 1
    run_gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$correction_builder" "$regression" "$0" || return 1
    run_gate conditional_policy /bin/bash \
        "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate output_evidence_policy /bin/bash \
        "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    run_gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" \
        --check "$correction_builder" "$regression" "$0" || return 1
    run_gate accepted_live_hash_policy /bin/bash "$caddy_root/tests/accepted-live-hash-policy.sh" --check || return 1
    run_gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check || return 1
    run_gate source_root source_root_exact || return 1
    run_gate baseline_builder_self_test /bin/bash "$baseline_builder" --self-test || return 1
    run_gate correction_builder_self_test /bin/bash "$correction_builder" --self-test || return 1
    run_gate regression /bin/bash "$regression" || return 1
}
safe_stream() {
    local action20g_retry3_stream=$1

    [[ "$(wc -c <"$action20g_retry3_stream")" -le "$maximum_bytes" ]] || return 1
    [[ "$(line_count "$action20g_retry3_stream")" -le "$maximum_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20g_retry3_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20g_retry3_stream"
}
emit_stream() {
    local action20g_retry3_stream_label=$1
    local action20g_retry3_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20g_retry3_stream_label" \
        "$(wc -c <"$action20g_retry3_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20g_retry3_stream_label" \
        "$(line_count "$action20g_retry3_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20g_retry3_stream_label" \
        "$(file_hash "$action20g_retry3_stream_path")"
    if safe_stream "$action20g_retry3_stream_path"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20g_retry3_stream_label"
        if [[ -s "$action20g_retry3_stream_path" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action20g_retry3_stream_label"
            cat "$action20g_retry3_stream_path"
            printf '%s_%s_end\n' "$prefix" "$action20g_retry3_stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$action20g_retry3_stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20g_retry3_stream_label" >&2
    return 97
}
run_capture() {
    local action20g_retry3_label=$1
    local action20g_retry3_runner=$2
    local action20g_retry3_capture_root=$3
    local action20g_retry3_status=0

    /usr/bin/env CADDY_ACTION20G_SOURCE_ROOT="$caddy_root" /bin/bash "$action20g_retry3_runner" \
        >"$action20g_retry3_capture_root/$action20g_retry3_label.stdout" \
        2>"$action20g_retry3_capture_root/$action20g_retry3_label.stderr" || action20g_retry3_status=$?
    emit_stream "${action20g_retry3_label}_stdout" \
        "$action20g_retry3_capture_root/$action20g_retry3_label.stdout" || return 97
    emit_stream "${action20g_retry3_label}_stderr" \
        "$action20g_retry3_capture_root/$action20g_retry3_label.stderr" || return 97
    printf '%s_%s_status=%s\n' "$prefix" "$action20g_retry3_label" "$action20g_retry3_status"
    return "$action20g_retry3_status"
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
work_root=$(mktemp -d /tmp/caddy-action20g-retry3-outer.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT
readonly baseline_root=$work_root/baseline
readonly correction_root=$work_root/correction
install -d -m 0700 "$baseline_root" "$correction_root"
for action20g_retry3_capture in baseline-builder correction-builder baseline correction; do
    : >"$work_root/$action20g_retry3_capture.stdout"
    : >"$work_root/$action20g_retry3_capture.stderr"
    chmod 0600 "$work_root/$action20g_retry3_capture.stdout" "$work_root/$action20g_retry3_capture.stderr"
done

baseline_builder_status=0
/bin/bash "$baseline_builder" --output "$baseline_root" \
    >"$work_root/baseline-builder.stdout" 2>"$work_root/baseline-builder.stderr" || baseline_builder_status=$?
readonly baseline_builder_status
emit_stream baseline_builder_stdout "$work_root/baseline-builder.stdout"
emit_stream baseline_builder_stderr "$work_root/baseline-builder.stderr"
[[ "$baseline_builder_status" -eq 0 ]]
readonly baseline_probe=$baseline_root/inspect-dual-node-caddy-postactivation-action20g-retry.sh
readonly baseline_runner=$baseline_root/run-dual-node-caddy-postactivation-action20g-retry.sh
require_hash "$baseline_probe_sha256" "$baseline_probe"
require_hash "$baseline_runner_sha256" "$baseline_runner"

correction_builder_status=0
/bin/bash "$correction_builder" --output "$correction_root" \
    >"$work_root/correction-builder.stdout" 2>"$work_root/correction-builder.stderr" || correction_builder_status=$?
readonly correction_builder_status
emit_stream correction_builder_stdout "$work_root/correction-builder.stdout"
emit_stream correction_builder_stderr "$work_root/correction-builder.stderr"
[[ "$correction_builder_status" -eq 0 ]]
readonly correction_installer=$correction_root/install-node-b-caddy-health-group-action20g.sh
readonly correction_runner=$correction_root/run-node-b-caddy-health-group-correction-action20g.sh
require_hash "$correction_installer_sha256" "$correction_installer"
require_hash "$correction_runner_sha256" "$correction_runner"

run_capture baseline "$baseline_runner" "$work_root"
run_capture correction "$correction_runner" "$work_root"
printf '%s_baseline_accepted=true\n' "$prefix"
printf '%s_correction_accepted=true\n' "$prefix"
printf '%s_node_b_activation_invoked=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
