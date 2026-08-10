#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_27_retry_a
readonly hostname=proxy.local.theama.co
readonly ipv4=10.1.0.56
readonly ipv6=fd36:5aa8:6971:1::56
readonly production_not_after='Jan 19 23:59:59 2027 GMT'
readonly openssl_bin=${CADDY_ACTION27_RETRY_A_OPENSSL_BIN:-/usr/bin/openssl}
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly immutable_retry_outer=$script_directory/run-workstation-caddy-tls-action27-retry-outer.sh
readonly immutable_retry_outer_sha256=07db480bf77f640c14450b19b73fecae494208e989323e203676cb8813d24c30
action27_retry_a_root=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
check() {
    local action27_retry_a_check_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action27_retry_a_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action27_retry_a_check_label" >&2
    return 1
}
expected_checks() {
    local action27_retry_a_family

    printf '%s\n' immutable_retry_outer_hash openssl_executable test_override_boundary
    for action27_retry_a_family in ipv4 ipv6; do
        printf '%s\n' \
            "${action27_retry_a_family}_capture_bounded" \
            "${action27_retry_a_family}_command_status" \
            "${action27_retry_a_family}_verify_return_code" \
            "${action27_retry_a_family}_protocol_exact" \
            "${action27_retry_a_family}_chain_count_exact" \
            "${action27_retry_a_family}_der_conversion" \
            "${action27_retry_a_family}_der_hash_shape" \
            "${action27_retry_a_family}_spki_conversion" \
            "${action27_retry_a_family}_spki_hash_shape" \
            "${action27_retry_a_family}_serial_present" \
            "${action27_retry_a_family}_subject_present" \
            "${action27_retry_a_family}_issuer_present" \
            "${action27_retry_a_family}_not_before_present" \
            "${action27_retry_a_family}_not_after_exact" \
            "${action27_retry_a_family}_san_extraction" \
            "${action27_retry_a_family}_san_wildcard_present" \
            "${action27_retry_a_family}_hostname_match"
    done
    printf '%s\n' identity_der_consistent identity_spki_consistent identity_serial_consistent \
        identity_subject_consistent identity_issuer_consistent identity_not_before_consistent \
        identity_not_after_consistent identity_san_digest_consistent identity_chain_count_consistent
}
safe_capture() {
    local action27_retry_a_capture=$1

    [[ "$(wc -c <"$action27_retry_a_capture")" -le 65536 ]] || return 1
    [[ "$(line_count "$action27_retry_a_capture")" -le 1024 ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action27_retry_a_capture" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:' \
        "$action27_retry_a_capture"
}
hash_shape() {
    local action27_retry_a_hash=$1

    [[ ${#action27_retry_a_hash} -eq 64 ]] || return 1
    [[ "$action27_retry_a_hash" =~ ^[0-9a-f]+$ ]]
}
extract_chain() {
    local action27_retry_a_input=$1
    local action27_retry_a_output_directory=$2

    awk -v output_directory="$action27_retry_a_output_directory" '
        /-----BEGIN CERTIFICATE-----/ { certificate += 1; output = output_directory "/cert-" certificate ".pem" }
        certificate > 0 { print > output }
        /-----END CERTIFICATE-----/ { close(output) }
        END { print certificate + 0 > output_directory "/count" }
    ' "$action27_retry_a_input"
}
canonical_san() {
    local action27_retry_a_leaf=$1
    local action27_retry_a_output=$2
    local action27_retry_a_raw=$action27_retry_a_output.raw

    "$openssl_bin" x509 -in "$action27_retry_a_leaf" -noout -ext subjectAltName \
        >"$action27_retry_a_raw" || return 1
    sed '1d' "$action27_retry_a_raw" |
        tr ',' '\n' |
        sed -n -E 's/^[[:space:]]*DNS:(.*)$/\1/p' |
        sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' |
        sed '/^$/d' |
        LC_ALL=C sort -u >"$action27_retry_a_output"
    [[ -s "$action27_retry_a_output" ]]
}
expected_not_after() {
    if [[ "${CADDY_ACTION27_RETRY_A_TEST_MODE:-}" = 1 ]]; then
        printf '%s\n' "${CADDY_ACTION27_RETRY_A_EXPECTED_NOT_AFTER:?}"
        return
    fi
    printf '%s\n' "$production_not_after"
}
test_override_boundary() {
    if [[ "${CADDY_ACTION27_RETRY_A_TEST_MODE:-}" = 1 ]]; then
        [[ -n "${CADDY_ACTION27_RETRY_A_EXPECTED_NOT_AFTER:-}" ]] || return 1
        [[ -n "${CADDY_ACTION27_RETRY_A_OPENSSL_BIN:-}" ]] || return 1
        return 0
    fi
    [[ -z "${CADDY_ACTION27_RETRY_A_EXPECTED_NOT_AFTER:-}" ]]
}
metadata_value() {
    local action27_retry_a_key=$1
    local action27_retry_a_file=$2

    sed -n "s/^${action27_retry_a_key}=//p" "$action27_retry_a_file"
}
derive_identity() {
    local action27_retry_a_family=$1
    local action27_retry_a_leaf=$2
    local action27_retry_a_chain_count=$3
    local action27_retry_a_directory=$action27_retry_a_root/$action27_retry_a_family.identity
    local action27_retry_a_der=$action27_retry_a_directory/leaf.der
    local action27_retry_a_pubkey=$action27_retry_a_directory/leaf.pubkey.pem
    local action27_retry_a_spki=$action27_retry_a_directory/leaf.spki.der
    local action27_retry_a_metadata=$action27_retry_a_directory/metadata
    local action27_retry_a_san=$action27_retry_a_directory/san.canonical
    local action27_retry_a_hostname_output=$action27_retry_a_directory/hostname
    local action27_retry_a_der_hash
    local action27_retry_a_spki_hash
    local action27_retry_a_serial
    local action27_retry_a_subject
    local action27_retry_a_issuer
    local action27_retry_a_not_before
    local action27_retry_a_not_after
    local action27_retry_a_san_hash
    local action27_retry_a_san_names

    mkdir -m 0700 -- "$action27_retry_a_directory" || return 1
    "$openssl_bin" x509 -in "$action27_retry_a_leaf" -outform DER -out "$action27_retry_a_der" || return 1
    check "${action27_retry_a_family}_der_conversion" test -s "$action27_retry_a_der" || return 1
    action27_retry_a_der_hash=$(file_hash "$action27_retry_a_der")
    check "${action27_retry_a_family}_der_hash_shape" hash_shape "$action27_retry_a_der_hash" || return 1
    "$openssl_bin" x509 -in "$action27_retry_a_leaf" -pubkey -noout \
        >"$action27_retry_a_pubkey" || return 1
    "$openssl_bin" pkey -pubin -in "$action27_retry_a_pubkey" -outform DER \
        -out "$action27_retry_a_spki" || return 1
    check "${action27_retry_a_family}_spki_conversion" test -s "$action27_retry_a_spki" || return 1
    action27_retry_a_spki_hash=$(file_hash "$action27_retry_a_spki")
    check "${action27_retry_a_family}_spki_hash_shape" hash_shape "$action27_retry_a_spki_hash" || return 1
    "$openssl_bin" x509 -in "$action27_retry_a_leaf" -noout -serial -subject -issuer \
        -startdate -enddate -nameopt RFC2253 >"$action27_retry_a_metadata" || return 1
    action27_retry_a_serial=$(metadata_value serial "$action27_retry_a_metadata")
    action27_retry_a_subject=$(metadata_value subject "$action27_retry_a_metadata")
    action27_retry_a_issuer=$(metadata_value issuer "$action27_retry_a_metadata")
    action27_retry_a_not_before=$(metadata_value notBefore "$action27_retry_a_metadata")
    action27_retry_a_not_after=$(metadata_value notAfter "$action27_retry_a_metadata")
    check "${action27_retry_a_family}_serial_present" test -n "$action27_retry_a_serial" || return 1
    check "${action27_retry_a_family}_subject_present" test -n "$action27_retry_a_subject" || return 1
    check "${action27_retry_a_family}_issuer_present" test -n "$action27_retry_a_issuer" || return 1
    check "${action27_retry_a_family}_not_before_present" test -n "$action27_retry_a_not_before" || return 1
    check "${action27_retry_a_family}_not_after_exact" test "$action27_retry_a_not_after" = \
        "$(expected_not_after)" || return 1
    check "${action27_retry_a_family}_san_extraction" canonical_san \
        "$action27_retry_a_leaf" "$action27_retry_a_san" || return 1
    check "${action27_retry_a_family}_san_wildcard_present" grep -Fqx \
        '*.local.theama.co' "$action27_retry_a_san" || return 1
    "$openssl_bin" x509 -in "$action27_retry_a_leaf" -noout -checkhost "$hostname" \
        >"$action27_retry_a_hostname_output" 2>&1 || return 1
    check "${action27_retry_a_family}_hostname_match" grep -Fq \
        "Hostname $hostname does match certificate" "$action27_retry_a_hostname_output" || return 1
    action27_retry_a_san_hash=$(file_hash "$action27_retry_a_san")
    action27_retry_a_san_names=$(paste -sd, "$action27_retry_a_san")
    cat >"$action27_retry_a_directory/identity" <<EOF
der_sha256=$action27_retry_a_der_hash
spki_sha256=$action27_retry_a_spki_hash
serial=$action27_retry_a_serial
subject=$action27_retry_a_subject
issuer=$action27_retry_a_issuer
not_before=$action27_retry_a_not_before
not_after=$action27_retry_a_not_after
san_sha256=$action27_retry_a_san_hash
san_dns_names=$action27_retry_a_san_names
chain_count=$action27_retry_a_chain_count
EOF
    printf '%s_observed_%s_der_sha256=%s\n' "$prefix" "$action27_retry_a_family" "$action27_retry_a_der_hash"
    printf '%s_observed_%s_spki_sha256=%s\n' "$prefix" "$action27_retry_a_family" "$action27_retry_a_spki_hash"
    printf '%s_observed_%s_serial=%s\n' "$prefix" "$action27_retry_a_family" "$action27_retry_a_serial"
    printf '%s_observed_%s_subject=%s\n' "$prefix" "$action27_retry_a_family" "$action27_retry_a_subject"
    printf '%s_observed_%s_issuer=%s\n' "$prefix" "$action27_retry_a_family" "$action27_retry_a_issuer"
    printf '%s_observed_%s_not_before=%s\n' "$prefix" "$action27_retry_a_family" "$action27_retry_a_not_before"
    printf '%s_observed_%s_not_after=%s\n' "$prefix" "$action27_retry_a_family" "$action27_retry_a_not_after"
    printf '%s_observed_%s_san_sha256=%s\n' "$prefix" "$action27_retry_a_family" "$action27_retry_a_san_hash"
    printf '%s_observed_%s_san_dns_names=%s\n' "$prefix" "$action27_retry_a_family" "$action27_retry_a_san_names"
    printf '%s_observed_%s_chain_count=%s\n' "$prefix" "$action27_retry_a_family" "$action27_retry_a_chain_count"
}
run_probe() {
    local action27_retry_a_family=$1
    local action27_retry_a_endpoint=$2
    local action27_retry_a_capture=$action27_retry_a_root/$action27_retry_a_family.capture
    local action27_retry_a_chain=$action27_retry_a_root/$action27_retry_a_family.chain
    local action27_retry_a_status=0
    local action27_retry_a_chain_count

    mkdir -m 0700 -- "$action27_retry_a_chain" || return 1
    "$openssl_bin" s_client -connect "$action27_retry_a_endpoint" -servername "$hostname" \
        -verify_hostname "$hostname" -verify_return_error -CApath /etc/ssl/certs \
        -tls1_2 -showcerts </dev/null >"$action27_retry_a_capture" 2>&1 || action27_retry_a_status=$?
    printf '%s_observed_%s_command_status=%s\n' "$prefix" "$action27_retry_a_family" "$action27_retry_a_status"
    printf '%s_observed_%s_capture_bytes=%s\n' "$prefix" "$action27_retry_a_family" "$(wc -c <"$action27_retry_a_capture")"
    printf '%s_observed_%s_capture_lines=%s\n' "$prefix" "$action27_retry_a_family" "$(line_count "$action27_retry_a_capture")"
    printf '%s_observed_%s_capture_sha256=%s\n' "$prefix" "$action27_retry_a_family" "$(file_hash "$action27_retry_a_capture")"
    safe_capture "$action27_retry_a_capture" || return 97
    printf '%s_observed_%s_capture_classification=bounded_public_certificate_suppressed\n' \
        "$prefix" "$action27_retry_a_family"
    check "${action27_retry_a_family}_capture_bounded" safe_capture "$action27_retry_a_capture" || return 1
    check "${action27_retry_a_family}_command_status" test "$action27_retry_a_status" -eq 0 || return 1
    check "${action27_retry_a_family}_verify_return_code" grep -Eq \
        '^[[:space:]]*Verify[[:space:]]+return[[:space:]]+code:[[:space:]]*0[[:space:]]+\(ok\)[[:space:]]*$' \
        "$action27_retry_a_capture" || return 1
    check "${action27_retry_a_family}_protocol_exact" grep -Eq \
        '^[[:space:]]*Protocol[[:space:]]*:[[:space:]]*TLSv1\.2[[:space:]]*$' \
        "$action27_retry_a_capture" || return 1
    extract_chain "$action27_retry_a_capture" "$action27_retry_a_chain" || return 1
    action27_retry_a_chain_count=$(<"$action27_retry_a_chain/count")
    check "${action27_retry_a_family}_chain_count_exact" test \
        "$action27_retry_a_chain_count" -eq 3 || return 1
    derive_identity "$action27_retry_a_family" "$action27_retry_a_chain/cert-1.pem" \
        "$action27_retry_a_chain_count"
}
compare_identity() {
    local action27_retry_a_key=$1
    local action27_retry_a_label=$2
    local action27_retry_a_ipv4=$action27_retry_a_root/ipv4.identity/identity
    local action27_retry_a_ipv6=$action27_retry_a_root/ipv6.identity/identity

    check "$action27_retry_a_label" test "$(metadata_value "$action27_retry_a_key" "$action27_retry_a_ipv4")" = \
        "$(metadata_value "$action27_retry_a_key" "$action27_retry_a_ipv6")"
}
cleanup() {
    local action27_retry_a_status=$?

    trap - EXIT INT TERM
    [[ -z "$action27_retry_a_root" ]] || rm -rf -- "$action27_retry_a_root"
    exit "$action27_retry_a_status"
}
run_action() {
    action27_retry_a_root=$(mktemp -d /tmp/caddy-action27-retry-a.XXXXXX)
    trap cleanup EXIT INT TERM
    check immutable_retry_outer_hash test "$(file_hash "$immutable_retry_outer")" = \
        "$immutable_retry_outer_sha256" || return 1
    check openssl_executable test -x "$openssl_bin" || return 1
    check test_override_boundary test_override_boundary || return 1
    run_probe ipv4 "${ipv4}:443" || return 1
    run_probe ipv6 "[${ipv6}]:443" || return 1
    compare_identity der_sha256 identity_der_consistent || return 1
    compare_identity spki_sha256 identity_spki_consistent || return 1
    compare_identity serial identity_serial_consistent || return 1
    compare_identity subject identity_subject_consistent || return 1
    compare_identity issuer identity_issuer_consistent || return 1
    compare_identity not_before identity_not_before_consistent || return 1
    compare_identity not_after identity_not_after_consistent || return 1
    compare_identity san_sha256 identity_san_digest_consistent || return 1
    compare_identity chain_count identity_chain_count_consistent || return 1
    printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
    printf '%s_probe_count=2\n' "$prefix"
    printf '%s_raw_pem_emitted=false\n' "$prefix"
    printf '%s_node_contact=false\n' "$prefix"
    printf '%s_persistent_mutation=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-checks) expected_checks ;;
    "") run_action ;;
    *) exit 64 ;;
esac
