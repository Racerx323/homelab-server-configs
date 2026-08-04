#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19b_a
readonly baseline_sha256=162f153d116e53aba95775836c4a5cb6677ad7fd080c673ca6c5ac8fb0092a0f
readonly inspector_sha256=71159ea5e0fa7c62f984ebe47742d9d0f235d570d3be948406ed93ad20cfe544
readonly runner_sha256=f865fc624d2fa10adb7c95d7dbc9570bef848dabb9281f31b78e4dd7595c72e5
readonly regression_sha256=c0db4f851520ed355ef9e261a5ea7a69b386fd5ff427982f554c077fcc67aa2c
readonly collision_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly baseline="$script_directory/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly inspector="$script_directory/inspect-node-b-action19b-postfailure-action19b-a.sh"
readonly runner="$script_directory/run-node-b-action19b-postfailure-action19b-a.sh"
readonly regression="$caddy_root/tests/action19b-a-node-b-postfailure-regression.sh"
readonly collision="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }

require_source() {
    local expected_hash=$1
    local source_path=$2

    [[ -f "$source_path" && ! -L "$source_path" && -x "$source_path" ]]
    [[ "$(stat -c '%U:%G:%a' "$source_path")" = "$(id -un):$(id -gn):755" ]]
    [[ "$(file_hash "$source_path")" = "$expected_hash" ]]
}

verify_sources() {
    require_source "$baseline_sha256" "$baseline"
    require_source "$inspector_sha256" "$inspector"
    require_source "$runner_sha256" "$runner"
    require_source "$regression_sha256" "$regression"
    require_source "$collision_sha256" "$collision"
    bash -n "$baseline" "$inspector" "$runner" "$regression"
    shellcheck "$inspector" "$runner" "$regression"
    "$collision" "$baseline" "$inspector" "$runner" "$regression" >/dev/null
}

run_local_gates() {
    "$inspector" --self-test "$baseline" >/dev/null
    "$inspector" --contract-test "$baseline" >/dev/null
    "$runner" --self-test >/dev/null
    "$runner" --contract-test >/dev/null
    "$regression" >/dev/null
}

safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]]
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]]
    if LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null; then
        return 1
    fi
    if grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$stream_path"; then
        return 1
    fi
}

case "${1:-}" in
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]]
        verify_sources
        run_local_gates
        printf '%s_outer_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] ;;
    *) exit 64 ;;
esac

verify_sources
[[ "$PWD" = /home/aaron/code/homelab-server-configs ]]
run_local_gates
work_directory=$(mktemp -d /tmp/caddy-action19b-a-outer.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly stdout_path="$work_directory/runner.stdout"
readonly stderr_path="$work_directory/runner.stderr"
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"
runner_status=0
"$runner" >"$stdout_path" 2>"$stderr_path" || runner_status=$?
readonly runner_status
printf '%s_outer_stdout_bytes=%s\n' "$prefix" "$(wc -c <"$stdout_path")"
printf '%s_outer_stdout_lines=%s\n' "$prefix" "$(line_count "$stdout_path")"
printf '%s_outer_stdout_sha256=%s\n' "$prefix" "$(file_hash "$stdout_path")"
printf '%s_outer_stderr_bytes=%s\n' "$prefix" "$(wc -c <"$stderr_path")"
printf '%s_outer_stderr_lines=%s\n' "$prefix" "$(line_count "$stderr_path")"
printf '%s_outer_stderr_sha256=%s\n' "$prefix" "$(file_hash "$stderr_path")"
if safe_stream "$stdout_path" && safe_stream "$stderr_path"; then
    printf '%s_outer_stream_classification=bounded_safe\n' "$prefix"
    printf '%s_outer_stdout_begin\n' "$prefix"
    cat "$stdout_path"
    printf '%s_outer_stdout_end\n' "$prefix"
    if [[ -s "$stderr_path" ]]; then
        printf '%s_outer_stderr_begin\n' "$prefix" >&2
        cat "$stderr_path" >&2
        printf '%s_outer_stderr_end\n' "$prefix" >&2
    fi
else
    trap - EXIT
    printf '%s_outer_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
printf '%s_outer_runner_status=%s\n' "$prefix" "$runner_status"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_outer_cleanup_complete=true\n' "$prefix"
exit "$runner_status"
