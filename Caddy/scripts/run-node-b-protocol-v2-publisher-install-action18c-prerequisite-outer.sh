#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_18c_publisher_prerequisite
readonly publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669
readonly installer_sha256=b26eab687ed6dc19f118d532ae14dacf85b0aa9e8a39f031bf2ed2369fe7a0a5
readonly runner_sha256=aafc230513d91a8ab337a2b50e447db067695992c32937ad36796b28c6c85ccc
readonly regression_sha256=bc1b6381d0e44877c42b1590800d47962aaab75a647bf4bfe510cd25ac90d0b8
readonly collision_checker_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly publisher="$script_directory/publish-release-v2.sh"
readonly installer="$script_directory/install-node-b-protocol-v2-publisher-action18c-prerequisite.sh"
readonly runner="$script_directory/run-node-b-protocol-v2-publisher-install-action18c-prerequisite.sh"
readonly regression="$caddy_root/tests/action18c-publisher-prerequisite-node-b-install-regression.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

line_count() {
    awk 'END { print NR }' "$1"
}

require_source() {
    local expected_hash=$1
    local source_path=$2
    local source_identity

    [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
    [[ -x "$source_path" ]] || return 1
    source_identity="$(id -un):$(id -gn):755"
    [[ "$(stat -c '%U:%G:%a' "$source_path")" = "$source_identity" ]] ||
        return 1
    [[ "$(file_hash "$source_path")" = "$expected_hash" ]] || return 1
}

verify_sources() {
    require_source "$publisher_sha256" "$publisher" || return 1
    require_source "$installer_sha256" "$installer" || return 1
    require_source "$runner_sha256" "$runner" || return 1
    require_source "$regression_sha256" "$regression" || return 1
    require_source "$collision_checker_sha256" "$collision_checker" ||
        return 1
    bash -n "$publisher" "$installer" "$runner" "$regression" || return 1
    shellcheck "$installer" "$runner" "$regression" || return 1
    "$collision_checker" "$installer" "$runner" "$regression" >/dev/null ||
        return 1
}

run_local_gates() {
    "$installer" --self-test >/dev/null || return 1
    "$runner" --self-test >/dev/null || return 1
    "$runner" --contract-test >/dev/null || return 1
    "$regression" >/dev/null || return 1
}

safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] ||
        return 1
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
run_local_gates
work_directory=$(mktemp -d /tmp/caddy-action18c-publisher-outer.XXXXXX)
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
emit_stream_metadata runner_stdout "$stdout_path"
emit_stream_metadata runner_stderr "$stderr_path"
if safe_stream "$stdout_path" && safe_stream "$stderr_path"; then
    printf '%s_outer_stream_classification=bounded_safe\n' "$prefix"
    printf '%s_outer_runner_stdout_begin\n' "$prefix"
    cat "$stdout_path"
    printf '%s_outer_runner_stdout_end\n' "$prefix"
    if [[ -s "$stderr_path" ]]; then
        printf '%s_outer_runner_stderr_begin\n' "$prefix" >&2
        cat "$stderr_path" >&2
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
