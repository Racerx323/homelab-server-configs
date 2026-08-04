#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_18c_vrrp_a_outer
readonly inspector_sha256=f7d50d5b3ff205e845ab577653dcc373ebd745988c81f9cbbc402664b96e6bc0
readonly runner_sha256=6878c7e14c3f2d68f667add07e1177cb1959d7b8bc0b16726cf429cf300a29ed
readonly regression_sha256=a4c5fb30e359b331860b64f59dd96d30e157fc199c1585776d7989776fe24240
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector="$script_directory/inspect-caddy-vrrp-emergency-master-eligibility-action18c-vrrp-a.sh"
readonly runner="$script_directory/run-dual-node-caddy-vrrp-emergency-master-eligibility-action18c-vrrp-a.sh"
readonly regression="$caddy_root/tests/action18c-vrrp-a-emergency-master-eligibility-regression.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

line_count() {
    awk 'END { print NR }' "$1"
}

require_source() {
    local expected_hash=$1
    local source_path=$2
    local expected_owner=aaron:aaron

    if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
        expected_owner=root:root
    fi
    [[ -f "$source_path" && ! -L "$source_path" && -x "$source_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$source_path")" = "$expected_owner:755" ]] || return 1
    [[ "$(file_hash "$source_path")" = "$expected_hash" ]] || return 1
}

verify_sources() {
    require_source "$inspector_sha256" "$inspector" || return 1
    require_source "$runner_sha256" "$runner" || return 1
    require_source "$regression_sha256" "$regression" || return 1
}

run_local_gates() {
    bash -n "$inspector" "$runner" "$regression" || return 1
    "$inspector" --self-test >/dev/null || return 1
    "$runner" --self-test >/dev/null || return 1
    "$runner" --contract-test >/dev/null || return 1
    "$regression" >/dev/null || return 1
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
[[ "$PWD" = /home/aaron/code/homelab-server-configs ]]
run_local_gates
work_directory=$(mktemp -d /tmp/caddy-action18c-vrrp-a-outer.XXXXXX)
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
emit_metadata runner_stdout "$stdout_path"
emit_metadata runner_stderr "$stderr_path"
if safe_stream "$stdout_path" && safe_stream "$stderr_path"; then
    printf '%s_stream_classification=bounded_safe\n' "$prefix"
    printf '%s_stdout_begin=true\n' "$prefix"
    cat "$stdout_path"
    printf '%s_stdout_end=true\n' "$prefix"
    if [[ -s "$stderr_path" ]]; then
        printf '%s_stderr_begin=true\n' "$prefix" >&2
        cat "$stderr_path" >&2
        printf '%s_stderr_end=true\n' "$prefix" >&2
    else
        printf '%s_stderr_content_secured=empty\n' "$prefix"
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
