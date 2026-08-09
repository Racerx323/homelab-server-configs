#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_26_e_retry_outer
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly adapter=$script_directory/run-workstation-wsl-mirrored-postrestart-action26-e-retry.sh
readonly validator=$script_directory/run-workstation-wsl-mirrored-postrestart-action26-e-outer.sh
readonly regression=$caddy_root/tests/action26-e-retry-postrestart-regression.sh
readonly adapter_sha256=e495dc337390b6861d5077d7b043a4887d6819e3f05106a576efb5180bb6663e
readonly validator_sha256=d5ecf40a30450962ef7ce79f4cce02331f53a4c924650518208808adf86b8133
readonly regression_sha256=6de59bd6f99ddc8a828636ca69f462395e051130ab2fef37d1bb039c7b06a554
readonly maximum_stream_bytes=262144
readonly maximum_stream_lines=4000
action26e_retry_outer_root=

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
gate() {
    local action26e_retry_outer_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action26e_retry_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action26e_retry_outer_label" >&2
    return 1
}
expected_gates() {
    printf '%s\n' working_directory adapter_regular adapter_executable adapter_hash \
        validator_regular validator_executable validator_hash regression_regular \
        regression_executable regression_hash syntax shellcheck canonical_format \
        collision_policy conditional_policy output_evidence_policy scalar_grep_policy \
        portable_awk_policy regression
}
safe_stream() {
    local action26e_retry_stream=$1

    [[ "$(wc -c <"$action26e_retry_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action26e_retry_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action26e_retry_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:' \
        "$action26e_retry_stream"
}
emit_stream() {
    local action26e_retry_label=$1
    local action26e_retry_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action26e_retry_label" "$(wc -c <"$action26e_retry_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action26e_retry_label" "$(line_count "$action26e_retry_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action26e_retry_label" "$(file_hash "$action26e_retry_stream")"
    safe_stream "$action26e_retry_stream" || return 97
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action26e_retry_label"
    if [[ -s "$action26e_retry_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action26e_retry_label"
        cat "$action26e_retry_stream"
        printf '%s_%s_end\n' "$prefix" "$action26e_retry_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action26e_retry_label"
    fi
}
run_gates() {
    local action26e_retry_skip_regression=$1

    gate working_directory working_directory_approved || return 1
    gate adapter_regular test -f "$adapter" || return 1
    gate adapter_executable test -x "$adapter" || return 1
    gate adapter_hash test "$(file_hash "$adapter")" = "$adapter_sha256" || return 1
    gate validator_regular test -f "$validator" || return 1
    gate validator_executable test -x "$validator" || return 1
    gate validator_hash test "$(file_hash "$validator")" = "$validator_sha256" || return 1
    gate regression_regular test -f "$regression" || return 1
    gate regression_executable test -x "$regression" || return 1
    gate regression_hash test "$(file_hash "$regression")" = "$regression_sha256" || return 1
    gate syntax /bin/bash -n "$adapter" "$validator" "$regression" "$0" || return 1
    gate shellcheck shellcheck "$adapter" "$regression" "$0" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$adapter" "$regression" "$0" || return 1
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$adapter" "$regression" "$0" || return 1
    gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate output_evidence_policy /bin/bash "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    gate scalar_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$adapter" "$regression" "$0" || return 1
    gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$adapter" "$regression" "$0" || return 1
    if [[ "$action26e_retry_skip_regression" = true ]]; then
        gate regression test "$action26e_retry_skip_regression" = true || return 1
    else
        gate regression /bin/bash "$regression" || return 1
    fi
}
validate_adapter_checks() {
    local action26e_retry_stdout=$1
    local action26e_retry_expected
    local action26e_retry_actual

    action26e_retry_expected=$(/bin/bash "$adapter" --expected-checks) || return 1
    action26e_retry_actual=$(sed -n 's/^action_26_e_retry_adapter_check_\([^=]*\)=true$/\1/p' \
        "$action26e_retry_stdout") || return 1
    test "$action26e_retry_actual" = "$action26e_retry_expected" || return 1
    test "$(grep -Ec '^action_26_e_retry_adapter_check_.*=(true|false)$' "$action26e_retry_stdout" || true)" \
        -eq "$(printf '%s\n' "$action26e_retry_expected" | wc -l)" || return 1
}
cleanup() {
    local action26e_retry_status=$?

    trap - EXIT INT TERM
    [[ -z "$action26e_retry_outer_root" ]] || rm -rf -- "$action26e_retry_outer_root"
    exit "$action26e_retry_status"
}
run_action() {
    local action26e_retry_status=0
    local action26e_retry_stdout
    local action26e_retry_stderr

    action26e_retry_outer_root=$(mktemp -d /tmp/caddy-action26-e-retry-outer.XXXXXX)
    trap cleanup EXIT INT TERM
    action26e_retry_stdout=$action26e_retry_outer_root/adapter.stdout
    action26e_retry_stderr=$action26e_retry_outer_root/adapter.stderr
    run_gates "${CADDY_ACTION26E_RETRY_SKIP_REGRESSION:-false}" || return 1
    /bin/bash "$adapter" >"$action26e_retry_stdout" 2>"$action26e_retry_stderr" || action26e_retry_status=$?
    emit_stream adapter_stdout "$action26e_retry_stdout" || return $?
    emit_stream adapter_stderr "$action26e_retry_stderr" || return $?
    validate_adapter_checks "$action26e_retry_stdout" || return 1
    /bin/bash "$validator" --validate-transcript "$action26e_retry_stdout" \
        "$action26e_retry_status" "$action26e_retry_stderr" || return 1
    printf '%s_wsl_shutdown=false\n' "$prefix"
    printf '%s_windows_firewall_mutation=false\n' "$prefix"
    printf '%s_node_administrative_contact=false\n' "$prefix"
    printf '%s_persistent_mutation=false\n' "$prefix"
    printf '%s_acceptance=true\n' "$prefix"
}

case "${1:-}" in
    --expected-local-gates) expected_gates ;;
    --validate-adapter-checks) validate_adapter_checks "${2:?}" ;;
    --self-test) CADDY_ACTION26E_RETRY_SKIP_REGRESSION=true run_gates true ;;
    "") run_action ;;
    *) exit 64 ;;
esac
