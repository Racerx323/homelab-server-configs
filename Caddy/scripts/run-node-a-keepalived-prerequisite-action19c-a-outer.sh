#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19c_a
readonly derivation_sha256=30132cf21f3b5768f1f11548e5321d512104bfda8825751402e65b716ae212de
readonly rendered_inspector_sha256=57e3bf9d9ae61b4e2b6017118481f492bd29c5784e74710a367b620230e0bea9
readonly rendered_runner_sha256=25b08fae82ac5f682f0e1f3a6dabd170864ff3d8ecc604ab9a18cc7c42c65484
readonly rendered_regression_sha256=8f4e5a7db1a542ab2236be3e137d2ebe5ae589713b073251f8f95612c493b0e2
readonly collision_checker_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly policy_sha256=99e0040d785e70a4f2e8d1796f8c6bf29675593d1ae5d13e54d9ac2dceebe44c
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly derivation="$script_directory/derive-node-a-keepalived-prerequisite-action19c-a.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"
readonly policy="$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh"

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
    require_source "$derivation_sha256" "$derivation" || return 1
    require_source "$collision_checker_sha256" "$collision_checker" ||
        return 1
    require_source "$policy_sha256" "$policy" || return 1
    bash -n "$derivation" "$policy" || return 1
    shellcheck "$derivation" "$policy" || return 1
    "$collision_checker" "$derivation" "$policy" >/dev/null || return 1
}

render_and_validate() {
    local stage_root=$1
    local inspector="$stage_root/Caddy/scripts/inspect-node-a-keepalived-prerequisite-action19c-a.sh"
    local regression="$stage_root/Caddy/tests/action19c-a-node-a-keepalived-prerequisite-regression.sh"
    local runner="$stage_root/Caddy/scripts/run-node-a-keepalived-prerequisite-action19c-a.sh"

    install -d -m 0700 "$stage_root" || return 1
    "$derivation" --output-directory "$stage_root" || return 1
    [[ "$(file_hash "$inspector")" = "$rendered_inspector_sha256" ]] ||
        return 1
    [[ "$(file_hash "$runner")" = "$rendered_runner_sha256" ]] || return 1
    [[ "$(file_hash "$regression")" = "$rendered_regression_sha256" ]] ||
        return 1
    bash -n "$inspector" "$runner" "$regression" || return 1
    shellcheck "$inspector" "$runner" "$regression" || return 1
    "$collision_checker" "$inspector" "$runner" "$regression" >/dev/null ||
        return 1
    "$inspector" --self-test >/dev/null || return 1
    "$runner" --self-test >/dev/null || return 1
    "$runner" --contract-test >/dev/null || return 1
    "$regression" >/dev/null || return 1
}

run_local_gates() {
    local gate_root

    verify_sources || return 1
    "$derivation" --self-test >/dev/null || return 1
    "$policy" >/dev/null || return 1
    gate_root=$(mktemp -d /tmp/caddy-action19c-a-local-gates.XXXXXX) ||
        return 1
    if ! render_and_validate "$gate_root"; then
        rm -rf -- "$gate_root"
        return 1
    fi
    rm -rf -- "$gate_root"
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

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_name" \
        "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_name" \
        "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_name" \
        "$(file_hash "$stream_path")"
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
[[ -z "${CADDY_ACTION19CA_SSH_BINARY:-}" ]]
[[ -z "${CADDY_ACTION19CA_INTERCEPTED_TEST:-}" ]]

work_directory=$(mktemp -d /tmp/caddy-action19c-a-outer.XXXXXX)
readonly work_directory
# shellcheck disable=SC2317
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT

render_and_validate "$work_directory/rendered"
readonly execution_runner="$work_directory/rendered/Caddy/scripts/run-node-a-keepalived-prerequisite-action19c-a.sh"
readonly stdout_path="$work_directory/runner.stdout"
readonly stderr_path="$work_directory/runner.stderr"
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"

runner_status=0
env -u CADDY_ACTION19CA_SSH_BINARY -u CADDY_ACTION19CA_INTERCEPTED_TEST \
    /bin/bash "$execution_runner" >"$stdout_path" 2>"$stderr_path" ||
    runner_status=$?
readonly runner_status
emit_stream_metadata runner_stdout "$stdout_path"
emit_stream_metadata runner_stderr "$stderr_path"
if safe_stream "$stdout_path" && safe_stream "$stderr_path"; then
    printf '%s_runner_stream_classification=bounded_safe\n' "$prefix"
    printf '%s_runner_stdout_begin\n' "$prefix"
    cat "$stdout_path"
    printf '%s_runner_stdout_end\n' "$prefix"
    if [[ -s "$stderr_path" ]]; then
        printf '%s_runner_stderr_begin\n' "$prefix" >&2
        cat "$stderr_path" >&2
        printf '%s_runner_stderr_end\n' "$prefix" >&2
    else
        printf '%s_runner_stderr_content_secured=empty\n' "$prefix"
    fi
else
    printf '%s_runner_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
printf '%s_runner_status=%s\n' "$prefix" "$runner_status"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_outer_cleanup_complete=true\n' "$prefix"
exit "$runner_status"
