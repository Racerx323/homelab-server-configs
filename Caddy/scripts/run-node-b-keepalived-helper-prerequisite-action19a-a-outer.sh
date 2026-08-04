#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19a_a
readonly inspector_sha256=162f153d116e53aba95775836c4a5cb6677ad7fd080c673ca6c5ac8fb0092a0f
readonly runner_sha256=d0f6cc13e4de61dd9105ee4db3afd8f4caead3485d119b6c1e59e488219c4801
readonly regression_sha256=2faab580c7d201d83333961d41b1278e36377757fe6222106c89f7dcb08e502e
readonly collision_checker_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector="$script_directory/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly runner="$script_directory/run-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly regression="$caddy_root/tests/action19a-a-node-b-keepalived-helper-prerequisite-regression.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }

require_source() {
    local expected_hash=$1
    local source_path=$2

    [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
    [[ -x "$source_path" ]] || return 1
    [[ "$(file_hash "$source_path")" = "$expected_hash" ]]
}

verify_sources() {
    require_source "$inspector_sha256" "$inspector" || return 1
    require_source "$runner_sha256" "$runner" || return 1
    require_source "$regression_sha256" "$regression" || return 1
    require_source "$collision_checker_sha256" "$collision_checker" ||
        return 1
    bash -n "$inspector" "$runner" "$regression" || return 1
    shellcheck "$inspector" "$runner" "$regression" || return 1
    "$collision_checker" "$inspector" "$runner" "$regression" >/dev/null ||
        return 1
}

run_local_gates() {
    "$inspector" --self-test >/dev/null || return 1
    "$runner" --self-test >/dev/null || return 1
    "$runner" --contract-test >/dev/null || return 1
    "$regression" >/dev/null || return 1
}

safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] ||
        return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null ||
        return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$stream_path"
}

emit_stream_metadata() {
    local stream_name=$1
    local stream_path=$2

    printf '%s_outer_%s_bytes=%s\n' "$prefix" "$stream_name" \
        "$(wc -c <"$stream_path")"
    printf '%s_outer_%s_lines=%s\n' "$prefix" "$stream_name" \
        "$(line_count "$stream_path")"
    printf '%s_outer_%s_sha256=%s\n' "$prefix" "$stream_name" \
        "$(file_hash "$stream_path")"
}

case "${1:-}" in
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        run_local_gates
        printf '%s_outer_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
[[ "$PWD" = /home/aaron/code/homelab-server-configs ]]
[[ -z "${CADDY_ACTION19AA_SSH_BINARY:-}" ]]
[[ -z "${CADDY_ACTION19AA_INTERCEPTED_TEST:-}" ]]
run_local_gates
work_directory=$(mktemp -d /tmp/caddy-action19a-a-outer.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly runner_stdout_path="$work_directory/runner.stdout"
readonly runner_stderr_path="$work_directory/runner.stderr"
: >"$runner_stdout_path"
: >"$runner_stderr_path"
chmod 0600 "$runner_stdout_path" "$runner_stderr_path"

runner_status=0
env -u CADDY_ACTION19AA_SSH_BINARY -u CADDY_ACTION19AA_INTERCEPTED_TEST \
    "$runner" >"$runner_stdout_path" 2>"$runner_stderr_path" ||
    runner_status=$?
readonly runner_status
emit_stream_metadata runner_stdout "$runner_stdout_path"
emit_stream_metadata runner_stderr "$runner_stderr_path"
if safe_stream "$runner_stdout_path" && safe_stream "$runner_stderr_path"; then
    printf '%s_outer_stream_classification=bounded_safe\n' "$prefix"
    printf '%s_outer_runner_stdout_begin\n' "$prefix"
    cat "$runner_stdout_path"
    printf '%s_outer_runner_stdout_end\n' "$prefix"
    if [[ -s "$runner_stderr_path" ]]; then
        printf '%s_outer_runner_stderr_begin\n' "$prefix" >&2
        cat "$runner_stderr_path" >&2
        printf '%s_outer_runner_stderr_end\n' "$prefix" >&2
    fi
else
    printf '%s_outer_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_outer_protected_evidence=%s\n' "$prefix" \
        "$work_directory" >&2
    exit 97
fi
printf '%s_outer_runner_status=%s\n' "$prefix" "$runner_status"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_outer_cleanup_complete=true\n' "$prefix"
exit "$runner_status"
