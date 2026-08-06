#!/usr/bin/env bash
# shellcheck disable=SC2317

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_d_outer
readonly candidate_sha256=d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810
readonly installer_sha256=ade3794ce506be9df2b6117715e33395b98bcd61bfb4dbfd7ed34570e00ee468
readonly runner_sha256=48b3790c24c9dc35be79abf519110cea0145ee5787ed017ca6493314a61f9c25
readonly regression_sha256=1b38908b57f66042edfff9d5f1743d440de715b7c1e350f8f0c7b91b9da1b5ff
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=32768

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly candidate=$script_directory/check-caddy-instrumented-action20d-retry10-d.sh
readonly installer=$script_directory/install-node-a-caddy-health-instrumentation-action20d-retry10-d.sh
readonly runner=$script_directory/run-node-a-caddy-health-instrumentation-action20d-retry10-d.sh
readonly regression=$caddy_root/tests/action20d-retry10-d-health-instrumentation-regression.sh
readonly collision_policy=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh
readonly conditional_policy=$caddy_root/tests/conditional-validator-errexit-policy-regression.sh
readonly transcript_policy=$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh
readonly output_policy=$caddy_root/tests/transaction-output-evidence-policy-regression.sh

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
    local action20d_d_outer_expected_hash=$1
    local action20d_d_outer_source_path=$2

    [[ -f "$action20d_d_outer_source_path" && ! -L "$action20d_d_outer_source_path" ]] || return 1
    [[ "$(stat -c '%a' "$action20d_d_outer_source_path")" = 755 ]] || return 1
    [[ "$(file_hash "$action20d_d_outer_source_path")" = "$action20d_d_outer_expected_hash" ]] || return 1
}
gate() {
    local action20d_d_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_outer_gate_%s=true\n' "$prefix" "$action20d_d_outer_gate_label"
        return 0
    fi
    printf '%s_outer_gate_%s=false\n' "$prefix" "$action20d_d_outer_gate_label" >&2
    return 1
}
safe_stream() {
    local action20d_d_outer_stream_path=$1

    [[ "$(wc -c <"$action20d_d_outer_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20d_d_outer_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20d_d_outer_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20d_d_outer_stream_path"
}
emit_stream() {
    local action20d_d_outer_stream_label=$1
    local action20d_d_outer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20d_d_outer_stream_label" \
        "$(wc -c <"$action20d_d_outer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20d_d_outer_stream_label" \
        "$(line_count "$action20d_d_outer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20d_d_outer_stream_label" \
        "$(file_hash "$action20d_d_outer_stream_path")"
    if ! safe_stream "$action20d_d_outer_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20d_d_outer_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20d_d_outer_stream_label"
    if [[ -s "$action20d_d_outer_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action20d_d_outer_stream_label"
        cat "$action20d_d_outer_stream_path"
        printf '%s_%s_end\n' "$prefix" "$action20d_d_outer_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$action20d_d_outer_stream_label"
    fi
}
run_local_gates() {
    gate working_directory working_directory_approved || return 1
    gate candidate_source source_exact "$candidate_sha256" "$candidate" || return 1
    gate installer_source source_exact "$installer_sha256" "$installer" || return 1
    gate runner_source source_exact "$runner_sha256" "$runner" || return 1
    gate regression_source source_exact "$regression_sha256" "$regression" || return 1
    gate syntax /bin/bash -n "$candidate" "$installer" "$runner" "$regression" "$0" || return 1
    gate shellcheck shellcheck "$candidate" "$installer" "$runner" "$regression" "$0" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$candidate" "$installer" "$runner" "$regression" "$0" || return 1
    gate collision_policy /bin/bash "$collision_policy" \
        "$candidate" "$installer" "$runner" "$regression" "$0" || return 1
    gate conditional_policy /bin/bash "$conditional_policy" || return 1
    gate transcript_policy /bin/bash "$transcript_policy" || return 1
    gate output_policy /bin/bash "$output_policy" || return 1
    gate candidate_self_test /bin/bash "$candidate" --self-test || return 1
    gate installer_self_test /bin/bash "$installer" --self-test || return 1
    gate runner_self_test /bin/bash "$runner" --self-test || return 1
    gate production_regression /bin/bash "$regression" || return 1
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        printf '%s\n' \
            working_directory candidate_source installer_source runner_source \
            regression_source syntax shellcheck canonical_format collision_policy \
            conditional_policy transcript_policy output_policy candidate_self_test \
            installer_self_test runner_self_test production_regression
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
work_root=$(mktemp -d /tmp/caddy-action20d-retry10-d-outer.XXXXXX)
readonly work_root
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
printf '%s_keepalived_reloaded=false\n' "$prefix"
printf '%s_vrrp_activation=false\n' "$prefix"
printf '%s_cleanup_complete=true\n' "$prefix"
exit "$runner_status"
