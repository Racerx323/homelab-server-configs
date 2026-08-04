#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19a_b
readonly inspector_sha256=d0869e875dd02e4e7e9658aa832ffd5851f6533d61e645571ff59d3e892deb77
readonly runner_sha256=0148cae3443a7ad8d08e5ea77a5de38fe9d5e68772521968a8bde15294b96ecb
readonly regression_sha256=4267b905959435736309c8ba8d28b51cd875ce16409b9d693aa12569fd9b02b9
readonly policy_sha256=99e0040d785e70a4f2e8d1796f8c6bf29675593d1ae5d13e54d9ac2dceebe44c
readonly collision_checker_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly inner_collision_checker_sha256=78b46fcdc6c4ca6b4cfe0121c347e0e101c472d723a891aac2dea7f23f085cd8
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector="$script_directory/inspect-node-b-keepalived-fragment-postinstall-action19a-b.sh"
readonly runner="$script_directory/run-node-b-keepalived-fragment-postinstall-action19a-b.sh"
readonly regression="$caddy_root/tests/action19a-b-node-b-keepalived-fragment-postinstall-regression.sh"
readonly policy="$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"
readonly inner_collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }

require_source() {
    local expected_hash=$1
    local source_path=$2
    local expected_identity

    expected_identity="$(id -un):$(id -gn):755"
    [[ -f "$source_path" && ! -L "$source_path" && -x "$source_path" ]] ||
        return 1
    [[ "$(stat -c '%U:%G:%a' "$source_path")" = "$expected_identity" ]] ||
        return 1
    [[ "$(file_hash "$source_path")" = "$expected_hash" ]]
}

verify_sources() {
    require_source "$inspector_sha256" "$inspector" || return 1
    require_source "$runner_sha256" "$runner" || return 1
    require_source "$regression_sha256" "$regression" || return 1
    require_source "$policy_sha256" "$policy" || return 1
    require_source "$collision_checker_sha256" "$collision_checker" || return 1
    require_source "$inner_collision_checker_sha256" \
        "$inner_collision_checker" || return 1
    bash -n "$inspector" "$runner" "$regression" "$policy" || return 1
    shellcheck "$inspector" "$runner" "$regression" "$policy" || return 1
    "$collision_checker" "$inspector" "$runner" "$regression" "$policy" \
        >/dev/null || return 1
}

run_local_gates() {
    verify_sources || return 1
    "$inspector" --self-test >/dev/null || return 1
    "$runner" --self-test >/dev/null || return 1
    "$runner" --contract-test >/dev/null || return 1
    "$policy" >/dev/null || return 1
    "$regression" >/dev/null || return 1
}

safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null ||
        return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$stream_path"
}

emit_stream_metadata() {
    local stream_name=$1
    local stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_name" "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_name" "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_name" "$(file_hash "$stream_path")"
}

case "${1:-}" in
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]]
        run_local_gates
        printf '%s_outer_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]]
        ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

run_local_gates
[[ "$PWD" = /home/aaron/code/homelab-server-configs ]]
work_directory=$(mktemp -d /tmp/caddy-action19a-b-outer.XXXXXX)
readonly work_directory
# shellcheck disable=SC2317
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT
readonly stdout_path=$work_directory/inner.stdout
readonly stderr_path=$work_directory/inner.stderr
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"

inner_status=0
"$runner" >"$stdout_path" 2>"$stderr_path" || inner_status=$?
readonly inner_status
emit_stream_metadata inner_stdout "$stdout_path"
emit_stream_metadata inner_stderr "$stderr_path"
if safe_stream "$stdout_path" && safe_stream "$stderr_path"; then
    printf '%s_inner_stream_classification=bounded_safe\n' "$prefix"
    printf '%s_inner_stdout_begin\n' "$prefix"
    cat "$stdout_path"
    printf '%s_inner_stdout_end\n' "$prefix"
    if [[ -s "$stderr_path" ]]; then
        printf '%s_inner_stderr_begin\n' "$prefix" >&2
        cat "$stderr_path" >&2
        printf '%s_inner_stderr_end\n' "$prefix" >&2
    else
        printf '%s_inner_stderr_content_secured=empty\n' "$prefix"
    fi
else
    printf '%s_inner_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
printf '%s_inner_status=%s\n' "$prefix" "$inner_status"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_outer_cleanup_complete=true\n' "$prefix"
exit "$inner_status"
