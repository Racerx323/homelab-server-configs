#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_27_retry2
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly immutable_core=$script_directory/run-workstation-caddy-tls-action27.sh
readonly accepted_identity_outer=$script_directory/run-workstation-caddy-certificate-identity-action27-retry-a-retry-outer.sh
readonly accepted_http3_outer=$script_directory/run-workstation-caddy-http3-action26-h3-retry-outer.sh
readonly immutable_core_sha256=b39eeff2a60beefd4b9e0528a54dda63e6a0f150881b01183a2fc0066efdbfad
readonly accepted_identity_outer_sha256=58a7aed3b6e290b31601b5ee0ecd9701090ce0efd5097441f34d5fe6af6fbc71
readonly accepted_leaf_der_sha256=9480cfd689e5804a103ca192849e3ef5810b4e1c37918fbcc2815e864da5580c
readonly generated_core_sha256=65494de08968f573b3c9a5a04c9b4cc2cc6a12317528da3e31dd275148ce0fdf
readonly raw_openssl_bin=${CADDY_ACTION27_RETRY2_RAW_OPENSSL_BIN:-/usr/bin/openssl}
action27_retry2_root=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local action27_retry2_check_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action27_retry2_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action27_retry2_check_label" >&2
    return 1
}
expected_checks() {
    printf '%s\n' immutable_core_hash accepted_identity_outer_hash raw_openssl_executable \
        corrected_core_regular corrected_core_executable corrected_core_hash \
        transformer_contract adapter_regular adapter_executable adapter_contract
}
transform_core() {
    local action27_retry2_output=$1

    # These substitutions intentionally match literal immutable-core source.
    # shellcheck disable=SC2016
    sed \
        -e 's/^readonly prefix=action_27$/readonly prefix=action_27_retry2/' \
        -e "s/^readonly production_leaf_sha256=.*/readonly production_leaf_der_sha256=${accepted_leaf_der_sha256}/" \
        -e 's/production_leaf_sha256/production_leaf_der_sha256/g' \
        -e 's/expected_leaf_hash/expected_leaf_der_hash/g' \
        -e 's/CADDY_ACTION27_EXPECTED_LEAF_SHA256/CADDY_ACTION27_RETRY2_EXPECTED_LEAF_DER_SHA256/g' \
        -e 's/leaf_hash_exact/leaf_der_sha256_exact/g' \
        -e 's/leaf_hash_consistent/leaf_der_sha256_consistent/g' \
        -e 's/action27_leaf_hash/action27_leaf_der_hash/g' \
        -e 's/_leaf_sha256=/_leaf_der_sha256=/g' \
        -e 's/file_hash "$action27_chain_directory\/cert-1.pem"/certificate_der_hash "$action27_chain_directory\/cert-1.pem"/' \
        -e 's/file_hash "$action27_root\/$action27_probe.chain\/cert-1.pem"/certificate_der_hash "$action27_root\/$action27_probe.chain\/cert-1.pem"/' \
        "$immutable_core" |
        awk '
            { print }
            /^file_hash\(\)/ {
                print "certificate_der_hash() { \"$openssl_bin\" x509 -in \"$1\" -outform DER | sha256sum | awk \047{ print $1 }\047; }"
            }
        ' >"$action27_retry2_output"
    chmod 0700 "$action27_retry2_output"
}
transformer_contract() {
    local action27_retry2_core=$1

    grep -Fqx 'readonly prefix=action_27_retry2' "$action27_retry2_core" || return 1
    grep -Fqx "readonly production_leaf_der_sha256=$accepted_leaf_der_sha256" \
        "$action27_retry2_core" || return 1
    [[ "$(grep -o 'leaf_der_sha256_exact' "$action27_retry2_core" | wc -l)" -eq 2 ]] || return 1
    [[ "$(grep -o 'leaf_der_sha256_consistent' "$action27_retry2_core" | wc -l)" -eq 5 ]] || return 1
    [[ "$(grep -o 'certificate_der_hash' "$action27_retry2_core" | wc -l)" -eq 3 ]] || return 1
    if grep -Eq 'production_leaf_sha256|expected_leaf_hash|leaf_hash_exact|leaf_hash_consistent|CADDY_ACTION27_EXPECTED_LEAF_SHA256' \
        "$action27_retry2_core"; then
        return 1
    fi
}
create_adapter() {
    local action27_retry2_adapter=$1

    cat >"$action27_retry2_adapter" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH
readonly raw_openssl_bin=${CADDY_ACTION27_RETRY2_RAW_OPENSSL_BIN:-/usr/bin/openssl}
adapter_root=
adapter_cleanup() {
    local adapter_status=$?

    trap - EXIT INT TERM
    [[ -z "$adapter_root" ]] || rm -rf -- "$adapter_root"
    exit "$adapter_status"
}
if [[ "${1:-}" = s_client ]]; then
    adapter_root=$(mktemp -d /tmp/caddy-action27-retry2-adapter.XXXXXX)
    trap adapter_cleanup EXIT INT TERM
    adapter_raw=$adapter_root/raw
    adapter_metadata=$adapter_root/metadata
    adapter_certificates=$adapter_root/certificates
    adapter_status=0
    "$raw_openssl_bin" "$@" >"$adapter_raw" 2>&1 || adapter_status=$?
    awk -v metadata="$adapter_metadata" -v certificates="$adapter_certificates" '
        BEGIN { inside_certificate = 0; malformed = 0; certificate_count = 0 }
        /-----BEGIN CERTIFICATE-----/ {
            if (inside_certificate) malformed = 1
            inside_certificate = 1
            certificate_count += 1
            print > certificates
            next
        }
        /-----END CERTIFICATE-----/ {
            if (!inside_certificate) malformed = 1
            print > certificates
            inside_certificate = 0
            next
        }
        {
            if (inside_certificate) print > certificates
            else print > metadata
        }
        END { if (inside_certificate || malformed || certificate_count == 0) exit 65 }
    ' "$adapter_raw" || exit 65
    [[ -s "$adapter_metadata" && -s "$adapter_certificates" ]] || exit 65
    sed -E \
        -e 's/^[[:space:]]*Verify[[:space:]]+return[[:space:]]+code:[[:space:]]*0[[:space:]]+\(ok\)[[:space:]]*$/Verify return code: 0 (ok)/' \
        "$adapter_metadata"
    cat "$adapter_certificates"
    exit "$adapter_status"
fi
exec "$raw_openssl_bin" "$@"
EOF
    chmod 0700 "$action27_retry2_adapter"
}
adapter_contract() {
    grep -Fq 'inside_certificate = 1' "$0" || return 1
    grep -Fq 'inside_certificate = 0' "$0" || return 1
    grep -Fq 'Verify return code: 0 (ok)' "$0" || return 1
    grep -Fq 'inside_certificate || malformed || certificate_count == 0' "$0"
}
cleanup() {
    local action27_retry2_status=$?

    trap - EXIT INT TERM
    [[ -z "$action27_retry2_root" ]] || rm -rf -- "$action27_retry2_root"
    exit "$action27_retry2_status"
}
prepare() {
    local action27_retry2_core=$1
    local action27_retry2_adapter=$2

    check immutable_core_hash test "$(file_hash "$immutable_core")" = "$immutable_core_sha256" || return 1
    check accepted_identity_outer_hash test "$(file_hash "$accepted_identity_outer")" = \
        "$accepted_identity_outer_sha256" || return 1
    check raw_openssl_executable test -x "$raw_openssl_bin" || return 1
    transform_core "$action27_retry2_core" || return 1
    check corrected_core_regular test -f "$action27_retry2_core" || return 1
    check corrected_core_executable test -x "$action27_retry2_core" || return 1
    check corrected_core_hash test "$(file_hash "$action27_retry2_core")" = "$generated_core_sha256" || return 1
    check transformer_contract transformer_contract "$action27_retry2_core" || return 1
    install -m 0500 -- "$accepted_http3_outer" \
        "${action27_retry2_core%/*}/run-workstation-caddy-http3-action26-h3-retry-outer.sh" || return 1
    create_adapter "$action27_retry2_adapter" || return 1
    check adapter_regular test -f "$action27_retry2_adapter" || return 1
    check adapter_executable test -x "$action27_retry2_adapter" || return 1
    check adapter_contract adapter_contract || return 1
}
run_action() {
    local action27_retry2_core
    local action27_retry2_adapter

    action27_retry2_root=$(mktemp -d /tmp/caddy-action27-retry2.XXXXXX)
    trap cleanup EXIT INT TERM
    action27_retry2_core=$action27_retry2_root/corrected-core
    action27_retry2_adapter=$action27_retry2_root/openssl-adapter
    prepare "$action27_retry2_core" "$action27_retry2_adapter" || return 1
    printf '%s_identity_scope=canonical_leaf_der_sha256\n' "$prefix"
    printf '%s_certificate_extraction=explicit_begin_end_state\n' "$prefix"
    printf '%s_verification_normalization=exact_success_line_whitespace_only\n' "$prefix"
    CADDY_ACTION27_OPENSSL_BIN=$action27_retry2_adapter \
        /bin/bash "$action27_retry2_core"
}
print_generated_hash() {
    local action27_retry2_hash_root
    local action27_retry2_hash_core

    action27_retry2_hash_root=$(mktemp -d /tmp/caddy-action27-retry2-hash.XXXXXX)
    action27_retry2_hash_core=$action27_retry2_hash_root/core
    transform_core "$action27_retry2_hash_core"
    file_hash "$action27_retry2_hash_core"
    rm -rf -- "$action27_retry2_hash_root"
}

case "${1:-}" in
    --expected-checks) expected_checks ;;
    --expected-core-checks)
        action27_retry2_root=$(mktemp -d /tmp/caddy-action27-retry2-checks.XXXXXX)
        trap cleanup EXIT INT TERM
        transform_core "$action27_retry2_root/core"
        /bin/bash "$action27_retry2_root/core" --expected-checks
        ;;
    --print-generated-hash) print_generated_hash ;;
    "") run_action ;;
    *) exit 64 ;;
esac
