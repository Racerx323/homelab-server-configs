#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20g_retry_outer
readonly historical_outer_sha256=b4a51f8ec33b130ce4ee540ebb310a4393da023693d2b453dec84c3d42ab76a9
readonly baseline_builder_sha256=dfbd052e6e71747e16a7018301740cac3b0db5c04b69b7bc85095e0faf684b8b
readonly correction_builder_sha256=8171bf8bf9cc881f4939c1589fbae181f95be110c56c4bee596125d1e5f86c5b
readonly regression_sha256=21ccb477aa84b561f333f599212d145756214db8f8368bea596151834de9aa0d
readonly hash_policy_sha256=ddd0bac4ed05db2b8a082c3df21e5e1b8a439ad5c7d60e74b09ee0aa99629174
readonly hash_policy_regression_sha256=edefa5e7c66e43395ef6f073ac0831307589b5d66b37e67190e2b3cd9cb0a857
readonly portable_awk_policy_sha256=30e6be4f4737b9df3c9669572252ee8bff7ae949387a7f96ebe62a2e384fc755
readonly portable_awk_regression_sha256=8b32ebc8c3edb1f2a5c0fcbf18b154963504c092f04d2b3372bb89d676f6e98e
readonly accepted_manifest_sha256=78f7e81d77acf93be923ca4a95a3f16d3250f6d0b52f767fd3044e6ad6575e44
readonly consumer_registry_sha256=d39c66f73f06b64371ee7327b9c49a1d64567f3c9cb18693d4315931015df541
readonly baseline_probe_sha256=0b0176222c78dad4726c4094f0378b6edb1bc22e6ec2011b2ebebd616ed9626d
readonly baseline_runner_sha256=55e465174151ddc40b577fc806079c48c0bcc70ea0e65b89d3f33552ce4f3f3e
readonly correction_installer_sha256=1961680f2591a988af5203744947455080903ce29e8317cfe678d95dffe78b6c
readonly correction_runner_sha256=88398dccf48209f63b5765d47886970269668fc486f3573f13ebabce192146ec
readonly maximum_bytes=8388608
readonly maximum_lines=32768

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly historical_outer=$script_directory/run-node-b-caddy-health-group-correction-action20g-outer.sh
readonly baseline_builder=$script_directory/build-action20g-retry-baseline.sh
readonly correction_builder=$script_directory/build-node-b-caddy-health-group-action20g.sh
readonly regression=$caddy_root/tests/action20g-retry-stale-hash-regression.sh
readonly hash_policy=$caddy_root/tests/accepted-live-hash-policy.sh
readonly hash_policy_regression=$caddy_root/tests/accepted-live-hash-policy-regression.sh
readonly portable_awk_policy=$caddy_root/tests/portable-awk-policy.sh
readonly portable_awk_regression=$caddy_root/tests/portable-awk-policy-regression.sh
readonly accepted_manifest=$caddy_root/manifests/accepted-live-artifacts.tsv
readonly consumer_registry=$caddy_root/manifests/deployable-live-hash-consumers.tsv

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
    local action20g_retry_expected_hash=$1
    local action20g_retry_path=$2

    [[ -f "$action20g_retry_path" && ! -L "$action20g_retry_path" ]] || return 1
    [[ "$(file_hash "$action20g_retry_path")" = "$action20g_retry_expected_hash" ]]
}
run_gate() {
    local action20g_retry_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20g_retry_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20g_retry_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory historical_outer_hash baseline_builder_hash \
        correction_builder_hash regression_hash hash_policy_hash \
        hash_policy_regression_hash portable_awk_policy_hash \
        portable_awk_regression_hash accepted_manifest_hash consumer_registry_hash \
        syntax collision_policy conditional_policy output_evidence_policy \
        multifile_grep_policy accepted_live_hash_policy hash_policy_regression \
        portable_awk_policy portable_awk_regression \
        baseline_builder_self_test baseline_builder_contract_test \
        correction_builder_self_test regression
}
run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate historical_outer_hash require_hash "$historical_outer_sha256" "$historical_outer" || return 1
    run_gate baseline_builder_hash require_hash "$baseline_builder_sha256" "$baseline_builder" || return 1
    run_gate correction_builder_hash require_hash "$correction_builder_sha256" "$correction_builder" || return 1
    run_gate regression_hash require_hash "$regression_sha256" "$regression" || return 1
    run_gate hash_policy_hash require_hash "$hash_policy_sha256" "$hash_policy" || return 1
    run_gate hash_policy_regression_hash require_hash "$hash_policy_regression_sha256" "$hash_policy_regression" || return 1
    run_gate portable_awk_policy_hash require_hash "$portable_awk_policy_sha256" "$portable_awk_policy" || return 1
    run_gate portable_awk_regression_hash require_hash "$portable_awk_regression_sha256" "$portable_awk_regression" || return 1
    run_gate accepted_manifest_hash require_hash "$accepted_manifest_sha256" "$accepted_manifest" || return 1
    run_gate consumer_registry_hash require_hash "$consumer_registry_sha256" "$consumer_registry" || return 1
    run_gate syntax /bin/bash -n "$baseline_builder" "$correction_builder" "$regression" \
        "$hash_policy" "$hash_policy_regression" "$portable_awk_policy" \
        "$portable_awk_regression" "$0" || return 1
    run_gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$baseline_builder" "$regression" "$hash_policy" "$hash_policy_regression" \
        "$portable_awk_policy" "$portable_awk_regression" "$0" || return 1
    run_gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate output_evidence_policy /bin/bash "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    run_gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$baseline_builder" "$regression" "$hash_policy" "$hash_policy_regression" "$0" || return 1
    run_gate accepted_live_hash_policy /bin/bash "$hash_policy" --check || return 1
    run_gate hash_policy_regression /bin/bash "$hash_policy_regression" || return 1
    run_gate portable_awk_policy /bin/bash "$portable_awk_policy" --check || return 1
    run_gate portable_awk_regression /bin/bash "$portable_awk_regression" || return 1
    run_gate baseline_builder_self_test /bin/bash "$baseline_builder" --self-test || return 1
    run_gate baseline_builder_contract_test /bin/bash "$baseline_builder" --contract-test || return 1
    run_gate correction_builder_self_test /bin/bash "$correction_builder" --self-test || return 1
    run_gate regression /bin/bash "$regression" || return 1
}
safe_stream() {
    local action20g_retry_stream=$1

    [[ "$(wc -c <"$action20g_retry_stream")" -le "$maximum_bytes" ]] || return 1
    [[ "$(line_count "$action20g_retry_stream")" -le "$maximum_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20g_retry_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' "$action20g_retry_stream"
}
emit_stream() {
    local action20g_retry_stream_label=$1
    local action20g_retry_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20g_retry_stream_label" "$(wc -c <"$action20g_retry_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20g_retry_stream_label" "$(line_count "$action20g_retry_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20g_retry_stream_label" "$(file_hash "$action20g_retry_stream_path")"
    if safe_stream "$action20g_retry_stream_path"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20g_retry_stream_label"
        if [[ -s "$action20g_retry_stream_path" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action20g_retry_stream_label"
            cat "$action20g_retry_stream_path"
            printf '%s_%s_end\n' "$prefix" "$action20g_retry_stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$action20g_retry_stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20g_retry_stream_label" >&2
    return 97
}
run_capture() {
    local action20g_retry_capture_label=$1
    local action20g_retry_capture_command=$2
    local action20g_retry_capture_root=$3
    local action20g_retry_capture_status=0

    /bin/bash "$action20g_retry_capture_command" \
        >"$action20g_retry_capture_root/$action20g_retry_capture_label.stdout" \
        2>"$action20g_retry_capture_root/$action20g_retry_capture_label.stderr" ||
        action20g_retry_capture_status=$?
    emit_stream "${action20g_retry_capture_label}_stdout" \
        "$action20g_retry_capture_root/$action20g_retry_capture_label.stdout" || return 97
    emit_stream "${action20g_retry_capture_label}_stderr" \
        "$action20g_retry_capture_root/$action20g_retry_capture_label.stderr" || return 97
    printf '%s_%s_status=%s\n' "$prefix" "$action20g_retry_capture_label" "$action20g_retry_capture_status"
    return "$action20g_retry_capture_status"
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
        printf 'Usage: %s [--expected-local-gates|--self-test|--source-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

run_local_gates
work_root=$(mktemp -d /tmp/caddy-action20g-retry-outer.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT
readonly baseline_root=$work_root/baseline
readonly correction_root=$work_root/correction
install -d -m 0700 "$baseline_root" "$correction_root"
for action20g_retry_capture in baseline-builder correction-builder baseline correction; do
    : >"$work_root/$action20g_retry_capture.stdout"
    : >"$work_root/$action20g_retry_capture.stderr"
    chmod 0600 "$work_root/$action20g_retry_capture.stdout" "$work_root/$action20g_retry_capture.stderr"
done

baseline_builder_status=0
/bin/bash "$baseline_builder" --output "$baseline_root" \
    >"$work_root/baseline-builder.stdout" 2>"$work_root/baseline-builder.stderr" ||
    baseline_builder_status=$?
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
    >"$work_root/correction-builder.stdout" 2>"$work_root/correction-builder.stderr" ||
    correction_builder_status=$?
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
