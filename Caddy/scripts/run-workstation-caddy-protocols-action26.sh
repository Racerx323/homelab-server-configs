#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/go/bin:/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_26
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly accepted_action25_outer=$script_directory/run-dual-node-pihole-web-access-action25-retry2-outer.sh
readonly accepted_action25_outer_sha256=e9eb4e88f02939778e42f7da3fc10135bdc3023e1cef675d875f59a1c27dd2af
readonly caddyfile=$caddy_root/configs/caddy/Caddyfile
readonly caddyfile_sha256=a41c7816e927c16278fab018675a3f2db5b2aae89dd5b181f1ecb06ec9beb86e
readonly health_fragment=$caddy_root/configs/caddy/conf.d/00-health.caddy
readonly health_fragment_sha256=05fa1d2875ee0639601447ccd31284d3df55fc8d5e8cedef4a291c61d44f4b27
readonly http3_source_root=$caddy_root/tools/http3-probe
readonly maximum_probe_bytes=2048
readonly maximum_probe_lines=12
action26_work_root=
action26_http3_binary=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
check() {
    local action26_check_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26_check_label" >&2
    return 1
}
expected_checks() {
    printf '%s\n' \
        accepted_action25_outer_hash caddyfile_hash health_fragment_hash \
        curl_regular curl_http2_feature http3_client_prerequisite http3_build_status \
        http3_build_stdout_safe http3_build_stderr_safe http3_binary_regular \
        http3_binary_executable \
        h1_ipv4_command_status h1_ipv4_stderr_empty h1_ipv4_output_safe h1_ipv4_protocol_exact \
        h1_ipv4_status_204 h1_ipv4_remote_ip_exact h1_ipv4_body_zero h1_ipv4_redirect_zero \
        h1_ipv6_command_status h1_ipv6_stderr_empty h1_ipv6_output_safe h1_ipv6_protocol_exact \
        h1_ipv6_status_204 h1_ipv6_remote_ip_exact h1_ipv6_body_zero h1_ipv6_redirect_zero \
        h2_ipv4_command_status h2_ipv4_stderr_empty h2_ipv4_output_safe h2_ipv4_protocol_exact \
        h2_ipv4_status_204 h2_ipv4_remote_ip_exact h2_ipv4_body_zero h2_ipv4_redirect_zero \
        h2_ipv6_command_status h2_ipv6_stderr_empty h2_ipv6_output_safe h2_ipv6_protocol_exact \
        h2_ipv6_status_204 h2_ipv6_remote_ip_exact h2_ipv6_body_zero h2_ipv6_redirect_zero \
        h3_ipv4_command_status h3_ipv4_stderr_empty h3_ipv4_output_safe h3_ipv4_protocol_exact \
        h3_ipv4_status_204 h3_ipv4_remote_ip_exact h3_ipv4_body_zero h3_ipv4_redirect_zero \
        h3_ipv6_command_status h3_ipv6_stderr_empty h3_ipv6_output_safe h3_ipv6_protocol_exact \
        h3_ipv6_status_204 h3_ipv6_remote_ip_exact h3_ipv6_body_zero h3_ipv6_redirect_zero
}
safe_probe_output() {
    local action26_safe_probe_file=$1

    [[ -s "$action26_safe_probe_file" ]] || return 1
    [[ "$(wc -c <"$action26_safe_probe_file")" -le "$maximum_probe_bytes" ]] || return 1
    [[ "$(line_count "$action26_safe_probe_file")" -le "$maximum_probe_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action26_safe_probe_file" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:' \
        "$action26_safe_probe_file"
}
safe_optional_output() {
    local action26_safe_optional_file=$1

    [[ "$(wc -c <"$action26_safe_optional_file")" -le "$maximum_probe_bytes" ]] || return 1
    [[ "$(line_count "$action26_safe_optional_file")" -le "$maximum_probe_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action26_safe_optional_file" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:' \
        "$action26_safe_optional_file"
}
emit_capture() {
    local action26_capture_label=$1
    local action26_capture_file=$2

    printf '%s_observed_%s_bytes=%s\n' "$prefix" "$action26_capture_label" "$(wc -c <"$action26_capture_file")"
    printf '%s_observed_%s_lines=%s\n' "$prefix" "$action26_capture_label" "$(line_count "$action26_capture_file")"
    printf '%s_observed_%s_sha256=%s\n' "$prefix" "$action26_capture_label" "$(file_hash "$action26_capture_file")"
    if safe_optional_output "$action26_capture_file"; then
        printf '%s_observed_%s_classification=bounded_safe\n' "$prefix" "$action26_capture_label"
        if [[ -s "$action26_capture_file" ]]; then
            printf '%s_observed_%s_begin\n' "$prefix" "$action26_capture_label"
            cat "$action26_capture_file"
            printf '%s_observed_%s_end\n' "$prefix" "$action26_capture_label"
        else
            printf '%s_observed_%s_content=empty\n' "$prefix" "$action26_capture_label"
        fi
        return 0
    fi
    printf '%s_observed_%s_classification=unsafe_retained\n' "$prefix" "$action26_capture_label" >&2
    return 97
}
value_for() {
    local action26_value_key=$1
    local action26_value_file=$2

    sed -n "s/^${action26_value_key}=//p" "$action26_value_file"
}
validate_probe_output() {
    local action26_validate_label=$1
    local action26_validate_expected_protocol=$2
    local action26_validate_expected_ip=$3
    local action26_validate_output=$4
    local action26_validate_protocol
    local action26_validate_status
    local action26_validate_remote_ip
    local action26_validate_body_bytes
    local action26_validate_redirects

    action26_validate_protocol=$(value_for protocol "$action26_validate_output") || return 1
    action26_validate_status=$(value_for status "$action26_validate_output") || return 1
    action26_validate_remote_ip=$(value_for remote_ip "$action26_validate_output") || return 1
    action26_validate_body_bytes=$(value_for body_bytes "$action26_validate_output") || return 1
    action26_validate_redirects=$(value_for redirects "$action26_validate_output") || return 1
    printf '%s_observed_%s_protocol=%s\n' "$prefix" "$action26_validate_label" "$action26_validate_protocol"
    printf '%s_observed_%s_status=%s\n' "$prefix" "$action26_validate_label" "$action26_validate_status"
    printf '%s_observed_%s_remote_ip=%s\n' "$prefix" "$action26_validate_label" "$action26_validate_remote_ip"
    printf '%s_observed_%s_body_bytes=%s\n' "$prefix" "$action26_validate_label" "$action26_validate_body_bytes"
    printf '%s_observed_%s_redirects=%s\n' "$prefix" "$action26_validate_label" "$action26_validate_redirects"

    check "${action26_validate_label}_output_safe" safe_probe_output "$action26_validate_output" || return 1
    check "${action26_validate_label}_protocol_exact" test \
        "$action26_validate_protocol" = "$action26_validate_expected_protocol" || return 1
    check "${action26_validate_label}_status_204" test \
        "$action26_validate_status" = 204 || return 1
    check "${action26_validate_label}_remote_ip_exact" test \
        "$action26_validate_remote_ip" = "$action26_validate_expected_ip" || return 1
    check "${action26_validate_label}_body_zero" test \
        "$action26_validate_body_bytes" = 0 || return 1
    check "${action26_validate_label}_redirect_zero" test \
        "$action26_validate_redirects" = 0 || return 1
}
run_curl_probe() {
    local action26_curl_label=$1
    local action26_curl_protocol_flag=$2
    local action26_curl_expected_protocol=$3
    local action26_curl_ip=$4
    local action26_curl_output=$action26_work_root/${action26_curl_label}.stdout
    local action26_curl_stderr=$action26_work_root/${action26_curl_label}.stderr
    local action26_curl_status=0
    local action26_curl_resolve=proxy.local.theama.co:443:$action26_curl_ip

    if [[ "$action26_curl_ip" == *:* ]]; then
        action26_curl_resolve=proxy.local.theama.co:443:[$action26_curl_ip]
    fi
    "${CADDY_ACTION26_CURL_BIN:-curl}" "$action26_curl_protocol_flag" \
        --insecure --silent --show-error --fail --connect-timeout 3 --max-time 8 \
        --resolve "$action26_curl_resolve" --output /dev/null \
        --write-out $'protocol=%{http_version}\nstatus=%{http_code}\nremote_ip=%{remote_ip}\nbody_bytes=%{size_download}\nredirects=%{num_redirects}\n' \
        https://proxy.local.theama.co/ >"$action26_curl_output" 2>"$action26_curl_stderr" ||
        action26_curl_status=$?
    printf '%s_observed_%s_command_status=%s\n' "$prefix" "$action26_curl_label" "$action26_curl_status"
    emit_capture "${action26_curl_label}_stdout" "$action26_curl_output" || return $?
    emit_capture "${action26_curl_label}_stderr" "$action26_curl_stderr" || return $?
    check "${action26_curl_label}_command_status" test "$action26_curl_status" -eq 0 || return 1
    check "${action26_curl_label}_stderr_empty" test ! -s "$action26_curl_stderr" || return 1
    validate_probe_output "$action26_curl_label" "$action26_curl_expected_protocol" \
        "$action26_curl_ip" "$action26_curl_output"
}
run_http3_probe() {
    local action26_h3_label=$1
    local action26_h3_ip=$2
    local action26_h3_output=$action26_work_root/${action26_h3_label}.stdout
    local action26_h3_stderr=$action26_work_root/${action26_h3_label}.stderr
    local action26_h3_status=0

    "$action26_http3_binary" -hostname proxy.local.theama.co -ip "$action26_h3_ip" \
        -path / -timeout 8s -insecure >"$action26_h3_output" 2>"$action26_h3_stderr" ||
        action26_h3_status=$?
    printf '%s_observed_%s_command_status=%s\n' "$prefix" "$action26_h3_label" "$action26_h3_status"
    emit_capture "${action26_h3_label}_stdout" "$action26_h3_output" || return $?
    emit_capture "${action26_h3_label}_stderr" "$action26_h3_stderr" || return $?
    check "${action26_h3_label}_command_status" test "$action26_h3_status" -eq 0 || return 1
    check "${action26_h3_label}_stderr_empty" test ! -s "$action26_h3_stderr" || return 1
    validate_probe_output "$action26_h3_label" HTTP/3.0 "$action26_h3_ip" "$action26_h3_output"
}
prepare_http3_binary() {
    local action26_build_stdout=$action26_work_root/http3-build.stdout
    local action26_build_stderr=$action26_work_root/http3-build.stderr
    local action26_build_status=0

    if [[ -n "${CADDY_ACTION26_HTTP3_BIN:-}" ]]; then
        action26_http3_binary=$CADDY_ACTION26_HTTP3_BIN
        : >"$action26_build_stdout"
        : >"$action26_build_stderr"
    else
        action26_http3_binary=$action26_work_root/caddy-http3-probe
        (
            cd -- "$http3_source_root"
            GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off \
                go build -mod=readonly -o "$action26_http3_binary" .
        ) >"$action26_build_stdout" 2>"$action26_build_stderr" || action26_build_status=$?
    fi
    printf '%s_observed_http3_build_status=%s\n' "$prefix" "$action26_build_status"
    emit_capture http3_build_stdout "$action26_build_stdout" || return $?
    emit_capture http3_build_stderr "$action26_build_stderr" || return $?
    check http3_build_status test "$action26_build_status" -eq 0 || return 1
    check http3_build_stdout_safe safe_optional_output "$action26_build_stdout" || return 1
    check http3_build_stderr_safe safe_optional_output "$action26_build_stderr" || return 1
    check http3_binary_regular test -f "$action26_http3_binary" || return 1
    check http3_binary_executable test -x "$action26_http3_binary" || return 1
}
curl_has_http2() {
    "${CADDY_ACTION26_CURL_BIN:-curl}" --version | sed -n 's/^Features: //p' | tr ' ' '\n' | grep -Fqx HTTP2
}
curl_is_executable() {
    local action26_curl_path

    action26_curl_path=$(command -v "${CADDY_ACTION26_CURL_BIN:-curl}") || return 1
    test -x "$action26_curl_path"
}
http3_client_prerequisite() {
    if [[ -n "${CADDY_ACTION26_HTTP3_BIN:-}" ]]; then
        test -f "$CADDY_ACTION26_HTTP3_BIN" && test -x "$CADDY_ACTION26_HTTP3_BIN"
        return
    fi
    test -x "$(command -v go)"
}
cleanup() {
    local action26_cleanup_status=$?

    trap - EXIT INT TERM
    if [[ -n "$action26_work_root" ]]; then
        rm -rf -- "$action26_work_root"
    fi
    exit "$action26_cleanup_status"
}
run_action() {
    action26_work_root=$(mktemp -d /tmp/caddy-action26.XXXXXX)
    trap cleanup EXIT INT TERM

    check accepted_action25_outer_hash test "$(file_hash "$accepted_action25_outer")" = \
        "$accepted_action25_outer_sha256" || return 1
    check caddyfile_hash test "$(file_hash "$caddyfile")" = "$caddyfile_sha256" || return 1
    check health_fragment_hash test "$(file_hash "$health_fragment")" = "$health_fragment_sha256" || return 1
    check curl_regular curl_is_executable || return 1
    check curl_http2_feature curl_has_http2 || return 1
    check http3_client_prerequisite http3_client_prerequisite || return 1
    prepare_http3_binary || return 1

    run_curl_probe h1_ipv4 --http1.1 1.1 10.1.0.56 || return 1
    run_curl_probe h1_ipv6 --http1.1 1.1 fd36:5aa8:6971:1::56 || return 1
    run_curl_probe h2_ipv4 --http2 2 10.1.0.56 || return 1
    run_curl_probe h2_ipv6 --http2 2 fd36:5aa8:6971:1::56 || return 1
    run_http3_probe h3_ipv4 10.1.0.56 || return 1
    run_http3_probe h3_ipv6 fd36:5aa8:6971:1::56 || return 1

    printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
    printf '%s_endpoint_count=6\n' "$prefix"
    printf '%s_workstation_only=true\n' "$prefix"
    printf '%s_node_ssh=false\n' "$prefix"
    printf '%s_filesystem_mutation=false\n' "$prefix"
    printf '%s_service_mutation=false\n' "$prefix"
    printf '%s_dns_mutation=false\n' "$prefix"
    printf '%s_protocol_validation_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-checks) expected_checks ;;
    '') run_action ;;
    *) exit 64 ;;
esac
