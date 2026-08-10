#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_27_retry_a_retry
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly immutable_diagnostic=$script_directory/run-workstation-caddy-certificate-identity-action27-retry-a.sh
readonly immutable_diagnostic_sha256=4fc72118c8ede79676e6e673951b0321d8add15355e62221d018ffac1b84b8b9
readonly raw_openssl_bin=${CADDY_ACTION27_RETRY_A_RETRY_RAW_OPENSSL_BIN:-/usr/bin/openssl}
action27_retry_a_retry_root=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local action27_retry_a_retry_check_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action27_retry_a_retry_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action27_retry_a_retry_check_label" >&2
    return 1
}
expected_checks() {
    printf '%s\n' immutable_diagnostic_hash raw_openssl_executable adapter_regular \
        adapter_executable adapter_state_contract adapter_cleanup_contract
}
adapter_state_contract() {
    grep -Fq 'inside_certificate = 1' "$0" || return 1
    grep -Fq 'inside_certificate = 0' "$0" || return 1
    grep -Fq 'if (inside_certificate || malformed || certificate_count == 0)' "$0" || return 1
    # This pattern intentionally matches literal adapter source.
    # shellcheck disable=SC2016
    grep -Fq 'cat "$adapter_metadata" "$adapter_certificates"' "$0"
}
adapter_cleanup_contract() {
    grep -Fq 'trap adapter_cleanup EXIT INT TERM' "$0" || return 1
    # This pattern intentionally matches literal adapter source.
    # shellcheck disable=SC2016
    grep -Fq 'rm -rf -- "$adapter_root"' "$0"
}
create_adapter() {
    local action27_retry_a_retry_adapter=$1

    cat >"$action27_retry_a_retry_adapter" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH
readonly raw_openssl_bin=${CADDY_ACTION27_RETRY_A_RETRY_RAW_OPENSSL_BIN:-/usr/bin/openssl}
adapter_root=
adapter_cleanup() {
    local adapter_status=$?

    trap - EXIT INT TERM
    [[ -z "$adapter_root" ]] || rm -rf -- "$adapter_root"
    exit "$adapter_status"
}
if [[ "${1:-}" = s_client ]]; then
    adapter_root=$(mktemp -d /tmp/caddy-action27-cert-adapter.XXXXXX)
    trap adapter_cleanup EXIT INT TERM
    adapter_raw=$adapter_root/raw
    adapter_metadata=$adapter_root/metadata
    adapter_certificates=$adapter_root/certificates
    adapter_count=$adapter_root/count
    adapter_status=0
    "$raw_openssl_bin" "$@" >"$adapter_raw" 2>&1 || adapter_status=$?
    awk -v metadata="$adapter_metadata" -v certificates="$adapter_certificates" \
        -v count_file="$adapter_count" '
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
        END {
            if (inside_certificate || malformed || certificate_count == 0) exit 65
            print certificate_count > count_file
        }
    ' "$adapter_raw" || exit 65
    [[ -s "$adapter_metadata" && -s "$adapter_certificates" && -s "$adapter_count" ]] || exit 65
    cat "$adapter_metadata" "$adapter_certificates"
    exit "$adapter_status"
fi
exec "$raw_openssl_bin" "$@"
EOF
    chmod 0700 "$action27_retry_a_retry_adapter"
}
cleanup() {
    local action27_retry_a_retry_status=$?

    trap - EXIT INT TERM
    [[ -z "$action27_retry_a_retry_root" ]] || rm -rf -- "$action27_retry_a_retry_root"
    exit "$action27_retry_a_retry_status"
}
run_action() {
    local action27_retry_a_retry_adapter

    action27_retry_a_retry_root=$(mktemp -d /tmp/caddy-action27-retry-a-retry.XXXXXX)
    trap cleanup EXIT INT TERM
    action27_retry_a_retry_adapter=$action27_retry_a_retry_root/openssl-certificate-state-adapter
    check immutable_diagnostic_hash test "$(file_hash "$immutable_diagnostic")" = \
        "$immutable_diagnostic_sha256" || return 1
    check raw_openssl_executable test -x "$raw_openssl_bin" || return 1
    create_adapter "$action27_retry_a_retry_adapter" || return 1
    check adapter_regular test -f "$action27_retry_a_retry_adapter" || return 1
    check adapter_executable test -x "$action27_retry_a_retry_adapter" || return 1
    check adapter_state_contract adapter_state_contract || return 1
    check adapter_cleanup_contract adapter_cleanup_contract || return 1
    printf '%s_extraction_scope=explicit_begin_end_certificate_state\n' "$prefix"
    CADDY_ACTION27_RETRY_A_OPENSSL_BIN=$action27_retry_a_retry_adapter \
        /bin/bash "$immutable_diagnostic"
}

case "${1:-}" in
    --expected-checks) expected_checks ;;
    --expected-diagnostic-checks) /bin/bash "$immutable_diagnostic" --expected-checks ;;
    "") run_action ;;
    *) exit 64 ;;
esac
