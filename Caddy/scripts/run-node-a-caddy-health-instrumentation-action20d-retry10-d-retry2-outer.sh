#!/usr/bin/env bash
# shellcheck disable=SC2317

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_d_retry2_outer
readonly builder_sha256=f4eec61014fe68ee0367a24e982b688b60025c8e07e6add655c82aff1bceb346
readonly candidate_sha256=d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810
readonly installer_sha256=9845137186eeb3bc6e16e83972bf8aec70f2ff82b0ee5f49110df48784ddc830
readonly runner_sha256=459e1b85037d82184e7daf586776bbee03d27df5ce8f40a6ca463f66c9edd409
readonly stager_sha256=2b8affebe56181007250c2a3cf859c25f18e7942bd62062ce353213488eca058
readonly regression_sha256=4fba7ad2744639a321dab5e35cc93abcf5480dbb6a86344bdbb9fca844fa8b83
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=32768

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly builder=$script_directory/build-node-a-caddy-health-instrumentation-action20d-retry10-d-retry2.sh
readonly regression=$caddy_root/tests/action20d-retry10-d-retry2-complete-path-regression.sh
generated_root=

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
    local action20d_d_retry2_outer_expected_hash=$1
    local action20d_d_retry2_outer_source_path=$2

    [[ -f "$action20d_d_retry2_outer_source_path" &&
        ! -L "$action20d_d_retry2_outer_source_path" ]] || return 1
    [[ "$(stat -c '%a' "$action20d_d_retry2_outer_source_path")" = 755 ]] || return 1
    [[ "$(file_hash "$action20d_d_retry2_outer_source_path")" = "$action20d_d_retry2_outer_expected_hash" ]] || return 1
}
gate() {
    local action20d_d_retry2_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_outer_gate_%s=true\n' "$prefix" "$action20d_d_retry2_outer_gate_label"
        return 0
    fi
    printf '%s_outer_gate_%s=false\n' "$prefix" "$action20d_d_retry2_outer_gate_label" >&2
    return 1
}
safe_stream() {
    local action20d_d_retry2_outer_stream_path=$1

    [[ "$(wc -c <"$action20d_d_retry2_outer_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20d_d_retry2_outer_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20d_d_retry2_outer_stream_path" \
        >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20d_d_retry2_outer_stream_path"
}
emit_stream() {
    local action20d_d_retry2_outer_stream_label=$1
    local action20d_d_retry2_outer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20d_d_retry2_outer_stream_label" \
        "$(wc -c <"$action20d_d_retry2_outer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20d_d_retry2_outer_stream_label" \
        "$(line_count "$action20d_d_retry2_outer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20d_d_retry2_outer_stream_label" \
        "$(file_hash "$action20d_d_retry2_outer_stream_path")"
    if ! safe_stream "$action20d_d_retry2_outer_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' \
            "$prefix" "$action20d_d_retry2_outer_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' \
        "$prefix" "$action20d_d_retry2_outer_stream_label"
    if [[ -s "$action20d_d_retry2_outer_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action20d_d_retry2_outer_stream_label"
        cat "$action20d_d_retry2_outer_stream_path"
        printf '%s_%s_end\n' "$prefix" "$action20d_d_retry2_outer_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' \
            "$prefix" "$action20d_d_retry2_outer_stream_label"
    fi
}
build_generated_sources() {
    generated_root=$1
    /bin/bash "$builder" --output "$generated_root" >/dev/null || return 1
}
generated_sources_exact() {
    local action20d_d_retry2_outer_generated_root=$1

    source_exact "$candidate_sha256" \
        "$action20d_d_retry2_outer_generated_root/check-caddy-instrumented-action20d-retry10-d.sh" || return 1
    source_exact "$installer_sha256" \
        "$action20d_d_retry2_outer_generated_root/install-node-a-caddy-health-instrumentation-action20d-retry10-d-retry2.sh" || return 1
    source_exact "$runner_sha256" \
        "$action20d_d_retry2_outer_generated_root/run-node-a-caddy-health-instrumentation-action20d-retry10-d-retry2.sh" || return 1
    source_exact "$stager_sha256" \
        "$action20d_d_retry2_outer_generated_root/stage-node-a-caddy-health-instrumentation-action20d-retry10-d-retry2.sh" || return 1
}
run_local_gates() {
    local action20d_d_retry2_outer_gate_root

    action20d_d_retry2_outer_gate_root=$(mktemp -d \
        /tmp/caddy-action20d-retry10-d-retry2-outer-gates.XXXXXX) || return 1
    trap 'rm -rf -- "$action20d_d_retry2_outer_gate_root"; trap - RETURN' RETURN
    gate working_directory working_directory_approved || return 1
    gate builder_source source_exact "$builder_sha256" "$builder" || return 1
    gate regression_source source_exact "$regression_sha256" "$regression" || return 1
    gate syntax /bin/bash -n "$builder" "$regression" "$0" || return 1
    gate shellcheck shellcheck "$builder" "$regression" "$0" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$builder" "$regression" "$0" || return 1
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$builder" "$regression" "$0" || return 1
    gate conditional_policy /bin/bash \
        "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate transcript_policy /bin/bash \
        "$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh" || return 1
    gate output_policy /bin/bash \
        "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    gate durable_staging_rule grep -Fq \
        'Any staged artifact consumed by an unprivileged identity must be placed in a' \
        "$caddy_root/../AGENTS.md" || return 1
    gate builder_self_test /bin/bash "$builder" --self-test || return 1
    gate generated_sources build_generated_sources \
        "$action20d_d_retry2_outer_gate_root/generated" || return 1
    gate generated_hashes generated_sources_exact \
        "$action20d_d_retry2_outer_gate_root/generated" || return 1
    gate production_regression /bin/bash "$regression" || return 1
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        printf '%s\n' \
            working_directory builder_source regression_source syntax shellcheck \
            canonical_format collision_policy conditional_policy transcript_policy \
            output_policy durable_staging_rule builder_self_test generated_sources \
            generated_hashes production_regression
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
work_root=$(mktemp -d /tmp/caddy-action20d-retry10-d-retry2-outer.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
readonly runner_stdout=$work_root/runner.stdout
readonly runner_stderr=$work_root/runner.stderr
build_generated_sources "$work_root/generated"
generated_sources_exact "$work_root/generated"
: >"$runner_stdout"
: >"$runner_stderr"
chmod 0600 "$runner_stdout" "$runner_stderr"
runner_status=0
/bin/bash \
    "$work_root/generated/run-node-a-caddy-health-instrumentation-action20d-retry10-d-retry2.sh" \
    >"$runner_stdout" 2>"$runner_stderr" || runner_status=$?
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
printf '%s_vrrp_activation=false\n' "$prefix"
printf '%s_cleanup_complete=true\n' "$prefix"
exit "$runner_status"
