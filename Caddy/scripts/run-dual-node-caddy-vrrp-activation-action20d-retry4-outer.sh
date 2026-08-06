#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry4
readonly complete_suite_sha256=96796968d68081aa183cb8142c952a0378e8653383a74dfe13038f7e771efd8c
readonly integration_suite_sha256=f3da2b630e909e85acbc05fceccd25ca6f418b44d0bfa4e485ca7f04c4447727
readonly correction_boundary_sha256=82f02ae0e98aaff984c3a377857c235992d8fdbb6db87c33f6af799aa98d491e
readonly readiness_outer_sha256=b7e1db77b4889a62d782a0331922f326edd73c87e13a42952441ad7fe9ce9f20
readonly activation_outer_sha256=085eff6386210d36a97682b86c90670b4b42cc249132b4f57dcae0ca5b7018d5
readonly regression_sha256=a3782acd9bf546118a1d2e69a88c47cf877066593fd6d2067b463d07ae306be3
readonly collision_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly conditional_sha256=68cd687916f9d8be78f50af7a410d376f457ca74ab906a8e459795de6c495455
readonly output_evidence_sha256=84873a1ad3ee1745fe445f179f6a002c2ccee5b147b93cc3db0d6f17d54d4441
readonly maximum_stream_bytes=16777216
readonly maximum_stream_lines=65536

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly complete_suite=$caddy_root/tests/run.sh
readonly integration_suite=$caddy_root/tests/integration.sh
readonly correction_boundary=$caddy_root/tests/action20d-retry3-a-retry-stale-suite-hash-boundary.sh
readonly readiness_outer=$script_directory/run-dual-node-caddy-notifier-context-action20d-c-retry-outer.sh
readonly activation_outer=$script_directory/run-dual-node-caddy-vrrp-activation-action20d-retry-outer.sh
readonly regression=$caddy_root/tests/action20d-retry4-activation-boundary-regression.sh
readonly collision=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$caddy_root/tests/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$caddy_root/tests/transaction-output-evidence-policy-regression.sh

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
    local expected_source_hash=$1
    local inspected_source_path=$2

    [[ -f "$inspected_source_path" && ! -L "$inspected_source_path" ]] || return 1
    [[ "$(file_hash "$inspected_source_path")" = "$expected_source_hash" ]] || return 1
    return 0
}

correction_wiring_exact() {
    # The dollar-prefixed names are literal suite source.
    # shellcheck disable=SC2016
    local expected_call='"$caddy_root/tests/action20d-retry3-a-retry-stale-suite-hash-boundary.sh"'
    # shellcheck disable=SC2016
    local expected_focused_call='"$caddy_root/tests/action20d-retry4-focused-validation.sh"'

    [[ "$(grep -Fxc "$expected_call" "$complete_suite")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc "$expected_call" "$integration_suite")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc "$expected_focused_call" "$complete_suite")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc "$expected_focused_call" "$integration_suite")" -eq 1 ]] || return 1
    # The dollar-prefixed names are literal historical suite source.
    # shellcheck disable=SC2016
    ! grep -Fq '"$caddy_root/tests/action17q-node-b-protocol-v2-install-regression.sh"' \
        "$complete_suite" "$integration_suite" || return 1
    # shellcheck disable=SC2016
    ! grep -Fq '"$caddy_root/tests/action17q-retry-node-b-protocol-v2-install-regression.sh"' \
        "$complete_suite" "$integration_suite" || return 1
    return 0
}

run_gate() {
    local local_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_outer_gate_%s=true\n' "$prefix" "$local_gate_label"
        return 0
    fi
    printf '%s_outer_gate_%s=false\n' "$prefix" "$local_gate_label" >&2
    return 1
}

run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate complete_suite_hash require_hash "$complete_suite_sha256" "$complete_suite" || return 1
    run_gate integration_suite_hash require_hash "$integration_suite_sha256" "$integration_suite" || return 1
    run_gate correction_boundary_hash require_hash "$correction_boundary_sha256" "$correction_boundary" || return 1
    run_gate correction_wiring correction_wiring_exact || return 1
    run_gate readiness_outer_hash require_hash "$readiness_outer_sha256" "$readiness_outer" || return 1
    run_gate activation_outer_hash require_hash "$activation_outer_sha256" "$activation_outer" || return 1
    run_gate regression_hash require_hash "$regression_sha256" "$regression" || return 1
    run_gate collision_hash require_hash "$collision_sha256" "$collision" || return 1
    run_gate conditional_hash require_hash "$conditional_sha256" "$conditional" || return 1
    run_gate output_evidence_hash require_hash "$output_evidence_sha256" "$output_evidence" || return 1
    run_gate syntax /bin/bash -n "$complete_suite" "$integration_suite" \
        "$correction_boundary" "$readiness_outer" "$activation_outer" \
        "$regression" "$0" || return 1
    run_gate collision_policy /bin/bash "$collision" "$correction_boundary" \
        "$readiness_outer" "$activation_outer" "$regression" "$0" || return 1
    run_gate conditional_policy /bin/bash "$conditional" || return 1
    run_gate output_evidence_policy /bin/bash "$output_evidence" || return 1
    run_gate readiness_outer_self_test /bin/bash "$readiness_outer" --self-test || return 1
    run_gate activation_outer_self_test /bin/bash "$activation_outer" --self-test || return 1
    run_gate regression /bin/bash "$regression" || return 1
}

safe_stream() {
    local classified_stream_path=$1

    [[ "$(wc -c <"$classified_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$classified_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$classified_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$classified_stream_path" || return 1
    return 0
}

emit_stream() {
    local stream_label=$1
    local stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_label" "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_label" "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_label" "$(file_hash "$stream_path")"
    if ! safe_stream "$stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$stream_label"
    if [[ -s "$stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$stream_label"
        cat "$stream_path"
        printf '%s_%s_end\n' "$prefix" "$stream_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$stream_label"
    fi
}

run_captured_gate() {
    local boundary_gate_name=$1
    local boundary_gate_command=$2
    local boundary_capture_root=$3
    local boundary_gate_status=0
    local boundary_stdout=$boundary_capture_root/$boundary_gate_name.stdout
    local boundary_stderr=$boundary_capture_root/$boundary_gate_name.stderr

    : >"$boundary_stdout"
    : >"$boundary_stderr"
    chmod 0600 "$boundary_stdout" "$boundary_stderr"
    /bin/bash "$boundary_gate_command" >"$boundary_stdout" 2>"$boundary_stderr" ||
        boundary_gate_status=$?
    emit_stream "${boundary_gate_name}_stdout" "$boundary_stdout" || return 97
    emit_stream "${boundary_gate_name}_stderr" "$boundary_stderr" || return 97
    printf '%s_%s_status=%s\n' "$prefix" "$boundary_gate_name" "$boundary_gate_status"
    return "$boundary_gate_status"
}

run_boundary() {
    local suite_command=$1
    local readiness_command=$2
    local activation_command=$3
    local boundary_root
    local suite_status=0
    local readiness_status=0
    local activation_status=0
    local cleanup_command

    boundary_root=$(mktemp -d /tmp/caddy-action20d-retry4-boundary.XXXXXX)
    chmod 0700 "$boundary_root"
    printf -v cleanup_command 'rm -rf -- %q' "$boundary_root"
    # Expand the escaped function-local path now so EXIT cleanup remains valid.
    # shellcheck disable=SC2064
    trap "$cleanup_command" EXIT

    run_captured_gate complete_suite "$suite_command" "$boundary_root" || suite_status=$?
    if [[ "$suite_status" -ne 0 ]]; then
        printf '%s_readiness_invoked=false\n' "$prefix"
        printf '%s_activation_invoked=false\n' "$prefix"
        printf '%s_boundary_accepted=false\n' "$prefix"
        if [[ "$suite_status" -eq 97 ]]; then
            trap - EXIT
            printf '%s_protected_evidence=%s\n' "$prefix" "$boundary_root" >&2
        fi
        return "$suite_status"
    fi
    printf '%s_complete_suite_accepted=true\n' "$prefix"

    run_captured_gate readiness "$readiness_command" "$boundary_root" || readiness_status=$?
    if [[ "$readiness_status" -ne 0 ]]; then
        printf '%s_activation_invoked=false\n' "$prefix"
        printf '%s_boundary_accepted=false\n' "$prefix"
        if [[ "$readiness_status" -eq 97 ]]; then
            trap - EXIT
            printf '%s_protected_evidence=%s\n' "$prefix" "$boundary_root" >&2
        fi
        return "$readiness_status"
    fi
    printf '%s_readiness_accepted=true\n' "$prefix"

    run_captured_gate activation "$activation_command" "$boundary_root" || activation_status=$?
    if [[ "$activation_status" -ne 0 ]]; then
        printf '%s_boundary_accepted=false\n' "$prefix"
        if [[ "$activation_status" -eq 97 ]]; then
            trap - EXIT
            printf '%s_protected_evidence=%s\n' "$prefix" "$boundary_root" >&2
        fi
        return "$activation_status"
    fi
    printf '%s_activation_accepted=true\n' "$prefix"

    rm -rf -- "$boundary_root"
    trap - EXIT
    printf '%s_boundary_cleanup_complete=true\n' "$prefix"
    printf '%s_boundary_accepted=true\n' "$prefix"
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        printf '%s\n' working_directory complete_suite_hash integration_suite_hash \
            correction_boundary_hash correction_wiring readiness_outer_hash \
            activation_outer_hash regression_hash collision_hash conditional_hash \
            output_evidence_hash syntax collision_policy conditional_policy \
            output_evidence_policy \
            readiness_outer_self_test activation_outer_self_test regression
        exit 0
        ;;
    --production-path-test)
        [[ $# -eq 4 ]] || exit 64
        run_boundary "$2" "$3" "$4"
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates
        printf '%s_outer_%s_complete=true\n' "$prefix" "${1#--}"
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        run_local_gates
        run_boundary "$complete_suite" "$readiness_outer" "$activation_outer"
        ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--production-path-test SUITE READINESS ACTIVATION|--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac
