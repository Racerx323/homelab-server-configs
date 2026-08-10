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
readonly immutable_diagnostic=$caddy_root/scripts/run-workstation-caddy-certificate-identity-action27-retry-a.sh
readonly corrected_diagnostic=$caddy_root/scripts/run-workstation-caddy-certificate-identity-action27-retry-a-retry.sh
regression_root=

cleanup() {
    local action27_retry_a_retry_regression_status=$?

    trap - EXIT INT TERM
    [[ -z "$regression_root" ]] || rm -rf -- "$regression_root"
    exit "$action27_retry_a_retry_regression_status"
}

regression_root=$(mktemp -d /tmp/caddy-action27-retry-a-retry-regression.XXXXXX)
trap cleanup EXIT INT TERM
/bin/bash "$test_directory/generate-test-certificate.sh" "$regression_root/certificate"
leaf=$regression_root/certificate/input.cert
chain=$regression_root/certificate/input.ca-bundle
not_after=$(/usr/bin/openssl x509 -in "$leaf" -noout -enddate)
not_after=${not_after#notAfter=}
{
    cat "$leaf" "$chain"
} | awk '
    /-----BEGIN CERTIFICATE-----/ { certificate += 1 }
    { print }
    /-----END CERTIFICATE-----/ {
        printf "depth=%d verify return:1 subject=CN = production-inter-certificate-%d\n", certificate, certificate
    }
' >"$regression_root/production-transcript"
printf '    Protocol  : TLSv1.2\n    Verify return code: 0 (ok)   \n' \
    >>"$regression_root/production-transcript"
{
    cat "$leaf" "$chain"
} | awk '
    /-----BEGIN CERTIFICATE-----/ { certificate += 1 }
    certificate == 3 && /-----END CERTIFICATE-----/ { next }
    { print }
    /-----END CERTIFICATE-----/ { print "depth=1 malformed-production-inter-certificate" }
' >"$regression_root/malformed-transcript"
printf '    Protocol  : TLSv1.2\n    Verify return code: 0 (ok)   \n' \
    >>"$regression_root/malformed-transcript"
cat >"$regression_root/fake-openssl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_ACTION27_RETRY_A_RETRY_OPENSSL_LOG:?}"
if [[ "$1" = s_client ]]; then
    cat "${CADDY_ACTION27_RETRY_A_RETRY_TRANSCRIPT:?}"
    exit 0
fi
exec /usr/bin/openssl "$@"
EOF
chmod 0755 "$regression_root/fake-openssl"
if CADDY_ACTION27_RETRY_A_TEST_MODE=1 \
    CADDY_ACTION27_RETRY_A_EXPECTED_NOT_AFTER=$not_after \
    CADDY_ACTION27_RETRY_A_OPENSSL_BIN=$regression_root/fake-openssl \
    CADDY_ACTION27_RETRY_A_RETRY_TRANSCRIPT=$regression_root/production-transcript \
    CADDY_ACTION27_RETRY_A_RETRY_OPENSSL_LOG=$regression_root/predecessor-openssl.log \
    /bin/bash "$immutable_diagnostic" >"$regression_root/predecessor.stdout" \
    2>"$regression_root/predecessor.stderr"; then
    exit 1
fi
grep -Fq 'Could not read certificate' "$regression_root/predecessor.stderr"
CADDY_ACTION27_RETRY_A_TEST_MODE=1 \
    CADDY_ACTION27_RETRY_A_EXPECTED_NOT_AFTER=$not_after \
    CADDY_ACTION27_RETRY_A_RETRY_RAW_OPENSSL_BIN=$regression_root/fake-openssl \
    CADDY_ACTION27_RETRY_A_RETRY_TRANSCRIPT=$regression_root/production-transcript \
    CADDY_ACTION27_RETRY_A_RETRY_OPENSSL_LOG=$regression_root/corrected-openssl.log \
    /bin/bash "$corrected_diagnostic" >"$regression_root/corrected.stdout" \
    2>"$regression_root/corrected.stderr"
[[ ! -s "$regression_root/corrected.stderr" ]]
grep -Fqx 'action_27_retry_a_retry_extraction_scope=explicit_begin_end_certificate_state' \
    "$regression_root/corrected.stdout"
grep -Fqx 'action_27_retry_a_check_identity_der_consistent=true' \
    "$regression_root/corrected.stdout"
grep -Fqx 'action_27_retry_a_check_identity_spki_consistent=true' \
    "$regression_root/corrected.stdout"
grep -Fqx 'action_27_retry_a_complete=true' "$regression_root/corrected.stdout"
[[ "$(grep -c '^s_client ' "$regression_root/corrected-openssl.log")" -eq 2 ]]
if grep -Fq -- '-----BEGIN CERTIFICATE-----' "$regression_root/corrected.stdout"; then
    exit 1
fi
if CADDY_ACTION27_RETRY_A_TEST_MODE=1 \
    CADDY_ACTION27_RETRY_A_EXPECTED_NOT_AFTER=$not_after \
    CADDY_ACTION27_RETRY_A_RETRY_RAW_OPENSSL_BIN=$regression_root/fake-openssl \
    CADDY_ACTION27_RETRY_A_RETRY_TRANSCRIPT=$regression_root/malformed-transcript \
    CADDY_ACTION27_RETRY_A_RETRY_OPENSSL_LOG=$regression_root/malformed-openssl.log \
    /bin/bash "$corrected_diagnostic" >"$regression_root/malformed.stdout" \
    2>"$regression_root/malformed.stderr"; then
    exit 1
fi
grep -Fqx 'action_27_retry_a_check_ipv4_command_status=false' \
    "$regression_root/malformed.stderr"
if grep -Fq 'action_27_retry_a_complete=true' "$regression_root/malformed.stdout"; then
    exit 1
fi
grep -Fq 'production-inter-certificate' "$regression_root/production-transcript"
printf 'action_27_retry_a_retry_regression_predecessor_corruption_reproduced=true\n'
printf 'action_27_retry_a_retry_regression_inter_certificate_text_isolated=true\n'
printf 'action_27_retry_a_retry_regression_unterminated_block_rejected=true\n'
printf 'action_27_retry_a_retry_regression_raw_pem_emitted=false\n'
printf 'action_27_retry_a_retry_regression_live_probe=false\n'
printf 'action_27_retry_a_retry_regression_complete=true\n'
