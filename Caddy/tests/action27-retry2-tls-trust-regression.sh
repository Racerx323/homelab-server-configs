#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly successor=$caddy_root/scripts/run-workstation-caddy-tls-action27-retry2.sh
regression_root=

report_error() {
    local action27_retry2_regression_error_line=$1
    local action27_retry2_regression_error_status=$2

    printf 'action_27_retry2_regression_failure_line=%s\n' \
        "$action27_retry2_regression_error_line" >&2
    printf 'action_27_retry2_regression_failure_status=%s\n' \
        "$action27_retry2_regression_error_status" >&2
}
trap 'report_error "$LINENO" "$?"' ERR

cleanup() {
    local action27_retry2_regression_status=$?

    trap - EXIT INT TERM
    [[ -z "$regression_root" ]] || rm -rf -- "$regression_root"
    exit "$action27_retry2_regression_status"
}

regression_root=$(mktemp -d /tmp/caddy-action27-retry2-regression.XXXXXX)
trap cleanup EXIT INT TERM
/bin/bash "$test_directory/generate-test-certificate.sh" "$regression_root/certificate"
leaf=$regression_root/certificate/input.cert
chain=$regression_root/certificate/input.ca-bundle
leaf_der_hash=$(/usr/bin/openssl x509 -in "$leaf" -outform DER | sha256sum | awk '{ print $1 }')
not_after=$(/usr/bin/openssl x509 -in "$leaf" -noout -enddate)
not_after=${not_after#notAfter=}
cat >"$regression_root/fake-openssl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_ACTION27_RETRY2_OPENSSL_LOG:?}"
if [[ "$1" = s_client ]]; then
    protocol=TLSv1.3
    for argument in "$@"; do
        [[ "$argument" != -tls1_2 ]] || protocol=TLSv1.2
    done
    certificate=0
    cat "${CADDY_ACTION27_RETRY2_TEST_LEAF:?}" "${CADDY_ACTION27_RETRY2_TEST_CHAIN:?}" |
        awk '
            /-----BEGIN CERTIFICATE-----/ { certificate += 1 }
            { print }
            /-----END CERTIFICATE-----/ {
                printf "depth=%d verify return:1 subject=CN = production-inter-certificate-%d\n", certificate, certificate
            }
        '
    verify_code=${CADDY_ACTION27_RETRY2_FAKE_VERIFY_CODE:-0}
    if [[ "$verify_code" = 0 ]]; then
        printf 'Protocol  : %s\n    Verify return code: 0 (ok)   \n' "$protocol"
    else
        printf 'Protocol  : %s\n Verify return code: %s (unable to get local issuer certificate) \n' \
            "$protocol" "$verify_code"
    fi
    exit 0
fi
exec /usr/bin/openssl "$@"
EOF
cat >"$regression_root/fake-curl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_ACTION27_RETRY2_CURL_LOG:?}"
remote=10.1.0.56
for argument in "$@"; do
    [[ "$argument" != *'[fd36:5aa8:6971:1::56]'* ]] || remote=fd36:5aa8:6971:1::56
done
printf 'http_code=204\nremote_ip=%s\nssl_verify_result=0\nnum_certs=3\nhttp_version=1.1\nsize_download=0\nnum_redirects=0\n' "$remote"
EOF
chmod 0755 "$regression_root/fake-openssl" "$regression_root/fake-curl"
positive_status=0
CADDY_ACTION27_TEST_MODE=1 \
    CADDY_ACTION27_RETRY2_EXPECTED_LEAF_DER_SHA256=$leaf_der_hash \
    CADDY_ACTION27_EXPECTED_NOT_AFTER=$not_after \
    CADDY_ACTION27_RETRY2_RAW_OPENSSL_BIN=$regression_root/fake-openssl \
    CADDY_ACTION27_CURL_BIN=$regression_root/fake-curl \
    CADDY_ACTION27_RETRY2_TEST_LEAF=$leaf \
    CADDY_ACTION27_RETRY2_TEST_CHAIN=$chain \
    CADDY_ACTION27_RETRY2_OPENSSL_LOG=$regression_root/openssl.log \
    CADDY_ACTION27_RETRY2_CURL_LOG=$regression_root/curl.log \
    /bin/bash "$successor" >"$regression_root/positive.stdout" \
    2>"$regression_root/positive.stderr" || positive_status=$?
if [[ "$positive_status" -ne 0 ]]; then
    cat "$regression_root/positive.stdout"
    cat "$regression_root/positive.stderr" >&2
    exit "$positive_status"
fi
[[ ! -s "$regression_root/positive.stderr" ]]
grep -Fqx 'action_27_retry2_identity_scope=canonical_leaf_der_sha256' \
    "$regression_root/positive.stdout"
grep -Fqx 'action_27_retry2_certificate_extraction=explicit_begin_end_state' \
    "$regression_root/positive.stdout"
grep -Fqx 'action_27_retry2_complete=true' "$regression_root/positive.stdout"
[[ "$(grep -c '^action_27_retry2_check_.*leaf_der_sha256_exact=true$' "$regression_root/positive.stdout")" -eq 4 ]]
[[ "$(grep -c '^action_27_retry2_check_leaf_der_sha256_consistent_.*=true$' "$regression_root/positive.stdout")" -eq 4 ]]
[[ "$(grep -c '^s_client ' "$regression_root/openssl.log")" -eq 4 ]]
[[ "$(wc -l <"$regression_root/curl.log")" -eq 2 ]]
if grep -Fq -- '-----BEGIN CERTIFICATE-----' "$regression_root/positive.stdout"; then
    exit 1
fi
CADDY_ACTION27_TEST_MODE=1 \
    CADDY_ACTION27_RETRY2_EXPECTED_LEAF_DER_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    CADDY_ACTION27_EXPECTED_NOT_AFTER=$not_after \
    CADDY_ACTION27_RETRY2_RAW_OPENSSL_BIN=$regression_root/fake-openssl \
    CADDY_ACTION27_CURL_BIN=$regression_root/fake-curl \
    CADDY_ACTION27_RETRY2_TEST_LEAF=$leaf \
    CADDY_ACTION27_RETRY2_TEST_CHAIN=$chain \
    CADDY_ACTION27_RETRY2_OPENSSL_LOG=$regression_root/wrong-der-openssl.log \
    CADDY_ACTION27_RETRY2_CURL_LOG=$regression_root/wrong-der-curl.log \
    /bin/bash "$successor" >"$regression_root/wrong-der.stdout" \
    2>"$regression_root/wrong-der.stderr" && exit 1
grep -Fqx 'action_27_retry2_check_ipv4_tls12_leaf_der_sha256_exact=false' \
    "$regression_root/wrong-der.stderr"
CADDY_ACTION27_TEST_MODE=1 \
    CADDY_ACTION27_RETRY2_EXPECTED_LEAF_DER_SHA256=$leaf_der_hash \
    CADDY_ACTION27_EXPECTED_NOT_AFTER=$not_after \
    CADDY_ACTION27_RETRY2_RAW_OPENSSL_BIN=$regression_root/fake-openssl \
    CADDY_ACTION27_CURL_BIN=$regression_root/fake-curl \
    CADDY_ACTION27_RETRY2_TEST_LEAF=$leaf \
    CADDY_ACTION27_RETRY2_TEST_CHAIN=$chain \
    CADDY_ACTION27_RETRY2_OPENSSL_LOG=$regression_root/nonzero-openssl.log \
    CADDY_ACTION27_RETRY2_CURL_LOG=$regression_root/nonzero-curl.log \
    CADDY_ACTION27_RETRY2_FAKE_VERIFY_CODE=20 \
    /bin/bash "$successor" >"$regression_root/nonzero.stdout" \
    2>"$regression_root/nonzero.stderr" && exit 1
grep -Fqx 'action_27_retry2_check_ipv4_tls12_verify_return_code=false' \
    "$regression_root/nonzero.stderr"
grep -Fq 'production-inter-certificate' "$0"
printf 'action_27_retry2_regression_full_acceptance_path=true\n'
printf 'action_27_retry2_regression_canonical_der_identity=true\n'
printf 'action_27_retry2_regression_inter_certificate_text_isolated=true\n'
printf 'action_27_retry2_regression_wrong_der_rejected=true\n'
printf 'action_27_retry2_regression_nonzero_verify_rejected=true\n'
printf 'action_27_retry2_regression_raw_pem_emitted=false\n'
printf 'action_27_retry2_regression_live_probe=false\n'
printf 'action_27_retry2_regression_complete=true\n'
