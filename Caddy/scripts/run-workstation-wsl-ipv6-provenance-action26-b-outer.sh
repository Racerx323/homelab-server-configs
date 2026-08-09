#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_26_b_outer
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly core=$script_directory/run-workstation-wsl-ipv6-provenance-action26-b.sh
readonly regression=$caddy_root/tests/action26-b-wsl-ipv6-provenance-regression.sh
readonly core_sha256=dc60ed1f3a67aa5aed9919ddbbeda44378112d3fc34959e87dddbe0c56fb1440
readonly regression_sha256=a3474dc05b69b8521945ce52613478092d81978fb7172d4a19fdc14bb498b015
readonly maximum_stream_bytes=262144
readonly maximum_stream_lines=4000
action26b_outer_work_root=

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
    local action26b_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action26b_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action26b_outer_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory core_regular core_executable core_hash \
        regression_regular regression_executable regression_hash syntax shellcheck \
        canonical_format collision_policy conditional_policy output_evidence_policy \
        scalar_grep_policy portable_awk_policy accepted_live_hash_policy regression
}
run_local_gates() {
    local action26b_outer_skip_regression=$1

    gate working_directory working_directory_approved || return 1
    gate core_regular test -f "$core" || return 1
    gate core_executable test -x "$core" || return 1
    gate core_hash test "$(file_hash "$core")" = "$core_sha256" || return 1
    gate regression_regular test -f "$regression" || return 1
    gate regression_executable test -x "$regression" || return 1
    gate regression_hash test "$(file_hash "$regression")" = "$regression_sha256" || return 1
    gate syntax /bin/bash -n "$core" "$regression" "$0" || return 1
    gate shellcheck shellcheck "$core" "$regression" "$0" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$core" "$regression" "$0" || return 1
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$core" "$regression" "$0" || return 1
    gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate output_evidence_policy /bin/bash "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    gate scalar_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$core" "$regression" "$0" || return 1
    gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$core" "$regression" "$0" || return 1
    gate accepted_live_hash_policy /bin/bash "$caddy_root/tests/accepted-live-hash-policy.sh" --check || return 1
    if [[ "$action26b_outer_skip_regression" = true ]]; then
        gate regression test "$action26b_outer_skip_regression" = true || return 1
    else
        gate regression /bin/bash "$regression" || return 1
    fi
}
safe_stream() {
    local action26b_outer_stream_path=$1

    [[ "$(wc -c <"$action26b_outer_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action26b_outer_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action26b_outer_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:' \
        "$action26b_outer_stream_path"
}
emit_stream() {
    local action26b_outer_stream_label=$1
    local action26b_outer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action26b_outer_stream_label" \
        "$(wc -c <"$action26b_outer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action26b_outer_stream_label" \
        "$(line_count "$action26b_outer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action26b_outer_stream_label" \
        "$(file_hash "$action26b_outer_stream_path")"
    if ! safe_stream "$action26b_outer_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' \
            "$prefix" "$action26b_outer_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action26b_outer_stream_label"
    if [[ -s "$action26b_outer_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action26b_outer_stream_label"
        cat "$action26b_outer_stream_path"
        printf '%s_%s_end\n' "$prefix" "$action26b_outer_stream_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action26b_outer_stream_label"
    fi
}
validation() {
    local action26b_outer_validation_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_validation_%s=true\n' "$prefix" "$action26b_outer_validation_label"
        return 0
    fi
    printf '%s_validation_%s=false\n' "$prefix" "$action26b_outer_validation_label" >&2
    return 1
}
classification_allowed() {
    case "$1" in
        ipv6_disabled | ula_route_present | wsl_nat_no_ula_route | \
            wsl_mirrored_no_ula_route | wsl_unknown_mode_no_ula_route | \
            native_linux_no_ula_route | indeterminate_ipv6_provenance) return 0 ;;
        *) return 1 ;;
    esac
}
validate_transcript() {
    local action26b_outer_stdout=$1
    local action26b_outer_status=$2
    local action26b_outer_stderr=$3
    local action26b_outer_expected_checks
    local action26b_outer_actual_checks
    local action26b_outer_expected_count
    local action26b_outer_actual_count
    local action26b_outer_false_count
    local action26b_outer_classification

    # conditional-validator-explicit-failures-begin
    validation status_zero test "$action26b_outer_status" -eq 0 || return 1
    validation stderr_empty test ! -s "$action26b_outer_stderr" || return 1
    action26b_outer_expected_checks=$(/bin/bash "$core" --expected-checks) || return 1
    action26b_outer_actual_checks=$(sed -n 's/^action_26_b_check_\([^=]*\)=true$/\1/p' \
        "$action26b_outer_stdout") || return 1
    validation ordered_checks test "$action26b_outer_actual_checks" = \
        "$action26b_outer_expected_checks" || return 1
    action26b_outer_expected_count=$(printf '%s\n' "$action26b_outer_expected_checks" | wc -l) || return 1
    action26b_outer_actual_count=$(grep -Ec '^action_26_b_check_.*=(true|false)$' \
        "$action26b_outer_stdout" || true) || return 1
    validation check_count_exact test "$action26b_outer_actual_count" -eq \
        "$action26b_outer_expected_count" || return 1
    validation declared_check_count grep -Fqx \
        "action_26_b_check_count=$action26b_outer_expected_count" "$action26b_outer_stdout" || return 1
    action26b_outer_false_count=$(grep -Ec '^action_26_b_check_.*=false$' \
        "$action26b_outer_stdout" || true) || return 1
    validation false_checks_absent test "$action26b_outer_false_count" -eq 0 || return 1
    validation interface_observed grep -Eq '^action_26_b_observed_interface=[a-zA-Z0-9_.:-]+$' \
        "$action26b_outer_stdout" || return 1
    validation vip_route_status_observed grep -Eq '^action_26_b_observed_vip_route_status=[0-9]+$' \
        "$action26b_outer_stdout" || return 1
    validation wslinfo_status_observed grep -Eq '^action_26_b_observed_wslinfo_status=[0-9]+$' \
        "$action26b_outer_stdout" || return 1
    action26b_outer_classification=$(sed -n 's/^action_26_b_observed_classification=//p' \
        "$action26b_outer_stdout") || return 1
    validation classification_single test \
        "$(grep -Ec '^action_26_b_observed_classification=' "$action26b_outer_stdout" || true)" -eq 1 || return 1
    validation classification_allowed classification_allowed "$action26b_outer_classification" || return 1
    validation live_network_probe_false grep -Fqx \
        'action_26_b_live_network_probe=false' "$action26b_outer_stdout" || return 1
    validation node_ssh_false grep -Fqx 'action_26_b_node_ssh=false' "$action26b_outer_stdout" || return 1
    validation persistent_mutation_false grep -Fqx \
        'action_26_b_persistent_mutation=false' "$action26b_outer_stdout" || return 1
    validation complete grep -Fqx 'action_26_b_diagnostic_complete=true' \
        "$action26b_outer_stdout" || return 1
    # conditional-validator-explicit-failures-end
}
cleanup() {
    local action26b_outer_cleanup_status=$?

    trap - EXIT INT TERM
    [[ -z "$action26b_outer_work_root" ]] || rm -rf -- "$action26b_outer_work_root"
    exit "$action26b_outer_cleanup_status"
}
run_action() {
    local action26b_outer_core_status=0
    local action26b_outer_stdout
    local action26b_outer_stderr

    action26b_outer_work_root=$(mktemp -d /tmp/caddy-action26-b-outer.XXXXXX)
    trap cleanup EXIT INT TERM
    action26b_outer_stdout=$action26b_outer_work_root/core.stdout
    action26b_outer_stderr=$action26b_outer_work_root/core.stderr
    run_local_gates "${CADDY_ACTION26B_SKIP_REGRESSION:-false}" || return 1
    /bin/bash "$core" >"$action26b_outer_stdout" 2>"$action26b_outer_stderr" ||
        action26b_outer_core_status=$?
    emit_stream core_stdout "$action26b_outer_stdout" || return $?
    emit_stream core_stderr "$action26b_outer_stderr" || return $?
    validate_transcript "$action26b_outer_stdout" "$action26b_outer_core_status" \
        "$action26b_outer_stderr" || return 1
    printf '%s_local_observation=true\n' "$prefix"
    printf '%s_live_network_probe=false\n' "$prefix"
    printf '%s_node_ssh=false\n' "$prefix"
    printf '%s_read_only=true\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-local-gates) expected_local_gates ;;
    --validate-transcript) validate_transcript "${2:?}" "${3:?}" "${4:?}" ;;
    --self-test)
        action26b_outer_work_root=$(mktemp -d /tmp/caddy-action26-b-outer-selftest.XXXXXX)
        trap cleanup EXIT INT TERM
        CADDY_ACTION26B_SKIP_REGRESSION=true run_local_gates true
        ;;
    '') run_action ;;
    *) exit 64 ;;
esac
