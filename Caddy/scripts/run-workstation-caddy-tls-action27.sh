#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_27
readonly hostname=proxy.local.theama.co
readonly ipv4=10.1.0.56
readonly ipv6=fd36:5aa8:6971:1::56
readonly production_leaf_sha256=4d0eb710b9920f2017ff2ac84f80ae5784deaad4ace7b4f4dafb9537347ef319
readonly production_not_after='Jan 19 23:59:59 2027 GMT'
readonly openssl_bin=${CADDY_ACTION27_OPENSSL_BIN:-/usr/bin/openssl}
readonly curl_bin=${CADDY_ACTION27_CURL_BIN:-/usr/bin/curl}
action27_root=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
check() {
    local action27_check_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action27_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action27_check_label" >&2
    return 1
}
expected_checks() {
    local action27_family
    local action27_version

    printf '%s\n' accepted_http3_outer_hash openssl_executable curl_executable test_override_boundary
    for action27_family in ipv4 ipv6; do
        for action27_version in tls12 tls13; do
            printf '%s\n' \
                "${action27_family}_${action27_version}_capture_bounded" \
                "${action27_family}_${action27_version}_command_status" \
                "${action27_family}_${action27_version}_verify_return_code" \
                "${action27_family}_${action27_version}_protocol_exact" \
                "${action27_family}_${action27_version}_chain_count_exact" \
                "${action27_family}_${action27_version}_leaf_hash_exact"
        done
    done
    printf '%s\n' leaf_hash_consistent_ipv4_tls12 leaf_hash_consistent_ipv4_tls13 \
        leaf_hash_consistent_ipv6_tls12 leaf_hash_consistent_ipv6_tls13 \
        leaf_expiry_exact san_wildcard_present \
        san_proxy_hostname san_pihole_admin_hostname san_pihole0_hostname \
        san_pihole00_hostname san_nested_hostname_rejected
    for action27_family in ipv4 ipv6; do
        printf '%s\n' \
            "${action27_family}_curl_stdout_bounded" \
            "${action27_family}_curl_stderr_bounded" \
            "${action27_family}_curl_command_status" \
            "${action27_family}_curl_stderr_empty" \
            "${action27_family}_curl_http_status" \
            "${action27_family}_curl_remote_ip" \
            "${action27_family}_curl_ssl_verify_result" \
            "${action27_family}_curl_chain_count" \
            "${action27_family}_curl_http_version" \
            "${action27_family}_curl_body_zero" \
            "${action27_family}_curl_redirect_zero"
    done
}
safe_text() {
    local action27_file=$1

    [[ "$(wc -c <"$action27_file")" -le 65536 ]] || return 1
    [[ "$(line_count "$action27_file")" -le 1024 ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action27_file" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:' \
        "$action27_file"
}
emit_safe_text() {
    local action27_label=$1
    local action27_file=$2

    printf '%s_observed_%s_bytes=%s\n' "$prefix" "$action27_label" "$(wc -c <"$action27_file")"
    printf '%s_observed_%s_lines=%s\n' "$prefix" "$action27_label" "$(line_count "$action27_file")"
    printf '%s_observed_%s_sha256=%s\n' "$prefix" "$action27_label" "$(file_hash "$action27_file")"
    safe_text "$action27_file" || return 97
    printf '%s_observed_%s_classification=bounded_safe\n' "$prefix" "$action27_label"
    if [[ -s "$action27_file" ]]; then
        printf '%s_observed_%s_begin\n' "$prefix" "$action27_label"
        cat "$action27_file"
        printf '%s_observed_%s_end\n' "$prefix" "$action27_label"
    else
        printf '%s_observed_%s_content=empty\n' "$prefix" "$action27_label"
    fi
}
value_for() {
    local action27_key=$1
    local action27_file=$2

    sed -n "s/^${action27_key}=//p" "$action27_file"
}
extract_chain() {
    local action27_input=$1
    local action27_output_directory=$2

    awk -v output_directory="$action27_output_directory" '
        /-----BEGIN CERTIFICATE-----/ { certificate += 1; output = output_directory "/cert-" certificate ".pem" }
        certificate > 0 { print > output }
        /-----END CERTIFICATE-----/ { close(output) }
        END { print certificate + 0 > output_directory "/count" }
    ' "$action27_input"
}
expected_leaf_hash() {
    if [[ "${CADDY_ACTION27_TEST_MODE:-}" = 1 ]]; then
        printf '%s\n' "${CADDY_ACTION27_EXPECTED_LEAF_SHA256:?}"
        return
    fi
    printf '%s\n' "$production_leaf_sha256"
}
expected_not_after() {
    if [[ "${CADDY_ACTION27_TEST_MODE:-}" = 1 ]]; then
        printf '%s\n' "${CADDY_ACTION27_EXPECTED_NOT_AFTER:?}"
        return
    fi
    printf '%s\n' "$production_not_after"
}
test_override_boundary() {
    if [[ "${CADDY_ACTION27_TEST_MODE:-}" = 1 ]]; then
        [[ -n "${CADDY_ACTION27_EXPECTED_LEAF_SHA256:-}" ]] || return 1
        [[ -n "${CADDY_ACTION27_EXPECTED_NOT_AFTER:-}" ]] || return 1
        [[ -n "${CADDY_ACTION27_OPENSSL_BIN:-}" ]] || return 1
        [[ -n "${CADDY_ACTION27_CURL_BIN:-}" ]] || return 1
        return 0
    fi
    [[ -z "${CADDY_ACTION27_EXPECTED_LEAF_SHA256:-}" ]] || return 1
    [[ -z "${CADDY_ACTION27_EXPECTED_NOT_AFTER:-}" ]]
}
run_handshake() {
    local action27_label=$1
    local action27_endpoint=$2
    local action27_protocol_flag=$3
    local action27_protocol_value=$4
    local action27_capture=$action27_root/${action27_label}.capture
    local action27_chain_directory=$action27_root/${action27_label}.chain
    local action27_status=0
    local action27_chain_count
    local action27_leaf_hash

    mkdir -m 0700 -- "$action27_chain_directory" || return 1
    "$openssl_bin" s_client -connect "$action27_endpoint" -servername "$hostname" \
        -verify_hostname "$hostname" -verify_return_error -CApath /etc/ssl/certs \
        "$action27_protocol_flag" -showcerts </dev/null >"$action27_capture" 2>&1 || action27_status=$?
    printf '%s_observed_%s_command_status=%s\n' "$prefix" "$action27_label" "$action27_status"
    printf '%s_observed_%s_capture_bytes=%s\n' "$prefix" "$action27_label" "$(wc -c <"$action27_capture")"
    printf '%s_observed_%s_capture_lines=%s\n' "$prefix" "$action27_label" "$(line_count "$action27_capture")"
    printf '%s_observed_%s_capture_sha256=%s\n' "$prefix" "$action27_label" "$(file_hash "$action27_capture")"
    safe_text "$action27_capture" || return 97
    printf '%s_observed_%s_capture_classification=bounded_public_certificate_suppressed\n' \
        "$prefix" "$action27_label"
    check "${action27_label}_capture_bounded" safe_text "$action27_capture" || return 1
    check "${action27_label}_command_status" test "$action27_status" -eq 0 || return 1
    check "${action27_label}_verify_return_code" grep -Eq '^Verify return code: 0 \(ok\)$' \
        "$action27_capture" || return 1
    check "${action27_label}_protocol_exact" grep -Eq \
        "^[[:space:]]*Protocol[[:space:]]*:[[:space:]]*${action27_protocol_value}[[:space:]]*$" \
        "$action27_capture" || return 1
    extract_chain "$action27_capture" "$action27_chain_directory" || return 1
    action27_chain_count=$(<"$action27_chain_directory/count")
    action27_leaf_hash=$(file_hash "$action27_chain_directory/cert-1.pem")
    printf '%s_observed_%s_chain_count=%s\n' "$prefix" "$action27_label" "$action27_chain_count"
    printf '%s_observed_%s_leaf_sha256=%s\n' "$prefix" "$action27_label" "$action27_leaf_hash"
    check "${action27_label}_chain_count_exact" test "$action27_chain_count" -eq 3 || return 1
    check "${action27_label}_leaf_hash_exact" test "$action27_leaf_hash" = "$(expected_leaf_hash)" || return 1
}
validate_leaf() {
    local action27_leaf=$action27_root/ipv4_tls12.chain/cert-1.pem
    local action27_san=$action27_root/leaf.san
    local action27_expiry
    local action27_probe
    local action27_hostname
    local action27_hostname_label
    local action27_hostname_output

    for action27_probe in ipv4_tls12 ipv4_tls13 ipv6_tls12 ipv6_tls13; do
        check "leaf_hash_consistent_${action27_probe}" test \
            "$(file_hash "$action27_root/$action27_probe.chain/cert-1.pem")" = \
            "$(expected_leaf_hash)" || return 1
    done
    action27_expiry=$("$openssl_bin" x509 -in "$action27_leaf" -noout -enddate)
    action27_expiry=${action27_expiry#notAfter=}
    printf '%s_observed_leaf_not_after=%s\n' "$prefix" "$action27_expiry"
    check leaf_expiry_exact test "$action27_expiry" = "$(expected_not_after)" || return 1
    "$openssl_bin" x509 -in "$action27_leaf" -noout -ext subjectAltName >"$action27_san"
    printf '%s_observed_leaf_san_sha256=%s\n' "$prefix" "$(file_hash "$action27_san")"
    check san_wildcard_present grep -Fq 'DNS:*.local.theama.co' "$action27_san" || return 1
    while IFS='|' read -r action27_hostname_label action27_hostname; do
        action27_hostname_output=$action27_root/${action27_hostname_label}.hostname
        "$openssl_bin" x509 -in "$action27_leaf" -noout -checkhost "$action27_hostname" \
            >"$action27_hostname_output" 2>&1 || return 1
        check "$action27_hostname_label" grep -Fq \
            "Hostname $action27_hostname does match certificate" "$action27_hostname_output" || return 1
    done <<'EOF'
san_proxy_hostname|proxy.local.theama.co
san_pihole_admin_hostname|pihole-admin.local.theama.co
san_pihole0_hostname|pihole0.local.theama.co
san_pihole00_hostname|pihole00.local.theama.co
EOF
    action27_hostname=unexpected.deep.local.theama.co
    action27_hostname_output=$action27_root/san_nested_hostname_rejected.hostname
    "$openssl_bin" x509 -in "$action27_leaf" -noout -checkhost "$action27_hostname" \
        >"$action27_hostname_output" 2>&1 || return 1
    check san_nested_hostname_rejected grep -Fq \
        "Hostname $action27_hostname does NOT match certificate" "$action27_hostname_output" || return 1
}
run_curl_probe() {
    local action27_label=$1
    local action27_address=$2
    local action27_resolve_address=$3
    local action27_stdout=$action27_root/${action27_label}.curl.stdout
    local action27_stderr=$action27_root/${action27_label}.curl.stderr
    local action27_status=0

    "$curl_bin" --silent --show-error --fail --http1.1 --max-time 8 \
        --resolve "${hostname}:443:${action27_resolve_address}" \
        --output /dev/null --write-out \
        'http_code=%{http_code}\nremote_ip=%{remote_ip}\nssl_verify_result=%{ssl_verify_result}\nnum_certs=%{num_certs}\nhttp_version=%{http_version}\nsize_download=%{size_download}\nnum_redirects=%{num_redirects}\n' \
        "https://${hostname}/healthz" >"$action27_stdout" 2>"$action27_stderr" || action27_status=$?
    printf '%s_observed_%s_curl_command_status=%s\n' "$prefix" "$action27_label" "$action27_status"
    emit_safe_text "${action27_label}_curl_stdout" "$action27_stdout" || return $?
    emit_safe_text "${action27_label}_curl_stderr" "$action27_stderr" || return $?
    check "${action27_label}_curl_stdout_bounded" safe_text "$action27_stdout" || return 1
    check "${action27_label}_curl_stderr_bounded" safe_text "$action27_stderr" || return 1
    check "${action27_label}_curl_command_status" test "$action27_status" -eq 0 || return 1
    check "${action27_label}_curl_stderr_empty" test ! -s "$action27_stderr" || return 1
    check "${action27_label}_curl_http_status" test "$(value_for http_code "$action27_stdout")" = 204 || return 1
    check "${action27_label}_curl_remote_ip" test "$(value_for remote_ip "$action27_stdout")" = "$action27_address" || return 1
    check "${action27_label}_curl_ssl_verify_result" test "$(value_for ssl_verify_result "$action27_stdout")" = 0 || return 1
    check "${action27_label}_curl_chain_count" test "$(value_for num_certs "$action27_stdout")" = 3 || return 1
    check "${action27_label}_curl_http_version" test "$(value_for http_version "$action27_stdout")" = 1.1 || return 1
    check "${action27_label}_curl_body_zero" test "$(value_for size_download "$action27_stdout")" = 0 || return 1
    check "${action27_label}_curl_redirect_zero" test "$(value_for num_redirects "$action27_stdout")" = 0 || return 1
}
cleanup() {
    local action27_status=$?

    trap - EXIT INT TERM
    [[ -z "$action27_root" ]] || rm -rf -- "$action27_root"
    exit "$action27_status"
}
run_action() {
    local action27_accepted_outer

    action27_root=$(mktemp -d /tmp/caddy-action27.XXXXXX)
    trap cleanup EXIT INT TERM
    action27_accepted_outer=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/run-workstation-caddy-http3-action26-h3-retry-outer.sh
    check accepted_http3_outer_hash test "$(file_hash "$action27_accepted_outer")" = \
        289fd577f78aea2015b162f534b3a6819ba92965a67c579a3b6f6e32bf4d60b2 || return 1
    check openssl_executable test -x "$openssl_bin" || return 1
    check curl_executable test -x "$curl_bin" || return 1
    check test_override_boundary test_override_boundary || return 1
    run_handshake ipv4_tls12 "${ipv4}:443" -tls1_2 TLSv1.2 || return 1
    run_handshake ipv4_tls13 "${ipv4}:443" -tls1_3 TLSv1.3 || return 1
    run_handshake ipv6_tls12 "[${ipv6}]:443" -tls1_2 TLSv1.2 || return 1
    run_handshake ipv6_tls13 "[${ipv6}]:443" -tls1_3 TLSv1.3 || return 1
    validate_leaf || return 1
    run_curl_probe ipv4 "$ipv4" "$ipv4" || return 1
    run_curl_probe ipv6 "$ipv6" "[$ipv6]" || return 1
    printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
    printf '%s_handshake_count=4\n' "$prefix"
    printf '%s_trusted_http_probe_count=2\n' "$prefix"
    printf '%s_insecure_flag=false\n' "$prefix"
    printf '%s_node_contact=false\n' "$prefix"
    printf '%s_persistent_mutation=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-checks) expected_checks ;;
    "") run_action ;;
    *) exit 64 ;;
esac
