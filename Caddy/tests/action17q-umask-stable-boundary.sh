#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_17q_umask_boundary
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096
readonly original_source_sha256=2286fbdc7db554725e1605a573f762a927afd7315fba1e503e277d8cf971887c
readonly original_stdout_sha256=a4a00068b72ee74a716391b9bc471fa5f58e6d91ae0fe9ea806af19c4387c151
readonly retry_source_sha256=02b349abc875f0321c3f816ec32df396b9288d045717383846cb91f50319c2ee
readonly retry_stdout_sha256=dbffee4763e1a39b79428b84ae5c427d4a62097d204583272e3b9d5142e6561d

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly original_regression=$script_directory/action17q-node-b-protocol-v2-install-regression.sh
readonly retry_regression=$script_directory/action17q-retry-node-b-protocol-v2-install-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }

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
    local emitted_label=$1
    local emitted_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$emitted_label" \
        "$(wc -c <"$emitted_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$emitted_label" \
        "$(line_count "$emitted_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$emitted_label" \
        "$(file_hash "$emitted_stream_path")"
    if ! safe_stream "$emitted_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$emitted_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$emitted_label"
    if [[ -s "$emitted_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$emitted_label"
        cat "$emitted_stream_path"
        printf '%s_%s_end\n' "$prefix" "$emitted_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$emitted_label"
    fi
}

run_invocation() {
    local invocation_label=$1
    local invocation_mode=$2
    local invoked_source_path=$3
    local expected_invocation_stdout_sha256=$4
    local invocation_capture_root=$5
    local invocation_stdout=$invocation_capture_root/$invocation_label.stdout
    local invocation_stderr=$invocation_capture_root/$invocation_label.stderr
    local invocation_status=0
    local invocation_accepted=true

    : >"$invocation_stdout"
    : >"$invocation_stderr"
    chmod 0600 "$invocation_stdout" "$invocation_stderr"

    if [[ "$invocation_mode" = direct_shebang ]]; then
        (umask 0022 && "$invoked_source_path" --self-test) \
            >"$invocation_stdout" 2>"$invocation_stderr" || invocation_status=$?
    elif [[ "$invocation_mode" = explicit_bash ]]; then
        (umask 0022 && /bin/bash "$invoked_source_path" --self-test) \
            >"$invocation_stdout" 2>"$invocation_stderr" || invocation_status=$?
    else
        printf '%s_%s_mode_valid=false\n' "$prefix" "$invocation_label" >&2
        return 64
    fi

    printf '%s_%s_mode=%s\n' "$prefix" "$invocation_label" "$invocation_mode"
    printf '%s_%s_status=%s\n' "$prefix" "$invocation_label" "$invocation_status"
    emit_stream "${invocation_label}_stdout" "$invocation_stdout" || return 97
    emit_stream "${invocation_label}_stderr" "$invocation_stderr" || return 97

    if [[ "$invocation_status" -eq 0 ]]; then
        printf '%s_%s_status_zero=true\n' "$prefix" "$invocation_label"
    else
        printf '%s_%s_status_zero=false\n' "$prefix" "$invocation_label"
        invocation_accepted=false
    fi
    if [[ ! -s "$invocation_stderr" ]]; then
        printf '%s_%s_stderr_empty=true\n' "$prefix" "$invocation_label"
    else
        printf '%s_%s_stderr_empty=false\n' "$prefix" "$invocation_label"
        invocation_accepted=false
    fi
    if [[ "$(file_hash "$invocation_stdout")" = "$expected_invocation_stdout_sha256" ]]; then
        printf '%s_%s_stdout_exact=true\n' "$prefix" "$invocation_label"
    else
        printf '%s_%s_stdout_exact=false\n' "$prefix" "$invocation_label"
        invocation_accepted=false
    fi
    printf '%s_%s_accepted=%s\n' "$prefix" "$invocation_label" "$invocation_accepted"
    [[ "$invocation_accepted" = true ]]
}

run_boundary() {
    local boundary_original_path=$1
    local boundary_original_source_sha256=$2
    local boundary_original_stdout_sha256=$3
    local boundary_retry_path=$4
    local boundary_retry_source_sha256=$5
    local boundary_retry_stdout_sha256=$6
    local boundary_capture_root
    local cleanup_command
    local failure_count=0
    local before_umask
    local after_umask

    boundary_capture_root=$(mktemp -d /tmp/caddy-action17q-umask-boundary.XXXXXX)
    chmod 0700 "$boundary_capture_root"
    printf -v cleanup_command 'rm -rf -- %q' "$boundary_capture_root"
    # Expand the escaped function-local path while it remains in scope.
    # shellcheck disable=SC2064
    trap "$cleanup_command" EXIT

    before_umask=$(umask)
    printf '%s_outer_umask_before=%s\n' "$prefix" "$before_umask"
    if [[ "$before_umask" = 0077 ]]; then
        printf '%s_outer_umask_before_exact=true\n' "$prefix"
    else
        printf '%s_outer_umask_before_exact=false\n' "$prefix"
        failure_count=$((failure_count + 1))
    fi

    if [[ -f "$boundary_original_path" && ! -L "$boundary_original_path" ]]; then
        printf '%s_original_source_regular=true\n' "$prefix"
    else
        printf '%s_original_source_regular=false\n' "$prefix"
        failure_count=$((failure_count + 1))
    fi
    if [[ -x "$boundary_original_path" ]]; then
        printf '%s_original_source_executable=true\n' "$prefix"
    else
        printf '%s_original_source_executable=false\n' "$prefix"
        failure_count=$((failure_count + 1))
    fi
    if [[ "$(file_hash "$boundary_original_path")" = "$boundary_original_source_sha256" ]]; then
        printf '%s_original_source_hash_exact=true\n' "$prefix"
    else
        printf '%s_original_source_hash_exact=false\n' "$prefix"
        failure_count=$((failure_count + 1))
    fi
    if [[ -f "$boundary_retry_path" && ! -L "$boundary_retry_path" ]]; then
        printf '%s_retry_source_regular=true\n' "$prefix"
    else
        printf '%s_retry_source_regular=false\n' "$prefix"
        failure_count=$((failure_count + 1))
    fi
    if [[ -x "$boundary_retry_path" ]]; then
        printf '%s_retry_source_executable=true\n' "$prefix"
    else
        printf '%s_retry_source_executable=false\n' "$prefix"
        failure_count=$((failure_count + 1))
    fi
    if [[ "$(file_hash "$boundary_retry_path")" = "$boundary_retry_source_sha256" ]]; then
        printf '%s_retry_source_hash_exact=true\n' "$prefix"
    else
        printf '%s_retry_source_hash_exact=false\n' "$prefix"
        failure_count=$((failure_count + 1))
    fi

    run_invocation original_direct direct_shebang "$boundary_original_path" \
        "$boundary_original_stdout_sha256" "$boundary_capture_root" || failure_count=$((failure_count + 1))
    run_invocation original_bash explicit_bash "$boundary_original_path" \
        "$boundary_original_stdout_sha256" "$boundary_capture_root" || failure_count=$((failure_count + 1))
    run_invocation retry_direct direct_shebang "$boundary_retry_path" \
        "$boundary_retry_stdout_sha256" "$boundary_capture_root" || failure_count=$((failure_count + 1))
    run_invocation retry_bash explicit_bash "$boundary_retry_path" \
        "$boundary_retry_stdout_sha256" "$boundary_capture_root" || failure_count=$((failure_count + 1))

    if cmp -s "$boundary_capture_root/original_direct.stdout" \
        "$boundary_capture_root/original_bash.stdout"; then
        printf '%s_original_invocation_stdout_equal=true\n' "$prefix"
    else
        printf '%s_original_invocation_stdout_equal=false\n' "$prefix"
        failure_count=$((failure_count + 1))
    fi
    if cmp -s "$boundary_capture_root/retry_direct.stdout" \
        "$boundary_capture_root/retry_bash.stdout"; then
        printf '%s_retry_invocation_stdout_equal=true\n' "$prefix"
    else
        printf '%s_retry_invocation_stdout_equal=false\n' "$prefix"
        failure_count=$((failure_count + 1))
    fi

    after_umask=$(umask)
    printf '%s_outer_umask_after=%s\n' "$prefix" "$after_umask"
    if [[ "$after_umask" = "$before_umask" ]]; then
        printf '%s_outer_umask_restored=true\n' "$prefix"
    else
        printf '%s_outer_umask_restored=false\n' "$prefix"
        failure_count=$((failure_count + 1))
    fi
    printf '%s_failure_count=%s\n' "$prefix" "$failure_count"
    printf '%s_node_contact=false\n' "$prefix"
    printf '%s_podman_invoked=false\n' "$prefix"
    printf '%s_readiness_invoked=false\n' "$prefix"
    printf '%s_activation_invoked=false\n' "$prefix"
    printf '%s_live_mutations=false\n' "$prefix"

    rm -rf -- "$boundary_capture_root"
    trap - EXIT
    printf '%s_cleanup_complete=true\n' "$prefix"
    if [[ "$failure_count" -eq 0 ]]; then
        printf '%s_complete=true\n' "$prefix"
        return 0
    fi
    printf '%s_complete=false\n' "$prefix" >&2
    return 1
}

case "${1:-}" in
    --production-path-test)
        [[ $# -eq 7 ]] || exit 64
        run_boundary "$2" "$3" "$4" "$5" "$6" "$7"
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        [[ -f "$original_regression" && ! -L "$original_regression" ]]
        [[ -x "$original_regression" ]]
        [[ "$(file_hash "$original_regression")" = "$original_source_sha256" ]]
        [[ -f "$retry_regression" && ! -L "$retry_regression" ]]
        [[ -x "$retry_regression" ]]
        [[ "$(file_hash "$retry_regression")" = "$retry_source_sha256" ]]
        /bin/bash -n "$original_regression" "$retry_regression" "$0"
        printf '%s_%s_complete=true\n' "$prefix" "${1#--}"
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        run_boundary "$original_regression" "$original_source_sha256" \
            "$original_stdout_sha256" "$retry_regression" \
            "$retry_source_sha256" "$retry_stdout_sha256"
        ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test|--production-path-test ORIGINAL ORIGINAL_SOURCE_SHA256 ORIGINAL_STDOUT_SHA256 RETRY RETRY_SOURCE_SHA256 RETRY_STDOUT_SHA256]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac
