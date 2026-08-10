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
readonly successor=$caddy_root/scripts/run-workstation-caddy-tls-action27-retry3.sh
regression_root=

report_error() {
    local action27_retry3_regression_error_line=$1
    local action27_retry3_regression_error_status=$2

    printf 'action_27_retry3_regression_failure_line=%s\n' \
        "$action27_retry3_regression_error_line" >&2
    printf 'action_27_retry3_regression_failure_status=%s\n' \
        "$action27_retry3_regression_error_status" >&2
}
trap 'report_error "$LINENO" "$?"' ERR
cleanup() {
    local action27_retry3_regression_status=$?

    trap - EXIT INT TERM
    [[ -z "$regression_root" ]] || rm -rf -- "$regression_root"
    exit "$action27_retry3_regression_status"
}

regression_root=$(mktemp -d /tmp/caddy-action27-retry3-regression.XXXXXX)
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
if [[ "$1" = s_client ]]; then
    protocol=TLSv1.3
    for argument in "$@"; do
        [[ "$argument" != -tls1_2 ]] || protocol=TLSv1.2
    done
    cat "${CADDY_ACTION27_RETRY3_TEST_LEAF:?}" "${CADDY_ACTION27_RETRY3_TEST_CHAIN:?}" |
        awk '
            /-----BEGIN CERTIFICATE-----/ { certificate += 1 }
            { print }
            /-----END CERTIFICATE-----/ { printf "depth=%d production-inter-certificate\n", certificate }
        '
    printf 'Protocol  : %s\n    Verify return code: 0 (ok)   \n' "$protocol"
    exit 0
fi
exec /usr/bin/openssl "$@"
EOF
cat >"$regression_root/fake-curl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_ACTION27_RETRY3_CURL_LOG:?}"
remote=10.1.0.56
for argument in "$@"; do
    [[ "$argument" != *'[fd36:5aa8:6971:1::56]'* ]] || remote=fd36:5aa8:6971:1::56
done
status=${CADDY_ACTION27_RETRY3_FAKE_HTTP_STATUS:-204}
printf 'http_code=%s\nremote_ip=%s\nssl_verify_result=0\nnum_certs=3\nhttp_version=1.1\nsize_download=0\nnum_redirects=0\n' \
    "$status" "$remote"
EOF
chmod 0755 "$regression_root/fake-openssl" "$regression_root/fake-curl"
CADDY_ACTION27_TEST_MODE=1 \
    CADDY_ACTION27_RETRY2_EXPECTED_LEAF_DER_SHA256=$leaf_der_hash \
    CADDY_ACTION27_EXPECTED_NOT_AFTER=$not_after \
    CADDY_ACTION27_RETRY2_RAW_OPENSSL_BIN=$regression_root/fake-openssl \
    CADDY_ACTION27_RETRY3_RAW_CURL_BIN=$regression_root/fake-curl \
    CADDY_ACTION27_RETRY3_TEST_LEAF=$leaf \
    CADDY_ACTION27_RETRY3_TEST_CHAIN=$chain \
    CADDY_ACTION27_RETRY3_CURL_LOG=$regression_root/positive-curl.log \
    /bin/bash "$successor" >"$regression_root/positive.stdout" \
    2>"$regression_root/positive.stderr"
[[ ! -s "$regression_root/positive.stderr" ]]
grep -Fqx 'action_27_retry3_curl_path_scope=/healthz_to_root_only' \
    "$regression_root/positive.stdout"
grep -Fqx 'action_27_retry2_complete=true' "$regression_root/positive.stdout"
[[ "$(wc -l <"$regression_root/positive-curl.log")" -eq 2 ]]
[[ "$(grep -c 'https://proxy.local.theama.co/$' "$regression_root/positive-curl.log")" -eq 2 ]]
if grep -Fq '/healthz' "$regression_root/positive-curl.log"; then
    exit 1
fi
CADDY_ACTION27_TEST_MODE=1 \
    CADDY_ACTION27_RETRY2_EXPECTED_LEAF_DER_SHA256=$leaf_der_hash \
    CADDY_ACTION27_EXPECTED_NOT_AFTER=$not_after \
    CADDY_ACTION27_RETRY2_RAW_OPENSSL_BIN=$regression_root/fake-openssl \
    CADDY_ACTION27_RETRY3_RAW_CURL_BIN=$regression_root/fake-curl \
    CADDY_ACTION27_RETRY3_TEST_LEAF=$leaf \
    CADDY_ACTION27_RETRY3_TEST_CHAIN=$chain \
    CADDY_ACTION27_RETRY3_CURL_LOG=$regression_root/status200-curl.log \
    CADDY_ACTION27_RETRY3_FAKE_HTTP_STATUS=200 \
    /bin/bash "$successor" >"$regression_root/status200.stdout" \
    2>"$regression_root/status200.stderr" && exit 1
grep -Fqx 'action_27_retry2_check_ipv4_curl_http_status=false' \
    "$regression_root/status200.stderr"
printf 'action_27_retry3_regression_full_acceptance_path=true\n'
printf 'action_27_retry3_regression_exact_root_path=true\n'
printf 'action_27_retry3_regression_inherited_healthz_absent=true\n'
printf 'action_27_retry3_regression_status_204_required=true\n'
printf 'action_27_retry3_regression_status_200_rejected=true\n'
printf 'action_27_retry3_regression_live_probe=false\n'
printf 'action_27_retry3_regression_complete=true\n'
