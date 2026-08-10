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
readonly core=$caddy_root/scripts/run-workstation-caddy-tls-action27.sh
readonly outer=$caddy_root/scripts/run-workstation-caddy-tls-action27-outer.sh
regression_root=
action27_regression_core_status=0

cleanup() {
    local action27_regression_status=$?

    trap - EXIT INT TERM
    [[ -z "$regression_root" ]] || rm -rf -- "$regression_root"
    exit "$action27_regression_status"
}

regression_root=$(mktemp -d /tmp/caddy-action27-regression.XXXXXX)
trap cleanup EXIT INT TERM
/bin/bash "$test_directory/generate-test-certificate.sh" "$regression_root/certificate"
leaf=$regression_root/certificate/input.cert
intermediate=$regression_root/certificate/input.ca-bundle
leaf_hash=$(sha256sum "$leaf" | awk '{ print $1 }')
not_after=$(/usr/bin/openssl x509 -in "$leaf" -noout -enddate)
not_after=${not_after#notAfter=}
cat >"$regression_root/fake-openssl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_ACTION27_OPENSSL_LOG:?}"
if [[ "$1" = s_client ]]; then
    protocol=TLSv1.3
    for argument in "$@"; do
        [[ "$argument" != -tls1_2 ]] || protocol=TLSv1.2
    done
    cat "${CADDY_ACTION27_TEST_LEAF:?}"
    cat "${CADDY_ACTION27_TEST_CHAIN:?}"
    verify_code=${CADDY_ACTION27_FAKE_VERIFY_CODE:-0}
    verify_text=ok
    [[ "$verify_code" = 0 ]] || verify_text='unable to get local issuer certificate'
    printf 'Protocol  : %s\nVerify return code: %s (%s)\n' "$protocol" "$verify_code" "$verify_text"
    exit 0
fi
exec /usr/bin/openssl "$@"
EOF
cat >"$regression_root/fake-curl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_ACTION27_CURL_LOG:?}"
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
    CADDY_ACTION27_OPENSSL_BIN=$regression_root/fake-openssl \
    CADDY_ACTION27_CURL_BIN=$regression_root/fake-curl \
    CADDY_ACTION27_TEST_LEAF=$leaf \
    CADDY_ACTION27_TEST_CHAIN=$intermediate \
    CADDY_ACTION27_OPENSSL_LOG=$regression_root/openssl.log \
    CADDY_ACTION27_CURL_LOG=$regression_root/curl.log \
    CADDY_ACTION27_SKIP_REGRESSION=true \
    /bin/bash "$outer" >"$regression_root/core.stdout" 2>"$regression_root/core.stderr" ||
    action27_regression_core_status=$?
if [[ "$action27_regression_core_status" -ne 0 ]]; then
    printf 'action_27_regression_core_status=%s\n' "$action27_regression_core_status" >&2
    cat "$regression_root/core.stdout" >&2
    cat "$regression_root/core.stderr" >&2
    exit 1
fi
[[ ! -s "$regression_root/core.stderr" ]]
grep -Fqx 'action_27_outer_complete=true' "$regression_root/core.stdout"
[[ "$(grep -c '^s_client ' "$regression_root/openssl.log")" -eq 4 ]]
[[ "$(wc -l <"$regression_root/curl.log")" -eq 2 ]]
grep -Fq -- '-connect 10.1.0.56:443 -servername proxy.local.theama.co -verify_hostname proxy.local.theama.co -verify_return_error -CApath /etc/ssl/certs -tls1_2 -showcerts' "$regression_root/openssl.log"
grep -Fq -- '-connect [fd36:5aa8:6971:1::56]:443 -servername proxy.local.theama.co -verify_hostname proxy.local.theama.co -verify_return_error -CApath /etc/ssl/certs -tls1_3 -showcerts' "$regression_root/openssl.log"
grep -Fq -- '--resolve proxy.local.theama.co:443:10.1.0.56' "$regression_root/curl.log"
grep -Fq -- '--resolve proxy.local.theama.co:443:[fd36:5aa8:6971:1::56]' "$regression_root/curl.log"
if grep -Eq -- '(^|[[:space:]])(-k|--insecure)([[:space:]]|$)' \
    "$regression_root/openssl.log" "$regression_root/curl.log"; then
    exit 1
fi
if grep -Fq -- '-----BEGIN CERTIFICATE-----' "$regression_root/core.stdout"; then
    exit 1
fi
grep -Fqx 'action_27_check_san_nested_hostname_rejected=true' "$regression_root/core.stdout"
grep -Fqx 'action_27_insecure_flag=false' "$regression_root/core.stdout"
CADDY_ACTION27_TEST_MODE=1 \
    CADDY_ACTION27_EXPECTED_LEAF_SHA256=$leaf_hash \
    CADDY_ACTION27_EXPECTED_NOT_AFTER=$not_after \
    CADDY_ACTION27_OPENSSL_BIN=$regression_root/fake-openssl \
    CADDY_ACTION27_CURL_BIN=$regression_root/fake-curl \
    CADDY_ACTION27_TEST_LEAF=$leaf \
    CADDY_ACTION27_TEST_CHAIN=$intermediate \
    CADDY_ACTION27_OPENSSL_LOG=$regression_root/negative-openssl.log \
    CADDY_ACTION27_CURL_LOG=$regression_root/negative-curl.log \
    CADDY_ACTION27_FAKE_VERIFY_CODE=20 \
    /bin/bash "$core" >"$regression_root/negative.stdout" \
    2>"$regression_root/negative.stderr" && exit 1
grep -Fqx 'action_27_check_ipv4_tls12_verify_return_code=false' \
    "$regression_root/negative.stderr"
if grep -Fq 'action_27_complete=true' "$regression_root/negative.stdout"; then
    exit 1
fi
printf 'action_27_regression_exact_production_commands=true\n'
printf 'action_27_regression_false_trust_rejected=true\n'
printf 'action_27_regression_private_material_emitted=false\n'
printf 'action_27_regression_live_probe=false\n'
printf 'action_27_regression_complete=true\n'
