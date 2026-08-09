#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/go/bin:/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_26_h3
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly accepted_protocol_outer=$script_directory/run-workstation-caddy-protocols-action26-retry-outer.sh
readonly accepted_protocol_outer_sha256=8458f79c24c56f70ab39cd6ad80d99519821227adca272da5f1a618a8a1b0a15
readonly http3_source_root=$caddy_root/tools/http3-probe
readonly maximum_capture_bytes=8192
readonly maximum_capture_lines=128
action26_h3_root=
action26_h3_binary=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
check() {
    local action26_h3_check_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26_h3_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26_h3_check_label" >&2
    return 1
}
expected_checks() {
    printf '%s\n' accepted_protocol_outer_hash http3_client_prerequisite \
        http3_build_status http3_build_stdout_safe http3_build_stderr_safe \
        http3_binary_regular http3_binary_executable \
        h3_ipv4_stdout_safe h3_ipv4_stderr_safe h3_ipv4_command_status h3_ipv4_stderr_empty \
        h3_ipv4_protocol_exact h3_ipv4_status_204 h3_ipv4_remote_ip_exact \
        h3_ipv4_body_zero h3_ipv4_redirect_zero \
        h3_ipv6_stdout_safe h3_ipv6_stderr_safe h3_ipv6_command_status h3_ipv6_stderr_empty \
        h3_ipv6_protocol_exact h3_ipv6_status_204 h3_ipv6_remote_ip_exact \
        h3_ipv6_body_zero h3_ipv6_redirect_zero
}
safe_capture() {
    local action26_h3_capture=$1

    [[ "$(wc -c <"$action26_h3_capture")" -le "$maximum_capture_bytes" ]] || return 1
    [[ "$(line_count "$action26_h3_capture")" -le "$maximum_capture_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action26_h3_capture" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:' \
        "$action26_h3_capture"
}
emit_capture() {
    local action26_h3_label=$1
    local action26_h3_capture=$2

    printf '%s_observed_%s_bytes=%s\n' "$prefix" "$action26_h3_label" "$(wc -c <"$action26_h3_capture")"
    printf '%s_observed_%s_lines=%s\n' "$prefix" "$action26_h3_label" "$(line_count "$action26_h3_capture")"
    printf '%s_observed_%s_sha256=%s\n' "$prefix" "$action26_h3_label" "$(file_hash "$action26_h3_capture")"
    safe_capture "$action26_h3_capture" || return 97
    printf '%s_observed_%s_classification=bounded_safe\n' "$prefix" "$action26_h3_label"
    if [[ -s "$action26_h3_capture" ]]; then
        printf '%s_observed_%s_begin\n' "$prefix" "$action26_h3_label"
        cat "$action26_h3_capture"
        printf '%s_observed_%s_end\n' "$prefix" "$action26_h3_label"
    else
        printf '%s_observed_%s_content=empty\n' "$prefix" "$action26_h3_label"
    fi
}
value_for() {
    local action26_h3_key=$1
    local action26_h3_file=$2

    sed -n "s/^${action26_h3_key}=//p" "$action26_h3_file"
}
prepare_binary() {
    local action26_h3_build_stdout=$action26_h3_root/build.stdout
    local action26_h3_build_stderr=$action26_h3_root/build.stderr
    local action26_h3_build_status=0

    if [[ -n "${CADDY_ACTION26_H3_BIN:-}" ]]; then
        action26_h3_binary=$CADDY_ACTION26_H3_BIN
        : >"$action26_h3_build_stdout"
        : >"$action26_h3_build_stderr"
    else
        action26_h3_binary=$action26_h3_root/http3-probe
        (
            cd -- "$http3_source_root"
            GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off \
                go build -mod=readonly -o "$action26_h3_binary" .
        ) >"$action26_h3_build_stdout" 2>"$action26_h3_build_stderr" || action26_h3_build_status=$?
    fi
    printf '%s_observed_http3_build_status=%s\n' "$prefix" "$action26_h3_build_status"
    emit_capture http3_build_stdout "$action26_h3_build_stdout" || return $?
    emit_capture http3_build_stderr "$action26_h3_build_stderr" || return $?
    check http3_build_status test "$action26_h3_build_status" -eq 0 || return 1
    check http3_build_stdout_safe safe_capture "$action26_h3_build_stdout" || return 1
    check http3_build_stderr_safe safe_capture "$action26_h3_build_stderr" || return 1
    check http3_binary_regular test -f "$action26_h3_binary" || return 1
    check http3_binary_executable test -x "$action26_h3_binary" || return 1
}
validate_output() {
    local action26_h3_label=$1
    local action26_h3_ip=$2
    local action26_h3_output=$3

    printf '%s_observed_%s_protocol=%s\n' "$prefix" "$action26_h3_label" "$(value_for protocol "$action26_h3_output")"
    printf '%s_observed_%s_status=%s\n' "$prefix" "$action26_h3_label" "$(value_for status "$action26_h3_output")"
    printf '%s_observed_%s_remote_ip=%s\n' "$prefix" "$action26_h3_label" "$(value_for remote_ip "$action26_h3_output")"
    printf '%s_observed_%s_body_bytes=%s\n' "$prefix" "$action26_h3_label" "$(value_for body_bytes "$action26_h3_output")"
    printf '%s_observed_%s_redirects=%s\n' "$prefix" "$action26_h3_label" "$(value_for redirects "$action26_h3_output")"
    check "${action26_h3_label}_protocol_exact" test "$(value_for protocol "$action26_h3_output")" = HTTP/3.0 || return 1
    check "${action26_h3_label}_status_204" test "$(value_for status "$action26_h3_output")" = 204 || return 1
    check "${action26_h3_label}_remote_ip_exact" test "$(value_for remote_ip "$action26_h3_output")" = "$action26_h3_ip" || return 1
    check "${action26_h3_label}_body_zero" test "$(value_for body_bytes "$action26_h3_output")" = 0 || return 1
    check "${action26_h3_label}_redirect_zero" test "$(value_for redirects "$action26_h3_output")" = 0 || return 1
}
run_probe() {
    local action26_h3_label=$1
    local action26_h3_ip=$2
    local action26_h3_stdout=$action26_h3_root/${action26_h3_label}.stdout
    local action26_h3_stderr=$action26_h3_root/${action26_h3_label}.stderr
    local action26_h3_status=0

    "$action26_h3_binary" -hostname proxy.local.theama.co -ip "$action26_h3_ip" \
        -path / -timeout 8s -insecure >"$action26_h3_stdout" 2>"$action26_h3_stderr" || action26_h3_status=$?
    printf '%s_observed_%s_command_status=%s\n' "$prefix" "$action26_h3_label" "$action26_h3_status"
    emit_capture "${action26_h3_label}_stdout" "$action26_h3_stdout" || return $?
    emit_capture "${action26_h3_label}_stderr" "$action26_h3_stderr" || return $?
    check "${action26_h3_label}_stdout_safe" safe_capture "$action26_h3_stdout" || return 1
    check "${action26_h3_label}_stderr_safe" safe_capture "$action26_h3_stderr" || return 1
    check "${action26_h3_label}_command_status" test "$action26_h3_status" -eq 0 || return 1
    check "${action26_h3_label}_stderr_empty" test ! -s "$action26_h3_stderr" || return 1
    validate_output "$action26_h3_label" "$action26_h3_ip" "$action26_h3_stdout"
}
cleanup() {
    local action26_h3_status=$?

    trap - EXIT INT TERM
    [[ -z "$action26_h3_root" ]] || rm -rf -- "$action26_h3_root"
    exit "$action26_h3_status"
}
run_action() {
    local action26_h3_client_prerequisite=${CADDY_ACTION26_H3_BIN:-}

    action26_h3_root=$(mktemp -d /tmp/caddy-action26-h3.XXXXXX)
    trap cleanup EXIT INT TERM
    check accepted_protocol_outer_hash test "$(file_hash "$accepted_protocol_outer")" = \
        "$accepted_protocol_outer_sha256" || return 1
    if [[ -z "$action26_h3_client_prerequisite" ]]; then
        action26_h3_client_prerequisite=$(command -v go) || return 1
    fi
    check http3_client_prerequisite test -x "$action26_h3_client_prerequisite" || return 1
    prepare_binary || return 1
    run_probe h3_ipv4 10.1.0.56 || return 1
    run_probe h3_ipv6 fd36:5aa8:6971:1::56 || return 1
    printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
    printf '%s_probe_count=2\n' "$prefix"
    printf '%s_http11_http2_evidence_preserved=true\n' "$prefix"
    printf '%s_node_ssh=false\n' "$prefix"
    printf '%s_persistent_mutation=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-checks) expected_checks ;;
    "") run_action ;;
    *) exit 64 ;;
esac
