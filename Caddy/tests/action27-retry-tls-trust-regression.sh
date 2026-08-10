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
readonly retry_core=$caddy_root/scripts/run-workstation-caddy-tls-action27-retry.sh
regression_root=

cleanup() {
    local action27_retry_regression_status=$?

    trap - EXIT INT TERM
    [[ -z "$regression_root" ]] || rm -rf -- "$regression_root"
    exit "$action27_retry_regression_status"
}

regression_root=$(mktemp -d /tmp/caddy-action27-retry-regression.XXXXXX)
trap cleanup EXIT INT TERM
/bin/bash "$test_directory/generate-test-certificate.sh" "$regression_root/certificate"
leaf=$regression_root/certificate/input.cert
chain=$regression_root/certificate/input.ca-bundle
leaf_hash=$(sha256sum "$leaf" | awk '{ print $1 }')
not_after=$(/usr/bin/openssl x509 -in "$leaf" -noout -enddate)
not_after=${not_after#notAfter=}
cat >"$regression_root/fake-openssl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_ACTION27_RETRY_OPENSSL_LOG:?}"
if [[ "$1" = s_client ]]; then
    protocol=TLSv1.3
    for argument in "$@"; do
        [[ "$argument" != -tls1_2 ]] || protocol=TLSv1.2
    done
    cat "${CADDY_ACTION27_RETRY_TEST_LEAF:?}"
    cat "${CADDY_ACTION27_RETRY_TEST_CHAIN:?}"
    verify_code=${CADDY_ACTION27_RETRY_FAKE_VERIFY_CODE:-0}
    if [[ "$verify_code" = 0 ]]; then
        printf 'Protocol  : %s\n    Verify return code: 0 (ok)   \n' "$protocol"
    else
        printf 'Protocol  : %s\n    Verify return code: %s (unable to get local issuer certificate)   \n' \
            "$protocol" "$verify_code"
    fi
    exit 0
fi
exec /usr/bin/openssl "$@"
EOF
cat >"$regression_root/fake-curl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_ACTION27_RETRY_CURL_LOG:?}"
remote=10.1.0.56
for argument in "$@"; do
    [[ "$argument" != *'[fd36:5aa8:6971:1::56]'* ]] || remote=fd36:5aa8:6971:1::56
done
printf 'http_code=204\nremote_ip=%s\nssl_verify_result=0\nnum_certs=3\nhttp_version=1.1\nsize_download=0\nnum_redirects=0\n' "$remote"
EOF
chmod 0755 "$regression_root/fake-openssl" "$regression_root/fake-curl"
CADDY_ACTION27_TEST_MODE=1 \
    CADDY_ACTION27_EXPECTED_LEAF_SHA256=$leaf_hash \
    CADDY_ACTION27_EXPECTED_NOT_AFTER=$not_after \
    CADDY_ACTION27_RETRY_RAW_OPENSSL_BIN=$regression_root/fake-openssl \
    CADDY_ACTION27_CURL_BIN=$regression_root/fake-curl \
    CADDY_ACTION27_RETRY_TEST_LEAF=$leaf \
    CADDY_ACTION27_RETRY_TEST_CHAIN=$chain \
    CADDY_ACTION27_RETRY_OPENSSL_LOG=$regression_root/openssl.log \
    CADDY_ACTION27_RETRY_CURL_LOG=$regression_root/curl.log \
    /bin/bash "$retry_core" >"$regression_root/positive.stdout" \
    2>"$regression_root/positive.stderr"
[[ ! -s "$regression_root/positive.stderr" ]]
grep -Fqx 'action_27_retry_normalization_scope=exact_success_verification_line_whitespace_only' \
    "$regression_root/positive.stdout"
grep -Fqx 'action_27_complete=true' "$regression_root/positive.stdout"
[[ "$(grep -c '^s_client ' "$regression_root/openssl.log")" -eq 4 ]]
[[ "$(wc -l <"$regression_root/curl.log")" -eq 2 ]]
if grep -Fq 'action_27_check_ipv4_tls12_verify_return_code=false' \
    "$regression_root/positive.stdout"; then
    exit 1
fi
CADDY_ACTION27_TEST_MODE=1 \
    CADDY_ACTION27_EXPECTED_LEAF_SHA256=$leaf_hash \
    CADDY_ACTION27_EXPECTED_NOT_AFTER=$not_after \
    CADDY_ACTION27_RETRY_RAW_OPENSSL_BIN=$regression_root/fake-openssl \
    CADDY_ACTION27_CURL_BIN=$regression_root/fake-curl \
    CADDY_ACTION27_RETRY_TEST_LEAF=$leaf \
    CADDY_ACTION27_RETRY_TEST_CHAIN=$chain \
    CADDY_ACTION27_RETRY_OPENSSL_LOG=$regression_root/negative-openssl.log \
    CADDY_ACTION27_RETRY_CURL_LOG=$regression_root/negative-curl.log \
    CADDY_ACTION27_RETRY_FAKE_VERIFY_CODE=20 \
    /bin/bash "$retry_core" >"$regression_root/negative.stdout" \
    2>"$regression_root/negative.stderr" && exit 1
grep -Fqx 'action_27_check_ipv4_tls12_verify_return_code=false' \
    "$regression_root/negative.stderr"
if grep -Fq 'action_27_complete=true' "$regression_root/negative.stdout"; then
    exit 1
fi
grep -Fq "Verify return code: 0 (ok)   " "$0"
grep -Fq "Verify return code: %s (unable to get local issuer certificate)" "$0"
printf 'action_27_retry_regression_production_whitespace_encoded=true\n'
printf 'action_27_retry_regression_exact_success_normalized=true\n'
printf 'action_27_retry_regression_nonzero_verify_rejected=true\n'
printf 'action_27_retry_regression_live_probe=false\n'
printf 'action_27_retry_regression_complete=true\n'
