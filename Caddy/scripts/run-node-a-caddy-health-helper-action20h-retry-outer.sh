#!/usr/bin/env bash
# shellcheck disable=SC2317

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20h_retry_outer
readonly candidate_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly installer_sha256=33a834270f8c468e24a573b7ab42cb106d2d25f2624ef783031964771c93874f
readonly stager_sha256=41ef10df5c02a058742b2e4c2d5183cd1c35c74ec63d103d1b5ff0ed8ba52e71
readonly runner_sha256=e0ad03a83e75b4e7ec3e4c3beb23458d72c90d13ffc6f0e14a105b070abbd48c
readonly regression_sha256=5ed35e5da3285e3dae1097a68b505da1caa7f1974febf52e3ef11a0f6268b0f4
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=32768

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly candidate=$script_directory/check-caddy-vrrp-action20h.sh
readonly installer=$script_directory/install-node-a-caddy-health-helper-action20h-retry.sh
readonly stager=$script_directory/stage-node-a-caddy-health-helper-action20h.sh
readonly runner=$script_directory/run-node-a-caddy-health-helper-action20h-retry.sh
readonly regression=$caddy_root/tests/action20h-retry-stale-path-regression.sh

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
    local action20h_retry_outer_expected_hash=$1
    local action20h_retry_outer_source_path=$2

    [[ -f "$action20h_retry_outer_source_path" && ! -L "$action20h_retry_outer_source_path" ]] || return 1
    [[ "$(stat -c '%a' "$action20h_retry_outer_source_path")" = 755 ]] || return 1
    [[ "$(file_hash "$action20h_retry_outer_source_path")" = "$action20h_retry_outer_expected_hash" ]] || return 1
}
gate() {
    local action20h_retry_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_outer_gate_%s=true\n' "$prefix" "$action20h_retry_outer_gate_label"
        return 0
    fi
    printf '%s_outer_gate_%s=false\n' "$prefix" "$action20h_retry_outer_gate_label" >&2
    return 1
}
safe_stream() {
    local action20h_retry_outer_stream_path=$1

    [[ "$(wc -c <"$action20h_retry_outer_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20h_retry_outer_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20h_retry_outer_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20h_retry_outer_stream_path" || return 1
}
emit_stream() {
    local action20h_retry_outer_stream_label=$1
    local action20h_retry_outer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20h_retry_outer_stream_label" \
        "$(wc -c <"$action20h_retry_outer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20h_retry_outer_stream_label" \
        "$(line_count "$action20h_retry_outer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20h_retry_outer_stream_label" \
        "$(file_hash "$action20h_retry_outer_stream_path")"
    if ! safe_stream "$action20h_retry_outer_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" \
            "$action20h_retry_outer_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20h_retry_outer_stream_label"
    if [[ -s "$action20h_retry_outer_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action20h_retry_outer_stream_label"
        cat "$action20h_retry_outer_stream_path"
        printf '%s_%s_end\n' "$prefix" "$action20h_retry_outer_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$action20h_retry_outer_stream_label"
    fi
}
sources_exact() {
    source_exact "$candidate_sha256" "$candidate" || return 1
    source_exact "$installer_sha256" "$installer" || return 1
    source_exact "$stager_sha256" "$stager" || return 1
    source_exact "$runner_sha256" "$runner" || return 1
    source_exact "$regression_sha256" "$regression" || return 1
}
run_local_gates() {
    gate working_directory working_directory_approved || return 1
    gate source_hashes sources_exact || return 1
    gate syntax /bin/bash -n "$candidate" "$installer" "$stager" "$runner" \
        "$regression" "$0" || return 1
    gate shellcheck shellcheck "$candidate" "$installer" "$stager" "$runner" \
        "$regression" "$0" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$candidate" "$installer" "$stager" "$runner" "$regression" "$0" || return 1
    gate executable_policy /bin/bash "$caddy_root/tests/executable-wrapper-policy-regression.sh" || return 1
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$candidate" "$installer" "$stager" "$runner" "$regression" "$0" || return 1
    gate conditional_policy /bin/bash \
        "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate transcript_policy /bin/bash \
        "$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh" || return 1
    gate output_policy /bin/bash \
        "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    gate candidate_self_test /bin/bash "$candidate" --self-test || return 1
    gate installer_self_test /bin/bash "$installer" --self-test || return 1
    gate runner_self_test /bin/bash "$runner" --self-test || return 1
    gate production_regression /bin/bash "$regression" || return 1
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        printf '%s\n' working_directory source_hashes syntax shellcheck canonical_format \
            executable_policy collision_policy conditional_policy transcript_policy \
            output_policy candidate_self_test installer_self_test runner_self_test \
            production_regression
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
work_root=$(mktemp -d /tmp/caddy-action20h-retry-outer.XXXXXX)
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
printf '%s_node_b_activation=false\n' "$prefix"
printf '%s_cleanup_complete=true\n' "$prefix"
exit "$runner_status"
