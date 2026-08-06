#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry2_a
readonly executed_outer_sha256=6d89fa6fff1ad1bcdb3d627a877e2e34a01c1096f770a7342ad13adeb116b9e5
readonly complete_suite_sha256=e48e4eee63e7797e22a3d338099294490421eee89f5d7f45f0532afa5a36e9df
readonly suite_boundary_sha256=3a1bde08ec0813ed9c6773b310a828a2065643cf7cd69ad1049d6bf3ab372c95
readonly receiver_regression_sha256=4923a9495b6022e8e6dd17c1b816b64786e10e9d0732358734b5fc247df4947c
readonly action17q_regression_sha256=2286fbdc7db554725e1605a573f762a927afd7315fba1e503e277d8cf971887c
readonly action17q_retry_regression_sha256=02b349abc875f0321c3f816ec32df396b9288d045717383846cb91f50319c2ee
readonly action17q_b_inspector_sha256=ba1b49c0f01bf43c25b576d3740ea29f622a7644db016d7b9d6673897bd5f8b4
readonly action17q_b_runner_sha256=20822b4e02466727e57e6257aad03f13660cc9b1ec049146f482c42b6508eede
readonly action17q_b_regression_sha256=0bb7e0a6eb586be85b2e64fd697dee0ab5001c45814cf05e6d724e056fc661a7
readonly collision_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly conditional_sha256=68cd687916f9d8be78f50af7a410d376f457ca74ab906a8e459795de6c495455
readonly output_evidence_sha256=84873a1ad3ee1745fe445f179f6a002c2ccee5b147b93cc3db0d6f17d54d4441
readonly maximum_stream_bytes=4194304
readonly maximum_stream_lines=16384

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly executed_outer=$script_directory/run-dual-node-caddy-vrrp-activation-action20d-retry2-outer.sh
readonly complete_suite=$caddy_root/tests/run.sh
readonly receiver_regression=$caddy_root/tests/receiver-finalization-protocol-v2-regression.sh
readonly action17q_regression=$caddy_root/tests/action17q-node-b-protocol-v2-install-regression.sh
readonly action17q_retry_regression=$caddy_root/tests/action17q-retry-node-b-protocol-v2-install-regression.sh
readonly action17q_b_inspector=$script_directory/inspect-node-b-protocol-v2-postinstall-action17q-b.sh
readonly action17q_b_runner=$script_directory/run-node-b-protocol-v2-postinstall-action17q-b.sh
readonly action17q_b_regression=$caddy_root/tests/action17q-b-node-b-postinstall-regression.sh
readonly collision=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$caddy_root/tests/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$caddy_root/tests/transaction-output-evidence-policy-regression.sh

declare -A observed_gate_statuses=()

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
require_hash() {
    local expected_source_hash=$1
    local inspected_source_path=$2

    [[ -f "$inspected_source_path" && ! -L "$inspected_source_path" ]] || return 1
    [[ "$(file_hash "$inspected_source_path")" = "$expected_source_hash" ]]
}
require_executable_source() {
    local expected_executable_hash=$1
    local executable_source_path=$2

    require_hash "$expected_executable_hash" "$executable_source_path" || return 1
    [[ -x "$executable_source_path" ]]
}
suite_boundary_hash() {
    sed -n '195,207p' "$complete_suite" | sha256sum | awk '{ print $1 }'
}
suite_boundary_exact() {
    [[ "$(suite_boundary_hash)" = "$suite_boundary_sha256" ]]
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
    run_gate executed_outer_hash require_hash "$executed_outer_sha256" "$executed_outer" || return 1
    run_gate complete_suite_hash require_hash "$complete_suite_sha256" "$complete_suite" || return 1
    run_gate suite_boundary_hash suite_boundary_exact || return 1
    run_gate receiver_regression_hash require_executable_source "$receiver_regression_sha256" "$receiver_regression" || return 1
    run_gate action17q_regression_hash require_executable_source "$action17q_regression_sha256" "$action17q_regression" || return 1
    run_gate action17q_retry_regression_hash require_executable_source "$action17q_retry_regression_sha256" "$action17q_retry_regression" || return 1
    run_gate action17q_b_inspector_hash require_executable_source "$action17q_b_inspector_sha256" "$action17q_b_inspector" || return 1
    run_gate action17q_b_runner_hash require_executable_source "$action17q_b_runner_sha256" "$action17q_b_runner" || return 1
    run_gate action17q_b_regression_hash require_executable_source "$action17q_b_regression_sha256" "$action17q_b_regression" || return 1
    run_gate collision_hash require_hash "$collision_sha256" "$collision" || return 1
    run_gate conditional_hash require_hash "$conditional_sha256" "$conditional" || return 1
    run_gate output_evidence_hash require_hash "$output_evidence_sha256" "$output_evidence" || return 1
    run_gate syntax /bin/bash -n "$receiver_regression" "$action17q_regression" \
        "$action17q_retry_regression" "$action17q_b_inspector" \
        "$action17q_b_runner" "$action17q_b_regression" "$0" || return 1
    run_gate collision_policy /bin/bash "$collision" "$receiver_regression" \
        "$action17q_regression" "$action17q_retry_regression" \
        "$action17q_b_inspector" "$action17q_b_runner" \
        "$action17q_b_regression" "$0" || return 1
    run_gate conditional_policy /bin/bash "$conditional" || return 1
    run_gate output_evidence_policy /bin/bash "$output_evidence" || return 1
}
safe_stream() {
    local classified_stream_path=$1

    [[ "$(wc -c <"$classified_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$classified_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$classified_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$classified_stream_path"
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
environment_name_hash() {
    env | sed 's/=.*//' | LC_ALL=C sort -u | sha256sum | awk '{ print $1 }'
}
repository_state_hash() {
    git status --porcelain=v1 --untracked-files=all | sha256sum | awk '{ print $1 }'
}
context_hash() {
    local context_repository_hash=$1

    {
        printf 'pwd=%s\n' "$PWD"
        printf 'physical_pwd=%s\n' "$(pwd -P)"
        printf 'user=%s\n' "$(id -un)"
        printf 'group=%s\n' "$(id -gn)"
        printf 'uid=%s\n' "$(id -u)"
        printf 'gid=%s\n' "$(id -g)"
        printf 'umask=%s\n' "$(umask)"
        printf 'path=%s\n' "$PATH"
        printf 'validation_container_present=%s\n' \
            "$([[ -v CADDY_VALIDATION_CONTAINER ]] && printf true || printf false)"
        printf 'environment_name_hash=%s\n' "$(environment_name_hash)"
        printf 'repository_state_hash=%s\n' "$context_repository_hash"
    } | sha256sum | awk '{ print $1 }'
}
capture_command() {
    local command_label=$1
    local command_path=$2
    local capture_root=$3
    shift 3
    local command_status=0
    local command_stdout=$capture_root/$command_label.stdout
    local command_stderr=$capture_root/$command_label.stderr

    : >"$command_stdout"
    : >"$command_stderr"
    chmod 0600 "$command_stdout" "$command_stderr"
    printf '%s_%s_invocation_mode=direct_shebang_exact_suite\n' "$prefix" "$command_label"
    printf '%s_%s_command_sha256=%s\n' "$prefix" "$command_label" "$(file_hash "$command_path")"
    "$command_path" "$@" >"$command_stdout" 2>"$command_stderr" || command_status=$?
    observed_gate_statuses["$command_label"]=$command_status
    emit_stream "${command_label}_stdout" "$command_stdout" || return 97
    emit_stream "${command_label}_stderr" "$command_stderr" || return 97
    printf '%s_%s_status=%s\n' "$prefix" "$command_label" "$command_status"
}
classify_result() {
    local receiver_status=${observed_gate_statuses[receiver_finalization]}
    local failure_count=0
    local result_label
    local gate_name

    for gate_name in receiver_finalization action17q_original action17q_retry \
        action17q_b_inspector action17q_b_runner_self \
        action17q_b_runner_contract action17q_b_regression; do
        if [[ "${observed_gate_statuses[$gate_name]}" -ne 0 ]]; then
            failure_count=$((failure_count + 1))
        fi
    done
    if [[ "$failure_count" -eq 0 ]]; then
        result_label=not_reproduced_in_narrow_sequence
    elif [[ "$failure_count" -gt 1 ]]; then
        result_label=multiple_boundary_failures_reproduced
    elif [[ "$receiver_status" -ne 0 ]]; then
        result_label=receiver_finalization_failure_reproduced
    else
        result_label=single_action17q_failure_reproduced
    fi
    printf '%s_failure_count=%s\n' "$prefix" "$failure_count"
    printf '%s_classification=%s\n' "$prefix" "$result_label"
}
run_diagnostic() {
    local receiver_command=$1
    local action17q_command=$2
    local action17q_retry_command=$3
    local inspector_command=$4
    local runner_command=$5
    local postinstall_regression_command=$6
    local diagnostic_root
    local cleanup_command
    local before_context
    local after_context
    local before_repository_state
    local after_repository_state
    local repository_drift=0

    diagnostic_root=$(mktemp -d /tmp/caddy-action20d-retry2-a-diagnostic.XXXXXX)
    chmod 0700 "$diagnostic_root"
    printf -v cleanup_command 'rm -rf -- %q' "$diagnostic_root"
    # Expand the escaped function-local path while it is still in scope.
    # shellcheck disable=SC2064
    trap "$cleanup_command" EXIT

    before_repository_state=$(repository_state_hash)
    before_context=$(context_hash "$before_repository_state")
    printf '%s_context_before_sha256=%s\n' "$prefix" "$before_context"
    printf '%s_working_directory=%s\n' "$prefix" "$PWD"
    printf '%s_physical_working_directory=%s\n' "$prefix" "$(pwd -P)"
    printf '%s_user=%s\n' "$prefix" "$(id -un)"
    printf '%s_group=%s\n' "$prefix" "$(id -gn)"
    printf '%s_umask=%s\n' "$prefix" "$(umask)"
    printf '%s_path=%s\n' "$prefix" "$PATH"
    printf '%s_validation_container_present=%s\n' "$prefix" \
        "$([[ -v CADDY_VALIDATION_CONTAINER ]] && printf true || printf false)"
    printf '%s_environment_name_sha256=%s\n' "$prefix" "$(environment_name_hash)"
    printf '%s_repository_state_before_sha256=%s\n' "$prefix" "$before_repository_state"

    capture_command receiver_finalization "$receiver_command" "$diagnostic_root" || return 97
    capture_command action17q_original "$action17q_command" "$diagnostic_root" --self-test || return 97
    capture_command action17q_retry "$action17q_retry_command" "$diagnostic_root" --self-test || return 97
    capture_command action17q_b_inspector "$inspector_command" "$diagnostic_root" --self-test || return 97
    capture_command action17q_b_runner_self "$runner_command" "$diagnostic_root" --self-test || return 97
    capture_command action17q_b_runner_contract "$runner_command" "$diagnostic_root" --contract-test || return 97
    capture_command action17q_b_regression "$postinstall_regression_command" "$diagnostic_root" --self-test || return 97

    classify_result
    after_repository_state=$(repository_state_hash)
    after_context=$(context_hash "$after_repository_state")
    printf '%s_context_after_sha256=%s\n' "$prefix" "$after_context"
    printf '%s_repository_state_after_sha256=%s\n' "$prefix" "$after_repository_state"
    if [[ "$before_context" = "$after_context" ]]; then
        printf '%s_context_unchanged=true\n' "$prefix"
    else
        printf '%s_context_unchanged=false\n' "$prefix"
    fi
    if [[ "$before_repository_state" = "$after_repository_state" ]]; then
        printf '%s_repository_state_unchanged=true\n' "$prefix"
        printf '%s_repository_mutations=false\n' "$prefix"
    else
        printf '%s_repository_state_unchanged=false\n' "$prefix"
        printf '%s_repository_mutations=true\n' "$prefix"
        repository_drift=1
    fi
    printf '%s_podman_invoked=false\n' "$prefix"
    printf '%s_node_contact=false\n' "$prefix"
    printf '%s_readiness_invoked=false\n' "$prefix"
    printf '%s_activation_invoked=false\n' "$prefix"
    printf '%s_live_mutations=false\n' "$prefix"
    rm -rf -- "$diagnostic_root"
    trap - EXIT
    printf '%s_cleanup_complete=true\n' "$prefix"
    printf '%s_diagnostic_complete=true\n' "$prefix"
    return "$repository_drift"
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        printf '%s\n' working_directory executed_outer_hash complete_suite_hash \
            suite_boundary_hash receiver_regression_hash action17q_regression_hash \
            action17q_retry_regression_hash action17q_b_inspector_hash \
            action17q_b_runner_hash action17q_b_regression_hash collision_hash \
            conditional_hash output_evidence_hash syntax collision_policy \
            conditional_policy output_evidence_policy
        exit 0
        ;;
    --production-path-test)
        [[ $# -eq 7 ]] || exit 64
        run_diagnostic "$2" "$3" "$4" "$5" "$6" "$7"
        exit
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates
        printf '%s_outer_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--production-path-test RECEIVER ACTION17Q ACTION17Q_RETRY INSPECTOR RUNNER POSTINSTALL_REGRESSION|--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

run_local_gates
run_diagnostic "$receiver_regression" "$action17q_regression" \
    "$action17q_retry_regression" "$action17q_b_inspector" \
    "$action17q_b_runner" "$action17q_b_regression"
