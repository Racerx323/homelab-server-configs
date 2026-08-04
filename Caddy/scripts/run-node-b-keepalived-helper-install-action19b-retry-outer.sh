#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19b_retry
readonly health_sha256=c3bc1c080cd148efc0a64440a2a411ec115d0ca83f8e6a66220d7bd201971414
readonly notification_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8
readonly inspector_sha256=162f153d116e53aba95775836c4a5cb6677ad7fd080c673ca6c5ac8fb0092a0f
readonly continuity_inspector_sha256=a9a92b4007e7b6a0798a76fd57bdd23771970e23d1e486e76b66f6408eb92c55
readonly installer_sha256=8e049e2177038c33cd7f0b8f6d6c77b02bb7117b13fa4b3a76f7022f8e3cbad9
readonly runner_sha256=ce889307caf1370145153a5eeee1ee2837f46784d61c518627e72f44596355ad
readonly regression_sha256=2955a950873e158cd6bf5a0cba21fbd755ceb24d58d443b597dd8ddbe4de434f
readonly collision_checker_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly health_source="$script_directory/check-caddy.sh"
readonly notification_source="$script_directory/lsyncd-ha-failover-notify.sh"
readonly inspector="$script_directory/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly continuity_inspector="$script_directory/inspect-node-b-action19b-postfailure-action19b-a-retry2.sh"
readonly installer="$script_directory/install-node-b-keepalived-helpers-action19b-retry.sh"
readonly runner="$script_directory/run-node-b-keepalived-helper-install-action19b-retry.sh"
readonly regression="$caddy_root/tests/action19b-retry-node-b-keepalived-helper-install-regression.sh"
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
    require_source "$health_sha256" "$health_source" || return 1
    require_source "$notification_sha256" "$notification_source" || return 1
    require_source "$inspector_sha256" "$inspector" || return 1
    require_source "$continuity_inspector_sha256" "$continuity_inspector" ||
        return 1
    require_source "$installer_sha256" "$installer" || return 1
    require_source "$runner_sha256" "$runner" || return 1
    require_source "$regression_sha256" "$regression" || return 1
    require_source "$collision_checker_sha256" "$collision_checker" ||
        return 1
    bash -n "$health_source" "$notification_source" "$inspector" \
        "$continuity_inspector" "$installer" "$runner" "$regression" ||
        return 1
    shellcheck "$continuity_inspector" "$installer" "$runner" \
        "$regression" || return 1
    "$collision_checker" "$health_source" "$notification_source" \
        "$inspector" "$continuity_inspector" "$installer" "$runner" \
        "$regression" >/dev/null || return 1
}

run_local_gates() {
    /bin/bash "$continuity_inspector" --self-test "$inspector" \
        >/dev/null || return 1
    /bin/bash "$continuity_inspector" --contract-test "$inspector" \
        >/dev/null || return 1
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
work_directory=$(mktemp -d /tmp/caddy-action19b-retry-outer.XXXXXX)
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
