#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry3_a_stale_hash_boundary
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096
readonly retry2_validator_sha256=3a5ddbcb85b307e61511fe8a9d69752df28b0c3650bd842bc7c1036f847e93df
readonly retry2_outer_sha256=6d89fa6fff1ad1bcdb3d627a877e2e34a01c1096f770a7342ad13adeb116b9e5
readonly retry3_validator_sha256=5d4cefc8f6c79067dd312e7b5f05da1b489f5f690f8ef7100113c9f321d89fa3
readonly retry3_outer_sha256=0f378ae8638374b7a88a8b64ba93bc3f65bebe925bc5802dbb108393fe4abe7a
readonly retry2_stale_complete_sha256=7393ef594f00839d0366b4d9415b04ed76378046e89cb50c2828877ae2b1a21d
readonly retry2_stale_integration_sha256=18acefaef2da1f0cbcff01b1c598344c11aa6a3caf12d017c1847842c74a2e73
readonly retry3_stale_complete_sha256=aba6f8bea4c0a5247cfa08bacf4e85e6dd3b92126dbf69be6f360ed36465bbd2
readonly retry3_stale_integration_sha256=cc1aa4e8873d680fbf144a51eceae921c6b56dd25d534edacde276fadcc8ff8e
readonly current_complete_sha256=a18ede910692dc8a695a214695c4ce8da5d02219854d325400ac50e23d045d0e
readonly current_integration_sha256=556ebdb878ff46e1d18b7e50224e02e8ce715625de1899b725373d28739f8df0
readonly retry2_stdout_sha256=918a705790cbadffe0c794e823955dca8bea962999a81be505b30ccd60b50f71
readonly retry2_stderr_sha256=706ca79b2ae7cc4516e4389fece806317b42b638fbc9aa395d4cef38de63b128
readonly retry3_stdout_sha256=16532004e5dde4585e326ae9df696ddde1ee6a8a940f490c0acd45279584c2f8
readonly retry3_stderr_sha256=53c23a82edf5aef4e2864dcc434647a0940af120bca231930677aac230ef8839

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly retry2_validator=$script_directory/action20d-retry2-focused-validation.sh
readonly retry2_outer=$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-retry2-outer.sh
readonly retry3_validator=$script_directory/action20d-retry3-focused-validation.sh
readonly retry3_outer=$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-retry3-outer.sh
readonly complete_suite=$script_directory/run.sh
readonly integration_suite=$script_directory/integration.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }

same_value() { [[ "$1" = "$2" ]]; }
different_value() { [[ "$1" != "$2" ]]; }
regular_file() { [[ -f "$1" && ! -L "$1" ]]; }
executable_file() { [[ -x "$1" ]]; }
exact_line_once() { [[ "$(grep -Fxc "$1" "$2")" -eq 1 ]]; }

record_assertion() {
    local assertion_label=$1

    shift
    if "$@"; then
        printf '%s_%s=true\n' "$prefix" "$assertion_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$assertion_label" >&2
    return 1
}

safe_stream() {
    local inspected_stream_path=$1

    [[ "$(wc -c <"$inspected_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$inspected_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$inspected_stream_path"
}

emit_stream() {
    local emitted_stream_label=$1
    local emitted_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$emitted_stream_label" \
        "$(wc -c <"$emitted_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$emitted_stream_label" \
        "$(line_count "$emitted_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$emitted_stream_label" \
        "$(file_hash "$emitted_stream_path")"
    if ! safe_stream "$emitted_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' \
            "$prefix" "$emitted_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$emitted_stream_label"
    if [[ -s "$emitted_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$emitted_stream_label"
        cat "$emitted_stream_path"
        printf '%s_%s_end\n' "$prefix" "$emitted_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$emitted_stream_label"
    fi
}

write_retry2_expected() {
    local expected_stdout_path=$1
    local expected_stderr_path=$2

    printf '%s\n' \
        action_20d_retry2_focused_syntax=true \
        action_20d_retry2_focused_shellcheck=true \
        action_20d_retry2_focused_canonical_format=true \
        action_20d_retry2_focused_collision_policy=true \
        action_20d_retry2_focused_conditional_policy=true \
        action_20d_retry2_focused_output_evidence_policy=true \
        action_20d_retry2_focused_readiness_outer_immutable=true \
        action_20d_retry2_focused_activation_outer_immutable=true \
        action_20d_retry2_focused_production_boundary_regression=true \
        >"$expected_stdout_path"
    printf '%s\n' \
        action_20d_retry2_outer_gate_complete_suite_hash=false \
        action_20d_retry2_focused_outer_self_test=false \
        >"$expected_stderr_path"
}

write_retry3_expected() {
    local expected_stdout_path=$1
    local expected_stderr_path=$2

    printf '%s\n' \
        action_20d_retry3_focused_syntax=true \
        action_20d_retry3_focused_shellcheck=true \
        action_20d_retry3_focused_canonical_format=true \
        action_20d_retry3_focused_collision_policy=true \
        action_20d_retry3_focused_conditional_policy=true \
        action_20d_retry3_focused_output_evidence_policy=true \
        >"$expected_stdout_path"
    printf '%s\n' \
        action_20d_retry3_focused_complete_suite_exact=false \
        >"$expected_stderr_path"
}

run_validator() {
    local validator_label=$1
    local validator_path=$2
    local expected_stdout_hash=$3
    local expected_stderr_hash=$4
    local validator_capture_root=$5
    local validator_stdout_path=$validator_capture_root/$validator_label.stdout
    local validator_stderr_path=$validator_capture_root/$validator_label.stderr
    local expected_stdout_path=$validator_capture_root/$validator_label.expected.stdout
    local expected_stderr_path=$validator_capture_root/$validator_label.expected.stderr
    local validator_exit_status=0
    local validator_failure_count=0

    : >"$validator_stdout_path"
    : >"$validator_stderr_path"
    : >"$expected_stdout_path"
    : >"$expected_stderr_path"
    chmod 0600 "$validator_stdout_path" "$validator_stderr_path" \
        "$expected_stdout_path" "$expected_stderr_path"

    if [[ "$validator_label" = retry2 ]]; then
        write_retry2_expected "$expected_stdout_path" "$expected_stderr_path"
    elif [[ "$validator_label" = retry3 ]]; then
        write_retry3_expected "$expected_stdout_path" "$expected_stderr_path"
    else
        printf '%s_%s_label_valid=false\n' "$prefix" "$validator_label" >&2
        return 64
    fi

    /bin/bash "$validator_path" >"$validator_stdout_path" \
        2>"$validator_stderr_path" || validator_exit_status=$?

    printf '%s_%s_status=%s\n' "$prefix" "$validator_label" "$validator_exit_status"
    emit_stream "${validator_label}_stdout" "$validator_stdout_path" || return 97
    emit_stream "${validator_label}_stderr" "$validator_stderr_path" || return 97

    record_assertion "${validator_label}_status_expected" \
        same_value "$validator_exit_status" 1 || validator_failure_count=$((validator_failure_count + 1))
    record_assertion "${validator_label}_stdout_hash_exact" \
        same_value "$(file_hash "$validator_stdout_path")" "$expected_stdout_hash" || validator_failure_count=$((validator_failure_count + 1))
    record_assertion "${validator_label}_stderr_hash_exact" \
        same_value "$(file_hash "$validator_stderr_path")" "$expected_stderr_hash" || validator_failure_count=$((validator_failure_count + 1))
    record_assertion "${validator_label}_stdout_content_exact" \
        cmp -s "$validator_stdout_path" "$expected_stdout_path" || validator_failure_count=$((validator_failure_count + 1))
    record_assertion "${validator_label}_stderr_content_exact" \
        cmp -s "$validator_stderr_path" "$expected_stderr_path" || validator_failure_count=$((validator_failure_count + 1))
    record_assertion "${validator_label}_stdout_no_false" \
        test "$(grep -Ec '=false$' "$validator_stdout_path")" -eq 0 || validator_failure_count=$((validator_failure_count + 1))
    record_assertion "${validator_label}_expected_failure_count" \
        test "$(grep -Ec '=false$' "$validator_stderr_path")" -eq "$([[ "$validator_label" = retry2 ]] && printf 2 || printf 1)" || validator_failure_count=$((validator_failure_count + 1))

    printf '%s_%s_failed_assertions=%s\n' \
        "$prefix" "$validator_label" "$validator_failure_count"
    [[ "$validator_failure_count" -eq 0 ]]
}

validate_source_contract() {
    local inspected_retry2_validator=$1
    local expected_retry2_validator_hash=$2
    local inspected_retry2_outer=$3
    local expected_retry2_outer_hash=$4
    local inspected_retry3_validator=$5
    local expected_retry3_validator_hash=$6
    local inspected_retry3_outer=$7
    local expected_retry3_outer_hash=$8
    local inspected_complete_suite=$9
    local expected_complete_hash=${10}
    local inspected_integration_suite=${11}
    local expected_integration_hash=${12}
    local source_failure_count=0

    record_assertion retry2_validator_regular regular_file "$inspected_retry2_validator" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry2_validator_executable executable_file "$inspected_retry2_validator" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry2_validator_hash_exact same_value "$(file_hash "$inspected_retry2_validator")" "$expected_retry2_validator_hash" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry2_outer_regular regular_file "$inspected_retry2_outer" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry2_outer_executable executable_file "$inspected_retry2_outer" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry2_outer_hash_exact same_value "$(file_hash "$inspected_retry2_outer")" "$expected_retry2_outer_hash" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry3_validator_regular regular_file "$inspected_retry3_validator" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry3_validator_executable executable_file "$inspected_retry3_validator" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry3_validator_hash_exact same_value "$(file_hash "$inspected_retry3_validator")" "$expected_retry3_validator_hash" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry3_outer_regular regular_file "$inspected_retry3_outer" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry3_outer_executable executable_file "$inspected_retry3_outer" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry3_outer_hash_exact same_value "$(file_hash "$inspected_retry3_outer")" "$expected_retry3_outer_hash" || source_failure_count=$((source_failure_count + 1))
    record_assertion complete_suite_regular regular_file "$inspected_complete_suite" || source_failure_count=$((source_failure_count + 1))
    record_assertion complete_suite_hash_exact same_value "$(file_hash "$inspected_complete_suite")" "$expected_complete_hash" || source_failure_count=$((source_failure_count + 1))
    record_assertion integration_suite_regular regular_file "$inspected_integration_suite" || source_failure_count=$((source_failure_count + 1))
    record_assertion integration_suite_hash_exact same_value "$(file_hash "$inspected_integration_suite")" "$expected_integration_hash" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry2_complete_pin_exact exact_line_once \
        "readonly complete_suite_sha256=$retry2_stale_complete_sha256" "$inspected_retry2_outer" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry2_integration_pin_exact exact_line_once \
        "readonly integration_suite_sha256=$retry2_stale_integration_sha256" "$inspected_retry2_outer" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry3_complete_pin_exact exact_line_once \
        "readonly complete_suite_sha256=$retry3_stale_complete_sha256" "$inspected_retry3_outer" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry3_integration_pin_exact exact_line_once \
        "readonly integration_suite_sha256=$retry3_stale_integration_sha256" "$inspected_retry3_outer" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry2_complete_pin_stale different_value "$expected_complete_hash" "$retry2_stale_complete_sha256" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry2_integration_pin_stale different_value "$expected_integration_hash" "$retry2_stale_integration_sha256" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry3_complete_pin_stale different_value "$expected_complete_hash" "$retry3_stale_complete_sha256" || source_failure_count=$((source_failure_count + 1))
    record_assertion retry3_integration_pin_stale different_value "$expected_integration_hash" "$retry3_stale_integration_sha256" || source_failure_count=$((source_failure_count + 1))

    printf '%s_source_failed_assertions=%s\n' "$prefix" "$source_failure_count"
    [[ "$source_failure_count" -eq 0 ]]
}

run_boundary() {
    local boundary_retry2_validator=$1
    local boundary_retry2_validator_hash=$2
    local boundary_retry2_outer=$3
    local boundary_retry2_outer_hash=$4
    local boundary_retry3_validator=$5
    local boundary_retry3_validator_hash=$6
    local boundary_retry3_outer=$7
    local boundary_retry3_outer_hash=$8
    local boundary_complete_suite=$9
    local boundary_complete_hash=${10}
    local boundary_integration_suite=${11}
    local boundary_integration_hash=${12}
    local boundary_capture_root
    local cleanup_command
    local boundary_failure_count=0

    boundary_capture_root=$(mktemp -d /tmp/caddy-action20d-retry3-a-boundary.XXXXXX)
    chmod 0700 "$boundary_capture_root"
    printf -v cleanup_command 'rm -rf -- %q' "$boundary_capture_root"
    # Expand the escaped function-local path while it remains in scope.
    # shellcheck disable=SC2064
    trap "$cleanup_command" EXIT

    validate_source_contract \
        "$boundary_retry2_validator" "$boundary_retry2_validator_hash" \
        "$boundary_retry2_outer" "$boundary_retry2_outer_hash" \
        "$boundary_retry3_validator" "$boundary_retry3_validator_hash" \
        "$boundary_retry3_outer" "$boundary_retry3_outer_hash" \
        "$boundary_complete_suite" "$boundary_complete_hash" \
        "$boundary_integration_suite" "$boundary_integration_hash" || boundary_failure_count=$((boundary_failure_count + 1))

    run_validator retry2 "$boundary_retry2_validator" \
        "$retry2_stdout_sha256" "$retry2_stderr_sha256" \
        "$boundary_capture_root" || boundary_failure_count=$((boundary_failure_count + 1))
    run_validator retry3 "$boundary_retry3_validator" \
        "$retry3_stdout_sha256" "$retry3_stderr_sha256" \
        "$boundary_capture_root" || boundary_failure_count=$((boundary_failure_count + 1))

    printf '%s_failure_count=%s\n' "$prefix" "$boundary_failure_count"
    printf '%s_historical_artifacts_modified=false\n' "$prefix"
    printf '%s_complete_suite_invoked=false\n' "$prefix"
    printf '%s_podman_invoked=false\n' "$prefix"
    printf '%s_node_contact=false\n' "$prefix"
    printf '%s_readiness_invoked=false\n' "$prefix"
    printf '%s_activation_invoked=false\n' "$prefix"
    printf '%s_live_mutations=false\n' "$prefix"

    rm -rf -- "$boundary_capture_root"
    trap - EXIT
    printf '%s_cleanup_complete=true\n' "$prefix"
    if [[ "$boundary_failure_count" -eq 0 ]]; then
        printf '%s_complete=true\n' "$prefix"
        return 0
    fi
    printf '%s_complete=false\n' "$prefix" >&2
    return 1
}

case "${1:-}" in
    --production-path-test)
        [[ $# -eq 13 ]] || exit 64
        run_boundary "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" \
            "${10}" "${11}" "${12}" "${13}"
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        validate_source_contract \
            "$retry2_validator" "$retry2_validator_sha256" \
            "$retry2_outer" "$retry2_outer_sha256" \
            "$retry3_validator" "$retry3_validator_sha256" \
            "$retry3_outer" "$retry3_outer_sha256" \
            "$complete_suite" "$current_complete_sha256" \
            "$integration_suite" "$current_integration_sha256"
        /bin/bash -n "$retry2_validator" "$retry2_outer" \
            "$retry3_validator" "$retry3_outer" "$0"
        printf '%s_%s_complete=true\n' "$prefix" "${1#--}"
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        run_boundary \
            "$retry2_validator" "$retry2_validator_sha256" \
            "$retry2_outer" "$retry2_outer_sha256" \
            "$retry3_validator" "$retry3_validator_sha256" \
            "$retry3_outer" "$retry3_outer_sha256" \
            "$complete_suite" "$current_complete_sha256" \
            "$integration_suite" "$current_integration_sha256"
        ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test|--production-path-test RETRY2_VALIDATOR RETRY2_VALIDATOR_SHA256 RETRY2_OUTER RETRY2_OUTER_SHA256 RETRY3_VALIDATOR RETRY3_VALIDATOR_SHA256 RETRY3_OUTER RETRY3_OUTER_SHA256 COMPLETE COMPLETE_SHA256 INTEGRATION INTEGRATION_SHA256]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac
