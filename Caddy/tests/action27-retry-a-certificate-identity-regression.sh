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
readonly diagnostic=$caddy_root/scripts/run-workstation-caddy-certificate-identity-action27-retry-a.sh
regression_root=

cleanup() {
    local action27_retry_a_regression_status=$?

    trap - EXIT INT TERM
    [[ -z "$regression_root" ]] || rm -rf -- "$regression_root"
    exit "$action27_retry_a_regression_status"
}

regression_root=$(mktemp -d /tmp/caddy-action27-retry-a-regression.XXXXXX)
trap cleanup EXIT INT TERM
/bin/bash "$test_directory/generate-test-certificate.sh" "$regression_root/certificate"
leaf=$regression_root/certificate/input.cert
chain=$regression_root/certificate/input.ca-bundle
not_after=$(/usr/bin/openssl x509 -in "$leaf" -noout -enddate)
not_after=${not_after#notAfter=}
/usr/bin/openssl x509 -in "$leaf" -outform DER -out "$regression_root/expected.der"
expected_der_sha256=$(sha256sum "$regression_root/expected.der" | awk '{ print $1 }')
/usr/bin/openssl x509 -in "$leaf" -pubkey -noout |
    /usr/bin/openssl pkey -pubin -outform DER -out "$regression_root/expected.spki.der"
expected_spki_sha256=$(sha256sum "$regression_root/expected.spki.der" | awk '{ print $1 }')
cat >"$regression_root/fake-openssl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_ACTION27_RETRY_A_OPENSSL_LOG:?}"
if [[ "$1" = s_client ]]; then
    cat "${CADDY_ACTION27_RETRY_A_TEST_LEAF:?}"
    cat "${CADDY_ACTION27_RETRY_A_TEST_CHAIN:?}"
    printf '    Protocol  : TLSv1.2\n    Verify return code: 0 (ok)   \n'
    exit 0
fi
if [[ "${CADDY_ACTION27_RETRY_A_FAKE_DER_DRIFT:-}" = 1 && "$1" = x509 ]]; then
    original_arguments=("$@")
    input=
    output=
    output_form=
    while (($#)); do
        case "$1" in
            -in)
                input=$2
                shift 2
                ;;
            -out)
                output=$2
                shift 2
                ;;
            -outform)
                output_form=$2
                shift 2
                ;;
            *) shift ;;
        esac
    done
    if [[ "$input" = */ipv6.chain/* && "$output_form" = DER && -n "$output" ]]; then
        /usr/bin/openssl x509 -in "$input" -outform DER -out "$output"
        printf 'X' >>"$output"
        exit 0
    fi
    exec /usr/bin/openssl "${original_arguments[@]}"
fi
exec /usr/bin/openssl "$@"
EOF
chmod 0755 "$regression_root/fake-openssl"
CADDY_ACTION27_RETRY_A_TEST_MODE=1 \
    CADDY_ACTION27_RETRY_A_EXPECTED_NOT_AFTER=$not_after \
    CADDY_ACTION27_RETRY_A_OPENSSL_BIN=$regression_root/fake-openssl \
    CADDY_ACTION27_RETRY_A_TEST_LEAF=$leaf \
    CADDY_ACTION27_RETRY_A_TEST_CHAIN=$chain \
    CADDY_ACTION27_RETRY_A_OPENSSL_LOG=$regression_root/positive-openssl.log \
    /bin/bash "$diagnostic" >"$regression_root/positive.stdout" \
    2>"$regression_root/positive.stderr"
[[ ! -s "$regression_root/positive.stderr" ]]
grep -Fqx "action_27_retry_a_observed_ipv4_der_sha256=$expected_der_sha256" \
    "$regression_root/positive.stdout"
grep -Fqx "action_27_retry_a_observed_ipv6_der_sha256=$expected_der_sha256" \
    "$regression_root/positive.stdout"
grep -Fqx "action_27_retry_a_observed_ipv4_spki_sha256=$expected_spki_sha256" \
    "$regression_root/positive.stdout"
grep -Fqx "action_27_retry_a_observed_ipv6_spki_sha256=$expected_spki_sha256" \
    "$regression_root/positive.stdout"
grep -Fqx 'action_27_retry_a_check_identity_der_consistent=true' \
    "$regression_root/positive.stdout"
grep -Fqx 'action_27_retry_a_check_identity_spki_consistent=true' \
    "$regression_root/positive.stdout"
grep -Fqx 'action_27_retry_a_complete=true' "$regression_root/positive.stdout"
[[ "$(grep -c '^s_client ' "$regression_root/positive-openssl.log")" -eq 2 ]]
if grep -Fq -- '-----BEGIN CERTIFICATE-----' "$regression_root/positive.stdout"; then
    exit 1
fi
CADDY_ACTION27_RETRY_A_TEST_MODE=1 \
    CADDY_ACTION27_RETRY_A_EXPECTED_NOT_AFTER=$not_after \
    CADDY_ACTION27_RETRY_A_OPENSSL_BIN=$regression_root/fake-openssl \
    CADDY_ACTION27_RETRY_A_TEST_LEAF=$leaf \
    CADDY_ACTION27_RETRY_A_TEST_CHAIN=$chain \
    CADDY_ACTION27_RETRY_A_OPENSSL_LOG=$regression_root/negative-openssl.log \
    CADDY_ACTION27_RETRY_A_FAKE_DER_DRIFT=1 \
    /bin/bash "$diagnostic" >"$regression_root/negative.stdout" \
    2>"$regression_root/negative.stderr" && exit 1
grep -Fqx 'action_27_retry_a_check_identity_der_consistent=false' \
    "$regression_root/negative.stderr"
if grep -Fq 'action_27_retry_a_complete=true' "$regression_root/negative.stdout"; then
    exit 1
fi
printf 'action_27_retry_a_regression_canonical_der=true\n'
printf 'action_27_retry_a_regression_canonical_spki=true\n'
printf 'action_27_retry_a_regression_cross_family_drift_rejected=true\n'
printf 'action_27_retry_a_regression_raw_pem_emitted=false\n'
printf 'action_27_retry_a_regression_live_probe=false\n'
printf 'action_27_retry_a_regression_complete=true\n'
