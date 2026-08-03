#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_18c_outer
readonly driver_sha256=66011fd63346f9ae399972b66177d8dfa8608399e7411f79e1018a31210bb24e
readonly inspector_sha256=04cb60b40351edf4221faeeb91ab60279197ce1a3b519fdd598ce10d8eb88441
readonly runner_sha256=ea732ede257791f45b8b82c10a36dee6f5a5e81d43d5b8f41ef576ae22deee42
readonly regression_sha256=701b38aea314d2d21182649fc0327b179d0ae1ea50b878a8e90b2627744df15e
readonly publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly driver="$script_directory/transfer-node-b-release-to-node-a-action18c.sh"
readonly inspector="$script_directory/inspect-node-a-incoming-release-action18c.sh"
readonly runner="$script_directory/run-node-b-to-node-a-release-transfer-action18c.sh"
readonly publisher="$script_directory/publish-release-v2.sh"
readonly regression="$caddy_root/tests/action18c-node-b-to-node-a-release-transfer-regression.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }

require_source() {
    local expected_hash=$1
    local source_path=$2
    local expected_owner=aaron:aaron

    if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
        expected_owner=root:root
    fi
    [[ -f "$source_path" && ! -L "$source_path" && -x "$source_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$source_path")" == "$expected_owner:755" ]] || return 1
    [[ "$(file_hash "$source_path")" == "$expected_hash" ]] || return 1
}

verify_sources() {
    require_source "$driver_sha256" "$driver" || return 1
    require_source "$inspector_sha256" "$inspector" || return 1
    require_source "$runner_sha256" "$runner" || return 1
    require_source "$regression_sha256" "$regression" || return 1
    require_source "$publisher_sha256" "$publisher" || return 1
}

run_local_gates() {
    bash -n "$driver" "$inspector" "$runner" "$regression" "$publisher" || return 1
    "$runner" --self-test >/dev/null || return 1
    "$runner" --contract-test >/dev/null 2>&1 || return 1
    "$regression" >/dev/null 2>&1 || return 1
}

safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$stream_path"
}

emit_metadata() {
    local stream_label=$1
    local stream_path=$2
    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_label" \
        "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_label" \
        "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_label" \
        "$(file_hash "$stream_path")"
}

case "${1:-}" in
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        run_local_gates
        outer_mode=${1#--}
        printf '%s_%s_complete=true\n' "$prefix" "${outer_mode//-/_}"
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
[[ "$PWD" == /home/aaron/code/homelab-server-configs ]]
run_local_gates
work_directory=$(mktemp -d /tmp/caddy-action18c-outer.XXXXXX)
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
emit_metadata runner_stdout "$stdout_path"
emit_metadata runner_stderr "$stderr_path"
if safe_stream "$stdout_path" && safe_stream "$stderr_path"; then
    printf '%s_stream_classification=bounded_safe\n' "$prefix"
    printf '%s_stdout_begin\n' "$prefix"
    cat "$stdout_path"
    printf '%s_stdout_end\n' "$prefix"
    if [[ -s "$stderr_path" ]]; then
        printf '%s_stderr_begin\n' "$prefix" >&2
        cat "$stderr_path" >&2
        printf '%s_stderr_end\n' "$prefix" >&2
    fi
else
    printf '%s_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
printf '%s_runner_status=%s\n' "$prefix" "$runner_status"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_cleanup_complete=true\n' "$prefix"
exit "$runner_status"
