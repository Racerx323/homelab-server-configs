#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_26_e_outer
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly core=$script_directory/inspect-workstation-wsl-mirrored-postrestart-action26-d.sh
readonly regression=$caddy_root/tests/action26-e-postrestart-regression.sh
readonly core_sha256=c28daa30a7b127d8d6b4ca9e669564350367695e8be4986112b4478d37d23a1d
readonly regression_sha256=658ff062a8ae194b1b9988469a7333190cc21eee92e1807831632a9cd2392c0c
readonly maximum_stream_bytes=262144
readonly maximum_stream_lines=4000
action26e_outer_work_root=

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
    local action26e_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action26e_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action26e_outer_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory core_regular core_executable core_hash \
        regression_regular regression_executable regression_hash syntax shellcheck \
        canonical_format collision_policy conditional_policy output_evidence_policy \
        scalar_grep_policy portable_awk_policy regression
}
expected_core_checks() {
    printf '%s\n' \
        target_regular target_not_symlink target_hash \
        backup_manifest_regular backup_manifest_action backup_manifest_baseline \
        wslinfo_stdout_safe wslinfo_stderr_safe wslinfo_status_zero networking_mode_mirrored \
        ipv6_addr_stdout_safe ipv6_addr_stderr_safe ipv6_addr_status_zero ula_address_present \
        node_a_route_stdout_safe node_a_route_stderr_safe node_a_route_status_zero \
        node_a_route_source_ula \
        node_b_route_stdout_safe node_b_route_stderr_safe node_b_route_status_zero \
        node_b_route_source_ula \
        caddy_vip_route_stdout_safe caddy_vip_route_stderr_safe caddy_vip_route_status_zero \
        caddy_vip_route_source_ula \
        dns_stdout_safe dns_stderr_safe dns_status_zero dns_answer_count_exact dns_answer_exact \
        https_stdout_safe https_stderr_safe https_status_zero https_protocol_exact \
        https_http_status_exact https_remote_ip_exact https_body_empty https_redirects_zero
}
run_local_gates() {
    local action26e_outer_skip_regression=$1

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
    if [[ "$action26e_outer_skip_regression" = true ]]; then
        gate regression test "$action26e_outer_skip_regression" = true || return 1
    else
        gate regression /bin/bash "$regression" || return 1
    fi
}
safe_stream() {
    local action26e_outer_stream_path=$1

    [[ "$(wc -c <"$action26e_outer_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action26e_outer_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action26e_outer_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:' \
        "$action26e_outer_stream_path"
}
emit_stream() {
    local action26e_outer_stream_label=$1
    local action26e_outer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action26e_outer_stream_label" \
        "$(wc -c <"$action26e_outer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action26e_outer_stream_label" \
        "$(line_count "$action26e_outer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action26e_outer_stream_label" \
        "$(file_hash "$action26e_outer_stream_path")"
    safe_stream "$action26e_outer_stream_path" || return 97
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action26e_outer_stream_label"
    if [[ -s "$action26e_outer_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action26e_outer_stream_label"
        cat "$action26e_outer_stream_path"
        printf '%s_%s_end\n' "$prefix" "$action26e_outer_stream_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action26e_outer_stream_label"
    fi
}
validation() {
    local action26e_outer_validation_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_validation_%s=true\n' "$prefix" "$action26e_outer_validation_label"
        return 0
    fi
    printf '%s_validation_%s=false\n' "$prefix" "$action26e_outer_validation_label" >&2
    return 1
}
validate_transcript() {
    local action26e_outer_stdout=$1
    local action26e_outer_status=$2
    local action26e_outer_stderr=$3
    local action26e_outer_actual_checks
    local action26e_outer_expected_checks

    # conditional-validator-explicit-failures-begin
    validation status_zero test "$action26e_outer_status" -eq 0 || return 1
    validation stderr_empty test ! -s "$action26e_outer_stderr" || return 1
    action26e_outer_expected_checks=$(expected_core_checks) || return 1
    action26e_outer_actual_checks=$(sed -n \
        's/^action_26_d_linux_check_\([^=]*\)=true$/\1/p' "$action26e_outer_stdout") || return 1
    validation ordered_checks test "$action26e_outer_actual_checks" = \
        "$action26e_outer_expected_checks" || return 1
    validation check_count_exact test \
        "$(grep -Ec '^action_26_d_linux_check_.*=(true|false)$' "$action26e_outer_stdout" || true)" -eq \
        "$(printf '%s\n' "$action26e_outer_expected_checks" | wc -l)" || return 1
    validation false_checks_absent test \
        "$(grep -Ec '^action_26_d_linux_check_.*=false$' "$action26e_outer_stdout" || true)" -eq 0 || return 1
    validation mode_mirrored grep -Fqx \
        'action_26_d_linux_observed_networking_mode=mirrored' "$action26e_outer_stdout" || return 1
    validation node_a_route_status_zero grep -Fqx \
        'action_26_d_linux_observed_node_a_route_status=0' "$action26e_outer_stdout" || return 1
    validation node_b_route_status_zero grep -Fqx \
        'action_26_d_linux_observed_node_b_route_status=0' "$action26e_outer_stdout" || return 1
    validation caddy_vip_route_status_zero grep -Fqx \
        'action_26_d_linux_observed_caddy_vip_route_status=0' "$action26e_outer_stdout" || return 1
    validation dns_status_zero grep -Fqx \
        'action_26_d_linux_observed_dns_status=0' "$action26e_outer_stdout" || return 1
    validation https_status_zero grep -Fqx \
        'action_26_d_linux_observed_https_status=0' "$action26e_outer_stdout" || return 1
    validation rollback_false grep -Fqx \
        'action_26_d_linux_rollback_mode=false' "$action26e_outer_stdout" || return 1
    validation persistent_mutation_false grep -Fqx \
        'action_26_d_linux_persistent_mutation=false' "$action26e_outer_stdout" || return 1
    validation core_acceptance grep -Fqx \
        'action_26_d_linux_acceptance=true' "$action26e_outer_stdout" || return 1
    # conditional-validator-explicit-failures-end
}
cleanup() {
    local action26e_outer_cleanup_status=$?

    trap - EXIT INT TERM
    [[ -z "$action26e_outer_work_root" ]] || rm -rf -- "$action26e_outer_work_root"
    exit "$action26e_outer_cleanup_status"
}
run_action() {
    local action26e_outer_core_status=0
    local action26e_outer_stdout
    local action26e_outer_stderr

    action26e_outer_work_root=$(mktemp -d /tmp/caddy-action26-e-outer.XXXXXX)
    trap cleanup EXIT INT TERM
    action26e_outer_stdout=$action26e_outer_work_root/core.stdout
    action26e_outer_stderr=$action26e_outer_work_root/core.stderr
    run_local_gates "${CADDY_ACTION26E_SKIP_REGRESSION:-false}" || return 1
    /bin/bash "$core" --expect-mirrored >"$action26e_outer_stdout" 2>"$action26e_outer_stderr" ||
        action26e_outer_core_status=$?
    emit_stream core_stdout "$action26e_outer_stdout" || return $?
    emit_stream core_stderr "$action26e_outer_stderr" || return $?
    validate_transcript "$action26e_outer_stdout" "$action26e_outer_core_status" \
        "$action26e_outer_stderr" || return 1
    printf '%s_wsl_shutdown=false\n' "$prefix"
    printf '%s_windows_firewall_mutation=false\n' "$prefix"
    printf '%s_node_administrative_contact=false\n' "$prefix"
    printf '%s_persistent_mutation=false\n' "$prefix"
    printf '%s_acceptance=true\n' "$prefix"
}

case "${1:-}" in
    --expected-local-gates) expected_local_gates ;;
    --expected-core-checks) expected_core_checks ;;
    --validate-transcript) validate_transcript "${2:?}" "${3:?}" "${4:?}" ;;
    --self-test) CADDY_ACTION26E_SKIP_REGRESSION=true run_local_gates true ;;
    "") run_action ;;
    *) exit 64 ;;
esac
